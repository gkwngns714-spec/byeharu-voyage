// THE REGISTRY: every dictionary, under the section name its keys start with (`auth.title`).
// One file per screen or domain, so two changes never fight over one file.
import { codesDict } from './codes'
import { commonDict } from './common'
import { formatDict } from './format'
import { shellDict } from './shell'
import { uiDict } from './ui'

export const DICT = {
  codes: codesDict,
  common: commonDict,
  format: formatDict,
  shell: shellDict,
  ui: uiDict,
} as const
