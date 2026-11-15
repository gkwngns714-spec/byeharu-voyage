import { defineDict } from '../define'

// JOINING A BATTLE (docs/design/tick-combat.md section 8, slice 0436): the map's Join bar (src/live/battle/JoinBar.tsx).
// Joining is a CHOICE: a ship in the red circle is never pulled in. These are the bar's own words and one short word for
// every refusal `cmd.battle_join` can answer (contract 9.2). Each is one or two words.
export const joinDict = defineDict({
  en: {
    title: 'Join',
    join: 'Join',
    joined: 'Joined',
    side: 'Side',
    watch: 'Watch',
    E_NO_BATTLE: 'No battle',
    E_BATTLE_OVER: 'Battle over',
    E_NOT_YOUR_FLEET: 'Not yours',
    E_NOT_IN_REACH: 'Too far',
    E_BAD_SIDE: 'Wrong side',
    E_HUMAN_TARGET: 'No PvP',
    E_FLEET_BUSY: 'Fleet busy',
    E_AT_PEACE: 'At peace',
    E_OTHER: 'Refused',
  },
  ko: {
    title: '참전',
    join: '참전',
    joined: '참전함',
    side: '편',
    watch: '관전',
    E_NO_BATTLE: '해전 없음',
    E_BATTLE_OVER: '해전 종료',
    E_NOT_YOUR_FLEET: '남의 선단',
    E_NOT_IN_REACH: '너무 멂',
    E_BAD_SIDE: '잘못된 편',
    E_HUMAN_TARGET: 'PvP 불가',
    E_FLEET_BUSY: '선단 바쁨',
    E_AT_PEACE: '휴전 중',
    E_OTHER: '거절됨',
  },
})
