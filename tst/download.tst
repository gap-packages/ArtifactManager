# ArtifactManager: the network layer
#
# Everything else is tested over file:// URLs, which needs no network at all.
# This file covers the one thing that cannot reach: talking HTTP through the
# utils package's 'Download'.  It needs the IO package (to run a server) and
# some way of making an HTTP request, and is skipped otherwise.
#
#@local server, sha, tree, store, one
gap> START_TEST("download.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"http-server.g"));

#@if IsPackageMarkedForLoading("IO", "") and (PathSystemProgram("curl") <> fail or PathSystemProgram("wget") <> fail)
gap> store := AMT_UseTempStore();;
gap> server := AMT_StartHTTPTestServer();;
gap> sha := AM_HexSHA256String(AMT_HTTPBody);;
gap> tree := "146e6ef112f8a6c08fbad6382dd54c7bf38b511138c42d0847683b6065d0ed38";;
gap> one := u -> rec(url := server.url(u), sha256 := sha,
>                    format := "file", filename := "sample.txt");;
gap> DeclareArtifacts("amhttp", [
>      rec(name := "ok", description := "served over http",
>          tree_sha256 := tree, download := [one("/file")]),
>      rec(name := "redirected", description := "302 to the real thing",
>          tree_sha256 := tree, download := [one("/redirect")]),
>      rec(name := "corrupt", description := "server returns wrong bytes",
>          tree_sha256 := tree, download := [one("/corrupt")]),
>      rec(name := "missing", description := "404",
>          tree_sha256 := tree, download := [one("/missing")]),
>      rec(name := "failover", description := "a dead source, then a good one",
>          tree_sha256 := tree,
>          download := [one("/missing"), one("/file")]),
>    ]);

# The happy path.
gap> StringFile(ArtifactFile("amhttp", "ok"));
"plain artifact\n"

# Redirects must be followed; this is one of the things that broke packages
# doing their own downloads when servers moved to https.
gap> StringFile(ArtifactFile("amhttp", "redirected"));
"plain artifact\n"

# A server that hands back the wrong bytes is caught by the checksum, and
# nothing is installed.
gap> FetchArtifact("amhttp", "corrupt");
false
gap> IsArtifactAvailable("amhttp", "corrupt");
false

# A 404 must not be mistaken for content.  (Several GAP packages that roll
# their own downloads do exactly that, and cache the error page.)
gap> FetchArtifact("amhttp", "missing");
false

# Sources are tried in order until one works.
gap> StringFile(ArtifactFile("amhttp", "failover"));
"plain artifact\n"

# Fetching without storing works over http too.
gap> ArtifactContents("amhttp", "ok");
"plain artifact\n"
gap> AMT_StopHTTPTestServer(server);
#@else
gap> Print("skipped: no IO package, or no way to make an HTTP request\n");
skipped: no IO package, or no way to make an HTTP request
#@fi

#
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("download.tst");
