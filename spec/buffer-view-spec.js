const {it, fit, ffit, fffit, beforeEach, afterEach} = require('./async-spec-helpers')
const path = require('path')
const temp = require('temp').track()
const BufferView = require('../lib/buffer-view')

describe('BufferView', () => {
  it('includes remote editors when teletype is enabled', async () => {
    const bufferView = new BufferView()

    const localEditor1 = await atom.workspace.open(path.join(temp.path(), 'a'))
    const localEditor2 = await atom.workspace.open(path.join(temp.path(), 'b'))
    const remoteEditor1 = await atom.workspace.open(path.join(temp.path(), 'c'))
    remoteEditor1.getURI = () => 'remote1-uri'
    const fakeTeletypeService = {
      async getRemoteEditors () {
        return [
          {uri: 'remote1-uri', path: 'remote1-path', label: 'remote1-label'},
          {uri: 'remote2-uri', path: 'remote2-path', label: 'remote2-label'}
        ]
      }
    }
    bufferView.setTeletypeService(fakeTeletypeService)
    await bufferView.toggle()

    expect(bufferView.items).toEqual([
      {uri: 'remote2-uri', filePath: 'remote2-path', label: 'remote2-label'},
      {uri: localEditor1.getURI(), filePath: localEditor1.getPath(), label: localEditor1.getPath()},
      {uri: localEditor2.getURI(), filePath: localEditor2.getPath(), label: localEditor2.getPath()},
      {uri: 'remote1-uri', filePath: 'remote1-path', label: 'remote1-label'}
    ])
  })

  it('excludes remote editors when teletype is disabled', async () => {
    const bufferView = new BufferView()

    const editor1 = await atom.workspace.open(path.join(temp.path(), 'a'))
    const editor2 = await atom.workspace.open(path.join(temp.path(), 'b'))
    await bufferView.toggle()

    expect(bufferView.items).toEqual([
      {uri: editor1.getURI(), filePath: editor1.getPath(), label: editor1.getPath()},
      {uri: editor2.getURI(), filePath: editor2.getPath(), label: editor2.getPath()}
    ])
  })
})
