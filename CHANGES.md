This file describes changes in the ArtifactManager package.

## Unreleased

- Let packages declare data artifacts in `artifacts.json`; download them on
  first use, verify their SHA256 checksums and cache them under
  `~/.gap/artifacts`. Add `ArtifactDirectory`, `ArtifactFile`,
  `FetchArtifact`, `IsArtifactAvailable`, `ShowArtifacts`, `VerifyArtifact`,
  `RemoveArtifact`, `PinArtifact`, `OverrideArtifact` and related functions
- Identify an artifact by `tree_sha256` (a directory, hashed like a git tree
  object with SHA256) or `file_sha256` (a single file); support the formats
  `raw`, `gz`, `tar` and `tar.gz`, never guessed from the URL; reject unknown
  manifest fields (#3, #4, #6)
- Add `ValidateArtifacts` to check every source against the manifest, and
  `DescribeArtifactURL` with a required format argument
- Let `FetchArtifact` take a destination; refuse archives containing anything
  but files and directories
- Report why an artifact cannot be used instead of claiming it was never
  declared
- Use the same store inside Oscar as outside it
- Require GAP >= 4.16 and the utils package; IO is recommended

## 0.1 (2026-08-05)

- Initial package skeleton, without functionality
