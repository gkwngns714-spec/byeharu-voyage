import { defineDict } from '../define'

// YOU (src/features/you): the three levels, every hull you own, and your captains. The level words
// came from the Profile dictionary with the section itself (owner row 181, 2026-10-20) — one screen
// prints a ladder, so one dictionary holds its words.
export const youDict = defineDict({
  en: {
    noCompany: 'No company yet.',
    levels: 'Levels',
    trading: 'Trading',
    exploration: 'Exploration',
    combat: 'Combat',
    noFighting: 'no fighting yet',
    levelOf: '{name} level',
    ships: 'Ships',
    // The plural follows the FLEETS (`count`): "1 in 1 fleet", "8 in 8 fleets" — it read "1 in 1 fleets".
    shipsCount: { one: '{ships} in {fleets} fleet', other: '{ships} in {fleets} fleets' },
    noShips: 'No ships yet.',
    flagship: 'flagship',
  },
  ko: {
    noCompany: '아직 회사 없음.',
    levels: '레벨',
    trading: '교역',
    exploration: '탐험',
    combat: '전투',
    noFighting: '아직 전투 없음',
    levelOf: '{name} 레벨',
    ships: '배',
    shipsCount: { one: '선단 {fleets}개 · {ships}척', other: '선단 {fleets}개 · {ships}척' },
    noShips: '아직 선박이 없습니다.',
    flagship: '기함',
  },
})
