---
id: 14
title: Drop the IO dependency
status: open
needs: 8
touches: gap/compat.gi, gap/compat.gd, PackageInfo.g
---

# Drop the IO dependency

The goal `gap/compat.gi` exists to work towards: a data-management package
should not need a compiled dependency in order to hash a file or move it.

U1 and U2 are gone, and with them the three-tier hashing and the wall-clock
shims. What still reaches for IO is file size, rename, the mode bits behind
`AM_IsExecutableFile` and `AM_IrregularFiles`, block counts in
`AM_DirectorySize`, and `IO_chmod` — that is, task 8.

When those land, IO comes out of `SuggestedOtherPackages`, `AM_HaveIO` goes,
and `compat.gi` shrinks to the process-running helpers. Each function there
carries a `TODO(U<n>)` naming what deletes it; the file should be measured by
how fast it shrinks.
