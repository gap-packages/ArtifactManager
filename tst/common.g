#############################################################################
##
##  Helpers shared by the ArtifactManager tests.
##
##  Every test reads this file; TestDirectory runs them all in one GAP
##  session, so it has to be safe to read more than once.
##

if not IsBoundGlobal( "AMT_DataDirectory" ) then

BindGlobal( "AMT_DataDirectory",
    Filename( DirectoriesPackageLibrary( "ArtifactManager", "tst/data" ), "" ) );

BindGlobal( "AMT_File",
    f -> Concatenation( AMT_DataDirectory, f ) );

BindGlobal( "AMT_Url",
    f -> Concatenation( "file://", AMT_DataDirectory, f ) );

BindGlobal( "AMT_Sha",
    f -> AM_HexSHA256File( AMT_File( f ) ) );

# A checksum that is valid in shape but matches nothing.
BindGlobal( "AMT_WrongSha",
    "0000000000000000000000000000000000000000000000000000000000000001" );

# Point the store at a fresh temporary directory.  DirectoryTemporary is
# removed when GAP exits, so a test can never touch a real store.
BindGlobal( "AMT_UseTempStore", function()
  local dir;
  dir := DirectoryTemporary();
  SetUserPreference( "ArtifactManager", "ArtifactStore",
                     Filename( dir, "store" ) );
  SetUserPreference( "ArtifactManager", "ExtraArtifactStores", [] );
  SetUserPreference( "ArtifactManager", "ArtifactStoreOverrides", rec() );
  SetUserPreference( "ArtifactManager", "AllowDownloads", true );
  SetUserPreference( "ArtifactManager", "MaxAutoDownloadSize", 0 );
  return Filename( dir, "store" );
end );

# The fixtures, declared as artifacts of the fictitious package "amtest".
BindGlobal( "AMT_DeclareFixtures", function()
  DeclareArtifacts( "amtest", [
    rec( name := "tgz",
         description := "a tarball",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample.tar.gz" ),
                            sha256 := AMT_Sha( "sample.tar.gz" ) ) ] ),
    rec( name := "zip",
         description := "a zip archive",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample.zip" ),
                            sha256 := AMT_Sha( "sample.zip" ) ) ] ),
    rec( name := "symlink",
         description := "an archive containing a symbolic link",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample-symlink.tar.gz" ),
                            sha256 := AMT_Sha( "sample-symlink.tar.gz" ) ) ] ),
    rec( name := "macos",
         description := "a tarball with the usual macOS dot-file litter",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample-macos.tar.gz" ),
                            sha256 := AMT_Sha( "sample-macos.tar.gz" ) ) ] ),
    rec( name := "txt",
         description := "a single file",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ) ] ),
    rec( name := "gz",
         description := "a compressed single file",
         download := [ rec( url := AMT_Url( "sample.txt.gz" ),
                            sha256 := AMT_Sha( "sample.txt.gz" ) ) ] ),
    rec( name := "broken",
         description := "declared with the wrong checksum",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_WrongSha,
                            format := "file" ) ] ),
    rec( name := "mirrored",
         description := "a dead source followed by a good one",
         download := [ rec( url := AMT_Url( "does-not-exist.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ),
                       rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ) ] ),
    rec( name := "big",
         description := "declared as enormous",
         size := 10^12,
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ) ] ),
  ] );
end );

fi;
