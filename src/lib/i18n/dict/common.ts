import { defineDict } from '../define'

// Words every screen shares: the language switch itself, and the plainest verbs.
export const commonDict = defineDict({
  en: {
    language: 'Language',
    korean: '한국어',
    english: 'English',
    close: 'Close',
    cancel: 'Cancel',
    back: 'Back',
    loading: 'Loading…',
    retry: 'Try again',
  },
  ko: {
    language: '언어',
    korean: '한국어',
    english: 'English',
    close: '닫기',
    cancel: '취소',
    back: '뒤로',
    loading: '불러오는 중…',
    retry: '다시 시도',
  },
})
