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
#!   "gapArtifactManifest": 1,
#!   "package": "transgrp",
#!   "artifacts": {
#!     "dat32": {
#!       "description": "Transitive groups of degree 32",
#!       "version": "1.0",
#!       "size": 314572800,
#!       "license": "GPL-2.0-or-later",
#!       "provenance": "https://doi.org/10.5281/zenodo.5935751",
#!       "strip": 1,
#!       "download": [
#!         { "url": "https://example.org/trans32.tar.gz",
#!           "sha256": "aaaa...", "format": "tar.gz" },
#!         { "url": "https://mirror.example.org/trans32.tar.gz",
#!           "sha256": "aaaa..." }
#!       ]
#!     }
#!   }
#! }
#! @EndLog
#!
#! @Section Fields
#!
#! <List>
#! <Mark><C>gapArtifactManifest</C></Mark>
#! <Item>Mandatory, an integer.  The version of this file format; currently
#!   <C>1</C>.  A manifest declaring a higher version is ignored entirely,
#!   with a message naming the version of &ArtifactManager; that would be
#!   needed &ndash; it is never a parse error.</Item>
#! <Mark><C>package</C></Mark>
#! <Item>Optional.  If given, it must match the package the file belongs
#!   to.</Item>
#! <Mark><C>artifacts</C></Mark>
#! <Item>Mandatory.  Maps artifact names to declarations.  A name may consist
#!   of letters, digits, and the characters <C>.</C>, <C>_</C> and
#!   <C>-</C>.</Item>
#! </List>
#!
#! Within one artifact:
#!
#! <List>
#! <Mark><C>download</C></Mark>
#! <Item>Mandatory, a non-empty list of <E>alternatives</E>, tried in order.
#!   Mirrors and different archive formats use the same mechanism.  Each entry
#!   has a <C>url</C> and a <C>sha256</C>, and optionally a <C>format</C> and
#!   a <C>size</C>.  Entries that share a checksum are mirrors of one another
#!   and share one directory in the store; entries with different checksums
#!   are looked for separately, so it does not matter which one a given user
#!   happened to download.</Item>
#! <Mark><C>format</C></Mark>
#! <Item>One of <C>"tar.gz"</C>, <C>"tar.bz2"</C>, <C>"tar.xz"</C>,
#!   <C>"tar"</C>, <C>"zip"</C>, <C>"file"</C>, <C>"file.gz"</C>.  If it is
#!   omitted it is guessed from the URL.  A <C>"file.gz"</C> artifact is kept
#!   compressed on disk, since &GAP;'s
#!   <C>StringFile</C> decompresses transparently.
#!   </Item>
#! <Mark><C>sha256</C></Mark>
#! <Item>Mandatory.  The SHA256 checksum of the file that is downloaded, as a
#!   hex string.  <Ref Func="DescribeArtifactURL"/> computes it for you.</Item>
#! <Mark><C>size</C></Mark>
#! <Item>Optional, in bytes.  Worth giving: it lets &ArtifactManager; tell the
#!   user what a download is going to cost before it starts, and it is what
#!   the <C>MaxAutoDownloadSize</C> preference compares against.</Item>
#! <Mark><C>strip</C></Mark>
#! <Item>Optional, an integer.  If <C>1</C> and the archive unpacks to a
#!   single top-level directory, the contents of that directory are moved up
#!   one level.  Most tarballs want this.</Item>
#! <Mark><C>tree_sha256</C></Mark>
#! <Item>Optional.  A checksum of the unpacked data, computed by
#!   <C>AM_TreeSHA256</C>.  With it the install is checked once more
#!   after unpacking, and <Ref Func="VerifyArtifact"/> can re-check the
#!   installed files rather than just their sizes.  The exact encoding is
#!   still provisional; do not publish one yet.</Item>
#! <Mark><C>description</C>, <C>version</C>, <C>license</C>,
#!   <C>provenance</C></Mark>
#! <Item>Optional strings, shown by <Ref Func="ShowArtifacts"/>.  Recording
#!   where data came from and under which licence costs nothing now and cannot
#!   be reconstructed later.</Item>
#! <Mark><C>lazy</C></Mark>
#! <Item>Optional, a boolean.  Reserved: it will tell an installer whether to
#!   fetch this artifact ahead of time.  Today everything is fetched on first
#!   use.</Item>
#! </List>
#!
#! Fields that &ArtifactManager; does not know are ignored, and an artifact
#! whose <C>kind</C> it does not understand is skipped without affecting the
#! rest of the manifest.  This is deliberate: it is what lets later versions
#! add features without old versions choking on the file.

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

# Highest 'gapArtifactManifest' version we understand.
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
