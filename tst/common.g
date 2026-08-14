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
# Tree hashes are what git reports for the unpacked data:
#   git init --object-format=sha256 && git add -A && git commit
#   git rev-parse 'HEAD^{tree}'
# so they check the encoding as well as the pipeline.  "symlink" is rejected
# before it is ever hashed, so its value is never reached.
BindGlobal( "AMT_TreeSha", rec(
    sample := "523f33c8b115ae982bca50b733af2df49a26a95e42033774b5ae24afa0d8ff55",
    macos  := "5f2245e00d833827b3c7cd4e4e444103131f0c59f313936f595ebcefa3b6fae8",
    link   := "0cb27ebb557eb20cd67330eb9a20e68743edb13346a613d400158645ec0671fa" ) );

# Plain "plain artifact\n", and the gzip of it.
BindGlobal( "AMT_PlainSha",
    "aa2132fcc52f465cdf2d0aad6239f788717db36baf84690deac7e1275303a81b" );
BindGlobal( "AMT_GzipSha",
    "a53e5af16337946166558c464f5b3495666de05b1516ea3d810aab19e217eacb" );

BindGlobal( "AMT_DeclareFixtures", function()
  DeclareArtifacts( "amtest", [
    rec( name := "tgz",
         tree_sha256 := AMT_TreeSha.sample,
         description := "a tarball",
         download := [ rec( url := AMT_Url( "sample.tar.gz" ),
                            sha256 := AMT_Sha( "sample.tar.gz" ),
                            format := "tar.gz" ) ] ),
    rec( name := "twoformats",
         tree_sha256 := AMT_TreeSha.sample,
         description := "the same tree, compressed or not",
         download := [ rec( url := AMT_Url( "sample.tar" ),
                            sha256 := AMT_Sha( "sample.tar" ),
                            format := "tar" ),
                       rec( url := AMT_Url( "sample.tar.gz" ),
                            sha256 := AMT_Sha( "sample.tar.gz" ),
                            format := "tar.gz" ) ] ),
    rec( name := "symlink",
         tree_sha256 := AMT_TreeSha.link,
         description := "an archive containing a symbolic link",
         download := [ rec( url := AMT_Url( "sample-symlink.tar.gz" ),
                            sha256 := AMT_Sha( "sample-symlink.tar.gz" ),
                            format := "tar.gz" ) ] ),
    rec( name := "macos",
         tree_sha256 := AMT_TreeSha.macos,
         description := "a tarball with the usual macOS dot-file litter",
         download := [ rec( url := AMT_Url( "sample-macos.tar.gz" ),
                            sha256 := AMT_Sha( "sample-macos.tar.gz" ),
                            format := "tar.gz" ) ] ),
    rec( name := "txt",
         file_sha256 := AMT_PlainSha,
         description := "a single file, used as it comes",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "raw" ) ] ),
    rec( name := "sample.txt.gz",
         file_sha256 := AMT_GzipSha,
         description := "kept compressed; GAP decompresses it on read",
         download := [ rec( url := AMT_Url( "sample.txt.gz" ),
                            sha256 := AMT_Sha( "sample.txt.gz" ),
                            format := "raw" ) ] ),
    rec( name := "gunzipped",
         file_sha256 := AMT_PlainSha,
         description := "the same download, decompressed on install",
         download := [ rec( url := AMT_Url( "sample.txt.gz" ),
                            sha256 := AMT_Sha( "sample.txt.gz" ),
                            format := "gz" ) ] ),
    rec( name := "broken",
         file_sha256 := AMT_PlainSha,
         description := "declared with the wrong download checksum",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_WrongSha,
                            format := "raw" ) ] ),
    rec( name := "mirrored",
         file_sha256 := AMT_PlainSha,
         description := "a dead source followed by a good one",
         download := [ rec( url := AMT_Url( "does-not-exist.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "raw" ),
                       rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            format := "raw" ) ] ),
    rec( name := "big",
         file_sha256 := AMT_PlainSha,
         description := "declared as enormous",
         download := [ rec( url := AMT_Url( "sample.txt" ),
                            sha256 := AMT_Sha( "sample.txt" ),
                            size := 10^12,
                            format := "raw" ) ] ),
  ] );
end );

fi;
