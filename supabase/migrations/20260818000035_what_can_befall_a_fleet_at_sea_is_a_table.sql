-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0035 — WHAT CAN BEFALL A FLEET AT SEA IS A TABLE
--        public.voyage_event_kinds — the catalogue of things that can happen on a voyage-day.
--        The FOUNDATION combat, exploration and NPCs will stand on. See docs/PLATFORM.md.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK, AND WHAT THIS FILE IS NOT ──────────────────────────────────────────────────────────
-- The owner, 2026-08-23: "this game might need OSN system as well as other system built in
-- byeharu, the previous game. audit and implement it so that later on, combat, exploration, npcs
-- can be added."
--
-- docs/PLATFORM.md is the audit. Its answer on OSN is NO, with evidence: the predecessor's
-- free-coordinate stack was built, gated, never lit and then DELETED (20 functions dropped by
-- 20260618000232, the table and six CHECKs by 0231, both coordinate flags asserted false first at
-- 0231:245-250) — and, decisively, in that schema a fleet at a free coordinate is the one thing
-- that CANNOT be attacked: combat_encounters.presence_id is `not null references
-- location_presence` (20260616000014_combat_tables.sql:14) and the space-arrival branch creates no
-- presence at all, "open space has no location" (0208:163-166). OSN does not make room for combat.
-- It is where combat cannot reach.
--
-- This file builds the seam that IS missing, and nothing else. It adds no combat, no NPC, no
-- exploration, no verb, no screen. A half-built combat system is worse than none.
--
-- ── THE DEFECT, MEASURED ────────────────────────────────────────────────────────────────────────
-- The set of things that can happen to a fleet at sea is stated in THREE FUNCTIONS, in three
-- different shapes, and nothing makes them agree:
--
--   1. voyage.hazard_roll   0006:697-703  — a CASE picks the kind:
--        `when r_kind < 0.40 then 'STORM' when r_kind < 0.75 then 'CALM' else 'PIRATES'`
--      followed by 0006:707-709, a second CASE-free branch that converts some storms to pirates
--      in proportion to the sea's piracy index.
--   2. voyage.settle        0007:887, re-cut 0027:238 — an if/elsif arm per kind, which APPLIES
--      the outcome. These arms are genuinely different code and this file does not touch them.
--   3. voyage.report_line   0007:868, re-cut 0027:196 — a CASE per kind produces the prose, with
--        `else format('Day %s. %s', p_day, p_kind)`
--      as the fallback. That fallback is the sharp end: adding a kind and forgetting this function
--      does not fail — it PRINTS THE RAW CODE AT THE PLAYER, "Day 7. DERELICT".
--
-- docs/NO_SPAGHETTI.md §1 question 2 — "would a rule change have to be made here too?" — answers
-- YES in three places, which is the definition of three authors. And question 3 — "can they
-- disagree?" — is answered by the fallback above: they can, silently, in the direction of a code
-- the player reads.
--
-- The predecessor learned this and got it right the second time. Its combat content is rows:
-- adding an enemy type there is an INSERT through an owner-gated RPC, not a migration
-- (byeharu/docs/COMBAT_CONTENT_PROGRAM.md), and which city a zone's raiders sortie from is
-- "a row, not a code edit" (byeharu/20260618000338:20-39). The standing method rule states it
-- plainly: a new enemy must be ROWS, not code; if adding content requires editing a function, the
-- design is wrong.
--
-- ── THE DECISION ────────────────────────────────────────────────────────────────────────────────
-- ONE catalogue. `public.voyage_event_kinds` owns, for each kind: whether it is ROLLED and with
-- what weight, what it CEDES to under piracy, and the SENTENCE the player reads. Three callers on
-- day one, which is why it is a table and not three literals:
--
--   * voyage.hazard_roll  reads the weights            — superseded here.
--   * voyage.report_line  reads the prose              — superseded here.
--   * public.voyage_events.kind is a FOREIGN KEY into it — so a kind nobody named can never be
--     written. The predecessor's own conclusion after eleven copies of one predicate: the cures
--     that worked were STRUCTURAL, not disciplinary. Make the wrong thing impossible.
--
-- After this file, adding a thing that can happen at sea is ONE INSERT plus, only if it does
-- something new to the ships, one arm in a superseding voyage.settle. It was three functions and a
-- silent way to get it wrong.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT TOUCH ──────────────────────────────────────────────────
--   * voyage.settle. Its arms are different code — a storm subtracts durability, a calm adds hours
--     — and one arm per kind is composition, not duplication. The FK is all the coupling needed.
--     Not re-cutting it also means proof 01's day-boundary, wage and ration arithmetic is
--     unchanged BY CONSTRUCTION.
--   * The hazard PROBABILITY. `sea.hazard_base x leg.hazard_mult`, clamped by `hazard_p_max`, is
--     untouched. This file changes WHICH thing happens, never HOW OFTEN something does.
--   * Per-sea weights. The flat mix plus `seas.piracy_index` reproduces today exactly; a second
--     weight table with one row would be machinery ahead of content. docs/PLATFORM.md §6 carries
--     its shape.
--   * An actor / subject column, and a second event on one day. Both are real gaps, both are named
--     with their shapes in docs/PLATFORM.md §6, and both are refused HERE because a column with no
--     reader is the predecessor's own recorded failure class — `enemy_archetypes.stat_overrides`
--     ("a DEAD authored field, read by nothing at spawn"), `encounter_runtime_state.active_count`
--     ("dead weight as a runtime authority — nothing reads it"), `fleet_combat_stats` (zero
--     callers). Four such items, each of which cost a migration to remove.
--
-- ── ONE THING IS GENERALISED, NOT ADDED ─────────────────────────────────────────────────────────
-- 0027's burial sentence ("We buried N of the crew…") hung off `p_kind = 'PIRATES'`. It now hangs
-- off the PAYLOAD carrying `crew_lost`, which is strictly more correct and removes the last kind
-- literal from report_line. It is byte-identical today: `crew_lost`, `base_loss` and
-- `surgeon_pct` are written in exactly ONE place, 0027:388-390, the PIRATES arm of settle. A
-- future event that costs crew gets the sentence for free instead of needing a fourth author.
--
-- ── WHAT IT SELF-ASSERTS (every one of them able to fail, and shown failing) ────────────────────
--   (a) THE NO-OP, exhaustively: over 50,000 (r_kind, piracy_index) pairs the catalogue draw
--       returns EXACTLY what 0006's CASE returned, cede included — with a non-vacuity guard that
--       all three rolled kinds and at least one real cede actually occurred in the sample.
--   (b) THE WIRING, end to end: the longest voyage in the world, every sea at the worst authored
--       hazard, every day compared against 0006's CASE applied to the same rng stream. Non-vacuous
--       by count: it asserts a real number of days OCCURRED and more than one kind appeared.
--   (c) THE PROSE NO-OP: eleven (day, kind, payload) cases captured from the LIVE report_line
--       BEFORE it is replaced, and required byte-identical after — including the '?' fallback, the
--       'They closed with us.' fallback, and all four branches of the surgeon clause.
--   (d) THE FALLBACK IS GONE: an unknown kind now RAISES instead of printing itself at a player.
--   (e) THE FK BITES: a real REJECTED insert of an unnamed kind into voyage_events.
--   (f) THE WEIGHTS MUST CLOSE: a real REJECTED insert of a rolled kind that does not rebalance.
--   (g) THE CATALOGUE IS THE ONLY AUTHORITY: neither superseded function's body contains a kind
--       literal any more — probed against COMMENT-STRIPPED prosrc, with the pre-image proving the
--       probe could see them before.
--   (h) POSTURE: the catalogue is server-private (no policy, no grant, RLS on), report_line's ACL
--       is unchanged, and all four read-wall authorities still read zero.
--
-- Depends ONLY on: 0006 (hazard_roll, voyage_events, rng, route, depart), 0007 (report_line),
--                  0027 (report_line's surgeon clause, the crew_lost payload), 0030 (the wording).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── PRE-IMAGES. Captured BEFORE anything is replaced, because "this changes nothing" is not
--    evidence (NO_SPAGHETTI §3.3). The prosrc rows are the POSITIVE CONTROL for assert (g): a
--    probe that cannot see the literals now would wave the change through unexamined.
create temporary table defs_before_0035 as
  select 'voyage.report_line'::text as fn,
         pg_get_functiondef('voyage.report_line(int, text, jsonb)'::regprocedure) as def,
         (select p.proacl::text  from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure) as acl,
         (select p.prosrc        from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure) as src
  union all
  select 'voyage.hazard_roll',
         pg_get_functiondef('voyage.hazard_roll(uuid, int)'::regprocedure),
         (select p.proacl::text  from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure),
         (select p.prosrc        from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure);

-- The eleven prose cases, answered by the LIVE function. Every branch of 0027's clause is here,
-- and so is each of the two fallbacks, because a no-op proof that only exercises the happy path
-- is a no-op proof of the happy path.
create temporary table report_before_0035 as
  select t.day, t.kind, t.payload, voyage.report_line(t.day, t.kind, t.payload) as line
    from (values
      ( 1, 'CLEAR',         '{}'::jsonb),
      ( 2, 'STORM',         '{"hull_lost": 12.5, "delay_hours": 36}'::jsonb),
      ( 3, 'STORM',         '{}'::jsonb),
      ( 4, 'CALM',          '{"delay_hours": 51.2}'::jsonb),
      ( 5, 'CALM',          '{}'::jsonb),
      ( 6, 'PIRATES',       '{"prose": "They came aboard and took what they could carry.", "crew_lost": 7, "base_loss": 0.10, "surgeon_pct": 0}'::jsonb),
      ( 7, 'PIRATES',       '{"prose": "We fired twice and they sheered away.", "crew_lost": 2, "base_loss": 0.02, "surgeon_pct": 15.5}'::jsonb),
      ( 8, 'PIRATES',       '{"prose": "They stood off and did not close.", "crew_lost": 0, "base_loss": 0, "surgeon_pct": 0}'::jsonb),
      ( 9, 'PIRATES',       '{"crew_lost": 0, "base_loss": 0.02, "surgeon_pct": 12}'::jsonb),
      (10, 'PIRATES',       '{}'::jsonb),
      (11, 'SHORT_RATIONS', '{}'::jsonb)
    ) as t(day, kind, payload);

-- ── 1. THE CATALOGUE ───────────────────────────────────────────────────────────────────────────
-- WHERE IT LIVES AND WHY (NO_SPAGHETTI §7B q2): `public`, beside the tables, because it is world
-- reference data like `seas` and `goods`. Not `voyage`, which owns time and motion; not `cmd`,
-- which owns writes.
-- WHO THE SECOND CALLER IS (q3): there are three on day one — hazard_roll, report_line, and the
-- foreign key on voyage_events.kind. That is why it is a table.
-- WHAT WOULD MAKE IT THE WRONG SHAPE (q4): if the mix ever has to differ per sea, this table is
-- too flat. The tell is anyone writing a second weight anywhere; docs/PLATFORM.md §6 holds the
-- shape of the per-sea table that answers it.
create table if not exists public.voyage_event_kinds (
  code            text primary key check (code ~ '^[A-Z][A-Z_]{2,29}$'),

  -- The band order of the draw. Stable, so the same rng stream keeps answering the same way.
  ordinal         int  not null unique check (ordinal > 0),

  -- ROLLED kinds are drawn by voyage.hazard_roll from the weights below. A CONDITION kind is
  -- decided by voyage.settle from what is actually aboard and is never drawn — 0006:701-702
  -- already said so in a comment about SHORT_RATIONS; here it is a column.
  is_rolled       boolean not null,
  roll_weight     numeric(6,4) check (roll_weight > 0 and roll_weight <= 1),

  -- A high-piracy sea converts some of one kind into another without a second rng draw
  -- (0006:707-709). Stated as a row so "the corsairs work these waters" is authorship.
  cedes_to        text references public.voyage_event_kinds(code),
  cede_fraction   numeric(6,4) check (cede_fraction > 0 and cede_fraction <= 1),

  -- THE SENTENCE. `prose` is the body; voyage.report_line prepends "Day N. " so that the house
  -- style has one owner. Each %s consumes prose_keys[i] out of the event payload, falling back to
  -- prose_fallbacks[i] when the payload does not carry it.
  prose           text   not null check (length(btrim(prose)) > 0),
  prose_keys      text[] not null default '{}',
  prose_fallbacks text[] not null default '{}',

  note            text not null check (length(btrim(note)) > 0),

  constraint voyage_event_kinds_weight_iff_rolled
    check (is_rolled = (roll_weight is not null)),
  constraint voyage_event_kinds_cede_is_a_pair
    check ((cedes_to is null) = (cede_fraction is null)),
  constraint voyage_event_kinds_only_rolled_cede
    check (cedes_to is null or is_rolled),
  constraint voyage_event_kinds_cede_is_not_self
    check (cedes_to is null or cedes_to <> code),
  -- A template whose placeholders do not match its keys cannot be inserted. `%` is legal ONLY as
  -- `%s`, so the count is exact and format() can never be handed the wrong arity at read time.
  constraint voyage_event_kinds_prose_percent_is_only_s
    check (prose !~ '%([^s]|$)'),
  constraint voyage_event_kinds_prose_arity
    check ((length(prose) - length(replace(prose, '%s', ''))) / 2
           = coalesce(array_length(prose_keys, 1), 0)),
  constraint voyage_event_kinds_prose_keys_paired
    check (coalesce(array_length(prose_keys, 1), 0)
           = coalesce(array_length(prose_fallbacks, 1), 0))
);

comment on table public.voyage_event_kinds is
  'THE catalogue of things that can befall a fleet on a voyage-day (DESIGN B.6). One row per kind: '
  'whether it is drawn and with what weight, what it cedes to under piracy, and the sentence the '
  'player reads. voyage.hazard_roll reads the weights, voyage.report_line reads the prose, and '
  'public.voyage_events.kind is a foreign key into it — so a kind nobody named cannot be written. '
  'Adding a thing that happens at sea is an INSERT here plus, only if it does something new to the '
  'ships, one arm in a superseding voyage.settle. See docs/PLATFORM.md.';

comment on column public.voyage_event_kinds.is_rolled is
  'A ROLLED kind is drawn by voyage.hazard_roll from roll_weight. A CONDITION kind (CLEAR, '
  'SHORT_RATIONS) is decided by voyage.settle from what is aboard and is never drawn. Setting a '
  'kind is_rolled=false RETIRES it from the draw while keeping it nameable, so history keeps its '
  'foreign key.';

-- Server-private, the world_config posture of 0001: RLS on, NO policy, NO grant. Nothing the
-- client renders comes from here directly — report_line hands out the sentence and nothing else,
-- so the weights never cross the wire.
alter table public.voyage_event_kinds enable row level security;

-- ── 2. THE WEIGHTS MUST CLOSE ──────────────────────────────────────────────────────────────────
-- The draw is "the first band whose cumulative weight exceeds r". If the rolled weights do not sum
-- to exactly 1, some r falls off the end and the draw has no answer. A comment cannot enforce
-- that; this can. DEFERRABLE INITIALLY IMMEDIATE: checked at end of statement, so the seed below
-- lands in one INSERT, and a legitimate multi-statement rebalance can still `set constraints ...
-- deferred` for its transaction. Adding a kind therefore forces the author to STATE the new mix
-- rather than silently changing everyone else's odds.
create or replace function public.tg_voyage_event_kind_weights()
returns trigger
language plpgsql
as $$
declare v_sum numeric;
begin
  select coalesce(sum(roll_weight), 0) into v_sum
    from public.voyage_event_kinds where is_rolled;
  if v_sum <> 1 then
    raise exception 'E_KIND_WEIGHTS: the rolled voyage_event_kinds weights sum to % — they must sum to exactly 1, or some hazard roll has no answer', v_sum
      using errcode = '23514';
  end if;
  return null;
end $$;

comment on function public.tg_voyage_event_kind_weights() is
  'THE closure guard for voyage_event_kinds. The rolled weights are the bands of a cumulative '
  'draw, so they must partition [0,1) exactly. Deferrable-immediate, so a rebalance can be '
  'deferred across statements but nothing can be left unbalanced at commit.';

drop trigger if exists voyage_event_kinds_weights_close on public.voyage_event_kinds;
create constraint trigger voyage_event_kinds_weights_close
  after insert or update or delete on public.voyage_event_kinds
  deferrable initially immediate
  for each row execute function public.tg_voyage_event_kind_weights();

-- ── 3. THE SEED — today's behaviour, restated as rows and nothing else ─────────────────────────
-- 0006:697-709 in full: STORM [0, 0.40), CALM [0.40, 0.75), PIRATES [0.75, 1.00), and within the
-- STORM band the sub-band [0, 0.40 x piracy_index) cedes to PIRATES. One statement, because the
-- self-FK and the closure trigger are both checked at its end.
insert into public.voyage_event_kinds
  (code, ordinal, is_rolled, roll_weight, cedes_to, cede_fraction, prose, prose_keys, prose_fallbacks, note)
values
  ('STORM', 1, true, 0.4000, 'PIRATES', 0.4000,
   'A gale took us on the beam. We ran under bare poles and lost %s points of hull.',
   array['hull_lost'], array['?'],
   'DESIGN B.6. Durability off every hull, and +1.5 voyage-days. Cedes to PIRATES in proportion to the sea''s piracy index, which is how the Barbary run breeds raiders without a second roll.'),
  ('CALM', 2, true, 0.3500, null, null,
   'The wind died away. We lay becalmed and lost %s hours.',
   array['delay_hours'], array['?'],
   'DESIGN B.6. 1-4 voyage-days added to the schedule. Stores are still drunk, which is what makes a calm dangerous rather than merely slow.'),
  ('PIRATES', 3, true, 0.2500, null, null,
   'Sail sighted to windward. %s',
   array['prose'], array['They closed with us.'],
   'DESIGN B.6, and the whole of this game''s combat: escort_score against the raider, five outcomes, and the flagship is never taken. The outcome sentence is chosen by voyage.settle and arrives in the payload.'),
  ('CLEAR', 4, false, null, null, null,
   'A quiet watch; nothing to report.',
   '{}', '{}',
   'A CONDITION, never drawn: what voyage.settle records when no hazard occurred and the stores are sound. Silence would read as a broken game.'),
  ('SHORT_RATIONS', 5, false, null, null, null,
   'Stores are low. The crew are on short rations and their wages are up.',
   '{}', '{}',
   'A CONDITION, never drawn (0006:701-702). Decided by voyage.settle from endurance against the voyage still to run, not by the dice.');

-- ── 4. THE STRUCTURAL GUARANTEE — a kind nobody named cannot be written ────────────────────────
-- On a live database this validates against every event ever recorded. It is the whole reason
-- voyage.settle needs no change: it cannot invent a kind, so the catalogue is provably complete.
alter table public.voyage_events
  add constraint voyage_events_kind_is_catalogued
  foreign key (kind) references public.voyage_event_kinds(code);

-- ── 5. SUPERSEDES 0006:666 — the draw reads the catalogue ──────────────────────────────────────
-- Signature, volatility, security and grants are unchanged. The PROBABILITY is unchanged. Only
-- the choice of WHICH kind moves, from a CASE to a cumulative draw over the rows above, and
-- assert (a) proves the two agree on 50,000 pairs.
create or replace function voyage.hazard_roll(p_voyage uuid, p_day int)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_leg    jsonb;
  v_base   numeric;
  v_piracy numeric;
  v_p      numeric;
  r_occur  numeric;
  r_kind   numeric;
  r_mag    numeric;
  v_cede   text;
  v_frac   numeric;
begin
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  select s.hazard_base, s.piracy_index into v_base, v_piracy
    from public.seas s where s.id = (v_leg->>'sea_id')::uuid;

  -- DESIGN B.6. season_mult, escort_score and lookout_expertise are all 1.0/0 in V0: seasons and
  -- officers are out of scope (K.1), and escorts need guns the V0 hulls barely carry. The shape of
  -- the formula is kept so V1 supplies coefficients rather than a second formula.
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

  -- THE DRAW. The rolled kinds partition [0,1) in ordinal order — a closure the table's own
  -- constraint trigger enforces, so this cannot fall off the end. 0035.
  select k.code into kind
    from (select c.code, c.ordinal,
                 sum(c.roll_weight) over (order by c.ordinal
                                          rows between unbounded preceding and current row) as cum
            from public.voyage_event_kinds c
           where c.is_rolled) k
   where r_kind < k.cum
   order by k.ordinal
   limit 1;

  -- NO_SPAGHETTI §7C: the alternative here is an event with no kind, which the foreign key would
  -- reject three frames later with a message about nothing. If the else is unacceptable it is not
  -- a branch.
  if kind is null then
    raise exception 'E_KIND_CATALOGUE: no voyage_event_kinds band holds r=% — the rolled weights do not partition [0,1)', r_kind
      using errcode = 'P0001';
  end if;

  -- A high-piracy sea converts part of one band into another. Authorship, not code: the row says
  -- which kind cedes, to what, and over how much of its own band.
  select c.cedes_to, c.cede_fraction into v_cede, v_frac
    from public.voyage_event_kinds c where c.code = kind;
  if v_cede is not null and r_kind < v_frac * v_piracy then
    kind := v_cede;
  end if;

  return next;
end $$;

comment on function voyage.hazard_roll(uuid, int) is
  'THE hazard decision of DESIGN B.6. Pure: it writes nothing. Supersedes 0006:666 in the CHOICE '
  'OF KIND only — the probability, the three rng streams and the returned shape are byte-'
  'identical. Which kinds exist, their weights and what they cede to under piracy are rows in '
  'public.voyage_event_kinds since 0035, so adding one is an INSERT.';

-- ── 6. SUPERSEDES 0027:196 — the prose reads the catalogue ─────────────────────────────────────
-- IMMUTABLE -> STABLE, and SECURITY DEFINER, because it now reads a row. Definer rather than a
-- client grant on the catalogue: the sentence crosses the wire, the weights never do. The ACL is
-- deliberately UNCHANGED and assert (h) proves it — tightening it is a separate concern and
-- mixing it in here would be scope this file has no reason to take.
--
-- TWO things change and both are the seam closing:
--   * the per-kind CASE becomes the catalogue's sentence, interpolated from the payload;
--   * `else format('Day %s. %s', p_day, p_kind)` — a raw code printed at a player — is DELETED.
--     An unknown kind raises. It cannot occur through settle (the FK), so the only way to reach it
--     is a caller passing a kind that does not exist, and answering that with prose would be
--     answering a different question.
-- And 0027's burial clause is generalised from `p_kind = 'PIRATES'` to `payload has crew_lost`,
-- which is byte-identical today (0027:388-390 is the sole writer of those three keys) and correct
-- for whatever costs crew next.
create or replace function voyage.report_line(p_day int, p_kind text, p_payload jsonb)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  k    public.voyage_event_kinds%rowtype;
  v_a  text[];
begin
  select * into k from public.voyage_event_kinds where code = p_kind;
  if k.code is null then
    raise exception 'E_KIND_CATALOGUE: % is not a voyage event kind', coalesce(p_kind, '(null)')
      using errcode = 'P0001';
  end if;

  select coalesce(array_agg(coalesce(p_payload->>k.prose_keys[i], k.prose_fallbacks[i]) order by i),
                  '{}'::text[])
    into v_a
    from generate_subscripts(k.prose_keys, 1) i;

  return format('Day %s. ', p_day)
      || format(k.prose, variadic v_a)
      -- 0027's sentence about the people, now keyed on the PAYLOAD rather than on one kind's name.
      -- Silence about a loss reads as a broken game; silence about a surgeon who prevented one is
      -- a bonus the player never sees working.
      || case
           when (p_payload->>'crew_lost')::numeric > 0
                and coalesce((p_payload->>'surgeon_pct')::numeric, 0) > 0
             then format(' We buried %s of the crew; the surgeon kept the rest.',
                         p_payload->>'crew_lost')
           when (p_payload->>'crew_lost')::numeric > 0
             then format(' We buried %s of the crew.', p_payload->>'crew_lost')
           when coalesce((p_payload->>'base_loss')::numeric, 0) > 0
                and coalesce((p_payload->>'surgeon_pct')::numeric, 0) > 0
             then ' The surgeon brought every man through it.'
           else ''
         end;
end $$;

comment on function voyage.report_line(int, text, jsonb) is
  'THE after-action prose of DESIGN E.6, generated in one place. Supersedes 0027:196: the sentence '
  'now comes from public.voyage_event_kinds, so a new kind reads correctly with no code edit, and '
  '0027''s "Day N. <code>" fallback is deleted in favour of a raise. The crew clause is unchanged '
  'in wording and now triggers on the payload carrying crew_lost rather than on the kind being '
  'PIRATES — byte-identical today, and free for whatever costs crew next.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe   constant uuid := '00000000-0035-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_far     uuid;
  v_nodes   uuid[];
  v_voyage  uuid;
  v_days    int;
  v_cap     int;
  v_total_nm numeric := 0;
  d         int;
  h         record;
  v_rk      numeric;
  v_pcy     numeric;
  v_leg     jsonb;
  v_ref     text;
  v_mismatch int := 0;
  v_occurred int := 0;
  v_kinds    text;
  v_nkinds   int;
  v_sweep_bad  int;
  v_sweep_n    int;
  v_sweep_cede int;
  v_sweep_kinds int;
  v_prose_bad  int;
  v_prose_n    int;
  v_src        text;
  v_pre_hz     text;
  v_pre_rl     text;
  v_acl0       text;
  v_acl1       text;
  v_fk_rows    int;
  v_left       int;
  -- The world as it stood before the probe touched the weather. Captured, never assumed:
  -- proofs-never-assert-ambient-defaults applies to the RESTORE as much as to the check.
  v_w0         text;
  v_w1         text;
  f_sweep   boolean := false;  f_wire    boolean := false;
  f_prose   boolean := false;  f_unknown boolean := false;
  f_fk      boolean := false;  f_weights boolean := false;
  f_nolit   boolean := false;  f_grant   boolean := false;
begin
  ---------------------------------------------------------------------------------------------
  -- (g) POSITIVE CONTROL FIRST. The pre-image bodies MUST contain the kind literals, or the
  -- probe below is blind and would pass on anything. Probe CODE, never prose: comments are
  -- stripped, because a function that merely MENTIONS 'STORM' in a comment is not an author.
  ---------------------------------------------------------------------------------------------
  select regexp_replace(src, '--[^\n]*', '', 'g') into v_pre_hz
    from defs_before_0035 where fn = 'voyage.hazard_roll';
  select regexp_replace(src, '--[^\n]*', '', 'g') into v_pre_rl
    from defs_before_0035 where fn = 'voyage.report_line';
  if v_pre_hz !~ '''(STORM|CALM|PIRATES)''' or v_pre_rl !~ '''(STORM|CALM|PIRATES|CLEAR)''' then
    raise exception '0035 self-assert FAIL: the pre-image of hazard_roll or report_line does not contain a kind literal, so the probe for (g) cannot see one — the chain has changed underneath this file, or the probe is blind';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (a) THE NO-OP, EXHAUSTIVELY. 10,000 values of r_kind x 5 piracy indices, the catalogue draw
  -- against 0006's CASE written out. Non-vacuity is asserted, not hoped for.
  ---------------------------------------------------------------------------------------------
  with sample as (
    select i::numeric / 10000 as r, p.v as piracy
      from generate_series(0, 9999) i
      cross join (values (0.0000), (0.1500), (0.4000), (0.8500), (1.0000)) as p(v)
  ),
  old as (
    -- 0006:697-709, transcribed.
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
  select count(*) filter (where o.kind is distinct from n.kind),
         count(*),
         count(*) filter (where o.kind = 'PIRATES' and o.r < 0.40),
         count(distinct o.kind)
    into v_sweep_bad, v_sweep_n, v_sweep_cede, v_sweep_kinds
    from old o join new n on n.r = o.r and n.piracy = o.piracy;

  if v_sweep_bad = 0 and v_sweep_n = 50000 and v_sweep_cede > 0 and v_sweep_kinds = 3 then
    f_sweep := true;
  end if;
  if not f_sweep then
    raise exception '0035 self-assert FAIL: the catalogue draw disagrees with 0006''s CASE on % of % pairs (cedes seen %, distinct kinds %) — the supersede is NOT a no-op',
      v_sweep_bad, v_sweep_n, v_sweep_cede, v_sweep_kinds;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (c) THE PROSE NO-OP, and (d) the deleted fallback.
  ---------------------------------------------------------------------------------------------
  select count(*) filter (where voyage.report_line(b.day, b.kind, b.payload) is distinct from b.line),
         count(*)
    into v_prose_bad, v_prose_n
    from report_before_0035 b;
  if v_prose_bad = 0 and v_prose_n = 11 then f_prose := true; end if;
  if not f_prose then
    raise exception '0035 self-assert FAIL: % of % after-action lines changed wording — the catalogue does not reproduce 0027''s prose',
      v_prose_bad, v_prose_n;
  end if;

  begin
    perform voyage.report_line(7, 'DERELICT', '{}'::jsonb);
  exception when others then
    if sqlerrm ~ 'E_KIND_CATALOGUE' then f_unknown := true; end if;
  end;
  if not f_unknown then
    raise exception '0035 self-assert FAIL: report_line still answers for an uncatalogued kind — 0027''s "Day N. <code>" fallback prints a schema code at a player and must raise instead';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (g) THE LITERALS ARE GONE from both superseded bodies. Comment-stripped, as above.
  ---------------------------------------------------------------------------------------------
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc p where p.oid = 'voyage.hazard_roll(uuid, int)'::regprocedure;
  if v_src !~ '''(STORM|CALM|PIRATES|CLEAR|SHORT_RATIONS)''' then
    select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
      from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure;
    if v_src !~ '''(STORM|CALM|PIRATES|CLEAR|SHORT_RATIONS)''' then f_nolit := true; end if;
  end if;
  if not f_nolit then
    raise exception '0035 self-assert FAIL: a kind literal survives in hazard_roll or report_line — the catalogue is not the only authority and the two can still disagree';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (f) THE WEIGHTS MUST CLOSE — a real rejected write, in a subtransaction.
  ---------------------------------------------------------------------------------------------
  begin
    insert into public.voyage_event_kinds
      (code, ordinal, is_rolled, roll_weight, prose, note)
    values ('DERELICT', 99, true, 0.1000, 'A hull lay low in the water, abandoned.', 'probe');
    raise exception 'NO_GUARD';
  exception when others then
    if sqlerrm ~ 'E_KIND_WEIGHTS' then f_weights := true; end if;
  end;
  if not f_weights then
    raise exception '0035 self-assert FAIL: a rolled kind was accepted without rebalancing the mix — the bands no longer partition [0,1) and some hazard roll has no answer';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (b) THE WIRING, END TO END, on a real long-haul voyage — and (e) the FK.
  -- Everything in this block is rolled back by the raise at its foot.
  ---------------------------------------------------------------------------------------------
  select md5(string_agg(x, '|' order by x)) into v_w0 from (
    select s.code || ':' || s.hazard_base || ':' || s.piracy_index as x from public.seas s
    union all select l.id::text || ':' || l.hazard_mult from public.legs l
    union all select 'knob:' || public.wc_num('hazard_p_max')) w(x);

  begin
    select id into v_lis from public.ports where code = 'LIS';
    -- FIND YOUR OWN SUBJECT, deterministically: the port whose sailed distance from Lisboa is
    -- nearest 7,000 nm — a real long haul of roughly sixty voyage-days at a starter's speed, which
    -- is long enough for the sample below and short enough that days_complete's O(days) walk does
    -- not turn this probe into a minute of WASM. `order by ... , port_id` because an unordered
    -- `limit 1` is a lottery and this chain has already lost that bet twice (NO_SPAGHETTI §4).
    select r.port_id into v_far
      from voyage.reach_from(v_lis) r order by abs(r.nm - 7000), r.port_id limit 1;

    v_player := public.new_house(c_probe, 'Casa Naufragio', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;

    -- THE PROBE SETS ITS OWN PRECONDITION rather than trusting the ambient seed. At the worst the
    -- schema will hold — hazard_base 0.05 (its CHECK ceiling) x hazard_mult 5 (likewise), with the
    -- clamp knob opened — every voyage-day carries p = 0.25. Over the ~60 days below the chance
    -- that NOT ONE occurs is 0.75^60, about one in a hundred million; the assert prints the count
    -- it actually got, so a thin run is visible rather than silently weak.
    -- The legs are set BEFORE the departure because path_from_nodes freezes hazard_mult into the
    -- voyage's own path (0006:305-322) — setting them after would change nothing at all.
    update public.seas set hazard_base = 0.0500, piracy_index = 1.0000;
    update public.legs set hazard_mult = 5.000;
    update public.world_config set value = to_jsonb(1.0) where key = 'hazard_p_max';

    v_nodes  := voyage.route(v_lis, v_far);
    v_voyage := voyage.depart(v_fleet, v_nodes);
    v_days   := voyage.total_days(v_voyage);
    v_cap    := least(v_days, 100);
    select total_nm into v_total_nm from public.voyages where id = v_voyage;

    for d in 1 .. v_cap loop
      select * into h from voyage.hazard_roll(v_voyage, d);
      if h.occurred then
        v_occurred := v_occurred + 1;
        v_rk := voyage.rng(v_voyage, d, 'kind');
        -- Hoist the leg into a variable before joining seas, exactly as 0006:673-675 does. Called
        -- inline in a WHERE clause instead, `voyage.leg_at_day` raises E_NO_SUCH_VOYAGE for a
        -- voyage the very next statement can count — measured on PGlite 0.5.5 2026-08-23, and the
        -- reason the house pattern is a variable. Following it here is not a workaround; it is the
        -- pattern the function this probe checks already uses.
        v_leg := voyage.leg_at_day(v_voyage, d);
        select s.piracy_index into v_pcy from public.seas s
         where s.id = (v_leg->>'sea_id')::uuid;
        -- 0006:697-709 again, this time against the LIVE function on a real voyage.
        v_ref := case when v_rk < 0.40 then 'STORM' when v_rk < 0.75 then 'CALM' else 'PIRATES' end;
        if v_ref = 'STORM' and v_rk < 0.40 * v_pcy then v_ref := 'PIRATES'; end if;
        if h.kind is distinct from v_ref then v_mismatch := v_mismatch + 1; end if;
        v_kinds := coalesce(v_kinds || ',', '') || h.kind;
      elsif h.kind is not null then
        v_mismatch := v_mismatch + 1;
      end if;
    end loop;

    select count(distinct x) into v_nkinds from unnest(string_to_array(v_kinds, ',')) x;
    if v_mismatch = 0 and v_cap >= 40 and v_occurred >= 1 and v_nkinds >= 1 then f_wire := true; end if;

    -- (e) THE FK BITES. A real rejected insert against the real table.
    begin
      insert into public.voyage_events (voyage_id, day_index, kind, payload)
      values (v_voyage, 9999, 'DERELICT', '{}'::jsonb);
    exception when foreign_key_violation then
      f_fk := true;
    end;

    raise exception 'ROLLBACK_0035_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0035_PROBE' then raise; end if;
  end;

  if not f_wire then
    raise exception '0035 self-assert FAIL: over % voyage-day(s), % of % occurring day(s) (% distinct kind(s)) disagreed with 0006''s CASE — hazard_roll is not wired to the catalogue correctly, or the sample was too thin to prove anything',
      v_cap, v_mismatch, v_occurred, v_nkinds;
  end if;
  if not f_fk then
    raise exception '0035 self-assert FAIL: voyage_events accepted a kind the catalogue does not hold — the foreign key is the whole reason voyage.settle needs no change';
  end if;

  ---------------------------------------------------------------------------------------------
  -- The rollback really rolled back, world data included.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_left from public.players pl where pl.auth_uid = c_probe;
  if v_left <> 0 then
    raise exception '0035 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  select md5(string_agg(x, '|' order by x)) into v_w1 from (
    select s.code || ':' || s.hazard_base || ':' || s.piracy_index as x from public.seas s
    union all select l.id::text || ':' || l.hazard_mult from public.legs l
    union all select 'knob:' || public.wc_num('hazard_p_max')) w(x);
  if v_w0 is distinct from v_w1 then
    raise exception '0035 self-assert FAIL: the probe left the world''s weather moved — every sea hazard, every leg multiplier and the hazard clamp must read exactly as they did before it ran';
  end if;
  select count(*) into v_left from public.voyage_event_kinds;
  if v_left <> 5 then
    raise exception '0035 self-assert FAIL: the catalogue holds % rows, not the 5 this file seeds', v_left;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (h) POSTURE. The catalogue is server-private, report_line's ACL did not move, and the four
  -- read-wall authorities still read zero.
  ---------------------------------------------------------------------------------------------
  select acl into v_acl0 from defs_before_0035 where fn = 'voyage.report_line';
  select p.proacl::text into v_acl1
    from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure;
  select count(*) into v_fk_rows from pg_policy where polrelid = 'public.voyage_event_kinds'::regclass;

  if v_acl0 is not distinct from v_acl1
     and v_fk_rows = 0
     and (select relrowsecurity from pg_class where oid = 'public.voyage_event_kinds'::regclass)
     and not has_table_privilege('authenticated', 'public.voyage_event_kinds', 'select')
     and not has_table_privilege('anon', 'public.voyage_event_kinds', 'select')
     and not has_function_privilege('authenticated', 'voyage.hazard_roll(uuid, int)', 'execute')
     and not has_function_privilege('anon', 'voyage.hazard_roll(uuid, int)', 'execute')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0035 self-assert FAIL: the posture moved — report_line''s ACL changed, or the catalogue is reachable by a client, or a read-wall authority no longer reads zero';
  end if;

  raise notice '0035 self-assert ok: WHAT CAN HAPPEN AT SEA IS NOW A TABLE, and it is a no-op today — the catalogue draw agrees with 0006''s CASE on all % (r_kind, piracy) pairs including % that cede a storm to raiders, and all 3 rolled kinds appear; on a real % nm long haul out of Lisboa (% legs, % voyage-days, % walked) every one of % occurring day(s) across % distinct kind(s) answered exactly as the CASE would, with every sea and every leg at the worst the schema will hold; all % after-action lines are byte-identical including both fallbacks and all four branches of the surgeon clause, and 0027''s "Day N. <code>" fallback is DELETED so an uncatalogued kind now raises instead of printing a schema code at a player; the catalogue is the ONLY authority, with no kind literal left in either superseded body (comment-stripped, and the pre-image proves the probe could see them before); and both guards were shown biting on real rejected writes — a rolled kind that did not rebalance the mix, and a voyage_events row naming a kind nobody catalogued. Adding a thing that happens at sea is now ONE INSERT plus, only if it does something new to the ships, one arm in a superseding voyage.settle. voyage.settle is UNTOUCHED, the hazard PROBABILITY is untouched, the probe left the weather exactly as it found it, and this file grants nothing: 0 client write grants, 0 client-executable writers, 0 read-wall gaps',
    v_sweep_n, v_sweep_cede, round(v_total_nm), coalesce(array_length(v_nodes, 1), 0) - 1, v_days, v_cap,
    v_occurred, v_nkinds, v_prose_n;
end $$;

drop table defs_before_0035;
drop table report_before_0035;
