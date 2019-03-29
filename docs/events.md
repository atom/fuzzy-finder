# Events specification

This document specifies all the data (along with the format) which gets sent from the Fuzzy Finder package to the GitHub analytics pipeline. This document follows the same format and nomenclature as the [Atom Core Events spec](https://github.com/atom/metrics/blob/master/docs/events.md).

## Counters

Currently the Fuzzy finder does not log any counter events.

## Timing events

#### Time to crawl the project

* **eventType**: `fuzzy-finder-v1`
* **metadata**

  | field | value |
  |-------|-------|
  | `ec` | `time-to-crawl`
  | `el` | Crawler type (`ripgrep` or `fs`)
  | `ev` | Number of crawled files

#### Time to filter results

* **eventType**: `fuzzy-finder-v1`
* **metadata**

  | field | value |
  |-------|-------|
  | `ec` | `time-to-filter`
  | `el` | Scoring system (`alternate` or `fast`)
  | `ev` | Number of items in the list

## Standard events

Currently the Fuzzy Finder does not log any standard events.
