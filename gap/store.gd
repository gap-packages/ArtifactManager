#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# store.gd: where artifacts live on disk.
#

#! @Chapter The artifact store
#!
#! @Section Layout
#!
#! Downloaded artifacts are cached in a <E>store</E>, a directory laid out
#! like this:
#!
#! @BeginLog
#! <store>/
#!   CACHEDIR.TAG                        # tells backup tools to skip this tree
#!   store-info.g
#!   artifacts/<pkg>/<name>-<hash16>/    # the data itself
#!   meta/<pkg>/<name>-<hash16>.g        # metadata; its presence means "installed"
#!   used/<pkg>/<name>-<hash16>.g        # when this artifact was last used
#!   pins.g
#!   overrides.g
#!   tmp/                                # downloads in progress
#! @EndLog
#!
#! Here <C>hash16</C> is the first 16 digits of the SHA256 checksum of the
#! downloaded file.  Two things follow:
#!
#! <List>
#! <Item>A changed checksum installs to a <E>different</E> directory, so an
#!   out-of-date cache cannot be mistaken for current data.</Item>
#! <Item>Concurrent installs of the same artifact produce identical bytes, so
#!   the loser of the race uses the winner's copy.  No locking.</Item>
#! </List>
#!
#! The <F>tmp</F> subdirectory is a sibling of <F>artifacts</F> so that the
#! final move is a rename within one filesystem, and therefore atomic.
#!
#! @Section Choosing a store
#!
#! The store is chosen by the user preference <C>ArtifactStore</C>.  If it is
#! not set, &ArtifactManager; picks the first of these that works:
#!
#! <Enum>
#! <Item>the environment variable <C>ARTIFACTMANAGER_STORE</C> &ndash; the
#!   right knob for a multi-user machine or a container image, since it needs
#!   no per-user configuration;</Item>
#! <Item>a Julia scratchspace, when &GAP; runs inside Julia (as in
#!   <Package>Oscar</Package>);</Item>
#! <Item><C>GAPInfo.UserGapRoot</C><C>/artifacts</C>, normally
#!   <F>~/.gap/artifacts</F>;</Item>
#! <Item>the <C>gap/artifacts</C> subdirectory of <C>XDG_DATA_HOME</C>, or
#!   <F>~/.local/share/gap/artifacts</F> &ndash; this is what happens when
#!   &GAP; is started with <C>-r</C>;</Item>
#! <Item>nothing.  Artifacts are then downloaded into a temporary directory
#!   and discarded when &GAP; exits.</Item>
#! </Enum>
#!
#! The store is never a package directory: data that can be re-downloaded has
#! no business inside a package installation, which may well be read-only or
#! shared between users.
#!
#! Additional read-only stores can be listed in <C>ExtraArtifactStores</C>.
#! They are searched but never written to, so a system administrator can
#! populate <F>/usr/share/gap/artifacts</F> once and every user benefits.
#! Individual packages can be sent elsewhere entirely with
#! <C>ArtifactStoreOverrides</C>, for instance to put one large database on a
#! separate disk.

#! @Section Functions

#! @Description
#!   The directory in which artifacts belonging to <A>pkg</A> are stored.
#!   With no argument, the default store.  Returns the empty string if
#!   artifacts are not being stored permanently in this session.
#! @Arguments [pkg]
#! @Returns a string
DeclareGlobalFunction( "ArtifactStoreDirectory" );

#! @Description
#!   Prints a report of the stores in use and of the capabilities
#!   &ArtifactManager; has available, in particular which optional packages
#!   and external programs were found.  Useful when something does not work.
#! @Arguments
#! @Returns nothing
DeclareGlobalFunction( "ArtifactStoreDiagnostics" );

#! @Description
#!   Removes leftovers of interrupted downloads from the store, and returns
#!   the number of directories removed.
#! @Arguments
#! @Returns an integer
DeclareGlobalFunction( "CleanArtifactTemp" );


#############################################################################
##
##  Internals.
##

# The computed default for the 'ArtifactStore' preference.  Called by
# 'DeclareUserPreference' when the package is loaded, so it must be cheap and
# must not create anything.
DeclareGlobalFunction( "AM_DefaultStore" );

# All stores relevant for <pkg>, as a list of
#   rec( path := <string>, writable := <bool> )
# The first writable entry is where new artifacts get installed.
DeclareGlobalFunction( "AM_Stores" );

# The store to install into for <pkg>, created if necessary.  Returns the path,
# or "" for session-only mode, or 'fail' if nothing usable could be prepared.
DeclareGlobalFunction( "AM_WritableStore" );

# Path construction.  <key> is a record with components 'package', 'name' and
# 'sha256'.
DeclareGlobalFunction( "AM_PayloadPath" );
DeclareGlobalFunction( "AM_MetaPath" );
DeclareGlobalFunction( "AM_UsedPath" );
DeclareGlobalFunction( "AM_ShortHash" );

# A fresh, empty staging directory inside <store>/tmp, or 'fail'.
DeclareGlobalFunction( "AM_StagingDirectory" );

# Small GAP-record files.
DeclareGlobalFunction( "AM_ReadRecordFile" );
DeclareGlobalFunction( "AM_WriteRecordFile" );

# Record that <key> was used just now.
DeclareGlobalFunction( "AM_TouchUsed" );

# Refuse to delete anything that is not inside a store.
DeclareGlobalFunction( "AM_AssertInStore" );
DeclareGlobalFunction( "AM_RemoveTree" );

# Pins and overrides.
DeclareGlobalFunction( "AM_ReadPins" );
DeclareGlobalFunction( "AM_WritePins" );
DeclareGlobalFunction( "AM_ReadOverrides" );
DeclareGlobalFunction( "AM_WriteOverrides" );
DeclareGlobalFunction( "AM_OverrideFor" );
