# ArtifactManager: checksums
#
#@local zeros, d, t, h
gap> START_TEST("hash.tst");
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

# Normalisation: lowercase, and exactly 64 hex digits.
gap> zeros := n -> ListWithIdenticalEntries(n, '0');;
gap> AM_NormalizeHex(Concatenation(zeros(61), "ABC"))
>      = Concatenation(zeros(61), "abc");
true
gap> AM_NormalizeHex("abc");
fail
gap> AM_NormalizeHex(Concatenation(zeros(64), "0"));
fail
gap> AM_NormalizeHex(Concatenation(zeros(61), "xyz"));
fail
gap> AM_NormalizeHex(42);
fail
gap> AM_IsSHA256(Concatenation(zeros(61), "abc"));
true
gap> AM_IsSHA256("zz");
false

# Known answer tests.
gap> AM_HexSHA256String("") =
>    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
true
gap> AM_HexSHA256String("abc") =
>    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
true

# Hashing a file, whichever of the three implementations is in use here.
gap> d := AM_HexSHA256File(AMT_File("sample.txt"));;
gap> Length(d);
64
gap> d = AM_HexSHA256String(StringFile(AMT_File("sample.txt")));
true

# A '.gz' file must be hashed as the bytes on disk, not as what StringFile
# would decompress it to.  Getting this wrong is silent and would make every
# compressed artifact fail verification.
gap> AM_HexSHA256File(AMT_File("sample.txt.gz")) =
>    AM_HexSHA256File(AMT_File("sample.txt"));
false
gap> AM_HexSHA256File(AMT_File("no-such-file"));
fail

#
# Hashing a whole tree.
#
# The expected values are what git itself reports, so these check the
# encoding and not merely that it is deterministic:
#
#   git init --object-format=sha256 . && git add -A && git commit -m x
#   git rev-parse 'HEAD^{tree}'
#
gap> t := Filename(DirectoryTemporary(), "tree");;
gap> CreateDirectoryRecursively(Concatenation(t, "/sub"));;
gap> FileString(Concatenation(t, "/a"), "one");;
gap> FileString(Concatenation(t, "/sub/b"), "two");;
gap> h := "ae894f377c336de98a1f0ef81fd9d4ef0ef1a734152bb80fe0a3051d6214893a";;
gap> AM_TreeSHA256(t) = h;
true

# An empty directory is invisible, because git cannot store one.
gap> CreateDirectoryRecursively(Concatenation(t, "/empty"));;
gap> AM_TreeSHA256(t) = h;
true

# The execute bit is part of the digest, which is why installing an artifact
# must not strip it.
gap> AM_Exec(fail, "chmod", ["+x", Concatenation(t, "/a")]).code;
0
gap> AM_TreeSHA256(t) =
>    "9a859d3ad6486aae2cf1b0322467a537359a9a182d1675386e219831201066dc";
true
gap> AM_TreeSHA256(Concatenation(t, "/no-such-directory"));
fail

#
gap> STOP_TEST("hash.tst");
