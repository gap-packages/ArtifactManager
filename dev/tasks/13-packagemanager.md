---
id: 13
title: Contribute the archive-safety and quoting fixes to PackageManager
status: open
needs: 
touches: 
---

# Contribute the archive-safety and quoting fixes to PackageManager

Three findings from the survey that produced this package, none filed:

- **U16** `PKGMAN_Exec` joins arguments with spaces and runs them through
  `sh -c`. Any path with a space breaks; any path with a shell metacharacter
  injects. This is why we cannot reuse `PKGMAN_ExtractArchive`.
- **U17** downloaded package archives are not checksummed at all. `grep -i
  'sha\|checksum\|md5'` over `gap/` and `doc/` returns nothing.
- **U18** `PKGMAN_TarTopDirectory` requires exactly one top-level directory
  but does not reject absolute paths or `..` members. It is the ecosystem's
  only tarbomb guard. The stricter check in `AM_CheckArchiveMembers` is worth
  contributing back.

U16 is a security fix and should not wait on the others.
