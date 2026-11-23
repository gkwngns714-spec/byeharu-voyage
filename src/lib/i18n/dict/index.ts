// THE REGISTRY: every dictionary, under the section name its keys start with (`auth.title`).
// One file per screen or domain, so two changes never fight over one file.
import { battleDict } from './battle'
import { booksDict } from './books'
import { bountyDict } from './bounty'
import { chartDict } from './chart'
import { cityDict } from './city'
import { codesDict } from './codes'
import { codexDict } from './codex'
import { commandDict } from './command'
import { commonDict } from './common'
import { deskDict } from './desk'
import { domainDict } from './domain'
import { eventsDict } from './events'
import { feedDict } from './feed'
import { fightDict } from './fight'
import { fleetsDict } from './fleets'
import { formatDict } from './format'
import { foundDict } from './found'
import { historyDict } from './history'
import { hqDict } from './hq'
import { innDict } from './inn'
import { joinDict } from './join'
import { landDict } from './land'
import { logbookDict } from './logbook'
import { masteryDict } from './mastery'
import { mapDict } from './map'
import { marketsDict } from './markets'
import { newsDict } from './news'
import { portDict } from './port'
import { profileDict } from './profile'
import { rankDict } from './rank'
import { routesDict } from './routes'
import { seasDict } from './seas'
import { shellDict } from './shell'
import { shipDict } from './ship'
import { statsDict } from './stats'
import { townDict } from './town'
import { tradeDict } from './trade'
import { uiDict } from './ui'
import { watchDict } from './watch'
import { yardDict } from './yard'
import { youDict } from './you'

export const DICT = {
  battle: battleDict,
  books: booksDict,
  bounty: bountyDict,
  chart: chartDict,
  city: cityDict,
  codes: codesDict,
  codex: codexDict,
  command: commandDict,
  common: commonDict,
  desk: deskDict,
  domain: domainDict,
  events: eventsDict,
  feed: feedDict,
  fight: fightDict,
  fleets: fleetsDict,
  format: formatDict,
  found: foundDict,
  history: historyDict,
  hq: hqDict,
  inn: innDict,
  join: joinDict,
  land: landDict,
  logbook: logbookDict,
  mastery: masteryDict,
  map: mapDict,
  markets: marketsDict,
  news: newsDict,
  port: portDict,
  profile: profileDict,
  rank: rankDict,
  routes: routesDict,
  seas: seasDict,
  shell: shellDict,
  ship: shipDict,
  stats: statsDict,
  town: townDict,
  trade: tradeDict,
  ui: uiDict,
  watch: watchDict,
  yard: yardDict,
  you: youDict,
} as const
