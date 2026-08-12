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

BindGlobal( "AM_ArtifactKey",
function( decl, entry )
  return rec( package := decl.package,
              name := decl.name,
              sha256 := entry.sha256 );
end );


#############################################################################
##
#F  AM_Installed( <decl> )
##
InstallGlobalFunction( AM_Installed,
function( decl )
  local store, entry, key, payload, meta, data;

  for store in AM_Stores( decl.package ) do
    for entry in decl.download do
      key := AM_ArtifactKey( decl, entry );
      payload := AM_PayloadPath( store.path, key );
      meta := AM_MetaPath( store.path, key );
      # The metadata file is written last, so its presence is what makes an
      # artifact count as installed.  A payload without metadata is the
      # remains of an interrupted install and is ignored.
      if IsDirectoryPath( payload ) and IsExistingFile( meta ) then
        data := AM_ReadRecordFile( meta );
        if IsRecord( data ) then
          return rec( store := store.path, key := key, path := payload,
                      meta := data, entry := entry, writable := store.writable );
        fi;
      fi;
    od;
  od;

  return fail;
end );


#############################################################################
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

BindGlobal( "AM_Extract",
function( blob, payload, format, filename )
  local members, check, res, target;

  if CreateDirectoryRecursively( payload ) = fail then
    return "could not create the unpacking directory";
  fi;

  if format = "file" then
    target := Concatenation( payload, "/", filename );
    if AM_Rename( blob, target ) then
      return true;
    fi;
    return "could not move the downloaded file into place";

  elif format = "file.gz" then
    # Keep it compressed: StringFile and InputTextFile decompress '.gz'
    # transparently, so this costs nothing and saves space.
    target := Concatenation( payload, "/", filename );
    if not EndsWith( target, ".gz" ) then
      target := Concatenation( target, ".gz" );
    fi;
    if AM_Rename( blob, target ) then
      return true;
    fi;
    return "could not move the downloaded file into place";
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

BindGlobal( "AM_StripLevels",
function( payload, levels )
  local i, entries, dirs, junk, sub, entry;

  for i in [ 1 .. levels ] do
    entries := Difference( DirectoryContents( payload ), [ ".", ".." ] );

    # macOS archives carry ._name and .DS_Store beside the real top-level
    # directory; those must not defeat the strip.  Kept, not deleted.
    dirs := Filtered( entries,
                e -> not StartsWith( e, "." ) and
                     IsDirectoryPath( Concatenation( payload, "/", e ) ) );
    junk := Filtered( entries, e -> StartsWith( e, "." ) );

    if Length( dirs ) <> 1 or
       Length( entries ) <> Length( dirs ) + Length( junk ) then
      Info( InfoArtifactManager, 1, "not stripping a leading directory: the ",
            "archive unpacked to ", Length( entries ), " entries, and they ",
            "are not one directory plus dot-files" );
      return;
    fi;
    if not IsEmpty( junk ) then
      Info( InfoArtifactManager, 3, "ignoring ", Length( junk ),
            " dot-entries while stripping the leading directory" );
    fi;

    sub := Concatenation( payload, "/", dirs[1] );
    for entry in Difference( DirectoryContents( sub ), [ ".", ".." ] ) do
      if not AM_Rename( Concatenation( sub, "/", entry ),
                        Concatenation( payload, "/", entry ) ) then
        Info( InfoArtifactManager, 1, "could not strip the leading ",
              "directory of the archive" );
        return;
      fi;
    od;
    RemoveDir( sub );
  od;
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
  local blob, errors, entry, key, res, digest, target, extracted, irregular;

  blob := Concatenation( staging, "/", AM_BlobName );
  errors := [];
  for entry in decl.download do
    key := AM_ArtifactKey( decl, entry );

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
    extracted := AM_Extract( blob, target, entry.format, entry.filename );
    if IsString( extracted ) then
      Add( errors, Concatenation( entry.url, ": ", extracted ) );
      continue;
    fi;
    if decl.strip > 0 then
      AM_StripLevels( target, decl.strip );
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

    if decl.tree_sha256 <> fail then
      Info( InfoArtifactManager, 2, "verifying tree hash" );
      digest := AM_TreeSHA256( target );
      if digest = fail then
        Add( errors, Concatenation( entry.url,
                 ": could not compute the tree hash of the unpacked data" ) );
        continue;
      elif digest <> decl.tree_sha256 then
        Info( InfoArtifactManager, 1, "tree hash mismatch for ", entry.url,
              "\n#I  expected ", decl.tree_sha256, "\n#I  got      ", digest );
        Add( errors, Concatenation( entry.url, ": tree hash mismatch" ) );
        continue;
      fi;
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
  local limit, store, staging, target, res, usage, meta, done, cleanup;

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

  limit := UserPreference( "ArtifactManager", "MaxAutoDownloadSize" );
  if not explicit and IsInt( limit ) and limit > 0 and decl.size <> fail
     and decl.size > limit then
    return rec( success := false, error := Concatenation(
        "the artifact ", decl.package, "/", decl.name, " is ",
        AM_HumanSize( decl.size ), ", which is more than the ",
        AM_HumanSize( limit ), " that may be downloaded automatically.  ",
        "Run  FetchArtifact(\"", decl.package, "\", \"", decl.name,
        "\");  to download it, or raise the user preference ",
        "ArtifactManager/MaxAutoDownloadSize." ) );
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
               version := decl.version,
               description := decl.description,
               license := decl.license,
               provenance := decl.provenance,
               sha256 := done.key.sha256,
               tree_sha256 := decl.tree_sha256,
               format := done.entry.format,
               url := done.entry.url,
               strip := decl.strip,
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

  if not ForAll( decl.download, e -> e.format in [ "file", "file.gz" ] ) then
    ErrorNoReturn( "the artifact '", pkg, "/", name, "' is an archive; use ",
                   "ArtifactDirectory instead of ArtifactContents" );
  fi;

  # Prefer a copy we already have.
  installed := AM_Installed( decl );
  if installed <> fail then
    AM_TouchUsed( installed.store, installed.key );
    path := Concatenation( installed.path, "/", installed.entry.filename );
    if installed.entry.format = "file.gz" and not EndsWith( path, ".gz" ) then
      path := Concatenation( path, ".gz" );
    fi;
    return StringFile( path );
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
