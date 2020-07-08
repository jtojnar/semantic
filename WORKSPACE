# This file defines the workspace for the Semantic monorepo.
# It loads the Haskell compilation rules, describes the packages
# that we use from Stackage, and pins the tree-sitter packages
# so that we can access their node-types.json files.

workspace(name = "semantic")

# Load the repository rule to download an http archive.
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# Load the ability to check out a git repository.
load(
    "@bazel_tools//tools/build_defs/repo:git.bzl",
    "git_repository",
    "new_git_repository",
)

# Download rules_haskell and make it accessible as "@rules_haskell".
http_archive(
    name = "rules_haskell",
    sha256 = "56a8e6337df8802f1e0e7d2b3d12d12d5d96c929c8daecccc5738a0f41d9c1e4",
    strip_prefix = "rules_haskell-0.12",
    urls = ["https://github.com/tweag/rules_haskell/archive/v0.12.tar.gz"],
)

load(
    "@rules_haskell//haskell:repositories.bzl",
    "rules_haskell_dependencies",
)

# Setup all Bazel dependencies required by rules_haskell.
rules_haskell_dependencies()

load(
    "@rules_haskell//haskell:toolchain.bzl",
    "rules_haskell_toolchains",
)

git_repository(
    name = "haskell-tree-sitter",
    branch = "master",
    remote = "https://github.com/tree-sitter/haskell-tree-sitter.git",
)

# Download a GHC binary distribution from haskell.org and register it as a toolchain.
rules_haskell_toolchains(version = "8.8.3")

load(
    "@rules_haskell//haskell:cabal.bzl",
    "stack_snapshot",
)

# This call establishes a @stackage repository, and describes what packages
# we use from Stackage. The resolver, as well as the non-Stackage packages
# on which we depend, are specified in stack-snapshot.yaml.
stack_snapshot(
    name = "stackage",
    local_snapshot = "//:stack-snapshot.yaml",
    packages = [
        "Glob",
        "HUnit",
        "QuickCheck",
        "aeson",
        "aeson-pretty",
        "algebraic-graphs",
        "ansi-terminal",
        "async",
        "attoparsec",
        "base",
        "bazel-runfiles",
        "bifunctors",
        "bytestring",
        "containers",
        "deepseq",
        "directory",
        "directory-tree",
        "doctest",
        "filepath",
        "foldl",
        "fused-effects",
        "fused-effects-exceptions",
        "fused-effects-readline",
        "fused-effects-resumable",
        "fused-syntax",
        "gauge",
        "generic-lens",
        "generic-monoid",
        "hashable",
        "haskeline",
        "hedgehog",
        "hostname",
        "hscolour",
        "hspec",
        "hspec-core",
        "hspec-expectations",
        "leancheck",
        "lens",
        "network",
        "network-uri",
        "optparse-applicative",
        "parallel",
        "parsers",
        "pathtype",
        "pretty-show",
        "pretty-simple",
        "prettyprinter",
        "prettyprinter-ansi-terminal",
        "process",
        "proto-lens",
        "proto-lens-jsonpb",
        "proto-lens-runtime",
        "raw-strings-qq",
        "recursion-schemes",
        "reducers",
        "resourcet",
        "safe-exceptions",
        "scientific",
        "semigroupoids",
        "semilattices",
        "split",
        "stm-chans",
        "streaming",
        "tasty",
        "tasty-golden",
        "tasty-hedgehog",
        "tasty-hspec",
        "tasty-hunit",
        "template-haskell",
        "temporary",
        "terminal-size",
        "text",
        "time",
        "transformers",
        "tree-sitter",
        "tree-sitter-json",
        "tree-sitter-ql",
        "tree-sitter-rust",
        "tree-sitter-tsx",
        "trifecta",
        "unix",
        "unliftio-core",
        "unordered-containers",
        "vector",
        "yaml",
    ],
    tools = ["@happy"],
    vendored_packages = {
        "tree-sitter-typescript": "@tree-sitter-typescript//:tree-sitter-typescript",
        "tree-sitter-php": "@tree-sitter-php//:tree-sitter-php",
        "tree-sitter-ruby": "@tree-sitter-ruby//:tree-sitter-ruby",
        "tree-sitter-java": "@tree-sitter-java//:tree-sitter-java",
        "tree-sitter-python": "@tree-sitter-python//:tree-sitter-python",
        "tree-sitter-go": "@tree-sitter-go//:tree-sitter-go",
    },
)

# Download Happy and make it accessible to the build process.
http_archive(
    name = "happy",
    build_file_content = """
load("@rules_haskell//haskell:cabal.bzl", "haskell_cabal_binary")
haskell_cabal_binary(name = "happy", srcs = glob(["**"]), visibility = ["//visibility:public"])
    """,
    sha256 = "fb9a23e41401711a3b288f93cf0a66db9f97da1ce32ec4fffea4b78a0daeb40f",
    strip_prefix = "happy-1.19.12",
    urls = ["http://hackage.haskell.org/package/happy-1.19.12/happy-1.19.12.tar.gz"],
)

# Pin the various tree-sitter packages so that we can access their
# node-types.json files.

load(
    "//:build/common.bzl",
    "tree_sitter_node_types_git",
    "tree_sitter_node_types_hackage",
    "tree_sitter_node_types_release",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-go",
    sha256 = "364a0ae4e683bda1e348fa85c6828cad72122af155560b680f6052852d98db6c",
    version = "0.5.0.1",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-python",
    sha256 = "36aca4989a9f8b52d6af1586e6eecc8c3a8db2b5643f64ef13ab3d284c266522",
    version = "0.9.0.2",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-php",
    sha256 = "d7a050948fcea3b740924520c5d0e00e9b239949eff831527a736c5421c912a3",
    version = "0.5.0.0",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-java",
    sha256 = "9978b56af40c0c66688c17a193761e9c21f7cbbb7e2e299cb7b99f42bd355dfc",
    version = "0.7.0.1",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-json",
    sha256 = "2b16e68afdc8c56bfac81b88dcd495fc8da6ba9df89347249f1785f1077965e5",
    version = "0.7.0.1",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-typescript",
    node_types_path = ":vendor/tree-sitter-typescript/typescript/src/node-types.json",
    sha256 = "19a036ed413c9da66de8fc3826a413c30278d8490603aeb9465caf3707553d19",
    version = "0.5.0.1",
)

# Download lingo (which has its own Bazel build instructions).

git_repository(
    name = "lingo",
    commit = "6614b9afe1a519364491c170d6b06ff5cd96153a",
    remote = "https://github.com/tclem/lingo-haskell.git",
    shallow_since = "1593202797 -0400",
)

# These packages use node_types_git because they correspond to Hackage
# tree-sitter-* parsers vendored not to a release of their C parser,
# but to a given Git SHA. This works, but is a little specious, so we
# should move these into node_types_release calls and fix the problems
# that emerge when we target version releases.

tree_sitter_node_types_hackage(
    name = "tree-sitter-ruby",
    sha256 = "d7e9cb06d37b5ee3be500a7f19ce09b6e846958195eff465d2b03d3218807690",
    version = "0.5.0.2",
)

tree_sitter_node_types_git(
    name = "tree-sitter-ql",
    commit = "c0d674abed8836bb5a4770f547343ef100f88c24",
    shallow_since = "1585868745 -0700",
)

tree_sitter_node_types_hackage(
    name = "tree-sitter-rust",
    sha256 = "",
    version = "0.1.0.0",
)

load("//:build/example_repos.bzl", "declare_example_repos")

declare_example_repos()
