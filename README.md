# Fuzzy Finder package
[![OS X Build Status](https://travis-ci.org/atom/fuzzy-finder.svg?branch=master)](https://travis-ci.org/atom/fuzzy-finder) [![Windows Build Status](https://ci.appveyor.com/api/projects/status/b4b2dg5n9r1wdqad/branch/master?svg=true)](https://ci.appveyor.com/project/Atom/fuzzy-finder/branch/master) [![Dependency Status](https://david-dm.org/atom/fuzzy-finder.svg)](https://david-dm.org/atom/fuzzy-finder)

Quickly find and open files using <kbd>cmd-t</kbd>.

  * <kbd>cmd-t</kbd> or <kbd>cmd-p</kbd> to open the file finder
  * <kbd>cmd-b</kbd> to open the list of open buffers
  * <kbd>cmd-shift-b</kbd> to open the list of Git modified and untracked files
  * <kbd>enter</kbd> defaults to opening the selected file without leaving the current pane
  * <kbd>shift-enter</kbd> defaults to switching to another pane if the file is already open there
  * <kbd>cmd-k</kbd> <kbd>right</kbd> (or any other directional arrow) will open the highlighted file in a new pane on the side indicated by the arrow

Turning on the "Search All Panes" setting reverses the behavior of <kbd>enter</kbd> and <kbd>shift-enter</kbd> so <kbd>enter</kbd> opens the file in any pane and <kbd>shift-enter</kbd> creates a new tab in the current pane.

This package uses both the `core.ignoredNames` and `fuzzy-finder.ignoredNames` config settings to filter out files and folders that will not be shown. Both of those config settings are interpreted as arrays of [minimatch](https://github.com/isaacs/minimatch) glob patterns.

This package also will also not show Git ignored files when the `core.excludeVcsIgnoredPaths` is enabled.

![](https://f.cloud.github.com/assets/671378/2241456/100db6b8-9cd3-11e3-9b3a-569c6b50cc60.png)
