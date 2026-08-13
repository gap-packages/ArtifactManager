# ArtifactManager: declarations and manifests
#
#@local m, d, decls, ok, dl
gap> START_TEST("declare.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));

#
# Validating a single declaration.
#
# A minimal valid declaration, given a URL.
gap> dl := u -> rec(tree_sha256 := AMT_WrongSha,
>                   download := [rec(url := u, sha256 := AMT_WrongSha)]);;
gap> ok := dl("https://x/a.tar.gz");;
gap> d := AM_CheckDeclaration("p", "a", ok);;
gap> d.package; d.name; d.download[1].format;
"p"
"a"
"tar.gz"

# The format is guessed from the URL when it is not given.
gap> List(["a.zip","a.tgz","a.grp.gz","a"],
>         u -> AM_CheckDeclaration("p","a",dl(u)).download[1].format);
[ "zip", "tar.gz", "file.gz", "file" ]

# ... and so is the name a single-file artifact gets on disk.
gap> AM_CheckDeclaration("p","a",dl("https://x/y/a.grp")).download[1].filename;
"a.grp"

# Problems are reported as a string, not raised, so one bad artifact never
# takes a whole manifest with it.
gap> AM_CheckDeclaration("p", "a", rec());
"'download' must be a non-empty list"
gap> AM_CheckDeclaration("p", "a", rec(download := []));
"'download' must be a non-empty list"
gap> AM_CheckDeclaration("p", "bad name", ok){[1..3]};
"'ba"
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(url:="https://x/a",sha256:="zz")]));
"download entry 1: 'sha256' is not a hexadecimal string"
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(sha256:=AMT_WrongSha)]));
"download entry 1: 'url' must be a non-empty string"
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha,format:="rar")])){[1..27]};
"download entry 1: 'format' "

# A tree hash is mandatory, and the message says how to get one.
gap> AM_CheckDeclaration("p","a",rec(download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha)]));
"'tree_sha256' is missing.  Run  DescribeArtifactURL(\"https://x/a\");  to comp\
ute it."
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:="zz",download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha)]));
"'tree_sha256' is not a hexadecimal string"

# A kind we do not understand skips that artifact, with an explanation.
gap> AM_CheckDeclaration("p","a",rec(kind:="tree",download:=[rec(url:="https://x/a",sha256:=AMT_WrongSha)])){[1..17]};
"unsupported kind "

# Checksums are normalised when they are read, so an author who generated one
# on GAP 4.14 (where leading zeros are dropped) is not left with a manifest
# that never matches.
gap> AM_CheckDeclaration("p","a",rec(tree_sha256:="1",download:=[rec(url:="https://x/a",sha256:="1")])).download[1].sha256 = AM_NormalizeHex("1");
true

#
# Parsing a whole manifest.
#
gap> m := Concatenation("{\"gapArtifactManifest\": 1, \"package\": \"p\",",
>      "\"artifacts\": {\"one\": {\"description\": \"d\",",
>      "\"tree_sha256\": \"", AMT_WrongSha, "\",",
>      "\"download\": [{\"url\": \"https://x/one.tar.gz\", \"sha256\": \"",
>      AMT_WrongSha, "\"}]}}}");;
gap> decls := AM_ParseManifest("p", m, "test");;
gap> Length(decls); decls[1].name; decls[1].description;
1
"one"
"d"

# A manifest from the future is skipped whole, with a message telling the user
# to upgrade -- never a parse error.
gap> AM_ParseManifest("p", "{\"gapArtifactManifest\": 99, \"artifacts\": {}}", "test");
[  ]

# Unknown keys are ignored, so a later version can add fields.
gap> m := Concatenation("{\"gapArtifactManifest\": 1, \"whatIsThis\": 7,",
>      "\"artifacts\": {\"one\": {\"futureField\": [1],",
>      "\"tree_sha256\": \"", AMT_WrongSha, "\",",
>      "\"download\": [{\"url\": \"https://x/one.tar.gz\", \"sha256\": \"",
>      AMT_WrongSha, "\"}]}}}");;
gap> Length(AM_ParseManifest("p", m, "test"));
1

# One broken artifact does not lose the good ones.
gap> m := Concatenation("{\"gapArtifactManifest\": 1, \"artifacts\": {",
>      "\"bad\": {}, \"good\": {\"tree_sha256\": \"", AMT_WrongSha, "\",",
>      "\"download\": [{\"url\": \"https://x/g.zip\",",
>      "\"sha256\": \"", AMT_WrongSha, "\"}]}}}");;
gap> List(AM_ParseManifest("p", m, "test"), d -> d.name);
[ "good" ]

# Malformed or mislabelled manifests are ignored rather than fatal.
gap> AM_ParseManifest("p", "not json", "test");
[  ]
gap> AM_ParseManifest("p", "{}", "test");
[  ]
gap> AM_ParseManifest("p", "{\"gapArtifactManifest\": 1}", "test");
[  ]
gap> AM_ParseManifest("p", "[1]", "test");
[  ]
gap> AM_ParseManifest("p", "{\"gapArtifactManifest\":1,\"package\":\"q\",\"artifacts\":{}}", "test");
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
[ "big", "broken", "gz", "macos", "mirrored", "symlink", "tgz", "txt", "zip" ]

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

# The manifest also declares an artifact of a kind we do not understand.  It is
# skipped; the ones we do understand are unaffected.
gap> ArtifactDeclaration("amfake", "fromTheFuture");
fail
gap> d := ArtifactDeclaration("amfake", "groups");;
gap> d.size; d.strip; d.license; Length(d.download);
314572800
1
"GPL-2.0-or-later"
2
gap> d.download[1].format;
"tar.gz"
gap> ArtifactDeclaration("amfake", "table").download[1].format;
"file.gz"
gap> Unbind(GAPInfo.PackagesInfo.amfake);
gap> AM_FlushDeclarations();
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("declare.tst");
