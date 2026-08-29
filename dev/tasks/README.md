# dev/tasks/

One file per open piece of work, numbered. `make tasks` lists them, ready
first, then the ones waiting on something else.

Resolved tasks move to `dev/tasks/done/` with `status: done`. They are kept:
why a thing was decided is worth more later than that it was.

Frontmatter: `id`, `title`, `status` (open or done), `needs` (task ids this
waits on, comma separated), `touches` (paths).

```
---
id: 42
title: Something short enough to read in a listing
status: open
needs: 7
touches: gap/fetch.gi, tst/fetch.tst
---
```

Anyone may add one. Cite the id in the commit that closes it.

## What goes where

- **Here**: work we intend to do, in this repository or upstream.
- **[../upstream.md](../upstream.md)**: the gaps in GAP and in other packages
  that this one works around, and which PR closes each. It answers "why is
  this workaround here", which is a question about the code; the `TODO(U<n>)`
  comments point at it. A task that acts on one cites its U-number.
- **GitHub issues**: anything that wants discussion rather than doing.
  A task may reference an issue without repeating it.
- **[../plan.md](../plan.md)**: the original design, kept as history. Not a
  list of asks.
