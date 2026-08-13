#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# user.gd: what packages and users call.
#

#! @Chapter Using artifacts
#!
#! @Section From package code
#!
#! A package that needs its data does this:
#!
#! @BeginLog
#! dir := ArtifactDirectory( "transgrp", "dat32" );
#! f   := Filename( dir, "trans32.grp" );
#! @EndLog
#!
#! <Ref Func="ArtifactDirectory"/> downloads the data on the first call and
#! returns immediately on every later one.  It raises an error if the data
#! cannot be provided, and the error says what to do about it; use
#! <Ref Func="IsArtifactAvailable"/> if you would rather decide for yourself.
#!
#! A package should depend on &ArtifactManager; in
#! <C>NeededOtherPackages</C> if it cannot work without its data.  If the data
#! is optional, make it a <C>SuggestedOtherPackages</C> entry and guard the
#! calls with <C>IsPackageLoaded( "artifactmanager" )</C>.

#! @Description
#!   The directory holding the artifact <A>name</A> of package <A>pkg</A>, as
#!   a directory object.  If the artifact is not available yet it is
#!   downloaded, verified and unpacked first.
#!
#!   Raises an error if the artifact cannot be provided &ndash; because it is
#!   not declared, because no mirror could be reached, because every copy
#!   failed its checksum, because downloads are switched off, or because the
#!   artifact is larger than <C>MaxAutoDownloadSize</C>.  The message names
#!   the concrete next step in each case.
#! @Arguments pkg, name
#! @Returns a directory object
DeclareGlobalFunction( "ArtifactDirectory" );

#! @Description
#!   The name of the file <A>relpath</A> inside the artifact <A>name</A> of
#!   package <A>pkg</A>, downloading the artifact if necessary.  Without
#!   <A>relpath</A>, and if the artifact consists of a single file, the name
#!   of that file.
#! @Arguments pkg, name[, relpath]
#! @Returns a string
DeclareGlobalFunction( "ArtifactFile" );

#! @Description
#!   Whether the artifact <A>name</A> of package <A>pkg</A> is available
#!   locally.  Never downloads anything and never raises an error, so it is
#!   safe to call when deciding what a package can offer.
#! @Arguments pkg, name
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "IsArtifactAvailable" );

#! @Section Managing what is on disk

#! @Description
#!   Prints a table of all known artifacts, of the package <A>pkg</A> if one
#!   is given, together with how much space they take.
#! @Arguments [pkg]
#! @Returns nothing
DeclareGlobalFunction( "ShowArtifacts" );

#! @Description
#!   The same information as <Ref Func="ShowArtifacts"/>, as a list of records
#!   with components <C>package</C>, <C>name</C>, <C>description</C>,
#!   <C>status</C>, <C>path</C>, <C>bytes</C>, <C>sha256</C> and <C>urls</C>.
#!
#!   <C>status</C> is one of
#!   <C>"installed"</C>,
#!   <C>"absent"</C>,
#!   <C>"overridden"</C> (redirected to a local directory, see
#!     <Ref Func="OverrideArtifact"/>),
#!   <C>"incomplete"</C> (an interrupted download; use
#!     <Ref Func="CleanArtifactTemp"/>), or
#!   <C>"stale"</C> (data in the store that no installed package asks for any
#!     more &ndash; this is what to delete when disk space runs short).
#! @Arguments [pkg]
#! @Returns a list of records
DeclareGlobalFunction( "ArtifactInfo" );

#! @Description
#!   Checks an installed artifact.  <A>level</A> is one of
#!   <C>"marker"</C> (the data and its metadata are both present; instant),
#!   <C>"quick"</C> (also that the size and number of files still match what
#!   was recorded at installation time; the default), or
#!   <C>"full"</C> (re-read and re-hash everything).
#!
#!   <C>"full"</C> recomputes the artifact's own checksum from the installed
#!   files, so it catches corruption that leaves their sizes unchanged.
#! @Arguments pkg, name[, level]
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "VerifyArtifact" );

#! @Description
#!   Deletes the local copy of the artifact <A>name</A> of package
#!   <A>pkg</A>.  It will be downloaded again the next time it is needed.
#!   Overridden artifacts are never deleted.
#! @Arguments pkg, name
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "RemoveArtifact" );

#! @Description
#!   Deletes every locally stored artifact, or every one belonging to the
#!   package <A>pkg</A>, and returns how many were removed.
#! @Arguments [pkg]
#! @Returns an integer
DeclareGlobalFunction( "RemoveAllArtifacts" );

#! @Section Pins and overrides

#! @Description
#!   Marks the artifact <A>name</A> of package <A>pkg</A> as one that must be
#!   kept, whatever happens to the package that declares it.  <A>reason</A> is
#!   an optional note shown by <Ref Func="PinnedArtifacts"/>.
#!
#!   Pins matter to the garbage collection planned for a later version; they
#!   exist already so that anything you pin now is safe by the time it
#!   arrives.  They do not stop <Ref Func="RemoveArtifact"/>.
#! @Arguments pkg, name[, reason]
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "PinArtifact" );

#! @Description
#!   Undoes <Ref Func="PinArtifact"/>.
#! @Arguments pkg, name
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "UnpinArtifact" );

#! @Description
#!   The list of pinned artifacts, as records.
#! @Arguments
#! @Returns a list of records
DeclareGlobalFunction( "PinnedArtifacts" );

#! @Description
#!   Makes <Ref Func="ArtifactDirectory"/> return <A>path</A> for the artifact
#!   <A>name</A> of package <A>pkg</A>, instead of downloading anything.
#!
#!   This is how a system administrator points &GAP; at a copy of the data
#!   that is already on the machine.  An overridden artifact is never
#!   downloaded, verified or deleted by &ArtifactManager;: what is behind the
#!   override is somebody else's property.
#! @Arguments pkg, name, path
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "OverrideArtifact" );

#! @Description
#!   Undoes <Ref Func="OverrideArtifact"/>.
#! @Arguments pkg, name
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "UnoverrideArtifact" );
