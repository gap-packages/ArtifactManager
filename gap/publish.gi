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
# What format to use when the caller does not say: extract an archive,
# decompress a lone compressed file, otherwise take the bytes as they are.
BindGlobal( "AM_FormatFromContents",
function( sniffed, url )
  if sniffed = "gzip" then
    # gzip alone does not say whether a tar is inside; the URL, if it looks
    # like one, is the only hint there is.  This is a suggestion for a human
    # to confirm, not a run-time decision.
    if EndsWith( LowercaseString( url ), ".tar.gz" ) or
       EndsWith( LowercaseString( url ), ".tgz" ) then
      return "tar.gz";
    fi;
    return "gz";
  elif sniffed = fail then
    return "raw";
  fi;
  return sniffed;
end );

# Everything DescribeArtifactURL needs to say, without saying it.
BindGlobal( "AM_DescribeURL",
function( url, format, name )
  local tmp, blob, res, digest, size, sniffed, payload, inner, ok;

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
  if digest = fail then
    Info( InfoArtifactManager, 1, "could not compute the checksum" );
    return fail;
  fi;

  sniffed := AM_SniffFormat( blob );
  if format = fail then
    format := AM_FormatFromContents( sniffed, url );
    Info( InfoArtifactManager, 2, "treating this as '", format, "'" );
  fi;

  payload := Filename( tmp, "payload" );
  Info( InfoArtifactManager, 1, "unpacking to compute the artifact checksum" );
  ok := AM_Extract( blob, payload, format, name );
  if IsString( ok ) then
    Info( InfoArtifactManager, 1, "could not unpack: ", ok );
    return fail;
  fi;

  if format in AM_ExtractFormats then
    inner := AM_TreeSHA256( payload );
  else
    inner := AM_HexSHA256File( Concatenation( payload, "/", name ) );
  fi;
  RemoveDirectoryRecursively( payload );
  RemoveFile( blob );
  if inner = fail then
    Info( InfoArtifactManager, 1, "could not compute the artifact checksum" );
    return fail;
  fi;

  return rec( url := url, sha256 := digest, size := size, format := format,
              artifactSha256 := inner,
              isDirectory := format in AM_ExtractFormats );
end );

InstallGlobalFunction( DescribeArtifactURL,
function( url, opt... )
  local name, format, res;

  if not IsString( url ) then
    ErrorNoReturn( "<url> must be a string" );
  elif Length( opt ) > 2 or ForAny( opt, o -> not IsString( o ) ) then
    ErrorNoReturn( "usage: DescribeArtifactURL( <url>[, <name>[, ",
                   "<format>]] )" );
  fi;

  if IsEmpty( opt ) then
    name := "<name>";
  else
    name := opt[1];
  fi;
  if Length( opt ) < 2 then
    format := fail;
  elif not opt[2] in AM_Formats then
    ErrorNoReturn( "<format> must be one of ",
                   JoinStringsWithSeparator( AM_Formats, ", " ) );
  else
    format := opt[2];
  fi;

  res := AM_DescribeURL( url, format, name );
  if res = fail then
    return fail;
  fi;

  Print( "\"", name, "\": {\n" );
  Print( "  \"description\": \"...\",\n" );
  if res.isDirectory then
    Print( "  \"tree_sha256\": \"", res.artifactSha256, "\",\n" );
  else
    Print( "  \"file_sha256\": \"", res.artifactSha256, "\",\n" );
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

InstallGlobalFunction( ValidateArtifacts,
function( pkg )
  local decls, decl, entry, res, bad, problems;

  decls := AllArtifactDeclarations( pkg );
  if IsEmpty( decls ) then
    Print( "no artifacts declared by ", pkg, "\n" );
    return true;
  fi;

  problems := 0;
  for decl in decls do
    for entry in decl.download do
      Print( decl.name, "  ", entry.url, "\n" );
      res := AM_DescribeURL( entry.url, entry.format, decl.name );
      bad := [];
      if res = fail then
        Add( bad, "could not be fetched and unpacked" );
      else
        if res.sha256 <> entry.sha256 then
          Add( bad, Concatenation( "'sha256' says ", entry.sha256,
                        ", the file is ", res.sha256 ) );
        fi;
        if res.artifactSha256 <> decl.sha256 then
          Add( bad, Concatenation( "the artifact checksum says ", decl.sha256,
                        ", the data is ", res.artifactSha256 ) );
        fi;
        if res.size <> fail and entry.size <> fail
           and res.size <> entry.size then
          Add( bad, Concatenation( "'size' says ", String( entry.size ),
                        ", the file is ", String( res.size ) ) );
        fi;
      fi;
      if IsEmpty( bad ) then
        Print( "  ok\n" );
      else
        problems := problems + Length( bad );
        Print( "  ", JoinStringsWithSeparator( bad, "\n  " ), "\n" );
      fi;
    od;
  od;

  Print( "\n", problems, " problem(s)\n" );
  return problems = 0;
end );
