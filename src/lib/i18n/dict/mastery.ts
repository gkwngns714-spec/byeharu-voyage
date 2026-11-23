import { defineDict } from '../define'

// GOODS MASTERY (0479, roadmap 2026-11-23 slice 11): a good's level as a ring (the logbook's Goods page, You's plate), its name in gold
// at the top, and a chip or toast when a sale raises it. Few words: the ring and the figure say the rest.
export const masteryDict = defineDict({
  en: {
    specialty: 'Specialty',
    ring: '{good} mastery {n} of {top}',
    up: 'Mastery {n}',
    toast: '{good} · Mastery {n}',
  },
  ko: {
    specialty: '특기',
    ring: '{good} 숙련 {top} 중 {n}',
    up: '숙련 {n}',
    toast: '{good} · 숙련 {n}',
  },
})
