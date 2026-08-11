#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# fetch.gd: downloading, verifying, unpacking, installing.
#

#! @Chapter Using artifacts
#!
#! @Section Fetching

#! @Description
#!   Downloads the artifact <A>name</A> of package <A>pkg</A> if it is not
#!   available yet, and returns <K>true</K> on success and <K>false</K>
#!   otherwise.  If the artifact is already there, nothing happens.
#!
#!   Unlike <Ref Func="ArtifactDirectory"/>, this ignores the
#!   <C>MaxAutoDownloadSize</C> preference: calling it is an explicit request
#!   for the data, however big it is.
#! @Arguments pkg, name
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "FetchArtifact" );

#! @Description
#!   Returns the contents of the artifact <A>name</A> of package <A>pkg</A> as
#!   a string, without storing anything permanently.  Only artifacts
#!   consisting of a single file (format <C>"file"</C> or <C>"file.gz"</C>)
#!   can be read this way; for anything else use
#!   <Ref Func="ArtifactDirectory"/>.
#!
#!   If the artifact happens to be installed already, the local copy is used.
#!   Otherwise it is downloaded into a temporary directory, verified, read,
#!   and the temporary copy is discarded.  This is what to use on a machine
#!   where nothing may be written to disk.
#! @Arguments pkg, name
#! @Returns a string or <K>fail</K>
DeclareGlobalFunction( "ArtifactContents" );


#############################################################################
##
##  Internals.
##

# Locate an installed copy of <decl>.  Returns
#   rec( store, key, path, meta )
# or 'fail'.
DeclareGlobalFunction( "AM_Installed" );

# Download, verify, unpack and install <decl>.  <explicit> says whether the
# user asked for this by name, which switches off the size limit.
# Returns rec( success := true, path := <string> )
#      or rec( success := false, error := <string> ).
DeclareGlobalFunction( "AM_Install" );

# Fetch <url> to the file <target>.  Returns rec( success, error ).
DeclareGlobalFunction( "AM_Download" );

# The names of the members of an archive, or 'fail'.
DeclareGlobalFunction( "AM_ArchiveMembers" );

# 'true', or a string saying which member is unsafe.
DeclareGlobalFunction( "AM_CheckArchiveMembers" );
