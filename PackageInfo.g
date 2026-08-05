#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# This file contains package meta data. For additional information on
# the meaning and correct usage of these fields, please consult the
# manual of the "Example" package as well as the comments in its
# PackageInfo.g file.
#
SetPackageInfo( rec(

PackageName := "ArtifactManager",
Subtitle := "Download, verify, and manage external data artifacts for GAP packages",
Version := "0.1",
Date := "05/08/2026", # dd/mm/yyyy format
License := "GPL-2.0-or-later",

Persons := [
  rec(
    FirstNames := "Max",
    LastName := "Horn",
    WWWHome := "https://www.quendi.de/math",
    Email := "mhorn@rptu.de",
    IsAuthor := true,
    IsMaintainer := true,
    PostalAddress := Concatenation(
               "Fachbereich Mathematik\n",
               "RPTU Kaiserslautern-Landau\n",
               "Gottlieb-Daimler-Straße 48\n",
               "67663 Kaiserslautern\n",
               "Germany" ),
    Place := "Kaiserslautern, Germany",
    Institution := "RPTU Kaiserslautern-Landau",
  ),
],

SourceRepository := rec(
    Type := "git",
    URL := "https://github.com/gap-packages/ArtifactManager",
),
IssueTrackerURL := Concatenation( ~.SourceRepository.URL, "/issues" ),
PackageWWWHome  := "https://gap-packages.github.io/ArtifactManager/",
PackageInfoURL  := Concatenation( ~.PackageWWWHome, "PackageInfo.g" ),
README_URL      := Concatenation( ~.PackageWWWHome, "README.md" ),
ArchiveURL      := Concatenation( ~.SourceRepository.URL,
                                 "/releases/download/v", ~.Version,
                                 "/", ~.PackageName, "-", ~.Version ),

ArchiveFormats := ".tar.gz",

AbstractHTML   :=  "",

PackageDoc := rec(
  BookName  := "ArtifactManager",
  ArchiveURLSubset := ["doc"],
  HTMLStart := "doc/chap0_mj.html",
  PDFFile   := "doc/manual.pdf",
  SixFile   := "doc/manual.six",
  LongTitle := "Download, verify, and manage external data artifacts for GAP packages",
),

Dependencies := rec(
  GAP := ">= 4.13",
  NeededOtherPackages := [ ],
  SuggestedOtherPackages := [ ],
  ExternalConditions := [ ],
),

AvailabilityTest := ReturnTrue,

TestFile := "tst/testall.g",

));
