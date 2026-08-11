#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# json.gd: reading JSON.
#
# We only ever *read* JSON, and only from files that may be untrusted (a
# manifest fetched from a web server must never be evaluated as GAP code).
# The 'json' package does this well, but it is a kernel extension, so it has
# to be compiled -- and requiring a compiled package for something whose whole
# purpose is to be adoptable everywhere defeats the purpose.  AtlasRep hit the
# same wall and ships its own parser (atlasrep/gap/json.g).
#
# So: use the 'json' package when it is there, and fall back to the small
# pure-GAP parser below when it is not.
#

# Parse the JSON document <str>.  Returns
#   rec( success := true,  value := <obj> )
# or
#   rec( success := false, error := <string> ).
#
# JSON objects become records, arrays become lists, strings become strings,
# integers become integers, other numbers become floats, and 'true', 'false'
# and 'null' become 'true', 'false' and 'fail'.  Note that 'null' and 'fail'
# are therefore indistinguishable; we never write 'null', and treat it as
# "absent" when reading.
DeclareGlobalFunction( "AM_JsonToGap" );

# Read and parse the JSON file <path>.  Same return value, plus a sensible
# error if the file cannot be read.
DeclareGlobalFunction( "AM_JsonFileToGap" );
