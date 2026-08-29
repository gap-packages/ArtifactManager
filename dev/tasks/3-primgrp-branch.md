---
id: 3
title: Push the primgrp branch and open a PR
status: open
needs: 1
touches: 
---

# Push the primgrp branch and open a PR

`mh/artifactmanager` in the primgrp clone is the end-to-end proof: a real
1 GB artifact on Zenodo, fetched, verified against a tree checksum of 29,776
files, and read through `ArtifactDirectory`. Local is ahead of the pushed
branch.

Worth waiting for task 1: without it a fetch of that size still buffers the
whole file in memory on the curlInterface backend.

It is also the honest test of whether the manifest is pleasant to write, so
any friction found here is worth recording rather than smoothing over by
hand.
