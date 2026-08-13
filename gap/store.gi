#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# store.gi: where artifacts live on disk.  See store.gd.
#

BindGlobal( "AM_StoreFormat", 1 );

# Set on first use, so that "no store" still gives us somewhere to work.
BindGlobal( "AM_SessionState", rec( sessionStore := fail,
                                    stagingCounter := 0,
                                    touched := rec() ) );

BindGlobal( "AM_CacheDirTag", Concatenation(
  "Signature: 8a477f597d28d172789f06886806bc55\n",
  "# This file is a cache directory tag created by the GAP package\n",
  "# ArtifactManager.  Everything below this directory can be re-downloaded.\n",
  "# See https://bford.info/cachedir/\n" ) );


#############################################################################
##
#F  AM_DefaultStore( )
##
InstallGlobalFunction( AM_DefaultStore,
function()
  local stored, val, home;

  # A stored value wins.  We still get called in that case -- user preference
  # defaults are evaluated even when a value is already present -- so return
  # early rather than doing pointless filesystem probing.  (AtlasRep does the
  # same, and calls the behaviour a bug in the preference machinery.)
  stored := UserPreference( "ArtifactManager", "ArtifactStore" );
  if stored <> fail then
    return stored;
  fi;

  val := AM_Environment( "ARTIFACTMANAGER_STORE" );
  if val <> fail then
    return val;
  fi;

  # Not a Julia scratchspace when running inside Oscar, though AtlasRep does
  # that: it would give someone who uses both Oscar and plain GAP two copies
  # of every artifact, and Julia's scratchspace collector could delete data
  # our own bookkeeping still records as present.  Anyone who does want a
  # separate store there can set ARTIFACTMANAGER_STORE above.
  if GAPInfo.UserGapRoot <> fail then
    return Concatenation( GAPInfo.UserGapRoot, "/artifacts" );
  fi;

  # 'gap -r' disables the user GAP root; fall back to the XDG location.
  val := AM_Environment( "XDG_DATA_HOME" );
  if val <> fail then
    return Concatenation( val, "/gap/artifacts" );
  fi;
  home := AM_Environment( "HOME" );
  if home <> fail then
    return Concatenation( home, "/.local/share/gap/artifacts" );
  fi;

  return "";
end );


#############################################################################
##
#F  AM_Stores( [<pkg>] )
##
BindGlobal( "AM_IsUsableStore",
function( path )
  return path <> "" and IsDirectoryPath( path ) and IsWritableFile( path );
end );

InstallGlobalFunction( AM_Stores,
function( arg )
  local pkg, res, main, overrides, extra, path;

  if Length( arg ) = 0 then
    pkg := fail;
  else
    pkg := LowercaseString( arg[1] );
  fi;

  res := [];
  main := fail;

  if pkg <> fail then
    path := AM_Environment( Concatenation( "ARTIFACTMANAGER_STORE_",
                                UppercaseString( pkg ) ) );
    if path <> fail then
      main := path;
    else
      overrides := UserPreference( "ArtifactManager", "ArtifactStoreOverrides" );
      if IsRecord( overrides ) and IsBound( overrides.( pkg ) ) then
        main := overrides.( pkg );
      fi;
    fi;
  fi;

  if main = fail then
    main := UserPreference( "ArtifactManager", "ArtifactStore" );
    if main = fail then
      main := "";
    fi;
  fi;

  if main <> "" then
    Add( res, rec( path := UserHomeExpand( main ), writable := true ) );
  fi;

  extra := UserPreference( "ArtifactManager", "ExtraArtifactStores" );
  if IsList( extra ) then
    for path in extra do
      if IsString( path ) and path <> "" then
        Add( res, rec( path := UserHomeExpand( path ), writable := false ) );
      fi;
    od;
  fi;

  return res;
end );

InstallGlobalFunction( ArtifactStoreDirectory,
function( arg )
  local stores;
  stores := CallFuncList( AM_Stores, arg );
  stores := Filtered( stores, s -> s.writable );
  if IsEmpty( stores ) then
    return "";
  fi;
  return stores[1].path;
end );


