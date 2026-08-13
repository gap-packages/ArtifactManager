# ArtifactManager: helpers for package authors
#
#@local f
gap> START_TEST("publish.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

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
# Describing a URL.  The artifact checksum comes from no other tool, so this
# has to download and unpack.  Expected values are git's; see tst/hash.tst.
#
gap> f := AM_DescribeURL(AMT_Url("sample.tar.gz"), "tar.gz", "data");;
gap> f.format; f.size; f.isDirectory;
"tar.gz"
220
true
gap> f.sha256 = AMT_Sha("sample.tar.gz");
true
gap> f.artifactSha256 = AMT_TreeSha.sample;
true

# Asked for the same download as a plain file, it is a file artifact and the
# checksum is of the bytes themselves.
gap> f := AM_DescribeURL(AMT_Url("sample.txt"), "raw", "data");;
gap> f.isDirectory; f.artifactSha256 = AMT_PlainSha;
false
true

# Decompressing a '.gz' gives the checksum of what is inside it.
gap> AM_DescribeURL(AMT_Url("sample.txt.gz"), "gz", "d").artifactSha256
>      = AMT_PlainSha;
true

# Without a format, the bytes decide -- a suggestion for a human to confirm,
# never a run-time decision.
gap> AM_DescribeURL(AMT_Url("sample.tar.gz"), fail, "d").format;
"tar.gz"
gap> AM_DescribeURL(AMT_Url("sample.txt.gz"), fail, "d").format;
"gz"
gap> AM_DescribeURL(AMT_Url("sample.txt"), fail, "d").format;
"raw"
gap> AM_DescribeURL(AMT_Url("no-such-file.tar.gz"), "tar.gz", "d");
fail
gap> DescribeArtifactURL(AMT_Url("sample.txt"), "d", "raw", "x");
Error, usage: DescribeArtifactURL( <url>[, <name>[, <format>]] )

#
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("publish.tst");
