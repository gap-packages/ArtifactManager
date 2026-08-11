> **Historical.** This is the plan as approved, before implementation.
> Four things changed while building it:
>
> - The `json` package delegation was dropped. One parser, always ours: two
>   would mean two sets of edge cases. `json` is no longer even suggested.
> - `AM_Download` ranks backends rather than just filtering one out. IO's
>   `SingleHTTPRequest` reports a 302 as a successful download of an empty
>   body, so it had to go last, not just after curlInterface.
> - `strip` ignores dot-entries, because real tarballs carry `.DS_Store` and
>   AppleDouble files beside the top-level directory.
> - `DescribeArtifactURL` sniffs magic bytes; Zenodo URLs end in `/content`
>   and carry no usable extension.
>
> Current state lives in `README.md` and `dev/upstream.md`.

# ArtifactManager — MVP plan, and the upstream work it should drive

## Context

[gap-system/gap#4285](https://github.com/gap-system/gap/issues/4285) asks for a Julia-artifacts-like
mechanism so GAP packages stop bundling huge data: declare an artifact, have it downloaded on
demand, verified by checksum, cached somewhere user-configurable, listed with its disk usage, and
eventually garbage-collected.

Today every data package solves this alone, badly. Verified survey of the tree:

- **No verification anywhere except AtlasRep.** PackageManager, GAPDoc, FactInt, StandardFF,
  unitlib, resclasses download and trust.
- **Four hand-rolled wget/curl fallback chains** (utils, PackageManager, GAPDoc, FactInt/StandardFF).
- **FactInt and StandardFF ship near-identical Brent-factor fetchers** whose URLs users are told to
  hand-edit as new data drops appear.
- **Hardcoded personal-webspace URLs** (`~hulpke`, `~Thomas.Breuer`, `alexk.host.cs.st-andrews.ac.uk`),
  repeated across README, error string and code.
- **transgrp/primgrp tell users to untar into the package directory by hand**; availability is
  `IsReadableFile` probing, with no version and no integrity.
- **FactInt/StandardFF write into the GAP installation tree**, requiring write access to it.
- **AtlasRep is the one good citizen** and documents its own hole at `atlasrep/gap/access.gd:651`:
  a cached file is never re-validated against its checksum on read, so corruption is permanent.

Intended outcome: one package that all of these can adopt, where transgrp's diff is *one new file
plus one changed call*.

Requirements from the issue and Thomas Breuer's comments: mirrors and retries; a disk-usage overview;
cleanup/GC; per-file on-demand fetch for AtlasRep-scale collections; a "fetch without storing locally"
mode; storage configurable *per database* and explicitly not the package directory, with `~/.gap` a
reasonable default but wrong for multi-user installs; and a `mkdir -p`-with-permission-fixing helper.

## The stance on workarounds

Building this exposes a set of genuine gaps in GAP core and in neighbouring packages. The MVP works
around them so it can ship — but **every workaround below is paired with an upstream fix**, and the
plan schedules both. Where the workaround is bad enough that the feature shouldn't be claimed, the
feature is descoped rather than hacked:

> **The MVP targets artifacts up to roughly 1 GB.** That covers simpcomp (239 MB), tomlib, unitlib,
> primgrp, FactInt/StandardFF, and transgrp's `dat32` (~300 MB) — i.e. every candidate consumer but
> one. **transgrp's 30 GB `dat48` is explicitly out of scope until the upstream fixes land**
> (streaming download in curlInterface, resumable transfers in utils, chunked file hashing in core).
> Pretending otherwise would mean shipping a 30 GB path that OOMs on the wrong backend and re-downloads
> from zero on any interruption.

See [Upstream work](#upstream-work) for the full list.

## Decisions already settled

| Question | Decision |
|---|---|
| Declaration | Conventional `<InstallationPath>/artifacts.json`, self-versioned. No `PackageInfo.g` change. Runtime `DeclareArtifacts` as escape hatch. |
| Format | JSON — `json` package when loadable, vendored pure-GAP parser otherwise. Never a hard dependency. |
| v0.1 scope | Whole-artifact fetch + pins, ≤ ~1 GB. GC in v0.2, per-file/tree artifacts in v0.3. |
| Store key | `<store>/artifacts/<pkg>/<name>-<first16 of sha256>/` — content-addressed but human-readable. |
| GC policy | Reachability decides safety (grace period ~7 days); recency sweep is explicit opt-in. **v0.1 must already record last-used timestamps.** |

## Upstream work

This is a deliverable of the project, not a footnote. Items marked **blocking** gate a feature we
have descoped until they land.

### GAP core

| # | Gap | Evidence | Action |
|---|---|---|---|
| U1 | **No wall-clock time.** `Runtime()` is CPU time; there is no way to get the current date/time without `io` or shelling out to `date`. | needed for last-used stamps (v0.1) and orphan timestamps (v0.2) | File an issue and propose `CurrentUnixTime()` (or similar). Small, self-contained, clearly belongs in core. **Blocking** for recency tracking — until it exists, `AM_Now()` degrades to `IO_gettimeofday` → `date +%s` → skip-with-warning. |
| U2 | **No file hashing.** `HexSHA256(<stream>)` does `ReadAll` — the whole file into memory. The source carries the TODO itself at `lib/files.gi:402-405`. | the kernel already has `GAP_SHA256_INIT`/`UPDATE`/`FINAL` (`src/sha256.c`); only a chunked driver is missing | Propose **`HexSHA256File(<filename>)`**, hashing in chunks, binary-safe. This single addition removes our entire three-tier hashing fallback and the practical need for `io`. **Blocking** for large artifacts. |
| U3 | **`Process` cannot capture stderr.** | [gap#4657](https://github.com/gap-system/gap/issues/4657), open | Help resolve. Without it we cannot report *why* `tar`/`unzip`/`sha256sum` failed, only that it did — the difference between an actionable error and "exit code 2". |
| U4 | **No safe, ergonomic process runner.** `Exec` goes through a shell; `Process` is correct but clumsy. | [gap#5103](https://github.com/gap-system/gap/pull/5103), an open draft PR adding `Exec2`: real argv, no shell, returns a record with the exit code and captured output | Finish that PR. Our `AM_Exec` is a strictly worse version of it and should be deleted once `Exec2` exists. Pairs naturally with U3. |
| U5 | **No `mkdir -p`, and no way to fix permissions.** `CreateDir` is a single-level `mkdir(2)`. | fingolfin asked for exactly this in #4285 itself; `AutoDoc_CreateDirIfMissing` and `PKGMAN_CreateDirRecursively` are two partial reimplementations | Propose `CreateDirectoryRecursively` for core, with the good-error and permission-fixing behaviour. We implement it first here, then upstream it. |
| U6 | **No binary-safe file reading.** `StringFile` goes through `InputTextFile`, which normalises CRLF and transparently gunzips `.gz` — documented as unsafe for binary data (`lib/streams.gd:645-652`). | forces us to name staged downloads `blob` so nothing silently gunzips them | File an issue: core should offer a raw-bytes read. Largely subsumed by U2 for our purposes, but it is a real trap for everyone else. |
| U7 | **No file size or mtime.** | needed for the disk-usage overview and cheap re-verification | Issue: add `FileSize` / a `FileStat`-like function. |
| U8 | **No rename/move.** Atomic same-filesystem rename is the whole basis of a lock-free install, and it currently requires `io` or shelling out to `mv`. | | Issue/PR: add `RenameFile`. |
| U9 | **`CreateDir`, `RemoveDir`, `RemoveDirectoryRecursively` are undocumented** despite being the obvious tools for this job. | | Documentation PR. Cheap, and it makes U5/U8 easier to argue. |

Taken together U1–U8 would let ArtifactManager drop `io` entirely and shrink `gap/compat.gi` to almost
nothing. That is the right long-term shape: **a data-management package should not need a compiled
dependency to hash a file or move it.**

### utils

| # | Gap | Evidence | Action |
|---|---|---|---|
| U10 | **`Download` mutates the caller's `opt` record.** | `utils/lib/download.gi` assigns `opt.verifyCert`/`opt.maxTime` in place | Issue + one-line PR (`ShallowCopy`). |
| U11 | **Inconsistent partial-file cleanup.** `wget` removes the partial target on failure; `curl` does not. | `utils/lib/download.gi:177-180` vs the curl backend | Issue + PR: make failure behaviour uniform. `utils`' own `tst/download.tst` already admits the backends "do not behave consistently in the case of failure… which makes them useless as automatic tests" — that admission *is* the bug report. |
| U12 | **No resume support.** A killed 30 GB transfer restarts from zero. | | Contribute a backend using `curl -L -C - --retry`, or a `resume` option. **Blocking** for large artifacts. |
| U13 | **`Download_Methods` is the documented extension point but backends advertise no capabilities**, so callers must hardcode backend names to avoid one. | we currently must string-match the curlInterface backend to skip it — exactly the kind of hack this section exists to eliminate | PR: add a capability record per backend (`streamsToFile`, `supportsTimeout`, `followsRedirects`, `supportsHttps`), and document the extension point. Then our selection becomes declarative. |
| U14 | **No progress reporting**, so a multi-minute download looks like a hung GAP. | | Propose a progress-callback option. |

### curlInterface

| # | Gap | Evidence | Action |
|---|---|---|---|
| U15 | **`DownloadURL` buffers the entire response body in RAM** and returns it as a GAP string; there is no way to stream to a file. The utils backend then writes that string out with `FileString`. | `curlInterface/gap/curl.gi`, and `utils/lib/download.gi:44-48` | **This is the real fix for the 30 GB problem.** Add an API that passes a `FILE*` via `CURLOPT_WRITEDATA` so libcurl writes straight to disk. Then utils' preferred backend becomes the *best* one for large files instead of the worst, and our workaround (U13-based backend filtering) disappears. **Blocking.** |

### PackageManager

| # | Gap | Evidence | Action |
|---|---|---|---|
| U16 | **`PKGMAN_Exec` joins args with spaces and runs them through `sh -c`.** Any path with a space breaks; any path with a metacharacter injects. | `PackageManager/gap/PackageManager.gi:296-298` | Issue + PR: switch to `Process`, or to `Exec2` once U4 lands. This is why we cannot reuse `PKGMAN_ExtractArchive`. |
| U17 | **No checksum verification of downloaded package archives at all.** | `grep -i "sha\|checksum\|md5"` over `PackageManager/gap/` and `doc/` returns nothing | Issue. Longer term PackageManager can verify against the PackageDistro metadata, or delegate to ArtifactManager. |
| U18 | **Weak archive safety.** `PKGMAN_TarTopDirectory` only enforces "exactly one top-level directory"; it does not reject absolute paths or `..` members. | `PackageManager/gap/archive.gi:87-93` — currently the ecosystem's *only* tarbomb guard | Contribute the stricter guard we write here back to PackageManager. |

### Sequencing

None of U1–U18 blocks v0.1 as scoped (≤ 1 GB artifacts). U2, U12 and U15 together are what unblock
`dat48`, and are the highest-value items. U3+U4 improve every error message in the package and are
also the easiest to land, since [gap#5103](https://github.com/gap-system/gap/pull/5103) already exists
as a draft. File the issues **at the start** of implementation, not the end, so the workarounds are
documented as temporary from the first commit — each one gets a `# TODO(U<n>): remove once <link>`
comment at its call site.

## Verified facts the design depends on

- `HexSHA256(<string>|<stream>)` exists from GAP 4.12 (`lib/files.gd:851`). **In 4.12–4.15 it drops
  leading zero hex digits**; padding added only in 4.16 (`gap-4.16.0/lib/files.gi:415-419`; compare
  `gap-4.13.0/lib/files.gi:422`, a bare `LowercaseString(HexStringInt(res))`). We target ≥ 4.13, so
  left-padding to 64 chars on **both** stored and computed values is mandatory — precedent
  `AGR_ChecksumFits`, `atlasrep/gap/access.gi:61-86`.
- `utils`' `Download(url[, opt])` — `opt.target` writes straight to a file; returns
  `rec(success := true, result := <string>)` / `rec(success := true)` / `rec(success := false, error := <string>)`.
  See U10, U11, U13 for its defects.
- The IO backend is `http://`-only and follows no redirects.
- `CreateDir` is `mkdir(2)` returning `fail` on EEXIST (`src/streams.c:1060-1066`) — a usable atomic
  create-if-not-exists primitive for lock directories, no `io` needed.
- `io` supplies `IO_stat`, `IO_rename`, `IO_mkdir`, `IO_chmod`, `IO_File`/`IO_read`, `IO_getpid`,
  `IO_gettimeofday` — i.e. the stand-in for U1, U2, U6, U7, U8.
- The `transgrp` consumer shape is `Filename(DirectoriesPackageLibrary("transgrp","dat32"), ...)`
  (`transgrp/lib/trans.grp:279-284,470`). The most important API is therefore *"give me a `Directory`"*.

## Dependencies

```gap
Dependencies := rec(
  GAP := ">= 4.13",
  NeededOtherPackages := [ [ "utils", ">= 0.77" ] ],
  SuggestedOtherPackages := [ [ "IO", ">= 4.7" ], [ "json", ">= 2.0" ] ],
),
```

- **utils: Needed.** Pure GAP, no compilation, and `utils/lib/download.gd:8-10` states outright that
  `Download` exists to replace per-package downloaders. Reimplementing four backends is the exact
  duplication #4285 complains about — so we improve utils (U10–U14) rather than route around it.
- **io: Suggested.** Purely a stand-in for missing core functionality (U1, U2, U6, U7, U8). Each use has
  a fallback. **The goal is to drop this dependency once those land** — track it explicitly.
- **json: Suggested.** It is a kernel extension; requiring compilation for a package whose point is
  universal adoptability is self-defeating, and AtlasRep already paid this cost by shipping its own
  parser. Vendor a parse-only pure-GAP fallback; delegate to `json` when present.

Degradation is always to *working but louder*, never to *silently unsafe*. One hard stop: if no
binary-safe hashing route exists at all, **refuse to install** rather than trust an unverified download.

## Declaration format — `<pkgdir>/artifacts.json`

```json
{
  "gapArtifactManifest": 1,
  "package": "transgrp",
  "artifacts": {
    "dat32": {
      "description": "Transitive groups of degree 32",
      "version":     "1.0",
      "size":        314572800,
      "license":     "GPL-2.0-or-later",
      "provenance":  "https://doi.org/10.5281/zenodo.5935751",
      "lazy":        true,
      "strip":       1,
      "download": [
        { "url": "https://zenodo.org/records/5935751/files/trans32.tar.gz",
          "sha256": "aaaa…", "format": "tar.gz", "size": 300000000 },
        { "url": "https://www.math.colostate.edu/~hulpke/transgrp/trans32.tgz",
          "sha256": "aaaa…", "format": "tar.gz", "size": 300000000 }
      ]
    }
  }
}
```

- `download` is an ordered list of **alternatives** — mirrors and format variants share one mechanism,
  each with its own `sha256` (Julia's `download` array; AtlasRep's
  `AtlasOfGroupRepresentationsTransferFile` already takes a URL *list*, `atlasrep/gap/access.gi:130`).
  Identical `sha256` ⇒ pure mirrors sharing one store path. Different `sha256` ⇒ different paths;
  `ArtifactDirectory` checks each candidate in turn.
- `format` ∈ `tar.gz` `tar.bz2` `tar.xz` `tar` `zip` `file` `file.gz`. `file.gz` is stored **still
  compressed** — `StringFile` gunzips transparently, so this is free savings and zero code.
- `size` lets `ShowArtifacts` say "would cost 300 MB" *before* downloading, and is what
  `MaxAutoDownloadSize` vetoes against.
- `license` / `provenance` cost nothing now and cannot be retrofitted later.

**Forward-compatibility rules — pin these in v0.1 and test them.** `gapArtifactManifest` above the
supported maximum ⇒ skip the whole manifest with a warning naming the version needed, never a parse
error. Unknown top-level and per-artifact keys ⇒ ignored at `Info` level 3. Unknown `kind` (reserved
for v0.3 `"tree"` artifacts) ⇒ skip that artifact only. We never emit `null`, sidestepping the json
package's `null ↔ fail` ambiguity.

**Discovery**: iterate `GAPInfo.PackagesInfo` (all names, all versions — GAP populates this at startup
from every root path, with `InstallationPath`, without loading anything), probe
`<InstallationPath>/artifacts.json`, parse lazily, memoise.

Runtime escape hatch for computed URLs and generated families: `DeclareArtifacts(<pkgname>, [<rec>, …])`.
Documented caveat: runtime declarations are **not GC roots** — use `PinArtifact` for persistence.

## Store layout

```
<store>/
  CACHEDIR.TAG                              # backup tools skip the tree
  store-info.g                              # rec( storeFormat := 1, createdAt := … )
  artifacts/<pkg>/<name>-<hash16>/          # payload, kept clean of our bookkeeping
  meta/<pkg>/<name>-<hash16>.g              # rec(...); PRESENCE IS THE INSTALLED MARKER
  used/<pkg>/<name>-<hash16>.g              # rec( lastUsed := … ); one small file per artifact
  pins.g
  overrides.g
  roots.d/<sha256-of-path>.g                # observed out-of-tree package locations (v0.2 GC)
  logs/                                     # v0.2: orphans.g, gc.log
  tmp/                                      # staging — sibling of artifacts/, hence same filesystem
```

`hash16` = first 16 hex chars of the downloaded archive's sha256. Three properties follow, and are the
reason for the layout:

1. **A changed checksum installs to a new path.** A stale cache is structurally incapable of being
   mistaken for current data — this closes AtlasRep's `access.gd:651` hole without re-hashing on read.
2. **Two sessions racing to install can only produce identical bytes**, so losing the race is success
   and no lock is needed on the install path.
3. **`tmp/` is a sibling of `artifacts/`**, so the final rename is same-filesystem and atomic. Get this
   wrong and `mv` silently degrades to a non-atomic `cp`.

Metadata is a **sibling file, not a dotdir inside the payload**, so consumers listing the artifact
directory see only their data. The meta write is the commit point: payload rename first, meta second.
A payload without meta is a crashed install — invisible to resolution, swept by `CleanArtifactTemp()`.

`used/` is one file per artifact rather than one log, so concurrent sessions never contend and no
locking is needed. Written at most once per artifact per session. **This is the v0.1 obligation that
enables the v0.2 recency sweep** — history cannot be reconstructed later. Depends on U1.

**Store composition**: read from all stores, write only to the first writable one (Julia's depot rule).
A read-only `/usr/share/gap/artifacts` populated by a sysadmin becomes a free cache layer with no extra
mechanism — Breuer's multi-user concern solved by ordering rather than a new feature.

## Directory-choice policy

`AM_DefaultStore()`, in order, each step falling through on failure:

1. `$ARTIFACTMANAGER_STORE` — **the multi-user answer**: settable in a module file or container image
   without touching anyone's `gap.ini`.
2. Julia scratchspace inside Julia/Oscar: `IsPackageLoaded("JuliaInterface")` and
   `IsBoundGlobal("GetJuliaScratchspace")` ⇒ `GetJuliaScratchspace("gap_artifacts")`. Mirrors
   `atlasrep/gap/userpref.g:107-127`; leaves Oscar's own GC in charge.
3. `GAPInfo.UserGapRoot <> fail` ⇒ `<UserGapRoot>/artifacts`.
4. `$XDG_DATA_HOME/gap/artifacts`, else `$HOME/.local/share/gap/artifacts` — the `gap -r` path where
   `UserGapRoot = fail`.
5. `""` — RAM/session mode: downloads land in `DirectoryTemporary()` and vanish at exit, with a
   level-1 `Info` saying so and how to fix it.

Never the package directory (Breuer's explicit objection — note AtlasRep's default *does* use it, so we
deliberately do not inherit that). Never a shared system directory by default.

### User preferences (`gap/prefs.g`, package `"ArtifactManager"`)

| name | default | purpose |
|---|---|---|
| `ArtifactStore` | computed (above) | main store; `""` = session-only |
| `ExtraArtifactStores` | `[]` | read-only site stores, searched not written |
| `ArtifactStoreOverrides` | `rec()` | **per-database** location, e.g. `rec(atlasrep := "/scratch/atlasrep")` — Breuer's requirement |
| `AllowDownloads` | `true` | `false` = work offline |
| `MaxAutoDownloadSize` | `1000000000` | above this, an explicit `FetchArtifact` is required; `0` = no limit |
| `CollectDelay` | `7` | days unreachable before v0.2 GC deletes |
| `MakeReadOnly` | `true` | chmod installed artifacts read-only (needs `io`; see U-list) |

Follow AtlasRep's `default := <function>` pattern (`atlasrep/gap/userpref.g:100-138`), including its
early return when a value is already stored — user preferences recompute defaults even when set.

Env escape hatches overriding preferences: `ARTIFACTMANAGER_STORE`, `ARTIFACTMANAGER_STORE_<PKGNAME>`,
`ARTIFACTMANAGER_OFFLINE`.

## Public API (v0.1)

```gap
# declaring — package authors
DeclareArtifacts( <pkgname>, <list> )       # runtime registration; validates, ErrorNoReturn on bad schema
ArtifactDeclaration( <pkg>, <name> )        # -> record or fail
AllArtifactDeclarations( [<pkg>] )          # -> list of records

# using — package code
ArtifactDirectory( <pkg>, <name> )          # -> Directory; downloads if needed; Errors with a fix
ArtifactFile( <pkg>, <name>[, <relpath>] )  # -> filename string
IsArtifactAvailable( <pkg>, <name> )        # -> bool; never downloads, never errors
FetchArtifact( <pkg>, <name> )              # -> true/false; explicit, ignores MaxAutoDownloadSize
ArtifactContents( <pkg>, <name> )           # -> string; fetch without storing  [Breuer]

# managing — end users
ShowArtifacts( [<pkg>] )                    # table + total disk usage
ArtifactInfo( [<pkg>] )                     # machine-readable form of the above
VerifyArtifact( <pkg>, <name>[, <level>] )  # "marker" | "quick" (default) | "full"
RemoveArtifact( <pkg>, <name> ) / RemoveAllArtifacts( [<pkg>] )
PinArtifact( <spec>[, <reason>] ) / UnpinArtifact( <spec> ) / PinnedArtifacts()
OverrideArtifact( <spec>, <path> ) / UnoverrideArtifact( <spec> )
ArtifactStoreDirectory( ) / ArtifactStoreDiagnostics( ) / CleanArtifactTemp( )

# publishing helper — this is what actually drives adoption
DescribeArtifactURL( <url> )                # prints a paste-ready JSON stanza with sha256 + size

# general utility (fingolfin asked for this by name; upstream candidate U5)
CreateDirectoryRecursively( <path> )
```

- **`ArtifactDirectory` errors deliberately** — consumers like transgrp want a path or a stop. The
  message names the artifact, every URL tried with its error, and the exact next step
  (`FetchArtifact("transgrp","dat32");` or the preference to set). `IsArtifactAvailable` is the probe
  for code that wants to branch.
- **`ArtifactContents`** downloads to a temp dir, verifies, returns bytes, deletes — Breuer's "just
  fetch remote data without storing locally", and the shape a v0.3 per-file artifact needs.
- **Overrides short-circuit everything.** `ArtifactDirectory` returns the override path;
  `FetchArtifact`/`VerifyArtifact`/`RemoveArtifact` refuse with an explanation. This is what stops
  `RemoveArtifact` deleting a sysadmin's `/opt/gapdata`.
- `ArtifactInfo` status ∈ `installed` `absent` `overridden` `pinned` `stale` `incomplete`. **`stale`** =
  a payload whose hash matches no current declaration; it makes "which GB can I delete" answerable in
  v0.1, before GC exists.

Ship **pins in v0.1, before GC**, so pins predate collection.

## Fetch pipeline — `AM_Install(decl)`

1. **Resolve.** Override? return. Any candidate `sha256` already installed (payload **and** meta present,
   in any store)? touch `used/`, return. No lock on this path.
2. **Gate.** `AllowDownloads = false` ⇒ error "offline mode". `size > MaxAutoDownloadSize` and not called
   via `FetchArtifact` ⇒ error naming the size and the explicit call to make.
3. **Stage.** `<store>/tmp/am-<pid>-<n>/`, via `CreateDirectoryRecursively`, write-probed. Not writable
   ⇒ fall back to `DirectoryTemporary()` with a level-1 warning naming the unwritable path.
4. **Download** to `<staging>/blob` — **deliberately no `.gz`/`.tar` suffix**, so nothing downstream
   silently gunzips it *(workaround for U6)*. Per `download` entry, up to 3 attempts with backoff, then
   the next entry.
   - `file://` handled by us, not by `Download` — the IO backend rejects non-http. Both a real feature
     (shared NFS mirror) and the backbone of network-free testing.
   - Fresh option record per call *(workaround for U10)*.
   - `RemoveFile(target)` before every retry *(workaround for U11)*.
   - Backend selection: prefer one that streams to a file. Until U13 lands this means matching backend
     names to skip the RAM-buffering curlInterface path; afterwards it becomes a capability query, and
     after U15 the preference inverts entirely. Mark the site `# TODO(U13/U15)`.
5. **Verify sha256 before `tar` ever sees the bytes.** Non-negotiable. Mismatch ⇒ delete, `Info` expected
   vs actual, **continue to the next mirror** (a corrupt mirror is what mirrors are for). All mirrors
   mismatch ⇒ error. Never install unverified bytes.
6. **Inspect, then extract.** `tar -tf` first; reject any member whose path is absolute or contains a
   `..` component — strictly stronger than `PKGMAN_TarTopDirectory`, and the thing to contribute back
   as U18. Extract into `<staging>/payload`; apply `strip`.
7. **Measure** size and file count while walking (`IO_stat`, else `du -sk`, else `fail` — see U7).
8. **Install.** `AM_Rename(<staging>/payload, <store>/artifacts/<pkg>/<name>-<hash16>)` (see U8).
   Destination exists ⇒ **we lost a race ⇒ success**; discard staging. Retry with backoff up to 5 times
   for Windows AV holding handles. Then write meta — **the commit point**. Then `used/`.
9. **Clean up** staging on every path, including every error path.

Kill at any point leaves at most one orphan dir under `<store>/tmp/`, never a partial artifact at a
valid path. `CleanArtifactTemp()` sweeps those plus meta-less payloads.

## Extraction and process execution

Write our own; do **not** depend on or vendor PackageManager's, for the reasons in U16/U18.

```gap
AM_Exec( <dir>, <prog>, <args> )   # -> rec( code, output )   # TODO(U4): replace with Exec2
```
`prog` resolved with `PathSystemProgram` (`fail` ⇒ actionable error naming the missing tool), run via
`Process(dir, prog, InputTextNone(), OutputTextString(out, true), args)` — a real argv, **no shell**.
stderr is lost until U3 lands, which is exactly why U3 matters: today a failing `tar` gives us an exit
code and nothing else.

- `tar*` ⇒ `tar -xf <blob> -C <payload> --no-same-owner`
- `zip` ⇒ `unzip -q -o`, falling back to `tar -xf` (bsdtar on macOS/Win10, not GNU tar)
- `file` ⇒ move to `<payload>/<filename>`; `file.gz` ⇒ same, left compressed
- `strip := 1` with exactly one top-level directory ⇒ hoist its contents; otherwise `Info` a warning and
  leave it (the maintainer set a hint, not a contract)

## Hashing

`AM_HexSHA256File(<file>)` — a temporary shim whose whole existence is U2:

1. **`io`**: `IO_File` + `IO_read` in 1 MB chunks into `GAP_SHA256_INIT`/`UPDATE`/`FINAL`, formatting the
   8 words to 64 lowercase hex. Binary-safe, constant memory.
2. **External**: `sha256sum` → `shasum -a 256` → `openssl dgst -sha256`.
3. **Last resort**: `HexSHA256(StringFile(f))`, level-1 warning, hard cap ~64 MB. Safe only because the
   staged file is named `blob`.

Once `HexSHA256File` exists in core, all three collapse into one call. Structure the shim so that
deletion is a one-line change.

`AM_NormalizeHex(h)` left-pads to 64 and lowercases, applied to **both** stored and computed values,
**and to declaration values at parse time**, so a maintainer who generated a checksum on GAP 4.14
doesn't ship a 63-char string. Forbid bare `HexSHA256` calls elsewhere; enforce by test.

## Verification tiers

| level | check | cost |
|---|---|---|
| `marker` (every resolve) | payload dir + meta file exist | O(1) |
| `quick` (`VerifyArtifact` default) | recorded size and file count still match | seconds |
| `full` | re-hash — v0.2, needs a per-file manifest | O(bytes), opt-in |

Content-addressing already eliminates the *stale-cache* class AtlasRep suffers from. What remains is
post-install corruption, which `quick` catches. Full re-verification needs a per-file manifest and is
deferred rather than faked.

## Files to create

Replace the PackageMaker skeleton. Delete `ArtifactManager_Example` from
[gap/ArtifactManager.gd](gap/ArtifactManager.gd) and [gap/ArtifactManager.gi](gap/ArtifactManager.gi),
keeping those files as the doc-chapter anchor and the home of `InfoArtifactManager`.

| file | contents |
|---|---|
| `gap/compat.gd/.gi` | **the shim layer for U1–U8** — `AM_Now`, `AM_Rename`, `AM_Stat`, `AM_Exec`, `AM_HaveIO`, `CreateDirectoryRecursively`. Every function here carries a `# TODO(U<n>)` naming the upstream issue that deletes it. Keeping them in one file makes the shrinking visible. |
| `gap/prefs.g` | the `DeclareUserPreference` records |
| `gap/json.gd/.gi` | `AM_JsonToGap` + delegation to the `json` package |
| `gap/hash.gd/.gi` | `AM_HexSHA256File`, `AM_NormalizeHex` |
| `gap/store.gd/.gi` | store discovery/composition, paths, `CACHEDIR.TAG`, meta/used/pins/overrides IO, `CleanArtifactTemp`, `AM_AssertInStore` |
| `gap/declare.gd/.gi` | manifest parse + version gate + schema validation, `DeclareArtifacts`, discovery over `GAPInfo.PackagesInfo` |
| `gap/fetch.gd/.gi` | `AM_Download`, extraction, `AM_Install`, `FetchArtifact`, `ArtifactContents` |
| `gap/user.gd/.gi` | `ArtifactDirectory`, `ArtifactFile`, `IsArtifactAvailable`, `ShowArtifacts`, `ArtifactInfo`, `VerifyArtifact`, `RemoveArtifact*`, pins, overrides, diagnostics |
| `gap/publish.gd/.gi` | `DescribeArtifactURL` |

Update [PackageInfo.g](PackageInfo.g), [init.g](init.g) (prefs then `.gd`s), [read.g](read.g) (`.gi`s),
and rewrite [README.md](README.md), still the PackageMaker TODO stub.

## Errors and messaging

`DeclareInfoClass("InfoArtifactManager")`, default level 1.

- **1** — checksum mismatch, mirror failed, store not writable, session-only mode, size veto. Also: a
  download that will take minutes announces itself at level 1 regardless — a silently hanging GAP
  session is the worst failure mode here (and U14 is what makes this better than a single line).
- **2** — downloading / verifying / extracting / installed-at. **3** — mirror, backend, external tool.
  **4** — full command lines.

`ErrorNoReturn` only for programming errors. `Error` for "cannot provide the artifact", always ending
with a concrete next step. Everything else returns `true`/`false`/`fail` plus `Info`.

## Verification

**`file://` is the testing backbone.** Because we implement it ourselves, the whole pipeline —
download → verify → extract → install → verify → remove — runs with zero network, zero forking, zero
`io`, and deterministic checksums. That should be ~80% of the suite.

`utils/tst/http-server.g` (~90 lines, pure `io`) is the model for the network tests: `IO_socket`/`IO_bind`
on **port 0** so the kernel picks a free port (read back via `IO_getsockname` — why it doesn't collide in
CI), `IO_fork` per connection, routes for success/delay/404/redirect. **Vendor and extend** rather than
`ReadPackage("utils", "tst/…")`; utils' test files are not API.

```
tst/data/                 # tiny fixtures: sample.tar.gz, sample.zip, sample.txt, sample.txt.gz
tst/http-server.g         # vendored + extended: /file/<n>, /badsum/<n>, /flaky/<n>, /dead
tst/declare.tst           # schema validation, version gating, unknown-key tolerance — no I/O
tst/manifest_forward.tst  # "gapArtifactManifest": 99 and an unknown kind must skip cleanly
tst/hash.tst              # padding incl. a leading-zero digest; all hash backends
tst/store.tst             # AM_DefaultStore cascade, CreateDirectoryRecursively, path construction
tst/fetch-file.tst        # THE WHOLE PIPELINE over file:// — no network, no io, always runs
tst/fetch-http.tst        # network layer against the local server; skipped without io
```

Every test sets `ArtifactStore` under `DirectoryTemporary()` in its `#@local` preamble, so no test can
pollute a real store. Negative tests: `RemoveArtifact` refuses an overridden path; no code path calls
`RemoveDirectoryRecursively` outside the store (guard `AM_AssertInStore`, generalising PackageManager's
`StartsWith` check at `directories.gi:124`).

**CI matrix**: GAP 4.13 (the padding bug), 4.14, 4.15, 4.16; each with and without `io`; plus one job
with neither `curl` nor `wget` on `PATH`, to assert error-message quality.

**End-to-end acceptance**: a real `transgrp` migration on a branch — add `artifacts.json`, change
`DirectoriesPackageLibrary("transgrp","dat32")` to `ArtifactDirectory("transgrp","dat32")` at
`lib/trans.grp:279-284`, and confirm `TransitiveGroup(32,1)` works from a clean store. That is the only
proof that matters.

## Roadmap

- **v0.1 — usable, ≤ 1 GB.** As above. In parallel: **file U1–U18**, and land the cheap ones
  (U4/U5/U9/U10/U11).
- **v0.2 — GC, and shrink the shim layer.** Roots = artifacts declared by any package in
  `GAPInfo.PackagesInfo`, ∪ pins, ∪ overrides, ∪ `roots.d` observed out-of-tree locations, re-validated
  by checking `<path>/PackageInfo.g` still exists (Julia's filter-to-what-still-exists trick applied to
  a path we recorded rather than a log we scrape — which is how we avoid Pkg.jl#2874).
  `logs/orphans.g` records first-seen-orphaned; deletion only after `CollectDelay`; orphanage written
  **before** deleting; `dryRun := true` by default; failed deletions reported as failures, not successes
  (Pkg.jl#1872). `assumeRemoved` so `RemovePackage` can collect in the same session — the concrete
  realisation of "when the last package needing it is removed, its artifacts can go". Opt-in
  `unusedFor := <days>` recency sweep reading `used/`. Per-file manifest ⇒ `VerifyArtifact(…, "full")`
  becomes real. Delete every `gap/compat.gi` shim whose upstream fix has landed.
- **v0.3 — large artifacts, gated on U2 + U12 + U15.** Only once those land does `dat48` become a
  supported target: streaming download, resumable transfer, chunked hashing. Raise
  `MaxAutoDownloadSize` guidance and re-scope the docs then, not before.
- **v0.4 — per-file / tree artifacts.** `kind := "tree"`: an index of path→sha256 plus mirror base URLs;
  `ArtifactFile(pkg, name, relpath)` fetches exactly one file. Breuer's requirement in full, and the
  AtlasRep shape. Adopt AtlasRep's `location`/`fetch`/`contents` triple
  (`atlasrep/gap/access.gd:287-410`) as an **internal** extension point, so zip-as-directory later
  becomes a fourth entry rather than a redesign.
- **v0.5 — zip as a read-only fake directory.**
- **v1.0 — upstreaming the package's own good parts.** `CreateDirectoryRecursively` into core (U5); the
  stricter tarbomb guard into PackageManager (U18); transgrp, primgrp, simpcomp, tomlib, unitlib,
  FactInt/StandardFF migrated, and the duplicate Brent-factor fetchers deleted.

## Risks

Each row separates the MVP workaround from the real fix.

| risk | MVP workaround | real fix |
|---|---|---|
| Large artifact OOMs GAP via the RAM-buffering curlInterface backend | skip that backend by name; **descope `dat48`** | U15 (stream to file), U12 (resume) |
| Interrupted large download restarts from zero | descope | U12 |
| Hashing a large file needs `io` or an external tool | three-tier shim | U2 (`HexSHA256File`) |
| No wall-clock time for last-used / orphan stamps | `IO_gettimeofday` → `date +%s` → skip loudly | U1 |
| Cannot report *why* an external tool failed | exit code only | U3 + U4 |
| No atomic rename without `io` | `IO_rename` → `mv` (same filesystem by layout) | U8 |
| No file size / mtime | `IO_stat` → `du -sk` → `?` | U7 |
| `Download` mutates the caller's `opt` | fresh record per call + regression test | U10 |
| `curl` backend leaves partial files | unconditional `RemoveFile` before retry | U11 |
| Backend capabilities not introspectable | match backend names | U13 |
| Multi-minute download looks like a hung GAP | mandatory level-1 announcement | U14 |
| `InputTextFile` corrupts binary / auto-gunzips `.gz` | staged file always named `blob`; never hash through it | U6 |
| `HexSHA256` drops leading zeros on 4.13–4.15 | `AM_NormalizeHex` on both sides and at parse time; leading-zero regression test | fixed in 4.16; raise the floor eventually |
| Tarbomb / path traversal | fresh private staging dir **and** `tar -tf` pre-scan | U18 (contribute the guard back) |
| Shell injection via paths with spaces | `Process` with a real argv, never `sh -c` | U4, U16 |
| Silent large download surprises a user | `MaxAutoDownloadSize` + level-1 announcement | — (this one is correct as designed) |
| Non-writable/absent store (`gap -r`, container, read-only home) | five-step cascade ending in session-only; write-probe before download | — |
| Concurrent sessions installing the same artifact | content-addressed destination + atomic rename; losing the race is success | — |
| Interrupt mid-install | staging inside the store; meta is the commit point; `CleanArtifactTemp()` | — |
| Deleting something outside the store | `AM_AssertInStore` on every deletion path; overrides never removable; both asserted by test | — |
| Kernel-extension dependency blocks adoption | no hard dependency on `json` or `io` | U1–U8 remove the `io` need entirely |
| Manifest schema growth forces a break | five forward-compat rules + `tst/manifest_forward.tst` | — |
| Windows | `tar` on Win10+; `mv`/`du` may be missing ⇒ copy-then-delete, `?` sizes; best-effort, CI on Linux/macOS | U5, U7, U8 in core would fix most of it |
