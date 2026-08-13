#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# fetch.gi: downloading, verifying, unpacking, installing.  See fetch.gd.
#

BindGlobal( "AM_MetaFormat", 1 );

# Above this size we avoid download backends that keep the whole file in
# memory.  See AM_Download.
BindGlobal( "AM_LargeDownload", 64 * 1024 * 1024 );

# Downloads always land here inside the staging directory.  The name has no
# extension on purpose: 'StringFile' and 'InputTextFile' gunzip anything whose
# name ends in '.gz', which would silently change the bytes we are about to
# checksum.  TODO(U6).
BindGlobal( "AM_BlobName", "blob" );

# An artifact is identified by what it *is*, not by which mirror produced it,
# so the key is the declared tree or file checksum.  Mirrors serving
# byte-different archives of the same data therefore share one directory.
BindGlobal( "AM_ArtifactKey",
function( decl )
  return rec( package := decl.package,
              name := decl.name,
              sha256 := decl.sha256 );
end );


#############################################################################
##
#F  AM_Installed( <decl> )
##
InstallGlobalFunction( AM_Installed,
function( decl )
  local store, key, payload, meta, data;

  key := AM_ArtifactKey( decl );
  for store in AM_Stores( decl.package ) do
    payload := AM_PayloadPath( store.path, key );
    meta := AM_MetaPath( store.path, key );
    # The metadata file is written last, so its presence is what makes an
    # artifact count as installed.  A payload without metadata is the
    # remains of an interrupted install and is ignored.
    if IsDirectoryPath( payload ) and IsExistingFile( meta ) then
      data := AM_ReadRecordFile( meta );
      if IsRecord( data ) then
        return rec( store := store.path, key := key, path := payload,
                    meta := data, writable := store.writable );
      fi;
    fi;
  od;

  return fail;
end );


#####
##
#F  AM_Download( <url>, <target>, <opt> )
##
BindGlobal( "AM_DownloadFileURL",
function( url, target )
  local path;

  path := url{ [ 8 .. Length( url ) ] };
  # file://localhost/... and file:///... both mean the local filesystem
  if StartsWith( path, "localhost/" ) then
    path := path{ [ 10 .. Length( path ) ] };
  fi;
  if path = "" then
    return rec( success := false, error := "empty file:// path" );
  fi;

  if not IsExistingFile( path ) then
    return rec( success := false,
                error := Concatenation( "no such file: ", path ) );
  fi;
  if AM_CopyFile( path, target ) then
    return rec( success := true );
  fi;
  return rec( success := false,
              error := Concatenation( "could not copy ", path ) );
end );

# Suitability of a download backend; lower is tried first.  'Download_Methods'
# is ordered worst-first for our purposes.
#
# TODO(U13): matching on names is a hack; utils should let backends advertise
# what they can do.
BindGlobal( "AM_BackendRank",
function( name, size )
  if name in [ "via curl", "via wget" ] then
    # stream to a file, follow redirects, speak https
    return 1;
  elif name = "via DownloadURL (from the curlInterface package)" then
    # correct, but buffers the whole file in memory
    if size = fail or size > AM_LargeDownload then
      return 3;
    fi;
    return 2;
  elif name = "via SingleHTTPRequest (from the IO package)" then
    # http only, no redirects
    return 4;
  fi;
  # Something a user added themselves; assume it is sensible.
  return 2;
end );

