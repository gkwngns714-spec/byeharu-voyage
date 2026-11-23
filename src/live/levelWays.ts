import type { IconName } from '../components/ui'
import type { LevelSkill } from '../lib/rpc'
import { translate, type Locale } from '../lib/i18n'
import { navWord } from '../app/navTabs'
import { openOfficeCity, OFFICE_TAB } from '../features/command/officeView'
import { PRODUCTION_PLACE, yardHref } from './cityFaces'
import type { GatedPlace } from './levelGate'

// "FASTEST WAY" (roadmap 2026-11-23, slice 10; RS3's skill guide, Melvor's "go to"): one press from a level's tile to the act that
// raises it. ONE TABLE: an activity code (as `public.level_activity_terms` serves it) to the place where that act is done. The
// figures stay the server's; this file says only WHERE. An activity with no row here has no press (a fight's result, a storm).
//
// WHICH ACT (decided by default, the owner may reverse it): the first of the level's served activities that has a place, in the
// served order. The units differ (per ducat, per mile, each, a day), so the client does not rank them: it never compares figures.
// A place the one level gate holds (live/levelGate.ts: the Workstation, Invest under Trading 5) offers no press while it is held.

export interface LevelWay {
  /** The activity it presses toward. */
  activity: string
  /** The route the press opens. */
  to: string
  icon: IconName
  /** The place's own word (the tab's, or the building's). */
  word: (locale: Locale) => string
  /** Turns the Office to the right building first (a City-face building). */
  prepare?: () => void
  /** A place the level gate may hold. */
  gated?: GatedPlace
}

type Way = Omit<LevelWay, 'activity'>

const TRADE: Way = { to: '/command', icon: 'scales', word: (l) => navWord(l, 'Trade') }
const SAIL: Way = { to: '/map', icon: 'chart', word: (l) => navWord(l, 'Map') }
const LAND: Way = { to: '/land', icon: 'mountain', word: (l) => navWord(l, 'Land') }
const YARD: Way = { to: yardHref(null), icon: 'mallet', word: (l) => translate(l, 'town.f_building_yard') }
const INVEST: Way = { to: '/office?face=invest', icon: 'invest', word: (l) => translate(l, 'command.f_invest'), gated: 'invest' }
const CRAFT: Way = {
  to: OFFICE_TAB,
  icon: 'crate',
  word: (l) => translate(l, 'town.f_workstation'),
  prepare: () => void openOfficeCity('workstation'),
  gated: 'workstation',
}
const PRODUCE: Way = { to: `/city?place=${PRODUCTION_PLACE}`, icon: 'hold', word: (l) => translate(l, 'city.production') }

/** THE TABLE: an activity, the place it is done. */
const WAYS: Record<string, Way> = {
  trade: TRADE,
  request: TRADE,
  lap: TRADE,
  port: SAIL,
  miles: SAIL,
  fed: SAIL,
  rough: SAIL,
  hull: YARD,
  repair: YARD,
  give: INVEST,
  share: INVEST,
  made: CRAFT,
  forged: PRODUCE,
  dig: LAND,
  smith: LAND,
}

/** The one press for a level: its first served activity with a place that is open to her now; null when none is. */
export function fastestWay(skill: Pick<LevelSkill, 'activities' | 'counted'>, shut: (place: string) => boolean): LevelWay | null {
  if (!skill.counted) return null
  for (const a of skill.activities) {
    const w = WAYS[a.code]
    if (w && !(w.gated && shut(w.gated))) return { activity: a.code, ...w }
  }
  return null
}

/** THE ACADEMY (X6): where the captain studies are trained. The Office's City face at its Academy. */
export function openAcademy(): string {
  return openOfficeCity('academy')
}
