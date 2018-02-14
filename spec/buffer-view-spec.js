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
          {uri: 'remote1-uri', path: 'remote1-path', hostGitHubUsername: 'user-1'},
          {uri: 'remote2-uri', path: 'remote2-path', hostGitHubUsername: 'user-2'}
        ]
      }
    }
    bufferView.setTeletypeService(fakeTeletypeService)
    await bufferView.toggle()

    expect(bufferView.items).toEqual([
      {uri: 'remote2-uri', filePath: 'remote2-path', label: '@user-2: remote2-path', ownerGitHubUsername: 'user-2'},
      {uri: localEditor1.getURI(), filePath: localEditor1.getPath(), label: localEditor1.getPath()},
      {uri: localEditor2.getURI(), filePath: localEditor2.getPath(), label: localEditor2.getPath()},
      {uri: 'remote1-uri', filePath: 'remote1-path', label: '@user-1: remote1-path', ownerGitHubUsername: 'user-1'}
    ])
  })
})
