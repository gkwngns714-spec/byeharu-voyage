import { defineDict } from '../define'

// Sign the book (src/features/found): a new player names a company and picks a country.
export const foundDict = defineDict({
  en: {
    title: 'Start',
    more: 'One ship, Gaivota, and 8,000 ducats at {capital}.',
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
  },
  ko: {
    title: '시작',
    more: '배 한 척 가이보타와 8,000두캇, {capital}에서.',
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
  },
})
