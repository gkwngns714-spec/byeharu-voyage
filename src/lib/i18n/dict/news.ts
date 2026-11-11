import { defineDict } from '../define'

// THE NEWS (0347, owner row 216; docs/NEWS_AND_MARKERS.md): the Stats News face, the dots on a chart and the card a dot opens. The
// headlines themselves are the server's (public.news_kinds, one template per kind in each language); these are the labels around them.
export const newsDict = defineDict({
  en: {
    heading: 'News',
    world: 'World',
    cities: 'My cities',
    older: 'Older',
    none: 'No news yet.',
    dot: '{n} news',
    more: '+{n} more',
  },
  ko: {
    heading: '소식',
    world: '세계',
    cities: '내 도시',
    older: '이전',
    none: '아직 소식 없음.',
    dot: '소식 {n}개',
    more: '외 {n}개',
  },
})
