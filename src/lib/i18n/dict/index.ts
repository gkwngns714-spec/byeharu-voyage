// THE REGISTRY: every dictionary, under the section name its keys start with (`auth.title`).
// One file per screen or domain, so two changes never fight over one file.
import { commonDict } from './common'

export const DICT = {
  common: commonDict,
} as const
