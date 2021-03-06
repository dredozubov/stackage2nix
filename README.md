# stackage2nix

[![Build Status](https://travis-ci.org/4e6/stackage2nix.svg?branch=master)](https://travis-ci.org/4e6/stackage2nix)

`stackage2nix` converts a Stack file into a Nix Haskell packages set.
It creates LTS Stackage packages set, and applies appropriate overrides on top of it.

```
stackage2nix \
  --lts-haskell "$LTS_HASKELL_REPO" \
  --all-cabal-hashes "$ALL_CABAL_HASHES_REPO" \
  .
```

`stackage2nix` has three required arguments:
- `--lts-haskell` - path to [fpco/lts-haskell](https://github.com/fpco/lts-haskell)
- `--all-cabal-hashes` - path to [commercialhaskell/all-cabal-hashes](https://github.com/commercialhaskell/all-cabal-hashes) checked out to `hackage` branch
- `.` - path to stack.yaml file or directory

Produced Nix derivation split on following files:
- packages.nix - Base Stackage packages set
- configuration-packages.nix - Compiler configuration
- default.nix - Final Haskell packages set with all overrides applied

A particular package from result Haskell packages set can be built with:

```
nix-build -A <package-name>
```

## Runtime dependencies

- `nix-env` is required to be on PATH by the
  [distribution-nixpkgs](https://hackage.haskell.org/package/distribution-nixpkgs)
  dependency
- `nix-prefetch-git` is required on PATH if you have git dependencies in
  `stack.yaml`

## Override result derivation

Complex projects may require some extra customization.
Snippet `override.nix` below shows a minimal example of how to apply additional
overrides on top of Haskell packages set produced by `stackage2nix`.

```
with import <nixpkgs> {};
with pkgs.haskell.lib;
let haskellPackages = import ./. {};
in haskellPackages.override {
  overrides = self: super: {
    stackage2nix = disableSharedExecutables super.stackage2nix;
  };
}
```

```
nix-build -A stackage2nix override.nix
```

For more complex overrides and detailed information on how to work with Haskell packages in Nix, see Nixpkgs manual [User’s Guide to the Haskell Infrastructure](http://nixos.org/nixpkgs/manual/#users-guide-to-the-haskell-infrastructure)


## Examples

For other examples of `stackage2nix` usage, see [4e6/stackage2nix-examples](https://github.com/4e6/stackage2nix-examples) repository.
It verifies `stackage2nix` by running it on different public projects.
