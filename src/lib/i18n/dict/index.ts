// THE REGISTRY: every dictionary, under the section name its keys start with (`auth.title`).
// One file per screen or domain, so two changes never fight over one file.
import { booksDict } from './books'
import { chartDict } from './chart'
import { codesDict } from './codes'
import { codexDict } from './codex'
import { commandDict } from './command'
import { commonDict } from './common'
import { deskDict } from './desk'
import { domainDict } from './domain'
import { fleetsDict } from './fleets'
import { formatDict } from './format'
import { foundDict } from './found'
import { historyDict } from './history'
import { innDict } from './inn'
import { mapDict } from './map'
import { marketsDict } from './markets'
import { portDict } from './port'
import { profileDict } from './profile'
import { rankDict } from './rank'
import { routesDict } from './routes'
import { shellDict } from './shell'
import { shipDict } from './ship'
import { townDict } from './town'
import { tradeDict } from './trade'
import { uiDict } from './ui'
import { yardDict } from './yard'
import { youDict } from './you'

export const DICT = {
  books: booksDict,
  chart: chartDict,
  codes: codesDict,
  codex: codexDict,
  command: commandDict,
  common: commonDict,
  desk: deskDict,
  domain: domainDict,
  fleets: fleetsDict,
  format: formatDict,
  found: foundDict,
  history: historyDict,
  inn: innDict,
  map: mapDict,
  markets: marketsDict,
  port: portDict,
  profile: profileDict,
  rank: rankDict,
  routes: routesDict,
  shell: shellDict,
  ship: shipDict,
  town: townDict,
  trade: tradeDict,
  ui: uiDict,
  yard: yardDict,
  you: youDict,
} as const
