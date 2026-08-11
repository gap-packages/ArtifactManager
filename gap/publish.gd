#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# publish.gd: helping package authors write artifacts.json.
#

#! @Chapter Declaring artifacts
#!
#! @Section Writing the declaration

#! @Description
#!   Downloads <A>url</A>, computes its SHA256 checksum and size, and prints a
#!   JSON fragment ready to be pasted into <F>artifacts.json</F>.  The file is
#!   not kept.
#!
#!   This exists because the alternative is every package author computing a
#!   checksum by hand, and getting it wrong.
#! @Arguments url
#! @Returns a record with components <C>url</C>, <C>sha256</C>, <C>size</C>
#!   and <C>format</C>, or <K>fail</K>
DeclareGlobalFunction( "DescribeArtifactURL" );
