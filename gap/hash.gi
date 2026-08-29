#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# hash.gi: SHA256 of files and strings.  See hash.gd.
#

BindGlobal( "AM_HexDigits", "0123456789abcdef" );

InstallGlobalFunction( AM_NormalizeHex,
function( str )
  if not IsString( str ) then
    return fail;
  fi;
  str := LowercaseString( ShallowCopy( str ) );
  if Length( str ) <> 64 or not ForAll( str, c -> c in AM_HexDigits ) then
    return fail;
  fi;
  return str;
end );

InstallGlobalFunction( AM_IsSHA256,
function( str )
  return AM_NormalizeHex( str ) <> fail;
end );

InstallGlobalFunction( AM_HexSHA256File,
function( path, prefix... )
  local s;

  if not IsExistingFile( path ) then
    return fail;
  fi;

  s := SHA256State();
  if not IsEmpty( prefix ) then
    UpdateSHA256( s, prefix[1] );
  fi;
  # 'false': the digest describes the bytes on disk, so a '.gz' file is not
  # decompressed on the way.
  if UpdateSHA256File( s, path, false ) = fail then
    return fail;
  fi;
  return HexSHA256( s );
end );

InstallGlobalFunction( AM_HexSHA256String,
function( str )
  return HexSHA256( str );
end );

BindGlobal( "AM_BytesOfHex",
function( hex )
  local res, i;
  res := "";
  for i in [ 1, 3 .. Length( hex ) - 1 ] do
    Add( res, CHAR_INT( 16 * Position( AM_HexDigits, hex[i] )
                        + Position( AM_HexDigits, hex[i+1] ) - 17 ) );
  od;
  return res;
end );

# The digest of a git object: its type, its length, a NUL, its body.
BindGlobal( "AM_GitObjectSHA256",
function( type, body )
  return AM_HexSHA256String( CopyToStringRep( Concatenation(
      type, " ", String( Length( body ) ), "\000", body ) ) );
end );

InstallGlobalFunction( AM_TreeSHA256,
function( dir )
  local empty, walk;

  if not IsDirectoryPath( dir ) then
    return fail;
  fi;

  empty := AM_GitObjectSHA256( "tree", "" );

  # The hash of one directory, as git computes it.
  walk := function( path )
    local entries, name, full, sub, size, hex, body, entry;

    entries := [];
    for name in Difference( DirectoryContents( path ), [ ".", ".." ] ) do
      full := Concatenation( path, "/", name );
      if IsDirectoryPath( full ) then
        sub := walk( full );
        if sub = fail then
          return fail;
        elif sub = empty then
          # git cannot store an empty directory, so neither do we.
          continue;
        fi;
        # A tree sorts as though its name ended in "/".
        Add( entries, [ Concatenation( name, "/" ), "40000", name, sub ] );
      else
        size := AM_FileSize( full );
        if size = fail then
          return fail;
        fi;
        # A git blob is its header followed by the contents, and the file
        # never has to be read into memory to hash it.
        hex := SHA256State();
        UpdateSHA256( hex, CopyToStringRep( Concatenation(
            "blob ", String( size ), "\000" ) ) );
        if UpdateSHA256File( hex, full, false ) = fail then
          return fail;
        fi;
        hex := HexSHA256( hex );
        if AM_IsExecutableFile( full ) then
          Add( entries, [ name, "100755", name, hex ] );
        else
          Add( entries, [ name, "100644", name, hex ] );
        fi;
      fi;
    od;

    SortBy( entries, e -> e[1] );
    body := "";
    for entry in entries do
      Append( body, entry[2] );
      Add( body, ' ' );
      Append( body, entry[3] );
      Add( body, '\000' );
      Append( body, AM_BytesOfHex( entry[4] ) );
    od;
    return AM_GitObjectSHA256( "tree", CopyToStringRep( body ) );
  end;

  return walk( dir );
end );