InstallGlobalFunction( AM_Download,
function( url, target, opt )
  local methods, ranked, rank, errors, m, res, size;

  if StartsWith( LowercaseString( url ), "file://" ) then
    return AM_DownloadFileURL( url, target );
  fi;

  if not IsBoundGlobal( "Download_Methods" ) then
    return rec( success := false,
                error := "the utils package does not provide 'Download'" );
  fi;

  size := opt.size;
  methods := ValueGlobal( "Download_Methods" );
  ranked := [];
  for rank in [ 1 .. 4 ] do
    Append( ranked,
            Filtered( methods, m -> AM_BackendRank( m.name, size ) = rank ) );
  od;
  methods := ranked;

  errors := [];
  for m in methods do
    if m.isAvailable() then
      Info( InfoArtifactManager, 3, "trying download backend ", m.name );
      # 'Download' and its backends modify the option record they are given,
      # so never reuse one.  TODO(U10, utils#102).
      res := m.download( url, rec( target := target,
                                   maxTime := opt.maxTime ) );
      if res.success = true then
        return rec( success := true );
      fi;
      Info( InfoArtifactManager, 3, "backend ", m.name, " failed: ",
            res.error );
      Add( errors, Concatenation( m.name, ": ", res.error ) );
      # wget removes a partial target on failure, curl does not.
      # TODO(U11, utils#103).
      if IsExistingFile( target ) then
        RemoveFile( target );
      fi;
    fi;
  od;

  if IsEmpty( errors ) then
    return rec( success := false,
        error := Concatenation( "no download method is available.  Install ",
            "'curl' or 'wget', or load the curlInterface package." ) );
  fi;
  return rec( success := false,
              error := JoinStringsWithSeparator( errors, "; " ) );
end );


#############################################################################
##
##  Archives.
##
InstallGlobalFunction( AM_ArchiveMembers,
function( blob, format )
  local res;

  if format = "zip" and AM_Program( "unzip" ) <> fail then
    res := AM_Exec( fail, "unzip", [ "-Z", "-1", blob ] );
  elif AM_Program( "tar" ) <> fail then
    res := AM_Exec( fail, "tar", [ "-tf", blob ] );
  else
    return fail;
  fi;

  if res.code <> 0 then
    Info( InfoArtifactManager, 1, "cannot list the archive: ", res.output );
    return fail;
  fi;
  return Filtered( SplitString( res.output, "\n" ), s -> s <> "" );
end );

InstallGlobalFunction( AM_CheckArchiveMembers,
function( members )
  local name, part;

  for name in members do
    if StartsWith( name, "/" ) then
      return Concatenation( "the archive contains an absolute path: ", name );
    fi;
    for part in SplitString( name, "/" ) do
      if part = ".." then
        return Concatenation( "the archive escapes its directory: ", name );
      fi;
    od;
  od;
  return true;
end );

# Decompressors, by format.  Each writes to stdout, so the shell does the
# redirection: a gigabyte must not pass through a GAP string.
BindGlobal( "AM_Decompressors",
  rec( gz := [ "gzip", "gunzip" ], bz2 := [ "bzip2", "bunzip2" ],
       xz := [ "xz", "unxz" ] ) );

# Turn <blob> into <payload>, a directory, as <format> says.  A file artifact
# gets a directory holding one file named <name>, so that both kinds have the
# same shape in the store and the name keeps whatever suffix the author gave
# it -- which is what makes GAP's transparent '.gz' reading work.
# Returns 'true', or a message.
BindGlobal( "AM_Extract",
function( blob, payload, format, name )
  local members, check, res, target, prog;

  if CreateDirectoryRecursively( payload ) = fail then
    return "could not create the unpacking directory";
  fi;
  target := Concatenation( payload, "/", name );

  if format = "raw" then
    if AM_Rename( blob, target ) then
      return true;
    fi;
    return "could not move the downloaded file into place";

  elif format in AM_DecompressFormats then
    prog := First( AM_Decompressors.( format ),
                   x -> AM_Program( x ) <> fail );
    if prog = fail then
      return Concatenation( "cannot decompress '", format, "'" );
    fi;
    res := AM_Exec( fail, "sh",
               [ "-c", Concatenation( prog, " -dc \"$0\" > \"$1\"" ),
                 blob, target ] );
    if res.code <> 0 then
      return Concatenation( "decompressing failed: ", res.output );
    fi;
    RemoveFile( blob );
    return true;
  fi;

  # Look inside before unpacking.  We always unpack into a private directory,
  # so this is belt and braces -- but it costs a few lines and catches
  # archives that try to write outside it.
  members := AM_ArchiveMembers( blob, format );
  if members = fail then
    return "could not inspect the archive; is 'tar' installed?";
  fi;
  check := AM_CheckArchiveMembers( members );
  if IsString( check ) then
    return check;
  fi;

  if format = "zip" then
    if AM_Program( "unzip" ) <> fail then
      res := AM_Exec( fail, "unzip", [ "-q", "-o", blob, "-d", payload ] );
    else
      # bsdtar handles zip; GNU tar does not.
      res := AM_Exec( fail, "tar", [ "-xf", blob, "-C", payload ] );
    fi;
  else
    res := AM_Exec( fail, "tar",
                    [ "-xf", blob, "-C", payload, "--no-same-owner" ] );
    if res.code <> 0 then
      # --no-same-owner is not universal
      res := AM_Exec( fail, "tar", [ "-xf", blob, "-C", payload ] );
    fi;
  fi;

  if res.code <> 0 then
    return Concatenation( "unpacking failed: ", res.output );
  fi;
  return true;
end );

