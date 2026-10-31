import { defineDict } from '../define'

// Profile (src/features/profile): the company, its country, the look, signing out. The LEVEL words
// went with the levels to the You tab (dict/you.ts, owner row 181).
export const profileDict = defineDict({
  en: {
    since: 'since {date}',
    noCompany: 'No company yet.',
    appearance: 'Appearance',
    Dark: 'Dark',
    Light: 'Light',
    Auto: 'Auto',
    localOnly: 'Not signed in: clearing browser data ends this game.',
    signOut: 'Sign out',
    signedIn: 'Signed in',
    signingOut: 'Signing out…',
    country: 'Country',
    nextChange: 'next change {date}',
    keep: 'Keep',
    change: 'Change',
    influenceStays: 'Influence stays with the old country.',
    changing: 'Changing…',
    sailFor: 'Sail for {nation}',
  },
  ko: {
    since: '{date} 설립',
    noCompany: '아직 회사가 없습니다.',
    appearance: '화면',
    Dark: '어둡게',
    Light: '밝게',
    Auto: '자동',
    localOnly: '로그인 안 됨: 브라우저 데이터를 지우면 게임이 끝남.',
    signOut: '로그아웃',
    signedIn: '로그인됨',
    signingOut: '로그아웃 중…',
    country: '나라',
    nextChange: '다음 변경 {date}',
    keep: '유지',
    change: '변경',
    influenceStays: '영향력은 떠난 나라에 남음.',
    changing: '바꾸는 중…',
    sailFor: '{nation} 소속으로 항해',
  },
})
