-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0055 — WHAT THESE WATERS BREED
--        The sea decides what befalls a fleet in it — as ROWS against 0035's catalogue, keyed on
--        the two facts the sea already carries. Landed DARK. And the map learns to say what
--        water still lies ahead, and how far off it is.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ────────────────────────────────────────────────────────────────────────────────────
-- docs/NAVIGATION_PLAN.md:173, step 6 of the plan the owner approved:
--
--   "**Encounters** — the contacts panel with distances. `0035` already made *what befalls a
--    fleet at sea* a table with a foreign key, so the disasters are largely authoring, not
--    machinery."
--
-- and the model it comes from, §2, in the owner's own spec:
--
--   "NPCs distributed by area, with levels. A panel on the map lists nearby contacts and their
--    distance; the player clicks one to engage."
--   "The empty ocean is filled by consequence: attacks, and disasters that take crew, stores, cargo."
--
-- ── THE DEFECT, MEASURED ON THIS CHAIN (PGlite 18.3, 2026-08-25) ───────────────────────────────
-- The sea does not decide anything. `public.seas` carries FOUR spatial facts, and only two of them
-- are ever read, and those two take exactly THREE distinct value-pairs across all 51 seas:
--
--     hazard_base / piracy_index    seas
--     0.0080 / 0.2000                36     Baltic · Yellow Sea · Java Sea · Philippine Sea · …
--     0.0180 / 0.1200                 8     the four oceans, Norwegian, Barents, S Atlantic
--     0.0120 / 0.4500                 7     Mediterranean · Red Sea · Aden · Caribbean · Malacca
--
-- So **71 per cent of the world's water is mechanically the same water.** The Baltic ("calm behind
-- the Sound", danger 1) and the Philippine Sea ("typhoon alley", danger 4) draw from an IDENTICAL
-- bag. The Strait of Malacca — "thick with pirates", the only danger 5 in the game — is arithmetic-
-- for-arithmetic the Mediterranean.
--
-- And `seas.danger_level` (1 home waters … 5 deadly) and `seas.note`, both authored per sea by 0040
-- for exactly this, are **READ BY NO RULE TODAY** — 0040:29-30 says so in the column comment and
-- names *"the NPC/encounter system"* as their reader. `docs/DEV_LOG.md:81` records it. This file is
-- that reader, on both halves: the danger tier decides what the water breeds, and the note and the
-- tier are what the map prints.
--
-- Today's whole spatial variation, worked out from 0035's seed (STORM 0.40 with the 0.40×piracy
-- sub-band ceding to PIRATES, CALM 0.35, PIRATES 0.25):
--
--     piracy   STORM   CALM   PIRATES        seas
--     0.12     35.2%   35.0%   29.8%           8
--     0.20     32.0%   35.0%   33.0%          36
--     0.45     22.0%   35.0%   43.0%           7
--
-- **Three mixes for fifty-one seas, and the calm is 35 % of everything, everywhere.** There is also
-- no such thing as a good day: all three kinds are losses, so every event at sea is a punishment.
--
-- ── THE DECISION, AND WHAT IT IS NOT ───────────────────────────────────────────────────────────
-- `docs/PLATFORM.md` §6 already holds the shape of the answer and its refusal:
--
--   | **per-sea event weights** | `voyage_event_kind_seas (kind_code, sea_id, weight)`, overriding
--   | the flat weight where a row exists … | one flat mix plus `piracy_index` reproduces today
--   | exactly; a second weight table with one row would be machinery ahead of content |
--
-- **That table is REJECTED here, and the reason is the same reason it was refused then.** It is
-- 51 seas × 8 kinds = 408 hand-authored numbers, none of them derived from anything, all of them
-- free to drift away from the danger tier and the piracy index sitting in the same row. That is a
-- SECOND danger scale — the exact thing the brief for this slice forbids — and nothing would make
-- the two agree. `docs/NO_SPAGHETTI.md` §1 question 3: two sites that can print different answers
-- to one question are two authorities even while they agree.
--
-- So the mix is **DERIVED**, and every kind carries its own response to the facts the sea already
-- has. Three columns on the row that already exists, not a table beside it:
--
--     weight(kind, sea) = mix_base × (1 + mix_danger × D + mix_raiders × D × piracy_index)
--     where D = seas.danger_level / 5
--
-- and the shares are those weights normalised. `mix_danger` is *how much harder this thing gets as
-- the water gets harder*; `mix_raiders` is *how much it needs lawless water AND hard water at
-- once*, which is the term that keeps corsairs out of the Arctic — danger 4, piracy 0.12, and a
-- plain piracy term would have put raiders in the pack ice. Coefficients are constrained ≥ 0 and
-- `mix_base > 0`, so **every weight is positive by construction** and the bands can never fail to
-- partition [0,1); no closure trigger is needed for the mix and none is added.
--
-- Also rejected: a second randomness. `voyage.encounter_at` draws from the same three
-- `voyage.rng(voyage, day, stream)` streams `voyage.hazard_roll` draws from, in the same order,
-- with the same occurrence arithmetic. There is one dice cup in this game and it is 0006's.
--
-- Also rejected: an actor. A named corsair band, a raider with a home sea and a standing, is
-- PLATFORM §3 SEAM 2 and it is still not built, because `voyage_events` has no subject column and
-- a subject column with no table to point at is byeharu's four-item ledger of authored-and-unread
-- fields. Which forces an honest correction to the brief, below.
--
-- ── THE CORRECTION: "CONTACTS" CANNOT MEAN SHIPS YET, SO THE PANEL NAMES WATER ─────────────────
-- The plan asks for *"the contacts panel with distances"* and the owner's spec means NPCs. There
-- are no NPCs: seam 2 is unbuilt and this file does not build it. Two dishonest panels were on the
-- table and both are refused:
--
--   * **a panel listing the encounters that WILL happen on the days ahead.** `voyage.hazard_roll`
--     is pure, so this is trivially computable — proof 01 does exactly it to pre-screen a voyage.
--     It is refused twice over. It hands the player the dice, and — measured below, and this is a
--     real property of the chain nobody had written down — **a look-ahead is not even
--     authoritative**: `voyage.leg_at_day` composes `voyage.progress_nm`, which subtracts
--     `voyage.delay_before_day`, which counts events that have not been written yet. Settle sees
--     day d with days < d recorded; a look-ahead sees none of them. The two can disagree for any
--     day whose own event carries delay_hours. Proof 01 is untouched by this (both of its runs
--     settle in the same order), and this file MEASURES the drift and prints the count rather than
--     pretending it is zero.
--   * **a panel showing the per-sea mix this file authors.** The mix is DARK. Printing "these
--     waters breed corsairs" while `voyage.settle` can never produce one is a legible lie.
--
-- What IS true, today, and is frozen at departure so it cannot drift: **which waters her course
-- still has to cross, and how far off each one is.** `voyage.depart` freezes the path, and every
-- segment of it carries its own `sea_id` (0047 §4). So the panel says: the tier, the sea, the
-- distance to it, and the sea's own character in the words 0040 authored. Four facts, one row,
-- no sentence — and the tier it prints is the SAME `seas.danger_level` the mix is keyed on, so
-- when the mix is lit nothing on the panel changes meaning. That is asserted below, not hoped for.
--
-- ── LANDED DARK, AND EXACTLY WHAT LIGHTING IT WOULD BE ─────────────────────────────────────────
-- The eight kinds in the mix include the three that are drawn today, and the five this file
-- authors are `is_rolled = false` — 0035's own retirement switch, whose column comment already
-- says *"Setting a kind is_rolled=false RETIRES it from the draw while keeping it nameable"*.
-- `voyage.hazard_roll` and `voyage.settle` are **NOT TOUCHED** and are asserted byte-identical
-- after this file runs. The rolled set is still exactly {STORM 0.40, CALM 0.35, PIRATES 0.25} and
-- the draw still answers 0006's CASE on 50,000 (r, piracy) pairs. **No voyage yields one ducat,
-- one hull point or one hand differently because this file ran.** That is deliberate: another
-- worktree is measuring what a first voyage returns, and moving the mix under that measurement
-- would invalidate it.
--
-- WHO READS WHAT, TODAY (the takes_effect discipline of 0015/0016/0040 — marked, never implied):
--     seas.danger_level      READ by voyage.sea_mix (dark) AND by voyage.waters_ahead (LIVE)
--     seas.note              READ by voyage.waters_ahead (LIVE) — the map prints it
--     mix_base/danger/raiders READ by voyage.sea_mix only
--     voyage.sea_mix         READ by voyage.encounter_at only
--     voyage.encounter_at    READ BY NOTHING. Named reader: the superseding voyage.hazard_roll of
--                            the lighting slice, below. Asserted to have zero callers.
--
-- **LIGHTING IT IS ONE MIGRATION AND IT IS THESE FOUR STATEMENTS:**
--   1. `create or replace function voyage.hazard_roll` = this file's `voyage.encounter_at` body.
--      (Same signature, same shape, same three streams — it is written to be dropped in.)
--   2. `update public.voyage_event_kinds set is_rolled = true, roll_weight = null where in_sea_mix`
--      …which the 0035 closure trigger forbids, so the same slice must also drop
--      `voyage_event_kinds_weights_close` and `roll_weight`: once the mix is the draw, a flat
--      weight is a second authority and must not survive. (`is_rolled` then means only "drawn".)
--   3. `voyage.settle` gains ONE arm per new kind — five arms. FAIR_WIND subtracts delay hours,
--      FOUL_WATER starts water over the side, SHOAL_WATER takes durability, DERELICT and CONSORT
--      touch no ship at all. The prose needs NO code: every new kind's sentence already comes out
--      of `voyage.report_line` correctly, which this file asserts on real payloads.
--   4. The panel gains the mix as a fifth fact per row, from `voyage.sea_mix`.
--
-- **AND HERE IS WHAT IT WOULD COST A VOYAGE. MEASURED, not estimated** (the figures below are
-- recomputed by this file's own self-assert and printed in its receipt, so they cannot go stale):
--
--     sea (danger, piracy)          PIRATES share   harmful share   distinct mixes
--     home waters   (1, 0.20)      33.0% → 7.0%     65.0% → 51.7%
--     Mediterranean (3, 0.45)      43.0% → 20.4%    65.0% → 64.0%       today  3
--     Caribbean     (4, 0.45)      43.0% → 23.4%    65.0% → 67.3%       lit   10
--     Malacca       (5, 0.45)      43.0% → 25.8%    65.0% → 70.0%
--
-- In one sentence: **lighting it would cut raid-days on the Barbary run by rather more than half
-- (43.0 % of event-days to 20.4 %), and cut them by nearly four fifths in home waters, while
-- making the Malacca run measurably worse than the Baltic for the first time.** The frequency of
-- event-days does not move at all — `hazard_base × hazard_mult`, clamped, is untouched, exactly as
-- 0035 left it: this changes WHICH thing happens, never HOW OFTEN something does.
--
-- ── WHAT THIS FILE SUPERSEDES ──────────────────────────────────────────────────────────────────
-- ONE function: `world.fleets()` (0009, re-cut 0017, 0028, 0047), by ONE sliced hunk that adds
-- `'waters'` to the voyage object it already serves and changes nothing else. The slice is proven
-- to be exactly that: the deployed definition after this file must equal the deployed definition
-- before it with that one insertion made, byte for byte. Its ACL is re-issued explicitly (0018's
-- lesson) and asserted unmoved. Nothing else in the chain is re-cut — in particular
-- `voyage.hazard_roll`, `voyage.settle` and `voyage.report_line` are asserted byte-identical.
--
-- ── AND ONE PROOF GROWS WITH IT ────────────────────────────────────────────────────────────────
-- `scripts/db/proofs/01_offline_equivalence.sql` gains a sixth marker, OFFLINE_EQUIV_ENCOUNTER:
-- the same voyage, settled tick-by-tick and settled lazily nine hours late, must get the same
-- answer out of `voyage.encounter_at` as well as the same voyage_events. That is the property
-- `docs/NAVIGATION_PLAN.md:149` says the whole game rests on, gated by the slice that AUTHORED the
-- dark function rather than by the slice that lights it — a self-assert proves a thing once, on
-- the day it lands; a proof re-proves it on every run for as long as it lives. The probe below
-- proves the same purity a second way (the voyage moved 600 hours through the clock), because a
-- rolled-back probe can force weather that a proof's real voyage cannot.
--
-- ── WHAT IT DELIBERATELY DOES NOT TOUCH ────────────────────────────────────────────────────────
--   * `voyage.settle`, `voyage.hazard_roll`, `voyage.report_line`, `voyage.rng` — see above.
--   * The hazard PROBABILITY, and `voyages.speed_profile`. Wind is step 5 and is not in this slice.
--   * `voyage_events`' primary key. One beat per day is what makes offline settlement idempotent
--     (PLATFORM §3 seam 3); widening it belongs to the slice that first needs a second beat.
--   * An actor / subject column (seam 2), and `voyage_event_kind_seas` (rejected above).
--   * `seas.hazard_base` and `seas.piracy_index`. Their three-valued flatness is the defect this
--     file works AROUND rather than re-authors: re-pricing 51 seas' hazard rates is a balance
--     change and this file is dark on purpose.
--
-- Depends ONLY on: 0035 (voyage_event_kinds, report_line, the FK), 0040 (seas.danger_level,
--                  seas.note, voyage.sea_at), 0047 (voyage.depart's frozen segments carrying
--                  sea_id, voyage.progress_nm over them, the sliced world.fleets), 0006
--                  (voyage.rng, leg_at_day, hazard_roll), 0050 (nothing is re-cut; named because
--                  the probe issues orders through cmd.issue and reads its refusals).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse (0047 §0, 0050 §0)
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
      raise exception '0055 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── PRE-IMAGES. "Nothing else moved" is a comparison, never a sentence (NO_SPAGHETTI §3.3). ────
create temporary table defs_before_0055 as
  select 'world.fleets'::text as fn,
         pg_get_functiondef('world.fleets()'::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = 'world.fleets()'::regprocedure) as acl
  union all
  select 'voyage.hazard_roll',
         pg_get_functiondef('voyage.hazard_roll(uuid, int)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure)
  union all
  select 'voyage.settle',
         pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.settle(uuid, timestamptz)'::regprocedure)
  union all
  select 'voyage.report_line',
         pg_get_functiondef('voyage.report_line(int, text, jsonb)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure);

-- ── 1. THE CATALOGUE LEARNS HOW EACH KIND ANSWERS THE WATER ───────────────────────────────────
-- WHAT CONCEPT (NO_SPAGHETTI §7B q1): "how much of this sea's trouble is THIS kind of trouble."
-- WHERE IT LIVES AND WHY (q2): on `public.voyage_event_kinds`, the row that already owns
--   everything else about a kind — whether it is drawn, what it cedes to, and the sentence the
--   player reads. A sibling table keyed on (kind, sea) is refused in the header.
-- WHO THE SECOND CALLER IS (q3): `voyage.sea_mix` today; `voyage.hazard_roll` on the day the
--   lighting slice above runs, and it is the SAME three numbers — no second authoring pass.
-- WHAT WOULD MAKE IT THE WRONG SHAPE (q4): a kind whose share must depend on something the sea
--   does not carry — a season, a latitude, a war. The tell is anyone adding a fourth coefficient
--   here instead of adding the FACT to `public.seas` and one coefficient for it. Per-SEGMENT
--   shelter (`path[i].hazard_mult`, 0047 §4: land within two cells 0.8, none within seven 1.2) is
--   the named next dimension and it is deliberately not taken now: it would make the mix a
--   function of the segment rather than the sea, and nothing needs that yet.
alter table public.voyage_event_kinds
  add column in_sea_mix  boolean not null default false,
  add column mix_base    numeric(6,4),
  add column mix_danger  numeric(6,4),
  add column mix_raiders numeric(6,4);

comment on column public.voyage_event_kinds.in_sea_mix is
  '0055: this kind is part of what a SEA breeds — the draw voyage.sea_mix normalises. Every kind '
  'that is_rolled must be in it (constraint), and CONDITIONS (CLEAR, SHORT_RATIONS, LANDFALL) '
  'never are. READ BY voyage.sea_mix, which is READ BY voyage.encounter_at, which is READ BY '
  'NOTHING TODAY (2026-08-25) — the takes_effect discipline of 0015/0016/0040. Named reader: the '
  'superseding voyage.hazard_roll named in 0055''s header.';
comment on column public.voyage_event_kinds.mix_base is
  '0055: this kind''s raw weight BEFORE the water is taken into account — the weight at D = 0, '
  'which no real sea is (the gentlest in the game is danger 1, D = 0.2), so it is a scale rather '
  'than a sea''s figure. Positive, which is what makes every sea''s bands partition [0,1) by '
  'construction rather than by a trigger.';
comment on column public.voyage_event_kinds.mix_danger is
  '0055: how much this kind''s weight grows with seas.danger_level / 5 — 0040''s authored tier, '
  'and the SAME number the map prints beside the sea''s name (voyage.waters_ahead).';
comment on column public.voyage_event_kinds.mix_raiders is
  '0055: how much this kind''s weight grows with danger AND piracy TOGETHER '
  '(danger_level/5 × piracy_index). Raiders need lawless water and hard water at once; a plain '
  'piracy term would have put corsairs in the Arctic (danger 4, piracy 0.12).';

-- ── 2. THE THREE THAT ARE DRAWN TODAY GET THEIR RESPONSES — and nothing else about them moves ──
-- roll_weight, cedes_to and cede_fraction are UNTOUCHED, which is why the live draw is a no-op.
update public.voyage_event_kinds set in_sea_mix = true,
  mix_base = 0.3000, mix_danger = 1.2000, mix_raiders =  0.0000 where code = 'STORM';
update public.voyage_event_kinds set in_sea_mix = true,
  mix_base = 0.2600, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'CALM';
update public.voyage_event_kinds set in_sea_mix = true,
  mix_base = 0.0350, mix_danger = 0.0000, mix_raiders = 30.0000 where code = 'PIRATES';

-- ── 3. THE CONTENT — five things that can befall a fleet, authored as rows ─────────────────────
-- Age of sail, and each one chosen because the WATER decides it, not because a list wanted five
-- entries. `is_rolled = false`: they are in the mix and out of the draw, so the game is unchanged
-- until the lighting slice. Every one of them reads correctly out of `voyage.report_line` with no
-- code edit — which is the claim NAVIGATION_PLAN:173 makes about 0035, and this file proves it on
-- real payloads rather than repeating it.
--
-- Ordinals start at 11, leaving 6-10 free: LANDFALL took 6 in 0036 and two other worktrees are
-- authoring against this chain. A collision would fail this migration loudly, which is correct;
-- the gap makes it unlikely.
insert into public.voyage_event_kinds
  (code, ordinal, is_rolled, roll_weight, cedes_to, cede_fraction,
   in_sea_mix, mix_base, mix_danger, mix_raiders, prose, prose_keys, prose_fallbacks, note)
values
  ('FAIR_WIND', 11, false, null, null, null,
   true, 0.1300, 0.0000, 0.0000,
   'A soldier''s wind all day, and she ran her easting down. We made up %s hours.',
   array['hours_gained'], array['?'],
   '0055. THE FIRST GOOD DAY AT SEA: before this row every kind in the catalogue was a loss, so an '
   'event was always a punishment. Flat in danger and piracy, so its SHARE is highest exactly '
   'where nothing else is growing — the gentle water a starter sails. Its settle arm subtracts '
   'delay hours, the mirror of CALM''s.'),

  ('CONSORT', 12, false, null, null, null,
   true, 0.1000, 0.0000, 0.0000,
   'We spoke a sail on the other tack and swapped what news we had.',
   '{}', '{}',
   '0055. The empty ocean stops being empty. Flat, like FAIR_WIND, so company is a home-waters '
   'thing by share. It touches no ship at all today; when PLATFORM seam 2 gives an event a '
   'SUBJECT this is the row that gets a name attached to it first, because it is the only one '
   'that is already about meeting somebody.'),

  ('DERELICT', 13, false, null, null, null,
   true, 0.0350, 0.5000, 3.0000,
   'A hull lay low in the water, abandoned. We took what we could off her: %s.',
   array['salvage'], array['a little cordage'],
   '0055. Hard water and lawless water both leave wrecks, so it answers to danger and to raiders '
   'together — a derelict in the Malacca Strait had help. 0035''s own worked example of "a kind '
   'nobody named cannot be written" used this code for its rejected insert; it is a real row now.'),

  ('FOUL_WATER', 14, false, null, null, null,
   true, 0.0500, 1.4000, 0.0000,
   'The casks were broached and the water in them had turned. We started %s tuns over the side.',
   array['stores_lost'], array['?'],
   '0055. The commonest disaster of a long passage, and the one this game''s stores rule already '
   'has a place for: it takes water_t, so a fleet''s endurance — the thing every SAIL is gated on '
   '— is what a bad sea actually costs. Answers to danger alone: hard water means long crossings.'),

  ('SHOAL_WATER', 15, false, null, null, null,
   true, 0.0500, 0.8000, 0.0000,
   'She touched on ground that was on no chart, and came off with %s points off her hull.',
   array['hull_lost'], array['?'],
   '0055. Grounding killed more ships than gunfire. It reuses STORM''s `hull_lost` payload key '
   'deliberately: one payload vocabulary, so the report reads the same way whatever took the '
   'planking. Answers to danger — reefs and shoal water are half the danger-3 notes 0040 wrote.');

-- ── 3b. THE GUARDS, added once the rows they judge exist ───────────────────────────────────────────
-- They come AFTER the seed on purpose: `alter table ... add constraint` VALIDATES against every
-- row already there, so adding them first would have refused the three kinds this file is about
-- to put into the mix. Adding them here means they are checked against the finished catalogue.
alter table public.voyage_event_kinds
  add constraint voyage_event_kinds_mix_is_all_or_nothing
    check (in_sea_mix = (mix_base is not null and mix_danger is not null and mix_raiders is not null)),
  add constraint voyage_event_kinds_mix_base_is_positive
    check (mix_base is null or (mix_base > 0 and mix_base <= 1)),
  -- ≥ 0 IS LOAD-BEARING, not tidiness: with a positive base and non-negative responses every
  -- weight is ≥ mix_base > 0 for every sea, so the normalised bands always partition [0,1) and
  -- the draw can never fall off the end. A negative coefficient would make that a runtime lottery.
  add constraint voyage_event_kinds_mix_responses_are_not_negative
    check ((mix_danger is null or mix_danger >= 0) and (mix_raiders is null or mix_raiders >= 0)),
  -- A kind that is DRAWN TODAY must survive the lighting slice. Without this, setting is_rolled
  -- without in_sea_mix would silently delete a hazard from the game on the day the mix goes live.
  add constraint voyage_event_kinds_rolled_is_in_the_mix
    check (not is_rolled or in_sea_mix);

-- ── 4. THE MIX — what this sea breeds, as shares that partition [0,1) ─────────────────────────
create or replace function voyage.sea_mix(p_sea uuid)
returns table (kind_code text, share numeric, cum_share numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- THE one reading of "what does this water breed". Pure in (sea, catalogue): no clock, no voyage,
-- no player. The bands are cumulative in `ordinal` order, exactly as 0035's flat draw is, so the
-- same rng stream keeps answering in the same direction.
declare
  v_d   numeric;
  v_p   numeric;
  v_tot numeric;
begin
  select s.danger_level::numeric / 5, s.piracy_index into v_d, v_p
    from public.seas s where s.id = p_sea;
  -- NO_SPAGHETTI §7C: the alternative is an empty mix, and an empty mix is a draw with no answer
  -- three frames later. If the else is unacceptable it is not a branch.
  if v_d is null then
    raise exception 'E_NO_SEA_MIX: % names no sea, so what its water breeds has no answer',
      coalesce(p_sea::text, '(null)') using errcode = 'P0001';
  end if;

  select sum(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p))
    into v_tot from public.voyage_event_kinds k where k.in_sea_mix;
  if v_tot is null or v_tot <= 0 then
    raise exception 'E_NO_SEA_MIX: no kind is in the sea mix, so every hazard roll would fall off the end of the bands'
      using errcode = 'P0001';
  end if;

  return query
    select k.code,
           round(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p) / v_tot, 6),
           round(sum(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p))
                   over (order by k.ordinal rows between unbounded preceding and current row)
                 / v_tot, 6)
      from public.voyage_event_kinds k
     where k.in_sea_mix
     order by k.ordinal;
end $$;

revoke all on function voyage.sea_mix(uuid) from public, anon, authenticated;

comment on function voyage.sea_mix(uuid) is
  '0055: THE per-sea encounter mix — one share per kind, cumulative, partitioning [0,1). Derived '
  'from seas.danger_level and seas.piracy_index through each kind''s own three response numbers; '
  'there is no per-(kind, sea) weight table and there must never be one, or the sea would carry '
  'two danger scales. READ BY voyage.encounter_at ONLY, which is READ BY NOTHING today.';

-- ── 5. THE ENCOUNTER — the pure function the lighting slice drops into voyage.hazard_roll ──────
create or replace function voyage.encounter_at(p_voyage uuid, p_day int)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- A PURE FUNCTION OF (voyage, day, world secret) AND OF NOTHING ELSE — which is the property the
-- whole game rests on: `docs/NAVIGATION_PLAN.md:149`, "it is why a voyage settles while the player
-- is asleep". It reads no clock: `voyage.rng` wraps the IMMUTABLE `voyage.rng_raw`, so PostgreSQL
-- itself forbids the seed from becoming time-dependent, and `voyage.leg_at_day` is a function of
-- the FROZEN path. This body is deliberately shaped so the lighting slice can `create or replace
-- function voyage.hazard_roll` with it unchanged: same signature, same returned columns, the same
-- three streams drawn in the same order.
--
-- THE ONE THING THAT DIFFERS from voyage.hazard_roll: the kind comes from voyage.sea_mix instead
-- of from the flat bands, and there is NO cede. The cede exists in 0035 only because the flat mix
-- could not say "this water breeds raiders"; the mix says it directly, so a second mechanism for
-- the same sentence would be a second authority.
declare
  v_leg   jsonb;
  v_sea   uuid;
  v_base  numeric;
  v_p     numeric;
  r_occur numeric;
  r_kind  numeric;
  r_mag   numeric;
begin
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
  select s.hazard_base into v_base from public.seas s where s.id = v_sea;

  -- THE PROBABILITY IS 0006'S, UNCHANGED, to the character. This file changes WHICH thing
  -- happens, never HOW OFTEN something does.
  v_p := least(public.wc_num('hazard_p_max'),
               greatest(0, v_base * (v_leg->>'hazard_mult')::numeric));

  r_occur := voyage.rng(p_voyage, p_day, 'occur');
  r_kind  := voyage.rng(p_voyage, p_day, 'kind');
  r_mag   := voyage.rng(p_voyage, p_day, 'magnitude');

  occurred  := r_occur < v_p;
  p_hazard  := round(v_p, 6);
  magnitude := round(r_mag, 6);

  if not occurred then
    kind := null;
    return next;
    return;
  end if;

  select m.kind_code into kind
    from voyage.sea_mix(v_sea) m
   where r_kind < m.cum_share
   order by m.cum_share
   limit 1;

  if kind is null then
    raise exception 'E_SEA_MIX_BAND: no band of sea %''s mix holds r=% — the shares do not partition [0,1)',
      v_sea, r_kind using errcode = 'P0001';
  end if;

  return next;
end $$;

revoke all on function voyage.encounter_at(uuid, int) from public, anon, authenticated;

comment on function voyage.encounter_at(uuid, int) is
  '0055: what befalls a fleet on a voyage-day when the SEA decides the mix. Pure in (voyage, day, '
  'world secret): the occurrence, the magnitude and the probability are voyage.hazard_roll''s to '
  'the character; only the choice of kind reads voyage.sea_mix, and the piracy cede is gone '
  'because the mix says it directly. READ BY NOTHING TODAY (2026-08-25) — it is written to BE '
  'voyage.hazard_roll''s next body, and 0055''s header names the four statements that lighting is.';

-- ── 6. THE WATERS SHE STILL HAS TO CROSS ──────────────────────────────────────────────────────
create or replace function voyage.waters_ahead(p_voyage uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- ONE ROW PER SEA her stored course still runs through, in sailing order, with the distance she
-- must still make good before she enters it. Every fact here is FROZEN AT DEPARTURE except her own
-- progress: `voyage.depart` stores the verified segments and 0047 §4 writes each one's `sea_id`
-- into them, so the list of waters and their lengths cannot drift while she sails.
--
-- IT PREDICTS NOTHING. No rng stream is touched here and no future day is evaluated — see this
-- migration's header for the measurement that makes that more than good manners: a look-ahead of
-- voyage.hazard_roll is not authoritative, because voyage.leg_at_day subtracts delays that have
-- not been recorded yet. What this returns is the map, not the dice.
declare
  v        public.voyages%rowtype;
  v_done   numeric;
  v_acc    numeric := 0;
  e        jsonb;
  v_sea    uuid;
  v_seas   uuid[]    := '{}';
  v_from   numeric[] := '{}';
  v_to     numeric[] := '{}';
  i        int;
  v_out    jsonb := '[]'::jsonb;
  s        public.seas%rowtype;
begin
  select * into v from public.voyages where id = p_voyage;
  if v.id is null then
    raise exception 'E_NO_SUCH_VOYAGE: %', p_voyage using errcode = 'P0001';
  end if;
  v_done := voyage.progress_nm(p_voyage);

  -- Pass one: fold the segments into RUNS of one water. A 3,700 nm crossing is ~30 segments and
  -- two seas; the player wants the two.
  for e in select * from jsonb_array_elements(v.path) loop
    v_sea := (e->>'sea_id')::uuid;
    if array_length(v_seas, 1) is null or v_seas[array_length(v_seas, 1)] is distinct from v_sea then
      v_seas := v_seas || v_sea;
      v_from := v_from || v_acc;
      v_to   := v_to   || v_acc;
    end if;
    v_acc := v_acc + (e->>'nm')::numeric;
    v_to[array_length(v_to, 1)] := v_acc;
  end loop;

  -- Pass two: emit the runs she has not finished with. ONE emitter, so a run's shape is stated
  -- once (the two-copies-of-one-emitter shape is how a "flush the last run" bug is written).
  for i in 1 .. coalesce(array_length(v_seas, 1), 0) loop
    continue when v_to[i] <= v_done;
    select * into s from public.seas where id = v_seas[i];
    -- NO_SPAGHETTI §7C: the alternative is a row on the map naming no water and carrying no
    -- tier — the "Day 7. DERELICT" defect 0035 deleted, one layer out. It cannot happen for any
    -- course this chain can create (voyage.segments_from_course raises E_NO_SEA at departure
    -- rather than freezing a segment with no sea), so if it ever does it is a world defect and
    -- must say so rather than be drawn.
    if s.id is null then
      raise exception 'E_NO_SEA: segment % of voyage % is frozen against sea %, which no row of public.seas holds', i, p_voyage, v_seas[i]
        using errcode = 'P0001';
    end if;
    v_out := v_out || jsonb_build_object(
      'sea',    s.code,
      'name',   s.name,
      -- 0040's authored tier, and the SAME column voyage.sea_mix is keyed on: what the player is
      -- shown and what decides her weather are one number, or they are two authorities.
      'danger', s.danger_level,
      'note',   s.note,
      'nm_to',  round(greatest(0, v_from[i] - v_done), 1),
      'nm_in',  round(v_to[i] - greatest(v_from[i], v_done), 1),
      'now',    v_from[i] <= v_done);
  end loop;

  return v_out;
end $$;

revoke all on function voyage.waters_ahead(uuid) from public, anon, authenticated;

comment on function voyage.waters_ahead(uuid) is
  '0055: the seas this voyage''s frozen course still has to cross, in order, each with the '
  'distance she must still make good to reach it, its 0040 danger tier and its character. Served '
  'on world.fleets().voyage.waters and drawn by the map. Composed, never granted: the client '
  'reaches it only through world.fleets, which is SECURITY DEFINER and already hers.';

-- ── 7. THE WIRE — world.fleets serves it, by ONE hunk ─────────────────────────────────────────
-- SUPERSEDES 0028:186, as last sliced by 0047 §12. The hunk must occur EXACTLY ONCE in the
-- DEPLOYED definition or this migration refuses: a drifted deployment fails rather than
-- half-applies. Nothing is retyped; the assert below proves the whole body is the pre-image with
-- exactly this insertion made.
select pg_temp.recut('world.fleets()'::regprocedure, false,
  $wo$                 'nm_done', voyage.progress_nm(v.id),
                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))$wo$,
  $wn$                 'nm_done', voyage.progress_nm(v.id),
                 -- 0055: THE WATERS SHE STILL HAS TO CROSS. Frozen at departure, so it cannot
                 -- drift; it evaluates no future day and touches no rng stream (see
                 -- voyage.waters_ahead). The map draws it beside her name.
                 'waters', voyage.waters_ahead(v.id),
                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))$wn$);

