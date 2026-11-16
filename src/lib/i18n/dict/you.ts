import { defineDict } from '../define'

// YOU (src/features/you): the three levels, every hull you own, and your captains. The level words
// came from the Profile dictionary with the section itself (owner row 181, 2026-10-20) — one screen
// prints a ladder, so one dictionary holds its words.
export const youDict = defineDict({
  en: {
    noCompany: 'No company yet.',
    levels: 'Levels',
    levelOf: '{name} level',
    ships: 'Ships',
    noShips: 'No ships yet.',
    flagship: 'flagship',
    // F5: the room the company has (world.house_room), one line, a link to Fleets
    room: 'Fleets {a} / {b} · Ships {c} / {d}',
  },
  ko: {
    noCompany: '아직 회사 없음.',
    levels: '레벨',
    levelOf: '{name} 레벨',
    ships: '배',
    noShips: '아직 배 없음.',
    flagship: '기함',
    room: '선단 {a} / {b} · 배 {c} / {d}',
  },
})
