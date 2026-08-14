#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# declare.gd: how a package says which artifacts it has.
#

#! @Chapter Declaring artifacts
#!
#! @Section The file <F>artifacts.json</F>
#!
#! A package declares its artifacts in a file <F>artifacts.json</F> in its
#! root directory, next to <F>PackageInfo.g</F>.  &ArtifactManager; finds it
#! by looking at <C>GAPInfo.PackagesInfo</C>, which &GAP; fills in at startup
#! for every installed version of every package, so the file is found without
#! the package being loaded &ndash; and, in a later version, without the
#! package being loaded the garbage collector will still know which artifacts
#! are still wanted.
#!
#! @BeginLog
#! {
#!   "gapArtifactManifestVersion": 1,
#!   "package": "transgrp",
#!   "artifacts": {
#!     "dat32": {
#!       "description": "Transitive groups of degree 32",
#!       "license": "GPL-2.0-or-later",
#!       "tree_sha256": "bbbb...",
#!       "download": [
#!         { "url": "https://example.org/trans32.tar.gz",
#!           "sha256": "aaaa...", "size": 314572800, "format": "tar.gz" },
#!         { "url": "https://mirror.example.org/trans32.tar",
#!           "sha256": "cccc...", "format": "tar" }
#!       ]
#!     }
#!   }
#! }
#! @EndLog
#!
#! @Section Fields
#!
#! <List>
#! <Mark><C>gapArtifactManifestVersion</C></Mark>
#! <Item>Mandatory, an integer.  The version of this file format; currently
#!   <C>1</C>.  Its presence is also what marks the file as ours.  A manifest
#!   declaring a higher version is ignored entirely, with a message naming
#!   the version of &ArtifactManager; that would be needed &ndash; it is
#!   never a parse error.</Item>
#! <Mark><C>package</C></Mark>
#! <Item>Mandatory, and must match the package the file belongs to.  Being
#!   mandatory lets tooling outside &GAP; read the package name here instead
#!   of parsing <F>PackageInfo.g</F>.</Item>
#! <Mark><C>artifacts</C></Mark>
#! <Item>Mandatory.  Maps artifact names to declarations.  A name may consist
#!   of letters, digits, and the characters <C>.</C>, <C>_</C> and
#!   <C>-</C>, and may not start with <C>.</C> &ndash; it is also the file
#!   name of a file artifact and a component of every store path.</Item>
#! </List>
#!
#! Within one artifact:
#!
#! <List>
#! <Mark><C>download</C></Mark>
#! <Item>Mandatory, a non-empty list of <E>alternatives</E>, tried in order;
#!   see below for what one entry contains.  Mirrors and different archive
#!   formats use the same mechanism: what matters is that they all yield the
#!   same data, and the checksum below is what says so.</Item>
#! <Mark><C>tree_sha256</C> or <C>file_sha256</C></Mark>
#! <Item>Mandatory, exactly one of them, and which one says what kind of
#!   artifact this is: <C>tree_sha256</C> a directory,
#!   <C>file_sha256</C> a single file.  Either way it is a checksum of the
#!   artifact as installed, not of what was downloaded, so two sources in
#!   different formats are interchangeable and share one place in the store.
#!   It is checked once the download has been unpacked, and it is what lets
#!   <Ref Func="VerifyArtifact"/> re-read the installed files instead of
#!   trusting their sizes.  <Ref Func="DescribeArtifactURL"/> computes it.
#!   <P/>
#!   A tree checksum is the one git computes for a tree object, with SHA256
#!   in place of SHA1, so it can be checked against a repository created with
#!   <C>git init --object-format=sha256</C>.  Two consequences follow from
#!   git's rules: the owner execute bit is part of the checksum, and an empty
#!   directory is not.</Item>
#! <Mark><C>description</C></Mark>
#! <Item>Optional, shown by <Ref Func="ShowArtifacts"/>.</Item>
#! <Mark><C>license</C></Mark>
#! <Item>Optional, an SPDX identifier or expression, e.g.
#!   <C>"GPL-2.0-or-later"</C> or <C>"MIT OR Apache-2.0"</C>.</Item>
#! </List>
#!
#! Within one entry of <C>download</C>:
#!
#! <List>
#! <Mark><C>url</C></Mark>
#! <Item>Mandatory.</Item>
#! <Mark><C>sha256</C></Mark>
#! <Item>Mandatory.  The checksum of the file as downloaded, which is not in
#!   general the checksum of the artifact.</Item>
#! <Mark><C>format</C></Mark>
#! <Item>Mandatory.  What to <E>do</E> with the download, never a description
#!   of it: <C>"raw"</C> to use it as it is, <C>"gz"</C> to decompress it,
#!   and <C>"tar"</C> or <C>"tar.gz"</C> to unpack it into a directory.  The
#!   unpacking formats belong to a <C>tree_sha256</C> artifact and the others
#!   to a <C>file_sha256</C> one.
#!   <P/>
#!   Only gzip for now.  Every further format is another tool to require on
#!   every platform, and zip is where the archivers disagree about what they
#!   produce.
#!   <P/>
#!   It is never guessed from the URL.  A URL is a poor witness &ndash;
#!   Zenodo's end in <F>/content</F> &ndash; and a wrong guess would install
#!   an archive without unpacking it.  Keep a file compressed on disk by
#!   giving <C>"raw"</C> and naming the artifact <F>...gz</F>: &GAP; reads
#!   such a file through <C>StringFile</C> without a separate step.</Item>
#! <Mark><C>size</C></Mark>
#! <Item>Optional, in bytes.  It lets &ArtifactManager; say what a download
#!   will cost before it starts, and it is what the
#!   <C>MaxAutoDownloadSize</C> preference compares against &ndash; per
#!   source, so a small mirror stays usable when a large one is not.</Item>
#! </List>
#!
#! A field &ArtifactManager; does not know is an error, not something to
#! ignore: a field skipped is a feature its author believes is in force.  Such
#! a field makes the artifact it appears in unusable, and leaves the others in
#! the file alone.
#!
#! That is separate from <C>gapArtifactManifestVersion</C>, which is recorded
#! once per file and so can only be judged for the file as a whole.
#!
#! @Section Functions

