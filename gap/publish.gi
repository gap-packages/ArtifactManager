#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# publish.gi: helping package authors write artifacts.json.  See publish.gd.
#

# Everything DescribeArtifactURL needs to say, without saying it.
BindGlobal( "AM_DescribeURL",
function( url, format, name )
  local tmp, blob, res, digest, size, payload, inner, ok;

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
function( url, name, format )
  local res;

  if not ( IsString( url ) and IsString( name ) ) then
    ErrorNoReturn( "<url> and <name> must be strings" );
  elif not ( IsString( format ) and format in AM_Formats ) then
    ErrorNoReturn( "<format> must be one of ",
                   JoinStringsWithSeparator( AM_Formats, ", " ),
                   ".  Say what should happen to the download; it is not ",
                   "guessed." );
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
