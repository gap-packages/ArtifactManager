# ArtifactManager: declarations and manifests
#
#@local m, d, decls, ok, dir, file
gap> START_TEST("declare.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

#
# Validating a single declaration.
#
# A minimal valid declaration of each kind.
gap> dir := u -> rec(tree_sha256 := AMT_WrongSha,
>        download := [rec(url := u, sha256 := AMT_WrongSha, format := "tar.gz")]);;
gap> file := u -> rec(file_sha256 := AMT_WrongSha,
>        download := [rec(url := u, sha256 := AMT_WrongSha, format := "raw")]);;
gap> ok := dir("https://x/a.tar.gz");;
gap> d := AM_CheckDeclaration("p", "a", ok);;
gap> d.package; d.name; d.isDirectory; d.download[1].format;
"p"
"a"
true
"tar.gz"
gap> AM_CheckDeclaration("p", "a", file("https://x/a")).isDirectory;
false

#
# The kind says itself: a tree hash means a directory, a file hash means a
# file.  Exactly one, or we do not know what we are being asked for.
#
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(url:="https://x/a",
>      sha256:=AMT_WrongSha,format:="raw")])){[1..60]};
"exactly one of 'tree_sha256' (a directory) and 'file_sha256'"
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:=AMT_WrongSha,
>      file_sha256:=AMT_WrongSha,download:=[rec(url:="https://x/a",
>      sha256:=AMT_WrongSha,format:="raw")])){[1..12]};
"exactly one "

# ... and the formats have to agree with it.
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:=AMT_WrongSha,
>      download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha,format:="raw")]));
"the source 'https://x/a' has format 'raw', but this artifact needs an unpacki\
ng format"
gap> AM_CheckDeclaration("p","a",rec(file_sha256:=AMT_WrongSha,
>      download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha,format:="zip")]));
"the source 'https://x/a' has format 'zip', but this artifact needs 'raw' or a\
 decompressing format"

#
# 'format' says what to do with the download, so it is never guessed and
# never omitted.
#
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:=AMT_WrongSha,
>      download:=[rec(url:="https://x/a.tar.gz",sha256:=AMT_WrongSha)])){[1..38]};
"download entry 1: 'format' must be one"
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:=AMT_WrongSha,
>      download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha,
>      format:="rar")])){[1..38]};
"download entry 1: 'format' must be one"

#
# Anything we do not recognise is refused, not ignored: a field we skip is a
# feature its author believes is in force.
#
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:=AMT_WrongSha,strip:=1,
>      download:=[rec(url:="https://x/a.tgz",sha256:=AMT_WrongSha,
>      format:="tar.gz")]));
"unknown field 'strip'; a newer version of ArtifactManager may be needed"
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:=AMT_WrongSha,
>      download:=[rec(url:="https://x/a.tgz",sha256:=AMT_WrongSha,
>      format:="tar.gz",filename:="x")])){[1..43]};
"download entry 1: unknown field 'filename';"

#
# Other problems are reported as a string, not raised.
#
gap> AM_CheckDeclaration("p", "a", rec());
"'download' must be a non-empty list"
gap> AM_CheckDeclaration("p", "bad name", ok){[1..3]};
"'ba"

# The name is also the file name of a file artifact, so it must be usable as
# one.
gap> AM_CheckDeclaration("p", ".hidden", ok){[1..9]};
"'.hidden'"
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(url:="https://x/a",
>      sha256:="zz",format:="raw")]));
"download entry 1: 'sha256' is not a hexadecimal string"
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(sha256:=AMT_WrongSha,
>      format:="raw")]));
"download entry 1: 'url' must be a non-empty string"
gap> AM_CheckDeclaration("p","a",rec(license:="MIT/X11",
>      tree_sha256:=AMT_WrongSha,download:=[rec(url:="https://x/a.tgz",
>      sha256:=AMT_WrongSha,format:="tar.gz")])){[1..14]};
"'license' must"

# Checksums are normalised when they are read, so an author who generated one
# on GAP 4.14 (where leading zeros are dropped) is not left with a manifest
# that never matches.
gap> AM_CheckDeclaration("p","a",rec(file_sha256:="1",
>      download:=[rec(url:="https://x/a",sha256:="1",
>      format:="raw")])).download[1].sha256 = AM_NormalizeHex("1");
true

