import { defineDict } from '../define'

// The chart's own controls (src/chart). Sea and region names on the chart are proper nouns.
export const chartDict = defineDict({
  en: {
    showOnChart: 'Show on chart',
    zoomIn: 'Zoom in',
    zoomOut: 'Zoom out',
    regions: 'Regions',
    opening: 'Opening…',
    findOrder: 'Show fleet and plan cities',
  },
  ko: {
    showOnChart: '해도에 표시',
    zoomIn: '확대',
    zoomOut: '축소',
    regions: '해역',
    opening: '여는 중…',
    findOrder: '선단과 계획 도시 표시',
  },
})
