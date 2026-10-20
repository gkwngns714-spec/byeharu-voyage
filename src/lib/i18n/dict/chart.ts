import { defineDict } from '../define'

// The chart's own controls (src/chart). Sea and region names on the chart are proper nouns.
export const chartDict = defineDict({
  en: {
    showOnChart: 'Show on the chart',
    zoomIn: 'Zoom in',
    zoomOut: 'Zoom out',
    regions: 'Regions',
  },
  ko: {
    showOnChart: '해도에서 보기',
    zoomIn: '확대',
    zoomOut: '축소',
    regions: '해역',
  },
})
