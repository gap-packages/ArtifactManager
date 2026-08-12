#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# hash.gd: SHA256 of files and strings.
#

# Normalise a SHA256 hex digest: lowercase, and left-padded to 64 characters.
#
# The padding is not cosmetic.  'HexSHA256' in GAP 4.12 to 4.15 formats the
# digest with 'HexStringInt', which drops leading zero digits, so one digest in
# 256 comes back shorter than 64 characters -- and one in 65536 shorter by two,
# and so on.  GAP 4.16 pads (lib/files.gi), but we support 4.13, and package
# authors will have generated their checksums on whatever GAP they had.  So we
# normalise *both* the value we compute and the value we read from a manifest.
# AtlasRep does the same thing for the same reason; see AGR_ChecksumFits in
# atlasrep/gap/access.gi.
#
# Returns 'fail' if <str> is not a hex string of at most 64 digits.
DeclareGlobalFunction( "AM_NormalizeHex" );

# 'true' if <str> normalises to a valid SHA256 digest.
DeclareGlobalFunction( "AM_IsSHA256" );

# SHA256 of the *bytes* of the file <path>, as 64 lowercase hex digits,
# or 'fail'.
#
# TODO(U2): GAP should have 'HexSHA256File'.  The kernel already has the
# pieces -- GAP_SHA256_INIT/UPDATE/FINAL in src/sha256.c -- and lib/files.gi
# carries a TODO about exactly this.  Today 'HexSHA256(<stream>)' does
# 'ReadAll', i.e. it pulls the whole file into memory, and the only binary
# safe way to read a file at all is via the IO package.  So this function is
# three implementations where there should be one call.
DeclareGlobalFunction( "AM_HexSHA256File" );

# SHA256 of a string, normalised.
DeclareGlobalFunction( "AM_HexSHA256String" );

# The canonical SHA256 digest of the directory tree <dir>, or 'fail'.
#
# PROVISIONAL: the encoding below must be agreed with lgoettgens/ArtifactManager
# before any 'tree_sha256' is published; see gap-packages/ArtifactManager#1.
#
# Hashed input, with no separators beyond those shown:
#
#   for every entry, ordered by its relative path compared byte-wise,
#     "d\0" <relative path> "\0"                       for a directory
#     "f\0" <relative path> "\0" <size in decimal> "\0" <contents>
#                                                      for a regular file
#
# Relative paths start with "/" and use "/" as separator.  Modes, owners and
# timestamps are excluded: they depend on the umask and the archiver, not on
# the data.  Directories are included so that an empty one is not invisible.
# Symbolic links and special files cannot occur, since an archive containing
# them is rejected before this runs.
DeclareGlobalFunction( "AM_TreeSHA256" );
