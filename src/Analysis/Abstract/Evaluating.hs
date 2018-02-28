{-# LANGUAGE ConstraintKinds, DataKinds, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators, MultiParamTypeClasses #-}
module Analysis.Abstract.Evaluating where

import Control.Effect
import Control.Monad.Effect.Addressable
import Control.Monad.Effect.Evaluatable
import Control.Monad.Effect.Fail
import Control.Monad.Effect.Reader
import Control.Monad.Effect.State
import Data.Abstract.Address
import Data.Abstract.Linker
import Data.Abstract.Store
import Data.Abstract.Value
import Data.Abstract.FreeVariables
import Data.Algebra
import Data.Bifunctor
import Data.Blob
import Data.Functor.Foldable (Base, Recursive(..))
import Data.Foldable (toList)
import Data.Semigroup
import Prelude hiding (fail)
import qualified Data.Map as Map
import System.FilePath.Posix

import qualified Data.ByteString.Char8 as BC

-- | The effects necessary for concrete interpretation.
type Evaluating t v
  = '[ Fail
     , State (Store (LocationFor v) v)
     , State (EnvironmentFor v)      -- Global (imperative) environment
     , Reader (EnvironmentFor v)     -- Local environment (e.g. binding over a closure)
     , Reader (Linker t) -- Cache of unevaluated modules
     , State (Linker v)              -- Cache of evaluated modules
     ]

-- | Require/import another term/file and return an Effect.
--
-- Looks up the term's name in the cache of evaluated modules first, returns a value if found, otherwise loads/evaluates the module.
require :: ( AbstractFunction effects term v
           , Addressable (LocationFor v) effects
           , Evaluatable effects (Base term)
           , FreeVariables term
           , Recursive term
           , Semigroup (Cell (LocationFor v) v)
           )
        => term
        -> Evaluator effects term v v
require term = getModuleTable >>= maybe (load term) pure . linkerLookup name
  where name = moduleName term

-- | Load another term/file and return an Effect.
--
-- Always loads/evaluates.
load :: ( AbstractFunction effects term v
        , Addressable (LocationFor v) effects
        , Evaluatable effects (Base term)
        , FreeVariables term
        , Recursive term
        , Semigroup (Cell (LocationFor v) v)
        )
     => term
     -> Evaluator effects term v v
load term = askModuleTable >>= maybe notFound evalAndCache . linkerLookup name
  where name = moduleName term
        notFound = fail ("cannot find " <> show name)
        evalAndCache e = do
          v <- foldSubterms eval e
          modifyModuleTable (linkerInsert name v)
          pure v

-- | Get a module name from a term (expects single free variables).
moduleName :: FreeVariables term => term -> Prelude.String
moduleName term = let [n] = toList (freeVariables term) in BC.unpack n


-- | Evaluate a term to a value.
evaluate :: forall v term.
         ( Ord v
         , Ord (LocationFor v)
         , AbstractFunction (Evaluating term v) term v
         , Addressable (LocationFor v) (Evaluating term v)
         , Evaluatable (Evaluating term v) (Base term)
         , FreeVariables term
         , Recursive term
         , Semigroup (Cell (LocationFor v) v)
         )
         => term
         -> Final (Evaluating term v) v
evaluate = run @(Evaluating term v) . runEvaluator . foldSubterms eval

-- | Evaluate terms and an entry point to a value.
evaluates :: forall v term.
          ( Ord v
          , Ord (LocationFor v)
          , AbstractFunction (Evaluating term v) term v
          , Addressable (LocationFor v) (Evaluating term v)
          , Evaluatable (Evaluating term v) (Base term)
          , FreeVariables term
          , Recursive term
          , Semigroup (Cell (LocationFor v) v)
          )
          => [(Blob, term)] -- List of (blob, term) pairs that make up the program to be evaluated
          -> (Blob, term)   -- Entrypoint
          -> Final (Evaluating term v) v
evaluates pairs (_, t) = run @(Evaluating term v) (runEvaluator (localModuleTable (const (Linker (Map.fromList (map (first (dropExtensions . blobPath)) pairs)))) (foldSubterms eval t)))
