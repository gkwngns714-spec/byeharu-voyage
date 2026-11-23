import { defineDict } from '../define'

// THE SEAS (docs/SEA_CONDITIONS_AND_REGIONS.md): a sea's name and harbours (the Codex's Seas face, the Map's Seas filter), and the
// words of a refusal a closed sea makes (components/ui/seaWallWords.ts). The owner switched the sea limits off on 2026-11-23
// (docs/design/hq-command-2026-11-23.md), so no screen draws what a sea asks; the wall words stand only where the server refuses.
// A wall is HAVE / NEED and the fix in a few words (owner, 2026-11-15): `Western Ocean closed · Waves 12 / 30 · fit planking`.
// A figure and its word never part at a line end (no-break spaces).
export const seasDict = defineDict({
  en: {
    seas: 'Seas',
    filter: 'Filter seas',
    harbours: { one: '{n} harbour', other: '{n} harbours' },
    wallHead: '{sea} closed',
    wallTitle: 'Title {have} / {need}',
    wallWaves: 'Waves {have} / {need}',
    wallBoth: 'Title {title} / {needTitle} · Waves {waves} / {needWaves}',
    wallAsks: 'Title {needTitle} · Waves {needWaves}',
    fixTitle: 'Trading & Exploration {need}',
    fixWaves: 'fit planking',
  },
  ko: {
    seas: '바다',
    filter: '바다 찾기',
    harbours: { one: '항구 {n}곳', other: '항구 {n}곳' },
    wallHead: '{sea} 닫힘',
    wallTitle: '직함 {have} / {need}',
    wallWaves: '내파 {have} / {need}',
    wallBoth: '직함 {title} / {needTitle} · 내파 {waves} / {needWaves}',
    wallAsks: '직함 {needTitle} · 내파 {needWaves}',
    fixTitle: '교역·탐험 {need}레벨',
    fixWaves: '판재 장착',
  },
})
