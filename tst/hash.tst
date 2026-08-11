# ArtifactManager: checksums
#
#@local zeros, d
gap> START_TEST("hash.tst");
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

# Normalisation: lowercase, and left-padded to 64 digits.
#
# The padding is what protects us from GAP 4.12 to 4.15, where HexSHA256
# drops leading zeros, so a package author's stored checksum may be short.
gap> zeros := n -> ListWithIdenticalEntries(n, '0');;
gap> AM_NormalizeHex("ABC") = Concatenation(zeros(61), "abc");
true
gap> AM_NormalizeHex("abc") = AM_NormalizeHex("ABC");
true
gap> Length(AM_NormalizeHex(""));
64
gap> AM_NormalizeHex(Concatenation(zeros(64), "0"));
fail
gap> AM_NormalizeHex("xyz");
fail
gap> AM_NormalizeHex(42);
fail
gap> AM_IsSHA256("abc");
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
gap> STOP_TEST("hash.tst");
