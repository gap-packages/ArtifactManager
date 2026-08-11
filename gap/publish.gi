#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# publish.gi: helping package authors write artifacts.json.  See publish.gd.
#

# Guess the format from the first bytes of the file rather than from the URL.
#
# This matters more than it sounds: the download URLs of the archives people
# actually publish often carry no file name at all.  Zenodo's, for instance,
# ends in '/content', so guessing from the URL yields "file" and the author
# would paste a stanza that stores a tarball without ever unpacking it.
#
# Returns a format name, or 'fail' if we cannot tell.
BindGlobal( "AM_SniffFormat",
function( path )
  local f, head;

  if not AM_HaveIO() then
    return fail;
  fi;
  f := ValueGlobal( "IO_File" )( path, "r" );
  if f = fail then
    return fail;
  fi;
  head := ValueGlobal( "IO_Read" )( f, 512 );
  ValueGlobal( "IO_Close" )( f );
  if not IsString( head ) then
    return fail;
  fi;

  if Length( head ) >= 2 and head{ [ 1, 2 ] } = "\037\213" then
    # gzip.  Whether what is inside is a tar cannot be told without
    # decompressing, so say only that much and let the caller decide.
    return "gzip";
  elif Length( head ) >= 2 and head{ [ 1, 2 ] } = "PK" then
    return "zip";
  elif Length( head ) >= 3 and head{ [ 1 .. 3 ] } = "BZh" then
    return "tar.bz2";
  elif Length( head ) >= 5 and head{ [ 1 .. 5 ] } = "\3757zXZ" then
    return "tar.xz";
  elif Length( head ) >= 262 and head{ [ 258 .. 262 ] } = "ustar" then
    # the 'ustar' magic lives at offset 257 of the first header block
    return "tar";
  fi;
  return fail;
end );

InstallGlobalFunction( DescribeArtifactURL,
function( url )
  local tmp, blob, res, digest, size, format, sniffed;

  if not IsString( url ) then
    ErrorNoReturn( "<url> must be a string" );
  fi;

  tmp := DirectoryTemporary();
  if tmp = fail then
    Info( InfoArtifactManager, 1, "cannot create a temporary directory" );
    return fail;
  fi;
  blob := Filename( tmp, AM_BlobName );

  Info( InfoArtifactManager, 1, "downloading ", url );
  res := AM_Download( url, blob, rec( size := fail,
                                      maxTime := AM_DownloadTimeout() ) );
  if not res.success then
    Info( InfoArtifactManager, 1, "download failed: ", res.error );
    return fail;
  fi;

  digest := AM_HexSHA256File( blob );
  size := AM_FileSize( blob );
  format := AM_GuessFormat( url );
  sniffed := AM_SniffFormat( blob );
  RemoveFile( blob );

  if digest = fail then
    Info( InfoArtifactManager, 1, "could not compute the checksum" );
    return fail;
  fi;

  # Trust the bytes over the URL, except that gzip alone does not say whether
  # what is inside is a tar; there the URL, if it looks like one, knows better.
  if sniffed = "gzip" then
    if not format in [ "tar.gz", "file.gz" ] then
      format := "file.gz";
    fi;
  elif sniffed <> fail and sniffed <> format then
    Info( InfoArtifactManager, 2, "the URL suggests format '", format,
          "', but the contents are '", sniffed, "'; using the latter" );
    format := sniffed;
  fi;

  Print( "{ \"url\": \"", url, "\",\n" );
  Print( "  \"sha256\": \"", digest, "\",\n" );
  if size <> fail then
    Print( "  \"size\": ", size, ",\n" );
  fi;
  Print( "  \"format\": \"", format, "\" }\n" );
  if size <> fail then
    Print( "\n# that is ", AM_HumanSize( size ), "\n" );
  fi;

  return rec( url := url, sha256 := digest, size := size, format := format );
end );
