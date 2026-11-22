import { defineDict } from '../define'

// THE WORLD EVENTS (0469; docs/design/playable-2026-11-22.md P2): a famine, a festival or a blockade the server names at a harbour for a
// few real hours (world.world_events). Their headlines in the News are the server's (public.news_kinds EVENT_*); these are the labels the
// Trade line, the quay and the map put around them. Each kind's effect is one short line: what to carry there, or what it costs.
export const eventsDict = defineDict({
  en: {
    heading: 'Events',
    FAMINE: 'Famine',
    FESTIVAL: 'Festival',
    BLOCKADE: 'Blockade',
    // what it does, said once, with the served figure
    wantFood: 'Food ×{mult}',
    wantLuxury: 'Luxuries ×{mult}',
    toll: 'Fees +{pct}%',
    endsIn: 'ends {when}',
    startsIn: 'starts {when}',
    here: 'Here',
  },
  ko: {
    heading: '사건',
    FAMINE: '기근',
    FESTIVAL: '축제',
    BLOCKADE: '봉쇄',
    wantFood: '식량 ×{mult}',
    wantLuxury: '사치품 ×{mult}',
    toll: '수수료 +{pct}%',
    endsIn: '{when} 종료',
    startsIn: '{when} 시작',
    here: '여기',
  },
})
