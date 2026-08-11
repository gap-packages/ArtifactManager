#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# Reading the implementation part of the package.
#
ReadPackage( "ArtifactManager", "gap/ArtifactManager.gi");
ReadPackage( "ArtifactManager", "gap/compat.gi");
ReadPackage( "ArtifactManager", "gap/hash.gi");
ReadPackage( "ArtifactManager", "gap/json.gi");
ReadPackage( "ArtifactManager", "gap/store.gi");

# The user preferences are declared only now: 'DeclareUserPreference' calls a
# 'default' function immediately, and ours needs 'AM_DefaultStore' from
# 'gap/store.gi' to already be installed.
ReadPackage( "ArtifactManager", "gap/prefs.g");

ReadPackage( "ArtifactManager", "gap/declare.gi");
ReadPackage( "ArtifactManager", "gap/fetch.gi");
ReadPackage( "ArtifactManager", "gap/user.gi");
ReadPackage( "ArtifactManager", "gap/publish.gi");