# What <format> needs and cannot find, or 'fail' if all is well.  Checked
# before downloading: finding out that 'tar' is missing after pulling a
# gigabyte across the network is not an acceptable way to learn it.
BindGlobal( "AM_MissingTool",
function( format )
  local progs;

  if format = "raw" then
    return fail;
  elif format in AM_DecompressFormats then
    progs := AM_Decompressors.( format );
    if ForAny( progs, x -> AM_Program( x ) <> fail ) then
      return fail;
    fi;
    return JoinStringsWithSeparator(
               List( progs, x -> Concatenation( "'", x, "'" ) ), " or " );
  elif format = "zip" and AM_Program( "unzip" ) <> fail then
    return fail;
  elif AM_Program( "tar" ) <> fail then
    return fail;
  elif format = "zip" then
    return "'unzip' or 'tar'";
  fi;
  return "'tar'";
end );

BindGlobal( "AM_DownloadTimeout",
function()
  local t;
  t := UserPreference( "utils", "DownloadMaxTime" );
  if IsInt( t ) then
    return t;
  fi;
  return 0;
end );


#############################################################################
##
#F  AM_ObtainInto( <decl>, <staging> )
##
##  Try each declared source in turn: download into <staging>/blob, verify it,
##  unpack it into <staging>/payload.  Returns
##    rec( success := true, entry := ..., key := ..., payload := ... )
##  or rec( success := false, error := <string> ).
##
BindGlobal( "AM_ObtainInto",
function( decl, staging )
  local blob, errors, entry, key, res, digest, target, extracted, irregular,
        missing;

  blob := Concatenation( staging, "/", AM_BlobName );
  errors := [];
  key := AM_ArtifactKey( decl );
  for entry in decl.download do
    missing := AM_MissingTool( entry.format );
    if missing <> fail then
      Add( errors, Concatenation( entry.url, ": unpacking a '", entry.format,
               "' archive needs ", missing, ", which is not installed" ) );
      continue;
    fi;

    Info( InfoArtifactManager, 1, "downloading ", decl.package, "/",
          decl.name, " (", AM_HumanSize( entry.size ), ") from ", entry.url );

    if IsExistingFile( blob ) then
      RemoveFile( blob );
    fi;
    res := AM_Download( entry.url, blob,
                        rec( size := entry.size,
                             maxTime := AM_DownloadTimeout() ) );
    if not res.success then
      Add( errors, Concatenation( entry.url, ": ", res.error ) );
      continue;
    fi;

    # (5) verify before anything unpacks these bytes.
    Info( InfoArtifactManager, 2, "verifying checksum" );
    digest := AM_HexSHA256File( blob );
    if digest = fail then
      Add( errors, Concatenation( entry.url,
               ": could not compute a checksum of the downloaded file" ) );
      continue;
    fi;
    if digest <> entry.sha256 then
      Info( InfoArtifactManager, 1, "checksum mismatch for ", entry.url,
            "\n#I  expected ", entry.sha256, "\n#I  got      ", digest );
      Add( errors, Concatenation( entry.url, ": checksum mismatch" ) );
      RemoveFile( blob );
      # A corrupt mirror is exactly what the other mirrors are for.
      continue;
    fi;

    # (6) unpack into the staging area.
    Info( InfoArtifactManager, 2, "unpacking (", entry.format, ")" );
    target := Concatenation( staging, "/payload" );
    extracted := AM_Extract( blob, target, entry.format, decl.name );
    if IsString( extracted ) then
      Add( errors, Concatenation( entry.url, ": ", extracted ) );
      continue;
    fi;

    irregular := AM_IrregularFiles( target );
    if irregular = fail then
      Info( InfoArtifactManager, 1, "cannot check the unpacked files for ",
            "symbolic links; load the IO package or install 'find'" );
    elif not IsEmpty( irregular ) then
      Add( errors, Concatenation( entry.url, ": the archive contains ",
               String( Length( irregular ) ), " entries that are neither ",
               "regular files nor directories, the first being '",
               irregular[1], "'" ) );
      continue;
    fi;

    # (7) the artifact's own checksum -- of the tree, or of the one file --
    # which is what identifies it and where it goes in the store.
    Info( InfoArtifactManager, 2, "verifying the artifact checksum" );
    if decl.isDirectory then
      digest := AM_TreeSHA256( target );
    else
      digest := AM_HexSHA256File( Concatenation( target, "/", decl.name ) );
    fi;
    if digest = fail then
      Add( errors, Concatenation( entry.url,
               ": could not compute the checksum of the unpacked data" ) );
      continue;
    elif digest <> decl.sha256 then
      Info( InfoArtifactManager, 1, "checksum mismatch for ", entry.url,
            "\n#I  expected ", decl.sha256, "\n#I  got      ", digest );
      Add( errors, Concatenation( entry.url,
               ": the unpacked data has the wrong checksum" ) );
      continue;
    fi;

    return rec( success := true, entry := entry, key := key,
                payload := target );
  od;

  return rec( success := false, error := Concatenation(
      "could not obtain ", decl.package, "/", decl.name, ": ",
      JoinStringsWithSeparator( errors, "; " ) ) );
end );


