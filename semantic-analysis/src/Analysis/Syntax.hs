module Analysis.Syntax
( Syntax(..)
  -- * Pretty-printing
, Print(..)
) where

import Data.Text (Text)

class Syntax rep where
  iff :: rep -> rep -> rep -> rep
  noop :: rep

  bool :: Bool -> rep
  string :: Text -> rep

  throw :: rep -> rep


-- Pretty-printing

newtype Print = Print { print_ :: ShowS }

instance Show Print where
  showsPrec _ = print_

instance Semigroup Print where
  Print a <> Print b = Print (a . b)

instance Monoid Print where
  mempty = Print id

str :: String -> Print
str = Print . showString

char :: Char -> Print
char = Print . showChar

parens :: Print -> Print
parens p = char '(' <> p <> char ')'

(<+>) :: Print -> Print -> Print
l <+> r = l <> char ' ' <> r

infixr 6 <+>