---
id: 8
title: File the GAP core gaps that keep the IO dependency (U5, U7, U8)
status: open
needs: 
touches: dev/upstream.md
---

# File the GAP core gaps that keep the IO dependency (U5, U7, U8)

Three things GAP core does not offer, each of which `gap/compat.gi` supplies
through the IO package or an external program:

- **U5** `mkdir -p`, with permission fixing and a good error. `CreateDir` is
  a single-level `mkdir(2)`. Asked for in gap-system/gap#4285 itself, and
  `AutoDoc_CreateDirIfMissing` and `PKGMAN_CreateDirRecursively` are two
  partial reimplementations. `CreateDirectoryRecursively` here is a third and
  is meant to be upstreamed.
- **U7** file size and mtime. Needed for the disk-usage listing and for cheap
  re-verification.
- **U8** rename. Atomic same-filesystem rename is the whole basis of a
  lock-free install; today it needs IO or an external `mv`.

None is filed. U1 and U2 went the same way and both landed, so the pattern
works: file the issue, then offer the PR.
