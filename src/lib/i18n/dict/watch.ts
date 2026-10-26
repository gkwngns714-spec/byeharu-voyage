import { defineDict } from '../define'

// THE ECONOMY WATCH (0229, docs/CLOSED_ECONOMY.md §7): the figures the closed economy is watched by, on the
// Stats Overview. Their own file so the Stats words and these never fight over one file. Short labels.
export const watchDict = defineDict({
  en: {
    heading: 'Economy watch',
    newMoney: 'New money',
    totalDay: 'Total, 24 h',
    underReserve: 'Under reserve',
    underThin: 'Under {n}',
    broke: 'Broke',
    gifts: 'Gifts, 24 h',
    swing: 'Price swing',
  },
  ko: {
    heading: '경제 감시',
    newMoney: '신규 화폐',
    totalDay: '총액, 24시간',
    underReserve: '준비금 미달',
    underThin: '{n} 미만',
    broke: '파산',
    gifts: '지원, 24시간',
    swing: '가격 변동',
  },
})
