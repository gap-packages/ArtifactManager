# ArtifactManager: the whole pipeline, over file:// URLs
#
# No network, no forking, no optional packages: this exercises download,
# verification, unpacking, installation, re-use, and removal, and it runs
# everywhere.
#
#@local store, d, p, info, first, i, tgz
gap> START_TEST("fetch.tst");
gap> SetInfoLevel(InfoArtifactManager, 0);
gap> Read(Filename(DirectoriesPackageLibrary("ArtifactManager","tst"),"common.g"));
gap> store := AMT_UseTempStore();;
gap> AMT_DeclareFixtures();

#
# A tarball.
#
gap> IsArtifactAvailable("amtest", "tgz");
false
gap> d := ArtifactDirectory("amtest", "tgz");;
gap> IsDirectory(d);
true
gap> IsArtifactAvailable("amtest", "tgz");
true

# 'strip' removed the single leading directory of the archive.
gap> SortedList(Difference(DirectoryContents(Filename(d, "")), [".", ".."]));
[ "hello.txt", "sub" ]
gap> StringFile(Filename(d, "hello.txt"));
"hello artifact\n"
gap> StringFile(Filename(d, "sub/inner.txt"));
"inner file\n"

# The second call must not download anything again.
gap> ArtifactDirectory("amtest", "tgz") = d;
true

# The installed data is read-only, but still readable -- an artifact whose
# directories lost their execute bit would be useless.
gap> IsReadableFile(Filename(d, "hello.txt"));
true

#
# A zip archive.
#
gap> d := ArtifactDirectory("amtest", "zip");;
gap> StringFile(Filename(d, "hello.txt"));
"hello artifact\n"

#
# Archives built on a Mac carry .DS_Store and AppleDouble files beside the
# real top-level directory.  Those must not stop 'strip' from recognising it,
# or every such tarball would need the consumer to know about the extra level.
# They are kept rather than deleted: we do not throw data away silently.
#
gap> d := ArtifactDirectory("amtest", "macos");;
gap> StringFile(Filename(d, "hello.txt"));
"hello artifact\n"
gap> StringFile(Filename(d, "sub/inner.txt"));
"inner file\n"
gap> SortedList(Difference(DirectoryContents(Filename(d, "")), [".", ".."]));
[ ".DS_Store", ".hidden", "hello.txt", "sub" ]

#
# An archive carrying a symbolic link is refused: a link is neither a regular
# file nor a directory, and what it points at is not ours to install.
#
gap> FetchArtifact("amtest", "symlink");
false
gap> IsArtifactAvailable("amtest", "symlink");
false

#
# Fetching to a caller-chosen directory, leaving the store alone.
#
gap> d := Filename(DirectoryTemporary(), "elsewhere");;
gap> IsArtifactAvailable("amtest", "mirrored");
false
gap> FetchArtifact("amtest", "mirrored", d);
true
gap> StringFile(Concatenation(d, "/sample.txt"));
"plain artifact\n"

# and the store still knows nothing about it
gap> IsArtifactAvailable("amtest", "mirrored");
false

# a non-empty destination is refused rather than overwritten
gap> FetchArtifact("amtest", "mirrored", d);
false
gap> FetchArtifact("amtest", "mirrored", 42);
Error, <destination> must be a string
gap> FetchArtifact("amtest", "mirrored", d, d);
Error, usage: FetchArtifact( <pkg>, <name>[, <destination>] )

#
# A single file, and a compressed single file.  The compressed one stays
# compressed on disk; StringFile decompresses it when it is read.
#
gap> StringFile(ArtifactFile("amtest", "txt"));
"plain artifact\n"
gap> p := ArtifactFile("amtest", "gz");;
gap> EndsWith(p, ".gz");
true
gap> StringFile(p);
"plain artifact\n"

# Without a relative path this only works for a one-file artifact.
gap> ArtifactFile("amtest", "tgz");
Error, the artifact 'amtest/tgz' is a directory with 
2 entries; say which file you want
gap> StringFile(ArtifactFile("amtest", "tgz", "sub/inner.txt"));
"inner file\n"

#
# Verification.
#
gap> VerifyArtifact("amtest", "tgz", "marker");
true
gap> VerifyArtifact("amtest", "tgz");
true
gap> VerifyArtifact("amtest", "broken");
false

#
# A checksum that does not match is refused, and the data is not installed.
#
gap> FetchArtifact("amtest", "broken");
false
gap> IsArtifactAvailable("amtest", "broken");
false

# An unreachable source falls through to the next one.
gap> StringFile(ArtifactFile("amtest", "mirrored"));
"plain artifact\n"

#
# Fetching without storing anything.
#
gap> ArtifactContents("amtest", "txt");
"plain artifact\n"
gap> ArtifactContents("amtest", "gz");
"plain artifact\n"
gap> ArtifactContents("amtest", "tgz");
Error, the artifact 'amtest/tgz' is an archive; use ArtifactDirectory instead \
of ArtifactContents