#############################################################################
##
#F  AM_WritableStore( [<pkg>] )
##
BindGlobal( "AM_InitialiseStore",
function( path )
  local tag, info;

  if CreateDirectoryRecursively( path ) = fail then
    return false;
  fi;

  tag := Concatenation( path, "/CACHEDIR.TAG" );
  if not IsExistingFile( tag ) then
    FileString( tag, AM_CacheDirTag );
  fi;

  info := Concatenation( path, "/store-info.g" );
  if not IsExistingFile( info ) then
    AM_WriteRecordFile( info, rec( storeFormat := AM_StoreFormat,
                                   createdBy := "ArtifactManager",
                                   createdAt := AM_TimeString() ) );
  fi;

  return true;
end );

BindGlobal( "AM_SessionStore",
function()
  local dir;
  if AM_SessionState.sessionStore = fail then
    dir := DirectoryTemporary();
    if dir = fail then
      return fail;
    fi;
    AM_SessionState.sessionStore := Filename( dir, "store" );
    AM_InitialiseStore( AM_SessionState.sessionStore );
    Info( InfoArtifactManager, 1,
          "no artifact store is configured, so downloaded data will be ",
          "discarded when GAP exits.  Set the user preference ",
          "ArtifactManager/ArtifactStore, or the environment variable ",
          "ARTIFACTMANAGER_STORE, to keep it." );
  fi;
  return AM_SessionState.sessionStore;
end );

InstallGlobalFunction( AM_WritableStore,
function( arg )
  local stores, s;

  stores := Filtered( CallFuncList( AM_Stores, arg ), x -> x.writable );
  for s in stores do
    if AM_InitialiseStore( s.path ) then
      return s.path;
    fi;
    Info( InfoArtifactManager, 1, "the artifact store '", s.path,
          "' is not usable: ", AM_DirectoryProblem( s.path ) );
  od;

  return AM_SessionStore();
end );


#############################################################################
##
##  Paths.
##
InstallGlobalFunction( AM_ShortHash,
function( sha )
  sha := AM_NormalizeHex( sha );
  if sha = fail then
    ErrorNoReturn( "<sha> is not a SHA256 digest" );
  fi;
  return sha{ [ 1 .. 16 ] };
end );

# <store>/<sub>/<pkg>/<name>/<sha256><suffix>.  The name is its own path
# component because a name may contain '-', so "<name>-<hash>" could not be
# taken apart again; and the hash is not truncated because there is no longer
# any reason to.
BindGlobal( "AM_KeyPath",
function( store, sub, key, suffix )
  return Concatenation( store, "/", sub, "/", LowercaseString( key.package ),
             "/", key.name, "/", key.sha256, suffix );
end );

InstallGlobalFunction( AM_PayloadPath,
function( store, key )
  return AM_KeyPath( store, "artifacts", key, "" );
end );

InstallGlobalFunction( AM_MetaPath,
function( store, key )
  return AM_KeyPath( store, "meta", key, ".g" );
end );

InstallGlobalFunction( AM_UsedPath,
function( store, key )
  return AM_KeyPath( store, "used", key, ".g" );
end );


#############################################################################
##
#F  AM_StagingDirectory( <store> )
##
InstallGlobalFunction( AM_StagingDirectory,
function( store )
  local base, pid, dir;

  # The staging area *must* be inside the store: the install step relies on
  # rename(2) being atomic, and that only holds within one filesystem.
  base := Concatenation( store, "/tmp" );
  if CreateDirectoryRecursively( base ) = fail then
    return fail;
  fi;

  if AM_HaveIO() then
    pid := String( ValueGlobal( "IO_getpid" )() );
  else
    pid := "x";
  fi;

  repeat
    AM_SessionState.stagingCounter := AM_SessionState.stagingCounter + 1;
    dir := Concatenation( base, "/am-", pid, "-",
                          String( AM_SessionState.stagingCounter ) );
  until not IsExistingFile( dir );

  if CreateDirectoryRecursively( dir ) = fail then
    return fail;
  fi;
  return dir;
end );


#############################################################################
##
##  Small record files.
##
InstallGlobalFunction( AM_ReadRecordFile,
function( path )
  local f, caught;

  if not IsExistingFile( path ) then
    return fail;
  fi;
  f := ReadAsFunction( path );
  if f = fail then
    Info( InfoArtifactManager, 1, "cannot read '", path, "'" );
    return fail;
  fi;
  caught := AM_CallSafely( f, [] );
  if not caught.success then
    Info( InfoArtifactManager, 1, "'", path, "' is corrupt and is being ",
          "ignored; remove it if this persists" );
    return fail;
  fi;
  return caught.value;
end );

