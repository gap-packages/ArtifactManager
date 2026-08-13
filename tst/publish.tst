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
# Describing a URL.  A tree hash is mandatory in a manifest and no other tool
# produces one, so this has to download and unpack.  The expected value is
# what git reports for the same tree; see tst/hash.tst.
#
gap> f := AM_DescribeURL(AMT_Url("sample.tar.gz"), 1);;
gap> f.format; f.size; f.strip;
"tar.gz"
596
1
gap> f.sha256 = AMT_Sha("sample.tar.gz");
true
gap> f.tree_sha256 =
>    "65da3422418c6e2c705b385a3fbd8127d652b1e54285e78f44597ad15a2b3555";
true

# Without the strip the tarball's own top-level directory is part of the tree,
# so the hash differs.
gap> AM_DescribeURL(AMT_Url("sample.tar.gz"), 0).tree_sha256 = f.tree_sha256;
false
gap> AM_DescribeURL(AMT_Url("no-such-file.tar.gz"), 1);
fail
gap> DescribeArtifactURL(AMT_Url("sample.tar.gz"), 1, 2);
Error, usage: DescribeArtifactURL( <url>[, <strip>] )

#
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("publish.tst");
