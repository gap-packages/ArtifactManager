# ArtifactManager: the store, and directory handling
#
#@local store, dir, deep, key, tmp
gap> START_TEST("store.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

#
# CreateDirectoryRecursively
#
gap> dir := Filename(DirectoryTemporary(), "");;
gap> deep := Concatenation(dir, "a/b/c");;
gap> CreateDirectoryRecursively(deep);
true
gap> IsDirectoryPath(deep);
true

# Doing it again is not an error: another process may have won the race, and
# the result is the same either way.
gap> CreateDirectoryRecursively(deep);
true
gap> CreateDirectoryRecursively(dir);
true

# A path component that exists but is not a directory cannot be created.
gap> FileString(Concatenation(dir, "afile"), "x");;
gap> CreateDirectoryRecursively(Concatenation(dir, "afile/below"));
fail
gap> CreateDirectoryRecursively(42);
Error, <path> must be a string

#
# Store paths
#
gap> store := AMT_UseTempStore();;
gap> ArtifactStoreDirectory() = store;
true
gap> IsDirectoryPath(AM_WritableStore());
true

# Creating the store leaves a CACHEDIR.TAG, so that backup tools skip it.
gap> IsExistingFile(Concatenation(store, "/CACHEDIR.TAG"));
true
gap> StringFile(Concatenation(store, "/CACHEDIR.TAG")){[1..10]};
"Signature:"
gap> AM_ReadRecordFile(Concatenation(store, "/store-info.g")).storeFormat;
1

# The path of an artifact carries the first 16 digits of its checksum.  That
# is what makes a changed declaration install somewhere new, instead of being
# confused with the old data.
gap> key := rec(package := "p", name := "n", sha256 := AMT_WrongSha);;
gap> AM_ShortHash(AMT_WrongSha);
"0000000000000000"
gap> AM_PayloadPath("/s", key);
"/s/artifacts/p/n-0000000000000000"
gap> AM_MetaPath("/s", key);
"/s/meta/p/n-0000000000000000.g"
gap> AM_UsedPath("/s", key);
"/s/used/p/n-0000000000000000.g"

# A per-package override sends one package's data somewhere else.
gap> SetUserPreference("ArtifactManager", "ArtifactStoreOverrides",
>        rec(somepkg := "/elsewhere"));
gap> ArtifactStoreDirectory("somepkg");
"/elsewhere"
gap> ArtifactStoreDirectory("otherpkg") = store;
true
gap> SetUserPreference("ArtifactManager", "ArtifactStoreOverrides", rec());

# Read-only extra stores are searched, but come after the writable one and
# are never installed into.
gap> SetUserPreference("ArtifactManager", "ExtraArtifactStores", ["/ro"]);
gap> List(AM_Stores("p"), s -> s.writable);
[ true, false ]
gap> Last(AM_Stores("p")).path;
"/ro"
gap> ArtifactStoreDirectory("p") = store;
true
gap> SetUserPreference("ArtifactManager", "ExtraArtifactStores", []);

#
# Small record files survive a round trip.
#
gap> tmp := Concatenation(store, "/probe.g");;
gap> AM_WriteRecordFile(tmp, rec(a := 1, b := "two", c := [3]));
true
gap> AM_ReadRecordFile(tmp);
rec( a := 1, b := "two", c := [ 3 ] )
gap> AM_ReadRecordFile(Concatenation(store, "/no-such-file.g"));
fail

# A file that runs but errors is caught rather than dropping the caller into a
# break loop.  (A syntactically broken file is handled too, but GAP prints the
# syntax error itself, so that case is not checked here.)
gap> FileString(tmp, "return 1/0;");;
gap> AM_ReadRecordFile(tmp);
Error, Rational operations: <divisor> must not be zero
fail

#
# Nothing outside a store may ever be deleted.
#
gap> AM_AssertInStore(Concatenation(store, "/artifacts/x"));
true
gap> AM_AssertInStore("/etc/passwd");
Error, refusing to touch '/etc/passwd', which is not inside an artifact store
gap> AM_RemoveTree("/tmp");
Error, refusing to touch '/tmp', which is not inside an artifact store

# Leftovers of interrupted downloads are swept up.
gap> CreateDirectoryRecursively(Concatenation(store, "/tmp/am-1-1"));
true
gap> CleanArtifactTemp();
1
gap> CleanArtifactTemp();
0
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("store.tst");
