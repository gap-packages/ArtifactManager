#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# declare.gi: how a package says which artifacts it has.  See declare.gd.
#

InstallGlobalFunction( AM_ManifestFormat, function() return 1; end );

BindGlobal( "AM_ManifestFileName", "artifacts.json" );

# What to do with what was downloaded.  A format is an instruction, never a
# description: we never look at the URL to decide.
#   "raw"                              use the file as it is
#   "gz"                               decompress it, keep one file
#   "tar", "tar.gz"                    unpack it into a directory
#
# Only gzip for now.  Every added format is another external tool to require
# on every platform, and zip in particular is where the archivers disagree:
# see #7.
BindGlobal( "AM_ExtractFormats", [ "tar", "tar.gz" ] );

BindGlobal( "AM_DecompressFormats", [ "gz" ] );

BindGlobal( "AM_Formats",
  Concatenation( [ "raw" ], AM_DecompressFormats, AM_ExtractFormats ) );

InstallGlobalFunction( AM_IsSingleFile,
  format -> not format in AM_ExtractFormats );

BindGlobal( "AM_NameChars",
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" );

# Declarations made by 'DeclareArtifacts', keyed by lowercase package name.
BindGlobal( "AM_RuntimeDeclarations", rec() );

# Manifests already read, keyed by absolute path.
BindGlobal( "AM_ManifestCache", rec() );

# Why a package's manifest, or one artifact in it, could not be used, keyed by
# lowercase package name.  Reading every package's manifest -- for a listing,
# or for garbage collection -- must not fail because one of them is unusable,
# but asking for a particular artifact must say what is wrong.
BindGlobal( "AM_ManifestProblems", rec() );
BindGlobal( "AM_ArtifactProblems", rec() );

BindGlobal( "AM_NoteProblem",
function( pkg, name, reason )
  local key;
  key := LowercaseString( pkg );
  if name = fail then
    AM_ManifestProblems.( key ) := reason;
  else
    if not IsBound( AM_ArtifactProblems.( key ) ) then
      AM_ArtifactProblems.( key ) := rec();
    fi;
    AM_ArtifactProblems.( key ).( name ) := reason;
  fi;
end );

# What stopped <pkg>/<name> from being declared, or 'fail' if nothing did.
InstallGlobalFunction( AM_DeclarationProblem,
function( pkg, name )
  local key;
  key := LowercaseString( pkg );
  if IsBound( AM_ArtifactProblems.( key ) )
     and IsBound( AM_ArtifactProblems.( key ).( name ) ) then
    return AM_ArtifactProblems.( key ).( name );
  elif IsBound( AM_ManifestProblems.( key ) ) then
    return AM_ManifestProblems.( key );
  fi;
  return fail;
end );

InstallGlobalFunction( AM_FlushDeclarations,
function()
  local key;
  for key in RecNames( AM_ManifestCache ) do
    Unbind( AM_ManifestCache.( key ) );
  od;
  for key in RecNames( AM_ManifestProblems ) do
    Unbind( AM_ManifestProblems.( key ) );
  od;
  for key in RecNames( AM_ArtifactProblems ) do
    Unbind( AM_ArtifactProblems.( key ) );
  od;
end );


#############################################################################
##
#F  AM_CheckDeclaration( <pkg>, <name>, <decl> )
##
# Reject anything we do not know rather than ignore it: a field we skip is a
# feature the author thinks is in force.  Granularity is one artifact, so a
# package adding an artifact we cannot read keeps the others usable.
BindGlobal( "AM_UnknownKeys",
function( rec_, known )
  return Difference( RecNames( rec_ ), known );
end );

BindGlobal( "AM_ComplainUnknown",
function( unknown, where )
  return Concatenation( where, "unknown field",
             ListWithIdenticalEntries( Length( unknown ) - 1, 's' ), " ",
             JoinStringsWithSeparator( List( unknown,
                 k -> Concatenation( "'", k, "'" ) ), ", " ),
             "; a newer version of ArtifactManager may be needed" );
end );

# SPDX identifiers and expressions: "GPL-2.0-or-later", "MIT OR Apache-2.0".
BindGlobal( "AM_SPDXChars",
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-+() " );

BindGlobal( "AM_KnownDownloadKeys", [ "url", "sha256", "format", "size" ] );

BindGlobal( "AM_CheckDownloadEntry",
function( entry, index )
  local res, sha, where, unknown;

  where := Concatenation( "download entry ", String( index ), ": " );

  if not IsRecord( entry ) then
    return Concatenation( where, "must be an object" );
  fi;
  unknown := AM_UnknownKeys( entry, AM_KnownDownloadKeys );
  if not IsEmpty( unknown ) then
    return AM_ComplainUnknown( unknown, where );
  fi;

  if not ( IsBound( entry.url ) and IsString( entry.url )
           and entry.url <> "" ) then
    return Concatenation( where, "'url' must be a non-empty string" );
  elif not IsBound( entry.sha256 ) then
    return Concatenation( where, "'sha256' is missing" );
  fi;

  sha := AM_NormalizeHex( entry.sha256 );
  if sha = fail then
    return Concatenation( where, "'sha256' is not a hexadecimal string" );
  fi;

  if not ( IsBound( entry.format ) and IsString( entry.format )
           and entry.format in AM_Formats ) then
    return Concatenation( where, "'format' must be one of ",
               JoinStringsWithSeparator( AM_Formats, ", " ),
               ".  It says what to do with the download, so it is never ",
               "guessed from the URL." );
  fi;

  res := rec( url := entry.url, sha256 := sha, format := entry.format );

  if IsBound( entry.size ) then
    if not ( IsInt( entry.size ) and entry.size >= 0 ) then
      return Concatenation( where, "'size' must be a non-negative integer" );
    fi;
    res.size := entry.size;
  else
    res.size := fail;
  fi;

  return res;
end );

BindGlobal( "AM_KnownArtifactKeys",
  [ "download", "tree_sha256", "file_sha256", "description", "license" ] );

InstallGlobalFunction( AM_CheckDeclaration,
function( pkg, name, decl )
  local res, i, entry, downloads, unknown, wanted;

  if not IsRecord( decl ) then
    return "the declaration must be an object";
  fi;

  # The name is also the file name of a file artifact and a component of
  # every store path, so it has to be usable as one.
  if not ( IsString( name ) and name <> ""
           and ForAll( name, c -> c in AM_NameChars ) ) then
    return Concatenation( "'", String( name ), "' is not a valid artifact ",
               "name (letters, digits, '.', '_' and '-' only)" );
  elif name[1] = '.' then
    return Concatenation( "'", name, "' is not a valid artifact name: it ",
               "must not start with '.'" );
  fi;

  unknown := AM_UnknownKeys( decl, AM_KnownArtifactKeys );
  if not IsEmpty( unknown ) then
    return AM_ComplainUnknown( unknown, "" );
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
              download := downloads );

  # What kind of artifact this is says itself: a tree hash means a directory,
  # a file hash means a file.  Exactly one, and the formats must agree.
  if IsBound( decl.tree_sha256 ) = IsBound( decl.file_sha256 ) then
    return Concatenation( "exactly one of 'tree_sha256' (a directory) and ",
               "'file_sha256' (a single file) must be given.  Run  ",
               "DescribeArtifactURL(\"", downloads[1].url,
               "\");  to compute it." );
  fi;

  res.isDirectory := IsBound( decl.tree_sha256 );
  if res.isDirectory then
    res.sha256 := AM_NormalizeHex( decl.tree_sha256 );
    wanted := "an unpacking format";
  else
    res.sha256 := AM_NormalizeHex( decl.file_sha256 );
    wanted := "'raw' or a decompressing format";
  fi;
  if res.sha256 = fail then
    return "the artifact checksum is not a hexadecimal string";
  fi;

  for entry in downloads do
    if ( entry.format in AM_ExtractFormats ) <> res.isDirectory then
      return Concatenation( "the source '", entry.url, "' has format '",
                 entry.format, "', but this artifact needs ", wanted );
    fi;
  od;

  if IsBound( decl.description ) then
    if not IsString( decl.description ) then
      return "'description' must be a string";
    fi;
    res.description := decl.description;
  else
    res.description := "";
  fi;

  if IsBound( decl.license ) then
    if not ( IsString( decl.license ) and decl.license <> ""
             and ForAll( decl.license, c -> c in AM_SPDXChars ) ) then
      return "'license' must be an SPDX identifier, e.g. 'GPL-2.0-or-later'";
    fi;
    res.license := decl.license;
  else
    res.license := "";
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
  local parsed, doc, res, key, decl, name, reject;

  reject := function( reason )
    Info( InfoArtifactManager, 1, "ignoring ", source, ": ", reason );
    AM_NoteProblem( pkg, fail, Concatenation( source, ": ", reason ) );
    return [];
  end;

  parsed := AM_JsonToGap( text );
  if not parsed.success then
    return reject( parsed.error );
  fi;
  doc := parsed.value;

  if not IsRecord( doc ) then
    return reject( "the top level must be an object" );
  fi;

  if not ( IsBound( doc.gapArtifactManifestVersion )
           and IsPosInt( doc.gapArtifactManifestVersion ) ) then
    return reject( "no 'gapArtifactManifestVersion'" );
  fi;

  # Forward compatibility: never a parse error, always a clear message.
  if doc.gapArtifactManifestVersion > AM_ManifestFormat() then
    return reject( Concatenation( "it uses manifest format ",
               String( doc.gapArtifactManifestVersion ), ", but this version ",
               "of ArtifactManager only understands up to ",
               String( AM_ManifestFormat() ),
               ".  Please upgrade ArtifactManager." ) );
  fi;

  # Mandatory, so that tooling outside GAP can read the package name here
  # instead of parsing PackageInfo.g.
  if not ( IsBound( doc.package ) and IsString( doc.package ) ) then
    return reject( "no 'package'" );
  elif LowercaseString( doc.package ) <> LowercaseString( pkg ) then
    return reject( Concatenation( "it declares package '", doc.package,
                       "' but belongs to '", pkg, "'" ) );
  fi;

  if not ( IsBound( doc.artifacts ) and IsRecord( doc.artifacts ) ) then
    return reject( "'artifacts' must be an object" );
  fi;

  key := AM_UnknownKeys( doc, AM_KnownManifestKeys );
  if not IsEmpty( key ) then
    return reject( AM_ComplainUnknown( key, "" ) );
  fi;

  res := [];
  for name in SortedList( RecNames( doc.artifacts ) ) do
    decl := AM_CheckDeclaration( pkg, name, doc.artifacts.( name ) );
    if IsString( decl ) then
      # One bad artifact must not take the whole manifest with it.
      Info( InfoArtifactManager, 1, source, ": skipping artifact '", name,
            "': ", decl );
      AM_NoteProblem( pkg, name, decl );
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
    # 'name' is how a runtime declaration says which artifact it is; in a
    # manifest that is the key, so the schema does not know the field.
    entry := ShallowCopy( entry );
    Unbind( entry.name );
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
