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

# Everything DescribeArtifactURL needs to say, without saying it: the caller
# below turns this into the stanza a package author pastes.
BindGlobal( "AM_DescribeURL",
function( url, strip )
  local tmp, blob, res, digest, size, format, sniffed, payload, tree;

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

  # The tree hash is mandatory in a manifest and cannot be produced by any
  # other tool, so unpack the archive here rather than leave the author stuck.
  payload := Filename( tmp, "payload" );
  Info( InfoArtifactManager, 1, "unpacking to compute the tree hash" );
  tree := AM_Extract( blob, payload, format, AM_BaseName( url ) );
  if IsString( tree ) then
    Info( InfoArtifactManager, 1, "could not unpack: ", tree );
    return fail;
  fi;
  if strip > 0 then
    AM_StripLevels( payload, strip );
  fi;
  tree := AM_TreeSHA256( payload );
  RemoveDirectoryRecursively( payload );
  RemoveFile( blob );
  if tree = fail then
    Info( InfoArtifactManager, 1, "could not compute the tree hash" );
    return fail;
  fi;

  return rec( url := url, sha256 := digest, size := size, format := format,
              tree_sha256 := tree, strip := strip );
end );

InstallGlobalFunction( DescribeArtifactURL,
function( url, strip... )
  local res;

  if not IsString( url ) then
    ErrorNoReturn( "<url> must be a string" );
  elif Length( strip ) > 1
       or ( not IsEmpty( strip )
            and not ( IsInt( strip[1] ) and strip[1] >= 0 ) ) then
    ErrorNoReturn( "usage: DescribeArtifactURL( <url>[, <strip>] )" );
  fi;
  if IsEmpty( strip ) then
    strip := 1;
  else
    strip := strip[1];
  fi;

  res := AM_DescribeURL( url, strip );
  if res = fail then
    return fail;
  fi;

  Print( "\"<name>\": {\n" );
  Print( "  \"description\": \"...\",\n" );
  Print( "  \"tree_sha256\": \"", res.tree_sha256, "\",\n" );
  if res.strip <> 0 then
    Print( "  \"strip\": ", res.strip, ",\n" );
  fi;
  Print( "  \"download\": [\n" );
  Print( "    { \"url\": \"", res.url, "\",\n" );
  Print( "      \"sha256\": \"", res.sha256, "\",\n" );
  if res.size <> fail then
    Print( "      \"size\": ", res.size, ",\n" );
  fi;
  Print( "      \"format\": \"", res.format, "\" } ]\n" );
  Print( "}\n" );
  if res.size <> fail then
    Print( "\n# that is ", AM_HumanSize( res.size ), " to download\n" );
  fi;

  return res;
end );