-- An assumed grant is how a read wall came down in 0018 and had to be rebuilt in 0023. Re-issued
-- explicitly, and asserted unmoved below.
revoke all on function world.fleets() from public, anon;
grant execute on function world.fleets() to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe  constant uuid := '00000000-0055-4000-8000-000000000001';
  -- The Lisbon → Salvador course 0047 §j proves is real water and really departs. A DATA literal,
  -- not a copied rule: this file re-uses the fixture rather than inventing a second one that would
  -- have to be re-verified against the raster.
  v_course_sal constant jsonb := '[[38.71,-9.14],[-9.625,-35.125],[-12.625,-37.875],[-12.98,-38.49]]'::jsonb;
  v_player uuid; v_fleet uuid; v_voyage uuid; v_res jsonb;
  v        public.voyages%rowtype;
  v_days   int; v_cap int; d int;
  v_bal    uuid; v_mal uuid; v_med uuid; v_arc uuid;
  v_path   jsonb;
  v_n      int; v_i int;
  v_sum    numeric; v_last numeric; v_min numeric;
  v_seas_seen int; v_distinct_mix int; v_distinct_today int;
  v_pir_bal numeric; v_pir_mal numeric; v_pir_med numeric; v_pir_arc numeric;
  v_bad    int; v_kinds int;
  v_sweep_bad int; v_sweep_n int; v_sweep_cede int; v_sweep_kinds int;
  v_before text; v_after text; v_acl0 text; v_acl1 text;
  v_occ    int := 0; v_drift int := 0; v_nkinds int;
  v_sig0   text; v_sig1 text;
  v_w      jsonb; v_fpay jsonb;
  v_nm_sum numeric; v_prog numeric;
  v_left   int;
  v_prose  text;
  v_readers int;
  v_w0     text; v_w1 text;
  r        record;
  f_mix    boolean := false;
  f_vary   boolean := false;  f_pure    boolean := false;
  f_water  boolean := false;  f_wire    boolean := false;
  f_dark   boolean := false;  f_prose   boolean := false;
  f_slice  boolean := false;  f_grant   boolean := false;
  f_guard  boolean := false;
