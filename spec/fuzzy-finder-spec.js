/* eslint-env jasmine */
/* global CustomEvent, advanceClock, waitsForPromise */

const net = require('net')
const path = require('path')
const _ = require('underscore-plus')
const etch = require('etch')
const fs = require('fs-plus')
const temp = require('temp')
const wrench = require('wrench')

const PathLoader = require('../lib/path-loader')
const DefaultFileIcons = require('../lib/default-file-icons')

function rmrf (_path) {
  if (fs.statSync(_path).isDirectory()) {
    _.each(fs.readdirSync(_path), (child) => rmrf(path.join(_path, child)))
    fs.rmdirSync(_path)
  } else {
    fs.unlinkSync(_path)
  }
}

function getOrScheduleUpdatePromise () {
  return new Promise((resolve) => etch.getScheduler().updateDocument(resolve))
}

describe('FuzzyFinder', () => {
  let rootDir1, rootDir2
  let fuzzyFinder, projectView, bufferView, gitStatusView, workspaceElement, fixturesPath

  beforeEach(() => {
    rootDir1 = fs.realpathSync(temp.mkdirSync('root-dir1'))
    rootDir2 = fs.realpathSync(temp.mkdirSync('root-dir2'))

    fixturesPath = atom.project.getPaths()[0]

    wrench.copyDirSyncRecursive(
      path.join(fixturesPath, 'root-dir1'),
      rootDir1,
      {forceDelete: true}
    )

    wrench.copyDirSyncRecursive(
      path.join(fixturesPath, 'root-dir2'),
      rootDir2,
      {forceDelete: true}
    )

    atom.project.setPaths([rootDir1, rootDir2])

    workspaceElement = atom.views.getView(atom.workspace)

    waitsForPromise(() => atom.workspace.open(path.join(rootDir1, 'sample.js')))

    waitsForPromise(() =>
      atom.packages.activatePackage('fuzzy-finder').then((pack) => {
        fuzzyFinder = pack.mainModule
        projectView = fuzzyFinder.createProjectView()
        bufferView = fuzzyFinder.createBufferView()
        gitStatusView = fuzzyFinder.createGitStatusView()
      })
    )
  })

  function waitForPathsToDisplay (fuzzyFinderView) {
    waitsFor(
      'paths to display',
      5000,
      () => fuzzyFinderView.element.querySelectorAll('li').length > 0
    )
  }

  function eachFilePath (dirPaths, fn) {
    for (let dirPath of dirPaths) {
      wrench.readdirSyncRecursive(dirPath).filter((filePath) => {
        const fullPath = path.join(dirPath, filePath)
        if (fs.isFileSync(fullPath)) {
          fn(filePath)
        }
      })
    }
  }

  describe('file-finder behavior', () => {
    beforeEach(() =>
      waitsFor(() => projectView.selectListView.update({maxResults: null}))
    )

    describe('toggling', () => {
      describe('when the project has multiple paths', () => {
        it('shows or hides the fuzzy-finder and returns focus to the active editor if it is already showing', () => {
          jasmine.attachToDOM(workspaceElement)

          expect(atom.workspace.panelForItem(projectView)).toBeNull()
          atom.workspace.getActivePane().splitRight({copyActiveItem: true})
          const [editor1, editor2] = Array.from(atom.workspace.getTextEditors())

          waitsForPromise(() => projectView.toggle())

          runs(() => {
            expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
            expect(projectView.selectListView.refs.queryEditor.element).toHaveFocus()
            projectView.selectListView.refs.queryEditor.insertText('this should not show up next time we toggle')
          })

          waitsForPromise(() => projectView.toggle())

          runs(() => {
            expect(atom.views.getView(editor1)).not.toHaveFocus()
            expect(atom.views.getView(editor2)).toHaveFocus()
            expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(false)
          })

          waitsForPromise(() => projectView.toggle())

          runs(() =>
            expect(projectView.selectListView.refs.queryEditor.getText()).toBe('')
          )
        })

        it('shows all files for the current project and selects the first', () => {
          jasmine.attachToDOM(workspaceElement)

          waitsForPromise(() => projectView.toggle())

          runs(() => {
            expect(projectView.element.querySelector('.loading').textContent.length).toBeGreaterThan(0)
            waitForPathsToDisplay(projectView)
          })

          runs(() => {
            eachFilePath([rootDir1, rootDir2], (filePath) => {
              const item = Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes(filePath))
              expect(item).toExist()
              const nameDiv = item.querySelector('div:first-child')
              expect(nameDiv.dataset.name).toBe(path.basename(filePath))
              expect(nameDiv.textContent).toBe(path.basename(filePath))
            })

            expect(projectView.element.querySelector('.loading')).not.toBeVisible()
          })
        })

        it("shows each file's path, including which root directory it's in", () => {
          waitsForPromise(() => projectView.toggle())

          waitForPathsToDisplay(projectView)

          runs(() => {
            eachFilePath([rootDir1], (filePath) => {
              const item = Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes(filePath))
              expect(item).toExist()
              expect(item.querySelectorAll('div')[1].textContent).toBe(path.join(path.basename(rootDir1), filePath))
            })

            eachFilePath([rootDir2], (filePath) => {
              const item = Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes(filePath))
              expect(item).toExist()
              expect(item.querySelectorAll('div')[1].textContent).toBe(path.join(path.basename(rootDir2), filePath))
            })
          })
        })

        it('only creates a single path loader task', () => {
          spyOn(PathLoader, 'startTask').andCallThrough()

          waitsForPromise(() => projectView.toggle()) // Show

          waitsForPromise(() => projectView.toggle()) // Hide

          waitsForPromise(() => projectView.toggle()) // Show again

          runs(() => expect(PathLoader.startTask.callCount).toBe(1))
        })

        it('puts the last opened path first', () => {
          waitsForPromise(() => atom.workspace.open('sample.txt'))
          waitsForPromise(() => atom.workspace.open('sample.js'))

          waitsForPromise(() => projectView.toggle())

          runs(() => waitForPathsToDisplay(projectView))

          runs(() => {
            expect(projectView.element.querySelectorAll('li')[0].textContent).toContain('sample.txt')
            expect(projectView.element.querySelectorAll('li')[1].textContent).toContain('sample.html')
          })
        })

        it('displays paths correctly if the last-opened path is not part of the project (regression)', () => {
          waitsForPromise(() => atom.workspace.open('foo.txt'))
          waitsForPromise(() => atom.workspace.open('sample.js'))

          waitsForPromise(() => projectView.toggle())

          runs(() => waitForPathsToDisplay(projectView))
        })

        describe('symlinks on #darwin or #linux', () => {
          let junkDirPath, junkFilePath

          beforeEach(() => {
            junkDirPath = fs.realpathSync(temp.mkdirSync('junk-1'))
            junkFilePath = path.join(junkDirPath, 'file.txt')
            fs.writeFileSync(junkFilePath, 'txt')
            fs.writeFileSync(path.join(junkDirPath, 'a'), 'txt')

            const brokenFilePath = path.join(junkDirPath, 'delete.txt')
            fs.writeFileSync(brokenFilePath, 'delete-me')

            fs.symlinkSync(junkFilePath, atom.project.getDirectories()[0].resolve('symlink-to-file'))
            fs.symlinkSync(junkDirPath, atom.project.getDirectories()[0].resolve('symlink-to-dir'))
            fs.symlinkSync(brokenFilePath, atom.project.getDirectories()[0].resolve('broken-symlink'))

            fs.symlinkSync(atom.project.getDirectories()[0].resolve('sample.txt'), atom.project.getDirectories()[0].resolve('symlink-to-internal-file'))
            fs.symlinkSync(atom.project.getDirectories()[0].resolve('dir'), atom.project.getDirectories()[0].resolve('symlink-to-internal-dir'))

            fs.unlinkSync(brokenFilePath)
          })

          it('indexes project paths that are symlinks', () => {
            const symlinkProjectPath = path.join(junkDirPath, 'root-dir-symlink')
            fs.symlinkSync(atom.project.getPaths()[0], symlinkProjectPath)

            atom.project.setPaths([symlinkProjectPath])

            waitsForPromise(() => projectView.toggle())

            runs(() => {})

            waitForPathsToDisplay(projectView)

            runs(() => expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('sample.txt'))).toBeDefined())
          })

          it('includes symlinked file paths', () => {
            waitsForPromise(() => projectView.toggle())

            runs(() => {})

            waitForPathsToDisplay(projectView)

            runs(() => {
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-file'))).toBeDefined()
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-internal-file'))).not.toBeDefined()
            })
          })

          it('excludes symlinked folder paths if followSymlinks is false', () => {
            atom.config.set('core.followSymlinks', false)

            waitsForPromise(() => projectView.toggle())

            runs(() => {})

            waitForPathsToDisplay(projectView)

            runs(() => {
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-dir'))).not.toBeDefined()
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-dir/a'))).not.toBeDefined()

              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-internal-dir'))).not.toBeDefined()
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-internal-dir/a'))).not.toBeDefined()
            })
          })

          it('includes symlinked folder paths if followSymlinks is true', () => {
            atom.config.set('core.followSymlinks', true)

            waitsForPromise(() => projectView.toggle())

            runs(() => {})

            waitForPathsToDisplay(projectView)

            runs(() => {
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-dir/a'))).toBeDefined()
              expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('symlink-to-internal-dir/a'))).not.toBeDefined()
            })
          })
        })

        describe('socket files on #darwin or #linux', () => {
          let socketServer, socketPath

          beforeEach(() => {
            socketServer = net.createServer(() => {})
            socketPath = path.join(rootDir1, 'some.sock')
            waitsFor(done => socketServer.listen(socketPath, done))
          })

          afterEach(() => waitsFor(done => socketServer.close(done)))

          it('ignores them', () => {
            waitsForPromise(() => projectView.toggle())

            runs(() => {})
            waitForPathsToDisplay(projectView)
            expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('some.sock'))).not.toBeDefined()
          })
        })

        it('ignores paths that match entries in config.fuzzy-finder.ignoredNames', () => {
          atom.config.set('fuzzy-finder.ignoredNames', ['sample.js', '*.txt'])

          waitsForPromise(() => projectView.toggle())

          runs(() => {})

          waitForPathsToDisplay(projectView)

          runs(() => {
            expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('sample.js'))).not.toBeDefined()
            expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('sample.txt'))).not.toBeDefined()
            expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('a'))).toBeDefined()
          })
        })

        it("only shows a given path once, even if it's within multiple root folders", () => {
          const childDir1 = path.join(rootDir1, 'a-child')
          const childFile1 = path.join(childDir1, 'child-file.txt')
          fs.mkdirSync(childDir1)
          fs.writeFileSync(childFile1, 'stuff')
          atom.project.addPath(childDir1)

          waitsForPromise(() => projectView.toggle())

          runs(() => {})
          waitForPathsToDisplay(projectView)

          runs(() => expect(Array.from(projectView.element.querySelectorAll('li')).filter(a => a.textContent.includes('child-file.txt')).length).toBe(1))
        })
      })

      describe('when the project only has one path', () => {
        beforeEach(() => atom.project.setPaths([rootDir1]))

        it("doesn't show the name of each file's root directory", () => {
          waitsForPromise(() => projectView.toggle())

          runs(() => {})

          waitForPathsToDisplay(projectView)

          runs(() => {
            const items = Array.from(projectView.element.querySelectorAll('li'))
            eachFilePath([rootDir1], (filePath) => {
              const item = items.find(a => a.textContent.includes(filePath))
              expect(item).toExist()
              expect(item).not.toHaveText(path.basename(rootDir1))
            })
          })
        })
      })

      describe('when the project has no path', () => {
        beforeEach(() => {
          jasmine.attachToDOM(workspaceElement)
          atom.project.setPaths([])
        })

        it('shows an empty message with no files in the list', () => {
          waitsForPromise(() => projectView.toggle())

          runs(() => {
            expect(projectView.selectListView.refs.emptyMessage).toBeVisible()
            expect(projectView.selectListView.refs.emptyMessage.textContent).toBe('Project is empty')
            expect(projectView.element.querySelectorAll('li').length).toBe(0)
          })
        })
      })
    })

    describe("when a project's root path is unlinked", () => {
      beforeEach(() => {
        if (fs.existsSync(rootDir1)) { rmrf(rootDir1) }
        if (fs.existsSync(rootDir2)) { rmrf(rootDir2) }
      })

      it('posts an error notification', () => {
        spyOn(atom.notifications, 'addError')
        waitsForPromise(() => projectView.toggle())

        runs(() => {})
        waitsFor(() => atom.workspace.panelForItem(projectView).isVisible())
        runs(() => expect(atom.notifications.addError).toHaveBeenCalled())
      })
    })

    describe('when a path selection is confirmed', () => {
      it('opens the file associated with that path in that split', () => {
        jasmine.attachToDOM(workspaceElement)
        const editor1 = atom.workspace.getActiveTextEditor()
        atom.workspace.getActivePane().splitRight({copyActiveItem: true})
        const editor2 = atom.workspace.getActiveTextEditor()
        const expectedPath = atom.project.getDirectories()[0].resolve('dir/a')

        waitsForPromise(() => projectView.toggle())

        runs(() => projectView.confirm({filePath: expectedPath}))

        waitsFor(() => atom.workspace.getActivePane().getItems().length === 2)

        runs(() => {
          const editor3 = atom.workspace.getActiveTextEditor()
          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(false)
          expect(editor1.getPath()).not.toBe(expectedPath)
          expect(editor2.getPath()).not.toBe(expectedPath)
          expect(editor3.getPath()).toBe(expectedPath)
          expect(atom.views.getView(editor3)).toHaveFocus()
        })
      })

      describe('when the selected path is a directory', () =>
        it("leaves the the tree view open, doesn't open the path in the editor, and displays an error", () => {
          jasmine.attachToDOM(workspaceElement)
          const editorPath = atom.workspace.getActiveTextEditor().getPath()
          waitsForPromise(() => projectView.toggle())

          runs(() => {})
          projectView.confirm({filePath: atom.project.getDirectories()[0].resolve('dir')})
          expect(projectView.element.parentElement).toBeDefined()
          expect(atom.workspace.getActiveTextEditor().getPath()).toBe(editorPath)

          waitsFor(() => projectView.selectListView.refs.errorMessage)

          runs(() => advanceClock(2000))

          waitsFor(() => !projectView.selectListView.refs.errorMessage)
        })
      )
    })
  })

  describe('buffer-finder behavior', () => {
    describe('toggling', () => {
      describe('when there are pane items with paths', () => {
        beforeEach(() => {
          jasmine.useRealClock()
          jasmine.attachToDOM(workspaceElement)

          waitsForPromise(() => atom.workspace.open('sample.txt'))
        })

        it("shows the FuzzyFinder if it isn't showing, or hides it and returns focus to the active editor", () => {
          expect(atom.workspace.panelForItem(bufferView)).toBeNull()
          atom.workspace.getActivePane().splitRight({copyActiveItem: true})
          const [editor1, editor2, editor3] = atom.workspace.getTextEditors() // eslint-disable-line no-unused-vars
          expect(atom.workspace.getActivePaneItem()).toBe(editor3)

          expect(atom.views.getView(editor3)).toHaveFocus()

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
            expect(workspaceElement.querySelector('.fuzzy-finder')).toHaveFocus()
            bufferView.selectListView.refs.queryEditor.insertText('this should not show up next time we toggle')
          })

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(atom.views.getView(editor3)).toHaveFocus()
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(false)
          })

          waitsForPromise(() => bufferView.toggle())

          runs(() => expect(bufferView.selectListView.refs.queryEditor.getText()).toBe(''))
        })

        it('lists the paths of the current items, sorted by most recently opened but with the current item last', () => {
          waitsForPromise(() => atom.workspace.open('sample-with-tabs.coffee'))

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
            expect(Array.from(bufferView.element.querySelectorAll('li > div.file')).map(e => e.textContent)).toEqual(['sample.txt', 'sample.js', 'sample-with-tabs.coffee'])
          })

          waitsForPromise(() => bufferView.toggle())

          runs(() => expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(false))

          waitsForPromise(() => atom.workspace.open('sample.txt'))

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
            expect(Array.from(bufferView.element.querySelectorAll('li > div.file')).map(e => e.textContent)).toEqual(['sample-with-tabs.coffee', 'sample.js', 'sample.txt'])
            expect(bufferView.element.querySelector('li')).toHaveClass('selected')
          })
        })

        it('serializes the list of paths and their last opened time', () => {
          waitsForPromise(() => atom.workspace.open('sample-with-tabs.coffee'))

          waitsForPromise(() => bufferView.toggle())

          waitsForPromise(() => atom.workspace.open('sample.js'))

          waitsForPromise(() => bufferView.toggle())

          waitsForPromise(() => atom.workspace.open())

          waitsForPromise(() => Promise.resolve(atom.packages.deactivatePackage('fuzzy-finder')))

          runs(() => {
            let states = _.map(atom.packages.getPackageState('fuzzy-finder'), (path, time) => [path, time])
            expect(states.length).toBe(3)
            states = _.sortBy(states, (path, time) => -time)

            const paths = ['sample-with-tabs.coffee', 'sample.txt', 'sample.js']

            for (let [time, bufferPath] of states) {
              expect(_.last(bufferPath.split(path.sep))).toBe(paths.shift())
              expect(time).toBeGreaterThan(50000)
            }
          })
        })
      })

      describe('when there are only panes with anonymous items', () =>
        it('does not open', () => {
          atom.workspace.getActivePane().destroy()
          waitsForPromise(() => atom.workspace.open())

          waitsForPromise(() => bufferView.toggle())

          runs(() => expect(atom.workspace.panelForItem(bufferView)).toBeNull())
        })
      )

      describe('when there are no pane items', () =>
        it('does not open', () => {
          atom.workspace.getActivePane().destroy()
          waitsForPromise(() => bufferView.toggle())

          runs(() => expect(atom.workspace.panelForItem(bufferView)).toBeNull())
        })
      )

      describe('when multiple sessions are opened on the same path', () =>
        it('does not display duplicates for that path in the list', () => {
          waitsForPromise(() => atom.workspace.open('sample.js'))

          runs(() => atom.workspace.getActivePane().splitRight({copyActiveItem: true}))

          waitsForPromise(() => bufferView.toggle())

          runs(() => expect(Array.from(bufferView.element.querySelectorAll('li > div.file')).map(e => e.textContent)).toEqual(['sample.js']))
        })
    )
    })

    describe('when a path selection is confirmed', () => {
      let editor1, editor2, editor3

      beforeEach(() => {
        jasmine.attachToDOM(workspaceElement)
        atom.workspace.getActivePane().splitRight({copyActiveItem: true})

        waitsForPromise(() => atom.workspace.open('sample.txt'))

        runs(() => {
          [editor1, editor2, editor3] = Array.from(atom.workspace.getTextEditors())

          expect(atom.workspace.getActiveTextEditor()).toBe(editor3)

          atom.commands.dispatch(atom.views.getView(editor2), 'pane:show-previous-item')
        })

        waitsForPromise(() => bufferView.toggle())
      })

      describe('when the active pane has an item for the selected path', () =>
        it('switches to the item for the selected path', () => {
          const expectedPath = atom.project.getDirectories()[0].resolve('sample.txt')
          bufferView.confirm({filePath: expectedPath})

          waitsFor(() => atom.workspace.getActiveTextEditor().getPath() === expectedPath)

          runs(() => {
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(false)
            expect(editor1.getPath()).not.toBe(expectedPath)
            expect(editor2.getPath()).not.toBe(expectedPath)
            expect(editor3.getPath()).toBe(expectedPath)
            expect(atom.views.getView(editor3)).toHaveFocus()
          })
        })
      )

      describe('when the active pane does not have an item for the selected path and fuzzy-finder.searchAllPanes is false', () =>
        it('adds a new item to the active pane for the selected path', () => {
          const expectedPath = atom.project.getDirectories()[0].resolve('sample.txt')

          waitsForPromise(() => bufferView.toggle())

          runs(() => atom.views.getView(editor1).focus())

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(atom.workspace.getActiveTextEditor()).toBe(editor1)
            bufferView.confirm({filePath: expectedPath}, atom.config.get('fuzzy-finder.searchAllPanes'))
          })

          waitsFor(() => atom.workspace.getActivePane().getItems().length === 2)

          runs(() => {
            const editor4 = atom.workspace.getActiveTextEditor()

            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(false)

            expect(editor4).not.toBe(editor1)
            expect(editor4).not.toBe(editor2)
            expect(editor4).not.toBe(editor3)

            expect(editor4.getPath()).toBe(expectedPath)
            expect(atom.views.getView(editor4)).toHaveFocus()
          })
        })
      )

      describe('when the active pane does not have an item for the selected path and fuzzy-finder.searchAllPanes is true', () => {
        beforeEach(() => atom.config.set('fuzzy-finder.searchAllPanes', true))

        it('switches to the pane with the item for the selected path', () => {
          const expectedPath = atom.project.getDirectories()[0].resolve('sample.txt')
          let originalPane = null

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            atom.views.getView(editor1).focus()
            originalPane = atom.workspace.getActivePane()
          })

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(atom.workspace.getActiveTextEditor()).toBe(editor1)
            bufferView.confirm({filePath: expectedPath}, {searchAllPanes: atom.config.get('fuzzy-finder.searchAllPanes')})
          })

          waitsFor(() => atom.workspace.getActiveTextEditor().getPath() === expectedPath)

          runs(() => {
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(false)
            expect(atom.workspace.getActivePane()).not.toBe(originalPane)
            expect(atom.workspace.getActiveTextEditor()).toBe(editor3)
            expect(atom.workspace.getPaneItems().length).toBe(3)
          })
        })
      })
    })
  })

  describe('common behavior between file and buffer finder', () =>
    describe('when the fuzzy finder is cancelled', () => {
      describe('when an editor is open', () =>
        it('detaches the finder and focuses the previously focused element', () => {
          jasmine.attachToDOM(workspaceElement)
          const activeEditor = atom.workspace.getActiveTextEditor()

          waitsForPromise(() => projectView.toggle())

          runs(() => {
            expect(projectView.element.parentElement).toBeDefined()
            expect(projectView.selectListView.refs.queryEditor.element).toHaveFocus()

            projectView.cancel()

            expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(false)
            expect(atom.views.getView(activeEditor)).toHaveFocus()
          })
        })
      )

      describe('when no editors are open', () =>
        it('detaches the finder and focuses the previously focused element', () => {
          jasmine.attachToDOM(workspaceElement)
          atom.workspace.getActivePane().destroy()

          const inputView = document.createElement('input')
          workspaceElement.appendChild(inputView)
          inputView.focus()

          waitsForPromise(() => projectView.toggle())

          runs(() => {
            expect(projectView.element.parentElement).toBeDefined()
            expect(projectView.selectListView.refs.queryEditor.element).toHaveFocus()
            projectView.cancel()
            expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(false)
            expect(inputView).toHaveFocus()
          })
        })
      )
    })
  )

  describe('cached file paths', () => {
    beforeEach(() => {
      spyOn(PathLoader, 'startTask').andCallThrough()
      spyOn(atom.workspace, 'getTextEditors').andCallThrough()
    })

    it('caches file paths after first time', () => {
      waitsForPromise(() => projectView.toggle())

      runs(() => waitForPathsToDisplay(projectView))

      runs(() => {
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
      })

      waitsForPromise(() => projectView.toggle())

      waitsForPromise(() => projectView.toggle())

      runs(() => waitForPathsToDisplay(projectView))

      runs(() => expect(PathLoader.startTask).not.toHaveBeenCalled())
    })

    it("doesn't cache buffer paths", () => {
      waitsForPromise(() => bufferView.toggle())

      runs(() => waitForPathsToDisplay(bufferView))

      runs(() => {
        expect(atom.workspace.getTextEditors).toHaveBeenCalled()
        atom.workspace.getTextEditors.reset()
      })

      waitsForPromise(() => bufferView.toggle())

      waitsForPromise(() => bufferView.toggle())

      runs(() => waitForPathsToDisplay(bufferView))

      runs(() => expect(atom.workspace.getTextEditors).toHaveBeenCalled())
    })

    it('busts the cache when the window gains focus', () => {
      waitsForPromise(() => projectView.toggle())

      runs(() => waitForPathsToDisplay(projectView))

      runs(() => {
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        window.dispatchEvent(new CustomEvent('focus'))
        waitsForPromise(() => projectView.toggle())
      })

      waitsForPromise(() => projectView.toggle())

      runs(() => expect(PathLoader.startTask).toHaveBeenCalled())
    })

    it('busts the cache when the project path changes', () => {
      waitsForPromise(() => projectView.toggle())

      runs(() => waitForPathsToDisplay(projectView))

      runs(() => {
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        atom.project.setPaths([temp.mkdirSync('atom')])
      })

      waitsForPromise(() => projectView.toggle())

      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(PathLoader.startTask).toHaveBeenCalled()
        expect(projectView.element.querySelectorAll('li').length).toBe(0)
      })
    })

    describe('the initial load paths task started during package activation', () => {
      beforeEach(() => {
        fuzzyFinder.projectView.destroy()
        fuzzyFinder.projectView = null
        fuzzyFinder.startLoadPathsTask()

        waitsFor(() => fuzzyFinder.projectPaths)
      })

      it('passes the indexed paths into the project view when it is created', () => {
        const {projectPaths} = fuzzyFinder
        expect(projectPaths.length).toBe(19)
        projectView = fuzzyFinder.createProjectView()
        expect(projectView.paths).toBe(projectPaths)
        expect(projectView.reloadPaths).toBe(false)
      })

      it('busts the cached paths when the project paths change', () => {
        atom.project.setPaths([])

        const {projectPaths} = fuzzyFinder
        expect(projectPaths).toBe(null)

        projectView = fuzzyFinder.createProjectView()
        expect(projectView.paths).toBe(null)
        expect(projectView.reloadPaths).toBe(true)
      })
    })
  })

  describe('opening a path into a split', () => {
    it('opens the path by splitting the active editor left', () => {
      expect(atom.workspace.getCenter().getPanes().length).toBe(1)
      let filePath = null

      waitsForPromise(() => bufferView.toggle())

      runs(() => {
        ({filePath} = bufferView.selectListView.getSelectedItem())
        atom.commands.dispatch(bufferView.element, 'pane:split-left')
      })

      waitsFor(() => atom.workspace.getCenter().getPanes().length === 2)

      waitsFor(() => atom.workspace.getActiveTextEditor())

      runs(() => {
        const [leftPane, rightPane] = atom.workspace.getCenter().getPanes() // eslint-disable-line no-unused-vars
        expect(atom.workspace.getActivePane()).toBe(leftPane)
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe(atom.project.getDirectories()[0].resolve(filePath))
      })
    })

    it('opens the path by splitting the active editor right', () => {
      expect(atom.workspace.getCenter().getPanes().length).toBe(1)
      let filePath = null

      waitsForPromise(() => bufferView.toggle())

      runs(() => {
        ({filePath} = bufferView.selectListView.getSelectedItem())
        atom.commands.dispatch(bufferView.element, 'pane:split-right')
      })

      waitsFor(() => atom.workspace.getCenter().getPanes().length === 2)

      waitsFor(() => atom.workspace.getActiveTextEditor())

      runs(() => {
        const [leftPane, rightPane] = atom.workspace.getCenter().getPanes() // eslint-disable-line no-unused-vars
        expect(atom.workspace.getActivePane()).toBe(rightPane)
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe(atom.project.getDirectories()[0].resolve(filePath))
      })
    })

    it('opens the path by splitting the active editor up', () => {
      expect(atom.workspace.getCenter().getPanes().length).toBe(1)
      let filePath = null

      waitsForPromise(() => bufferView.toggle())

      runs(() => {
        ({filePath} = bufferView.selectListView.getSelectedItem())
        atom.commands.dispatch(bufferView.element, 'pane:split-up')
      })

      waitsFor(() => atom.workspace.getCenter().getPanes().length === 2)

      waitsFor(() => atom.workspace.getActiveTextEditor())

      runs(() => {
        const [topPane, bottomPane] = atom.workspace.getCenter().getPanes() // eslint-disable-line no-unused-vars
        expect(atom.workspace.getActivePane()).toBe(topPane)
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe(atom.project.getDirectories()[0].resolve(filePath))
      })
    })

    it('opens the path by splitting the active editor down', () => {
      expect(atom.workspace.getCenter().getPanes().length).toBe(1)
      let filePath = null

      waitsForPromise(() => bufferView.toggle())

      runs(() => {
        ({filePath} = bufferView.selectListView.getSelectedItem())
        atom.commands.dispatch(bufferView.element, 'pane:split-down')
      })

      waitsFor(() => atom.workspace.getCenter().getPanes().length === 2)

      waitsFor(() => atom.workspace.getActiveTextEditor())

      runs(() => {
        const [topPane, bottomPane] = atom.workspace.getCenter().getPanes() // eslint-disable-line no-unused-vars
        expect(atom.workspace.getActivePane()).toBe(bottomPane)
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe(atom.project.getDirectories()[0].resolve(filePath))
      })
    })
  })

  describe('when the filter text contains a colon followed by a number', () => {
    beforeEach(() => {
      jasmine.attachToDOM(workspaceElement)
      expect(atom.workspace.panelForItem(projectView)).toBeNull()

      waitsForPromise(() => atom.workspace.open('sample.txt'))

      runs(() => {
        const [editor1, editor2] = Array.from(atom.workspace.getTextEditors())
        expect(atom.workspace.getActiveTextEditor()).toBe(editor2)
        expect(editor1.getCursorBufferPosition()).toEqual([0, 0])
      })
    })

    describe('when the filter text has a file path', () => {
      it('opens the selected path to that line number', () => {
        const [editor1, editor2] = atom.workspace.getTextEditors() // eslint-disable-line no-unused-vars

        waitsForPromise(() => bufferView.toggle())

        runs(() => {
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
          bufferView.selectListView.refs.queryEditor.setText('sample.js:4')
        })

        waitsForPromise(() => getOrScheduleUpdatePromise())

        runs(() => {
          const {filePath} = bufferView.selectListView.getSelectedItem()
          expect(atom.project.getDirectories()[0].resolve(filePath)).toBe(editor1.getPath())

          spyOn(bufferView, 'moveToLine').andCallThrough()
          atom.commands.dispatch(bufferView.element, 'core:confirm')
        })

        waitsFor(() => bufferView.moveToLine.callCount > 0)

        runs(() => {
          expect(atom.workspace.getActiveTextEditor()).toBe(editor1)
          expect(editor1.getCursorBufferPosition()).toEqual([3, 4])
        })
      })
    })
  })

  describe('match highlighting', () => {
    beforeEach(() => {
      jasmine.attachToDOM(workspaceElement)
      waitsForPromise(() => bufferView.toggle())
    })

    it('highlights an exact match', () => {
      bufferView.selectListView.refs.queryEditor.setText('sample.js')

      waitsForPromise(() => getOrScheduleUpdatePromise())

      runs(() => {
        const resultView = bufferView.element.querySelector('li')
        const primaryMatches = resultView.querySelectorAll('.primary-line .character-match')
        const secondaryMatches = resultView.querySelectorAll('.secondary-line .character-match')
        expect(primaryMatches.length).toBe(1)
        expect(primaryMatches[primaryMatches.length - 1].textContent).toBe('sample.js')
        // Use `toBeGreaterThan` because dir may have some characters in it
        expect(secondaryMatches.length).toBeGreaterThan(0)
        expect(secondaryMatches[secondaryMatches.length - 1].textContent).toBe('sample.js')
      })
    })

    it('highlights a partial match', () => {
      bufferView.selectListView.refs.queryEditor.setText('sample')

      waitsForPromise(() => getOrScheduleUpdatePromise())

      runs(() => {
        const resultView = bufferView.element.querySelector('li')
        const primaryMatches = resultView.querySelectorAll('.primary-line .character-match')
        const secondaryMatches = resultView.querySelectorAll('.secondary-line .character-match')
        expect(primaryMatches.length).toBe(1)
        expect(primaryMatches[primaryMatches.length - 1].textContent).toBe('sample')
        // Use `toBeGreaterThan` because dir may have some characters in it
        expect(secondaryMatches.length).toBeGreaterThan(0)
        expect(secondaryMatches[secondaryMatches.length - 1].textContent).toBe('sample')
      })
    })

    it('highlights multiple matches in the file name', () => {
      bufferView.selectListView.refs.queryEditor.setText('samplejs')

      waitsForPromise(() => getOrScheduleUpdatePromise())

      runs(() => {
        const resultView = bufferView.element.querySelector('li')
        const primaryMatches = resultView.querySelectorAll('.primary-line .character-match')
        const secondaryMatches = resultView.querySelectorAll('.secondary-line .character-match')
        expect(primaryMatches.length).toBe(2)
        expect(primaryMatches[0].textContent).toBe('sample')
        expect(primaryMatches[primaryMatches.length - 1].textContent).toBe('js')
        // Use `toBeGreaterThan` because dir may have some characters in it
        expect(secondaryMatches.length).toBeGreaterThan(1)
        expect(secondaryMatches[secondaryMatches.length - 1].textContent).toBe('js')
      })
    })

    it('highlights matches in the directory and file name', () => {
      spyOn(bufferView, 'projectRelativePathsForFilePaths').andCallFake((paths) => paths)
      bufferView.selectListView.refs.queryEditor.setText('root-dirsample')

      waitsForPromise(() =>
        bufferView.setItems([
          {
            filePath: '/test/root-dir1/sample.js',
            projectRelativePath: 'root-dir1/sample.js'
          }
        ])
      )

      runs(() => {
        const resultView = bufferView.element.querySelector('li')
        const primaryMatches = resultView.querySelectorAll('.primary-line .character-match')
        const secondaryMatches = resultView.querySelectorAll('.secondary-line .character-match')
        expect(primaryMatches.length).toBe(1)
        expect(primaryMatches[primaryMatches.length - 1].textContent).toBe('sample')
        expect(secondaryMatches.length).toBe(2)
        expect(secondaryMatches[0].textContent).toBe('root-dir')
        expect(secondaryMatches[secondaryMatches.length - 1].textContent).toBe('sample')
      })
    })

    describe("when the filter text doesn't have a file path", () => {
      it('moves the cursor in the active editor to that line number', () => {
        const [editor1, editor2] = atom.workspace.getTextEditors() // eslint-disable-line no-unused-vars

        waitsForPromise(() => atom.workspace.open('sample.js'))

        runs(() => expect(atom.workspace.getActiveTextEditor()).toBe(editor1))

        waitsForPromise(() => bufferView.toggle())

        runs(() => {
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
          bufferView.selectListView.refs.queryEditor.insertText(':4')
        })

        waitsForPromise(() => getOrScheduleUpdatePromise())

        runs(() => {
          expect(bufferView.element.querySelectorAll('li').length).toBe(0)
          spyOn(bufferView, 'moveToLine').andCallThrough()
          atom.commands.dispatch(bufferView.element, 'core:confirm')
        })

        waitsFor(() => bufferView.moveToLine.callCount > 0)

        runs(() => {
          expect(atom.workspace.getActiveTextEditor()).toBe(editor1)
          expect(editor1.getCursorBufferPosition()).toEqual([3, 4])
        })
      })
    })

    describe('when splitting panes', () => {
      it('opens the selected path to that line number in a new pane', () => {
        const [editor1, editor2] = atom.workspace.getTextEditors() // eslint-disable-line no-unused-vars

        waitsForPromise(() => atom.workspace.open('sample.js'))

        runs(() => expect(atom.workspace.getActiveTextEditor()).toBe(editor1))

        waitsForPromise(() => bufferView.toggle())

        runs(() => {
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
          bufferView.selectListView.refs.queryEditor.insertText(':4')
        })

        waitsForPromise(() => getOrScheduleUpdatePromise())

        runs(() => {
          expect(bufferView.element.querySelectorAll('li').length).toBe(0)
          spyOn(bufferView, 'moveToLine').andCallThrough()
          atom.commands.dispatch(bufferView.element, 'pane:split-left')
        })

        waitsFor(() => bufferView.moveToLine.callCount > 0)

        runs(() => {
          expect(atom.workspace.getActiveTextEditor()).not.toBe(editor1)
          expect(atom.workspace.getActiveTextEditor().getPath()).toBe(editor1.getPath())
          expect(atom.workspace.getActiveTextEditor().getCursorBufferPosition()).toEqual([3, 4])
        })
      })
    })
  })

  describe('preserve last search', () => {
    it('does not preserve last search by default', () => {
      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
        bufferView.selectListView.refs.queryEditor.insertText('this should not show up next time we open finder')
      })

      waitsForPromise(() => projectView.toggle())

      runs(() => expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(false))

      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
        expect(projectView.selectListView.getQuery()).toBe('')
      })
    })

    it('preserves last search when the config is set', () => {
      atom.config.set('fuzzy-finder.preserveLastSearch', true)

      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
        projectView.selectListView.refs.queryEditor.insertText('this should show up next time we open finder')
      })

      waitsForPromise(() => projectView.toggle())

      runs(() => expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(false))

      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
        expect(projectView.selectListView.getQuery()).toBe('this should show up next time we open finder')
        expect(projectView.selectListView.refs.queryEditor.getSelectedText()).toBe('this should show up next time we open finder')
      })
    })
  })

  describe('prefill query from selection', () => {
    it('should not be enabled by default', () => {
      waitsForPromise(() => atom.workspace.open())

      runs(() => {
        atom.workspace.getActiveTextEditor().setText('sample.txt')
        atom.workspace.getActiveTextEditor().setSelectedBufferRange([[0, 0], [0, 10]])
        expect(atom.workspace.getActiveTextEditor().getSelectedText()).toBe('sample.txt')
      })

      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
        expect(projectView.selectListView.getQuery()).toBe('')
        expect(projectView.selectListView.refs.queryEditor.getSelectedText()).toBe('')
      })
    })

    it('takes selection from active editor and prefills query with it', () => {
      atom.config.set('fuzzy-finder.prefillFromSelection', true)

      waitsForPromise(() => atom.workspace.open())

      runs(() => {
        atom.workspace.getActiveTextEditor().setText('sample.txt')
        atom.workspace.getActiveTextEditor().setSelectedBufferRange([[0, 0], [0, 10]])
        expect(atom.workspace.getActiveTextEditor().getSelectedText()).toBe('sample.txt')
      })

      waitsForPromise(() => projectView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(projectView).isVisible()).toBe(true)
        expect(projectView.selectListView.getQuery()).toBe('sample.txt')
        expect(projectView.selectListView.refs.queryEditor.getSelectedText()).toBe('sample.txt')
      })
    })
  })

  describe('file icons', () => {
    const fileIcons = new DefaultFileIcons()

    it('defaults to text', () => {
      waitsForPromise(() => atom.workspace.open('sample.js'))

      waitsForPromise(() => bufferView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
        bufferView.selectListView.refs.queryEditor.insertText('js')
      })

      waitsForPromise(() => getOrScheduleUpdatePromise())

      runs(() => {
        const firstResult = bufferView.element.querySelector('li .primary-line')
        expect(fileIcons.iconClassForPath(firstResult.dataset.path)).toBe('icon-file-text')
      })
    })

    it('shows image icons', () => {
      waitsForPromise(() => atom.workspace.open('sample.gif'))

      waitsForPromise(() => bufferView.toggle())

      runs(() => {
        expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe(true)
        bufferView.selectListView.refs.queryEditor.insertText('gif')
      })

      waitsForPromise(() => getOrScheduleUpdatePromise())

      runs(() => {
        const firstResult = bufferView.element.querySelector('li .primary-line')
        expect(fileIcons.iconClassForPath(firstResult.dataset.path)).toBe('icon-file-media')
      })
    })
  })

  describe('Git integration', () => {
    let projectPath, gitRepository, gitDirectory

    beforeEach(() => {
      projectPath = atom.project.getDirectories()[0].resolve('git/working-dir')
      fs.moveSync(path.join(projectPath, 'git.git'), path.join(projectPath, '.git'))
      atom.project.setPaths([rootDir2, projectPath])

      gitDirectory = atom.project.getDirectories()[1]
      gitRepository = atom.project.getRepositories()[1]
    })

    describe('git-status-finder behavior', () => {
      let originalPath, newPath

      beforeEach(() => {
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise(() => atom.workspace.open(path.join(projectPath, 'a.txt')))

        runs(() => {
          const editor = atom.workspace.getActiveTextEditor()
          originalPath = editor.getPath()
          fs.writeFileSync(originalPath, 'making a change for the better')
          gitRepository.getPathStatus(originalPath)

          newPath = atom.project.getDirectories()[1].resolve('newsample.js')
          fs.writeFileSync(newPath, '')
          gitRepository.getPathStatus(newPath)
        })
      })

      it('displays all new and modified paths', () => {
        expect(atom.workspace.panelForItem(gitStatusView)).toBeNull()
        waitsForPromise(() => gitStatusView.toggle())

        runs(() => {
          expect(atom.workspace.panelForItem(gitStatusView).isVisible()).toBe(true)
          expect(gitStatusView.element.querySelectorAll('.file').length).toBe(2)
          expect(gitStatusView.element.querySelectorAll('.status.status-modified').length).toBe(1)
          expect(gitStatusView.element.querySelectorAll('.status.status-added').length).toBe(1)
        })
      })
    })

    describe('status decorations', () => {
      let originalPath, editor, newPath

      beforeEach(() => {
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise(() => atom.workspace.open(path.join(projectPath, 'a.txt')))

        runs(() => {
          editor = atom.workspace.getActiveTextEditor()
          originalPath = editor.getPath()
          newPath = gitDirectory.resolve('newsample.js')
          fs.writeFileSync(newPath, '')
          fs.writeFileSync(originalPath, 'a change')
        })
      })

      describe('when a modified file is shown in the list', () =>
        it('displays the modified icon', () => {
          gitRepository.getPathStatus(editor.getPath())

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(bufferView.element.querySelectorAll('.status.status-modified').length).toBe(1)
            expect(bufferView.element.querySelector('.status.status-modified').closest('li').querySelector('.file').textContent).toBe('a.txt')
          })
        })
      )

      describe('when a new file is shown in the list', () =>
        it('displays the new icon', () => {
          waitsForPromise(() => atom.workspace.open(path.join(projectPath, 'newsample.js')))

          runs(() => gitRepository.getPathStatus(editor.getPath()))

          waitsForPromise(() => bufferView.toggle())

          runs(() => {
            expect(bufferView.element.querySelectorAll('.status.status-added').length).toBe(1)
            expect(bufferView.element.querySelector('.status.status-added').closest('li').querySelector('.file').textContent).toBe('newsample.js')
          })
        })
      )
    })

    describe('when core.excludeVcsIgnoredPaths is set to true', () => {
      beforeEach(() => atom.config.set('core.excludeVcsIgnoredPaths', true))

      describe("when the project's path is the repository's working directory", () => {
        beforeEach(() => {
          const ignoreFile = path.join(projectPath, '.gitignore')
          fs.writeFileSync(ignoreFile, 'ignored.txt')

          const ignoredFile = path.join(projectPath, 'ignored.txt')
          fs.writeFileSync(ignoredFile, 'ignored text')
        })

        it('excludes paths that are git ignored', () => {
          waitsForPromise(() => projectView.toggle())

          runs(() => waitForPathsToDisplay(projectView))

          runs(() => expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('ignored.txt'))).not.toBeDefined())
        })
      })

      describe("when the project's path is a subfolder of the repository's working directory", () => {
        beforeEach(() => {
          atom.project.setPaths([gitDirectory.resolve('dir')])
          const ignoreFile = path.join(projectPath, '.gitignore')
          fs.writeFileSync(ignoreFile, 'b.txt')
        })

        it('does not exclude paths that are git ignored', () => {
          waitsForPromise(() => projectView.toggle())

          runs(() => waitForPathsToDisplay(projectView))

          runs(() => expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('b.txt'))).toBeDefined())
        })
      })

      describe('when the .gitignore matches parts of the path to the root folder', () => {
        beforeEach(() => {
          const ignoreFile = path.join(projectPath, '.gitignore')
          fs.writeFileSync(ignoreFile, path.basename(projectPath))
        })

        it('only applies the .gitignore patterns to relative paths within the root folder', () => {
          waitsForPromise(() => projectView.toggle())

          runs(() => waitForPathsToDisplay(projectView))

          runs(() => expect(Array.from(projectView.element.querySelectorAll('li')).find(a => a.textContent.includes('file.txt'))).toBeDefined())
        })
      })
    })
  })
})
