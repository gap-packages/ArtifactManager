# ArtifactManager: helpers for package authors
#
#@local f
gap> START_TEST("publish.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

# Guessing the format from the URL.
gap> List(["a.tar.gz", "a.tgz", "a.tar.bz2", "a.tar.xz", "a.tar", "a.zip",
>          "a.g.gz", "a.grp", "a"], AM_GuessFormat);
[ "tar.gz", "tar.gz", "tar.bz2", "tar.xz", "tar", "zip", "file.gz", "file", 
  "file" ]

# Guessing it from the bytes instead.  This is what saves a package author
# whose download URL carries no file name at all -- Zenodo's, for one, ends in
# "/content", so the URL alone says "file" for what is really a tarball.
#@if IsPackageMarkedForLoading("IO", "")
gap> AM_SniffFormat(AMT_File("sample.tar.gz"));
"gzip"
gap> AM_SniffFormat(AMT_File("sample.txt.gz"));
"gzip"
gap> AM_SniffFormat(AMT_File("sample.zip"));
"zip"
gap> AM_SniffFormat(AMT_File("sample.txt"));
fail
gap> AM_SniffFormat(AMT_File("no-such-file"));
fail
#@else
gap> Print("skipped: sniffing needs the IO package\n");
skipped: sniffing needs the IO package
#@fi

#
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("publish.tst");
