---
id: 2
title: Restore the CI matrix once GAP 4.17 is released
status: open
needs: 
touches: .github/workflows/CI.yml
---

# Restore the CI matrix once GAP 4.17 is released

The package requires 4.17, for `CurrentSecondsSinceEpoch` and the SHA256
accumulator. Until 4.17 ships, `latest` and `minimal` both resolve to 4.16,
which cannot load the package at all, so CI tests `devel` only.

When 4.17 is out, put `latest` and `minimal` back. The macOS and Windows
entries stay pinned to one version; they are there because `tar` differs by
platform, not because GAP does.