BindGlobal( "AM_OfflineMode",
function()
  return AM_Environment( "ARTIFACTMANAGER_OFFLINE" ) <> fail or
         UserPreference( "ArtifactManager", "AllowDownloads" ) = false;
end );

#############################################################################
##
#F  AM_FetchTo( <decl>, <dest> )
##
InstallGlobalFunction( AM_FetchTo,
function( decl, dest )
  local parent, staging, res, ok, n;

  if IsDirectoryPath( dest ) and
     not IsEmpty( Difference( DirectoryContents( dest ), [ ".", ".." ] ) ) then
    return rec( success := false, error := Concatenation(
        "'", dest, "' already exists and is not empty" ) );
  fi;
  if AM_OfflineMode() then
    return rec( success := false,
        error := "downloads are switched off; see ArtifactManager/AllowDownloads" );
  fi;

  # Stage beside the destination, not in the store: this path must not touch
  # the store, and a sibling directory keeps the final move on one filesystem.
  parent := AM_DirName( dest );
  if CreateDirectoryRecursively( parent ) = fail then
    return rec( success := false, error := Concatenation(
        "could not create '", parent, "'" ) );
  fi;
  # Not AM_StagingDirectory: that lives inside a store, and AM_RemoveTree
  # refuses to delete anything outside one.  This directory is ours.
  n := 0;
  repeat
    n := n + 1;
    staging := Concatenation( parent, "/.am-fetch-", String( n ) );
  until not IsExistingFile( staging );
  if CreateDirectoryRecursively( staging ) = fail then
    return rec( success := false, error := Concatenation(
        "could not create a staging directory in '", parent, "'" ) );
  fi;

  res := AM_ObtainInto( decl, staging );
  if not res.success then
    RemoveDirectoryRecursively( staging );
    return res;
  fi;

  if IsDirectoryPath( dest ) then
    RemoveDir( dest );
  fi;
  ok := AM_Rename( res.payload, dest );
  RemoveDirectoryRecursively( staging );
  if not ok then
    return rec( success := false, error := Concatenation(
        "could not move the unpacked data to '", dest, "'" ) );
  fi;
  Info( InfoArtifactManager, 2, "unpacked ", decl.package, "/", decl.name,
        " at ", dest );
  return rec( success := true, path := dest );
end );


