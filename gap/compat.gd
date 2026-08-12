#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# compat.gd: things GAP does not (yet) provide.
#
# Every function in this file exists only because &GAP; itself is missing
# something.  Each one carries a TODO naming the upstream issue that should
# make it go away; when that lands, delete the shim rather than keeping it.
# The point of collecting them in one file is that the file should shrink.
#

#! @Chapter Utilities
#!
#! This chapter documents the one function in &ArtifactManager; that is of
#! general interest beyond artifact handling.  The remaining helpers in
#! <F>gap/compat.gd</F> are undocumented on purpose: they only paper over
#! functionality missing from &GAP;, and are meant to disappear.

#! @Section Directories

#! @Description
#!   Creates the directory <A>path</A>, together with any missing parent
#!   directories, and returns <K>true</K>.  If the directory already exists,
#!   nothing happens and <K>true</K> is returned as well.
#!
#!   If the directory cannot be created, <K>fail</K> is returned quietly.  Use
#!   <Ref Func="CreateDirectoryRecursivelyOrError"/> to get an error instead,
#!   which explains <E>which</E> path component could not be created and
#!   <E>why</E>.
#!
#!   A leading <C>~</C> in <A>path</A> is expanded as by
#!   <Ref Func="UserHomeExpand" BookName="ref"/>.
#! @Arguments path
#! @Returns <K>true</K> or <K>fail</K>
DeclareGlobalFunction( "CreateDirectoryRecursively" );

#! @Description
#!   Like <Ref Func="CreateDirectoryRecursively"/>, but raises an error
#!   describing the problem instead of returning <K>fail</K>.
#! @Arguments path
#! @Returns <K>true</K>
DeclareGlobalFunction( "CreateDirectoryRecursivelyOrError" );

# TODO(U5): propose CreateDirectoryRecursively for the GAP library; see
#   https://github.com/gap-system/gap/issues/4285
# The diagnostic below (naming the deepest existing ancestor and the reason)
# is the part that AutoDoc_CreateDirIfMissing and PKGMAN_CreateDirRecursively
# both lack.


#############################################################################
##
##  Internal helpers.  Not documented, not part of the API.
##

# TODO(U1): GAP has no wall clock. 'Runtime()' is CPU time.  We need real time
# for the last-used stamps that the future garbage collector reads.
# Returns the number of seconds since the epoch, or 'fail' if we cannot tell.
DeclareGlobalFunction( "AM_Now" );

# TODO(U1): a human readable timestamp for the same reason.
DeclareGlobalFunction( "AM_TimeString" );

# TODO(U7): GAP has no way to ask for the size of a file.
# Returns an integer, or 'fail'.
DeclareGlobalFunction( "AM_FileSize" );

# TODO(U8): GAP has no rename/move.  Atomic same-filesystem rename is what
# makes our install lock-free, so this one really wants to be in the kernel.
# Returns 'true' or 'false'.
DeclareGlobalFunction( "AM_Rename" );

# Copy a single file.  Returns 'true' or 'false'.
DeclareGlobalFunction( "AM_CopyFile" );

# TODO(U3, U4): run <prog> with the argument list <args> in the directory
# <dir>, and return 'rec( code := <int>, output := <string> )'.
#
# Unlike Exec and unlike PackageManager's PKGMAN_Exec, no shell interprets the
# arguments, so paths containing spaces or shell metacharacters are safe.
# stderr is captured only when a POSIX 'sh' is available, via the fixed script
#   "$0" "$@" 2>&1
# which interpolates nothing and is therefore still injection-free.  Once
# gap#4657 (Process and stderr) and gap#5103 (Exec2) land, this whole function
# is a call to Exec2.
DeclareGlobalFunction( "AM_Exec" );

# Absolute path of the external program <name>, or 'fail'.  Cached.
DeclareGlobalFunction( "AM_Program" );

# 'true' if the IO package is loaded and usable.
DeclareGlobalFunction( "AM_HaveIO" );

# Total size in bytes and number of regular files below <path>, as
# 'rec( bytes := <int>, files := <int> )'.  'bytes' may be 'fail'.
DeclareGlobalFunction( "AM_DirectorySize" );

# Relative paths of everything below <dir> that is neither a regular file nor
# a directory: symbolic links, sockets, fifos, devices.  Returns 'fail' if the
# check cannot be made at all.
DeclareGlobalFunction( "AM_IrregularFiles" );

# Make <path> and everything below it read-only.  Best effort; returns nothing.
DeclareGlobalFunction( "AM_SetTreeReadOnly" );
DeclareGlobalFunction( "AM_SetTreeWritable" );

# "1.4 GB" and friends.
DeclareGlobalFunction( "AM_HumanSize" );

# The value of the environment variable <name>, or 'fail' if unset or empty.
DeclareGlobalFunction( "AM_Environment" );

# Call <f> with <args>, returning 'rec( success := true, value := <v> )' or
# 'rec( success := false )'.
#
# 'CALL_WITH_CATCH' on its own is not enough: GAP's 'Error' opens the break
# loop first, and CALL_WITH_CATCH only regains control once something quits
# it.  In a non-interactive session that is a hang.  Clearing 'BreakOnError'
# around the call is what actually makes catching work.
DeclareGlobalFunction( "AM_CallSafely" );