#! @Description
#!   Declares artifacts for the package <A>pkgname</A> at run time, as an
#!   alternative to an <F>artifacts.json</F> file.  <A>list</A> is a list of
#!   records with the same fields as described above, plus a <C>name</C>.
#!
#!   This is for packages whose URLs are computed rather than fixed.  Note
#!   that such declarations exist only in the current &GAP; session, so a
#!   future garbage collector will not see them; use
#!   <Ref Func="PinArtifact"/> if the data must survive.
#! @Arguments pkgname, list
#! @Returns nothing
DeclareGlobalFunction( "DeclareArtifacts" );

# Whether <format> names a single file rather than an archive.
DeclareGlobalFunction( "AM_IsSingleFile" );

# Why <pkg>/<name> is not declared, as a string, or 'fail' if no manifest
# problem explains it.  Reading every package's manifest -- for a listing, or
# for garbage collection -- must not fail because one of them is unusable;
# asking for one artifact must say what is wrong.
DeclareGlobalFunction( "AM_DeclarationProblem" );

#! @Description
#!   The declaration of the artifact <A>name</A> of package <A>pkg</A>, as a
#!   record, or <K>fail</K> if there is no such artifact.
#! @Arguments pkg, name
#! @Returns a record or <K>fail</K>
DeclareGlobalFunction( "ArtifactDeclaration" );

#! @Description
#!   All known artifact declarations, or those of the package <A>pkg</A>.
#! @Arguments [pkg]
#! @Returns a list of records
DeclareGlobalFunction( "AllArtifactDeclarations" );


#############################################################################
##
##  Internals.
##

# Highest 'gapArtifactManifestVersion' we understand.
DeclareGlobalFunction( "AM_ManifestFormat" );

# Validate and normalise one declaration record.  Returns the normalised
# record, or a string describing what is wrong with it.
DeclareGlobalFunction( "AM_CheckDeclaration" );

# Parse a manifest, given its text and the package it belongs to.  Returns a
# list of normalised declarations; problems are reported via Info and never
# raise an error.
DeclareGlobalFunction( "AM_ParseManifest" );

# Forget everything cached about declarations.  Mainly for the tests.
DeclareGlobalFunction( "AM_FlushDeclarations" );