BindGlobal( "AM_DirName",
function( path )
  local i;
  i := Length( path );
  while i > 0 and path[i] <> '/' do
    i := i - 1;
  od;
  if i = 0 then
    return ".";
  elif i = 1 then
    return "/";
  fi;
  return path{ [ 1 .. i - 1 ] };
end );

InstallGlobalFunction( AM_WriteRecordFile,
function( path, r )
  local tmp, out;

  if CreateDirectoryRecursively( AM_DirName( path ) ) = fail then
    return false;
  fi;

  tmp := Concatenation( path, ".new" );
  out := OutputTextFile( tmp, false );
  if out = fail then
    Info( InfoArtifactManager, 1, "cannot write '", tmp, "'" );
    return false;
  fi;
  SetPrintFormattingStatus( out, false );
  PrintTo( out, "# written by the GAP package ArtifactManager\n" );
  PrintTo( out, "return ", r, ";\n" );
  CloseStream( out );

  # Replace the old file in one step, so a reader never sees a partial record.
  if IsExistingFile( path ) then
    RemoveFile( path );
  fi;
  if not AM_Rename( tmp, path ) then
    RemoveFile( tmp );
    return false;
  fi;
  return true;
end );


#############################################################################
##
#F  AM_TouchUsed( <store>, <key> )
##
InstallGlobalFunction( AM_TouchUsed,
function( store, key )
  local id, path, now;

  # Once per artifact per session is enough; this is a hint for the future
  # garbage collector, not an audit log.
  id := Concatenation( store, "|", key.package, "|", key.name, "|",
                       AM_ShortHash( key.sha256 ) );
  if IsBound( AM_SessionState.touched.( id ) ) then
    return;
  fi;
  AM_SessionState.touched.( id ) := true;

  now := AM_Now();
  if now = fail then
    # TODO(U1): without a wall clock we cannot record this at all, and the
    # recency sweep planned for the garbage collector will have nothing to go
    # on.  Say so once rather than silently inventing a timestamp.
    Info( InfoArtifactManager, 3,
          "cannot record last-use time: no clock available" );
    return;
  fi;

  path := AM_UsedPath( store, key );
  if CreateDirectoryRecursively(
         Concatenation( store, "/used/", LowercaseString( key.package ) ) )
       = fail then
    return;
  fi;
  AM_WriteRecordFile( path, rec( lastUsed := now,
                                  package := key.package,
                                  name := key.name,
                                  sha256 := key.sha256 ) );
end );


#############################################################################
##
##  Deletion, guarded.
##
InstallGlobalFunction( AM_AssertInStore,
function( path )
  local stores, s;

  path := UserHomeExpand( path );
  stores := AM_Stores();
  if AM_SessionState.sessionStore <> fail then
    Add( stores, rec( path := AM_SessionState.sessionStore, writable := true ) );
  fi;

  for s in stores do
    if s.path <> "" and StartsWith( path, Concatenation( s.path, "/" ) ) then
      return true;
    fi;
  od;

  ErrorNoReturn( "refusing to touch '", path,
                 "', which is not inside an artifact store" );
end );

InstallGlobalFunction( AM_RemoveTree,
function( path )
  AM_AssertInStore( path );
  if not IsExistingFile( path ) then
    return true;
  fi;
  if not IsDirectoryPath( path ) then
    return RemoveFile( path ) = true;
  fi;
  AM_SetTreeWritable( path );
  RemoveDirectoryRecursively( path );
  return not IsExistingFile( path );
end );


#############################################################################
##
#F  CleanArtifactTemp( )
##
InstallGlobalFunction( CleanArtifactTemp,
function()
  local count, stores, s, tmp, entry, path;

  count := 0;
  stores := Filtered( AM_Stores(), x -> x.writable );
  if AM_SessionState.sessionStore <> fail then
    Add( stores, rec( path := AM_SessionState.sessionStore, writable := true ) );
  fi;

  for s in stores do
    tmp := Concatenation( s.path, "/tmp" );
    if IsDirectoryPath( tmp ) then
      for entry in Difference( DirectoryContents( tmp ), [ ".", ".." ] ) do
        path := Concatenation( tmp, "/", entry );
        Info( InfoArtifactManager, 2, "removing leftover ", path );
        if AM_RemoveTree( path ) then
          count := count + 1;
        fi;
      od;
    fi;
  od;

  return count;
end );


