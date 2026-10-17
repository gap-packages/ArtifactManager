# Upstream work

The gaps in GAP and in neighbouring packages that this package works around.
Every workaround carries a `TODO(U<n>)` comment naming its row here, so this
file answers "why is this code shaped like that":

```
grep -rn 'TODO(U' gap/
```

It is a reference, not a worklist. What we intend to *do* about these lives in
[tasks/](tasks/) — `make tasks`. The point of both is that `gap/compat.gi`
should shrink over time, not calcify: U1 and U2 landing removed a third of it.

## GAP

| # | What is missing | Why we need it | Status |
|---|---|---|---|
| U1 | **A wall clock.** `Runtime()` is CPU time; there is no way to ask for the current date or time without the IO package or shelling out to `date`. | Last-use timestamps, and the orphan timestamps the planned garbage collection needs. | **merged**, [gap#6504](https://github.com/gap-system/gap/pull/6504) |
| U2 | **`HexSHA256File(<filename>)`.** `HexSHA256(<stream>)` calls `ReadAll`, i.e. it pulls the whole file into memory; `lib/files.gi` carries a TODO saying so. The kernel already has `GAP_SHA256_INIT`/`UPDATE`/`FINAL` in `src/sha256.c`, so only a chunked driver is missing. | Verifying a download without reading it all at once. This one addition would replace all three implementations in `gap/hash.gi`. | **merged**, [gap#6505](https://github.com/gap-system/gap/pull/6505), and the accumulator in [gap#6509](https://github.com/gap-system/gap/pull/6509) |
| U3 | **`Process` cannot capture stderr.** `RunProcess` (U4) inherits it too. | Without it a failing `tar` gives us an exit code and nothing else, which is the difference between an actionable error message and "exit code 2". | [gap#4657](https://github.com/gap-system/gap/issues/4657), open |
| U4 | **A safe, ergonomic process runner.** `Exec` goes through a shell; `Process` is correct but clumsy. | `AM_Exec` in `gap/compat.gi` should become a call to `RunProcess`. `AM_ExecQuiet` keeps its `sh -c` until U3. | **merged** as `RunProcess`, [gap#6536](https://github.com/gap-system/gap/pull/6536), in 4.17 |
| U5 | **`mkdir -p`, with permission fixing and good errors.** `CreateDir` is a single-level `mkdir(2)`. | Asked for in [gap#4285](https://github.com/gap-system/gap/issues/4285) itself. `AutoDoc_CreateDirIfMissing` and `PKGMAN_CreateDirRecursively` are two partial reimplementations; `CreateDirectoryRecursively` here is a third, and is meant to be upstreamed. | to file |
| U6 | **Binary-safe file reading.** `StringFile` goes through `InputTextFile`, which transparently gunzips `.gz` and, on systems distinguishing text and binary mode, translates line endings; documented as unsafe for binary data. | This silently produces the wrong checksum. We work around it by giving every staged download a name with no extension. | to file |
| U7 | **File size and mtime.** | The disk-usage overview, and cheap re-verification of installed data. | to file |
| U8 | **Rename/move.** | An atomic same-filesystem rename is the whole basis of a lock-free install. Today it needs the IO package or an external `mv`. | to file |
| U9 | `CreateDir`, `RemoveDir` and `RemoveDirectoryRecursively` are **undocumented**, despite being the obvious tools for this job. | Discoverability; also makes U5 and U8 easier to argue for. | **drafted**, see [upstream-drafts.md](upstream-drafts.md) |

U1 through U8 together would let ArtifactManager drop the IO dependency
entirely. That is the right long-term shape: a data-management package should
not need a compiled dependency in order to hash a file or move it.

## utils

| # | What is wrong | Status |
|---|---|---|
| U10 | **`Download` modifies the option record it is given**, assigning `opt.verifyCert` and `opt.maxTime` in place. | **merged**, [utils#102](https://github.com/gap-packages/utils/pull/102), in 0.99 |
| U11 | **Inconsistent cleanup after a failure.** The `wget` backend removed a partial target file; the `curl` backend left it behind. | **merged**, [utils#103](https://github.com/gap-packages/utils/pull/103) and [#107](https://github.com/gap-packages/utils/pull/107), in 0.99. `Download` now cleans up, not the backends. We call backends one at a time (U13), so `AM_Download` still removes the partial file itself. |
| U12 | **No resume.** A transfer that is killed restarts from zero. | **merged**, [utils#105](https://github.com/gap-packages/utils/pull/105), in 0.99; not used here yet |
| U13 | **Backends advertise no capabilities**, so a caller who needs one that streams to a file, or follows redirects, has to match on backend *names*. `AM_BackendRank` in `gap/fetch.gi` is exactly that hack. A per-backend record with `streamsToFile`, `followsRedirects`, `supportsTimeout`, `supportsHttps` would turn it into a query. `Download_Methods` should also be documented, since it is the intended extension point. | to file |
| U14 | **No progress reporting**, so a download of several minutes looks like a hung GAP. | to file |

### A concrete bug this uncovered

`Download_Methods` is ordered with IO's `SingleHTTPRequest` ahead of `curl` and
`wget`. That backend speaks plain HTTP only and **does not follow redirects**:
it reports a 302 as a *successful* download of an empty body (still so in
utils 1.01 with IO 4.11). Any caller that does not checksum what it got will
silently install nothing at all — which is precisely the "technology
transitions such as http to https broke several packages which simply used the
IO package for downloads" complaint in
[gap#4285](https://github.com/gap-system/gap/issues/4285).

ArtifactManager works around this by ranking backends itself (see U13); the
regression test is in `tst/download.tst`. Upstream, the ordering itself is
worth reconsidering.

## curlInterface

| # | What is missing | Status |
|---|---|---|
| U15 | **`DownloadURL` cannot stream to a file.** It builds the entire response as a GAP string. | **merged**, [curlInterface#62](https://github.com/gap-packages/curlInterface/pull/62) as option `targetFile`, in 2.5.0; utils 0.99 passes `target` on to it ([utils#104](https://github.com/gap-packages/utils/pull/104)). `AM_BackendRank` still demotes this backend for large files. |

## GAP.jl

Its `Download` method sits first in `Download_Methods`, so under Oscar it is
the one that runs.

| # | What is wrong | Status |
|---|---|---|
| U19 | **A failed download deletes an existing target file.** `Downloads.download(url, path)` truncates `path`, and removes it on error. | [GAP.jl#1454](https://github.com/oscar-system/GAP.jl/issues/1454), open. Does not hit us: we download to a staging file. |
| U20 | **`maxTime := 0` is rejected** (`ArgumentError: timeout must be positive`), though utils documents 0 as no timeout. | [GAP.jl#1455](https://github.com/oscar-system/GAP.jl/issues/1455), open. Hits us on every download: `AM_DownloadTimeout` returns the preference's default 0 and we pass it on. Ours to fix too, by omitting `maxTime` when it is 0, as `Download` does. |

## PackageManager

Checked against master `9e40dc4` (2.0.0-beta.2 plus CI changes). 2.0.0 is the
window for anything that changes behaviour.

| # | What is wrong | Status |
|---|---|---|
| U16 | **`PKGMAN_Exec` joins arguments with spaces and runs them through `sh -c`** (`gap/PackageManager.gi:150`). Any path containing a space breaks; any path containing a shell metacharacter injects. This is why ArtifactManager cannot reuse `PKGMAN_ExtractArchive`, which is built on it. `Process` fixes it; `RunProcess` (U4) needs GAP 4.17. Related: [PackageManager#104](https://github.com/gap-packages/PackageManager/issues/104) (stop merging stderr into stdout). | to file |
| U17 | **No checksum verification of downloaded package archives at all.** `grep -i 'sha\|checksum\|md5'` over `gap/` and `doc/` returns nothing. The package distro publishes `ArchiveSHA256` for every package, but PackageManager reads `PackageInfo.g` URLs rather than the distro ([PackageManager#84](https://github.com/gap-packages/PackageManager/issues/84)). | to file |
| U18 | **Weak archive safety.** `PKGMAN_TarTopDirectory` requires exactly one top-level directory but does not reject absolute paths or `..` members. It is currently the only tarbomb guard in the GAP ecosystem. The stricter check in `AM_CheckArchiveMembers` is worth contributing back. | to file |

## Status at a glance

Landed: U1, U2, U4 (GAP 4.17); U10, U11, U12 (utils 0.99); U15
(curlInterface 2.5.0). Not yet acted on here: U4 (`AM_Exec`), U12 (resume),
U15 (`AM_BackendRank`).

Filed, open: U3 (gap#4657, someone else's), U19 and U20 (GAP.jl#1454, #1455).

Not filed: U5 to U8 (tasks 8 and 10), U9 (task 9, drafted), U13 and U14
(tasks 11 and 12), U16 to U18 (task 13).
