{-# LANGUAGE OverloadedStrings #-}
module Tags.Spec (spec) where

import qualified Analysis.File as File
import           Control.Carrier.Reader
import           Semantic.Api.Symbols
import           Source.Loc
import           SpecHelpers
import qualified System.Path as Path
import           Tags.Tagging as Tags

spec :: Spec
spec = do
  describe "go" $ do
    it "produces tags for functions with docs (TODO)" $
      parseTestFile [Function] (Path.relFile "test/fixtures/go/tags/simple_functions.go") `shouldReturn`
        [ Tag "TestFromBits" Function (Loc (Range 56 68) (Span (Pos 6 6) (Pos 6 18))) "func TestFromBits(t *testing.T) {" Nothing
        , Tag "Hi" Function (Loc (Range 99 101) (Span (Pos 10 6) (Pos 10 8))) "func Hi() {" Nothing ]

    it "produces tags for methods" $
      parseTestFile [Method] (Path.relFile "test/fixtures/go/tags/method.go") `shouldReturn`
        [ Tag "CheckAuth" Method (Loc (Range 39 48) (Span (Pos 3 21) (Pos 3 30))) "func (c *apiClient) CheckAuth(req *http.Request, user, repo string) (*authenticatedActor, error) {}" Nothing]

    it "produces tags for calls" $
      parseTestFile [Call] (Path.relFile "test/fixtures/go/tags/simple_functions.go") `shouldReturn`
        [ Tag "Hi" Call (Loc (Range 86 88) (Span (Pos 7 2) (Pos 7 4))) "Hi()" Nothing]

  describe "javascript and typescript" $ do
    it "produces tags for functions with docs (TODO)" $
      parseTestFile [Function] (Path.relFile "test/fixtures/javascript/tags/simple_function_with_docs.js") `shouldReturn`
        [ Tag "myFunction" Function (Loc (Range 31 41) (Span (Pos 2 10) (Pos 2 20))) "function myFunction() {" Nothing ]

    it "produces tags for classes" $
      parseTestFile [Class] (Path.relFile "test/fixtures/typescript/tags/class.ts") `shouldReturn`
        [ Tag "FooBar" Class (Loc (Range 6 12) (Span (Pos 1 7) (Pos 1 13))) "class FooBar {}" Nothing ]

    it "produces tags for modules" $
      parseTestFile [Tags.Module] (Path.relFile "test/fixtures/typescript/tags/module.ts") `shouldReturn`
        [ Tag "APromise" Tags.Module (Loc (Range 7 15) (Span (Pos 1 8) (Pos 1 16))) "module APromise { }" Nothing ]

  describe "python" $ do
    it "produces tags for functions" $
      parseTestFile [Function] (Path.relFile "test/fixtures/python/tags/simple_functions.py") `shouldReturn`
        [ Tag "Foo" Function (Loc (Range 4 7) (Span (Pos 1 5) (Pos 1 8))) "def Foo(x):" Nothing
        , Tag "Bar" Function (Loc (Range 74 77) (Span (Pos 7 5) (Pos 7 8))) "def Bar():" Nothing
        , Tag "local" Function (Loc (Range 89 94) (Span (Pos 8 9) (Pos 8 14))) "def local():" Nothing
        ]

    it "produces tags for functions with docs" $
      parseTestFile [Function] (Path.relFile "test/fixtures/python/tags/simple_function_with_docs.py") `shouldReturn`
        [ Tag "Foo" Function (Loc (Range 4 7) (Span (Pos 1 5) (Pos 1 8))) "def Foo(x):" (Just "\"\"\"This is the foo function\"\"\"") ]

    it "produces tags for classes" $
      parseTestFile [Class, Function] (Path.relFile "test/fixtures/python/tags/class.py") `shouldReturn`
        [ Tag "Foo" Class (Loc (Range 6 9) (Span (Pos 1 7) (Pos 1 10))) "class Foo:" (Just "\"\"\"The Foo class\"\"\"")
        , Tag "f" Function (Loc (Range 43 44) (Span (Pos 3 9) (Pos 3 10))) "def f(self):" (Just "\"\"\"The f method\"\"\"")
        ]

    it "produces tags for multi-line functions" $
      parseTestFile [Function] (Path.relFile "test/fixtures/python/tags/multiline.py") `shouldReturn`
        [ Tag "Foo" Function (Loc (Range 4 7) (Span (Pos 1 5) (Pos 1 8))) "def Foo(x," Nothing ]

  describe "ruby" $ do
    it "produces tags for methods" $
      parseTestFile [Method] (Path.relFile "test/fixtures/ruby/tags/simple_method.rb") `shouldReturn`
        [ Tag "foo" Method (Loc (Range 4 7) (Span (Pos 1 5) (Pos 1 8))) "def foo" Nothing ]

    it "produces tags for sends" $
      parseTestFile [Call] (Path.relFile "test/fixtures/ruby/tags/simple_method.rb") `shouldReturn`
        [ Tag "puts" Call (Loc (Range 10 14) (Span (Pos 2 3) (Pos 2 7))) "puts \"hi\"" Nothing
        , Tag "bar" Call (Loc (Range 24 27) (Span (Pos 3 5) (Pos 3 8))) "a.bar" Nothing
        , Tag "a" Call (Loc (Range 22 23) (Span (Pos 3 3) (Pos 3 4))) "a" Nothing
        ]

    it "produces tags for methods with docs (TODO)" $
      parseTestFile [Method] (Path.relFile "test/fixtures/ruby/tags/simple_method_with_docs.rb") `shouldReturn`
        [ Tag "foo" Method (Loc (Range 18 21) (Span (Pos 2 5) (Pos 2 8))) "def foo" Nothing ]

    it "correctly tags files containing multibyte UTF-8 characters (TODO)" $
      parseTestFile [Method] (Path.relFile "test/fixtures/ruby/tags/unicode_identifiers.rb") `shouldReturn`
        [ Tag "日本語" Method (Loc (Range 20 29) (Span (Pos 2 5) (Pos 2 14))) "def 日本語" Nothing]

    it "produces tags for methods and classes with docs (TODO)" $
      parseTestFile [Class, Method, Tags.Module] (Path.relFile "test/fixtures/ruby/tags/class_module.rb") `shouldReturn`
        [ Tag "Foo" Tags.Module (Loc (Range 21 24) (Span (Pos 2 8) (Pos 2 11))) "module Foo" Nothing
        , Tag "Bar" Class  (Loc (Range 50 53) (Span (Pos 5 9) (Pos 5 12))) "class Bar" Nothing
        , Tag "baz" Method (Loc (Range 81 84) (Span (Pos 8 9) (Pos 8 12))) "def baz(a)" Nothing
        , Tag "C" Class (Loc (Range 132 133) (Span (Pos 14 13) (Pos 14 14))) "class A::B::C" Nothing
        , Tag "foo" Method (Loc (Range 140 143) (Span (Pos 15 7) (Pos 15 10))) "def foo" Nothing
        , Tag "foo" Method (Loc (Range 175 178) (Span (Pos 18 12) (Pos 18 15))) "def self.foo" Nothing
        ]

parseTestFile :: Foldable t => t Tags.Kind -> Path.RelFile -> IO [Tag]
parseTestFile include path = runTaskOrDie $ readBlob (File.fromPath path) >>= runReader defaultLanguageModes . fmap (filter ((`elem` include) . kind)) . tagsForBlob
