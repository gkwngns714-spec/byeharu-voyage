-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0195 — THE RAIDS ARE ROLLED BACK  (reverses 0192: combat_bite false, armour_turns_pct 0)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- WHY: 0192's 30-minute after-check (16:52-17:22 UTC, read-only) broke its own bound: arrivals avg 3.18 s against
-- the bound of 3 s (p95 4.54 s held; before 2.80 / 3.89, 0189 dark 2.95 / 3.98). The raids themselves held their bounds
-- (docs/dev-log/2026-10-18-auto-fight.md). The bound is absolute, so the switch goes off. A forward migration,
-- never a raw UPDATE on prod. Nothing written lit is unreadable dark: a day's `rounds` and a report's `fights`
-- stay in their rows and the History tray keeps printing them; a dark day simply has none.
-- No body, no ALTER, no grant. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
-- VERSION: 0195 (prod head 0194 at writing; renumber to head + 1 at deploy). Applies on 0192 lit.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('lock_timeout', '5s', true);
  if (select value from public.world_config where key = 'combat_bite') <> 'true'::jsonb then
    raise exception '0195 refuses: combat_bite is not lit — there is nothing to roll back';
  end if;
end $guard$;

update public.world_config set value = 'false'::jsonb,
       description = '0168 (S4 + K10) / 0189 / 0192 / 0195: THE switch of combat — OFF again since 0195 (0192''s after-check). '
                     'Off: DESIGN B.6''s ratio table. On: a raid is fought in rounds (voyage.fight).'
 where key = 'combat_bite';
update public.world_config set value = '0'::jsonb,
       description = '0168 / 0192 / 0195: the share of a storm''s, a shoal''s or a fight''s hull loss armour turns (public.armour_soak). '
                     '0 since 0195 (the loss itself).'
 where key = 'armour_turns_pct';

do $$
begin
  if (select value from public.world_config where key = 'combat_bite') <> 'false'::jsonb
     or (select value from public.world_config where key = 'armour_turns_pct') <> '0'::jsonb then
    raise exception '0195 self-assert FAIL: the switches did not go back';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0195 self-assert FAIL: the grant wall moved';
  end if;
  raise notice '0195 self-assert ok: THE RAIDS ARE ROLLED BACK — combat_bite false, armour_turns_pct 0 (DESIGN B.6''s roll again).';
end $$;
