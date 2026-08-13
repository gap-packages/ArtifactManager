LoadPackage("ArtifactManager");;
d := DirectoriesPackageLibrary("ArtifactManager", "tst/data")[1];;
SetInfoLevel(InfoArtifactManager, 0);
for spec in [ ["sample.tar.gz","tar.gz"], ["sample.zip","zip"] ] do
  tmp := Filename(DirectoryTemporary(), "x");;
  ok := AM_Extract(Concatenation(Filename(d,""), spec[1]), tmp, spec[2], "n");;
  Print("== ", spec[1], " extract -> ", ok, "\n");
  walk := function(rel)
    local full, e, sub;
    full := Concatenation(tmp, rel);
    for e in SortedList(Difference(DirectoryContents(full), [".",".."])) do
      sub := Concatenation(rel, "/", e);
      if IsDirectoryPath(Concatenation(tmp, sub)) then
        Print("  d ", sub, "\n"); walk(sub);
      else
        Print("  f ", sub, " size=", AM_FileSize(Concatenation(tmp,sub)),
              " exec=", AM_IsExecutableFile(Concatenation(tmp,sub)),
              " sha=", AM_HexSHA256File(Concatenation(tmp,sub)){[1..12]}, "\n");
      fi;
    od;
  end;;
  walk("");
  Print("  tree=", AM_TreeSHA256(tmp), "\n");
od;
QUIT;
