# ArtifactManager: the whole pipeline, over file:// URLs
#
# No network, no forking, no optional packages: this exercises download,
# verification, unpacking, installation, re-use, and removal, and it runs
# everywhere.
#
#@local store, d, p, info, first, i
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

# The tree is exactly what the archive holds -- nothing is stripped, so the
# checksum is one a publisher can reproduce with 'tar xf' and git.
gap> SortedList(Difference(DirectoryContents(Filename(d, "")), [".", ".."]));
[ "sample" ]
gap> StringFile(Filename(d, "sample/hello.txt"));
"hello artifact\n"
gap> StringFile(Filename(d, "sample/sub/inner.txt"));
"inner file\n"

# The second call must not download anything again.
gap> ArtifactDirectory("amtest", "tgz") = d;
true

# The installed data is read-only, but still readable -- an artifact whose
# directories lost their execute bit would be useless.
gap> IsReadableFile(Filename(d, "sample/hello.txt"));
true

#
# A zip archive.
#
gap> d := ArtifactDirectory("amtest", "zip");;
gap> StringFile(Filename(d, "sample/hello.txt"));
"hello artifact\n"

# The zip and the tarball unpack to the same tree, so they are the same
# artifact as far as the store is concerned.
gap> ArtifactDeclaration("amtest", "zip").sha256
>      = ArtifactDeclaration("amtest", "tgz").sha256;
true

#
# Archives built on a Mac carry .DS_Store and AppleDouble files beside the
# real top-level directory.  Those must not stop 'strip' from recognising it,
# or every such tarball would need the consumer to know about the extra level.
# They are kept rather than deleted: we do not throw data away silently.
#
gap> d := ArtifactDirectory("amtest", "macos");;
gap> StringFile(Filename(d, "sample/hello.txt"));
"hello artifact\n"
gap> SortedList(Difference(DirectoryContents(Filename(d, "")), [".", ".."]));
[ ".DS_Store", ".hidden", "sample" ]

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
gap> StringFile(Concatenation(d, "/mirrored"));
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

# The artifact name is the file name, so an author who wants GAP's
# transparent decompression names the artifact accordingly.
gap> p := ArtifactFile("amtest", "sample.txt.gz");;
gap> EndsWith(p, ".gz");
true
gap> StringFile(p);
"plain artifact\n"

# The same download, decompressed on install instead, is a different artifact.
gap> p := ArtifactFile("amtest", "gunzipped");;
gap> EndsWith(p, ".gz");
false
gap> StringFile(p);
"plain artifact\n"

# Without a relative path this only works for a file artifact.
gap> ArtifactFile("amtest", "tgz");
Error, the artifact 'amtest/tgz' is a directory; say which file inside it you \
want
gap> StringFile(ArtifactFile("amtest", "tgz", "sample/sub/inner.txt"));
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
gap> ArtifactContents("amtest", "sample.txt.gz");
"plain artifact\n"
gap> ArtifactContents("amtest", "tgz");
Error, the artifact 'amtest/tgz' is a directory; use ArtifactDirectory instead\
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
Error, every source for amtest/big is at least 1.0 TB, which is more than the \
1.0 kB that may be downloaded automatically.  Run  FetchArtifact("amtest", "bi\
g");  to download it, or raise the user preference ArtifactManager/MaxAutoDown\
loadSize.

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
[ "big", "broken", "gunzipped", "macos", "mirrored", "sample.txt.gz", 
  "symlink", "tgz", "txt", "zip" ]
gap> First(info, r -> r.name = "tgz").status;
"installed"
gap> First(info, r -> r.name = "broken").status;
"absent"
gap> First(info, r -> r.name = "tgz").bytes > 0;
true

#
# A tree hash that does not match is refused, exactly like a bad checksum:
# the data is dropped and nothing is installed.
#
gap> DeclareArtifacts("amtree", [
>      rec(name := "bad", tree_sha256 := AMT_WrongSha,
>          download := [rec(url := AMT_Url("sample.tar.gz"), format := "tar.gz",
>                           sha256 := AMT_Sha("sample.tar.gz"))])]);
gap> FetchArtifact("amtree", "bad");
false
gap> IsArtifactAvailable("amtree", "bad");
false

# A full check re-reads the installed files instead of trusting their sizes --
# against the tree hash for an archive, against 'sha256' for a single file.
gap> VerifyArtifact("amtest", "tgz", "full");
true
gap> VerifyArtifact("amtest", "sample.txt.gz", "full");
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
gap> ForAny(["zip", "txt", "gunzipped"], n -> IsArtifactAvailable("amtest", n));
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
