-- | Semantic functionality for CodeQL programs.
module Language.CodeQL
( Term(..)
, TreeSitter.QL.tree_sitter_ql
) where

import qualified AST.Unmarshal as TS
import           Data.Proxy
import qualified Language.CodeQL.AST as CodeQL
import qualified Language.CodeQL.Tags as CodeQLTags
import           Scope.Graph.Convert
import qualified Tags.Tagging.Precise as Tags
import qualified TreeSitter.QL (tree_sitter_ql)

newtype Term a = Term { getTerm :: CodeQL.Ql a }

instance TS.SymbolMatching Term where
  matchedSymbols _ = TS.matchedSymbols (Proxy :: Proxy CodeQL.Ql)
  showFailure _ = TS.showFailure (Proxy :: Proxy CodeQL.Ql)

instance TS.Unmarshal Term where
  matchers = fmap (fmap (TS.hoist Term)) TS.matchers

instance Tags.ToTags Term where
  tags src = Tags.runTagging src . CodeQLTags.tags . getTerm

instance ToScopeGraph Term where
  scopeGraph = undefined
