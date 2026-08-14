# ArtifactManager: helpers for package authors
#
#@local f
gap> START_TEST("publish.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

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

# The same download as a plain file: a file artifact, checksummed over the
# bytes themselves.
gap> f := AM_DescribeURL(AMT_Url("sample.txt"), "raw", "data");;
gap> f.isDirectory; f.artifactSha256 = AMT_PlainSha;
false
true

# Decompressing a '.gz' gives the checksum of what is inside it.
gap> AM_DescribeURL(AMT_Url("sample.txt.gz"), "gz", "d").artifactSha256
>      = AMT_PlainSha;
true
gap> AM_DescribeURL(AMT_Url("no-such-file.tar.gz"), "tar.gz", "d");
fail

# The format is never guessed, so it has to be given.
gap> DescribeArtifactURL(AMT_Url("sample.txt"), "d"){[1..3]};
Error, Function: number of arguments must be 3 (not 2)
gap> DescribeArtifactURL(AMT_Url("sample.txt"), "d", "guess"){[1..3]};
Error, <format> must be one of raw, gz, tar, tar.gz.  Say what should happen t\
o the download; it is not guessed.

gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("publish.tst");
