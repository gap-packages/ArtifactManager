---
id: 1
title: Land the download PRs in utils and curlInterface
status: open
needs: 
touches: gap/fetch.gi
---

# Land the download PRs in utils and curlInterface

In flight, and the last thing between us and a `Download` we do not have to
work around:

- gap-packages/utils#104 — pass `target` on to curlInterface as `targetFile`.
- gap-packages/utils#105 — a `resume` option. Approved.
- `mh/download-keep-existing` in utils — a failed download must not delete a
  target file the caller already had. Not yet a PR.
- gap-packages/curlInterface#62 — write the body straight to a file, so a
  large download is not bounded by memory. Draft.

The option is `targetFile` on the curlInterface side and `target` on the
`utils` side on purpose: `Download` forwards its whole option record, so
sharing the name makes a released `utils` and a new curlInterface both write
the same file. Checked against a local server; only the naming avoids it.

Once these land, `AM_Download` in `gap/fetch.gi` can drop the fresh-option
-record dance (U10) and the unconditional `RemoveFile` before each retry (U11).
