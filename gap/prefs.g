#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# prefs.g: user preferences.
#
# This file is read from read.g rather than init.g, because
# 'DeclareUserPreference' evaluates a function-valued 'default' immediately,
# and ours needs 'AM_DefaultStore' to already be installed.
#

DeclareUserPreference( rec(
  name := "ArtifactStore",
  description := [
    "The directory in which downloaded artifacts are cached.  The empty \
string means that artifacts are not stored permanently: they are downloaded \
into a temporary directory which is removed when GAP exits.",
    "If this preference is not set, a default is computed: the environment \
variable ARTIFACTMANAGER_STORE if it is set; otherwise the subdirectory \
'artifacts' of \
GAPInfo.UserGapRoot; otherwise $XDG_DATA_HOME/gap/artifacts respectively \
~/.local/share/gap/artifacts; otherwise the empty string.",
    "On a machine with several users, prefer setting the environment \
variable, which needs no per-user configuration." ],
  default := AM_DefaultStore,
  check := val -> IsString( val ),
  package := "ArtifactManager" ) );

DeclareUserPreference( rec(
  name := "ExtraArtifactStores",
  description := [
    "A list of further directories that are searched for already installed \
artifacts, but never written to.  This is how a system administrator can \
provide artifacts once for all users of a machine." ],
  default := [],
  check := val -> IsList( val ) and ForAll( val, IsString ),
  package := "ArtifactManager" ) );

DeclareUserPreference( rec(
  name := "ArtifactStoreOverrides",
  description := [
    "A record mapping package names, in lowercase, to store directories, for \
data that must live somewhere specific -- for example on a larger disk.  An \
example value is rec( atlasrep := \"/scratch/atlasrep\" ).",
    "The environment variable ARTIFACTMANAGER_STORE_<PACKAGENAME>, with the \
package name in uppercase, does the same thing and takes precedence." ],
  default := rec(),
  check := IsRecord,
  package := "ArtifactManager" ) );

DeclareUserPreference( rec(
  name := "AllowDownloads",
  description := [
    "If 'true' (the default), artifacts that are not available locally are \
downloaded when they are first needed.  Set this to 'false' to work offline; \
then only artifacts that are already present can be used.",
    "The environment variable ARTIFACTMANAGER_OFFLINE, if set to a non-empty \
value, forces this to 'false'." ],
  default := true,
  values := [ true, false ],
  multi := false,
  package := "ArtifactManager" ) );

DeclareUserPreference( rec(
  name := "MaxAutoDownloadSize",
  description := [
    "Artifacts whose declared size in bytes exceeds this value are not \
downloaded automatically; an explicit call of 'FetchArtifact' is needed.  \
This exists so that an innocent-looking computation cannot start a download \
of many gigabytes without asking.  The value 0 means no limit.",
    "The default is 1000000000, that is one gigabyte." ],
  default := 1000000000,
  check := val -> IsInt( val ) and val >= 0,
  package := "ArtifactManager" ) );

DeclareUserPreference( rec(
  name := "CollectDelay",
  description := [
    "The number of days for which an artifact that is no longer referenced by \
any installed package is kept before it is removed.  This is not used yet; \
garbage collection is planned for a later version, and the last-use times it \
needs are already being recorded." ],
  default := 7,
  check := val -> IsInt( val ) and val >= 0,
  package := "ArtifactManager" ) );

DeclareUserPreference( rec(
  name := "MakeReadOnly",
  description := [
    "If 'true' (the default), installed artifacts are made read-only, so that \
they are not modified by accident.  This requires the IO package or an \
external 'chmod'." ],
  default := true,
  values := [ true, false ],
  multi := false,
  package := "ArtifactManager" ) );
