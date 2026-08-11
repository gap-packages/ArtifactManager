#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
#! @Chapter Introduction
#!
#! Many &GAP; packages come with large data sets: tables of groups, lists of
#! simplicial complexes, factorisation tables, and so on.  Shipping those
#! inside the package archive makes the package huge for everybody, including
#! the users who never touch the data.  The traditional alternatives are worse:
#! telling users to download a tarball by hand and unpack it in the right
#! place, or rolling a bespoke download function per package.
#!
#! &ArtifactManager; offers a common mechanism instead.  A package declares its
#! <E>artifacts</E> &ndash; named blobs of data living on a web server &ndash;
#! in a file <F>artifacts.json</F> next to its <F>PackageInfo.g</F>.  When the
#! package first needs one, &ArtifactManager; downloads it, verifies it against
#! the declared SHA256 checksum, unpacks it, and hands back a directory.  The
#! data is cached in a location the user controls, and can be listed and
#! removed again.
#!
#! @Section A first example
#!
#! Suppose the package <Package>transgrp</Package> declared an artifact
#! <C>"dat32"</C>.  Then its code obtains the data with
#!
#! @BeginLog
#! dir := ArtifactDirectory( "transgrp", "dat32" );
#! @EndLog
#!
#! which downloads the data if it is not there yet, and otherwise returns
#! immediately.  A user can see what is taking up space with
#!
#! @BeginLog
#! ShowArtifacts();
#! @EndLog
#!
#! and reclaim it with <Ref Func="RemoveArtifact"/>.
#!
#! @Section Vocabulary
#!
#! <List>
#! <Mark>artifact</Mark>
#! <Item>A named, versioned blob of data belonging to a package, identified by
#!   the SHA256 checksum of the file it is downloaded from.</Item>
#! <Mark>declaration</Mark>
#! <Item>The description of an artifact: what it is called, where to download
#!   it from (possibly from several mirrors), its checksum, and how to unpack
#!   it.  See the chapter on declaring artifacts.</Item>
#! <Mark>store</Mark>
#! <Item>The directory in which downloaded artifacts are cached.  See
#!   the chapter on the artifact store.</Item>
#! </List>

#! @Chapter Using artifacts

#! @Section Information messages

#! @Description
#!   Info class of the &ArtifactManager; package.  The default level is 1.
#!   <List>
#!   <Mark>1</Mark><Item>problems the user must know about: a checksum
#!     mismatch, a mirror that could not be reached, a store that is not
#!     writable &ndash; and the announcement of a download that is going to
#!     take a while.</Item>
#!   <Mark>2</Mark><Item>progress: downloading, verifying, extracting.</Item>
#!   <Mark>3</Mark><Item>details: which mirror, which download backend, which
#!     external program.</Item>
#!   <Mark>4</Mark><Item>full command lines and their output.</Item>
#!   </List>
DeclareInfoClass( "InfoArtifactManager" );
