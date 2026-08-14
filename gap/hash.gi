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

# The kernel hands back eight 32-bit words; turn them into 64 hex digits.
BindGlobal( "AM_HexOfSHA256Words",
function( words )
  local res, w, hex;
  res := "";
  for w in words do
    hex := LowercaseString( HexStringInt( w ) );
    Append( res, ListWithIdenticalEntries( 8 - Length( hex ), '0' ) );
    Append( res, hex );
  od;
  return res;
end );

# The first 64-hex-digit token in <output>, or 'fail'.  Copes with the output
# of sha256sum ("<hex>  <file>"), shasum, and openssl ("SHA256(f)= <hex>").
BindGlobal( "AM_ExtractDigest",
function( output )
  local token;
  for token in SplitString( output, " \t\n=()" ) do
    if Length( token ) = 64 and ForAll( token, c -> c in AM_HexDigits ) then
      return token;
    fi;
  od;
  return fail;
end );

BindGlobal( "AM_MaxUnsafeHashSize", 64 * 1024 * 1024 );

# An argv string cannot carry a NUL byte, so a prefix that has one has to
# reach 'printf %b' as the two characters '\' and '0' instead.
BindGlobal( "AM_PrintfEscapes",
function( str )
  local res, c;
  res := "";
  for c in str do
    if c = '\000' then
      Append( res, "\\0" );
    elif c = '\\' then
      Append( res, "\\\\" );
    else
      Add( res, c );
    fi;
  od;
  return res;
end );

InstallGlobalFunction( AM_HexSHA256File,
function( path, prefix... )
  local f, state, chunk, prog, res, digest, size, data, script;

  if not IsExistingFile( path ) then
    return fail;
  fi;
  if IsEmpty( prefix ) then
    prefix := "";
  else
    prefix := prefix[1];
  fi;

  # (1) IO package: chunked and binary safe, constant memory.
  if AM_HaveIO() then
    f := ValueGlobal( "IO_File" )( path, "r" );
    if f <> fail then
      state := GAP_SHA256_INIT();
      GAP_SHA256_UPDATE( state, prefix );
      repeat
        chunk := ValueGlobal( "IO_Read" )( f, 1048576 );
        if IsString( chunk ) and Length( chunk ) > 0 then
          GAP_SHA256_UPDATE( state, chunk );
        fi;
      until not IsString( chunk ) or Length( chunk ) = 0;
      ValueGlobal( "IO_Close" )( f );
      if chunk = fail then
        Info( InfoArtifactManager, 1, "error while reading '", path, "'" );
        return fail;
      fi;
      return AM_HexOfSHA256Words( GAP_SHA256_FINAL( state ) );
    fi;
  fi;

  # (2) an external checksum tool.  A prefix has to reach it through a pipe;
  # 'printf' and 'cat' write it and the file in one stream.
  for prog in [ [ "sha256sum", [ path ], "sha256sum" ],
                [ "shasum", [ "-a", "256", path ], "shasum -a 256" ],
                [ "openssl", [ "dgst", "-sha256", path ],
                  "openssl dgst -sha256" ] ] do
    if AM_Program( prog[1] ) <> fail then
      if prefix = "" then
        res := AM_ExecQuiet( fail, prog[1], prog[2] );
      else
        script := Concatenation( "{ printf %b \"$0\"; cat \"$1\"; } | ",
                                 prog[3] );
        res := AM_ExecQuiet( fail, "sh",
                   [ "-c", script, AM_PrintfEscapes( prefix ), path ] );
      fi;
      if res.code = 0 then
        digest := AM_ExtractDigest( res.output );
        if digest <> fail then
          Info( InfoArtifactManager, 3, "hashed '", path, "' using ",
                prog[1] );
          return digest;
        fi;
      fi;
    fi;
  od;

  # (3) Last resort.  'StringFile' goes through 'InputTextFile', which
  # transparently gunzips files whose name ends in '.gz', and on systems that
  # distinguish text and binary mode also translates line endings -- either
  # of which silently produces the wrong digest.  We only get away with it
  # because everything we hash is staged under a name with no extension (see
  # AM_StagingDirectory), and we refuse to do it for large files.
  size := AM_FileSize( path );
  if size <> fail and size > AM_MaxUnsafeHashSize then
    Info( InfoArtifactManager, 1,
          "cannot compute the SHA256 checksum of '", path, "' (",
          AM_HumanSize( size ), "): please load the IO package, or install ",
          "one of 'sha256sum', 'shasum', 'openssl'" );
    return fail;
  fi;
  Info( InfoArtifactManager, 1,
        "computing a SHA256 checksum via StringFile; this is not binary ",
        "safe.  Load the IO package or install 'sha256sum' to be sure." );
  data := StringFile( path );
  if data = fail then
    return fail;
  fi;
  return LowercaseString( HexSHA256(
      CopyToStringRep( Concatenation( prefix, data ) ) ) );
end );

InstallGlobalFunction( AM_HexSHA256String,
function( str )
  return LowercaseString( HexSHA256( str ) );
end );

# 64 hex digits -> the 32 raw bytes they denote.
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
        hex := AM_HexSHA256File( full, CopyToStringRep( Concatenation(
                   "blob ", String( size ), "\000" ) ) );
        if hex = fail then
          return fail;
        fi;
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
