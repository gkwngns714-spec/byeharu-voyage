// THE SHIPPED WORLD WHERE THE HOUSE FOUNDS WITH ONE B NAVIGATOR SEATED AND 260 REPUTATION — for the captain's skill rows (0355, docs/REPUTATION.md R2).
//
// A local world founds its house at boot (`public.new_house`, src/lib/db/localDb.ts), AFTER the image is loaded, so neither a captain nor a balance can be a row in
// the image: there is no player yet. The patch leaves a trigger on `public.ships`, as tests/captainSheet.fixture.ts does. When the founding flagship is commissioned
// it signs Richard Chancellor into that fleet through the game's own door (`public.sign_officer`: seated by `public.captain_seat_pick`, her wage paid from the
// purse), sets what she uses (`public.captain_traits_set_for`) and books 260 Reputation through the one writer (`public.reputation_credit`, kind `built`, which is
// outside the day's cap). Nothing is stubbed: `world.captain_skills` and `cmd.captain_skill_up` answer from the real tables.
//
// WHY HER, AND WHY 260. She is a B captain, so her ceiling is 5, and her Navigator is 6.5 % (data/officers.json, public.captain_traits; MEASURED, then pinned
// here). 260 buys step 1 (50) and step 2 (150) and leaves 60, which is short of step 3 (300): the design's own row, `Navigator · 2 / 5 · +8 %  [ Upgrade · 300 ]`,
// with the button greyed and the server's reason under it. Her speed term goes 6.5 -> 6.76 -> 7.02 (6.5 x 1.04, 6.5 x 1.08), which the
// same card's speed line words to one decimal: +6.5%, +6.8%, +7%. (The exact terms are proof 58's.)
//
// Merchants are not touched (`is_npc`), and the trigger returns at depth 2. The chain fingerprint inside the image is untouched.

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

export const SKILL_CAPTAIN = {
  code: 'CHANCELLOR',
  name: 'Richard Chancellor',
  /** her grade's ceiling (B) */
  max: 5,
  /** the six skills a B captain knows, in her kit's order */
  known: ['NAVIGATOR', 'PROVISIONER', 'PILOT', 'SURGEON', 'TOBACCO_TRADER', 'BOARDER'],
  uses: ['NAVIGATOR', 'PILOT'],
  /** her speed line at step 0, 1 and 2: 6.5 %, x 1.04 = 6.76, x 1.08 = 7.02, as the server words a part (public.trait_effect_words: one decimal) */
  speed: ['+6.5% speed', '+6.8% speed', '+7% speed'],
} as const

/** What the trigger books, and what is left after each step. */
export const SKILL_REPUTATION = { seed: 260, after: [260, 210, 60], costs: [50, 150, 300] } as const

export function captainSkillsWorld(): Promise<Buffer> {
  return patchedWorldImage('captain-skills', async (pg) => {
    await pg.exec(`
      create function public.spec_captain_skills() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $fn$
      declare
        v_r jsonb;
      begin
        if pg_trigger_depth() > 1 then return null; end if;
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        if exists (select 1 from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = new.player_id and o.code = '${SKILL_CAPTAIN.code}') then return null; end if;
        v_r := public.sign_officer(new.player_id, '${SKILL_CAPTAIN.code}', new.fleet_id);
        if not coalesce((v_r ->> 'ok')::boolean, false) then
          raise exception 'spec: ${SKILL_CAPTAIN.code} was refused: %', v_r;
        end if;
        v_r := public.captain_traits_set_for(new.player_id, '${SKILL_CAPTAIN.code}', array[${SKILL_CAPTAIN.uses.map((t) => `'${t}'`).join(', ')}]);
        if not coalesce((v_r ->> 'ok')::boolean, false) then
          raise exception 'spec: her skills were refused: %', v_r;
        end if;
        if public.reputation_credit(new.player_id, 'built', ${SKILL_REPUTATION.seed}, 'spec:seed') <> ${SKILL_REPUTATION.seed} then
          raise exception 'spec: the Reputation was not booked';
        end if;
        return null;
      end $fn$;
      create trigger spec_captain_skills after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_captain_skills();
    `)
  })
}

/** Serve the captain's-skills world to `page` in place of the shipped image. Call it before `page.goto`. */
export async function serveCaptainSkillsWorld(page: Page): Promise<void> {
  await serveWorldImage(page, await captainSkillsWorld())
}