#
# Guard rails.
#
gap> ArtifactDirectory("amtest", "no-such-artifact");
Error, the package 'amtest' declares no artifact 'no-such-artifact'.  Is the p\
ackage installed, and does it have an artifacts.json?

# An artifact declared as huge is not fetched behind the user's back.
gap> SetUserPreference("ArtifactManager", "MaxAutoDownloadSize", 1000);
gap> ArtifactDirectory("amtest", "big");
Error, the artifact amtest/big is 1.0 TB, which is more than the 1.0 kB that m\
ay be downloaded automatically.  Run  FetchArtifact("amtest", "big");  to down\
load it, or raise the user preference ArtifactManager/MaxAutoDownloadSize.

# Asking for it by name is an explicit decision, and goes ahead.
gap> FetchArtifact("amtest", "big");
true
gap> SetUserPreference("ArtifactManager", "MaxAutoDownloadSize", 0);

# Offline mode refuses to reach out at all.
gap> RemoveArtifact("amtest", "txt");
true
gap> SetUserPreference("ArtifactManager", "AllowDownloads", false);
gap> IsArtifactAvailable("amtest", "txt");
false
gap> ArtifactDirectory("amtest", "txt");
Error, the artifact amtest/txt is not available locally, and downloads are swi\
tched off.  Set the user preference ArtifactManager/AllowDownloads to 'true' t\
o allow them.
gap> ArtifactContents("amtest", "txt");
fail
gap> ArtifactDirectory("amtest", "tgz") = d;
false
gap> SetUserPreference("ArtifactManager", "AllowDownloads", true);

#
# Reporting.
#
gap> info := ArtifactInfo("amtest");;
gap> SortedList(List(info, r -> r.name));
[ "big", "broken", "gz", "macos", "mirrored", "symlink", "tgz", "txt", "zip" ]
gap> First(info, r -> r.name = "tgz").status;
"installed"
gap> First(info, r -> r.name = "broken").status;
"absent"
gap> First(info, r -> r.name = "tgz").bytes > 0;
true

#
# A declared tree hash is checked again once the data is unpacked, and lets
# VerifyArtifact re-read the installed files instead of trusting their sizes.
#
gap> tgz := rec(url := AMT_Url("sample.tar.gz"), sha256 := AMT_Sha("sample.tar.gz"));;
gap> DeclareArtifacts("amtree", [
>      rec(name := "good", strip := 1, download := [tgz],
>          tree_sha256 := AM_TreeSHA256(
>              Filename(ArtifactDirectory("amtest", "tgz"), ""))),
>      rec(name := "bad", strip := 1, download := [tgz],
>          tree_sha256 := AMT_WrongSha)]);
gap> FetchArtifact("amtree", "good");
true
gap> VerifyArtifact("amtree", "good", "full");
true
gap> FetchArtifact("amtree", "bad");
false
gap> IsArtifactAvailable("amtree", "bad");
false

# Without one, a full check has nothing to compare against and says so.
gap> VerifyArtifact("amtest", "tgz", "full");
true

#
# Removal.
#
gap> RemoveArtifact("amtest", "tgz");
true
gap> IsArtifactAvailable("amtest", "tgz");
false
gap> RemoveArtifact("amtest", "tgz");
false
gap> RemoveAllArtifacts("amtest") >= 1;
true
gap> ForAny(["zip", "txt", "gz"], n -> IsArtifactAvailable("amtest", n));
false

#
# Overrides: point at a directory we already have, and keep hands off it.
#
gap> OverrideArtifact("amtest", "tgz", AMT_DataDirectory);
true
gap> Filename(ArtifactDirectory("amtest", "tgz"), "") = AMT_DataDirectory;
true
gap> IsArtifactAvailable("amtest", "tgz");
true
gap> RemoveArtifact("amtest", "tgz");
false
gap> IsExistingFile(AMT_File("sample.txt"));
true
gap> VerifyArtifact("amtest", "tgz");
true
gap> UnoverrideArtifact("amtest", "tgz");
true
gap> UnoverrideArtifact("amtest", "tgz");
false
gap> IsArtifactAvailable("amtest", "tgz");
false

#
# Pins.
#
gap> PinArtifact("amtest", "tgz", "wanted for the tests");
true
gap> List(PinnedArtifacts(), p -> [p.package, p.name, p.reason]);
[ [ "amtest", "tgz", "wanted for the tests" ] ]
gap> UnpinArtifact("amtest", "tgz");
true
gap> PinnedArtifacts();
[  ]
gap> UnpinArtifact("amtest", "tgz");
false
gap> SetInfoLevel(InfoArtifactManager, 1);
gap> STOP_TEST("fetch.tst");
