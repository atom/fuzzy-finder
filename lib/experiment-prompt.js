const etch = require('etch')
const $ = etch.dom
const SCORING_SYSTEMS = require('./scoring-systems')

/**
 * For how long to show the "NEW" badge in the prompt since the first time
 * it was seen (24h).
 */
const TimeToShowNewBadge = 24 * 60 * 10 * 1000
const FirstTimeShownKey = 'fuzzy-finder:prompt-first-time-shown'

function shouldShowBadge () {
  const firstTimeShown = localStorage.getItem(FirstTimeShownKey)
  const now = new Date().getTime()

  if (!firstTimeShown) {
    localStorage.setItem(FirstTimeShownKey, now)

    return true
  }

  return now - firstTimeShown <= TimeToShowNewBadge
}

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
        shouldShowBadge() ? $.span({className: 'badge badge-info'}, 'NEW') : null,
        $.span({className: ''}, 'Try experimental fast mode?'),
        $.span({className: 'icon icon-microscope'}, '')
      ])
    ])
  )
}

module.exports = {
  renderExperimentPrompt
}
