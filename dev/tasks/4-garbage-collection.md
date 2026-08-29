---
id: 4
title: Garbage collection
status: open
needs: 
touches: gap/store.gi, gap/user.gi
---

# Garbage collection

The largest thing still missing, and the reason the store records what it
does. v0.1 deliberately shipped the bookkeeping first: `used/<pkg>/<name>/
<hash>.g` gets a timestamp on every resolve, and pins and overrides exist,
because history cannot be reconstructed later.

What it needs:

- Roots: every artifact declared by any package in `GAPInfo.PackagesInfo`,
  plus pins, plus overrides, plus out-of-tree package locations we have seen.
  Reading a manifest must not load the package — this is why the format is
  JSON.
- An orphan log with a first-seen timestamp, written *before* anything is
  deleted, and a grace period (`CollectDelay`, default 7 days).
- `dryRun := true` by default. Failed deletions reported as failures, not
  quietly counted as successes.
- An `unusedFor := <days>` sweep as explicit opt-in, reading `used/`.

Pkg.jl#1872 and Pkg.jl#2874 are the two mistakes worth not repeating: silent
failure to delete, and scraping a log instead of recording a path.