#
# Parsing a whole manifest.
#
gap> m := Concatenation("{\"gapArtifactManifestVersion\": 1, \"package\": \"p\",",
>      "\"artifacts\": {\"one\": {\"description\": \"d\",",
>      "\"tree_sha256\": \"", AMT_WrongSha, "\",",
>      "\"download\": [{\"url\": \"https://x/one.tar.gz\", \"format\": \"tar.gz\",",
>      "\"sha256\": \"", AMT_WrongSha, "\"}]}}}");;
gap> decls := AM_ParseManifest("p", m, "test");;
gap> Length(decls); decls[1].name; decls[1].description;
1
"one"
"d"

# A manifest from the future is skipped whole, with a message telling the user
# to upgrade -- never a parse error.
gap> AM_ParseManifest("p", "{\"gapArtifactManifestVersion\": 99, \"package\": \"p\", \"artifacts\": {}}", "test");
[  ]

# An unknown top-level key is refused for the same reason as an unknown field.
gap> AM_ParseManifest("p", Concatenation("{\"gapArtifactManifestVersion\": 1,",
>      "\"package\": \"p\", \"whatIsThis\": 7, \"artifacts\": {}}"), "test");
[  ]

# One broken artifact does not lose the good ones: a package adding an
# artifact we cannot read must not break the ones we can.
gap> m := Concatenation("{\"gapArtifactManifestVersion\": 1, \"package\": \"p\",",
>      "\"artifacts\": {",
>      "\"bad\": {\"fromTheFuture\": 1}, \"good\": {\"tree_sha256\": \"",
>      AMT_WrongSha, "\", \"download\": [{\"url\": \"https://x/g.zip\",",
>      "\"format\": \"zip\", \"sha256\": \"", AMT_WrongSha, "\"}]}}}");;
gap> List(AM_ParseManifest("p", m, "test"), d -> d.name);
[ "good" ]

# 'package' is mandatory, so tooling outside GAP can read the package name
# here instead of parsing PackageInfo.g.
gap> AM_ParseManifest("p", "{\"gapArtifactManifestVersion\":1,\"artifacts\":{}}", "test");
[  ]
gap> AM_ParseManifest("p", "{\"gapArtifactManifestVersion\":1,\"package\":\"q\",\"artifacts\":{}}", "test");
[  ]

# Malformed manifests are ignored rather than fatal.
gap> AM_ParseManifest("p", "not json", "test");
[  ]
gap> AM_ParseManifest("p", "{}", "test");
[  ]
gap> AM_ParseManifest("p", "[1]", "test");
[  ]

#
# Runtime declarations.
#
gap> AMT_DeclareFixtures();
gap> ArtifactDeclaration("amtest", "tgz").description;
"a tarball"
gap> ArtifactDeclaration("AMTEST", "tgz") = ArtifactDeclaration("amtest", "tgz");
true
gap> ArtifactDeclaration("amtest", "nope");
fail
gap> ArtifactDeclaration("no-such-package", "x");
fail
gap> SortedList(List(AllArtifactDeclarations("amtest"), d -> d.name));
[ "big", "broken", "gunzipped", "macos", "mirrored", "sample.txt.gz", 
  "symlink", "tgz", "txt", "zip" ]

# A bad runtime declaration is a programming error, so here it does raise.
gap> DeclareArtifacts("amtest", [rec(name := "x")]);
Error, invalid declaration of artifact 'x' for package 'amtest': 'download' mu\
st be a non-empty list
gap> DeclareArtifacts("amtest", [rec()]);
Error, each entry of <list> must be a record with a component 'name'

#
# Discovery: finding artifacts.json through GAPInfo.PackagesInfo.
#
# This is the path that matters for real packages, and the reason the manifest
# lives at a fixed place in the package directory: GAP fills PackagesInfo in at
# startup for every installed version of every package, so we find the file
# without loading anything.  Here a fixture package is registered for the
# duration of the test.
#
gap> SetPackagePath("amfake",
>      DirectoriesPackageLibrary("ArtifactManager", "tst/data/fakepkg")[1]);
gap> SortedList(List(AllArtifactDeclarations("amfake"), d -> d.name));
[ "groups", "table" ]

# The manifest also declares an artifact using a field we do not understand.
# It is skipped; the ones we do understand are unaffected.
gap> ArtifactDeclaration("amfake", "fromTheFuture");
fail
gap> d := ArtifactDeclaration("amfake", "groups");;
gap> d.isDirectory; d.license; Length(d.download); d.download[1].size;
true
"GPL-2.0-or-later"
2
300000000

# Two sources in different formats are one artifact, because the tree they
# unpack to is the same.
gap> List(d.download, e -> e.format);
[ "tar.gz", "zip" ]
gap> ArtifactDeclaration("amfake", "table").isDirectory;
false
gap> Unbind(GAPInfo.PackagesInfo.amfake);
gap> AM_FlushDeclarations();
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("declare.tst");
