# ArtifactManager: the network layer
#
# Everything else is tested over file:// URLs, which needs no network at all.
# This file covers the one thing that cannot reach: talking HTTP through the
# utils package's 'Download'.  It needs the IO package (to run a server) and
# some way of making an HTTP request, and is skipped otherwise.
#
#@local server, sha, store
gap> START_TEST("download.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"http-server.g"));

#@if IsPackageMarkedForLoading("IO", "") and (PathSystemProgram("curl") <> fail or PathSystemProgram("wget") <> fail)
gap> store := AMT_UseTempStore();;
gap> server := AMT_StartHTTPTestServer();;
gap> sha := AM_HexSHA256String(AMT_HTTPBody);;
gap> DeclareArtifacts("amhttp", [
>      rec(name := "ok", description := "served over http",
>          download := [rec(url := server.url("/file"), sha256 := sha,
>                           format := "file")]),
>      rec(name := "redirected", description := "302 to the real thing",
>          download := [rec(url := server.url("/redirect"), sha256 := sha,
>                           format := "file")]),
>      rec(name := "corrupt", description := "server returns wrong bytes",
>          download := [rec(url := server.url("/corrupt"), sha256 := sha,
>                           format := "file")]),
>      rec(name := "missing", description := "404",
>          download := [rec(url := server.url("/missing"), sha256 := sha,
>                           format := "file")]),
>      rec(name := "failover", description := "a dead source, then a good one",
>          download := [rec(url := server.url("/missing"), sha256 := sha,
>                           format := "file"),
>                       rec(url := server.url("/file"), sha256 := sha,
>                           format := "file")]),
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
