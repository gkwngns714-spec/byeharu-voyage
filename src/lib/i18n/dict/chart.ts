import { defineDict } from '../define'

// The chart's own controls (src/chart). Sea and region names on the chart are proper nouns.
export const chartDict = defineDict({
  en: {
    showOnChart: 'Show on the chart',
    zoomIn: 'Zoom in',
    zoomOut: 'Zoom out',
    regions: 'Regions',
    opening: 'Opening the chart…',
    findOrder: 'Show where the fleet is and the cities of this plan',
  },
  ko: {
    showOnChart: '해도에서 보기',
    zoomIn: '확대',
    zoomOut: '축소',
    regions: '해역',
    opening: '해도를 여는 중…',
    findOrder: '선단 위치와 이 계획의 도시 보기',
  },
})