InstallGlobalFunction( AM_Install,
function( decl, explicit )
  local limit, affordable, store, staging, target, res, usage, meta,
        done, cleanup;

  # (1) already there?
  res := AM_Installed( decl );
  if res <> fail then
    AM_TouchUsed( res.store, res.key );
    return rec( success := true, path := res.path );
  fi;

  # (2) may we download at all, and is it small enough to do silently?
  if AM_OfflineMode() then
    return rec( success := false, error := Concatenation(
        "the artifact ", decl.package, "/", decl.name, " is not available ",
        "locally, and downloads are switched off.  Set the user preference ",
        "ArtifactManager/AllowDownloads to 'true' to allow them." ) );
  fi;

  # Sizes are per source, so a small mirror is usable even when a large one
  # is not: the same data as a 300 MB .tar.xz and a 1 GB .tar should be
  # fetchable on a tether.
  limit := UserPreference( "ArtifactManager", "MaxAutoDownloadSize" );
  if not explicit and IsInt( limit ) and limit > 0 then
    affordable := Filtered( decl.download,
                            e -> e.size = fail or e.size <= limit );
    if IsEmpty( affordable ) then
      return rec( success := false, error := Concatenation(
          "every source for ", decl.package, "/", decl.name, " is at least ",
          AM_HumanSize( Minimum( List( decl.download, e -> e.size ) ) ),
          ", which is more than the ", AM_HumanSize( limit ),
          " that may be downloaded automatically.  Run  FetchArtifact(\"",
          decl.package, "\", \"", decl.name, "\");  to download it, or ",
          "raise the user preference ",
          "ArtifactManager/MaxAutoDownloadSize." ) );
    fi;
    decl := ShallowCopy( decl );
    decl.download := affordable;
  fi;

  # (3) somewhere to work.  The staging directory lives inside the store, so
  # that the final move is a rename within one filesystem, and thus atomic.
  store := AM_WritableStore( decl.package );
  if store = fail or store = "" then
    return rec( success := false,
        error := "no usable artifact store; see ArtifactStoreDiagnostics()" );
  fi;
  staging := AM_StagingDirectory( store );
  if staging = fail then
    return rec( success := false, error := Concatenation(
        "could not create a staging directory in '", store, "'" ) );
  fi;
  cleanup := function()
    if IsExistingFile( staging ) then
      AM_RemoveTree( staging );
    fi;
  end;

  # (4) try each declared source in turn.
  res := AM_ObtainInto( decl, staging );
  if not res.success then
    cleanup();
    return rec( success := false, error := res.error );
  fi;
  done := res;


  # (7) measure while we still can write to it.
  usage := AM_DirectorySize( done.payload );
  if usage = fail then
    usage := rec( bytes := fail, files := fail );
  fi;

  # (8) install.  The destination name contains the checksum, so if another
  # process got there first its copy is byte for byte the same as ours and we
  # can simply use it.
  target := AM_PayloadPath( store, done.key );
  if CreateDirectoryRecursively( AM_DirName( target ) ) = fail then
    cleanup();
    return rec( success := false, error := Concatenation(
        "could not create '", AM_DirName( target ), "'" ) );
  fi;

  if IsDirectoryPath( target ) then
    Info( InfoArtifactManager, 2,
          "another process installed this artifact first; using its copy" );
  elif not AM_Rename( done.payload, target ) then
    if not IsDirectoryPath( target ) then
      cleanup();
      return rec( success := false, error := Concatenation(
          "could not move the unpacked data to '", target, "'" ) );
    fi;
  fi;

  # (9) the metadata write is the commit point: until it is there, the
  # payload above counts as an interrupted install.
  meta := rec( metaFormat := AM_MetaFormat,
               package := decl.package,
               name := decl.name,
               description := decl.description,
               license := decl.license,
               provenance := decl.provenance,
               sha256 := decl.sha256,
               isDirectory := decl.isDirectory,
               format := done.entry.format,
               url := done.entry.url,
               installedAt := AM_TimeString(),
               bytes := usage.bytes,
               files := usage.files );
  if not AM_WriteRecordFile( AM_MetaPath( store, done.key ), meta ) then
    cleanup();
    return rec( success := false,
                error := "could not write the artifact metadata" );
  fi;

  AM_TouchUsed( store, done.key );

  if UserPreference( "ArtifactManager", "MakeReadOnly" ) = true then
    AM_SetTreeReadOnly( target );
  fi;

  cleanup();

  Info( InfoArtifactManager, 2, "installed ", decl.package, "/", decl.name,
        " (", AM_HumanSize( usage.bytes ), ") at ", target );

  return rec( success := true, path := target );
end );


