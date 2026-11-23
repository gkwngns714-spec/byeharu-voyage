import { defineDict } from '../define'

// The chart's own controls (src/chart). Sea and region names on the chart are proper nouns.
export const chartDict = defineDict({
  en: {
    showOnChart: 'Show on chart',
    zoomIn: 'Zoom in',
    zoomOut: 'Zoom out',
    regions: 'Regions',
    filter: 'Filter',
    layerOff: 'Off',
    seas: 'Seas',
    // 0484: the country race on the map (each contested city ringed by who leads it this week)
    race: 'Race',
    opening: 'Opening…',
    findOrder: 'Show fleet and plan cities',
  },
  ko: {
    showOnChart: '해도에 표시',
    zoomIn: '확대',
    zoomOut: '축소',
    regions: '해역',
    filter: '필터',
    layerOff: '끔',
    seas: '바다',
    race: '경쟁',
    opening: '여는 중…',
    findOrder: '선단과 계획 도시 표시',
  },
})
