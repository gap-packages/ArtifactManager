#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# compat.gi: things GAP does not (yet) provide.  See compat.gd for why.
#

BindGlobal( "AM_ProgramCache", rec() );

InstallGlobalFunction( AM_Program,
function( name )
  local path;
  if not IsBound( AM_ProgramCache.( name ) ) then
    path := PathSystemProgram( name );
    if path = fail then
      AM_ProgramCache.( name ) := fail;
    else
      AM_ProgramCache.( name ) := path;
    fi;
  fi;
  return AM_ProgramCache.( name );
end );

InstallGlobalFunction( AM_HaveIO,
function()
  return IsPackageLoaded( "io" ) and IsBoundGlobal( "IO_stat" );
end );

InstallGlobalFunction( AM_CallSafely,
function( f, args )
  local saved, caught;
  saved := BreakOnError;
  BreakOnError := false;
  caught := CALL_WITH_CATCH( f, args );
  BreakOnError := saved;
  if caught[1] = true then
    return rec( success := true, value := caught[2] );
  fi;
  return rec( success := false );
end );

InstallGlobalFunction( AM_Environment,
function( name )
  local env;
  env := GAPInfo.SystemEnvironment;
  if IsBound( env.( name ) ) and env.( name ) <> "" then
    return env.( name );
  fi;
  return fail;
end );


#############################################################################
##
#F  AM_Exec( <dir>, <prog>, <args> )
##
InstallGlobalFunction( AM_Exec,
function( dir, prog, args )
  local path, sh, out, stream, code, allargs;

  path := AM_Program( prog );
  if path = fail then
    return rec( code := -1, output := "",
                error := Concatenation( "the program '", prog,
                            "' was not found in your PATH" ) );
  fi;

  if dir = fail then
    dir := DirectoryCurrent();
  elif IsString( dir ) then
    dir := Directory( dir );
  fi;

  out := "";
  stream := OutputTextString( out, true );
  SetPrintFormattingStatus( stream, false );

  # TODO(U3): Process cannot redirect stderr.  Route through 'sh -c' with a
  # *constant* script; the command and its arguments become "$0" "$@", so
  # nothing is ever interpreted by the shell.  Drop this once gap#4657 lands.
  sh := AM_Program( "sh" );
  if sh <> fail then
    allargs := Concatenation( [ "-c", "\"$0\" \"$@\" 2>&1", path ], args );
    code := Process( dir, sh, InputTextNone(), stream, allargs );
  else
    code := Process( dir, path, InputTextNone(), stream, args );
  fi;
  CloseStream( stream );

  Info( InfoArtifactManager, 4, "AM_Exec: ", prog, " ", args,
        " -> code ", code );
  if code <> 0 then
    Info( InfoArtifactManager, 4, "AM_Exec: output: ", out );
  fi;

  return rec( code := code, output := out );
end );


#############################################################################
##
#F  AM_Now( )
#F  AM_TimeString( )
##
InstallGlobalFunction( AM_Now,
function()
  local res;
  # TODO(U1): GAP core should offer the current time; then this is one call.
  if AM_HaveIO() then
    return ValueGlobal( "IO_gettimeofday" )().tv_sec;
  fi;
  if AM_Program( "date" ) <> fail then
    res := AM_Exec( fail, "date", [ "+%s" ] );
    if res.code = 0 then
      res := Int( Filtered( res.output, c -> c in "0123456789" ) );
      if res <> fail then
        return res;
      fi;
    fi;
  fi;
  return fail;
end );

InstallGlobalFunction( AM_TimeString,
function()
  local res;
  if AM_Program( "date" ) <> fail then
    res := AM_Exec( fail, "date", [ "+%Y-%m-%dT%H:%M:%S" ] );
    if res.code = 0 then
      return Filtered( res.output, c -> c <> '\n' );
    fi;
  fi;
  res := AM_Now();
  if res = fail then
    return "unknown";
  fi;
  return Concatenation( "unix:", String( res ) );
end );


#############################################################################
##
#F  AM_FileSize( <path> )
##
InstallGlobalFunction( AM_FileSize,
function( path )
  local st, res, digits;

  # TODO(U7): GAP core should offer this.
  if AM_HaveIO() then
    st := ValueGlobal( "IO_stat" )( path );
    if st = fail then
      return fail;
    fi;
    return st.size;
  fi;

  if AM_Program( "wc" ) <> fail then
    res := AM_Exec( fail, "wc", [ "-c", path ] );
    if res.code = 0 then
      digits := First( SplitString( res.output, " \n\t" ), s -> s <> "" );
      if digits <> fail then
        return Int( digits );
      fi;
    fi;
  fi;

  return fail;
end );


