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
  if Length( str ) > 64 or not ForAll( str, c -> c in AM_HexDigits ) then
    return fail;
  fi;
  return Concatenation( ListWithIdenticalEntries( 64 - Length( str ), '0' ),
                        str );
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

InstallGlobalFunction( AM_HexSHA256File,
function( path )
  local f, state, chunk, prog, res, digest, size, data;

  if not IsExistingFile( path ) then
    return fail;
  fi;

  # (1) IO package: chunked and binary safe, constant memory.
  if AM_HaveIO() then
    f := ValueGlobal( "IO_File" )( path, "r" );
    if f <> fail then
      state := GAP_SHA256_INIT();
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

  # (2) an external checksum tool.
  for prog in [ [ "sha256sum", [ path ] ],
                [ "shasum", [ "-a", "256", path ] ],
                [ "openssl", [ "dgst", "-sha256", path ] ] ] do
    if AM_Program( prog[1] ) <> fail then
      res := AM_Exec( fail, prog[1], prog[2] );
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
  return AM_NormalizeHex( HexSHA256( data ) );
end );

InstallGlobalFunction( AM_HexSHA256String,
function( str )
  return AM_NormalizeHex( HexSHA256( str ) );
end );
