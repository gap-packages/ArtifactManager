#
# A fixture package, used only to test that ArtifactManager finds an
# 'artifacts.json' through GAP's package machinery.  It is never loaded.
#
SetPackageInfo( rec(
PackageName := "amfake",
Subtitle := "Fixture package for the ArtifactManager tests",
Version := "1.0",
Date := "01/01/2026",
License := "GPL-2.0-or-later",
PackageDoc := rec(
  BookName := "amfake",
  SixFile := "doc/manual.six",
  Autoload := false,
),
Dependencies := rec(
  GAP := ">= 4.13",
  NeededOtherPackages := [ ],
  SuggestedOtherPackages := [ ],
  ExternalConditions := [ ],
),
AvailabilityTest := ReturnTrue,
) );
