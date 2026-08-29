---
id: 5
title: Decide whether the execute bit belongs in a tree checksum
status: open
needs: 
touches: gap/hash.gi
---

# Decide whether the execute bit belongs in a tree checksum

gap-packages/ArtifactManager#7. `AM_TreeSHA256` follows git, which encodes
the owner execute bit in a tree entry's mode. On Cygwin `unzip` leaves
extracted files executable where `tar` does not, so the same data unpacked
from a zip and from a tarball produced different checksums, and Windows CI
went red.

Dodged for now by supporting only `tar` and `tar.gz`, so no second archiver
is involved. The question comes back the moment zip does.

Options are in the issue. My preference is to hash every regular file as
`100644`: an artifact's identity should not depend on the user's toolchain,
and for any tree without executables that is still exactly git's value.
`AM_SetTreeReadOnly` can go on preserving whatever bit it was given.
