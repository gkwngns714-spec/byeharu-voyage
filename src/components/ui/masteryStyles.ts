// A GOOD'S MASTERY (0479, roadmap 2026-11-23 slice 11): the one recipe for a mastered good's name, so the Trade desk's cards, the From
// here tiles, the arrival card, the toast, You's plate and the logbook's slots draw it alike (Mastery.tsx draws the level ring).

/** A good's name at the top of its ladder is gold (the accent) and bold; else the caller's ink. */
export function masteredTone(mastered: boolean, ink = 'text-ink'): string {
  return mastered ? 'font-semibold text-accent' : ink
}
