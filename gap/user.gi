#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# user.gi: what packages and users call.  See user.gd.
#

#############################################################################
##
#F  ArtifactDirectory( <pkg>, <name> )
##
BindGlobal( "AM_ArtifactPath",
function( pkg, name, explicit )
  local decl, override, res;

  override := AM_OverrideFor( pkg, name );
  if override <> fail then
    if not IsDirectoryPath( override ) then
      ErrorNoReturn( "the artifact '", pkg, "/", name, "' is overridden to ",
                     "'", override, "', but that is not a directory.  Use ",
                     "UnoverrideArtifact(\"", pkg, "\", \"", name,
                     "\"); to undo this." );
    fi;
    return override;
  fi;

  decl := AM_DeclarationOrError( pkg, name );
  res := AM_Install( decl, explicit );
  if not res.success then
    ErrorNoReturn( res.error );
  fi;
  return res.path;
end );

InstallGlobalFunction( ArtifactDirectory,
function( pkg, name )
  return Directory( AM_ArtifactPath( pkg, name, false ) );
end );

InstallGlobalFunction( ArtifactFile,
function( arg )
  local pkg, name, path, entries;

  if not Length( arg ) in [ 2, 3 ] then
    ErrorNoReturn( "usage: ArtifactFile( <pkg>, <name>[, <relpath>] )" );
  fi;
  pkg := arg[1];
  name := arg[2];
  path := AM_ArtifactPath( pkg, name, false );

  if Length( arg ) = 3 then
    return Concatenation( path, "/", arg[3] );
  fi;

  # No relative path given: a file artifact is stored under its own name.
  if IsExistingFile( Concatenation( path, "/", name ) ) and
     not IsDirectoryPath( Concatenation( path, "/", name ) ) then
    return Concatenation( path, "/", name );
  fi;
  ErrorNoReturn( "the artifact '", pkg, "/", name, "' is a directory; say ",
                 "which file inside it you want" );
end );

InstallGlobalFunction( IsArtifactAvailable,
function( pkg, name )
  local decl, override;

  override := AM_OverrideFor( pkg, name );
  if override <> fail then
    return IsDirectoryPath( override );
  fi;

  decl := ArtifactDeclaration( pkg, name );
  if decl = fail then
    return false;
  fi;
  return AM_Installed( decl ) <> fail;
end );


#############################################################################
##
##  Looking at the store.
##
# Every artifact the store knows about, whether or not anyone still declares
# it.  Returns a list of rec( store, package, name, sha256, path, meta ).
BindGlobal( "AM_ScanStores",
function()
  local res, store, metaroot, pkgdir, namedir, entry, path, meta, key;

  res := [];
  for store in AM_Stores() do
    metaroot := Concatenation( store.path, "/meta" );
    if not IsDirectoryPath( metaroot ) then
      continue;
    fi;
    for pkgdir in Difference( DirectoryContents( metaroot ), [ ".", ".." ] ) do
      if not IsDirectoryPath( Concatenation( metaroot, "/", pkgdir ) ) then
        continue;
      fi;
      for namedir in Difference( DirectoryContents(
              Concatenation( metaroot, "/", pkgdir ) ), [ ".", ".." ] ) do
        path := Concatenation( metaroot, "/", pkgdir, "/", namedir );
        if not IsDirectoryPath( path ) then
          continue;
        fi;
        for entry in Difference( DirectoryContents( path ), [ ".", ".." ] ) do
          if not EndsWith( entry, ".g" ) then
            continue;
          fi;
          meta := AM_ReadRecordFile( Concatenation( path, "/", entry ) );
          if not ( IsRecord( meta ) and IsBound( meta.sha256 )
                   and IsBound( meta.name ) ) then
            continue;
          fi;
          key := rec( package := pkgdir, name := meta.name,
                      sha256 := meta.sha256 );
          Add( res, rec( store := store.path,
                         writable := store.writable,
                         package := pkgdir,
                         name := meta.name,
                         sha256 := meta.sha256,
                         key := key,
                         path := AM_PayloadPath( store.path, key ),
                         metaPath := Concatenation( path, "/", entry ),
                         meta := meta ) );
        od;
      od;
    od;
  od;

  return res;
end );

