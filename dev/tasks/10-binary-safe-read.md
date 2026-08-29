---
id: 10
title: A binary-safe read for GAP core (U6)
status: open
needs: 
touches: gap/compat.gi
---

# A binary-safe read for GAP core (U6)

`StringFile` goes through `InputTextFile`, which transparently gunzips a
`.gz` file and, where text and binary mode differ, translates line endings.
Both silently produce the wrong bytes, and the library documents it as unsafe
for binary data.

Mostly worked around here rather than suffered: every staged download is
named without an extension, and hashing no longer goes through `StringFile`
at all now that `UpdateSHA256File` exists. What remains is `AM_CopyFile`'s
last-resort branch when `cp` is missing.

Lower value than it was before U2 landed, but it is still a trap for everyone
else, and worth an issue if not a PR.
