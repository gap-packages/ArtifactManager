---
id: 6
title: Read files straight out of the archive
status: open
needs: 
touches: gap/fetch.gi, gap/user.gi
---

# Read files straight out of the archive

gap-packages/ArtifactManager#5. An artifact of 10,000 files of 100 bytes is
1 MB of data and 41 MB of disk, because each file costs a block.

An uncompressed `.tar` is a sequence of contiguous byte ranges: index it once
at install time and a read is `IO_lseek` plus `IO_read`, with no `tar`
process, no C, and no libarchive. `.tar.gz` cannot do this — decompress once
at install and keep the `.tar`. `.zip` is harder, not easier: its members are
individually DEFLATE-compressed and GAP has no inflate.

The cost is that the consumer gets a stream rather than a filename.
`Read(<input stream>)` exists, so the transgrp and primgrp pattern is covered,
but anything wanting a real path is not — so this is opt-in per artifact.

Not urgent on the evidence: primgrp's data is 7.2% block waste, median file
24 KB. Worth doing when an artifact actually exhibits the problem.
