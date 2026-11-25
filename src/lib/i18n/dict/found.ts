import { defineDict } from '../define'

// Sign the book (src/features/found): a new player names a company and picks a country.
export const foundDict = defineDict({
  en: {
    title: 'Start',
    // 2026-11-15 owner: shorter words — what she gets, as figures; money is the coin, never "ducats" (docs/WORDS.md)
    more: '1 ship · 40,000 {coin} · {capital}',
    yourCapital: 'your capital',
    moreTitle: 'You get',
    nameQ: 'Company name',
    // 0503: the rule in one line (the server judges: public.company_name_refusal)
    nameRule: '3–24 letters or digits. No symbols. Not a country, city or trade good.',
    countryQ: 'Country',
    country: 'Country',
    try: 'Try',
    starting: 'Starting…',
    start: 'Start',
    // 0380: what the skull costs, said before she picks (the country picker, at Start and in Profile)
    skull: 'At war with all: higher tax and dock fees. Pirate ports: free, no yard.',
  },
  ko: {
    title: '시작',
    more: '배 1척 · 40,000 {coin} · {capital}',
    yourCapital: '자국 수도',
    moreTitle: '시작 자산',
    nameQ: '회사 이름',
    nameRule: '3~24자, 중복 불가.',
    countryQ: '나라',
    country: '나라',
    try: '해 볼 것',
    starting: '시작하는 중…',
    start: '시작',
    skull: '모든 나라와 전쟁: 세금·입항료 더 비쌈. 해적 항구: 무료, 조선소 없음.',
  },
})
