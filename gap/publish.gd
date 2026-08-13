#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# publish.gd: helping package authors write artifacts.json.
#

#! @Chapter Declaring artifacts
#!
#! @Section Writing the declaration

#! @Description
#!   Downloads <A>url</A>, unpacks it, and prints the artifact stanza to paste
#!   into <F>artifacts.json</F>: the download checksum, size and format, and
#!   the checksum of the artifact itself.  Nothing is kept.
#!
#!   <A>name</A> is the artifact name, which for a file artifact is also its
#!   file name.  <A>format</A> says what to do with the download; without it
#!   the bytes are inspected and a format suggested, which is a suggestion for
#!   you to confirm rather than something &ArtifactManager; would ever do at
#!   run time.
#!
#!   This exists because a manifest cannot be written by hand: the artifact
#!   checksum comes from nowhere else.
#! @Arguments url[, name[, format]]
#! @Returns a record with components <C>url</C>, <C>sha256</C>, <C>size</C>,
#!   <C>format</C>, <C>artifactSha256</C> and <C>isDirectory</C>, or
#!   <K>fail</K>
DeclareGlobalFunction( "DescribeArtifactURL" );

#! @Description
#!   Fetches every source of every artifact of <A>pkg</A> and checks it
#!   against the manifest: the download checksum, the size, and the checksum
#!   of the unpacked data.  Prints a report and returns whether everything
#!   agreed.
#!
#!   This is what catches a mirror that has been re-uploaded, which otherwise
#!   only shows up for the user whose download happens to pick it.  Meant to
#!   be run from CI.
#! @Arguments pkg
#! @Returns <K>true</K> or <K>false</K>
DeclareGlobalFunction( "ValidateArtifacts" );