#############################################################################
##
##  Pins and overrides.
##
BindGlobal( "AM_PinsPath",
function( store )
  return Concatenation( store, "/pins.g" );
end );

BindGlobal( "AM_OverridesPath",
function( store )
  return Concatenation( store, "/overrides.g" );
end );

InstallGlobalFunction( AM_ReadPins,
function()
  local store, r;
  store := ArtifactStoreDirectory();
  if store = "" then
    return rec();
  fi;
  r := AM_ReadRecordFile( AM_PinsPath( store ) );
  if not IsRecord( r ) then
    return rec();
  fi;
  return r;
end );

InstallGlobalFunction( AM_WritePins,
function( pins )
  local store;
  store := AM_WritableStore();
  if store = fail or store = "" then
    return false;
  fi;
  return AM_WriteRecordFile( AM_PinsPath( store ), pins );
end );

InstallGlobalFunction( AM_ReadOverrides,
function()
  local store, r;
  store := ArtifactStoreDirectory();
  if store = "" then
    return rec();
  fi;
  r := AM_ReadRecordFile( AM_OverridesPath( store ) );
  if not IsRecord( r ) then
    return rec();
  fi;
  return r;
end );

InstallGlobalFunction( AM_WriteOverrides,
function( ov )
  local store;
  store := AM_WritableStore();
  if store = fail or store = "" then
    return false;
  fi;
  return AM_WriteRecordFile( AM_OverridesPath( store ), ov );
end );

InstallGlobalFunction( AM_OverrideFor,
function( pkg, name )
  local ov, key;
  ov := AM_ReadOverrides();
  key := Concatenation( LowercaseString( pkg ), "/", name );
  if IsBound( ov.( key ) ) and IsString( ov.( key ) ) and ov.( key ) <> "" then
    return UserHomeExpand( ov.( key ) );
  fi;
  return fail;
end );


#############################################################################
##
#F  ArtifactStoreDiagnostics( )
##
InstallGlobalFunction( ArtifactStoreDiagnostics,
function()
  local stores, s, prog, path, missing;

  Print( "ArtifactManager diagnostics\n" );
  Print( "---------------------------\n" );

  stores := AM_Stores();
  if IsEmpty( stores ) then
    Print( "stores:      none configured; artifacts are kept for this ",
           "session only\n" );
  else
    for s in stores do
      Print( "store:       ", s.path );
      if not s.writable then
        Print( "   (read only)" );
      elif not IsExistingFile( s.path ) then
        Print( "   (does not exist yet)" );
      elif not IsWritableFile( s.path ) then
        Print( "   (NOT WRITABLE)" );
      fi;
      Print( "\n" );
    od;
  fi;
  if AM_SessionState.sessionStore <> fail then
    Print( "session:     ", AM_SessionState.sessionStore,
           "   (temporary)\n" );
  fi;

  Print( "\n" );
  Print( "IO package:  ", AM_HaveIO() );
  if not AM_HaveIO() then
    Print( "   (file sizes, atomic rename and binary safe hashing ",
           "fall back to external programs)" );
  fi;
  Print( "\n" );
  Print( "json:        ", IsPackageLoaded( "json" ) );
  if not IsPackageLoaded( "json" ) then
    Print( "   (using the built-in fallback parser)" );
  fi;
  Print( "\n" );
  Print( "utils:       ", IsPackageLoaded( "utils" ), "\n" );
  Print( "clock:       " );
  if AM_Now() = fail then
    Print( "unavailable -- last-use times are not being recorded\n" );
  else
    Print( AM_TimeString(), "\n" );
  fi;

  Print( "\n" );
  missing := [];
  for prog in [ "tar", "unzip", "sha256sum", "shasum", "openssl", "curl",
                "wget", "mv", "cp", "sh" ] do
    path := AM_Program( prog );
    if path = fail then
      Add( missing, prog );
    else
      Print( "found:       ", prog, " at ", path, "\n" );
    fi;
  od;
  if not IsEmpty( missing ) then
    Print( "not found:   ", JoinStringsWithSeparator( missing, ", " ), "\n" );
  fi;
end );