begin
  ---------------------------------------------------------------------------------------------
  -- (a) THE SLICE IS EXACTLY ONE INSERTION. The whole deployed body of world.fleets, after,
  --     must equal the body before with the hunk replaced — byte for byte. A no-op proof that
  --     only reads the new key would pass while the rest of the payload had been rewritten.
  ---------------------------------------------------------------------------------------------
  select def into v_before from defs_before_0055 where fn = 'world.fleets';
  v_after := pg_get_functiondef('world.fleets()'::regprocedure);
  if v_before is null or position('''waters'', voyage.waters_ahead(v.id),' in v_before) > 0 then
    raise exception '0055 self-assert FAIL: the pre-image of world.fleets is missing, or it already served the waters — this migration was generated against a different chain';
  end if;
  if v_after = replace(v_before,
      E'                 ''nm_done'', voyage.progress_nm(v.id),\n                 ''position'', (select to_jsonb(pos) from voyage.position(v.id) pos))',
      E'                 ''nm_done'', voyage.progress_nm(v.id),\n                 -- 0055: THE WATERS SHE STILL HAS TO CROSS. Frozen at departure, so it cannot\n                 -- drift; it evaluates no future day and touches no rng stream (see\n                 -- voyage.waters_ahead). The map draws it beside her name.\n                 ''waters'', voyage.waters_ahead(v.id),\n                 ''position'', (select to_jsonb(pos) from voyage.position(v.id) pos))')
  then
    f_slice := true;
  end if;
  if not f_slice then
    raise exception '0055 self-assert FAIL: world.fleets after this file is not its pre-image with exactly the one waters hunk inserted — something else in the roster payload moved';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (b) THE DRAW IS UNMOVED — the three bodies that decide what a voyage yields are byte-
  --     identical, and the live draw still answers 0006's CASE over 50,000 (r_kind, piracy)
  --     pairs. This is the whole promise that this file costs a voyage nothing.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from defs_before_0055 b
   where b.fn in ('voyage.hazard_roll', 'voyage.settle', 'voyage.report_line')
     and b.def is distinct from pg_get_functiondef(
           case b.fn when 'voyage.hazard_roll' then 'voyage.hazard_roll(uuid, int)'::regprocedure
                     when 'voyage.settle'      then 'voyage.settle(uuid, timestamptz)'::regprocedure
                     else 'voyage.report_line(int, text, jsonb)'::regprocedure end);
  if v_n <> 0 then
    raise exception '0055 self-assert FAIL: % of the three outcome bodies (hazard_roll, settle, report_line) changed — this file is supposed to leave what a voyage YIELDS byte-identical', v_n;
  end if;

  with sample as (
    select i::numeric / 10000 as r, p.v as piracy
      from generate_series(0, 9999) i
      cross join (values (0.0000), (0.1200), (0.2000), (0.4500), (1.0000)) as p(v)
  ),
  old as (
    select s.r, s.piracy,
           case
             when (case when s.r < 0.40 then 'STORM' when s.r < 0.75 then 'CALM' else 'PIRATES' end) = 'STORM'
                  and s.r < 0.40 * s.piracy then 'PIRATES'
             else (case when s.r < 0.40 then 'STORM' when s.r < 0.75 then 'CALM' else 'PIRATES' end)
           end as kind
      from sample s
  ),
  drawn as (
    select s.r, s.piracy,
           (select k.code
              from (select c.code, c.ordinal,
                           sum(c.roll_weight) over (order by c.ordinal
                                                    rows between unbounded preceding and current row) as cum
                      from public.voyage_event_kinds c where c.is_rolled) k
             where s.r < k.cum order by k.ordinal limit 1) as code
      from sample s
  ),
  new as (
    select d2.r, d2.piracy,
           case when kk.cedes_to is not null and d2.r < kk.cede_fraction * d2.piracy
                then kk.cedes_to else d2.code end as kind
      from drawn d2 join public.voyage_event_kinds kk on kk.code = d2.code
  )
  select count(*) filter (where o.kind is distinct from n2.kind),
         count(*),
         count(*) filter (where o.kind = 'PIRATES' and o.r < 0.40),
         count(distinct o.kind)
    into v_sweep_bad, v_sweep_n, v_sweep_cede, v_sweep_kinds
    from old o join new n2 on n2.r = o.r and n2.piracy = o.piracy;

  if v_sweep_bad <> 0 or v_sweep_n <> 50000 or v_sweep_cede = 0 or v_sweep_kinds <> 3 then
    raise exception '0055 self-assert FAIL: the LIVE flat draw no longer answers 0006''s CASE on % of % pairs (cedes seen %, distinct kinds %) — five new rows in the catalogue have changed what happens at sea',
      v_sweep_bad, v_sweep_n, v_sweep_cede, v_sweep_kinds;
  end if;

  select count(*) into v_n from public.voyage_event_kinds where is_rolled;
  select coalesce(sum(roll_weight), 0) into v_sum from public.voyage_event_kinds where is_rolled;
  if v_n <> 3 or v_sum <> 1 then
    raise exception '0055 self-assert FAIL: % kind(s) are rolled and their weights sum to % — the five new kinds must be DARK (is_rolled = false) and the mix must still be 3 x weight 1', v_n, v_sum;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (c) THE GUARDS BITE. Two real rejected writes, in subtransactions: a kind cannot be drawn
  --     without being in the mix (or lighting would delete a hazard), and a response cannot be
  --     negative (or some sea's bands would not partition [0,1)).
  ---------------------------------------------------------------------------------------------
  begin
    insert into public.voyage_event_kinds (code, ordinal, is_rolled, roll_weight, in_sea_mix, prose, note)
    values ('ORPHAN_ROLL', 91, true, 0.0001, false, 'probe.', 'probe');
    raise exception 'NO_GUARD_ROLLED';
  exception when others then
    if sqlerrm ~ 'voyage_event_kinds_rolled_is_in_the_mix' then f_guard := true; end if;
  end;
  if not f_guard then
    raise exception '0055 self-assert FAIL: a ROLLED kind was accepted while out of the sea mix — lighting the mix would then silently delete it from the game';
  end if;
  f_guard := false;
  begin
    update public.voyage_event_kinds set mix_danger = -0.5 where code = 'CALM';
    raise exception 'NO_GUARD_SIGN';
  exception when others then
    if sqlerrm ~ 'voyage_event_kinds_mix_responses_are_not_negative' then f_guard := true; end if;
  end;
  if not f_guard then
    raise exception '0055 self-assert FAIL: a negative mix response was accepted — a weight could then go to zero or below and some sea''s draw would fall off the end of its own bands';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (d) THE MIX IS TOTAL. Every one of the world's seas answers, with every kind, all shares
  --     positive, closing on exactly 1. Non-vacuous by count: the sea count is asserted.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_seas_seen from public.seas;
  select count(*), min(x.n), min(x.lo), max(abs(x.hi - 1)), max(abs(x.tot - 1))
    into v_n, v_i, v_min, v_sum, v_last
    from (select s.id,
                 (select count(*) from voyage.sea_mix(s.id))                       as n,
                 (select min(m.share) from voyage.sea_mix(s.id) m)                 as lo,
                 (select max(m.cum_share) from voyage.sea_mix(s.id) m)             as hi,
                 -- BOTH readings, because they can disagree: the cumulative band closing on 1
                 -- says the DRAW cannot fall off the end; the shares summing to 1 says the shares
                 -- ARE the bands. A mix that satisfies only the first is a legible, wrong answer
                 -- to "how often does this happen here", and the panel would print it.
                 (select sum(m.share) from voyage.sea_mix(s.id) m)                 as tot
            from public.seas s) x;
  if v_n = v_seas_seen and v_seas_seen >= 51 and v_i = 8 and v_min > 0
     and v_sum = 0 and v_last <= 0.000008 then
    f_mix := true;
  end if;
  if not f_mix then
    raise exception '0055 self-assert FAIL: the mix is not total over the world''s water — % of % sea(s) answered, fewest kinds %, smallest share %, worst band-closure error %, worst share-sum error % (every sea must return all 8 kinds, all shares > 0, the shares summing to 1 and the bands closing on exactly 1)',
      v_n, v_seas_seen, v_i, v_min, v_sum, v_last;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (e) AND IT ACTUALLY VARIES BY WHERE SHE IS — the defect this file exists to close. Today
  --     the world has THREE mixes; measured, printed, and required to have grown.
  ---------------------------------------------------------------------------------------------
  select id into v_bal from public.seas where code = 'BAL';
  select id into v_mal from public.seas where code = 'STR';
  select id into v_med from public.seas where code = 'MED';
  select id into v_arc from public.seas where code = 'ARC';
  if v_bal is null or v_mal is null or v_med is null or v_arc is null then
    raise exception '0055 self-assert FAIL: the probe cannot find the seas it measures against (BAL/STR/MED/ARC) — the world data moved under this file';
  end if;

  select count(distinct sig) into v_distinct_mix from (
    select (select string_agg(m.kind_code || ':' || m.share, ',' order by m.kind_code)
              from voyage.sea_mix(s.id) m) as sig
      from public.seas s) q;
  -- today's flat mix is a pure function of piracy_index alone (0035's seed + the cede)
  select count(distinct s.piracy_index) into v_distinct_today from public.seas s;

  select m.share into v_pir_bal from voyage.sea_mix(v_bal) m where m.kind_code = 'PIRATES';
  select m.share into v_pir_mal from voyage.sea_mix(v_mal) m where m.kind_code = 'PIRATES';
  select m.share into v_pir_med from voyage.sea_mix(v_med) m where m.kind_code = 'PIRATES';
  select m.share into v_pir_arc from voyage.sea_mix(v_arc) m where m.kind_code = 'PIRATES';

  -- AND IT IS A DIFFERENT DRAW, densely and deterministically: walk the whole [0,1) line at
  -- Malacca and count how much of it the mix sends somewhere other than 0035's flat bands (cede
  -- included). Without this the two could differ by a rounding error and every share assert above
  -- would still pass.
  with mix as (select m.kind_code, m.cum_share from voyage.sea_mix(v_mal) m),
       line as (select i::numeric / 10000 as x from generate_series(0, 9999) i)
  select count(*) filter (where nu.k is distinct from fl.k), count(*)
    into v_bad, v_kinds
    from line
   cross join lateral (select mm.kind_code as k from mix mm
                        where line.x < mm.cum_share order by mm.cum_share limit 1) nu
   cross join lateral (select case
                          when (case when line.x < 0.40 then 'STORM'
                                     when line.x < 0.75 then 'CALM' else 'PIRATES' end) = 'STORM'
                               and line.x < 0.40 * 0.45 then 'PIRATES'
                          else (case when line.x < 0.40 then 'STORM'
                                     when line.x < 0.75 then 'CALM' else 'PIRATES' end) end as k) fl;

  -- The ARCTIC clause is the whole reason mix_raiders is an interaction and not a plain piracy
  -- term: danger 4, piracy 0.12, and no corsairs have ever worked the pack ice. It must stay
  -- under the Mediterranean, which is only danger 3 but is thick with them.
  if v_distinct_mix >= 10 and v_distinct_mix > v_distinct_today
     and v_kinds = 10000 and v_bad >= 5000
     and v_pir_mal > v_pir_bal + 0.15
     and v_pir_med > v_pir_bal
     and v_pir_arc < v_pir_med then
    f_vary := true;
  end if;
  if not f_vary then
    raise exception '0055 self-assert FAIL: the sea does not decide enough to be worth the columns — % distinct mixes (today %), PIRATES share Baltic % / Mediterranean % / Malacca %, Arctic %, and only % of % points of Malacca''s draw land anywhere but where the flat bands already put them (Malacca must beat the Baltic by >15 points, the Arctic must stay under the Mediterranean, and at least half the line must move)',
      v_distinct_mix, v_distinct_today, v_pir_bal, v_pir_med, v_pir_mal, v_pir_arc, v_bad, v_kinds;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (f) THE CONTENT READS ITSELF. Every new kind's sentence comes out of voyage.report_line
  --     with no code edit — the claim NAVIGATION_PLAN:173 makes about 0035, proved on real
  --     payloads including the fallback arm. A kind whose prose raised would be content that
  --     cannot ship.
  ---------------------------------------------------------------------------------------------
  v_n := 0;
  for r in select k.code, k.prose_keys from public.voyage_event_kinds k
            where k.code in ('FAIR_WIND', 'CONSORT', 'DERELICT', 'FOUL_WATER', 'SHOAL_WATER')
            order by k.ordinal loop
    -- with the payload the settle arm would write
    v_prose := voyage.report_line(4, r.code, jsonb_build_object(
      'hours_gained', 9, 'salvage', 'two casks of tar', 'stores_lost', 3.5, 'hull_lost', 6.25));
    if v_prose !~ '^Day 4\. .' or v_prose ~ '%s' or v_prose ~ '\?' then
      raise exception '0055 self-assert FAIL: % does not read as a sentence out of voyage.report_line with its own payload — got "%"', r.code, v_prose;
    end if;
    -- and with NOTHING, which is the arm that prints '?' rather than raising
    v_prose := voyage.report_line(4, r.code, '{}'::jsonb);
    if v_prose !~ '^Day 4\. .' then
      raise exception '0055 self-assert FAIL: % raised or printed nothing on an empty payload — a kind whose prose can fail is a kind that cannot be lit', r.code;
    end if;
    v_n := v_n + 1;
  end loop;
  -- the crew clause 0035 generalised off PIRATES still attaches to whatever costs crew
  if v_n = 5 and voyage.report_line(4, 'SHOAL_WATER',
        '{"hull_lost": 6.25, "crew_lost": 3}'::jsonb) ~ 'We buried 3 of the crew' then
    f_prose := true;
  end if;
  if not f_prose then
    raise exception '0055 self-assert FAIL: % of 5 new kinds read back, and the payload-keyed crew clause did not attach to one of them — the catalogue is not carrying the content on its own', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (g) IT IS DARK. Nothing in the chain calls voyage.encounter_at, and the only caller of
  --     voyage.sea_mix is voyage.encounter_at. Probed against COMMENT-STRIPPED prosrc, with a
  --     positive control — a probe that cannot see the one real call would pass on anything.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_readers
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.oid <> 'voyage.encounter_at(uuid, int)'::regprocedure
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'encounter_at';
  select count(*) into v_n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.oid <> 'voyage.sea_mix(uuid)'::regprocedure
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'sea_mix';
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_before
    from pg_proc p where p.oid = 'voyage.encounter_at(uuid, int)'::regprocedure;
  if v_readers = 0 and v_n = 1 and v_before ~ 'voyage\.sea_mix' then
    f_dark := true;
  end if;
  if not f_dark then
    raise exception '0055 self-assert FAIL: the mix is not dark — % function(s) call voyage.encounter_at (must be 0) and % call voyage.sea_mix (must be exactly 1, encounter_at itself)', v_readers, v_n;
  end if;

  -- IT IS A DROP-IN, AND THE DICE CUP IS 0006'S. The lighting slice's whole first statement is
  -- "this body becomes voyage.hazard_roll", so it must draw the same three streams, named, and no
  -- fourth. Counted off the comment-stripped body, with each name asserted individually so a
  -- renamed stream ('kind2') cannot hide behind the right total.
  v_i := (length(v_before) - length(replace(v_before, 'voyage.rng(', ''))) / length('voyage.rng(');
  if v_i <> 3
     or v_before !~ 'voyage\.rng\(p_voyage, p_day, ''occur''\)'
     or v_before !~ 'voyage\.rng\(p_voyage, p_day, ''kind''\)'
     or v_before !~ 'voyage\.rng\(p_voyage, p_day, ''magnitude''\)' then
    raise exception '0055 self-assert FAIL: voyage.encounter_at draws % voyage.rng stream(s), and not exactly the three voyage.hazard_roll draws (occur, kind, magnitude) — it is then not the drop-in its header says lighting the mix would be, and one voyage would answer two ways across that one migration', v_i;
  end if;

  ---------------------------------------------------------------------------------------------
  -- THE PROBE. A real house, a real long-haul voyage across two oceans, everything below rolled
  --     back by the raise at its foot. The world's weather is fingerprinted before and after.
  ---------------------------------------------------------------------------------------------
  select md5(string_agg(x, '|' order by x)) into v_w0 from (
    select s.code || ':' || s.hazard_base || ':' || s.piracy_index || ':' || s.danger_level as x
      from public.seas s
    union all select 'knob:' || public.wc_num('hazard_p_max')) w(x);

  begin
    v_player := public.new_house(c_probe, 'Casa das Aguas', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id into v_fleet from public.fleets where player_id = v_player;

    -- THE PROBE OWNS ITS PRECONDITIONS (README §3), and 0047 §j's recipe is followed because it
    -- is the one that is known to depart this course: full crew, deterministic stores, coin.
    update public.players set ducats = 8000 where id = v_player;
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - sh.crew from public.ships sh
         join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));
    -- stores are SET, not bought (0047 §j): do_provision(FULL) raises E_HOLD_FULL when the
    -- casks are already topped, and whether they are depends on the starting fleet. 45 crew-days
    -- of each clears this 3,700 nm passage's endurance margin deterministically.
    update public.ships s
       set water_t = round(s.crew * public.wc_num('water_per_crew_day') * 45, 3),
           food_t  = round(s.crew * public.wc_num('food_per_crew_day') * 45, 3)
     where s.fleet_id = v_fleet;

    v_res := cmd.issue(v_fleet, 'SAIL TO SLV', null, v_course_sal);
    if coalesce(v_res->>'ok', 'false') <> 'true' then
      raise exception '0055 self-assert FAIL: the probe''s Salvador passage was refused [%: %] — the probe has no subject and everything below it would be vacuous',
        v_res->>'error_code', v_res->>'error_message';
    end if;
    select * into v from public.voyages where fleet_id = v_fleet and status = 'SAILING';
    v_voyage := v.id;
    v_days := voyage.total_days(v_voyage);

    -----------------------------------------------------------------------------------------
    -- (h) THE WATERS ARE THE WHOLE OF WHAT IS LEFT. The runs are contiguous, in order, and
    --     their lengths sum to exactly the distance she has still to make good. Non-vacuous:
    --     the run count and the number of DISTINCT seas are asserted.
    -----------------------------------------------------------------------------------------
    v_w := voyage.waters_ahead(v_voyage);
    v_prog := voyage.progress_nm(v_voyage);
    select coalesce(sum((e->>'nm_in')::numeric), 0), count(*), count(distinct e->>'sea')
      into v_nm_sum, v_n, v_nkinds
      from jsonb_array_elements(v_w) e;
    select count(*) into v_bad from jsonb_array_elements(v_w) with ordinality t(e, ord)
     where (t.ord = 1) <> ((t.e->>'now')::boolean)
        or (t.e->>'danger')::int not between 1 and 5
        or coalesce(length(t.e->>'note'), 0) = 0
        or (t.e->>'nm_to')::numeric < 0;
    -- every tier printed is the tier public.seas holds, and the tier the mix reads
    select count(*) into v_i
      from jsonb_array_elements(v_w) e
      join public.seas s on s.code = e->>'sea'
     where (e->>'danger')::int is distinct from s.danger_level
        or (e->>'note') is distinct from s.note;
    if v_n >= 2 and v_nkinds >= 2 and v_bad = 0 and v_i = 0
       and abs(v_nm_sum - (v.total_nm - v_prog)) <= 0.5 then
      f_water := true;
    end if;
    if not f_water then
      raise exception '0055 self-assert FAIL: the waters ahead do not describe the passage — % run(s) over % sea(s), % misshapen, % disagreeing with public.seas, and they measure % nm against the % nm she still has to make good',
        v_n, v_nkinds, v_bad, v_i, v_nm_sum, v.total_nm - v_prog;
    end if;

    -----------------------------------------------------------------------------------------
    -- ...and A WATER WITH NO NAME IS REFUSED RATHER THAN DRAWN. A real poked segment, on the
    -- real voyage, and the path is put straight back — 0040's own idiom for proving a raster
    -- read really reads. Without this the guard above is a branch nothing can reach.
    -----------------------------------------------------------------------------------------
    f_guard := false;
    select jsonb_set(v.path, '{0,sea_id}',
                     to_jsonb('00000000-0055-4000-8000-00000000dead'::uuid)) into v_path;
    update public.voyages set path = v_path where id = v_voyage;
    begin
      perform voyage.waters_ahead(v_voyage);
      raise exception 'NO_GUARD_NAMELESS';
    exception when others then
      if sqlerrm ~ 'E_NO_SEA' then f_guard := true; end if;
    end;
    update public.voyages set path = v.path where id = v_voyage;
    if not f_guard then
      raise exception '0055 self-assert FAIL: a segment frozen against a sea nobody holds was DRAWN instead of refused — the map would print a row with no name and no tier, which is 0035''s deleted "Day 7. DERELICT" one layer out';
    end if;
    if voyage.waters_ahead(v_voyage) is distinct from v_w then
      raise exception '0055 self-assert FAIL: the poked segment did not go back — everything measured after this point is measuring a bent voyage';
    end if;

    -----------------------------------------------------------------------------------------
    -- (i) AND THEY CROSS THE WIRE. world.fleets serves them on the voyage it already serves.
    -----------------------------------------------------------------------------------------
    select f into v_fpay from jsonb_array_elements(world.fleets()) f where f->>'id' = v_fleet::text;
    if v_fpay->'voyage'->'waters' = v_w
       and jsonb_array_length(v_fpay->'voyage'->'waters') = v_n
       and v_fpay->'voyage'->'course' is not null
       and v_fpay->'voyage'->'position'->>'lat' is not null then
      f_wire := true;
    end if;
    if not f_wire then
      raise exception '0055 self-assert FAIL: world.fleets does not serve the waters beside the course it already served (voyage payload: %)', v_fpay->'voyage';
    end if;

    -----------------------------------------------------------------------------------------
    -- (j) THE ENCOUNTER IS A PURE FUNCTION OF (voyage, day, secret) AND NOT OF THE CLOCK.
    --     The probe FORCES weather so the comparison is not vacuous: every sea at its CHECK
    --     ceiling and every frozen segment at hazard_mult 5, which puts p at 0.25 a day — over
    --     the days below, the chance of no encounter at all is about one in ten thousand, and
    --     the count is printed so a thin run is visible rather than silently weak.
    -----------------------------------------------------------------------------------------
    update public.seas set hazard_base = 0.0500;
    update public.world_config set value = to_jsonb(1.0) where key = 'hazard_p_max';
    select jsonb_agg(jsonb_set(t.e, '{hazard_mult}', to_jsonb(5.0)) order by t.ord)
      into v_path from jsonb_array_elements(v.path) with ordinality t(e, ord);
    update public.voyages set path = v_path where id = v_voyage;

    v_cap := least(v_days, 60);
    select string_agg(coalesce(e.kind, '-') || ':' || e.magnitude || ':' || e.p_hazard, '|' order by g),
           count(*) filter (where e.occurred),
           count(distinct e.kind)
      into v_sig0, v_occ, v_nkinds
      from generate_series(1, v_cap) g
     cross join lateral voyage.encounter_at(v_voyage, g) e;

    -- AND IT IS THE SAME DAY'S WEATHER, not merely a pure one. Lighting the mix replaces
    -- voyage.hazard_roll's BODY, so on the migration that does it every voyage already at sea
    -- must keep the same event DAYS and the same magnitudes — only WHICH thing happened may
    -- move. Compared day by day against the live hazard_roll on this same voyage.
    select count(*) filter (where e.occurred is distinct from h2.occurred
                               or e.magnitude is distinct from h2.magnitude
                               or e.p_hazard  is distinct from h2.p_hazard),
           count(*) filter (where e.kind is distinct from h2.kind)
      into v_bad, v_i
      from generate_series(1, v_cap) g
     cross join lateral voyage.encounter_at(v_voyage, g) e
     cross join lateral voyage.hazard_roll(v_voyage, g) h2;
    if v_bad <> 0 then
      raise exception '0055 self-assert FAIL: on % of % voyage-day(s) voyage.encounter_at disagreed with voyage.hazard_roll about WHETHER something happened, how big it was, or how likely it was — lighting the mix would then move the event days of every voyage already at sea, and it is only allowed to move which thing happened',
        v_bad, v_cap;
    end if;

    -- "evaluated now, or in an hour": shift the whole voyage through the clock. Nothing about
    -- WHEN it is asked may change WHAT it answers.
    update public.voyages set departed_at = departed_at - interval '600 hours',
                              eta = eta - interval '600 hours'
     where id = v_voyage;
    select string_agg(coalesce(e.kind, '-') || ':' || e.magnitude || ':' || e.p_hazard, '|' order by g)
      into v_sig1
      from generate_series(1, v_cap) g
     cross join lateral voyage.encounter_at(v_voyage, g) e;
    update public.voyages set departed_at = departed_at + interval '600 hours',
                              eta = eta + interval '600 hours'
     where id = v_voyage;

    if v_sig0 = v_sig1 and v_cap >= 20 and v_occ >= 1 and v_nkinds >= 1 then
      f_pure := true;
    end if;
    if not f_pure then
      raise exception '0055 self-assert FAIL: over % voyage-day(s) the encounter answered differently once the voyage was moved through the clock (% day(s) carried one, % distinct kind(s)) — it is not the pure function offline settlement rests on',
        v_cap, v_occ, v_nkinds;
    end if;

    -----------------------------------------------------------------------------------------
    -- (k) THE MEASUREMENT THIS FILE OWES ITS HEADER: a look-ahead is not authoritative. Settle
    --     the whole voyage, then ask the same days again. Any day whose own event carried
    --     delay_hours can answer differently, because voyage.leg_at_day subtracts delays that
    --     had not been written when the look-ahead ran. NOT asserted to be zero — it is a
    --     property of the chain, it is why the panel predicts nothing, and it is printed.
    -----------------------------------------------------------------------------------------
    v_i := 0;
    while (select status from public.fleets where id = v_fleet) = 'SAILING' and v_i < 40 loop
      update public.voyages set departed_at = departed_at - interval '600 hours',
                                eta = eta - interval '600 hours'
       where id = v_voyage;
      perform voyage.settle(v_fleet);
      v_i := v_i + 1;
    end loop;
    select count(*) into v_drift
      from generate_series(1, v_cap) g
     where (select coalesce(e.kind, '-') from voyage.encounter_at(v_voyage, g) e)
           is distinct from split_part((string_to_array(v_sig0, '|'))[g], ':', 1);

    raise exception 'ROLLBACK_0055_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0055_PROBE' then raise; end if;
  end;

  select md5(string_agg(x, '|' order by x)) into v_w1 from (
    select s.code || ':' || s.hazard_base || ':' || s.piracy_index || ':' || s.danger_level as x
      from public.seas s
    union all select 'knob:' || public.wc_num('hazard_p_max')) w(x);
  if v_w0 is distinct from v_w1 then
    raise exception '0055 self-assert FAIL: the probe left the world''s weather moved — every sea''s hazard rate, piracy index and danger tier, and the hazard clamp, must read exactly as they did before it ran';
  end if;
  select count(*) into v_left from public.players pl where pl.auth_uid = c_probe;
  if v_left <> 0 then
    raise exception '0055 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (l) POSTURE. world.fleets' ACL is unchanged, nothing this file made is reachable by a
  --     client, the catalogue is still server-private, and all four read-wall authorities read
  --     zero.
  ---------------------------------------------------------------------------------------------
  select acl into v_acl0 from defs_before_0055 where fn = 'world.fleets';
  select p.proacl::text into v_acl1 from pg_proc p where p.oid = 'world.fleets()'::regprocedure;
  if v_acl0 is not distinct from v_acl1
     and not has_function_privilege('anon', 'world.fleets()', 'execute')
     and has_function_privilege('authenticated', 'world.fleets()', 'execute')
     and not has_function_privilege('authenticated', 'voyage.sea_mix(uuid)', 'execute')
     and not has_function_privilege('anon', 'voyage.sea_mix(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'voyage.encounter_at(uuid, int)', 'execute')
     and not has_function_privilege('anon', 'voyage.encounter_at(uuid, int)', 'execute')
     and not has_function_privilege('authenticated', 'voyage.waters_ahead(uuid)', 'execute')
     and not has_function_privilege('anon', 'voyage.waters_ahead(uuid)', 'execute')
     and not has_table_privilege('authenticated', 'public.voyage_event_kinds', 'select')
     and not has_table_privilege('anon', 'public.voyage_event_kinds', 'select')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0055 self-assert FAIL: the posture moved — world.fleets'' ACL changed, or one of this file''s three new functions is reachable by a client, or a read-wall authority no longer reads zero';
  end if;

  raise notice '0055 self-assert ok: THE SEA NOW DECIDES WHAT IT BREEDS, AND IT IS DARK. WHERE a fleet is used to buy her exactly THREE mixes across all % seas — 71 per cent of the world''s water draws from one bag — and it now buys her %, derived from seas.danger_level and seas.piracy_index through three response numbers per kind and no second danger scale: PIRATES runs % per cent of event-days in the Baltic, % in the Mediterranean and % in the Strait of Malacca, while the Arctic stays at % because mix_raiders needs lawless water and hard water at once. All % seas answer with all 8 kinds, every share positive, closing on exactly 1. THE DRAW IS UNTOUCHED: hazard_roll, settle and report_line are byte-identical, the rolled set is still 3 kinds summing to 1, and the live draw still answers 0006''s CASE on all % (r_kind, piracy) pairs including % that cede a storm to raiders — no voyage yields one ducat differently because this file ran. The five new kinds are is_rolled=false and every one of them reads back out of voyage.report_line with no code edit, on a real payload and on an empty one, with 0035''s crew clause attaching to SHOAL_WATER for free. voyage.encounter_at has 0 callers and voyage.sea_mix has exactly 1; over % voyage-day(s) of a real % nm two-ocean passage — every sea at its CHECK ceiling and every segment at hazard_mult 5, which carried % encounter day(s) across % kind(s) — it answered IDENTICALLY after the whole voyage was moved 600 hours through the clock, which is the purity offline settlement rests on. MEASURED AND NOT HIDDEN, because a look-ahead is NOT authoritative in this chain: voyage.leg_at_day subtracts delays that have not been recorded when it is asked early, so a day can answer one way before the voyage settles and another after. On this two-sea passage the drift came out at % day(s) of % — the seam is narrow here because only one sea boundary lies on the course — and it is the reason the map predicts no roll at all and prints only what is frozen at departure: % run(s) of water over % sea(s), measuring % nm against the % nm she had still to make good, each carrying the SAME danger tier and note public.seas holds, served on world.fleets by ONE sliced hunk that leaves the rest of that payload byte-identical. Both new guards bit on real rejected writes. The probe left 0 houses and the weather exactly as it found it, and this file grants nothing: 0 client write grants, 0 client-executable writers, 0 read-wall gaps',
    v_seas_seen, v_distinct_mix, round(v_pir_bal * 100, 1), round(v_pir_med * 100, 1),
    round(v_pir_mal * 100, 1), round(v_pir_arc * 100, 1), v_seas_seen,
    v_sweep_n, v_sweep_cede,
    v_cap, round(v.total_nm), v_occ, v_nkinds,
    v_drift, v_cap,
    (select count(*) from jsonb_array_elements(v_w)),
    (select count(distinct e->>'sea') from jsonb_array_elements(v_w) e),
    v_nm_sum, round(v.total_nm - v_prog, 1);
end $$;

drop table defs_before_0055;
