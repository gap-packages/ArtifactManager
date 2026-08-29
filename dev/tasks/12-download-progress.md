---
id: 12
title: Progress reporting for long downloads (U14)
status: open
needs: 1
touches: gap/fetch.gi
---

# Progress reporting for long downloads (U14)

A multi-minute download looks like a hung GAP. `AM_Install` announces the size
before it starts, at Info level 1, which is the least that could work, but
nothing moves afterwards.

`utils`' `Download` would want a progress-callback option; curl and wget can
both feed one, and curlInterface has `CURLOPT_XFERINFOFUNCTION`.

Matters more the moment large artifacts are routine — a 30 GB transgrp
download with no output for an hour is indistinguishable from a hang.