#############################################################################
##
#F  AM_Rename( <old>, <new> )
##
InstallGlobalFunction( AM_Rename,
function( old, new )
  local res;

  # TODO(U8): GAP core should offer rename(2).  We rely on the *atomicity* of
  # this operation, which is why the fallback must stay within one filesystem:
  # 'mv' across devices degrades to a non-atomic copy.  Callers guarantee this
  # by staging inside the store; see AM_StagingDirectory.
  if AM_HaveIO() then
    return ValueGlobal( "IO_rename" )( old, new ) <> fail;
  fi;

  if AM_Program( "mv" ) <> fail then
    res := AM_Exec( fail, "mv", [ old, new ] );
    return res.code = 0;
  fi;

  Info( InfoArtifactManager, 1,
        "cannot move files: neither the IO package nor 'mv' is available" );
  return false;
end );

InstallGlobalFunction( AM_CopyFile,
function( src, dst )
  local res, data;

  if AM_Program( "cp" ) <> fail then
    res := AM_Exec( fail, "cp", [ src, dst ] );
    if res.code = 0 then
      return true;
    fi;
    Info( InfoArtifactManager, 2, "cp failed: ", res.output );
    return false;
  fi;

  # TODO(U6): no binary-safe read in GAP core, so this fallback mangles
  # '.gz' files, and on Windows translates line endings.  Last resort only.
  Info( InfoArtifactManager, 1,
        "no 'cp' found; copying via StringFile, which is not binary safe" );
  data := StringFile( src );
  if data = fail then
    return false;
  fi;
  return FileString( dst, data ) <> fail;
end );


#############################################################################
##
#F  CreateDirectoryRecursively( <path> )
##
BindGlobal( "AM_SplitPath",
function( path )
  return Filtered( SplitString( path, "/" ), s -> s <> "" and s <> "." );
end );

# Explain why <path> could not be created, as precisely as we can.
BindGlobal( "AM_DirectoryProblem",
function( path )
  local parts, cur, i, sofar;

  parts := AM_SplitPath( path );
  if StartsWith( path, "/" ) then
    sofar := "";
  else
    sofar := ".";
  fi;

  for i in [ 1 .. Length( parts ) ] do
    cur := Concatenation( sofar, "/", parts[i] );
    if not IsExistingFile( cur ) then
      if not IsDirectoryPath( sofar ) then
        return Concatenation( "'", sofar, "' is not a directory" );
      elif not IsWritableFile( sofar ) then
        return Concatenation( "'", sofar, "' is not writable" );
      fi;
      return Concatenation( "could not create '", cur, "': ",
                            LastSystemError().message );
    elif not IsDirectoryPath( cur ) then
      return Concatenation( "'", cur, "' exists but is not a directory" );
    fi;
    sofar := cur;
  od;

  return Concatenation( "could not create '", path, "'" );
end );

InstallGlobalFunction( CreateDirectoryRecursively,
function( path )
  local parts, sofar, part, cur;

  if not IsString( path ) then
    ErrorNoReturn( "<path> must be a string" );
  fi;
  path := UserHomeExpand( path );

  if IsDirectoryPath( path ) then
    return true;
  fi;

  parts := AM_SplitPath( path );
  if StartsWith( path, "/" ) then
    sofar := "";
  else
    sofar := ".";
  fi;

  for part in parts do
    cur := Concatenation( sofar, "/", part );
    if not IsDirectoryPath( cur ) then
      # Racing against another process is fine: if the directory exists
      # afterwards, whoever created it did our job for us.
      CreateDir( cur );
      if not IsDirectoryPath( cur ) then
        # Deliberately quiet: this is the "try" form, and a caller that
        # cares says so itself or uses CreateDirectoryRecursivelyOrError,
        # which reports which component failed and why.
        Info( InfoArtifactManager, 3, "could not create directory '", path,
              "': ", AM_DirectoryProblem( path ) );
        return fail;
      fi;
      if AM_HaveIO() then
        # TODO(U5): GAP's CreateDir uses mode 0777 masked by the umask, which
        # is usually what we want; but if the umask is hostile the directory
        # ends up unusable.  Make sure at least the owner can use it.
        if not ( IsWritableFile( cur ) and IsExecutableFile( cur ) ) then
          ValueGlobal( "IO_chmod" )( cur, 448 );  # 0700
        fi;
      fi;
    fi;
    sofar := cur;
  od;

  return true;
end );

InstallGlobalFunction( CreateDirectoryRecursivelyOrError,
function( path )
  if CreateDirectoryRecursively( path ) = fail then
    ErrorNoReturn( "could not create directory '", path, "': ",
                   AM_DirectoryProblem( UserHomeExpand( path ) ) );
  fi;
  return true;
end );


