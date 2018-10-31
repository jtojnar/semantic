{-# LANGUAGE GADTs, Rank2Types, ScopedTypeVariables #-}
module Control.Abstract.Value
( AbstractValue(..)
, AbstractIntro(..)
, Comparator(..)
-- * Value effects
-- $valueEffects
, function
, call
, Function(..)
, boolean
, asBool
, ifthenelse
, disjunction
, Boolean(..)
, while
, doWhile
, forLoop
, makeNamespace
-- , address
, value
, rvalBox
, subtermValue
-- , subtermAddress
) where

import Control.Abstract.ScopeGraph (Declaration, ScopeGraph, ScopeError)
import Control.Abstract.Environment
import Control.Abstract.Evaluator
import Control.Abstract.Heap hiding (address)
import Control.Abstract.ScopeGraph (Allocator, currentScope, newScope, EdgeLabel(..), )
import qualified Control.Abstract.Heap as Heap
import Data.Abstract.Environment as Env
import Data.Abstract.BaseError
import Data.Abstract.Module
import Data.Abstract.Name
import Data.Abstract.Number as Number
import Data.Abstract.Ref
import Data.Scientific (Scientific)
import Data.Span
import Prologue hiding (TypeError)
import qualified Data.Map.Strict as Map

-- | This datum is passed into liftComparison to handle the fact that Ruby and PHP
--   have built-in generalized-comparison ("spaceship") operators. If you want to
--   encapsulate a traditional, boolean-returning operator, wrap it in 'Concrete';
--   if you want the generalized comparator, pass in 'Generalized'. In 'AbstractValue'
--   instances, you can then then handle the different cases to return different
--   types, if that's what you need.
data Comparator
  = Concrete (forall a . Ord a => a -> a -> Bool)
  | Generalized

-- Value effects

-- $valueEffects
-- Value effects are effects modelling the /introduction/ & /elimination/ of some specific kind of value.
--
-- Modelling each of these as effects has several advantages∷
--
-- * It is strictly more flexible than modelling them as methods in a typeclass, as effect list–indexed typeclasses must be constrained at every list of effects at which they can be applied, whereas effect membership constraints can be deduced recursively (i.e. if @X@ is constrained to be a member of @effects@, it is automatically deducible that it is also a member of @Y \': effects@).
-- * It offers us the potential of specializing the handlers on a language-by-language basis without the need for extra type parameters (albeit at the cost of automatic selection).
-- * It offers us the potential of fine-grained specialization of the abstract domain, enabling convenient, piecemeal customization of the domain, and even semi-abstract domains.
-- * Finally, it should eventually allow us to customize _which_ value effects are available for a given language; e.g. a language without OO features would not require OO value effects. (This would also rely on 'Evaluatable' instances being able to specify membership constraints, which is not currently possible.)
--
-- In the concrete domain, introductions & eliminations respectively construct & pattern match against values, while in abstract domains they respectively construct & project finite sets of discrete observations of abstract values. For example, an abstract domain modelling integers as a sign (-, 0, or +) would introduce abstract values by mapping integers to their sign and eliminate them by mapping signs back to some canonical integer, e.g. - -> -1, 0 -> 0, + -> 1.

function :: forall address value effects. Member (Function address value) effects => Name -> [Name] -> Set Name -> Evaluator address value effects value -> Evaluator address value effects value
function name params fvs (Evaluator body) = send @(Function address value) (Function name params fvs body)

call :: Member (Function address value) effects => value -> address -> [value] -> Evaluator address value effects value
call fn self args = send (Call fn self args)

data Function address value m result where
  Function :: Name -> [Name] -> Set Name -> m value -> Function address value m value
  Call     :: value -> address -> [value]   -> Function address value m value

instance PureEffect (Function address value) where
  handle handler (Request (Function name params fvs body) k) = Request (Function name params fvs (handler body)) (handler . k)
  handle handler (Request (Call fn self addrs)            k) = Request (Call fn self addrs)                      (handler . k)

-- | Construct a boolean value in the abstract domain.
boolean :: Member (Boolean value) effects => Bool -> Evaluator address value effects value
boolean = send . Boolean

-- | Extract a 'Bool' from a given value.
asBool :: Member (Boolean value) effects => value -> Evaluator address value effects Bool
asBool = send . AsBool

-- | Eliminate boolean values. TODO: s/boolean/truthy
ifthenelse :: Member (Boolean value) effects => value -> Evaluator address value effects a -> Evaluator address value effects a -> Evaluator address value effects a
ifthenelse v t e = asBool v >>= \ c -> if c then t else e

-- | Compute the disjunction (boolean or) of two computed values. This should have short-circuiting semantics where applicable.
disjunction :: Member (Boolean value) effects => Evaluator address value effects value -> Evaluator address value effects value -> Evaluator address value effects value
disjunction (Evaluator a) (Evaluator b) = send (Disjunction a b)

data Boolean value m result where
  Boolean     :: Bool  -> Boolean value m value
  AsBool      :: value -> Boolean value m Bool
  Disjunction :: m value -> m value -> Boolean value m value

instance PureEffect (Boolean value) where
  handle handler (Request (Boolean b)        k) = Request (Boolean b) (handler . k)
  handle handler (Request (AsBool v)         k) = Request (AsBool v)  (handler . k)
  handle handler (Request (Disjunction a b)  k) = Request (Disjunction (handler a) (handler b))  (handler . k)


class Show value => AbstractIntro value where
  -- | Construct an abstract unit value.
  --   TODO: This might be the same as the empty tuple for some value types
  unit :: value

  -- | Construct an abstract string value.
  string :: Text -> value

  -- | Construct a self-evaluating symbol value.
  --   TODO: Should these be interned in some table to provide stronger uniqueness guarantees?
  symbol :: Text -> value

  -- | Construct an abstract regex value.
  regex :: Text -> value

  -- | Construct an abstract integral value.
  integer :: Integer -> value

  -- | Construct a floating-point value.
  float :: Scientific -> value

  -- | Construct a rational value.
  rational :: Rational -> value

  -- | Construct a key-value pair for use in a hash.
  kvPair :: value -> value -> value

  -- | Construct a hash out of pairs.
  hash :: [(value, value)] -> value

  -- | Construct the nil/null datatype.
  null :: value

-- | A 'Monad' abstracting the evaluation of (and under) binding constructs (functions, methods, etc).
--
--   This allows us to abstract the choice of whether to evaluate under binders for different value types.
class AbstractIntro value => AbstractValue address value effects where
  -- | Cast numbers to integers
  castToInteger :: value -> Evaluator address value effects value


  -- | Lift a unary operator over a 'Num' to a function on 'value's.
  liftNumeric  :: (forall a . Num a => a -> a)
               -> (value -> Evaluator address value effects value)

  -- | Lift a pair of binary operators to a function on 'value's.
  --   You usually pass the same operator as both arguments, except in the cases where
  --   Haskell provides different functions for integral and fractional operations, such
  --   as division, exponentiation, and modulus.
  liftNumeric2 :: (forall a b. Number a -> Number b -> SomeNumber)
               -> (value -> value -> Evaluator address value effects value)

  -- | Lift a Comparator (usually wrapping a function like == or <=) to a function on values.
  liftComparison :: Comparator -> (value -> value -> Evaluator address value effects value)

  -- | Lift a unary bitwise operator to values. This is usually 'complement'.
  liftBitwise :: (forall a . Bits a => a -> a)
              -> (value -> Evaluator address value effects value)

  -- | Lift a binary bitwise operator to values. The Integral constraint is
  --   necessary to satisfy implementation details of Haskell left/right shift,
  --   but it's fine, since these are only ever operating on integral values.
  liftBitwise2 :: (forall a . (Integral a, Bits a) => a -> a -> a)
               -> (value -> value -> Evaluator address value effects value)

  unsignedRShift :: value -> value -> Evaluator address value effects value

  -- | Construct an N-ary tuple of multiple (possibly-disjoint) values
  tuple :: [value] -> Evaluator address value effects value

  -- | Construct an array of zero or more values.
  array :: [value] -> Evaluator address value effects value

  asArray :: value -> Evaluator address value effects [value]

  -- | Extract the contents of a key-value pair as a tuple.
  asPair :: value -> Evaluator address value effects (value, value)

  -- | Extract a 'Text' from a given value.
  asString :: value -> Evaluator address value effects Text

  -- | @index x i@ computes @x[i]@, with zero-indexing.
  index :: value -> value -> Evaluator address value effects value

  -- | Build a class value from a name and environment.
  klass :: Declaration      -- ^ The new class's identifier
        -> [value]          -- ^ A list of superclasses
        -> address          -- ^ The frame address to capture
        -> Evaluator address value effects value

  -- | Build a namespace value from a name and environment stack
  --
  -- Namespaces model closures with monoidal environments.
  namespace :: Declaration          -- ^ The namespace's declaration
            -> Maybe value          -- The ancestor of the namespace
            -> address              -- ^ The frame address to capture
            -> Evaluator address value effects value

  -- | Extract the environment from any scoped object (e.g. classes, namespaces, etc).
  scopedEnvironment :: address -> Evaluator address value effects (Maybe (Environment address))

  -- | Primitive looping combinator, approximately equivalent to 'fix'. This should be used in place of direct recursion, as it allows abstraction over recursion.
  --
  --   The function argument takes an action which recurs through the loop.
  loop :: (Evaluator address value effects value -> Evaluator address value effects value) -> Evaluator address value effects value


-- | C-style for loops.
forLoop :: ( AbstractValue address value effects
           , Member (Boolean value) effects
           , Member (Reader ModuleInfo) effects
           , Member (State (Heap address address value)) effects
           , Ord address
           , Member (Reader Span) effects
           , Member (Resumable (BaseError (HeapError address))) effects
           , Member (Allocator address) effects
           , Member (Resumable (BaseError (ScopeError address))) effects
           , Member Fresh effects
           , Member (State (ScopeGraph address)) effects
           )
        => Evaluator address value effects value -- ^ Initial statement
        -> Evaluator address value effects value -- ^ Condition
        -> Evaluator address value effects value -- ^ Increment/stepper
        -> Evaluator address value effects value -- ^ Body
        -> Evaluator address value effects value
forLoop initial cond step body = initial *> while cond (action *> step)
  where
    action = do
      currentScope' <- currentScope
      currentFrame' <- currentFrame
      scopeAddr <- newScope (Map.singleton Lexical [ currentScope' ])
      frame <- newFrame scopeAddr (Map.singleton Lexical (Map.singleton currentScope' currentFrame'))
      withScopeAndFrame frame body

-- | The fundamental looping primitive, built on top of 'ifthenelse'.
while :: (AbstractValue address value effects, Member (Boolean value) effects)
      => Evaluator address value effects value
      -> Evaluator address value effects value
      -> Evaluator address value effects value
while cond body = loop $ \ continue -> do
  this <- cond
  ifthenelse this (body *> continue) (pure unit)

-- | Do-while loop, built on top of while.
doWhile :: (AbstractValue address value effects, Member (Boolean value) effects)
        => Evaluator address value effects value
        -> Evaluator address value effects value
        -> Evaluator address value effects value
doWhile body cond = loop $ \ continue -> body *> do
  this <- cond
  ifthenelse this continue (pure unit)

-- TODO rethink whether this function is necessary.
makeNamespace :: ( AbstractValue address value effects
                 , Member (Deref value) effects
                 , Member (Reader ModuleInfo) effects
                 , Member (State (ScopeGraph address)) effects
                 , Member (Allocator address) effects
                 , Member (Reader Span) effects
                 , Member (Resumable (BaseError (HeapError address))) effects
                 , Member (Resumable (BaseError (AddressError address value))) effects
                 , Member (Allocator address) effects
                 , Member (Resumable (BaseError (ScopeError address))) effects
                 , Member (State (Heap address address value)) effects
                 , Member Fresh effects
                 , Ord address
                 )
              => Declaration
              -> Address address
              -> Maybe (Address address)
              -> Evaluator address value effects ()
              -> Evaluator address value effects value
makeNamespace declaration addr super body = do
  super' <- traverse deref super
  define declaration . withChildFrame declaration $ \frame -> do
      _ <- body
      namespace declaration super' frame


-- | Evaluate a term within the context of the scoped environment of 'scopedEnvTerm'.
-- evaluateInScopedEnv :: ( AbstractValue address value effects
--                        )
--                     => address
--                     -> Evaluator address value effects a
--                     -> Evaluator address value effects a
-- evaluateInScopedEnv receiver term = do
--   scopedEnv <- scopedEnvironment receiver
--   env <- maybeM getEnv scopedEnv
--   withEvalContext (EvalContext (Just receiver) env) term


-- | Evaluates a 'Value' returning the referenced value
value :: ( AbstractValue address value effects
         , Member (Deref value) effects
         , Member (Reader ModuleInfo) effects
         , Member (Reader Span) effects
         , Member (Resumable (BaseError (AddressError address value))) effects
         , Member (State (Heap address address value)) effects
         , Ord address
         )
      => ValueRef address value
      -> Evaluator address value effects value
value (Rval val) = pure val
value (LvalLocal name) = undefined
value (LvalMember slot) = undefined

-- | Evaluates a 'Subterm' to its rval
subtermValue :: ( AbstractValue address value effects
                , Member (Deref value) effects
                , Member (Reader ModuleInfo) effects
                , Member (Reader Span) effects
                , Member (Resumable (BaseError (AddressError address value))) effects
                , Member (State (Heap address address value)) effects
                , Ord address
                )
             => Subterm term (Evaluator address value effects (ValueRef address value))
             -> Evaluator address value effects value
subtermValue = value <=< subtermRef

-- | Returns the address of a value referenced by a 'ValueRef'
-- address :: ( AbstractValue address value effects
--            , Member (Env address) effects
--            , Member (Reader ModuleInfo) effects
--            , Member (Reader Span) effects
--            , Member (Resumable (BaseError (EnvironmentError address))) effects
--            )
--         => ValueRef address
--         -> Evaluator address value effects address
-- address (LvalLocal var)       = variable var
-- address (LvalMember ptr prop) = evaluateInScopedEnv ptr (variable prop)
-- address (Rval addr)           = pure addr

-- | Evaluates a 'Subterm' to the address of its rval
-- subtermAddress :: ( AbstractValue address value effects
--                   , Member (Env address) effects
--                   , Member (Reader ModuleInfo) effects
--                   , Member (Reader Span) effects
--                   , Member (Resumable (BaseError (EnvironmentError address))) effects
--                   )
--                => Subterm term (Evaluator address value effects (ValueRef address value))
--                -> Evaluator address value effects address
-- subtermAddress = address <=< subtermRef

-- | Convenience function for boxing a raw value and wrapping it in an Rval
rvalBox :: ( Member (Allocator address) effects
           , Member (Deref value) effects
           , Member Fresh effects
           , Member (State (Heap address address value)) effects
           , Ord address
           )
        => value
        -> Evaluator address value effects (ValueRef address value)
rvalBox val = pure (Rval val)
