{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings, GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Distribution.Nixpkgs.Haskell.Stack where

import Control.Lens
import Data.Text as T
import Distribution.System as System
import Distribution.Compiler as Compiler
import Distribution.PackageDescription as PackageDescription
import Distribution.Nixpkgs.Fetch
import Distribution.Nixpkgs.Haskell.Derivation
import Distribution.Nixpkgs.Haskell.FromCabal as FromCabal
import Distribution.Nixpkgs.Haskell.PackageSourceSpec as PackageSourceSpec
import Language.Nix
import Language.Nix.PrettyPrinting
import Stack.Config

data OverrideConfig = OverrideConfig
  { stackageCompilerConfig :: FilePath
  -- ^ Nixpkgs compiler config for Stackage packages set
  , stackagePackagesConfig :: FilePath
  -- ^ Nixpkgs packages config for Stackage packages set
  , haskellPackagesOverride :: Identifier
  -- ^ 'pkgs.haskell.packages.<compiler>' to override
  }

overrideConfigFixture :: OverrideConfig
overrideConfigFixture = OverrideConfig
  { stackageCompilerConfig = "./haskell-modules/configuration-6_30.nix"
  , stackagePackagesConfig = "./haskell-modules/packages-6_30.nix"
  , haskellPackagesOverride = "ghc7103" }

stackageCompilerConfigFun :: FilePath -> Doc
stackageCompilerConfigFun p =
  funargs [text "superPkgs"] $$ "import" <+> string p
  <+> lbrace
  <+> text "inherit (superPkgs) pkgs;"
  <+> rbrace

nixLet :: [Doc] -> Doc
nixLet ls = vcat
  [ text "let"
  , nest 2 $ vcat ls
  ]

nixpkgsOverride :: OverrideConfig -> Doc
nixpkgsOverride OverrideConfig {..} = vcat
  [ text "{ nixpkgs ? import <nixpkgs> {}, compiler ? \"default\" }: "
  , text ""
  , nixLet
    [ text "inherit (nixpkgs.stdenv.lib) extends;"
    , attr "stackageCompilerConfig" $ stackageCompilerConfigFun stackageCompilerConfig
    , attr "stackagePackagesConfig" $ stackageCompilerConfigFun stackagePackagesConfig
    , text "packageOverrides = super: let self = super.pkgs; in"
    , text "{"
    , text "  pkgs = super.pkgs // {"
    , text "    haskell = super.pkgs.haskell // {"
    , text "      packages = super.pkgs.haskell.packages // {"
    , text "        \"${compiler}\" = super.pkgs.haskell.packages." <> disp haskellPackagesOverride <> ".override {};"
    , text "      };"
    , text "    };"
    , text "  };"
    , text "};"
    , text "in packageOverrides nixpkgs"
    ]
  ]

-- TODO: maybe move to module Stack.Derivation

newtype HackageDb = HackageDb { fromHackageDB :: T.Text }
  deriving (Eq, Ord, Show)

makePrisms ''HackageDb

unHackageDb :: HackageDb -> String
unHackageDb = T.unpack . fromHackageDB

-- Thin wrapper around private stack2nix 'PackageSourceSpec.fromDB' method.
getStackPackageFromDb
  :: Maybe HackageDb
  -> StackPackage
  -> IO Package
getStackPackageFromDb optHackageDb stackPackage =
  PackageSourceSpec.getPackage
    (unHackageDb <$> optHackageDb)
    (stackLocationToSource $ stackPackage ^. spSource)

stackLocationToSource :: StackLocation -> Source
stackLocationToSource = \case
  HackagePackage p -> Source
    { sourceUrl      = "cabal://" ++ T.unpack p
    , sourceRevision = mempty
    , sourceHash     = UnknownHash }
  StackPath p     -> Source
    { sourceUrl      = T.unpack p
    , sourceRevision = mempty
    , sourceHash     = UnknownHash }
  StackRepoGit rg -> Source
    { sourceUrl      = T.unpack $ rg ^. rgUri
    , sourceRevision = T.unpack $ rg ^. rgCommit
    , sourceHash     = UnknownHash }

packageDerivation
  :: Maybe HackageDb
  -> System.Platform
  -> Compiler.CompilerId
  -> PackageDescription.FlagAssignment
  -> StackPackage
  -> IO Derivation
packageDerivation optHackageDb optPlatform optCompilerId optFlagAssignment sed = do
  pkg <- getStackPackageFromDb optHackageDb sed
  pure
    $ FromCabal.fromGenericPackageDescription
      (const True)
      (\i -> Just (binding # (i, path # [i])))
      optPlatform
      (unknownCompilerInfo optCompilerId NoAbiTag)
      optFlagAssignment
      []
      (pkgCabal pkg)
    & src .~ pkgSource pkg