var $, $$, CompositeDisposable, FuzzyFinderView, Point, SelectListView, fs, fuzzaldrin, fuzzaldrinPlus, path, ref, ref1, repositoryForPath,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

path = require('path');

ref = require('atom'), Point = ref.Point, CompositeDisposable = ref.CompositeDisposable;

ref1 = require('atom-space-pen-views'), $ = ref1.$, $$ = ref1.$$, SelectListView = ref1.SelectListView;

repositoryForPath = require('./helpers').repositoryForPath;

fs = require('fs-plus');

fuzzaldrin = require('fuzzaldrin');

fuzzaldrinPlus = require('fuzzaldrin-plus');

module.exports = FuzzyFinderView = (function(superClass) {
  extend(FuzzyFinderView, superClass);

  function FuzzyFinderView() {
    return FuzzyFinderView.__super__.constructor.apply(this, arguments);
  }

  FuzzyFinderView.prototype.filePaths = null;

  FuzzyFinderView.prototype.projectRelativePaths = null;

  FuzzyFinderView.prototype.subscriptions = null;

  FuzzyFinderView.prototype.alternateScoring = false;

  FuzzyFinderView.prototype.initialize = function() {
    FuzzyFinderView.__super__.initialize.apply(this, arguments);
    this.addClass('fuzzy-finder');
    this.setMaxItems(10);
    this.subscriptions = new CompositeDisposable;
    atom.commands.add(this.element, {
      'pane:split-left': (function(_this) {
        return function() {
          return _this.splitOpenPath(function(pane) {
            return pane.splitLeft.bind(pane);
          });
        };
      })(this),
      'pane:split-right': (function(_this) {
        return function() {
          return _this.splitOpenPath(function(pane) {
            return pane.splitRight.bind(pane);
          });
        };
      })(this),
      'pane:split-down': (function(_this) {
        return function() {
          return _this.splitOpenPath(function(pane) {
            return pane.splitDown.bind(pane);
          });
        };
      })(this),
      'pane:split-up': (function(_this) {
        return function() {
          return _this.splitOpenPath(function(pane) {
            return pane.splitUp.bind(pane);
          });
        };
      })(this),
      'fuzzy-finder:invert-confirm': (function(_this) {
        return function() {
          return _this.confirmInvertedSelection();
        };
      })(this)
    });
    this.alternateScoring = atom.config.get('fuzzy-finder.useAlternateScoring');
    return this.subscriptions.add(atom.config.onDidChange('fuzzy-finder.useAlternateScoring', (function(_this) {
      return function(arg) {
        var newValue;
        newValue = arg.newValue;
        return _this.alternateScoring = newValue;
      };
    })(this)));
  };

  FuzzyFinderView.prototype.getFilterKey = function() {
    return 'projectRelativePath';
  };

  FuzzyFinderView.prototype.cancel = function() {
    var lastSearch;
    if (atom.config.get('fuzzy-finder.preserveLastSearch')) {
      lastSearch = this.getFilterQuery();
      FuzzyFinderView.__super__.cancel.apply(this, arguments);
      this.filterEditorView.setText(lastSearch);
      return this.filterEditorView.getModel().selectAll();
    } else {
      return FuzzyFinderView.__super__.cancel.apply(this, arguments);
    }
  };

  FuzzyFinderView.prototype.destroy = function() {
    var ref2, ref3;
    this.cancel();
    if ((ref2 = this.panel) != null) {
      ref2.destroy();
    }
    if ((ref3 = this.subscriptions) != null) {
      ref3.dispose();
    }
    return this.subscriptions = null;
  };

  FuzzyFinderView.prototype.viewForItem = function(arg) {
    var filePath, filterQuery, matches, projectRelativePath;
    filePath = arg.filePath, projectRelativePath = arg.projectRelativePath;
    filterQuery = this.getFilterQuery();
    if (this.alternateScoring) {
      matches = fuzzaldrinPlus.match(projectRelativePath, filterQuery);
    } else {
      matches = fuzzaldrin.match(projectRelativePath, filterQuery);
    }
    return $$(function() {
      var highlighter;
      highlighter = (function(_this) {
        return function(path, matches, offsetIndex) {
          var j, lastIndex, len, matchIndex, matchedChars, unmatched;
          lastIndex = 0;
          matchedChars = [];
          for (j = 0, len = matches.length; j < len; j++) {
            matchIndex = matches[j];
            matchIndex -= offsetIndex;
            if (matchIndex < 0) {
              continue;
            }
            unmatched = path.substring(lastIndex, matchIndex);
            if (unmatched) {
              if (matchedChars.length) {
                _this.span(matchedChars.join(''), {
                  "class": 'character-match'
                });
              }
              matchedChars = [];
              _this.text(unmatched);
            }
            matchedChars.push(path[matchIndex]);
            lastIndex = matchIndex + 1;
          }
          if (matchedChars.length) {
            _this.span(matchedChars.join(''), {
              "class": 'character-match'
            });
          }
          return _this.text(path.substring(lastIndex));
        };
      })(this);
      return this.li({
        "class": 'two-lines'
      }, (function(_this) {
        return function() {
          var baseOffset, ext, fileBasename, repo, status, typeClass;
          if ((repo = repositoryForPath(filePath)) != null) {
            status = repo.getCachedPathStatus(filePath);
            if (repo.isStatusNew(status)) {
              _this.div({
                "class": 'status status-added icon icon-diff-added'
              });
            } else if (repo.isStatusModified(status)) {
              _this.div({
                "class": 'status status-modified icon icon-diff-modified'
              });
            }
          }
          ext = path.extname(filePath);
          if (fs.isReadmePath(filePath)) {
            typeClass = 'icon-book';
          } else if (fs.isCompressedExtension(ext)) {
            typeClass = 'icon-file-zip';
          } else if (fs.isImageExtension(ext)) {
            typeClass = 'icon-file-media';
          } else if (fs.isPdfExtension(ext)) {
            typeClass = 'icon-file-pdf';
          } else if (fs.isBinaryExtension(ext)) {
            typeClass = 'icon-file-binary';
          } else {
            typeClass = 'icon-file-text';
          }
          fileBasename = path.basename(filePath);
          baseOffset = projectRelativePath.length - fileBasename.length;
          _this.div({
            "class": "primary-line file icon " + typeClass,
            'data-name': fileBasename,
            'data-path': projectRelativePath
          }, function() {
            return highlighter(fileBasename, matches, baseOffset);
          });
          return _this.div({
            "class": 'secondary-line path no-icon'
          }, function() {
            return highlighter(projectRelativePath, matches, 0);
          });
        };
      })(this));
    });
  };

  FuzzyFinderView.prototype.openPath = function(filePath, lineNumber, openOptions) {
    if (filePath) {
      return atom.workspace.open(filePath, openOptions).then((function(_this) {
        return function() {
          return _this.moveToLine(lineNumber);
        };
      })(this));
    }
  };

  FuzzyFinderView.prototype.moveToLine = function(lineNumber) {
    var position, textEditor;
    if (lineNumber == null) {
      lineNumber = -1;
    }
    if (!(lineNumber >= 0)) {
      return;
    }
    if (textEditor = atom.workspace.getActiveTextEditor()) {
      position = new Point(lineNumber);
      textEditor.scrollToBufferPosition(position, {
        center: true
      });
      textEditor.setCursorBufferPosition(position);
      return textEditor.moveToFirstCharacterOfLine();
    }
  };

  FuzzyFinderView.prototype.splitOpenPath = function(splitFn) {
    var editor, filePath, lineNumber, pane, ref2;
    filePath = ((ref2 = this.getSelectedItem()) != null ? ref2 : {}).filePath;
    lineNumber = this.getLineNumber();
    if (this.isQueryALineJump() && (editor = atom.workspace.getActiveTextEditor())) {
      pane = atom.workspace.getActivePane();
      splitFn(pane)({
        copyActiveItem: true
      });
      return this.moveToLine(lineNumber);
    } else if (!filePath) {

    } else if (pane = atom.workspace.getActivePane()) {
      splitFn(pane)();
      return this.openPath(filePath, lineNumber);
    } else {
      return this.openPath(filePath, lineNumber);
    }
  };

  FuzzyFinderView.prototype.populateList = function() {
    if (this.isQueryALineJump()) {
      this.list.empty();
      return this.setError('Jump to line in active editor');
    } else if (this.alternateScoring) {
      return this.populateAlternateList();
    } else {
      return FuzzyFinderView.__super__.populateList.apply(this, arguments);
    }
  };

  FuzzyFinderView.prototype.populateAlternateList = function() {
    var filterQuery, filteredItems, i, item, itemView, j, ref2;
    if (this.items == null) {
      return;
    }
    filterQuery = this.getFilterQuery();
    if (filterQuery.length) {
      filteredItems = fuzzaldrinPlus.filter(this.items, filterQuery, {
        key: this.getFilterKey()
      });
    } else {
      filteredItems = this.items;
    }
    this.list.empty();
    if (filteredItems.length) {
      this.setError(null);
      for (i = j = 0, ref2 = Math.min(filteredItems.length, this.maxItems); 0 <= ref2 ? j < ref2 : j > ref2; i = 0 <= ref2 ? ++j : --j) {
        item = filteredItems[i];
        itemView = $(this.viewForItem(item));
        itemView.data('select-list-item', item);
        this.list.append(itemView);
      }
      return this.selectItemView(this.list.find('li:first'));
    } else {
      return this.setError(this.getEmptyMessage(this.items.length, filteredItems.length));
    }
  };

  FuzzyFinderView.prototype.confirmSelection = function() {
    var item;
    item = this.getSelectedItem();
    return this.confirmed(item, {
      searchAllPanes: atom.config.get('fuzzy-finder.searchAllPanes')
    });
  };

  FuzzyFinderView.prototype.confirmInvertedSelection = function() {
    var item;
    item = this.getSelectedItem();
    return this.confirmed(item, {
      searchAllPanes: !atom.config.get('fuzzy-finder.searchAllPanes')
    });
  };

  FuzzyFinderView.prototype.confirmed = function(arg, openOptions) {
    var filePath, lineNumber;
    filePath = (arg != null ? arg : {}).filePath;
    if (atom.workspace.getActiveTextEditor() && this.isQueryALineJump()) {
      lineNumber = this.getLineNumber();
      this.cancel();
      return this.moveToLine(lineNumber);
    } else if (!filePath) {
      return this.cancel();
    } else if (fs.isDirectorySync(filePath)) {
      this.setError('Selected path is a directory');
      return setTimeout(((function(_this) {
        return function() {
          return _this.setError();
        };
      })(this)), 2000);
    } else {
      lineNumber = this.getLineNumber();
      this.cancel();
      return this.openPath(filePath, lineNumber, openOptions);
    }
  };

  FuzzyFinderView.prototype.isQueryALineJump = function() {
    var colon, query, trimmedPath;
    query = this.filterEditorView.getModel().getText();
    colon = query.indexOf(':');
    trimmedPath = this.getFilterQuery().trim();
    return trimmedPath === '' && colon !== -1;
  };

  FuzzyFinderView.prototype.getFilterQuery = function() {
    var colon, query;
    query = FuzzyFinderView.__super__.getFilterQuery.apply(this, arguments);
    colon = query.indexOf(':');
    if (colon !== -1) {
      query = query.slice(0, colon);
    }
    if (process.platform === 'win32') {
      query = query.replace(/\//g, '\\');
    }
    return query;
  };

  FuzzyFinderView.prototype.getLineNumber = function() {
    var colon, query;
    query = this.filterEditorView.getText();
    colon = query.indexOf(':');
    if (colon === -1) {
      return -1;
    } else {
      return parseInt(query.slice(colon + 1)) - 1;
    }
  };

  FuzzyFinderView.prototype.setItems = function(filePaths) {
    return FuzzyFinderView.__super__.setItems.call(this, this.projectRelativePathsForFilePaths(filePaths));
  };

  FuzzyFinderView.prototype.projectRelativePathsForFilePaths = function(filePaths) {
    var projectHasMultipleDirectories;
    if (filePaths !== this.filePaths) {
      projectHasMultipleDirectories = atom.project.getDirectories().length > 1;
      this.filePaths = filePaths;
      this.projectRelativePaths = this.filePaths.map(function(filePath) {
        var projectRelativePath, ref2, rootPath;
        ref2 = atom.project.relativizePath(filePath), rootPath = ref2[0], projectRelativePath = ref2[1];
        if (rootPath && projectHasMultipleDirectories) {
          projectRelativePath = path.join(path.basename(rootPath), projectRelativePath);
        }
        return {
          filePath: filePath,
          projectRelativePath: projectRelativePath
        };
      });
    }
    return this.projectRelativePaths;
  };

  FuzzyFinderView.prototype.show = function() {
    this.storeFocusedElement();
    if (this.panel == null) {
      this.panel = atom.workspace.addModalPanel({
        item: this
      });
    }
    this.panel.show();
    return this.focusFilterEditor();
  };

  FuzzyFinderView.prototype.hide = function() {
    var ref2;
    return (ref2 = this.panel) != null ? ref2.hide() : void 0;
  };

  FuzzyFinderView.prototype.cancelled = function() {
    return this.hide();
  };

  return FuzzyFinderView;

})(SelectListView);

// ---
// generated by coffee-script 1.9.2
