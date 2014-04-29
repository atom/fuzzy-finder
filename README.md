# Fuzzy Finder package [![Build Status](https://travis-ci.org/atom/fuzzy-finder.svg?branch=master)](https://travis-ci.org/atom/fuzzy-finder)

Quickly find and open files using `cmd-t`.

  * `cmd-b` to open the buffer list
  * `cmd-shift-b` to open the list of Git modified and untracked files

This package uses both the `core.ignoredNames` and `fuzzy-finder.ignoredNames`
config settings to filter out files and folders that will not be shown.
Both of those config settings are interpreted as arrays of
[minimatch](https://github.com/isaacs/minimatch) glob patterns.

This package also will also not show Git ignored files when the
`core.excludeVcsIgnoredPaths` is enabled.

![](https://f.cloud.github.com/assets/671378/2241456/100db6b8-9cd3-11e3-9b3a-569c6b50cc60.png)
