-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0059 — THE SEA DECIDES WHAT IT BREEDS
--        0055's mix stops being dark. `voyage.hazard_roll` becomes `voyage.encounter_at`'s body,
--        the flat weight and the cede are DELETED rather than left beside it, `voyage.settle`
--        gains one arm per new kind, and the panel's row carries the mix.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE AUTHORITY FOR WHAT "LIGHTING IT" MEANS, QUOTED VERBATIM ────────────────────────────────
-- `supabase/migrations/20260818000055_what_these_waters_breed.sql:132-143`, from the section
-- headed "── LANDED DARK, AND EXACTLY WHAT LIGHTING IT WOULD BE ──":
--
--   "**LIGHTING IT IS ONE MIGRATION AND IT IS THESE FOUR STATEMENTS:**
--      1. `create or replace function voyage.hazard_roll` = this file's `voyage.encounter_at` body.
--         (Same signature, same shape, same three streams — it is written to be dropped in.)
--      2. `update public.voyage_event_kinds set is_rolled = true, roll_weight = null where in_sea_mix`
--         ...which the 0035 closure trigger forbids, so the same slice must also drop
--         `voyage_event_kinds_weights_close` and `roll_weight`: once the mix is the draw, a flat
--         weight is a second authority and must not survive. (`is_rolled` then means only "drawn".)
--      3. `voyage.settle` gains ONE arm per new kind - five arms. FAIR_WIND subtracts delay hours,
--         FOUL_WATER starts water over the side, SHOAL_WATER takes durability, DERELICT and CONSORT
--         touch no ship at all. The prose needs NO code: every new kind's sentence already comes out
--         of `voyage.report_line` correctly, which this file asserts on real payloads.
--      4. The panel gains the mix as a fifth fact per row, from `voyage.sea_mix`."
--
-- This file is those four statements. 0055 chose the mix, the coefficients, the five kinds and
-- their sentences; 0059 re-opens none of it.
--
-- ── WHAT IT SUPERSEDES, NAMED ──────────────────────────────────────────────────────────────────
-- THREE deployed bodies, every one SLICED out of the live catalogue rather than retyped, so
-- "nothing else moved" is a byte comparison and not a sentence (NO_SPAGHETTI §3.3):
--
--   * `voyage.hazard_roll(uuid, int)` — 0006:666, superseded by 0035:294, SUPERSEDED HERE. Its new
--     body is `voyage.encounter_at`'s DEPLOYED definition with the function name in the header
--     changed and NOTHING ELSE; `voyage.encounter_at` is DROPPED in the same statement, because a
--     copy of a rule kept "for reference" is the second author §1 exists to forbid. Asserted: the
--     new `prosrc` is the old `encounter_at` `prosrc`, character for character, and `encounter_at`
--     no longer exists.
--   * `voyage.settle(uuid, timestamptz)` — 0007:887, superseded 0027:237, sliced 0047 §12,
--     SUPERSEDED HERE by three hunks: two declarations, the five arms, and `if v_delay > 0`
--     becoming `if v_delay <> 0` (a fair wind moves the arrival EARLIER, so the old test would have
--     banked the hours and left the ETA where it was). Every other arm is asserted byte-identical.
--   * `voyage.waters_ahead(uuid)` — 0055 §6, SUPERSEDED HERE by one hunk that adds `'mix'` to the
--     row it already emits and changes nothing else.
--
-- And THREE things are deleted, not deprecated (NO_SPAGHETTI §5): `voyage.encounter_at`; the
-- trigger `voyage_event_kinds_weights_close` with its function `public.tg_voyage_event_kind_weights`;
-- and the columns `roll_weight`, `cedes_to`, `cede_fraction`.
--
-- ── WHY THE CEDE COLUMNS GO TOO, WHICH IS NOT A FIFTH DESIGN ───────────────────────────────────
-- Statement 2 names `roll_weight`. `cedes_to` / `cede_fraction` are the same object one layer over,
-- and 0055's own §5 already ruled on them, at
-- `20260818000055_what_these_waters_breed.sql:427-430`:
--
--   "THE ONE THING THAT DIFFERS from voyage.hazard_roll: the kind comes from voyage.sea_mix instead
--    of from the flat bands, and there is NO cede. The cede exists in 0035 only because the flat mix
--    could not say 'this water breeds raiders'; the mix says it directly, so a second mechanism for
--    the same sentence would be a second authority."
--
-- After statement 1 nothing reads them. Measured, not assumed: `grep -rn 'cedes_to'` over the whole
-- tree finds migrations 0035 / 0036 / 0055, which are history and replay before this file, and
-- `scripts/build-sea-places.mjs:408`, which is the GENERATOR that emitted 0036 and is not part of
-- the chain. Two authored numbers that decide nothing are the "authored-and-unread fields" ledger
-- 0055:86 names as a defect; they are deleted in the change that made them dead, which is all §5 is.
--
-- ── WHAT IT COSTS A VOYAGE. MEASURED BY THIS FILE, ON THIS CHAIN ──────────────────────────────
-- Both columns below are produced by walking all 10,000 points of [0,1) twice — once through the
-- pre-image bands, captured before the first statement deleted them, and once through the deployed
-- `voyage.sea_mix` — and both are printed in the receipt, so they cannot go stale (§6 case 1).
--
--     sea (danger, piracy)          PIRATES share of event-days
--     home waters   (1, 0.20)      33.0  ->   7.0  per cent
--     Mediterranean (3, 0.45)      43.0  ->  20.4  per cent   <- the Barbary run
--     Caribbean     (4, 0.45)      43.0  ->  23.4  per cent
--     Malacca       (5, 0.45)      43.0  ->  25.8  per cent
--     Arctic        (4, 0.12)      29.8  ->   9.3  per cent
--
-- THE FREQUENCY OF EVENT-DAYS DOES NOT MOVE AT ALL. `hazard_base x hazard_mult`, clamped at
-- `hazard_p_max`, is untouched to the character, and this file proves it by RECOMPUTING the
-- probability and the three rng draws independently of the deployed body and requiring the deployed
-- body to agree on every day of a real voyage. This changes WHICH thing happens, never HOW OFTEN.
--
-- ── WHAT IT DOES TO THE VOYAGES ALREADY AT SEA, SAID OUT LOUD ─────────────────────────────────
-- Production carries live voyages. Days already recorded in `voyage_events` are NOT recomputed —
-- settle reads them, it never re-derives them — so no day a player has already been told about
-- changes. For the days still ahead of a sailing fleet, 0055's own assert (j) is the guarantee: it
-- proved `voyage.encounter_at` agrees with `voyage.hazard_roll` on WHETHER something happens, on
-- its magnitude and on its probability, day for day. A fleet at sea therefore keeps her event days
-- and her arrival; only what befalls her on them may differ. That is the whole change.
--
-- ── WHY `if v_delay <> 0`, AND WHY A FAIR WIND IS BOUNDED ─────────────────────────────────────
-- `public.voyages.delay_hours` is `numeric(10,3) not null default 0 check (delay_hours >= 0)`
-- (0006:67), and `voyage.recompute_eta` (0006:533) writes the SUM of every event's `delay_hours`
-- into it. An unbounded fair wind would drive a lucky voyage's total negative and abort the
-- settlement on that CHECK — and, worse, land a fleet before she could physically have sailed. So
-- the arm gives back hours the voyage has ALREADY LOST and never more:
--
--     hours_gained = least((0.25 + 0.70 x magnitude) x 24, voyage.delay_before_day(voyage, day))
--
-- The upper bound is the second invariant, and it was MEASURED rather than reasoned about.
-- voyage.day_ends_at(d) is `departed_at + (d x 24 + delay_before_day(d)) x k`, so a gain of 24
-- hours or more moves day d+1's boundary TO OR BEFORE day d's and the schedule INVERTS: settle
-- then resolves two checkpoints where the player was told there was one. The first draft of
-- this file gained up to 48 hours and its own probe caught it. 6 to 22.8 hours is strictly
-- inside one voyage-day, so a fair wind compresses the schedule and never folds it — and the
-- probe below asserts the boundaries stayed in order after the arm fired.
--
-- `voyage.delay_before_day` (0006:475) is the existing single authority for "how much delay had
-- this voyage accrued before day N began" — composed onto, rather than the events summed a second
-- time. By induction the running total can never go below zero, so the CHECK holds by construction
-- and not by luck. A voyage that has lost nothing makes up nothing, and the report says so;
-- inventing a gain the schedule cannot hold would be the legible lie.
--
-- ── THE ONE THING ADDED THAT IS NOT IN THE FOUR STATEMENTS, AND WHY (§7C) ─────────────────────
-- `voyage.settle`'s arm chain ends `elsif v_short then SHORT_RATIONS else CLEAR`. An occurred kind
-- with no arm falls through that `else` and is RECORDED AS A QUIET WATCH — a hazard silently
-- deleted from the game, green everywhere. With eight drawn kinds instead of three that stops being
-- theoretical, so the chain now ends with an explicit `elsif h.occurred then raise E_KIND_ARM`. It
-- cannot fire today (all eight in-mix kinds have arms, and the probe below draws an unarmed one on
-- a real day to watch the guard bite). If the `else` branch is unacceptable it is not a branch.
--
-- ── WHAT IT DELIBERATELY DOES NOT TOUCH ───────────────────────────────────────────────────────
--   * `voyage.sea_mix`, `voyage.rng`, `voyage.leg_at_day`, `voyage.report_line`,
--     `voyage.recompute_eta`, `voyage.delay_before_day`. The mix, the dice, the sentence and the
--     schedule each have one owner and this file opens no second door to any of them; four of them
--     are asserted byte-identical after it runs.
--   * The mix COEFFICIENTS. `mix_base` / `mix_danger` / `mix_raiders` are 0055's authorship and not
--     one of them moves here. Re-tuning them is a balance change and would hide inside a lighting
--     slice.
--   * `seas.hazard_base` and `seas.piracy_index`, which 0055 left flat on purpose.
--   * THE CLIENT. `src/features/map/WatersAhead.tsx:41-44` names itself the reader of the mix
--     ("It becomes a fourth fact on the row the day the mix is lit"). That is a client slice with
--     its own spec (`tests/waters.panel.spec.ts`), whose row contract forbids a row that reads like
--     a forecast, and this file does not pretend to have made it. The takes_effect discipline of
--     0015/0016/0040, marked rather than implied:
--         voyage.sea_mix        READ by voyage.hazard_roll (LIVE) and voyage.waters_ahead (LIVE)
--         waters_ahead[].mix    SERVED on world.fleets().voyage.waters; drawn by NOTHING yet.
--
-- Depends ONLY on: 0006 (voyages.delay_hours and its CHECK, delay_before_day, recompute_eta, rng),
--                  0027 / 0047 (the deployed voyage.settle these hunks are cut against), 0035
--                  (voyage_event_kinds, the closure trigger, report_line), 0055 (sea_mix,
--                  encounter_at, waters_ahead, the five dark kinds), 0050 (pg_temp.recut).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse (0047 §0, 0055 §0)
-- A pg_temp function dies with the session and never enters the deployed catalogue, so every
-- migration that slices carries its own copy — docs/DEV_LOG.md D25.
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0059 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── PRE-IMAGES, captured before the first statement moves anything ────────────────────────────
create temporary table defs_before_0059 as
  select 'voyage.encounter_at'::text as fn,
         pg_get_functiondef('voyage.encounter_at(uuid, int)'::regprocedure) as def,
         (select p.prosrc from pg_proc p where p.oid = 'voyage.encounter_at(uuid, int)'::regprocedure) as src,
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.encounter_at(uuid, int)'::regprocedure) as acl
  union all
  select 'voyage.hazard_roll',
         pg_get_functiondef('voyage.hazard_roll(uuid, int)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure)
  union all
  select 'voyage.settle',
         pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.settle(uuid, timestamptz)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.settle(uuid, timestamptz)'::regprocedure)
  union all
  select 'voyage.waters_ahead',
         pg_get_functiondef('voyage.waters_ahead(uuid)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.waters_ahead(uuid)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.waters_ahead(uuid)'::regprocedure)
  union all
  select 'voyage.sea_mix',
         pg_get_functiondef('voyage.sea_mix(uuid)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.sea_mix(uuid)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.sea_mix(uuid)'::regprocedure)
  union all
  select 'voyage.report_line',
         pg_get_functiondef('voyage.report_line(int, text, jsonb)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure)
  union all
  select 'voyage.recompute_eta',
         pg_get_functiondef('voyage.recompute_eta(uuid)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.recompute_eta(uuid)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.recompute_eta(uuid)'::regprocedure)
  union all
  select 'voyage.delay_before_day',
         pg_get_functiondef('voyage.delay_before_day(uuid, int)'::regprocedure),
         (select p.prosrc from pg_proc p where p.oid = 'voyage.delay_before_day(uuid, int)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.delay_before_day(uuid, int)'::regprocedure);

-- THE OLD BANDS, so "43.0 becomes 20.4" is a measurement taken against the world as it stood one
-- statement ago rather than a number somebody remembered. The columns this file is about to delete
-- are the only place that draw was ever written down.
create temporary table kinds_before_0059 as
  select code, ordinal, is_rolled, roll_weight, cedes_to, cede_fraction, in_sea_mix
    from public.voyage_event_kinds;

-- ── 1. THE DRAW BECOMES THE MIX — statement 1 ─────────────────────────────────────────────────
-- SUPERSEDES voyage.hazard_roll (0035:294). Its new body is voyage.encounter_at's DEPLOYED
-- definition with its own name in the header replaced, so the two cannot differ by a character;
-- and encounter_at is DROPPED in the same statement, because 0055 wrote it to BE this body and a
-- second copy of it would be a second author the day either one is edited.
select pg_temp.recut('voyage.encounter_at(uuid, int)'::regprocedure, true,
  'FUNCTION voyage.encounter_at(p_voyage uuid, p_day integer)',
  'FUNCTION voyage.hazard_roll(p_voyage uuid, p_day integer)');

-- An assumed grant is how a read wall came down in 0018 and had to be rebuilt in 0023. hazard_roll
-- has never been client-callable; re-issued explicitly, and asserted unmoved below.
revoke all on function voyage.hazard_roll(uuid, int) from public, anon, authenticated;

comment on function voyage.hazard_roll(uuid, int) is
  '0059: THE hazard decision of DESIGN B.6, now decided by the SEA. Pure: it writes nothing. Its '
  'body is 0055''s voyage.encounter_at, moved here unchanged and that function deleted — the '
  'occurrence, the magnitude and the probability are 0006''s to the character, and only the choice '
  'of kind moved, from flat bands to voyage.sea_mix. There is no cede any more: the mix says "this '
  'water breeds raiders" directly, and a second mechanism for one sentence would be a second '
  'authority. Adding a thing that happens at sea is still an INSERT into public.voyage_event_kinds '
  '(in_sea_mix plus three response numbers) and one arm in a superseding voyage.settle.';

-- ── 2. THE FLAT WEIGHT AND THE CEDE ARE DELETED — statement 2 ─────────────────────────────────
-- Order is load-bearing. The closure trigger asserts the rolled weights sum to 1, and
-- voyage_event_kinds_weight_iff_rolled requires a rolled kind to carry a weight; both must go
-- before eight kinds can be rolled with no weight at all. Dropping the COLUMN is what statement 2's
-- `roll_weight = null` means once and for ever, and it takes its own CHECK with it.
drop trigger voyage_event_kinds_weights_close on public.voyage_event_kinds;
drop function public.tg_voyage_event_kind_weights();

alter table public.voyage_event_kinds
  drop column roll_weight,
  drop column cedes_to,
  drop column cede_fraction;

update public.voyage_event_kinds set is_rolled = true where in_sea_mix;

comment on column public.voyage_event_kinds.is_rolled is
  '0059: a ROLLED kind is DRAWN — by voyage.hazard_roll, out of voyage.sea_mix''s per-sea shares. '
  'It no longer means "carries a flat weight": that column, its closure trigger and the piracy cede '
  'were deleted when the mix became the draw. A CONDITION kind (CLEAR, SHORT_RATIONS) is decided by '
  'voyage.settle from what is aboard, and LANDFALL by its arrival arm; none of them is ever drawn. '
  'is_rolled is now exactly in_sea_mix for every row — voyage_event_kinds_rolled_is_in_the_mix '
  'keeps one half of that true and 0059''s self-assert measures the other. Setting is_rolled=false '
  'still RETIRES a kind from the draw while keeping it nameable, so history keeps its foreign key.';

comment on table public.voyage_event_kinds is
  'THE catalogue of things that can befall a fleet on a voyage-day (DESIGN B.6). One row per kind: '
  'whether it is drawn, how its weight answers the water it is drawn in (0055''s in_sea_mix, '
  'mix_base, mix_danger, mix_raiders), and the sentence the player reads. voyage.sea_mix turns those '
  'three numbers and the sea''s own danger tier and piracy index into shares, voyage.hazard_roll '
  'draws from them, voyage.report_line reads the prose, and public.voyage_events.kind is a foreign '
  'key into it — so a kind nobody named cannot be written. Adding a thing that happens at sea is an '
  'INSERT here plus, only if it does something new to the ships, one arm in a superseding '
  'voyage.settle — and since 0059 a drawn kind with no arm RAISES E_KIND_ARM rather than being '
  'written down as a quiet watch. See docs/PLATFORM.md.';

-- ── 3. FIVE ARMS — statement 3 ────────────────────────────────────────────────────────────────
-- SUPERSEDES voyage.settle (0027:237, as sliced by 0047 §12) by THREE hunks and nothing else.
-- STORM's durability and 36 hours, CALM's delay, the whole PIRATES combat and surgeon block,
-- SHORT_RATIONS, CLEAR, the arrival arm and LANDFALL are untouched — proven below by rebuilding the
-- pre-image around the insertion point and comparing byte for byte.
select pg_temp.recut('voyage.settle(uuid, timestamptz)'::regprocedure, false,

  -- (i) two declarations. v_lost, v_hull, s, v_delay and v_payload are 0027's and are REUSED, so
  --     the arms below state no arithmetic twice.
  E'  v_crew1     numeric;\nbegin',
  E'  v_crew1     numeric;\n  -- 0059: what a fair wind made up, and what went over the side.\n  v_gain      numeric;\n  v_stores    numeric;\nbegin',

  -- (ii) THE FIVE ARMS, and the guard for the ninth kind.
  $a0$    elsif v_short then
      v_kind := 'SHORT_RATIONS';$a0$,
  $a1$    elsif h.occurred and h.kind = 'FAIR_WIND' then
      -- 0059. THE FIRST GOOD DAY AT SEA, and the mirror of CALM's arm: it SUBTRACTS delay hours.
      -- BOUNDED BY WHAT SHE HAS ALREADY LOST, and that bound is not tidiness. voyages.delay_hours
      -- is `check (delay_hours >= 0)` (0006:67) and voyage.recompute_eta writes the sum of every
      -- event's delay into it, so an unbounded gain would abort a settlement on a CHECK and, worse,
      -- land a fleet before she could have sailed. voyage.delay_before_day is the EXISTING single
      -- authority for "how much delay had this voyage accrued before day N" (0006:475) — composed
      -- onto here rather than the events summed a second time. By induction the running total never
      -- goes below zero. A voyage that has lost nothing makes up nothing, and the report says so.
      --
      -- AND IT IS BOUNDED ABOVE BY LESS THAN ONE VOYAGE-DAY (6 to 22.8 hours), which is the second
      -- invariant and was MEASURED rather than reasoned about: voyage.day_ends_at(d) is
      -- `departed_at + (d x 24 + delay_before_day(d)) x k`, so a gain of 24 hours or more moves day
      -- d+1's boundary TO OR BEFORE day d's and the schedule inverts — settle then resolves two
      -- checkpoints where the player was told there was one. The first draft of this file gained up
      -- to 48 hours and its own probe caught exactly that. A fair wind compresses the schedule; it
      -- never folds it.
      v_kind    := 'FAIR_WIND';
      v_gain    := least(round((0.25 + 0.70 * h.magnitude) * 24, 2),
                         voyage.delay_before_day(v.id, d));
      v_delay   := -v_gain;
      v_payload := v_payload || jsonb_build_object('hours_gained', v_gain, 'delay_hours', v_delay);

    elsif h.occurred and h.kind = 'FOUL_WATER' then
      -- 0059. The casks are broached and what is in them goes over the side. It takes water_t — the
      -- thing every SAIL is gated on through voyage.endurance_days — so a bad sea costs her reach
      -- rather than her paint. Shaped exactly like STORM's arm, one hull at a time, because the
      -- fleet sails in company and each drinks from her own casks.
      v_kind := 'FOUL_WATER';
      v_stores := 0;
      for s in select sh.id, sh.water_t from public.ships sh where sh.fleet_id = p_fleet loop
        v_lost := round(s.water_t * (0.10 + 0.25 * h.magnitude), 3);
        update public.ships set water_t = greatest(0, s.water_t - v_lost) where id = s.id;
        v_stores := v_stores + v_lost;
      end loop;
      v_payload := v_payload || jsonb_build_object('stores_lost', v_stores);

    elsif h.occurred and h.kind = 'SHOAL_WATER' then
      -- 0059. Grounding killed more ships than gunfire. STORM's arm at a lighter coefficient (4-15
      -- per cent of rated durability against STORM's 8-25), and it reuses STORM's own `hull_lost`
      -- payload key on purpose: one payload vocabulary, so the report reads the same way whatever
      -- took the planking. It costs no hours — she came off, and she sailed on.
      v_kind := 'SHOAL_WATER';
      v_hull := 0;
      for s in select sh.id, sh.durability, c.durability maxd
                 from public.ships sh join public.ship_classes c on c.id = sh.class_id
                where sh.fleet_id = p_fleet loop
        v_lost := round(s.maxd * (0.04 + 0.11 * h.magnitude), 2);
        update public.ships set durability = greatest(0, s.durability - v_lost) where id = s.id;
        v_hull := v_hull + v_lost;
      end loop;
      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull);

    elsif h.occurred and h.kind in ('DERELICT', 'CONSORT') then
      -- 0059. THEY TOUCH NO SHIP AT ALL — 0055's words, and the reason is that neither has anyone
      -- to touch it with: an event has no SUBJECT (PLATFORM §3 seam 2 is unbuilt), so a derelict
      -- cannot hand over a named cargo and a consort cannot be a named ship. DERELICT writes no
      -- `salvage` key, which is not an omission: voyage.report_line's fallback arm prints "a little
      -- cordage" for exactly this, and 0055's assert (f) already proved it reads. The slice that
      -- gives an event a subject is the named writer of that key.
      v_kind := h.kind;

    elsif h.occurred then
      -- NO_SPAGHETTI §7C. Without this an occurred kind with no arm falls through to the `else`
      -- below and is recorded as a QUIET WATCH — a hazard silently deleted from the game, green
      -- everywhere. Unreachable today (all eight in-mix kinds are handled) and it is the guard for
      -- the ninth.
      raise exception 'E_KIND_ARM: % befell voyage % on day % and voyage.settle has no arm for it — a drawn kind with no arm would be written down as a quiet watch', h.kind, v.id, d
        using errcode = 'P0001';

    elsif v_short then
      v_kind := 'SHORT_RATIONS';$a1$,

  -- (iii) a fair wind moves the arrival EARLIER, so `> 0` would have banked the hours and left the
  --       ETA where it was. The ONE ETA authority is still voyage.recompute_eta; only the test that
  --       decides whether to call it moves.
  E'    if v_delay > 0 then perform voyage.recompute_eta(v.id); end if;',
  E'    if v_delay <> 0 then perform voyage.recompute_eta(v.id); end if;');

comment on function voyage.settle(uuid, timestamptz) is
  'THE idempotent catch-up of DESIGN D.2. Supersedes the 0027 definition (as sliced by 0047) in '
  'three marked hunks and nowhere else — the file was SLICED, not retyped, so the wage, ration, '
  'day-boundary, storm, calm and raid arithmetic proof 01 matches to the character is byte-identical '
  'by construction. What 0059 changed: five arms for the kinds 0055 authored dark (FAIR_WIND gives '
  'back delay hours it can prove the voyage lost, FOUL_WATER starts water over the side, '
  'SHOAL_WATER takes durability, DERELICT and CONSORT touch no ship), an E_KIND_ARM raise so a '
  'drawn kind with no arm can never be written down as a quiet watch, and recompute_eta now runs on '
  'ANY schedule change rather than only on a slip.';

-- ── 4. THE PANEL'S ROW CARRIES THE MIX — statement 4 ──────────────────────────────────────────
-- SUPERSEDES voyage.waters_ahead (0055 §6) by ONE hunk. The shares are voyage.sea_mix's own,
-- copied — nothing here derives a mix, for the same reason nothing here derives a tier: the picture
-- and the rules would be two authorities for one number.
select pg_temp.recut('voyage.waters_ahead(uuid)'::regprocedure, false,
  $wo$      'nm_to',  round(greatest(0, v_from[i] - v_done), 1),$wo$,
  $wn$      'nm_to',  round(greatest(0, v_from[i] - v_done), 1),
      -- 0059: AND WHAT THIS WATER BREEDS. voyage.sea_mix's own shares, keyed on the SAME
      -- seas.danger_level the row above prints, so the panel and the dice can never disagree.
      -- It is the mix and not an opinion about it: which kind is worth naming on a row is the
      -- screen's choice, and a headline picked here would be a second authority for it.
      'mix',    (select jsonb_object_agg(m.kind_code, m.share) from voyage.sea_mix(s.id) m),$wn$);

comment on function voyage.waters_ahead(uuid) is
  '0059 (supersedes 0055 §6 by one hunk): the seas this voyage''s frozen course still has to cross, '
  'in order, each with the distance she must still make good to reach it, its 0040 danger tier, its '
  'character, and — since the mix was lit — what that water breeds, as voyage.sea_mix''s own shares. '
  'Served on world.fleets().voyage.waters. Composed, never granted: the client reaches it only '
  'through world.fleets, which is SECURITY DEFINER and already hers. It still PREDICTS NOTHING: no '
  'rng stream is touched here and no future day is evaluated.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe  constant uuid := '00000000-0059-4000-8000-000000000001';
  -- 0047 §j's Lisbon -> Salvador course, re-used by 0055's probe: a DATA literal for water that is
  -- known to depart, not a second fixture that would have to be re-verified against the raster.
  v_course_sal constant jsonb := '[[38.71,-9.14],[-9.625,-35.125],[-12.625,-37.875],[-12.98,-38.49]]'::jsonb;
  -- The kinds probed, in this order and for a reason: CALM first, so the voyage has lost hours a
  -- fair wind can give back, then the four arms this file adds that do something.
  v_order  constant text[] := array['CALM', 'FAIR_WIND', 'FOUL_WATER', 'SHOAL_WATER', 'DERELICT', 'CONSORT'];
  -- The three hunks, restated so the comparison below is INDEPENDENT of the slice above: if the two
  -- ever disagree the assert goes red, which is the point of restating them.
  c_decl0  constant text := E'  v_crew1     numeric;\nbegin';
  c_decl1  constant text := E'  v_crew1     numeric;\n  -- 0059: what a fair wind made up, and what went over the side.\n  v_gain      numeric;\n  v_stores    numeric;\nbegin';
  c_eta0   constant text := E'    if v_delay > 0 then perform voyage.recompute_eta(v.id); end if;';
  c_eta1   constant text := E'    if v_delay <> 0 then perform voyage.recompute_eta(v.id); end if;';
  c_anchor constant text := E'    elsif v_short then\n      v_kind := ''SHORT_RATIONS'';';
  v_before text; v_after text; v_src0 text; v_src1 text; v_haz0 text;
  v_pre    text; v_post text; v_ins text;
  v_n      int; v_i int; v_bad int; v_min numeric; v_sum numeric; v_last numeric;
  v_rolled int; v_mixed int; v_seas_seen int;
  v_med    uuid;
  v_pirb   jsonb; v_pira jsonb;
  v_pir_med0 numeric; v_pir_med1 numeric;
  v_pir_bal0 numeric; v_pir_bal1 numeric;
  v_pir_mal0 numeric; v_pir_mal1 numeric;
  v_pir_car0 numeric; v_pir_car1 numeric;
  v_pir_arc0 numeric; v_pir_arc1 numeric;
  v_moved  int;
  v_player uuid; v_fleet uuid; v_voyage uuid; v_res jsonb;
  v        public.voyages%rowtype;
  v_cap    int; d int; v_skip int; v_waters int;
  v_path   jsonb; v_w jsonb; v_fpay jsonb;
  v_code   text;
  r_ev     public.voyage_events%rowtype;
  v_dur0   numeric; v_dur1 numeric;
  v_crw0   numeric; v_crw1 numeric;
  v_wat0   numeric; v_wat1 numeric;
  v_car0   text;    v_car1 text;
  v_eta0   timestamptz; v_eta1 timestamptz;
  v_del0   numeric; v_del1 numeric;
  v_ration numeric;
  v_occ    int; v_nkinds int;
  v_prose  text;
  v_kfp0   text; v_kfp1 text;
  v_wfp0   text; v_wfp1 text;
  v_left   int;
  v_acl0   text; v_acl1 text;
  v_armed  int := 0;
  v_occurs boolean;
  f_body   boolean := false;  f_slice boolean := false;
  f_gone   boolean := false;  f_moved boolean := false;
  f_mix    boolean := false;  f_freq  boolean := false;
  f_arms   boolean := false;  f_wire  boolean := false;
  f_guard  boolean := false;  f_grant boolean := false;
begin
  ---------------------------------------------------------------------------------------------
  -- (a) STATEMENT 1 IS A MOVE AND NOT A RETYPE. voyage.hazard_roll's body is now the exact source
  --     text voyage.encounter_at carried one statement ago, and encounter_at is gone.
  ---------------------------------------------------------------------------------------------
  select src into v_src0  from defs_before_0059 where fn = 'voyage.encounter_at';
  select src into v_haz0  from defs_before_0059 where fn = 'voyage.hazard_roll';
  select p.prosrc into v_src1 from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure;
  if v_src0 is null or v_src1 is null or v_haz0 is null then
    raise exception '0059 self-assert FAIL: a pre-image is missing — this migration was generated against a different chain';
  end if;
  if v_src1 = v_src0 and v_src1 <> v_haz0
     and v_src1 ~ 'voyage\.sea_mix' and v_haz0 !~ 'voyage\.sea_mix' and v_haz0 ~ 'roll_weight' then
    f_body := true;
  end if;
  if not f_body then
    raise exception '0059 self-assert FAIL: voyage.hazard_roll''s body is not voyage.encounter_at''s, character for character (% chars now against % in encounter_at and % in the old draw; the new body % read voyage.sea_mix, the old one % read it) — statement 1 was a retype rather than the move 0055 wrote it to be',
      length(v_src1), length(v_src0), length(v_haz0),
      case when v_src1 ~ 'voyage\.sea_mix' then 'does' else 'does NOT' end,
      case when v_haz0 ~ 'voyage\.sea_mix' then 'did'  else 'did not' end;
  end if;
  if to_regprocedure('voyage.encounter_at(uuid, int)') is not null then
    raise exception '0059 self-assert FAIL: voyage.encounter_at survived the move — two copies of one rule, and they disagree the day either one is edited (NO_SPAGHETTI §1)';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (b) STATEMENT 2. The flat weight, the cede and the closure trigger are GONE; every kind in the
  --     mix is drawn and every kind drawn is in the mix.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'public' and table_name = 'voyage_event_kinds'
     and column_name in ('roll_weight', 'cedes_to', 'cede_fraction');
  select count(*) into v_i from pg_trigger t
   where t.tgrelid = 'public.voyage_event_kinds'::regclass
     and t.tgname = 'voyage_event_kinds_weights_close';
  select count(*) into v_bad from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'tg_voyage_event_kind_weights';
  if v_n <> 0 or v_i <> 0 or v_bad <> 0 then
    raise exception '0059 self-assert FAIL: % of the three retired column(s), % closure trigger(s) and % trigger function(s) are still there — a flat weight beside the mix is a second answer to "how often does this happen here"',
      v_n, v_i, v_bad;
  end if;

  select count(*) filter (where is_rolled), count(*) filter (where in_sea_mix),
         count(*) filter (where is_rolled <> in_sea_mix)
    into v_rolled, v_mixed, v_bad from public.voyage_event_kinds;
  if v_rolled < 8 or v_mixed <> v_rolled or v_bad <> 0 then
    raise exception '0059 self-assert FAIL: % kind(s) are drawn and % are in the mix, and % row(s) disagree — after this file is_rolled and in_sea_mix are one fact, and the eight kinds 0055 authored must all be drawn',
      v_rolled, v_mixed, v_bad;
  end if;
  f_gone := true;

  ---------------------------------------------------------------------------------------------
  -- (c) AND IT COST WHAT 0055 SAID IT WOULD. Both figures are MEASURED by walking all 10,000
  --     points of [0,1) — once through the pre-image bands, captured before statement 2 deleted
  --     them, once through the deployed voyage.sea_mix. No formula is restated on either side.
  ---------------------------------------------------------------------------------------------
  select id into v_med from public.seas where code = 'MED';
  if v_med is null then
    raise exception '0059 self-assert FAIL: the probe cannot find the Mediterranean, the sea whose Barbary run it measures — the world data moved under this file';
  end if;

  with bands as (
    select b.code, b.ordinal, b.cedes_to, b.cede_fraction,
           sum(b.roll_weight) over (order by b.ordinal rows between unbounded preceding and current row) as cum
      from kinds_before_0059 b where b.is_rolled),
  line as (select i::numeric / 10000 as x from generate_series(0, 9999) i),
  subject as (select s.code, s.piracy_index from public.seas s
               where s.code in ('MED', 'BAL', 'STR', 'CAR', 'ARC'))
  select jsonb_object_agg(q.code, q.pir) into v_pirb from (
    select subject.code, count(*) filter (where fl.k = 'PIRATES')::numeric / 10000 as pir
      from subject
     cross join line
     cross join lateral (select case when bb.cedes_to is not null
                                      and line.x < bb.cede_fraction * subject.piracy_index
                                     then bb.cedes_to else bb.code end as k
                           from bands bb where line.x < bb.cum order by bb.ordinal limit 1) fl
     group by subject.code) q;

  with line as (select i::numeric / 10000 as x from generate_series(0, 9999) i),
  subject as (select s.id, s.code from public.seas s
               where s.code in ('MED', 'BAL', 'STR', 'CAR', 'ARC'))
  select jsonb_object_agg(q.code, q.pir) into v_pira from (
    select subject.code, count(*) filter (where nu.k = 'PIRATES')::numeric / 10000 as pir
      from subject
     cross join line
     cross join lateral (select mm.kind_code as k from voyage.sea_mix(subject.id) mm
                          where line.x < mm.cum_share order by mm.cum_share limit 1) nu
     group by subject.code) q;

  if v_pirb is null or v_pira is null
     or (select count(*) from jsonb_object_keys(v_pirb)) <> 5
     or (select count(*) from jsonb_object_keys(v_pira)) <> 5 then
    raise exception '0059 self-assert FAIL: the before/after walks produced % and % sea(s) instead of 5 each — every comparison below would be vacuous',
      (select count(*) from jsonb_object_keys(coalesce(v_pirb, '{}'::jsonb))),
      (select count(*) from jsonb_object_keys(coalesce(v_pira, '{}'::jsonb)));
  end if;
  v_pir_med0 := (v_pirb->>'MED')::numeric;  v_pir_med1 := (v_pira->>'MED')::numeric;
  v_pir_bal0 := (v_pirb->>'BAL')::numeric;  v_pir_bal1 := (v_pira->>'BAL')::numeric;
  v_pir_mal0 := (v_pirb->>'STR')::numeric;  v_pir_mal1 := (v_pira->>'STR')::numeric;
  v_pir_car0 := (v_pirb->>'CAR')::numeric;  v_pir_car1 := (v_pira->>'CAR')::numeric;
  v_pir_arc0 := (v_pirb->>'ARC')::numeric;  v_pir_arc1 := (v_pira->>'ARC')::numeric;

  -- how much of the Mediterranean's whole draw lands somewhere other than the flat bands put it
  with line as (select i::numeric / 10000 as x from generate_series(0, 9999) i),
  bands as (
    select b.code, b.ordinal, b.cedes_to, b.cede_fraction,
           sum(b.roll_weight) over (order by b.ordinal rows between unbounded preceding and current row) as cum
      from kinds_before_0059 b where b.is_rolled)
  select count(*) filter (where nu.k is distinct from fl.k), count(*)
    into v_moved, v_n
    from line
   cross join lateral (select mm.kind_code as k from voyage.sea_mix(v_med) mm
                        where line.x < mm.cum_share order by mm.cum_share limit 1) nu
   cross join lateral (select case when bb.cedes_to is not null and line.x < bb.cede_fraction * 0.45
                                   then bb.cedes_to else bb.code end as k
                         from bands bb where line.x < bb.cum order by bb.ordinal limit 1) fl;

  if v_n = 10000 and v_moved >= 5000
     and v_pir_med0 > 0.40 and v_pir_med1 < v_pir_med0 / 2
     and v_pir_bal1 < v_pir_bal0 / 4
     and v_pir_mal1 < v_pir_mal0 and v_pir_mal1 > v_pir_bal1 + 0.15
     and v_pir_arc1 < v_pir_med1 then
    f_moved := true;
  end if;
  if not f_moved then
    raise exception '0059 self-assert FAIL: the raid-days did not move the way 0055 measured — PIRATES ran % per cent of Mediterranean event-days and now runs % (must be under half), Baltic % -> % (must be under a quarter), Malacca % -> % (must stay above the Baltic by 15 points), Arctic now %, and % of % points of the Mediterranean draw moved (must be at least half)',
      round(v_pir_med0 * 100, 1), round(v_pir_med1 * 100, 1),
      round(v_pir_bal0 * 100, 1), round(v_pir_bal1 * 100, 1),
      round(v_pir_mal0 * 100, 1), round(v_pir_mal1 * 100, 1),
      round(v_pir_arc1 * 100, 1), v_moved, v_n;
  end if;

  -- AND THE MIX IS STILL TOTAL OVER THE WHOLE WORLD, now that a hole in it would be a hazard roll
  -- with no answer rather than a dark curiosity.
  select count(*) into v_seas_seen from public.seas;
  select count(*), min(x.n), min(x.lo), max(abs(x.hi - 1)), max(abs(x.tot - 1))
    into v_n, v_i, v_min, v_sum, v_last
    from (select s.id,
                 (select count(*) from voyage.sea_mix(s.id))           as n,
                 (select min(m.share) from voyage.sea_mix(s.id) m)     as lo,
                 (select max(m.cum_share) from voyage.sea_mix(s.id) m) as hi,
                 (select sum(m.share) from voyage.sea_mix(s.id) m)     as tot
            from public.seas s) x;
  if v_n = v_seas_seen and v_seas_seen >= 51 and v_i = v_rolled and v_min > 0
     and v_sum = 0 and v_last <= 0.000008 then
    f_mix := true;
  end if;
  if not f_mix then
    raise exception '0059 self-assert FAIL: the mix is not total over the world''s water now that it IS the draw — % of % sea(s) answered, fewest kinds % against % drawn, smallest share %, worst band-closure error %, worst share-sum error %',
      v_n, v_seas_seen, v_i, v_rolled, v_min, v_sum, v_last;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (d) NOTHING ELSE IN THE SETTLEMENT MOVED. The deployed body is split at the insertion point
  --     and both sides are compared to the PRE-IMAGE with only the two small hunks applied. A
  --     no-op proof that merely looked for the new arms would pass while STORM's arm had been
  --     rewritten underneath it.
  ---------------------------------------------------------------------------------------------
  select def into v_before from defs_before_0059 where fn = 'voyage.settle';
  v_after := pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure);
  if (length(v_before) - length(replace(v_before, c_anchor, ''))) / length(c_anchor) <> 1
     or (length(v_after) - length(replace(v_after, c_anchor, ''))) / length(c_anchor) <> 1 then
    raise exception '0059 self-assert FAIL: the SHORT_RATIONS arm does not occur exactly once in voyage.settle before (% time(s)) and after (% time(s)) this file — the body cannot be split at its insertion point and the comparison would be meaningless',
      (length(v_before) - length(replace(v_before, c_anchor, ''))) / length(c_anchor),
      (length(v_after)  - length(replace(v_after,  c_anchor, ''))) / length(c_anchor);
  end if;
  v_pre  := replace(substr(v_before, 1, position(c_anchor in v_before) - 1), c_decl0, c_decl1);
  v_post := replace(substr(v_before, position(c_anchor in v_before)), c_eta0, c_eta1);
  if left(v_after, length(v_pre)) = v_pre
     and right(v_after, length(v_post)) = v_post
     and length(v_after) > length(v_pre) + length(v_post) then
    v_ins := substr(v_after, length(v_pre) + 1, length(v_after) - length(v_pre) - length(v_post));
  end if;
  if v_ins is not null
     and v_ins ~ 'FAIR_WIND' and v_ins ~ 'FOUL_WATER' and v_ins ~ 'SHOAL_WATER'
     and v_ins ~ 'DERELICT' and v_ins ~ 'CONSORT' and v_ins ~ 'E_KIND_ARM'
     and v_ins !~ 'WAGES' and v_ins !~ 'raid_crew_lost' and v_ins !~ 'v_escort' then
    f_slice := true;
  end if;
  if not f_slice then
    raise exception '0059 self-assert FAIL: voyage.settle after this file is not its pre-image with exactly the three declared hunks made — % character(s) were inserted at the arm chain and everything outside them must be byte-identical, so proof 01''s wage, ration, day-boundary, storm, calm and raid arithmetic stays matched by construction',
      coalesce(length(v_ins), -1);
  end if;

  select count(*) into v_n from defs_before_0059 b
   where b.fn in ('voyage.sea_mix', 'voyage.report_line', 'voyage.recompute_eta', 'voyage.delay_before_day')
     and b.src is distinct from (select p.prosrc from pg_proc p where p.oid =
           case b.fn when 'voyage.sea_mix'       then 'voyage.sea_mix(uuid)'::regprocedure
                     when 'voyage.report_line'   then 'voyage.report_line(int, text, jsonb)'::regprocedure
                     when 'voyage.recompute_eta' then 'voyage.recompute_eta(uuid)'::regprocedure
                     else 'voyage.delay_before_day(uuid, int)'::regprocedure end);
  if v_n <> 0 then
    raise exception '0059 self-assert FAIL: % of the four bodies this file must not touch (sea_mix, report_line, recompute_eta, delay_before_day) changed — the mix, the sentence and the schedule each have one owner and this file opened a second door to one of them', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- THE PROBE. A real house, a real two-ocean passage, every arm fired on a real settled day, and
  --     the whole thing rolled back by the raise at its foot.
  ---------------------------------------------------------------------------------------------
  select md5(string_agg(x, '|' order by x)) into v_kfp0 from (
    select k.code || ':' || k.is_rolled || ':' || k.in_sea_mix || ':'
           || k.mix_base || ':' || k.mix_danger || ':' || k.mix_raiders as x
      from public.voyage_event_kinds k where k.in_sea_mix) q(x);
  select md5(string_agg(x, '|' order by x)) into v_wfp0 from (
    select s.code || ':' || s.hazard_base || ':' || s.piracy_index || ':' || s.danger_level as x
      from public.seas s
    union all select 'knob:' || public.wc_num('hazard_p_max')) w(x);

  begin
    v_player := public.new_house(c_probe, 'Casa do Vento', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id into v_fleet from public.fleets where player_id = v_player;

    -- THE PROBE OWNS ITS PRECONDITIONS (README §3), following 0047 §j / 0055's recipe, which is the
    -- one known to depart this course: full crew, deterministic stores, coin.
    update public.players set ducats = 8000 where id = v_player;
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - sh.crew from public.ships sh
         join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));
    update public.ships s
       set water_t = round(s.crew * public.wc_num('water_per_crew_day') * 45, 3),
           food_t  = round(s.crew * public.wc_num('food_per_crew_day') * 45, 3)
     where s.fleet_id = v_fleet;

    v_res := cmd.issue(v_fleet, 'SAIL TO SLV', null, v_course_sal);
    if coalesce(v_res->>'ok', 'false') <> 'true' then
      raise exception '0059 self-assert FAIL: the probe''s Salvador passage was refused [%: %] — the probe has no subject and everything below it would be vacuous',
        v_res->>'error_code', v_res->>'error_message';
    end if;
    select * into v from public.voyages where fleet_id = v_fleet and status = 'SAILING';
    v_voyage := v.id;

    -------------------------------------------------------------------------------------------
    -- (e) STATEMENT 4 CROSSES THE WIRE. Every water on the panel carries the mix, it is
    --     voyage.sea_mix's own numbers rather than a second derivation, and world.fleets serves
    --     it beside the four facts 0055 put there. Taken BEFORE any weather is forced, so it is
    --     measured on a voyage exactly as the world would have made it.
    -------------------------------------------------------------------------------------------
    v_w := voyage.waters_ahead(v_voyage);
    select count(*), count(*) filter (where e->'mix' is null or jsonb_typeof(e->'mix') <> 'object')
      into v_waters, v_bad from jsonb_array_elements(v_w) e;
    select count(*) into v_i
      from jsonb_array_elements(v_w) e
      join public.seas s on s.code = e->>'sea'
     where (select jsonb_object_agg(m.kind_code, m.share) from voyage.sea_mix(s.id) m)
           is distinct from e->'mix';
    select count(*) into v_n
      from jsonb_array_elements(v_w) e
     where abs((select sum(t.value::numeric) from jsonb_each_text(e->'mix') t) - 1) > 0.000008
        or (select count(*) from jsonb_each_text(e->'mix')) <> v_rolled;
    select f into v_fpay from jsonb_array_elements(world.fleets()) f where f->>'id' = v_fleet::text;
    if v_waters >= 2 and v_bad = 0 and v_i = 0 and v_n = 0
       and v_fpay->'voyage'->'waters' = v_w
       and jsonb_array_length(v_fpay->'voyage'->'waters') = v_waters then
      f_wire := true;
    end if;
    if not f_wire then
      raise exception '0059 self-assert FAIL: the waters do not carry the mix — % run(s), % with no mix object, % disagreeing with voyage.sea_mix, % whose shares do not sum to 1 over all % drawn kinds, and world.fleets served % of them',
        v_waters, v_bad, v_i, v_n, v_rolled,
        jsonb_array_length(coalesce(v_fpay->'voyage'->'waters', '[]'::jsonb));
    end if;

    -------------------------------------------------------------------------------------------
    -- (f) THE FREQUENCY OF EVENT-DAYS DID NOT MOVE. Recomputed INDEPENDENTLY of the deployed
    --     body — DESIGN B.6's clamp and the three rng streams, written out here — and the
    --     deployed voyage.hazard_roll must agree on every day. Comparing against a copy of the
    --     new body would have proved nothing. Weather is forced first (every sea at its CHECK
    --     ceiling, every frozen segment at hazard_mult 10, so p = 0.5 a day) so the sample is not
    --     fifty quiet days.
    -------------------------------------------------------------------------------------------
    update public.seas set hazard_base = 0.0500;
    update public.world_config set value = to_jsonb(1.0) where key = 'hazard_p_max';
    select jsonb_agg(jsonb_set(t.e, '{hazard_mult}', to_jsonb(10.0)) order by t.ord)
      into v_path from jsonb_array_elements(v.path) with ordinality t(e, ord);
    update public.voyages set path = v_path where id = v_voyage;
    select * into v from public.voyages where id = v_voyage;

    v_cap := least(voyage.total_days(v_voyage), 60);
    select count(*) filter (
             where h2.occurred is distinct from (voyage.rng(v_voyage, g, 'occur') < ind.p)
                or h2.magnitude is distinct from round(voyage.rng(v_voyage, g, 'magnitude'), 6)
                or h2.p_hazard  is distinct from round(ind.p, 6)),
           count(*) filter (where h2.occurred),
           count(distinct h2.kind)
      into v_bad, v_occ, v_nkinds
      from generate_series(1, v_cap) g
     cross join lateral (select least(public.wc_num('hazard_p_max'),
                                greatest(0, (select s.hazard_base from public.seas s
                                              where s.id = (voyage.leg_at_day(v_voyage, g)->>'sea_id')::uuid)
                                            * (voyage.leg_at_day(v_voyage, g)->>'hazard_mult')::numeric)) as p) ind
     cross join lateral voyage.hazard_roll(v_voyage, g) h2;
    if v_bad = 0 and v_cap >= 20 and v_occ >= 5 then
      f_freq := true;
    end if;
    if not f_freq then
      raise exception '0059 self-assert FAIL: over % voyage-day(s) the lit draw disagreed with DESIGN B.6''s own arithmetic on % of them about WHETHER something happened, how big it was, or how likely it was (% day(s) carried an encounter, over % distinct kind(s)) — lighting the mix is only allowed to change WHICH thing happens',
        v_cap, v_bad, v_occ, v_nkinds;
    end if;

    -------------------------------------------------------------------------------------------
    -- (g) EVERY ARM FIRES, ON A REAL SETTLED DAY, AND MOVES EXACTLY WHAT IT SAYS IT MOVED. The
    --     weather goes to certainty (hazard_mult 40, so p clamps at 1) and the mix is PINNED to
    --     one kind at a time. No probe here picks its subject by lottery: the day is chosen
    --     because its own kind-draw sits clear of the pinned tail AND its occurrence is read back
    --     from voyage.hazard_roll, and the settled event's kind is then asserted, not hoped for.
    -------------------------------------------------------------------------------------------
    select jsonb_agg(jsonb_set(t.e, '{hazard_mult}', to_jsonb(40.0)) order by t.ord)
      into v_path from jsonb_array_elements(v.path) with ordinality t(e, ord);
    update public.voyages set path = v_path where id = v_voyage;
    select * into v from public.voyages where id = v_voyage;

    foreach v_code in array v_order loop
      -- advance under whatever mix is pinned now until the next day is a clean subject
      v_skip := 0;
      loop
        d := v.last_settled_day + 1;
        select h3.occurred into v_occurs from voyage.hazard_roll(v_voyage, d) h3;
        exit when v_occurs and voyage.rng(v_voyage, d, 'kind') >= 0.01;
        v_skip := v_skip + 1;
        if v_skip > 6 or d > voyage.total_days(v_voyage) - 4 then
          raise exception '0059 self-assert FAIL: no clean day to fire % on within % skip(s) of day % of % — the arm would have been measured through a mix that was not pinned',
            v_code, v_skip, d, voyage.total_days(v_voyage);
        end if;
        perform voyage.settle(v_fleet, voyage.day_ends_at(v_voyage, d));
        select * into v from public.voyages where id = v_voyage;
      end loop;
      if d > voyage.total_days(v_voyage) - 4 then
        raise exception '0059 self-assert FAIL: the probe ran out of passage at day % of % before it could fire % — the arms after it would never have been measured',
          d, voyage.total_days(v_voyage), v_code;
      end if;

      -- PIN THE MIX to this kind alone. mix_base > 0 is a CHECK, so the others go to the smallest
      -- weight numeric(6,4) can hold: seven times 0.0001 against 1.0000 is a tail of 0.0007, and
      -- the day above was chosen to sit clear of it.
      update public.voyage_event_kinds
         set mix_base = case when code = v_code then 1.0000 else 0.0001 end,
             mix_danger = 0, mix_raiders = 0
       where in_sea_mix;

      select coalesce(sum(sh.durability), 0), coalesce(sum(sh.crew), 0), coalesce(sum(sh.water_t), 0),
             md5(coalesce(string_agg(sh.cargo::text, '|' order by sh.id), '')),
             coalesce(sum(least(sh.water_t, sh.crew * public.wc_num('water_per_crew_day'))), 0)
        into v_dur0, v_crw0, v_wat0, v_car0, v_ration
        from public.ships sh where sh.fleet_id = v_fleet;
      select eta, delay_hours into v_eta0, v_del0 from public.voyages where id = v_voyage;

      perform voyage.settle(v_fleet, voyage.day_ends_at(v_voyage, d));
      select * into v from public.voyages where id = v_voyage;
      select * into r_ev from public.voyage_events where voyage_id = v_voyage and day_index = d;
      if r_ev.kind is distinct from v_code or v.last_settled_day <> d then
        raise exception '0059 self-assert FAIL: day % of the probe settled as % with the mix pinned to %, and the voyage stands at day % — the draw is not reading voyage.sea_mix',
          d, coalesce(r_ev.kind, '(nothing)'), v_code, v.last_settled_day;
      end if;

      select coalesce(sum(sh.durability), 0), coalesce(sum(sh.crew), 0), coalesce(sum(sh.water_t), 0),
             md5(coalesce(string_agg(sh.cargo::text, '|' order by sh.id), ''))
        into v_dur1, v_crw1, v_wat1, v_car1
        from public.ships sh where sh.fleet_id = v_fleet;
      select eta, delay_hours into v_eta1, v_del1 from public.voyages where id = v_voyage;

      if v_code = 'CALM' then
        -- 0027's arm, untouched, and it runs first because a fair wind needs hours to give back.
        if coalesce((r_ev.payload->>'delay_hours')::numeric, 0) <= 0 or v_del1 <= v_del0 then
          raise exception '0059 self-assert FAIL: CALM recorded % delay hour(s) and the voyage''s total went % -> % — 0027''s arm is supposed to be untouched by this file',
            r_ev.payload->>'delay_hours', v_del0, v_del1;
        end if;

      elsif v_code = 'FAIR_WIND' then
        if coalesce((r_ev.payload->>'hours_gained')::numeric, 0) <= 0
           or (r_ev.payload->>'delay_hours')::numeric <> -(r_ev.payload->>'hours_gained')::numeric
           or round(v_del0 - v_del1, 3) <> round((r_ev.payload->>'hours_gained')::numeric, 3)
           or v_eta1 >= v_eta0
           or v_del1 < 0
           or voyage.day_ends_at(v_voyage, d + 1) <= voyage.day_ends_at(v_voyage, d) then
          raise exception '0059 self-assert FAIL: FAIR_WIND claimed % hour(s) made up, wrote delay_hours %, moved the voyage''s total from % to % and the arrival from % to %, and left day % ending at % against day %''s % — a fair wind must give back exactly the hours it names, must never drive the total below zero (voyages.delay_hours is CHECK >= 0), must move the arrival EARLIER, and must never fold the schedule so that a later day ends before an earlier one',
            r_ev.payload->>'hours_gained', r_ev.payload->>'delay_hours', v_del0, v_del1, v_eta0, v_eta1,
            d + 1, voyage.day_ends_at(v_voyage, d + 1), d, voyage.day_ends_at(v_voyage, d);
        end if;

      elsif v_code = 'FOUL_WATER' then
        if coalesce((r_ev.payload->>'stores_lost')::numeric, 0) <= 0
           or abs((v_wat0 - v_wat1) - (v_ration + (r_ev.payload->>'stores_lost')::numeric)) > 0.01
           or v_dur1 <> v_dur0 or v_crw1 <> v_crw0 or v_car1 <> v_car0 or v_del1 <> v_del0 then
          raise exception '0059 self-assert FAIL: FOUL_WATER said % tun(s) went over the side, and the fleet''s water went % -> % against a day''s ration of % (hull % -> %, hands % -> %, delay % -> %) — the arm must take exactly what it reports and touch nothing else',
            r_ev.payload->>'stores_lost', v_wat0, v_wat1, v_ration, v_dur0, v_dur1, v_crw0, v_crw1, v_del0, v_del1;
        end if;

      elsif v_code = 'SHOAL_WATER' then
        if coalesce((r_ev.payload->>'hull_lost')::numeric, 0) <= 0
           or round(v_dur0 - v_dur1, 2) <> round((r_ev.payload->>'hull_lost')::numeric, 2)
           or v_crw1 <> v_crw0 or v_car1 <> v_car0 or v_del1 <> v_del0 or v_eta1 <> v_eta0 then
          raise exception '0059 self-assert FAIL: SHOAL_WATER said % point(s) off her hull and the fleet''s durability went % -> % (hands % -> %, delay % -> %, arrival % -> %) — the arm must take exactly the durability it reports and touch nothing else',
            r_ev.payload->>'hull_lost', v_dur0, v_dur1, v_crw0, v_crw1, v_del0, v_del1, v_eta0, v_eta1;
        end if;

      else
        -- DERELICT and CONSORT: 0055's "touch no ship at all". The day's own ration is the only
        -- thing that may have moved, and the schedule may not have moved at all.
        if v_dur1 <> v_dur0 or v_crw1 <> v_crw0 or v_car1 <> v_car0
           or v_del1 <> v_del0 or v_eta1 <> v_eta0
           or jsonb_exists_any(r_ev.payload, array['hull_lost', 'stores_lost', 'delay_hours', 'hours_gained'])
           or abs((v_wat0 - v_wat1) - v_ration) > 0.01 then
          raise exception '0059 self-assert FAIL: % moved something — hull % -> %, hands % -> %, water % -> % against a ration of %, delay % -> %, arrival % -> %, payload % — 0055 authored it to touch no ship at all',
            v_code, v_dur0, v_dur1, v_crw0, v_crw1, v_wat0, v_wat1, v_ration, v_del0, v_del1, v_eta0, v_eta1, r_ev.payload;
        end if;
      end if;

      -- AND IT READS AS A SENTENCE off the payload its own arm wrote. 0055 proved the catalogue's
      -- prose on a hand-built payload; this proves it on the real one.
      v_prose := voyage.report_line(r_ev.day_index, r_ev.kind, r_ev.payload);
      if v_prose !~ ('^Day ' || r_ev.day_index || '\. .') or v_prose ~ '%s' or v_prose ~ '\?' then
        raise exception '0059 self-assert FAIL: % did not read as a sentence out of voyage.report_line on the payload its own arm wrote — got "%"', v_code, v_prose;
      end if;
      v_armed := v_armed + 1;
    end loop;

    if v_armed = array_length(v_order, 1) then f_arms := true; end if;
    if not f_arms then
      raise exception '0059 self-assert FAIL: % of % arm(s) fired on a real settled day', v_armed, array_length(v_order, 1);
    end if;

    -------------------------------------------------------------------------------------------
    -- ...AND A DRAWN KIND WITH NO ARM IS REFUSED RATHER THAN WRITTEN DOWN AS A QUIET WATCH. A
    -- real unarmed kind, drawn on a real day of the real voyage. Without this the §7C guard is a
    -- branch nothing can reach.
    -------------------------------------------------------------------------------------------
    -- ORDER IS LOAD-BEARING, and this is the second thing the probe caught about itself: the
    -- clean day is found FIRST, while the mix still holds only armed kinds. Pinning the unarmed
    -- kind before the search means a skipped day settles it OUTSIDE the handler below, and
    -- E_KIND_ARM — the guard doing exactly its job — escapes as a migration failure. That is a
    -- one-in-a-hundred lottery, and it lost on the third full apply.
    v_skip := 0;
    loop
      d := v.last_settled_day + 1;
      select h3.occurred into v_occurs from voyage.hazard_roll(v_voyage, d) h3;
      exit when v_occurs and voyage.rng(v_voyage, d, 'kind') >= 0.01;
      v_skip := v_skip + 1;
      if v_skip > 6 then
        raise exception '0059 self-assert FAIL: no clean day to draw an unarmed kind on';
      end if;
      perform voyage.settle(v_fleet, voyage.day_ends_at(v_voyage, d));
      select * into v from public.voyages where id = v_voyage;
    end loop;

    insert into public.voyage_event_kinds
      (code, ordinal, is_rolled, prose, note, in_sea_mix, mix_base, mix_danger, mix_raiders)
    values ('PROBE_UNARMED', 92, true, 'A probe.', 'probe', true, 1.0000, 0, 0);
    update public.voyage_event_kinds set mix_base = 0.0001
     where code <> 'PROBE_UNARMED' and in_sea_mix;
    begin
      perform voyage.settle(v_fleet, voyage.day_ends_at(v_voyage, d));
      raise exception 'NO_GUARD_ARM';
    exception when others then
      if sqlerrm ~ 'E_KIND_ARM' then f_guard := true; end if;
    end;
    if not f_guard then
      raise exception '0059 self-assert FAIL: a drawn kind with no arm in voyage.settle was recorded rather than refused — it would have been written down as a quiet watch, the hazard deleted from the game with everything green';
    end if;

    raise exception 'ROLLBACK_0059_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0059_PROBE' then raise; end if;
  end;

  -- THE PROBE LEFT NOTHING BEHIND: the catalogue's coefficients, the world's weather, the houses.
  select md5(string_agg(x, '|' order by x)) into v_kfp1 from (
    select k.code || ':' || k.is_rolled || ':' || k.in_sea_mix || ':'
           || k.mix_base || ':' || k.mix_danger || ':' || k.mix_raiders as x
      from public.voyage_event_kinds k where k.in_sea_mix) q(x);
  select md5(string_agg(x, '|' order by x)) into v_wfp1 from (
    select s.code || ':' || s.hazard_base || ':' || s.piracy_index || ':' || s.danger_level as x
      from public.seas s
    union all select 'knob:' || public.wc_num('hazard_p_max')) w(x);
  if v_kfp0 is distinct from v_kfp1 or v_wfp0 is distinct from v_wfp1 then
    raise exception '0059 self-assert FAIL: the probe left the mix or the world''s weather moved — every kind''s three response numbers, every sea''s hazard rate, piracy index and danger tier, and the hazard clamp, must read exactly as they did before it ran';
  end if;
  select count(*) into v_left from public.players pl where pl.auth_uid = c_probe;
  if v_left <> 0 then
    raise exception '0059 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (h) POSTURE. voyage.hazard_roll's ACL is where 0006 and 0035 left it, nothing this file
  --     touched is reachable by a client, and all four read-wall authorities read zero.
  ---------------------------------------------------------------------------------------------
  select acl into v_acl0 from defs_before_0059 where fn = 'voyage.hazard_roll';
  select p.proacl::text into v_acl1 from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure;
  if v_acl0 is not distinct from v_acl1
     and not has_function_privilege('anon', 'voyage.hazard_roll(uuid, int)', 'execute')
     and not has_function_privilege('authenticated', 'voyage.hazard_roll(uuid, int)', 'execute')
     and not has_function_privilege('anon', 'voyage.sea_mix(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'voyage.sea_mix(uuid)', 'execute')
     and not has_function_privilege('anon', 'voyage.waters_ahead(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'voyage.waters_ahead(uuid)', 'execute')
     and not has_function_privilege('anon', 'world.fleets()', 'execute')
     and has_function_privilege('authenticated', 'world.fleets()', 'execute')
     and not has_table_privilege('anon', 'public.voyage_event_kinds', 'select')
     and not has_table_privilege('authenticated', 'public.voyage_event_kinds', 'select')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0059 self-assert FAIL: the posture moved — voyage.hazard_roll''s ACL changed, or the draw, the mix or the panel became reachable by a client, or a read-wall authority no longer reads zero';
  end if;

  raise notice '0059 self-assert ok: THE MIX IS LIT, AND THE SEA NOW DECIDES WHAT BEFALLS A FLEET IN IT. voyage.hazard_roll''s body IS 0055''s voyage.encounter_at, moved character for character (% chars) and that function DELETED, so there is one draw and not two. The flat weight, the piracy cede and the closure trigger went with it: % kind(s) are drawn, every one of them in the mix and every kind in the mix drawn. MEASURED by walking all % points of [0,1) twice — once through the bands captured one statement before they were deleted, once through the deployed voyage.sea_mix — PIRATES ran % per cent of Mediterranean event-days and now runs % (the Barbary run, cut by rather more than half), the Baltic goes % -> %, Malacca % -> %, the Caribbean % -> % and the Arctic % -> % because mix_raiders needs lawless water and hard water at once; % of % points of the Mediterranean draw now land somewhere other than the flat bands put them. All % seas still answer with all % kinds, every share positive, the shares summing to 1 and the bands closing on exactly 1. THE FREQUENCY DID NOT MOVE: over % voyage-day(s) of a real % nm two-ocean passage the lit draw matched DESIGN B.6''s clamp and the three rng streams, recomputed independently of the deployed body, on every single day — % of those days carried an encounter across % distinct kind(s). Every one of % arms then fired on a REAL settled day with the mix pinned to it: CALM still adds hours, FAIR_WIND gives back exactly the hours it names and never more than the voyage lost (voyages.delay_hours is CHECK >= 0, so an unbounded gain would abort a settlement), FOUL_WATER''s tuns and SHOAL_WATER''s planking each match their own payload to the hundredth with nothing else moved, and DERELICT and CONSORT moved no hull, no hand, no cargo and no hour. Each read back as a sentence out of voyage.report_line on the payload its own arm wrote, with no code edit. A kind with NO arm was then drawn on a real day and REFUSED with E_KIND_ARM rather than written down as a quiet watch. voyage.settle is its pre-image with exactly the three declared hunks made (% inserted characters, everything outside them byte-identical), and sea_mix, report_line, recompute_eta and delay_before_day are byte-identical. The panel''s % run(s) of water carry the mix as a fifth fact, voyage.sea_mix''s own shares, served on world.fleets. The probe left 0 houses and the weather and the coefficients exactly as it found them, and this file grants nothing: 0 client write grants, 0 client-executable writers, 0 read-wall gaps',
    length(v_src1), v_rolled, 10000,
    round(v_pir_med0 * 100, 1), round(v_pir_med1 * 100, 1),
    round(v_pir_bal0 * 100, 1), round(v_pir_bal1 * 100, 1),
    round(v_pir_mal0 * 100, 1), round(v_pir_mal1 * 100, 1),
    round(v_pir_car0 * 100, 1), round(v_pir_car1 * 100, 1),
    round(v_pir_arc0 * 100, 1), round(v_pir_arc1 * 100, 1),
    v_moved, 10000, v_seas_seen, v_rolled,
    v_cap, round(v.total_nm), v_occ, v_nkinds,
    v_armed, length(v_ins), v_waters;
end $$;

drop table defs_before_0059;
drop table kinds_before_0059;