#############################################################################
##
#F  FetchArtifact( <pkg>, <name> )
##
BindGlobal( "AM_DeclarationOrError",
function( pkg, name )
  local decl;
  decl := ArtifactDeclaration( pkg, name );
  if decl = fail then
    ErrorNoReturn( "the package '", pkg, "' declares no artifact '", name,
                   "'.  Is the package installed, and does it have an ",
                   "artifacts.json?" );
  fi;
  return decl;
end );

InstallGlobalFunction( FetchArtifact,
function( args... )
  local pkg, name, dest, decl, override, res;

  if not Length( args ) in [ 2, 3 ] then
    ErrorNoReturn( "usage: FetchArtifact( <pkg>, <name>[, <destination>] )" );
  fi;
  pkg := args[1];
  name := args[2];
  decl := AM_DeclarationOrError( pkg, name );

  if Length( args ) = 3 then
    dest := args[3];
    if not IsString( dest ) then
      ErrorNoReturn( "<destination> must be a string" );
    fi;
    res := AM_FetchTo( decl, UserHomeExpand( dest ) );
    if res.success then
      return true;
    fi;
    Info( InfoArtifactManager, 1, res.error );
    return false;
  fi;

  override := AM_OverrideFor( pkg, name );
  if override <> fail then
    Info( InfoArtifactManager, 1, "not fetching ", pkg, "/", name,
          ": it is overridden to point at '", override, "'" );
    return true;
  fi;

  res := AM_Install( decl, true );
  if res.success then
    return true;
  fi;
  Info( InfoArtifactManager, 1, res.error );
  return false;
end );


#############################################################################
##
#F  ArtifactContents( <pkg>, <name> )
##
InstallGlobalFunction( ArtifactContents,
function( pkg, name )
  local decl, installed, entry, tmp, blob, res, digest, path, data, errors;

  decl := AM_DeclarationOrError( pkg, name );

  if decl.isDirectory then
    ErrorNoReturn( "the artifact '", pkg, "/", name, "' is a directory; use ",
                   "ArtifactDirectory instead of ArtifactContents" );
  fi;

  # Prefer a copy we already have.
  installed := AM_Installed( decl );
  if installed <> fail then
    AM_TouchUsed( installed.store, installed.key );
    return StringFile( Concatenation( installed.path, "/", decl.name ) );
  fi;

  if AM_OfflineMode() then
    Info( InfoArtifactManager, 1, "the artifact ", pkg, "/", name,
          " is not available locally, and downloads are switched off" );
    return fail;
  fi;

  tmp := DirectoryTemporary();
  if tmp = fail then
    return fail;
  fi;
  blob := Filename( tmp, AM_BlobName );

  errors := [];
  for entry in decl.download do
    Info( InfoArtifactManager, 1, "downloading ", pkg, "/", name, " from ",
          entry.url, " (not storing it)" );
    if IsExistingFile( blob ) then
      RemoveFile( blob );
    fi;
    res := AM_Download( entry.url, blob,
                        rec( size := entry.size,
                             maxTime := AM_DownloadTimeout() ) );
    if not res.success then
      Add( errors, Concatenation( entry.url, ": ", res.error ) );
      continue;
    fi;
    digest := AM_HexSHA256File( blob );
    if digest <> entry.sha256 then
      Info( InfoArtifactManager, 1, "checksum mismatch for ", entry.url );
      Add( errors, Concatenation( entry.url, ": checksum mismatch" ) );
      continue;
    fi;

    path := blob;
    if entry.format = "file.gz" then
      # Let StringFile do the decompressing, which it only does for '.gz'.
      path := Concatenation( blob, ".gz" );
      if not AM_Rename( blob, path ) then
        Add( errors, "could not rename the downloaded file" );
        continue;
      fi;
    fi;
    data := StringFile( path );
    RemoveFile( path );
    return data;
  od;

  Info( InfoArtifactManager, 1, "could not obtain ", pkg, "/", name, ": ",
        JoinStringsWithSeparator( errors, "; " ) );
  return fail;
end );
