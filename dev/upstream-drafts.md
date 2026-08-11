# Draft text for the first three upstream issues

Ready to post, nothing posted yet. These are U9, U10 and U11 from
[upstream.md](upstream.md), written out in full. Every claim here was checked
against the source rather than recalled.

This file is scaffolding: delete it once the issues are filed and their
numbers recorded in `upstream.md`.

---

## 1. `gap-system/gap` — U9

**Title:** Document `CreateDir`, `RemoveDir` and `RemoveDirectoryRecursively`

**Labels:** kind: enhancement, topic: documentation

These three functions exist and work, but none of them appears in the
reference manual:

- `CreateDir( <name> )` — `src/streams.c`, a single-level `mkdir(2)`,
  returning `true` or `fail`
- `RemoveDir( <name> )` — `src/streams.c`, `rmdir(2)`, so the directory has to
  be empty
- `RemoveDirectoryRecursively( <name> )` — `lib/files.gi`

They are the obvious tools for any package that manages files on disk, and the
neighbouring functions (`RemoveFile`, `IsDirectoryPath`, `DirectoryContents`,
`TmpDirectory`) *are* documented, so the omission looks accidental rather than
deliberate.

Two behaviours are worth stating explicitly, because both are easy to get
wrong and both matter to callers:

- `CreateDir` creates **one** level only; it is not `mkdir -p`. (There is no
  `mkdir -p` in GAP at all — I will open a separate issue about that.)
- `CreateDir` returns `fail` when the directory already exists. Code that
  wants "make sure this directory exists" therefore has to check with
  `IsDirectoryPath` afterwards rather than trusting the return value — which
  is also the race-free way to write it.

If these are deliberately undocumented — because the API is not considered
settled, say — that would be worth recording too, so package authors know to
keep away.

Found while writing the ArtifactManager package
(https://github.com/gap-packages/ArtifactManager), which needs all three.

---

## 2. `gap-packages/utils` — U10

**Title:** `Download` modifies the option record it is given

**Labels:** bug

`Download( <url>, <opt> )` writes into the caller's record:

```gap
if not IsBound( opt.verifyCert ) and
   UserPreference( "utils", "DownloadVerifyCertificate" ) = false then
  opt.verifyCert:= false;
fi;

if not IsBound( opt.maxTime ) then
  timeout:= UserPreference( "utils", "DownloadMaxTime" );
  if IsPosInt( timeout ) then
    opt.maxTime:= timeout;
  fi;
fi;
```

(`lib/download.gi`, in the two-argument method.)

So a caller that builds one option record and reuses it for several downloads
gets the settings from the first call baked in, and a caller that passes a
record it also uses for something else has that record changed underneath it.
Neither is documented.

What makes this worth fixing rather than documenting is *when* it happens.
With the default preferences it does not happen at all — `DownloadMaxTime` is
`0`, which is not an `IsPosInt`, and `DownloadVerifyCertificate` is `true`, so
neither branch is taken:

```gap
gap> LoadPackage( "utils" );;
gap> opt := rec();;
gap> Download( "file:///nonexistent", opt );;
gap> opt;
rec(  )
gap> SetUserPreference( "utils", "DownloadMaxTime", 30 );
gap> SetUserPreference( "utils", "DownloadVerifyCertificate", false );
gap> opt := rec();;
gap> Download( "file:///nonexistent", opt );;
gap> opt;
rec( maxTime := 30, verifyCert := false )
```

So it is invisible to anyone testing with a default configuration, and shows
up only for users who have changed a preference — the hardest kind of bug to
get a report about.

It bites soonest in a retry loop, since the natural way to write one is to
hoist the option record out of the loop.

Suggested fix — one line at the top of the two-argument method:

```gap
opt := ShallowCopy( opt );
```

`ShallowCopy` is enough, since only top-level components are assigned.

The `via DownloadURL` backend already copies the record before touching it
(`lib/download.gi:39`), which suggests the behaviour was not intended.

Found while writing the ArtifactManager package
(https://github.com/gap-packages/ArtifactManager), which passes a fresh record
on every call to avoid it.

---

## 3. `gap-packages/utils` — U11

**Title:** `Download` backends disagree about what to do with a partial file after a failure

**Labels:** bug

When `opt.target` is set and the download fails, the `wget` backend removes
the partially written file:

```gap
if code <> 0 then
  # wget may have created the target file; try to remove it
  if IsBound( opt.target ) and IsString( opt.target ) and
     IsExistingFile( opt.target ) and RemoveFile( opt.target ) <> true then
    Error( "Download cannot remove unwanted file ", opt.target );
  fi;
  ...
```

The `curl` backend does not — on a non-zero exit it returns straight away.

So after

```gap
res := Download( url, rec( target := f ) );
```

with `res.success = false`, whether `f` exists at all — and if it does,
whether it holds a truncated file or an HTTP error page — depends on which
backend happened to be available. A caller cannot write correct cleanup code
against that.

The failure mode is not hypothetical: a caller that tests
`IsExistingFile( target )` to decide whether it has the data will accept a
truncated file on a curl-only machine and behave correctly on a wget-only one.

`tst/download.tst` already records the problem, in a comment:

> the backends do not behave consistently in the case of failure … which makes
> them useless as automatic tests

Suggested fix: guarantee it centrally rather than per backend — in the
two-argument `Download` method, remove `opt.target` whenever the chosen
backend reports failure, and document the guarantee ("on failure, the target
file is not left behind"). That also covers backends added later, including
ones contributed from outside the package via `Download_Methods`.

Related, and worth doing in the same pass: `Download_Methods` is named in the
manual as the extension point, but the record format its entries must have is
not specified anywhere. (I will open a separate issue about backends
advertising their capabilities.)

Found while writing the ArtifactManager package
(https://github.com/gap-packages/ArtifactManager), which deletes the target
before every attempt to sidestep this.
