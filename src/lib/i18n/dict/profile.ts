import { defineDict } from '../define'

// Profile (src/features/profile): the company, its country, signing out. The LEVEL words
// went with the levels to the You tab (dict/you.ts, owner row 181).
export const profileDict = defineDict({
  en: {
    since: 'since {date}',
    noCompany: 'No company yet.',
    localOnly: 'Not signed in',
    localWhere: 'This browser only',
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
    // 0503: the company's rename, beside its name. The first is free; a later one waits for the owner's decision on payment.
    rename: 'Rename',
    renameFree: 'Rename (1 free)',
    renameTitle: 'Rename company',
    renameSave: 'Save',
    renameOnce: 'Your first rename is free. Choose with care.',
    renameUsed: 'Your free rename is used. Another rename is not available yet.',
    // 0509: close the company and found again
    restart: 'Restart',
    restartTitle: 'Restart company',
    restartWarning: 'Your company closes for good: ships, cargo, stores, captains, shares and levels go. Your coin goes to your capital. You begin again with the usual start. Once a day.',
    restartConfirm: 'Type {name} to confirm',
  },
  ko: {
    since: '{date} 설립',
    noCompany: '아직 회사 없음.',
    localOnly: '로그인 안 됨',
    localWhere: '이 브라우저에만 저장',
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