# The cheapest source to fetch, or 'fail' if none says.
BindGlobal( "AM_SmallestSize",
function( download )
  local sizes;
  sizes := Filtered( List( download, e -> e.size ), s -> s <> fail );
  if IsEmpty( sizes ) then
    return fail;
  fi;
  return Minimum( sizes );
end );

InstallGlobalFunction( ArtifactInfo,
function( arg )
  local decls, res, seen, decl, installed, override, stored, item;

  decls := CallFuncList( AllArtifactDeclarations, arg );

  res := [];
  seen := [];

  for decl in decls do
    item := rec( package := decl.package,
                 name := decl.name,
                 description := decl.description,
                 sha256 := decl.sha256,
                 isDirectory := decl.isDirectory,
                 urls := List( decl.download, e -> e.url ),
                 downloadSize := AM_SmallestSize( decl.download ),
                 bytes := fail,
                 path := fail,
                 status := "absent" );

    override := AM_OverrideFor( decl.package, decl.name );
    if override <> fail then
      item.status := "overridden";
      item.path := override;
    else
      installed := AM_Installed( decl );
      if installed <> fail then
        item.status := "installed";
        item.path := installed.path;
        item.sha256 := installed.key.sha256;
        if IsBound( installed.meta.bytes ) then
          item.bytes := installed.meta.bytes;
        fi;
        AddSet( seen, Concatenation( installed.key.package, "/",
                    installed.key.name, "/", installed.key.sha256 ) );
      elif IsDirectoryPath( AM_PayloadPath(
               ArtifactStoreDirectory( decl.package ),
               AM_ArtifactKey( decl ) ) ) then
        # A payload with no metadata is an interrupted install.
        item.status := "incomplete";
      fi;
    fi;

    Add( res, item );
  od;

  # Anything in the store that nothing declares any more.
  for stored in AM_ScanStores() do
    if Length( arg ) = 1 and
       stored.package <> LowercaseString( arg[1] ) then
      continue;
    fi;
    if Concatenation( stored.package, "/", stored.name, "/",
                      stored.sha256 ) in seen then
      continue;
    fi;
    if ArtifactDeclaration( stored.package, stored.name ) <> fail and
       ForAny( res, r -> r.package = stored.package
                         and r.name = stored.name
                         and r.status = "installed" ) then
      continue;
    fi;
    item := rec( package := stored.package,
                 name := stored.name,
                 description := "",
                 version := "",
                 sha256 := stored.sha256,
                 urls := [],
                 downloadSize := fail,
                 bytes := fail,
                 path := stored.path,
                 status := "stale" );
    if IsBound( stored.meta.description ) then
      item.description := stored.meta.description;
    fi;
    if IsBound( stored.meta.bytes ) then
      item.bytes := stored.meta.bytes;
    fi;
    if IsBound( stored.meta.url ) then
      item.urls := [ stored.meta.url ];
    fi;
    Add( res, item );
  od;

  return res;
end );

InstallGlobalFunction( ShowArtifacts,
function( arg )
  local info, total, widths, row, rows, i, item, stale;

  info := CallFuncList( ArtifactInfo, arg );
  if IsEmpty( info ) then
    Print( "No artifacts are declared by the installed packages.\n" );
    return;
  fi;

  SortBy( info, r -> [ r.package, r.name ] );

  rows := [ [ "package", "artifact", "status", "size", "description" ] ];
  total := 0;
  stale := 0;
  for item in info do
    if item.bytes <> fail then
      total := total + item.bytes;
      if item.status = "stale" then
        stale := stale + item.bytes;
      fi;
    fi;
    if item.bytes <> fail then
      row := AM_HumanSize( item.bytes );
    elif item.downloadSize <> fail then
      row := Concatenation( "(", AM_HumanSize( item.downloadSize ), ")" );
    else
      row := "?";
    fi;
    Add( rows, [ item.package, item.name, item.status, row,
                 item.description ] );
  od;

  widths := List( [ 1 .. 5 ],
                  i -> Maximum( List( rows, r -> Length( r[i] ) ) ) );

  for i in [ 1 .. Length( rows ) ] do
    row := rows[i];
    Print( String( row[1], -widths[1] ), "  ",
           String( row[2], -widths[2] ), "  ",
           String( row[3], -widths[3] ), "  ",
           String( row[4],  widths[4] ), "  ",
           row[5], "\n" );
    if i = 1 then
      Print( ListWithIdenticalEntries(
                 Sum( widths ) + 8, '-' ), "\n" );
    fi;
  od;

  Print( "\n" );
  Print( "total on disk: ", AM_HumanSize( total ), "\n" );
  if stale > 0 then
    Print( "of which stale (no installed package wants it): ",
           AM_HumanSize( stale ), "\n" );
  fi;
end );


