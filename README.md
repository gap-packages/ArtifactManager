# The GAP package ArtifactManager

Many GAP packages come with large data sets. Shipping them inside the package
archive makes the package huge for everybody, including the people who never
touch the data. The usual alternatives are worse: telling users to download a
tarball by hand and unpack it in exactly the right place, or writing a
download function per package — and today essentially none of those verify
what they downloaded.

ArtifactManager offers a common mechanism instead. A package declares its
**artifacts** — named blobs of data living on a web server — in a file
`artifacts.json` next to its `PackageInfo.g`. When the package first needs
one, ArtifactManager downloads it, verifies it against the declared SHA256
checksum, unpacks it, and hands back a directory. The data is cached where the
user wants it, and can be listed and removed again.

This addresses [gap-system/gap#4285](https://github.com/gap-system/gap/issues/4285).

**Status: early.** The on-disk format is settled, but the feature set is not
complete — see [Limitations](#limitations) below.

## For users

```gap
gap> LoadPackage("ArtifactManager");
gap> ShowArtifacts();
package   artifact  status     size  description
------------------------------------------------
transgrp  dat32     installed  312.3 MB  Transitive groups of degree 32
transgrp  dat48     absent     (30.0 GB) Transitive groups of degree 48

total on disk: 312.3 MB
```

Useful things to know:

* `RemoveArtifact("transgrp", "dat32")` reclaims the space; the data is
  downloaded again next time it is needed.
* By default the store is `~/.gap/artifacts`. Set the user preference
  `ArtifactManager/ArtifactStore`, or the environment variable
  `ARTIFACTMANAGER_STORE`, to move it. On a shared machine the environment
  variable is the better knob, since it needs no per-user configuration.
* Anything bigger than 1 GB is not downloaded automatically; you get an error
  telling you to call `FetchArtifact` explicitly. Change this with the
  `MaxAutoDownloadSize` preference.
* `AllowDownloads := false` works offline.
* `OverrideArtifact("transgrp", "dat48", "/scratch/trans48")` points GAP at a
  copy you already have. ArtifactManager will then never download, verify or
  delete it.
* `ArtifactStoreDiagnostics()` says what it found and what it is missing.

## For package authors

Add `artifacts.json` to your package's root directory:

```json
{
  "gapArtifactManifestVersion": 1,
  "package": "transgrp",
  "artifacts": {
    "dat32": {
      "description": "Transitive groups of degree 32",
      "license": "GPL-2.0-or-later",
      "tree_sha256": "bbbb...",
      "download": [
        { "url": "https://example.org/trans32.tar.gz",
          "sha256": "aaaa...", "size": 314572800, "format": "tar.gz" },
        { "url": "https://mirror.example.org/trans32.tar",
          "sha256": "cccc...", "format": "tar" }
      ]
    }
  }
}
```

`DescribeArtifactURL("https://example.org/trans32.tar.gz", "dat32", "tar.gz")`
downloads
and unpacks the file once and prints the stanza above with everything filled
in. Use it rather than writing the file by hand: `tree_sha256` comes from
nowhere else.

That checksum is of the data as installed, not of what was downloaded, which
is why the two sources above can be compressed or not and still be one
artifact. For a single file, declare `file_sha256` instead — that is all that
distinguishes the two kinds. Tree checksums are git's, with SHA256 in place of
SHA1, so you can check one against `git init --object-format=sha256`.

`ValidateArtifacts("transgrp")` fetches every source and checks it against the
manifest; it belongs in CI, since a silently re-uploaded mirror otherwise only
breaks for whoever downloads it.

Then, in your package code, replace whatever you did before with:

```gap
dir := ArtifactDirectory("transgrp", "dat32");
f   := Filename(dir, "trans32.grp");
```

`ArtifactDirectory` downloads on the first call and returns immediately after
that. It raises an error if the data cannot be provided, and the error says
what to do about it. Use `IsArtifactAvailable` if you would rather decide for
yourself — it never downloads and never raises.

Add ArtifactManager to `NeededOtherPackages` if your package cannot work
without its data, or to `SuggestedOtherPackages` and guard the calls with
`IsPackageLoaded("artifactmanager")` if the data is optional.

The full field reference is in the manual, chapter "Declaring artifacts".

## What it does about integrity

* Checksums are verified **before** anything is unpacked, so no untrusted
  bytes ever reach `tar`.
* Archives are listed before extraction and rejected if any member has an
  absolute path or a `..` component.
* An artifact's directory name contains its checksum, so a changed declaration
  installs somewhere new. A stale cache cannot be mistaken for current data.
* Because of that, two GAP sessions installing the same artifact at once can
  only produce identical bytes, so no locking is needed; the loser of the race
  simply uses the winner's copy.
* An interrupted download leaves at most a directory under `<store>/tmp`,
  never a half-installed artifact. `CleanArtifactTemp()` sweeps those up.
* Sources are tried in order, so a mirror that has gone bad is skipped.
* Download backends that do not follow HTTP redirects are used only as a last
  resort, because a redirect silently returning an empty body is exactly how
  data downloads broke when servers moved from http to https.

## Limitations

* **Artifacts up to about 1 GB.** The pieces needed for very large data
  (streaming downloads, resumable transfers, hashing a file without an
  external helper) are missing from GAP and from the packages we build on.
  Issues have been filed; see `dev/upstream.md`. Until they land, something
  like transgrp's 30 GB degree-48 data is out of scope, and pretending
  otherwise would only produce a path that runs out of memory on the wrong
  backend and restarts from zero on any interruption.
* **No garbage collection yet.** `RemoveArtifact` and `RemoveAllArtifacts`
  cover reclaiming space by hand, and `ShowArtifacts` marks data that no
  installed package asks for any more as `stale`. Collecting it automatically
  is the next piece of work; the last-use times it will need are already being
  recorded, and `PinArtifact` already exists so that anything you pin now is
  safe by the time it arrives.
* **One artifact, one archive.** Fetching individual files out of a large
  remote collection — what AtlasRep needs — is planned but not implemented.
* Windows support is best effort and untested.

## Requirements

GAP 4.13 or newer, and the [utils](https://github.com/gap-packages/utils)
package for downloading.

The [IO](https://github.com/gap-packages/io) package is strongly recommended.
It is not required, but without it several things GAP itself cannot do — file
sizes, atomic renames, reading a file as raw bytes, telling the time — have to
be done by running external programs instead.

## Contact

Please report issues at
<https://github.com/gap-packages/ArtifactManager/issues>.

## License

This package is distributed under the terms of the GNU General Public License
v2.0 or later. This is also the license used by GAP itself and by many GAP
packages.
