import { defineDict } from '../define'

// Sign the book (src/features/found): a new player names a company and picks a country.
export const foundDict = defineDict({
  en: {
    title: 'Start',
    more: 'One ship, Gaivota, and 40,000 ducats at {capital}.',
    yourCapital: 'your capital',
    moreTitle: 'How you begin',
    hint: 'Everyone begins the same way.',
    nameQ: 'Company name',
    nameRule: '3–24 letters, unique.',
    countryQ: 'Country',
    country: 'Country',
    try: 'Try',
    starting: 'Starting…',
    start: 'Start',
    // 0380: what the skull costs, said before she picks (the country picker, at Start and in Profile)
    skull: 'At war with every country: their ports tax you more and charge more to dock. Pirate ports are free. Their ports have no yard.',
  },
  ko: {
    title: '시작',
    more: '배 한 척 가이보타와 40,000두캇, {capital}에서.',
    yourCapital: '자국 수도',
    moreTitle: '시작',
    hint: '모두 같게 시작.',
    nameQ: '회사 이름',
    nameRule: '3~24자, 중복 불가.',
    countryQ: '나라',
    country: '나라',
    try: '해 볼 것',
    starting: '시작하는 중…',
    start: '시작',
    skull: '모든 나라와 전쟁 중: 다른 나라 항구는 세금과 입항료가 더 비쌈. 해적 항구는 무료. 해적 항구에는 조선소 없음.',
  },
})