#############################################################################
##
#F  VerifyArtifact( <pkg>, <name>[, <level>] )
##
InstallGlobalFunction( VerifyArtifact,
function( arg )
  local pkg, name, level, decl, installed, usage;

  if Length( arg ) = 2 then
    pkg := arg[1];  name := arg[2];  level := "quick";
  elif Length( arg ) = 3 then
    pkg := arg[1];  name := arg[2];  level := arg[3];
  else
    ErrorNoReturn( "usage: VerifyArtifact( <pkg>, <name>[, <level>] )" );
  fi;
  if not level in [ "marker", "quick", "full" ] then
    ErrorNoReturn( "<level> must be \"marker\", \"quick\" or \"full\"" );
  fi;

  if AM_OverrideFor( pkg, name ) <> fail then
    Info( InfoArtifactManager, 1, "not verifying ", pkg, "/", name,
          ": it is overridden" );
    return true;
  fi;

  decl := AM_DeclarationOrError( pkg, name );
  installed := AM_Installed( decl );
  if installed = fail then
    Info( InfoArtifactManager, 1, pkg, "/", name, " is not installed" );
    return false;
  fi;

  if level = "marker" then
    return true;
  fi;

  if level = "full" then
    if installed.meta.isDirectory = true then
      return AM_TreeSHA256( installed.path ) = installed.meta.sha256;
    fi;
    return AM_HexSHA256File( Concatenation( installed.path, "/",
               installed.meta.name ) ) = installed.meta.sha256;
  fi;

  if not ( IsBound( installed.meta.bytes ) and installed.meta.bytes <> fail
           and IsBound( installed.meta.files )
           and installed.meta.files <> fail ) then
    Info( InfoArtifactManager, 1, "no size was recorded for ", pkg, "/", name,
          "; cannot check it" );
    return true;
  fi;

  usage := AM_DirectorySize( installed.path );
  if usage = fail then
    Info( InfoArtifactManager, 1, "cannot measure ", installed.path );
    return false;
  fi;

  if usage.files <> installed.meta.files then
    Info( InfoArtifactManager, 1, pkg, "/", name, " has ", usage.files,
          " files, but ", installed.meta.files, " were installed" );
    return false;
  fi;
  if usage.bytes <> fail and usage.bytes <> installed.meta.bytes then
    Info( InfoArtifactManager, 1, pkg, "/", name, " is ",
          AM_HumanSize( usage.bytes ), ", but ",
          AM_HumanSize( installed.meta.bytes ), " were installed" );
    return false;
  fi;

  return true;
end );


#############################################################################
##
#F  RemoveArtifact( <pkg>, <name> )
##
BindGlobal( "AM_RemoveOne",
function( store, key, payload )
  local ok, path;

  ok := true;
  if IsExistingFile( payload ) then
    ok := AM_RemoveTree( payload );
  fi;
  for path in [ AM_MetaPath( store, key ), AM_UsedPath( store, key ) ] do
    if IsExistingFile( path ) then
      AM_AssertInStore( path );
      RemoveFile( path );
    fi;
  od;
  return ok;
end );

