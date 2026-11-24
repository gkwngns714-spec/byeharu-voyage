import { defineDict } from '../define'

// YOU (src/features/you): the three levels, your captains (the ships are the Fleets tab's: one list). The level words
// came from the Profile dictionary with the section itself (owner row 181, 2026-10-20) — one screen
// prints a ladder, so one dictionary holds its words.
export const youDict = defineDict({
  en: {
    noCompany: 'No company yet.',
    levels: 'Levels',
    // slice 10: a level tile's one press to the act that raises it (its accessible name; the tile shows the place's mark and word)
    fastest: 'Fastest way',
    levelOf: '{name} level',
    // F5: the room the company has (world.house_room), one line, a link to Fleets
    // 2026-11-22 second play-test: "Ships 1 / 4" here beside Fleets' "Ships each 1 / 2" read as two counts of one thing; this is every fleet's room together
    room: 'Fleets {a} / {b} · All ships {c} / {d}',
  },
  ko: {
    noCompany: '아직 회사 없음.',
    levels: '레벨',
    fastest: '지름길',
    levelOf: '{name} 레벨',
    room: '선단 {a} / {b} · 전체 배 {c} / {d}',
  },
})
