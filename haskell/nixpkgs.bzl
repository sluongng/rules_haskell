"""Workspace rules (Nixpkgs)"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
    "nixpkgs_package",
)

def haskell_nixpkgs_package(
        name,
        attribute_path,
        nix_file_deps = [],
        repositories = {},
        build_file_content = None,
        build_file = None,
        **kwargs):
    """Load a single haskell package.
    The package is expected to be in the form of the packages generated by
    `genBazelBuild.nix`
    """
    repositories = dicts.add(
        {"bazel_haskell_wrapper": "@io_tweag_rules_haskell//haskell:nix/default.nix"},
        repositories,
    )

    nixpkgs_args = dict(
        name = name,
        attribute_path = attribute_path,
        build_file_content = build_file_content,
        nix_file_deps = nix_file_deps + ["@io_tweag_rules_haskell//haskell:nix/default.nix"],
        repositories = repositories,
        **kwargs
    )

    if build_file_content:
        nixpkgs_args["build_file_content"] = build_file_content
    elif build_file:
        nixpkgs_args["build_file"] = build_file
    else:
        nixpkgs_args["build_file_content"] = """
package(default_visibility = ["//visibility:public"])
load("@io_tweag_rules_haskell//haskell:import.bzl", haskell_import_new = "haskell_import")

load(":BUILD.bzl", "targets")
targets()
"""

    nixpkgs_package(
        **nixpkgs_args
    )

def _bundle_impl(repository_ctx):
    build_file_content = """
package(default_visibility = ["//visibility:public"])
    """
    for package in repository_ctx.attr.packages:
        build_file_content += """
