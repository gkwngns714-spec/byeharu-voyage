import { worldCaptainSkills, type CaptainSkillsView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

// ONE CAPTAIN'S SKILLS (0355, docs/REPUTATION.md section 3): `useCaptainStats`'s doorway for her steps. Read when her card opens, and again on the world's beat
// while it stays open, so a step bought, a promotion or Reputation earned at sea lands on the rows as it lands on the card. The answer is the server's whole
// reading (`public.captain_skill_next`, the one the door refuses by): this derives nothing. A captain the server does not know reads as no rows at all.
export function useCaptainSkills(code: string | null): ServedRead<CaptainSkillsView | null> {
  return useServedRead<CaptainSkillsView | null>(code, () => worldCaptainSkills(code ?? ''), { name: 'worldCaptainSkills' })
}
