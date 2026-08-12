# Draft text for U9

Not posted yet. U10 and U11, which used to be drafted here too, became
[utils#102](https://github.com/gap-packages/utils/pull/102) and
[utils#103](https://github.com/gap-packages/utils/pull/103).

Delete this file once the issue is filed and its number is in
[upstream.md](upstream.md).

---

## `gap-system/gap` — U9

**Title:** Document `CreateDir`, `RemoveDir` and `RemoveDirectoryRecursively`

**Labels:** kind: enhancement, topic: documentation

These three functions exist and work, but none of them appears in the
reference manual:

- `CreateDir( <name> )` — `src/streams.c`, a single-level `mkdir(2)`,
  returning `true` or `fail`
- `RemoveDir( <name> )` — `src/streams.c`, `rmdir(2)`, so the directory has to
  be empty
- `RemoveDirectoryRecursively( <name> )` — `lib/files.gi`

They are the obvious tools for any package that manages files on disk, and the
neighbouring functions (`RemoveFile`, `IsDirectoryPath`, `DirectoryContents`,
`TmpDirectory`) *are* documented, so the omission looks accidental rather than
deliberate.

Two behaviours are worth stating explicitly, because both are easy to get
wrong and both matter to callers:

- `CreateDir` creates **one** level only; it is not `mkdir -p`. (There is no
  `mkdir -p` in GAP at all — I will open a separate issue about that.)
- `CreateDir` returns `fail` when the directory already exists. Code that
  wants "make sure this directory exists" therefore has to check with
  `IsDirectoryPath` afterwards rather than trusting the return value — which
  is also the race-free way to write it.

If these are deliberately undocumented — because the API is not considered
settled, say — that would be worth recording too, so package authors know to
keep away.

Found while writing the ArtifactManager package
(https://github.com/gap-packages/ArtifactManager), which needs all three.

---