#############################################################################
##
#F  AM_DirectorySize( <path> )
##
InstallGlobalFunction( AM_DirectorySize,
function( path )
  local bytes, files, recurse;

  bytes := 0;
  files := 0;

  recurse := function( dir )
    local entry, sub;
    for entry in Difference( DirectoryContents( dir ), [ ".", ".." ] ) do
      sub := Concatenation( dir, "/", entry );
      if IsDirectoryPath( sub ) then
        recurse( sub );
      else
        files := files + 1;
        if bytes <> fail then
          entry := AM_FileSize( sub );
          if entry = fail then
            bytes := fail;
          else
            bytes := bytes + entry;
          fi;
        fi;
      fi;
    od;
  end;

  if not IsDirectoryPath( path ) then
    if IsExistingFile( path ) then
      return rec( bytes := AM_FileSize( path ), files := 1 );
    fi;
    return fail;
  fi;

  recurse( path );
  return rec( bytes := bytes, files := files );
end );


#############################################################################
##
#F  AM_IrregularFiles( <dir> )
##
InstallGlobalFunction( AM_IrregularFiles,
function( dir )
  local res, walk, st, kind, out;

  if AM_HaveIO() then
    res := [];
    walk := function( rel )
      local full, entry, st, kind;
      full := Concatenation( dir, rel );
      st := ValueGlobal( "IO_lstat" )( full );
      if st = fail then
        return;
      fi;
      # top four bits of the mode are the file type: 4 = directory,
      # 8 = regular file, anything else is not ours to install
      kind := QuoInt( st.mode mod 65536, 4096 );
      if kind = 4 then
        for entry in Difference( DirectoryContents( full ), [ ".", ".." ] ) do
          walk( Concatenation( rel, "/", entry ) );
        od;
      elif kind <> 8 then
        Add( res, rel );
      fi;
    end;
    for st in Difference( DirectoryContents( dir ), [ ".", ".." ] ) do
      walk( Concatenation( "/", st ) );
    od;
    return res;
  fi;

  if AM_Program( "find" ) <> fail then
    out := AM_Exec( fail, "find", [ dir, "!", "-type", "f", "!", "-type", "d" ] );
    if out.code = 0 then
      return Filtered( SplitString( out.output, "\n" ), s -> s <> "" );
    fi;
  fi;

  return fail;
end );


#############################################################################
##
#F  AM_SetTreeReadOnly( <path> ) . . . . . . . . . . . . . . . best effort
##
BindGlobal( "AM_Chmod",
function( path, mode )
  if AM_HaveIO() then
    ValueGlobal( "IO_chmod" )( path, mode );
  fi;
end );

InstallGlobalFunction( AM_SetTreeReadOnly,
function( path )
  local res;
  if not AM_HaveIO() then
    if AM_Program( "chmod" ) <> fail then
      AM_Exec( fail, "chmod", [ "-R", "a-w", path ] );
    fi;
    return;
  fi;
  res := function( p )
    local entry, sub;
    if IsDirectoryPath( p ) then
      for entry in Difference( DirectoryContents( p ), [ ".", ".." ] ) do
        res( Concatenation( p, "/", entry ) );
      od;
      # 0555.  The execute bit on a directory is what permits entering it,
      # so it must survive; dropping it makes the artifact unreadable.
      AM_Chmod( p, 365 );
    else
      AM_Chmod( p, 292 );   # 0444
    fi;
  end;
  res( path );
end );

InstallGlobalFunction( AM_SetTreeWritable,
function( path )
  local res;
  if not AM_HaveIO() then
    if AM_Program( "chmod" ) <> fail then
      AM_Exec( fail, "chmod", [ "-R", "u+w", path ] );
    fi;
    return;
  fi;
  res := function( p )
    local entry;
    if IsDirectoryPath( p ) then
      AM_Chmod( p, 448 );   # 0700
      for entry in Difference( DirectoryContents( p ), [ ".", ".." ] ) do
        res( Concatenation( p, "/", entry ) );
      od;
    else
      AM_Chmod( p, 384 );   # 0600
    fi;
  end;
  res( path );
end );


#############################################################################
##
#F  AM_HumanSize( <bytes> )
##
InstallGlobalFunction( AM_HumanSize,
function( bytes )
  local units, unit, val, frac;

  if bytes = fail then
    return "?";
  elif not IsInt( bytes ) then
    ErrorNoReturn( "<bytes> must be an integer or fail" );
  elif bytes < 1000 then
    return Concatenation( String( bytes ), " B" );
  fi;

  units := [ "kB", "MB", "GB", "TB", "PB" ];
  unit := 0;
  val := bytes;
  while val >= 1000000 and unit < Length( units ) - 1 do
    val := QuoInt( val, 1000 );
    unit := unit + 1;
  od;
  unit := unit + 1;

  # one decimal digit
  frac := QuoInt( val * 10 + 500, 1000 );
  return Concatenation( String( QuoInt( frac, 10 ) ), ".",
                        String( RemInt( frac, 10 ) ), " ", units[unit] );
end );
