#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# This file runs package tests. It is also referenced in the package
# metadata in PackageInfo.g.
#
LoadPackage( "ArtifactManager" );

# 'uptowhitespace' rather than an exact comparison: several tests check the
# text of an error message, and GAP wraps those at the screen width, which
# differs between GAP versions and terminals.  The message contents are still
# compared in full.
TestDirectory( DirectoriesPackageLibrary( "ArtifactManager", "tst" ),
  rec( exitGAP := true,
       compareFunction := "uptowhitespace" ) );

FORCE_QUIT_GAP(1); # if we ever get here, there was an error
