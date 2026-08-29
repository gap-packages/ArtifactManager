---
id: 7
title: Per-file artifacts and a remote table of contents
status: open
needs: 6
touches: gap/declare.gi, gap/fetch.gi
---

# Per-file artifacts and a remote table of contents

gap-packages/ArtifactManager#2, and Thomas Breuer's requirement in
gap-system/gap#4285: fetch one file of a large collection rather than the
whole thing. AtlasRep is the shape to match.

A new `kind`, with an index of path to checksum plus mirror base URLs;
`ArtifactFile(pkg, name, relpath)` then fetches exactly one file. The
manifest's forward-compatibility rules exist for this: an older
ArtifactManager skips an artifact whose `kind` it does not know, and says so
when asked for it.

The remote index must never be executed, which is the other half of why the
manifest format is JSON.

Shares machinery with task 6 — both are about not materialising what nobody
asked for — so worth designing together even if built apart.
