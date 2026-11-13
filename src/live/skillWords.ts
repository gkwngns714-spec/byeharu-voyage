import { jobWord } from './captainWords'

// A CAPTAIN'S SKILL, BY ITS WORD (0355, docs/REPUTATION.md section 6, R2).
//
// A skill is named by its job word (`Navigator`, public.traits.word), and a job word has ONE authority on the glass:
// `jobWord` (src/live/captainWords.ts), the `books.job_*` dictionary every face that prints a job reads (the Inn, You,
// the Codex, a ship's cabins). This is that reader under the skill's name, so the upgrade rows (CaptainSkills.tsx) and
// History's sentence (features/ledger/headline.ts) say the same Korean word as the row beside them (항해사). A word
// the dictionary does not know is printed as served. The code is carried for the callers' sake and is not read.
export function skillWord(_code: string, served: string): string {
  return jobWord(served) ?? served
}
