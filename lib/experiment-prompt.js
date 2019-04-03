const etch = require('etch')
const $ = etch.dom
const SCORING_SYSTEMS = require('./scoring-systems')

function enableExperimentalFuzzyFinder () {
  const notification = atom.notifications.addInfo(
    'The project you\'ve opened is quite large, which may cause performance issues on the quick open menu. Do you want to enable the new experimental fast mode for the quick open menu?',
    {
      detail: 'This mode can be disabled from the fuzzy finder settings later',
      dismissable: true,
      buttons: [
        {
          text: 'Enable experimental fast mode',
          onDidClick: () => {
            atom.config.set('fuzzy-finder.scoringSystem', SCORING_SYSTEMS.FAST)
            atom.config.set('fuzzy-finder.useRipGrep', true)

            notification.dismiss()
          },
          className: 'btn btn-info btn-primary'
        },
        {
          text: 'No',
          onDidClick: () => {
            notification.dismiss()
          }
        }
      ],
      icon: 'rocket'
    }
  )
}

function renderExperimentPrompt () {
  return (
    $.span({className: 'experiment-prompt'}, [
      $.a({onmousedown: enableExperimentalFuzzyFinder}, [
        $.span({className: 'badge badge-info'}, 'NEW'),
        $.span({className: ''}, 'Try experimental fast mode?'),
        $.span({className: 'icon icon-microscope'}, '')
      ])
    ])
  )
}

module.exports = {
  renderExperimentPrompt
}