InstallGlobalFunction( RemoveArtifact,
function( pkg, name )
  local decl, installed, removed, stored;

  if AM_OverrideFor( pkg, name ) <> fail then
    Info( InfoArtifactManager, 1, "refusing to remove ", pkg, "/", name,
          ": it is overridden, so the data belongs to somebody else.  Use ",
          "UnoverrideArtifact first if that is really what you want." );
    return false;
  fi;

  removed := false;

  decl := ArtifactDeclaration( pkg, name );
  if decl <> fail then
    installed := AM_Installed( decl );
    while installed <> fail do
      if not installed.writable then
        Info( InfoArtifactManager, 1, "cannot remove ", installed.path,
              ": it is in a read-only store" );
        break;
      fi;
      Info( InfoArtifactManager, 2, "removing ", installed.path );
      removed := AM_RemoveOne( installed.store, installed.key,
                               installed.path ) or removed;
      installed := AM_Installed( decl );
    od;
  fi;

  # Also catch copies the current declaration no longer mentions.
  for stored in AM_ScanStores() do
    if stored.writable and stored.package = LowercaseString( pkg )
       and stored.name = name then
      Info( InfoArtifactManager, 2, "removing ", stored.path );
      removed := AM_RemoveOne( stored.store, stored.key, stored.path )
                 or removed;
    fi;
  od;

  if not removed then
    Info( InfoArtifactManager, 1, pkg, "/", name, " was not installed" );
  fi;
  return removed;
end );

InstallGlobalFunction( RemoveAllArtifacts,
function( arg )
  local stored, count, all;

  count := 0;
  all := AM_ScanStores();
  if Length( arg ) = 1 then
    all := Filtered( all, s -> s.package = LowercaseString( arg[1] ) );
  elif Length( arg ) > 1 then
    ErrorNoReturn( "usage: RemoveAllArtifacts( [<pkg>] )" );
  fi;

  for stored in all do
    if not stored.writable then
      Info( InfoArtifactManager, 2, "skipping ", stored.path,
            ": read-only store" );
      continue;
    fi;
    if AM_OverrideFor( stored.package, stored.name ) <> fail then
      continue;
    fi;
    Info( InfoArtifactManager, 2, "removing ", stored.path );
    if AM_RemoveOne( stored.store, stored.key, stored.path ) then
      count := count + 1;
    fi;
  od;

  return count;
end );


#############################################################################
##
##  Pins.
##
BindGlobal( "AM_PinKey",
function( pkg, name )
  return Concatenation( LowercaseString( pkg ), "/", name );
end );

InstallGlobalFunction( PinArtifact,
function( arg )
  local pkg, name, reason, pins;

  if Length( arg ) = 2 then
    pkg := arg[1];  name := arg[2];  reason := "";
  elif Length( arg ) = 3 then
    pkg := arg[1];  name := arg[2];  reason := arg[3];
  else
    ErrorNoReturn( "usage: PinArtifact( <pkg>, <name>[, <reason>] )" );
  fi;

  pins := AM_ReadPins();
  pins.( AM_PinKey( pkg, name ) ) :=
      rec( package := LowercaseString( pkg ), name := name,
           reason := reason,
           pinnedAt := AM_TimeString() );
  if not AM_WritePins( pins ) then
    Info( InfoArtifactManager, 1, "could not record the pin: there is no ",
          "writable artifact store" );
    return false;
  fi;
  return true;
end );

InstallGlobalFunction( UnpinArtifact,
function( pkg, name )
  local pins, key;

  pins := AM_ReadPins();
  key := AM_PinKey( pkg, name );
  if not IsBound( pins.( key ) ) then
    return false;
  fi;
  Unbind( pins.( key ) );
  return AM_WritePins( pins );
end );

InstallGlobalFunction( PinnedArtifacts,
function()
  local pins;
  pins := AM_ReadPins();
  return List( SortedList( RecNames( pins ) ), k -> pins.( k ) );
end );


#############################################################################
##
##  Overrides.
##
InstallGlobalFunction( OverrideArtifact,
function( pkg, name, path )
  local ov;

  if not IsString( path ) then
    ErrorNoReturn( "<path> must be a string" );
  fi;
  path := UserHomeExpand( path );
  if not IsDirectoryPath( path ) then
    ErrorNoReturn( "'", path, "' is not an existing directory" );
  fi;

  ov := AM_ReadOverrides();
  ov.( AM_PinKey( pkg, name ) ) := path;
  if not AM_WriteOverrides( ov ) then
    Info( InfoArtifactManager, 1, "could not record the override: there is ",
          "no writable artifact store" );
    return false;
  fi;
  return true;
end );

InstallGlobalFunction( UnoverrideArtifact,
function( pkg, name )
  local ov, key;

  ov := AM_ReadOverrides();
  key := AM_PinKey( pkg, name );
  if not IsBound( ov.( key ) ) then
    return false;
  fi;
  Unbind( ov.( key ) );
  return AM_WriteOverrides( ov );
end );
