/* global emit */

const async = require('async')
const fs = require('fs')
const path = require('path')
const {GitRepository} = require('atom')
const {Minimatch} = require('minimatch')

const childProcess = require('child_process')

const PathsChunkSize = 100

const emittedPaths = new Set()

class PathLoader {
  constructor (rootPath, ignoreVcsIgnores, traverseSymlinkDirectories, ignoredNames) {
    this.rootPath = rootPath
    this.traverseSymlinkDirectories = traverseSymlinkDirectories
    this.ignoredNames = ignoredNames
    this.paths = []
    this.inodes = new Set()
    this.repo = null
    if (ignoreVcsIgnores) {
      const repo = GitRepository.open(this.rootPath, {refreshOnWindowFocus: false})
      if ((repo && repo.relativize(path.join(this.rootPath, 'test'))) === 'test') {
        this.repo = repo
      }
    }
  }

  load (done) {
    if (this.repo && !this.traverseSymlinkDirectories) {
      this.loadFromGit().then(done)

      return
    }

    this.loadPath(this.rootPath, true, () => {
      this.flushPaths()
      if (this.repo != null) this.repo.destroy()
      done()
    })
  }

  async loadFromGit () {
    return new Promise((resolve) => {
      const args = ['ls-files', '--cached', '--exclude-standard', '--others', '-z']

      for (let ignoredName of this.ignoredNames) {
        args.push('--exclude', ignoredName.pattern)
      }

      let output = ''

      // TODO: do this via a call to GitRepository (needs to be implemented).
      const result = childProcess.spawn('git', args, {cwd: this.rootPath})
      result.stdout.on('data', chunk => {
        const files = (output + chunk).split('\0')
        output = files.pop()

        for (const file of files) {
          this.pathLoaded(file)
        }
      })
      result.on('close', () => {
        this.flushPaths()
        resolve()
      })
    })
  }

  isIgnored (loadedPath) {
    const relativePath = path.relative(this.rootPath, loadedPath)
    if (this.repo && this.repo.isPathIgnored(relativePath)) {
      return true
    } else {
      for (let ignoredName of this.ignoredNames) {
        if (ignoredName.match(relativePath)) return true
      }
    }
  }

  pathLoaded (loadedPath, done) {
    if (!emittedPaths.has(loadedPath)) {
      this.paths.push(loadedPath)
      emittedPaths.add(loadedPath)
    }

    if (this.paths.length === PathsChunkSize) {
      this.flushPaths()
    }

    done && done()
  }

  flushPaths () {
    emit('load-paths:paths-found', this.paths)
    this.paths = []
  }

  loadPath (pathToLoad, root, done) {
    if (this.isIgnored(pathToLoad) && !root) return done()

    fs.lstat(pathToLoad, (error, stats) => {
      if (error != null) { return done() }
      if (stats.isSymbolicLink()) {
        fs.stat(pathToLoad, (error, stats) => {
          if (error != null) return done()
          if (this.inodes.has(stats.ino)) {
            return done()
          } else {
            this.inodes.add(stats.ino)
          }

          if (stats.isFile()) {
            this.pathLoaded(pathToLoad, done)
          } else if (stats.isDirectory()) {
            if (this.traverseSymlinkDirectories) {
              this.loadFolder(pathToLoad, done)
            } else {
              done()
            }
          } else {
            done()
          }
        })
      } else {
        this.inodes.add(stats.ino)
        if (stats.isDirectory()) {
          this.loadFolder(pathToLoad, done)
        } else if (stats.isFile()) {
          this.pathLoaded(pathToLoad, done)
        } else {
          done()
        }
      }
    })
  }

  loadFolder (folderPath, done) {
    fs.readdir(folderPath, (_, children = []) => {
      async.each(
        children,
        (childName, next) => {
          this.loadPath(path.join(folderPath, childName), false, next)
        },
        done
      )
    })
  }
}

module.exports = function (rootPaths, followSymlinks, ignoreVcsIgnores, ignores = []) {
  const ignoredNames = []
  for (let ignore of ignores) {
    if (ignore) {
      try {
        ignoredNames.push(new Minimatch(ignore, {matchBase: true, dot: true}))
      } catch (error) {
        console.warn(`Error parsing ignore pattern (${ignore}): ${error.message}`)
      }
    }
  }

  async.each(
    rootPaths,
    (rootPath, next) =>
      new PathLoader(
        rootPath,
        ignoreVcsIgnores,
        followSymlinks,
        ignoredNames
      ).load(next)
    ,
    this.async()
  )
}
