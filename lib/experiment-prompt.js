const etch = require('etch')
const $ = etch.dom
const SCORING_SYSTEMS = require('./scoring-systems')

/**
 * For how long to show the "NEW" badge in the prompt since the first time
 * it was seen (24h).
 */
const TimeToShowNewBadgeInMilliseconds = 24 * 60 * 60 * 1000
const FirstTimeShownKey = 'fuzzy-finder:prompt-first-time-shown'

function shouldShowPrompt (numItems) {
  return false
}

function shouldShowBadge () {
  const firstTimeShown = localStorage.getItem(FirstTimeShownKey)
  const now = new Date().getTime()

  if (!firstTimeShown) {
    localStorage.setItem(FirstTimeShownKey, now)

    return true
  }

  return now - firstTimeShown <= TimeToShowNewBadgeInMilliseconds
}

function showNotification (message, {description, confirmBtn, cancelBtn, confirmFn, cancelFn}) {
  const notification = atom.notifications.addInfo(
    message,
    {
      description,
      dismissable: true,
      buttons: [
        {
          text: confirmBtn,
          onDidClick: () => {
            confirmFn && confirmFn()
            notification.dismiss()
          },
          className: 'btn btn-info btn-primary'
        },
        {
          text: cancelBtn,
          onDidClick: () => {
            cancelFn && cancelFn()
            notification.dismiss()
          }
        }
      ],
      icon: 'rocket'
    }
  )
}

function enableExperimentalFuzzyFinder (metricsReporter) {
  metricsReporter.incrementCounter('click-enable-prompt')

  showNotification(
    'Introducing experimental fast mode',
    {
      description: "The fuzzy finder has a new experimental _fast mode_. It dramatically speeds up the experience of finding files, especially in large projects. Would you like to try it?\n\n(You can always switch back to the fuzzy finder's _normal mode_ later.)",
      confirmBtn: 'Enable fast mode',
      confirmFn: () => {
        metricsReporter.incrementCounter('confirm-enable-prompt')

        atom.config.set('fuzzy-finder.useRipGrep', true)
        atom.config.set('fuzzy-finder.scoringSystem', SCORING_SYSTEMS.FAST)
        atom.notifications.addSuccess('Fasten your seatbelt! Here comes a faster fuzzy finder.', {icon: 'rocket'})
      },
      cancelBtn: 'Not right now',
      cancelFn: () => {
        metricsReporter.incrementCounter('cancel-enable-prompt')
      }
    }
  )
}

function disableExperimentalFuzzyFinder (metricsReporter) {
  metricsReporter.incrementCounter('click-disable-prompt')

  showNotification(
    'Do you want to disable the new experimental fast mode for the fuzzy finder?',
    {
      description: 'If the experimental fast mode is negatively impacting your experience, please leave a comment to [**let us know**](https://github.com/atom/fuzzy-finder/issues/379).\n\n(You can reenable fast mode later from the fuzzy finder.)',
      confirmBtn: 'Disable experimental fast mode',
      confirmFn: () => {
        metricsReporter.incrementCounter('confirm-disable-prompt')

        atom.config.set('fuzzy-finder.useRipGrep', false)
        atom.config.set('fuzzy-finder.scoringSystem', SCORING_SYSTEMS.ALTERNATE)
        atom.notifications.addSuccess('OK. Experimental fast mode is disabled.')
      },
      cancelBtn: 'No, thanks',
      cancelFn: () => {
        metricsReporter.incrementCounter('cancel-disable-prompt')
      }
    }
  )
}

function isFastModeEnabled () {
  return (
    atom.config.get('fuzzy-finder.scoringSystem') === SCORING_SYSTEMS.FAST &&
    atom.config.get('fuzzy-finder.useRipGrep') === true
  )
}

function renderExperimentPrompt (metricsReporter) {
  if (isFastModeEnabled()) {
    metricsReporter.incrementCounter('show-disable-prompt')

    return (
      $.span({className: 'experiment-prompt'}, [
        $.a({onmousedown: disableExperimentalFuzzyFinder.bind(null, metricsReporter)}, [
          $.span({className: 'icon icon-rocket'}, ''),
          $.span({className: ''}, 'Using experimental fast mode. Opt out?')
        ])
      ])
    )
  }

  metricsReporter.incrementCounter('show-enable-prompt')

  return (
    $.span({className: 'experiment-prompt'}, [
      $.a({onmousedown: enableExperimentalFuzzyFinder.bind(null, metricsReporter)}, [
        shouldShowBadge() ? $.span({className: 'badge badge-info'}, 'NEW') : null,
        $.span({className: 'icon icon-beaker'}, ''),
        $.span({className: ''}, 'Try experimental fast mode?')
      ])
    ])
  )
}

module.exports = {
  renderExperimentPrompt,
  shouldShowPrompt
}
