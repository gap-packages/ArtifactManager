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
| U3 | **`Process` cannot capture stderr.** | Without it a failing `tar` gives us an exit code and nothing else, which is the difference between an actionable error message and "exit code 2". | [gap#4657](https://github.com/gap-system/gap/issues/4657), open |
| U4 | **A safe, ergonomic process runner.** `Exec` goes through a shell; `Process` is correct but clumsy. | `AM_Exec` in `gap/compat.gi` is a strictly worse version of the proposed `Exec2` and should be deleted once it exists. | [gap#5103](https://github.com/gap-system/gap/pull/5103), open draft |
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
| U10 | **`Download` modifies the option record it is given**, assigning `opt.verifyCert` and `opt.maxTime` in place. Callers must therefore pass a throwaway record every time. One-line fix. Note that with the *default* preferences neither assignment fires, so this is invisible to anyone testing a stock configuration — which is what makes it worth fixing rather than documenting. | **merged**, [utils#102](https://github.com/gap-packages/utils/pull/102) |
| U11 | **Inconsistent cleanup after a failure.** The `wget` backend removes a partial target file; the `curl` backend leaves it behind. `utils`' own `tst/download.tst` says the backends "do not behave consistently in the case of failure… which makes them useless as automatic tests" — that admission is the bug report. | **merged**, [utils#103](https://github.com/gap-packages/utils/pull/103); follow-up fix on `mh/download-keep-existing` |
| U12 | **No resume.** A transfer that is killed restarts from zero. | [utils#105](https://github.com/gap-packages/utils/pull/105), open, **blocking** |
| U13 | **Backends advertise no capabilities**, so a caller who needs one that streams to a file, or follows redirects, has to match on backend *names*. `AM_BackendRank` in `gap/fetch.gi` is exactly that hack. A per-backend record with `streamsToFile`, `followsRedirects`, `supportsTimeout`, `supportsHttps` would turn it into a query. `Download_Methods` should also be documented, since it is the intended extension point. | to file |
| U14 | **No progress reporting**, so a download of several minutes looks like a hung GAP. | to file |

### A concrete bug this uncovered

`Download_Methods` is ordered with IO's `SingleHTTPRequest` ahead of `curl` and
`wget`. That backend speaks plain HTTP only and **does not follow redirects**:
it reports a 302 as a *successful* download of an empty body. Any caller that
does not checksum what it got will silently install nothing at all — which is
precisely the "technology transitions such as http to https broke several
packages which simply used the IO package for downloads" complaint in
[gap#4285](https://github.com/gap-system/gap/issues/4285).

ArtifactManager works around this by ranking backends itself (see U13); the
regression test is in `tst/download.tst`. Upstream, the ordering itself is
worth reconsidering.

## curlInterface

| # | What is missing | Status |
|---|---|---|
| U15 | **`DownloadURL` cannot stream to a file.** It builds the entire response as a GAP string and returns it; the utils backend then writes that string out. So `utils`' *first-choice* backend is the one that must be avoided for any sizeable file. Passing a `FILE*` via `CURLOPT_WRITEDATA` would fix it, and would make that backend the *best* choice for large files instead of the worst. | [curlInterface#62](https://github.com/gap-packages/curlInterface/pull/62), open, **blocking** |

Landing curlInterface#62 breaks `utils` until
[utils#104](https://github.com/gap-packages/utils/pull/104) goes in: once
`DownloadURL` honours `target` it no longer returns a `result` component, and
`utils/lib/download.gi` reads that component unconditionally. Neither CI
catches it, since neither repository tests against the other's branch.

## PackageManager

| # | What is wrong | Status |
|---|---|---|
| U16 | **`PKGMAN_Exec` joins arguments with spaces and runs them through `sh -c`** (`gap/PackageManager.gi:296`). Any path containing a space breaks; any path containing a shell metacharacter injects. This is why ArtifactManager cannot reuse `PKGMAN_ExtractArchive`, which is built on it. Switching to `Process`, or to `Exec2` once U4 lands, fixes it. | to file |
| U17 | **No checksum verification of downloaded package archives at all.** `grep -i 'sha\|checksum\|md5'` over `gap/` and `doc/` returns nothing. | to file |
| U18 | **Weak archive safety.** `PKGMAN_TarTopDirectory` requires exactly one top-level directory but does not reject absolute paths or `..` members. It is currently the only tarbomb guard in the GAP ecosystem. The stricter check in `AM_CheckArchiveMembers` is worth contributing back. | to file |

## Status at a glance

Landed: U1, U2, U10, U11. Requiring GAP 4.17 retired their shims here —
`AM_HexSHA256File` is four lines over `SHA256State`, and `AM_Now` is one call.

Open PRs: U12 (utils#105), U15 (curlInterface#62), and utils#104 alongside
them — task 1.

Not filed: U5, U6, U7, U8 (tasks 8 and 10), U9 (task 9, drafted), U13 and U14
(tasks 11 and 12), U16 to U18 (task 13). U3 and U4 wait on gap#4657 and
gap#5103, which are other people's.
