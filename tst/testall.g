#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# This file runs package tests. It is also referenced in the package
# metadata in PackageInfo.g.
#
LoadPackage( "ArtifactManager" );

# 'uptowhitespace' because several tests check the text of an error message,
# and GAP wraps those at the screen width.  Note it belongs in 'testOptions';
# passed at the top level it is silently ignored.
TestDirectory( DirectoriesPackageLibrary( "ArtifactManager", "tst" ),
  rec( exitGAP := true,
       testOptions := rec( compareFunction := "uptowhitespace" ) ) );

FORCE_QUIT_GAP(1); # if we ever get here, there was an error
