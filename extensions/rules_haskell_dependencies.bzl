""" This module extension contains rules_haskell dependencies that are not available as modules """

load("@rules_haskell//haskell:repositories.bzl", "rules_haskell_dependencies_bzlmod")
load("@rules_haskell//tools:repositories.bzl", "rules_haskell_worker_dependencies")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@rules_haskell//tools:os_info.bzl", "os_info")

def repositories(*, bzlmod):
    rules_haskell_dependencies_bzlmod()

    # Some helpers for platform-dependent configuration
    maybe(
        os_info,
        name = "os_info",
    )

    # For persistent worker (tools/worker)
    # TODO: make this customizable via a module extension so that users
    # of persistant workers can use dependencies compatible with the
    # selected toolchain.
    rules_haskell_worker_dependencies()

    # TODO: Remove when tests are run with a ghc version containing Cabal >= 3.10
    # See https://github.com/tweag/rules_haskell/issues/1871
    http_archive(
        name = "Cabal",
        build_file_content = """
load("@rules_haskell//haskell:cabal.bzl", "haskell_cabal_library")
haskell_cabal_library(
    name = "Cabal",
    srcs = glob(["Cabal/**"]),
    verbose = False,
    version = "3.6.3.0",
    visibility = ["//visibility:public"],
)
""",
        sha256 = "f69b46cb897edab3aa8d5a4bd7b8690b76cd6f0b320521afd01ddd20601d1356",
        strip_prefix = "cabal-gg-8220-with-3630",
        urls = ["https://github.com/tweag/cabal/archive/refs/heads/gg/8220-with-3630.zip"],
    )

def _rules_haskell_dependencies_impl(_mctx):
    repositories(bzlmod = True)

rules_haskell_dependencies = module_extension(
    implementation = _rules_haskell_dependencies_impl,
)
