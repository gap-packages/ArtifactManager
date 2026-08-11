# Notes for agents working in this repository

## Prose: say it once, then stop

**Be terse.** This applies to comments, commit messages, and documentation.
It is the note most often needed.

The failure mode is not being wrong, it is being long: three sentences where
one would do, a restatement of what the code plainly says, a second example
that adds nothing, a clause defending a decision nobody questioned.

- Say why, not what. `# the list is sorted` earns its place; a paragraph
  narrating a loop does not.
- One example, not three. One reason, not every reason.
- Do not explain a thing twice in one file, and do not repeat in a comment
  what the identifier already says.
- Numbers and specifics beat adjectives. "160 orders" is worth more than
  "relatively few orders".
- Cut throat-clearing: no "it is worth noting that", "the point here is",
  "deliberately", "the whole point of".

Existing comments in this repository may be longer than this in places. That
is history, not a licence.

## Working here

Run the tests with

    gap tst/testall.g

They use `file://` URLs, so they need no network. `tst/download.tst` forks a
local HTTP server and is skipped without the IO package.

Rebuild the manual with `gap makedoc.g`. Everything under `doc/` is generated
and gitignored; notes for contributors go in `dev/`.

`gap/compat.gi` exists only to paper over things GAP lacks. Every function
there carries a `TODO(U<n>)` naming the entry in `dev/upstream.md` that should
delete it. The file should shrink; do not let it grow.

`dev/plan.md` is the original design plan, kept for the reasoning behind
decisions that are not obvious from the code. It is history: where it and the
code disagree, the code is right.
