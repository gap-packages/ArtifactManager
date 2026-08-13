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
#!   into <F>artifacts.json</F>: checksum, size, format, and the
#!   <C>tree_sha256</C> of the unpacked data.  Nothing is kept.
#!
#!   <A>strip</A> defaults to <C>1</C>, which is what almost every tarball
#!   wants; it must match the <C>strip</C> in the stanza, since the tree hash
#!   is taken after stripping.
#!
#!   This exists because a manifest cannot be written by hand: the tree hash
#!   comes from nowhere else.
#! @Arguments url[, strip]
#! @Returns a record with components <C>url</C>, <C>sha256</C>, <C>size</C>,
#!   <C>format</C>, <C>tree_sha256</C> and <C>strip</C>, or <K>fail</K>
DeclareGlobalFunction( "DescribeArtifactURL" );
