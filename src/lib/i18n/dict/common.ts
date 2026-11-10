import { defineDict } from '../define'

// Words every screen shares: the language switch itself, and the plainest verbs.
export const commonDict = defineDict({
  en: {
    language: 'Language',
    korean: '한국어',
    english: 'English',
    close: 'Close',
    open: 'Open',
    cancel: 'Cancel',
    back: 'Back',
    loading: 'Loading…',
    retry: 'Try again',
    // THE WORLD'S LOADING STEPS (live/loadSteps.ts): the meter's words on every screen that opens the world (the city, the map).
    loadWorld: 'World',
    loadSea: 'Sea',
    loadFleets: 'Fleets',
  },
  ko: {
    language: '언어',
    korean: '한국어',
    english: 'English',
    close: '닫기',
    open: '열기',
    cancel: '취소',
    back: '뒤로',
    loading: '불러오는 중…',
    retry: '다시 시도',
    loadWorld: '세계',
    loadSea: '바다',
    loadFleets: '선단',
  },
})
