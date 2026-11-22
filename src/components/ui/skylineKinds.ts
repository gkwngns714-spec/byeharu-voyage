// WHICH SKYLINE A HARBOUR WEARS — the one table (./Skyline.tsx draws them; its header says why).

export type SkylineKind = 'latin' | 'northern' | 'islamic' | 'tropical' | 'indic' | 'eastern'

export const SKYLINE_KINDS: readonly SkylineKind[] = ['latin', 'northern', 'islamic', 'tropical', 'indic', 'eastern']

const BY_CULTURE: Readonly<Record<string, SkylineKind>> = {
  latin: 'latin',
  anglo: 'northern',
  germanic: 'northern',
  nordic: 'northern',
  islamic: 'islamic',
  swahili: 'tropical',
  guinean: 'tropical',
  oceanic: 'tropical',
  indic: 'indic',
  malay: 'indic',
  sinic: 'eastern',
  korean: 'eastern',
  japanese: 'eastern',
}

/** The picture a served culture is drawn as. */
export function skylineOf(culture: string | null | undefined): SkylineKind {
  return (culture && BY_CULTURE[culture]) || 'latin'
}
