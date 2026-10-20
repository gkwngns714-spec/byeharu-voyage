// THE REGISTRY: every dictionary, under the section name its keys start with (`auth.title`).
// One file per screen or domain, so two changes never fight over one file.
import { codesDict } from './codes'
import { codexDict } from './codex'
import { commonDict } from './common'
import { fleetsDict } from './fleets'
import { formatDict } from './format'
import { foundDict } from './found'
import { historyDict } from './history'
import { innDict } from './inn'
import { mapDict } from './map'
import { portDict } from './port'
import { profileDict } from './profile'
import { quayDict } from './quay'
import { rankDict } from './rank'
import { routesDict } from './routes'
import { shellDict } from './shell'
import { townDict } from './town'
import { uiDict } from './ui'

export const DICT = {
  codes: codesDict,
  codex: codexDict,
  common: commonDict,
  fleets: fleetsDict,
  format: formatDict,
  found: foundDict,
  history: historyDict,
  inn: innDict,
  map: mapDict,
  port: portDict,
  profile: profileDict,
  quay: quayDict,
  rank: rankDict,
  routes: routesDict,
  shell: shellDict,
  town: townDict,
  ui: uiDict,
} as const
