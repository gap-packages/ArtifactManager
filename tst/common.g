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
#
# The tree hashes are what git reports for the unpacked data:
#   git init --object-format=sha256 && git add -A && git commit
#   git rev-parse 'HEAD^{tree}'
# so they check the encoding as well as the pipeline.  "symlink" never gets
# far enough to be unpacked, so its hash is arbitrary.
BindGlobal( "AMT_DeclareFixtures", function()
  DeclareArtifacts( "amtest", [
    rec( name := "tgz",
         tree_sha256 :=
        "65da3422418c6e2c705b385a3fbd8127d652b1e54285e78f44597ad15a2b3555",
         description := "a tarball",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample.tar.gz" ),
                            sha256 := AMT_Sha( "sample.tar.gz" ) ) ] ),
    rec( name := "zip",
         tree_sha256 :=
        "65da3422418c6e2c705b385a3fbd8127d652b1e54285e78f44597ad15a2b3555",
         description := "a zip archive",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample.zip" ),
                            sha256 := AMT_Sha( "sample.zip" ) ) ] ),
    rec( name := "symlink",
         tree_sha256 :=
        "0000000000000000000000000000000000000000000000000000000000000002",
         description := "an archive containing a symbolic link",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample-symlink.tar.gz" ),
                            sha256 := AMT_Sha( "sample-symlink.tar.gz" ) ) ] ),
    rec( name := "macos",
         tree_sha256 :=
        "fbda8bac4ed2e92ce60e6a6361bb7f750a4b12dc46dd3ec7a35a4a69974ea0d0",
         description := "a tarball with the usual macOS dot-file litter",
         strip := 1,
         download := [ rec( url := AMT_Url( "sample-macos.tar.gz" ),
                            sha256 := AMT_Sha( "sample-macos.tar.gz" ) ) ] ),
    rec( name := "txt",
         tree_sha256 :=
        "146e6ef112f8a6c08fbad6382dd54c7bf38b511138c42d0847683b6065d0ed38",
         description := "a single file",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ) ] ),
    rec( name := "gz",
         tree_sha256 :=
        "ae9c130a8b628ba748e982d271dcfb2ae290e74733f1e2c6c4a862a70f9f7127",
         description := "a compressed single file",
         download := [ rec( url := AMT_Url( "sample.txt.gz" ),
                            sha256 := AMT_Sha( "sample.txt.gz" ) ) ] ),
    rec( name := "broken",
         tree_sha256 :=
        "146e6ef112f8a6c08fbad6382dd54c7bf38b511138c42d0847683b6065d0ed38",
         description := "declared with the wrong checksum",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_WrongSha,
                            format := "file" ) ] ),
    rec( name := "mirrored",
         tree_sha256 :=
        "146e6ef112f8a6c08fbad6382dd54c7bf38b511138c42d0847683b6065d0ed38",
         description := "a dead source followed by a good one",
         download := [ rec( url := AMT_Url( "does-not-exist.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ),
                       rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ) ] ),
    rec( name := "big",
         tree_sha256 :=
        "146e6ef112f8a6c08fbad6382dd54c7bf38b511138c42d0847683b6065d0ed38",
         description := "declared as enormous",
         size := 10^12,
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "file" ) ] ),
  ] );
end );

fi;