alias(
    name = "{package}",
    actual = "@{base_repo}-{package}//:pkg",
)
        """.format(
            package = package,
            base_repo = repository_ctx.attr.base_repository,
        )
    repository_ctx.file("BUILD", build_file_content)

_bundle = repository_rule(
    attrs = {
        "packages": attr.string_list(),
        "base_repository": attr.string(),
    },
    implementation = _bundle_impl,
)
"""
Generate an alias from `@base_repo//:package` to `@base_repo-package//:pkg` for
each one of the input package
"""

def haskell_nixpkgs_packages(name, base_attribute_path, packages, **kwargs):
    """Import a set of haskell packages from nixpkgs.

    This takes as input the same arguments as
    [nixpkgs_package](https://github.com/tweag/rules_nixpkgs#nixpkgs_package),
    expecting the `attribute_path` to resolve to a set of haskell packages
    (such as `haskellPackages` or `haskell.packages.ghc822`) preprocessed by
    the `genBazelBuild` function. It also takes as input a list of packages to
    import (which can be generated by the `gen_packages_list` function).
   """
    for package in packages:
        haskell_nixpkgs_package(
            name = name + "-" + package,
            attribute_path = base_attribute_path + "." + package,
            **kwargs
        )
    _bundle(
        name = name,
        packages = packages,
        base_repository = name,
    )

def _is_nix_platform(repository_ctx):
    return repository_ctx.which("nix-build") != None

def _gen_imports_impl(repository_ctx):
    repository_ctx.file("BUILD", "")
    extra_args_raw = ""
    for foo, bar in repository_ctx.attr.extra_args.items():
        extra_args_raw += foo + " = " + bar + ", "
    bzl_file_content = """
load("{repo_name}", "packages")
load("@io_tweag_rules_haskell//haskell:nixpkgs.bzl", "haskell_nixpkgs_packages")

def import_packages(name):
    haskell_nixpkgs_packages(
        name = name,
        packages = packages,
        {extra_args_raw}
    )
    """.format(
        repo_name = repository_ctx.attr.packages_list_file,
        extra_args_raw = extra_args_raw,
    )

    # A dummy 'packages.bzl' file with a no-op 'import_packages()' on unsupported platforms
    bzl_file_content_unsupported_platform = """
def import_packages(name):
    return
    """
    if _is_nix_platform(repository_ctx):
        repository_ctx.file("packages.bzl", bzl_file_content)
    else:
        repository_ctx.file("packages.bzl", bzl_file_content_unsupported_platform)

_gen_imports_str = repository_rule(
    implementation = _gen_imports_impl,
    attrs = dict(
        packages_list_file = attr.label(doc = "A list containing the list of packages to import"),
        # We pass the extra arguments to `haskell_nixpkgs_packages` as strings
        # since we can't forward arbitrary arguments in a rule and they will be
        # converted to strings anyways.
        extra_args = attr.string_dict(doc = "Extra arguments for `haskell_nixpkgs_packages`"),
    ),
)
"""
Generate a repository containing a file `packages.bzl` which imports the given
packages list.
"""

def _gen_imports(name, packages_list_file, extra_args):
    """
    A wrapper around `_gen_imports_str` which allows passing an arbitrary set of
    `extra_args` instead of a set of strings
    """
    extra_args_str = {label: repr(value) for (label, value) in extra_args.items()}
    _gen_imports_str(
        name = name,
        packages_list_file = packages_list_file,
        extra_args = extra_args_str,
    )

def haskell_nixpkgs_packageset(name, base_attribute_path, repositories = {}, **kwargs):
    """Import all the available haskell packages.
    The arguments are the same as the arguments of ``nixpkgs_package``, except
    for the ``base_attribute_path`` which should point to an `haskellPackages`
    set in the nix expression

    Example:

      In `haskellPackages.nix`:

      ```nix
      with import <nixpkgs> {};

      let wrapPackages = callPackage <bazel_haskell_wrapper> { }; in
      { haskellPackages = wrapPackages haskell.packages.ghc822; }
      ```

      In your `WORKSPACE`

      ```bazel
      # Define a nix repository to fetch the packages from
      load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
          "nixpkgs_git_repository")
      nixpkgs_git_repository(
          name = "nixpkgs",
          revision = "9a787af6bc75a19ac9f02077ade58ddc248e674a",
      )

      load("@io_tweag_rules_haskell//haskell:nixpkgs.bzl",
          "haskell_nixpkgs_packageset",

      # Generate a list of all the available haskell packages
      haskell_nixpkgs_packageset(
          name = "hackage-packages",
          repositories = {"@nixpkgs": "nixpkgs"},
          nix_file = "//haskellPackages.nix",
          base_attribute_path = "haskellPackages",
      )
      load("@hackage-packages//:packages.bzl", "import_packages")
      import_packages(name = "hackage")
      ```

      Then in your `BUILD` files, you can access to the whole of hackage as
      `@hackage//:{your-package-name}`
    """

    repositories = dicts.add(
        {"bazel_haskell_wrapper": "@io_tweag_rules_haskell//haskell:nix/default.nix"},
        repositories,
    )

    nixpkgs_package(
        name = name + "-packages-list",
        attribute_path = base_attribute_path + ".packageNames",
        repositories = repositories,
        build_file_content = """
exports_files(["all-haskell-packages.bzl"])
        """,
        fail_not_supported = False,
        **kwargs
    )
    _gen_imports(
        name = name,
        packages_list_file = "@" + name + "-packages-list//:all-haskell-packages.bzl",
        extra_args = dict(
            repositories = repositories,
            base_attribute_path = base_attribute_path,
            **kwargs
        ),
    )

def _ghc_nixpkgs_toolchain_impl(repository_ctx):
    # These constraints might look tautological, because they always
    # match the host platform if it is the same as the target
    # platform. But they are important to state because Bazel
    # toolchain resolution prefers other toolchains with more specific
    # constraints otherwise.
    target_constraints = ["@bazel_tools//platforms:x86_64"]
    if repository_ctx.os.name == "linux":
        target_constraints.append("@bazel_tools//platforms:linux")
    elif repository_ctx.os.name == "mac os x":
        target_constraints.append("@bazel_tools//platforms:osx")
    exec_constraints = list(target_constraints)
    exec_constraints.append("@io_tweag_rules_haskell//haskell/platforms:nixpkgs")

    compiler_flags_select = repository_ctx.attr.compiler_flags_select or {"//conditions:default": []}
    locale_archive = repr(repository_ctx.attr.locale_archive or None)

    repository_ctx.file(
        "BUILD",
        executable = False,
        content = """
load("@io_tweag_rules_haskell//haskell:toolchain.bzl", "haskell_toolchain")

haskell_toolchain(
    name = "toolchain",
    tools = ["{tools}"],
    version = "{version}",
    compiler_flags = {compiler_flags} + {compiler_flags_select},
    haddock_flags = {haddock_flags},
    repl_ghci_args = {repl_ghci_args},
    # On Darwin we don't need a locale archive. It's a Linux-specific
    # hack in Nixpkgs.
    locale_archive = {locale_archive},
    exec_compatible_with = {exec_constraints},
    target_compatible_with = {target_constraints},
)
        """.format(
            tools = "@io_tweag_rules_haskell_ghc-nixpkgs//:bin",
            version = repository_ctx.attr.version,
            compiler_flags = repository_ctx.attr.compiler_flags,
            compiler_flags_select = "select({})".format(compiler_flags_select),
            haddock_flags = repository_ctx.attr.haddock_flags,
            repl_ghci_args = repository_ctx.attr.repl_ghci_args,
            locale_archive = locale_archive,
            exec_constraints = exec_constraints,
            target_constraints = target_constraints,
        ),
    )

_ghc_nixpkgs_toolchain = repository_rule(
    _ghc_nixpkgs_toolchain_impl,
    local = False,
    attrs = {
        # These attributes just forward to haskell_toolchain.
        # They are documented there.
        "version": attr.string(),
        "compiler_flags": attr.string_list(),
        "compiler_flags_select": attr.string_list_dict(),
        "haddock_flags": attr.string_list(),
        "repl_ghci_args": attr.string_list(),
        "locale_archive": attr.string(),
    },
)

def haskell_register_ghc_nixpkgs(
        version,
        build_file = None,
        compiler_flags = None,
        compiler_flags_select = None,
        haddock_flags = None,
        repl_ghci_args = None,
        locale_archive = None,
        attribute_path = "haskellPackages.ghc",
        nix_file = None,
        nix_file_deps = [],
        repositories = {}):
    """Register a package from Nixpkgs as a toolchain.

    Toolchains can be used to compile Haskell code. To have this
    toolchain selected during [toolchain
    resolution][toolchain-resolution], set a host platform that
    includes the `@io_tweag_rules_haskell//haskell/platforms:nixpkgs`
    constraint value.

    [toolchain-resolution]: https://docs.bazel.build/versions/master/toolchains.html#toolchain-resolution

    Example:

      ```
      haskell_register_ghc_nixpkgs(
          locale_archive = "@glibc_locales//:locale-archive",
          atttribute_path = "haskellPackages.ghc",
          version = "1.2.3",   # The version of GHC
      )
      ```

      Setting the host platform can be done on the command-line like
      in the following:

      ```
      --host_platform=@io_tweag_rules_haskell//haskell/platforms:linux_x86_64_nixpkgs
      ```

    """
    haskell_nixpkgs_package(
        name = "io_tweag_rules_haskell_ghc-nixpkgs",
        attribute_path = attribute_path,
        build_file = build_file or "@io_tweag_rules_haskell//haskell:ghc.BUILD",
        nix_file = nix_file,
        nix_file_deps = nix_file_deps,
        repositories = repositories,
    )
    _ghc_nixpkgs_toolchain(
        name = "io_tweag_rules_haskell_ghc-nixpkgs-toolchain",
        version = version,
        compiler_flags = compiler_flags,
        compiler_flags_select = compiler_flags_select,
        haddock_flags = haddock_flags,
        repl_ghci_args = repl_ghci_args,
        locale_archive = locale_archive,
    )
    native.register_toolchains("@io_tweag_rules_haskell_ghc-nixpkgs-toolchain//:toolchain")
