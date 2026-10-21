import { defineDict } from '../define'

// Sign the book (src/features/found): a new player names a company and picks a country.
export const foundDict = defineDict({
  en: {
    title: 'Start your company',
    more: 'You start with one ship, Gaivota, and 8,000 ducats at {capital}. The name and country are yours.',
    yourCapital: 'your country\'s capital',
    moreTitle: 'How every captain begins',
    hint: 'Every captain begins the same way.',
    nameQ: 'What is your company called?',
    nameRule: '3 to 24 letters; no two houses share a name.',
    countryQ: 'Which country does it sail for?',
    country: 'Country',
    try: 'Try',
    starting: 'Starting…',
    start: 'Start',
  },
  ko: {
    title: '상회 설립',
    more: '바르카 가이보타 한 척과 두캇 8,000으로 {capital}에서 시작합니다. 이름과 나라는 직접 고릅니다.',
    yourCapital: '모국의 수도',
    moreTitle: '모든 선장의 출발',
    hint: '모든 선장은 같은 조건으로 시작합니다.',
    nameQ: '상회 이름은 무엇입니까?',
    nameRule: '3~24자이며, 같은 이름의 상회는 둘일 수 없습니다.',
    countryQ: '어느 나라를 위해 항해합니까?',
    country: '나라',
    try: '해 볼 것',
    starting: '시작하는 중…',
    start: '시작',
  },
})
