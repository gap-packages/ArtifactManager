#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# declare.gi: how a package says which artifacts it has.  See declare.gd.
#

InstallGlobalFunction( AM_ManifestFormat, function() return 1; end );

BindGlobal( "AM_ManifestFileName", "artifacts.json" );

BindGlobal( "AM_Formats",
  [ "tar.gz", "tar.bz2", "tar.xz", "tar", "zip", "file", "file.gz" ] );

InstallGlobalFunction( AM_IsSingleFile,
  format -> format in [ "file", "file.gz" ] );

BindGlobal( "AM_NameChars",
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" );

# Declarations made by 'DeclareArtifacts', keyed by lowercase package name.
BindGlobal( "AM_RuntimeDeclarations", rec() );

# Manifests already read, keyed by absolute path.
BindGlobal( "AM_ManifestCache", rec() );

InstallGlobalFunction( AM_FlushDeclarations,
function()
  local key;
  for key in RecNames( AM_ManifestCache ) do
    Unbind( AM_ManifestCache.( key ) );
  od;
end );


#############################################################################
##
#F  AM_CheckDeclaration( <pkg>, <name>, <decl> )
##
BindGlobal( "AM_GuessFormat",
function( url )
  local lower, suffix;
  lower := LowercaseString( url );
  for suffix in [ [ ".tar.gz", "tar.gz" ], [ ".tgz", "tar.gz" ],
                  [ ".tar.bz2", "tar.bz2" ], [ ".tbz2", "tar.bz2" ],
                  [ ".tar.xz", "tar.xz" ], [ ".txz", "tar.xz" ],
                  [ ".tar", "tar" ], [ ".zip", "zip" ],
                  [ ".gz", "file.gz" ] ] do
    if EndsWith( lower, suffix[1] ) then
      return suffix[2];
    fi;
  od;
  return "file";
end );

# The name a "file"/"file.gz" artifact gets inside its directory.
BindGlobal( "AM_BaseName",
function( url )
  local parts;
  parts := SplitString( url, "/" );
  parts := Filtered( parts, s -> s <> "" );
  if IsEmpty( parts ) then
    return "data";
  fi;
  parts := SplitString( parts[ Length( parts ) ], "?#" )[1];
  if parts = "" then
    return "data";
  fi;
  return parts;
end );

BindGlobal( "AM_CheckDownloadEntry",
function( entry, index )
  local res, sha, where;

  where := Concatenation( "download entry ", String( index ), ": " );

  if not IsRecord( entry ) then
    return Concatenation( where, "must be an object" );
  elif not ( IsBound( entry.url ) and IsString( entry.url )
             and entry.url <> "" ) then
    return Concatenation( where, "'url' must be a non-empty string" );
  elif not IsBound( entry.sha256 ) then
    return Concatenation( where, "'sha256' is missing" );
  fi;

  sha := AM_NormalizeHex( entry.sha256 );
  if sha = fail then
    return Concatenation( where, "'sha256' is not a hexadecimal string" );
  fi;

  res := rec( url := entry.url, sha256 := sha );

  if IsBound( entry.format ) then
    if not ( IsString( entry.format ) and entry.format in AM_Formats ) then
      return Concatenation( where, "'format' must be one of ",
                 JoinStringsWithSeparator( AM_Formats, ", " ) );
    fi;
    res.format := entry.format;
  else
    res.format := AM_GuessFormat( entry.url );
  fi;

  if IsBound( entry.size ) then
    if not ( IsInt( entry.size ) and entry.size >= 0 ) then
      return Concatenation( where, "'size' must be a non-negative integer" );
    fi;
    res.size := entry.size;
  else
    res.size := fail;
  fi;

  if IsBound( entry.filename ) and IsString( entry.filename ) then
    res.filename := entry.filename;
  else
    res.filename := AM_BaseName( entry.url );
  fi;

  return res;
end );

InstallGlobalFunction( AM_CheckDeclaration,
function( pkg, name, decl )
  local res, i, entry, downloads, opt;

  if not IsRecord( decl ) then
    return "the declaration must be an object";
  elif not ( IsString( name ) and name <> ""
             and ForAll( name, c -> c in AM_NameChars ) ) then
    return Concatenation( "'", String( name ), "' is not a valid artifact ",
               "name (letters, digits, '.', '_' and '-' only)" );
  fi;

  # 'kind' is reserved for later versions.  An artifact we do not understand
  # is skipped; the rest of the manifest stays usable.
  if IsBound( decl.kind ) and decl.kind <> "archive" then
    return Concatenation( "unsupported kind '", String( decl.kind ),
               "'; a newer version of ArtifactManager is needed" );
  fi;

  if not ( IsBound( decl.download ) and IsList( decl.download )
           and not IsEmpty( decl.download ) ) then
    return "'download' must be a non-empty list";
  fi;

  downloads := [];
  for i in [ 1 .. Length( decl.download ) ] do
    entry := AM_CheckDownloadEntry( decl.download[i], i );
    if IsString( entry ) then
      return entry;
    fi;
    Add( downloads, entry );
  od;

  res := rec( package := LowercaseString( pkg ),
              name := name,
              download := downloads,
              strip := 0,
              lazy := true );

  for opt in [ "description", "version", "license", "provenance" ] do
    if IsBound( decl.( opt ) ) and IsString( decl.( opt ) ) then
      res.( opt ) := decl.( opt );
    else
      res.( opt ) := "";
    fi;
  od;

  # A single file needs no tree hash: 'sha256' already covers the exact bytes
  # that end up on disk, so a tree hash would say nothing new.
  if IsBound( decl.tree_sha256 ) then
    res.tree_sha256 := AM_NormalizeHex( decl.tree_sha256 );
    if res.tree_sha256 = fail then
      return "'tree_sha256' is not a hexadecimal string";
    fi;
  elif ForAll( res.download, e -> AM_IsSingleFile( e.format ) ) then
    res.tree_sha256 := fail;
  else
    return Concatenation( "'tree_sha256' is missing.  Run  ",
               "DescribeArtifactURL(\"", res.download[1].url,
               "\");  to compute it." );
  fi;

  if IsBound( decl.strip ) then
    if not ( IsInt( decl.strip ) and decl.strip >= 0 ) then
      return "'strip' must be a non-negative integer";
    fi;
    res.strip := decl.strip;
  fi;

  if IsBound( decl.lazy ) and decl.lazy in [ true, false ] then
    res.lazy := decl.lazy;
  fi;

  if IsBound( decl.size ) then
    if not ( IsInt( decl.size ) and decl.size >= 0 ) then
      return "'size' must be a non-negative integer";
    fi;
    res.size := decl.size;
  else
    # fall back to the largest declared download size, if any
    res.size := fail;
    for entry in downloads do
      if entry.size <> fail and
         ( res.size = fail or entry.size > res.size ) then
        res.size := entry.size;
      fi;
    od;
  fi;

  return res;
end );


#############################################################################
##
#F  AM_ParseManifest( <pkg>, <text>, <source> )
##
BindGlobal( "AM_KnownManifestKeys",
  [ "gapArtifactManifestVersion", "package", "artifacts" ] );

InstallGlobalFunction( AM_ParseManifest,
function( pkg, text, source )
  local parsed, doc, res, key, decl, name;

  parsed := AM_JsonToGap( text );
  if not parsed.success then
    Info( InfoArtifactManager, 1, "ignoring ", source, ": ", parsed.error );
    return [];
  fi;
  doc := parsed.value;

  if not IsRecord( doc ) then
    Info( InfoArtifactManager, 1, "ignoring ", source,
          ": the top level must be an object" );
    return [];
  fi;

  if not ( IsBound( doc.gapArtifactManifestVersion )
           and IsPosInt( doc.gapArtifactManifestVersion ) ) then
    Info( InfoArtifactManager, 1, "ignoring ", source,
          ": no 'gapArtifactManifestVersion'" );
    return [];
  fi;

  # Forward compatibility: never a parse error, always a clear message.
  if doc.gapArtifactManifestVersion > AM_ManifestFormat() then
    Info( InfoArtifactManager, 1, "ignoring ", source, ": it uses manifest ",
          "format ", doc.gapArtifactManifestVersion, ", but this version of ",
          "ArtifactManager only understands up to ", AM_ManifestFormat(),
          ".  Please upgrade ArtifactManager." );
    return [];
  fi;

  if IsBound( doc.package ) and IsString( doc.package )
     and LowercaseString( doc.package ) <> LowercaseString( pkg ) then
    Info( InfoArtifactManager, 1, "ignoring ", source, ": it declares ",
          "package '", doc.package, "' but belongs to '", pkg, "'" );
    return [];
  fi;

  if not ( IsBound( doc.artifacts ) and IsRecord( doc.artifacts ) ) then
    Info( InfoArtifactManager, 1, "ignoring ", source,
          ": 'artifacts' must be an object" );
    return [];
  fi;

  for key in RecNames( doc ) do
    if not key in AM_KnownManifestKeys then
      Info( InfoArtifactManager, 3, source, ": ignoring unknown key '",
            key, "'" );
    fi;
  od;

  res := [];
  for name in SortedList( RecNames( doc.artifacts ) ) do
    decl := AM_CheckDeclaration( pkg, name, doc.artifacts.( name ) );
    if IsString( decl ) then
      # One bad artifact must not take the whole manifest with it.
      Info( InfoArtifactManager, 1, source, ": skipping artifact '", name,
            "': ", decl );
    else
      decl.source := source;
      Add( res, decl );
    fi;
  od;

  return res;
end );


#############################################################################
##
#F  AM_ManifestDeclarations( <pkg> )
##
BindGlobal( "AM_PackageInstallationPaths",
function( pkg )
  local res, info;

  res := [];
  pkg := LowercaseString( pkg );
  if IsBound( GAPInfo.PackagesInfo.( pkg ) ) then
    for info in GAPInfo.PackagesInfo.( pkg ) do
      if IsBound( info.InstallationPath ) then
        AddSet( res, info.InstallationPath );
      fi;
    od;
  fi;
  return res;
end );

BindGlobal( "AM_ManifestDeclarations",
function( pkg )
  local res, path, file, text;

  res := [];
  for path in AM_PackageInstallationPaths( pkg ) do
    file := Concatenation( path, "/", AM_ManifestFileName );
    if IsBound( AM_ManifestCache.( file ) ) then
      Append( res, AM_ManifestCache.( file ) );
    elif IsReadableFile( file ) then
      text := StringFile( file );
      if text = fail then
        Info( InfoArtifactManager, 1, "cannot read ", file );
        AM_ManifestCache.( file ) := [];
      else
        AM_ManifestCache.( file ) := AM_ParseManifest( pkg, text, file );
      fi;
      Append( res, AM_ManifestCache.( file ) );
    fi;
  od;

  return res;
end );


#############################################################################
##
#F  DeclareArtifacts( <pkgname>, <list> )
##
InstallGlobalFunction( DeclareArtifacts,
function( pkgname, list )
  local pkg, decl, entry, name;

  if not IsString( pkgname ) then
    ErrorNoReturn( "<pkgname> must be a string" );
  elif not IsList( list ) then
    ErrorNoReturn( "<list> must be a list of records" );
  fi;

  pkg := LowercaseString( pkgname );
  if not IsBound( AM_RuntimeDeclarations.( pkg ) ) then
    AM_RuntimeDeclarations.( pkg ) := rec();
  fi;

  for entry in list do
    if not ( IsRecord( entry ) and IsBound( entry.name ) ) then
      ErrorNoReturn( "each entry of <list> must be a record with a ",
                     "component 'name'" );
    fi;
    name := entry.name;
    decl := AM_CheckDeclaration( pkg, name, entry );
    if IsString( decl ) then
      ErrorNoReturn( "invalid declaration of artifact '", name,
                     "' for package '", pkgname, "': ", decl );
    fi;
    decl.source := "declared at run time";
    AM_RuntimeDeclarations.( pkg ).( name ) := decl;
  od;
end );


#############################################################################
##
#F  ArtifactDeclaration( <pkg>, <name> )
##
InstallGlobalFunction( ArtifactDeclaration,
function( pkg, name )
  local key, decl;

  if not ( IsString( pkg ) and IsString( name ) ) then
    ErrorNoReturn( "<pkg> and <name> must be strings" );
  fi;

  key := LowercaseString( pkg );
  if IsBound( AM_RuntimeDeclarations.( key ) )
     and IsBound( AM_RuntimeDeclarations.( key ).( name ) ) then
    return AM_RuntimeDeclarations.( key ).( name );
  fi;

  decl := First( AM_ManifestDeclarations( pkg ), d -> d.name = name );
  if decl = fail then
    return fail;
  fi;
  return decl;
end );


#############################################################################
##
#F  AllArtifactDeclarations( [<pkg>] )
##
InstallGlobalFunction( AllArtifactDeclarations,
function( arg )
  local packages, res, pkg, seen, decl, key;

  if Length( arg ) = 1 then
    packages := [ LowercaseString( arg[1] ) ];
  elif Length( arg ) = 0 then
    packages := Set( Concatenation( RecNames( GAPInfo.PackagesInfo ),
                                    RecNames( AM_RuntimeDeclarations ) ) );
  else
    ErrorNoReturn( "usage: AllArtifactDeclarations( [<pkg>] )" );
  fi;

  res := [];
  for pkg in packages do
    seen := [];
    if IsBound( AM_RuntimeDeclarations.( pkg ) ) then
      for key in SortedList( RecNames( AM_RuntimeDeclarations.( pkg ) ) ) do
        Add( res, AM_RuntimeDeclarations.( pkg ).( key ) );
        AddSet( seen, key );
      od;
    fi;
    for decl in AM_ManifestDeclarations( pkg ) do
      if not decl.name in seen then
        Add( res, decl );
      fi;
    od;
  od;

  return res;
end );
