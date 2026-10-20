// THE REGISTRY: every dictionary, under the section name its keys start with (`auth.title`).
// One file per screen or domain, so two changes never fight over one file.
import { codesDict } from './codes'
import { commonDict } from './common'
import { fleetsDict } from './fleets'
import { formatDict } from './format'
import { foundDict } from './found'
import { mapDict } from './map'
import { profileDict } from './profile'
import { rankDict } from './rank'
import { routesDict } from './routes'
import { shellDict } from './shell'
import { uiDict } from './ui'

export const DICT = {
  codes: codesDict,
  common: commonDict,
  fleets: fleetsDict,
  format: formatDict,
  found: foundDict,
  map: mapDict,
  profile: profileDict,
  rank: rankDict,
  routes: routesDict,
  shell: shellDict,
  ui: uiDict,
} as const
