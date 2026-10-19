-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0202 — A CREW THAT CANNOT HOLD THE DECK SURRENDERS  (the raid balance, before the fight is lit again;
--        DARK by construction: voyage.fight_resolve is read only while combat_bite is on)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18 ~13:40 UTC: "yes lets do a automatic fight, so that range and accuracy is an important
-- factor." 0189 built the fight; 0200 lit it at 20:48 UTC 2026-10-18; its 30-minute after-check broke two raid
-- bounds (lost share 43.8 % against 35.0 % dark; crew lost per raid 12.50 % against 6.43 %), and 0201 rolls it
-- back. docs/dev-log/2026-10-18-auto-fight.md, "0202 — the raid balance", has the measurement. In short:
--   * Replayed on production's REAL raids (all 236 PIRATES days, 2026-10-16 → 2026-10-18 21:27 UTC, their own
--     fleets read read-only with world.ship_stats, their own raider strength; 20 rolls each), 0189 lit stays
--     inside both bounds on the same raids overall (lost 25.2 % vs 27.1 %; crew 7.13 % vs 6.48 %) — but a
--     lone hull of 12 hands or fewer, 60 % of the raided, buries more: crew 11.28 % vs 9.76 %, STRIPPED
--     13.4 % vs 6.4 %. Every one of those STRIPPED days is a boarding below the last band (a 40–70-hand xebec
--     crew against 8–12): the crew fought a deck it could not hold and lost 30 % of its hands.
--   * The after-check's own window was not this: the dark table on the SAME 16 raids of 0200's lit window gives
--     lost 50.0 % and crew 12.45 % — that window met heavier raids on smaller hulls than the dark one before it.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- Hunks on voyage.fight_resolve (0189), sliced from the live body: at the boarding, below the last of
-- fight_board_bands the crew SURRENDERS. The raiders board and take what they can carry (PLUNDERED) and nobody
-- dies holding a lost deck, so a fight never ends STRIPPED. Above it, nothing moves: the sighting, the rounds
-- (range, accuracy, attack, armour), the break-off, the bands 1.2 / 0.7 and every word of every other fight.
-- Historically the rule, not the exception: a merchant crew that could not hope to hold the deck struck to the
-- raiders rather than fight; the pirates' and the corsairs' own terror worked by offering quarter to a crew that
-- yielded and none to one that resisted, so the cost of a prize was its cargo, not its crew.
-- The day's sentence is the fight's own, true of it: "We surrendered, and they took what they could carry." —
-- plain words (docs/WORDS.md); the closing line says "You surrender; they board and take what they can carry."
-- What an outcome COSTS is DESIGN B.6's, in voyage.settle, unchanged: PLUNDERED is crew −10 % (public.raid_crew_lost).
-- The knob fight_board_bands keeps its three values; its third is now where the crew surrenders (description).
-- NOT the owner's — confirm: the surrender rule, its band, and "a fight never ends STRIPPED".
--
-- MEASURED, production's real raid mix (dev-log; 20 rolls a raid; lit = this body, armour_turns_pct 0.5):
--   dark table   lost 27.1 %  crew 6.48 %   (lone ≤ 12 hands: lost 43.3 %, crew 9.76 %, STRIPPED 6.4 %)
--   0189 lit     lost 25.2 %  crew 7.13 %   (lone ≤ 12 hands: lost 40.3 %, crew 11.28 %, STRIPPED 13.4 %)
--   0202 lit     lost 25.2 %  crew 5.47 %   (lone ≤ 12 hands: lost 40.3 %, crew 8.56 %, STRIPPED 0)
--   won by every hull's accuracy 20 / 40 / 60 / 80: 56.8 / 63.3 / 70.9 / 78.7 %; by reach under / over the
--   xebec's 26: 61.6 / 68.4 %; by attack × 0 / 1 / 2: 51.5 / 63.4 / 73.8 % — the same as 0189 (no round moves).
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- No switch moves (combat_bite and armour_turns_pct are left as they stand — 0201 rolls them back, a later file
-- re-lights); no other knob value, no ALTER, no cron, no entry point, no client write. voyage.fight,
-- voyage.settle and every reader of the five outcomes are untouched. No top-level LOCK / SET LOCAL / BEGIN /
-- SET ROLE. Timings by RAISE NOTICE only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- ROW EXCLUSIVE on world_config (one description). CREATE OR REPLACE FUNCTION locks no table. The probe's writes
-- (its own knob values, in a block) are rolled back; a probe that meets a lock is retried 5 × 0.2 s.
--
-- SUPERSEDES by hunks sliced from the LIVE body (LF-normalised), each asserted to occur exactly once and to
-- reverse to its pre-image, ACL / volatility / definer / config unchanged: voyage.fight_resolve (0189).
-- ROLLBACK (forward migration): reverse the hunks (old text in hunks_0202) and restore the knob's description.
-- VERSION: 0202 (provisional; head + 1 at deploy). Applies on 0202 (or any head with 0189: no hunk here touches
-- what 0190–0202 moved).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
  if to_regprocedure('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)') is null then
    raise exception '0202 refuses: 0189 (the fight) is not in this world';
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0202(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0202 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)')) f(fn);

create temp table untouched_before_0202 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
  from (values ('voyage.fight(uuid, integer, uuid, numeric)'), ('voyage.settle(uuid, timestamp with time zone)'),
               ('public.armour_soak(numeric, numeric)'), ('public.armour_turns(uuid, numeric)'),
               ('voyage.escort_score(uuid)'), ('public.raid_crew_lost(uuid, numeric, numeric)'),
               ('public.fight_points(text)'), ('voyage.report_line(integer, text, jsonb)')) f(fn);

create temp table before_0202 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select jsonb_object_agg(key, value) from public.world_config
         where key like 'fight\_%' or key in ('combat_bite', 'armour_turns_pct')) as knobs;

-- the old core under a pg_temp name, so the probe can fight one day by both bodies
do $$
declare
  v_def text := (select def from defs_before_0202);
  v_new text := 'CREATE OR REPLACE FUNCTION pg_temp.fight_resolve_b0202(';
begin
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION voyage.fight_resolve(', v_new);
  if pg_temp.occurs_0202(v_def, v_new) <> 1 then
    raise exception '0202 self-assert FAIL: could not rename the pre-image of voyage.fight_resolve';
  end if;
  execute v_def;
end $$;

-- ── 2. THE HUNKS (old → new), sliced from the live body ────────────────────────────────────────
create temp table hunks_0202 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0202 values
-- the header says what the boarding now does
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 1,
$h$--             weighed for a fight hand to hand — read against fight_board_bands: DRIVEN_OFF, RANSOM,
--             PLUNDERED, STRIPPED.
$h$,
$h$--             weighed for a fight hand to hand — read against fight_board_bands: DRIVEN_OFF, RANSOM,
--             PLUNDERED; 0202: below the last band the crew SURRENDERS (PLUNDERED, never STRIPPED) — a crew that
--             cannot hold the deck yields its cargo rather than die for it. NOT the owner's — confirm.
$h$),
-- a place for the surrender
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 2,
$h$  v_ratio  numeric;
begin
$h$,
$h$  v_ratio  numeric;
  v_surrender boolean := false;   -- 0202: the boarding fell below the last band, and the crew surrendered
begin
$h$),
-- THE SURRENDER: below the last band, PLUNDERED — not STRIPPED
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 3,
$h$    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'
                      when v_ratio >= (v_bands->>1)::numeric then 'RANSOM'
                      when v_ratio >= (v_bands->>2)::numeric then 'PLUNDERED'
                      else 'STRIPPED' end;
$h$,
$h$    -- 0202: below the last band the crew cannot hold the deck, and surrenders: the raiders take what they can
    -- carry (PLUNDERED) and nobody dies defending a lost deck — a fight never ends STRIPPED
    v_surrender := v_ratio < (v_bands->>2)::numeric;
    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'
                      when v_ratio >= (v_bands->>1)::numeric then 'RANSOM'
                      else 'PLUNDERED' end;
$h$),
-- the boarding's closing line and the day's sentence say so
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 4,
$h$                           || case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                             when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                             when 'PLUNDERED'  then ' They board and take what they can carry.'
                                             else ' They board and take everything but the ships.' end);
    v_sentence := case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                 when 'RANSOM'     then 'They came alongside and we paid them off.'
                                 when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
                                 else 'They took everything but the ships themselves.' end;
$h$,
$h$                           || case when v_surrender then ' You surrender; they board and take what they can carry.'
                                   else case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                                       when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                                       else ' They board and take what they can carry.' end end);
    v_sentence := case when v_surrender then 'We surrendered, and they took what they could carry.'
                       else case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                           when 'RANSOM'     then 'They came alongside and we paid them off.'
                                           else 'They came aboard and took what they could carry.' end end;
$h$);

create or replace function pg_temp.recut_0202(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0202 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0202(v_def, h.old);
    if v_n <> 1 then
      raise exception '0202 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0202(fn) from defs_before_0202 order by fn;

comment on function voyage.fight_resolve(uuid, int, numeric, numeric, jsonb) is
  '0189 / 0202: THE FIGHT — sighting, rounds of range / accuracy / attack / armour, boarding (below the last band the '
  'crew surrenders: PLUNDERED, never STRIPPED); deterministic per (voyage, day). Returns {outcome, rounds[], '
  'hull_lost, raiders, first, hits}. Read by voyage.fight. Server-only.';

update public.world_config
   set description = '0189 / 0202: at the boarding, your hulls'' (crew × fight_hand_value × (1 + a Boarder''s share) + tier × 3) '
                     '× hull left against theirs: at least the first → driven off, the second → ransom, below it → plundered; '
                     'below the third the crew surrenders (plundered, never stripped — 0202). NOT the owner''s — confirm.'
 where key = 'fight_board_bands';

-- ── 3. THE PROBE (pure: the core on crafted hulls, a fixed seed, its own knob values; rolled back whole) ──
-- one hull set against one raider strength, p_days days, by the old body and the new
create or replace function pg_temp.duel_0202(p_ships jsonb, p_raider numeric, p_days int, p_escort numeric)
returns table (day int, old jsonb, new jsonb)
language sql
as $$
  select d, pg_temp.fight_resolve_b0202('00000000-0202-4000-8000-0000000000ff'::uuid, d, p_raider, p_escort, p_ships),
            voyage.fight_resolve('00000000-0202-4000-8000-0000000000ff'::uuid, d, p_raider, p_escort, p_ships)
    from generate_series(1, p_days) d
$$;

create or replace function pg_temp.engine_0202(p_ships jsonb, p_raider numeric, p_days int, p_escort numeric default 11.74)
returns jsonb
language sql
as $$
  with f as (select voyage.fight_resolve('00000000-0202-4000-8000-0000000000fe'::uuid, d, p_raider, p_escort, p_ships) j
               from generate_series(1, p_days) d)
  select jsonb_build_object(
    'won', count(*) filter (where j->>'outcome' in ('EVADED', 'DRIVEN_OFF')),
    'lost', count(*) filter (where j->>'outcome' in ('PLUNDERED', 'STRIPPED')),
    'stripped', count(*) filter (where j->>'outcome' = 'STRIPPED'),
    'n', count(*))
  from f
$$;

create temp table duel_0202 (set_name text, raider numeric, day int, old jsonb, new jsonb) on commit drop;
create temp table engine_0202 (j jsonb) on commit drop;

create or replace function pg_temp.probe_0202()
returns void
language plpgsql
as $$
declare
  v_carlat jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0202-4000-8000-0000000000a1', 'name', 'Probe Carlat',
                      'tier', 1, 'hull', 550, 'maxd', 550, 'crew', 12, 'attack', 55, 'accuracy', 40, 'reach', 25, 'armour', 12,
                      'sighting', 10, 'gear', jsonb_build_array('Boarding Gear')));
  v_barca  jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0202-4000-8000-0000000000a2', 'name', 'Probe Barca',
                      'tier', 1, 'hull', 400, 'maxd', 400, 'crew', 8, 'attack', 35, 'accuracy', 0, 'reach', 0, 'armour', 5,
                      'sighting', 8));
  v_rows   jsonb := '[]'::jsonb;
  v_eng    jsonb;
  v_t0     timestamptz := clock_timestamp();
begin
  begin
    -- OWN PRECONDITIONS: 0189's knob values and armour at 0.5 (0200's), whatever the world holds; rolled back
    update public.world_config set value = '"xebec"'::jsonb where key = 'fight_raider_class';
    update public.world_config set value = '[["LONG",0.6],["LONG",0.6],["LONG",0.6],["MEDIUM",0.8],["MEDIUM",0.8],["CLOSE",1.0]]'::jsonb
     where key = 'fight_ranges';
    update public.world_config set value = '0.7'::jsonb where key = 'fight_damage_per_attack';
    update public.world_config set value = '0.15'::jsonb where key = 'fight_raider_break';
    update public.world_config set value = '0.03'::jsonb where key = 'fight_evade_per_sighting';
    update public.world_config set value = '0.30'::jsonb where key = 'fight_evade_max';
    update public.world_config set value = '2.0'::jsonb where key = 'fight_standoff_ratio';
    update public.world_config set value = '0.15'::jsonb where key = 'fight_hand_value';
    update public.world_config set value = '[1.2, 0.7, 0.3]'::jsonb where key = 'fight_board_bands';
    update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';
    -- (A) THE DUEL: a lone carlat (12 hands, Boarding Gear) and an unarmed barca (8 hands) against production's
    --     raider strengths, 120 days each, by the old body and the new
    select coalesce(jsonb_agg(jsonb_build_object('set', s.nm, 'raider', r.r, 'day', x.day, 'old', x.old, 'new', x.new)), '[]'::jsonb)
      into v_rows
      from (values ('carlat', v_carlat, 11.74), ('barca', v_barca, 6.66)) s(nm, ships, esc)
     cross join (values (6.0), (12.0), (18.0), (24.0)) r(r)
     cross join lateral pg_temp.duel_0202(s.ships, r.r, 120, s.esc) x;
    -- (B) THE ENGINE: range, accuracy, attack and crew still decide (the new body; 300 days, fixed seed)
    v_eng := jsonb_build_object(
      'base',     pg_temp.engine_0202(v_carlat, 12, 300),
      'reach',    pg_temp.engine_0202(jsonb_set(v_carlat, '{0,reach}', '60'), 12, 300),
      'accuracy', pg_temp.engine_0202(jsonb_set(v_carlat, '{0,accuracy}', '70'), 12, 300),
      'attack',   pg_temp.engine_0202(jsonb_set(v_carlat, '{0,attack}', '110'), 12, 300),
      'crew',     pg_temp.engine_0202(jsonb_set(v_carlat, '{0,crew}', '40'), 12, 300),
      'unarmed',  pg_temp.engine_0202(jsonb_set(jsonb_set(v_carlat, '{0,attack}', '0'), '{0,accuracy}', '0'), 12, 300),
      'heavy',    pg_temp.engine_0202(v_barca, 24, 300, 6.66),
      'same',     voyage.fight_resolve('00000000-0202-4000-8000-0000000000fe'::uuid, 7, 24, 6.66, v_barca)
                    = voyage.fight_resolve('00000000-0202-4000-8000-0000000000fe'::uuid, 7, 24, 6.66, v_barca),
      'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    raise exception 'PROBE_ROLLBACK_0202';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0202' then raise; end if;
  end;
  -- the answers survive the rollback in plpgsql variables; the knobs do not
  insert into duel_0202 select x->>'set', (x->>'raider')::numeric, (x->>'day')::int, x->'old', x->'new' from jsonb_array_elements(v_rows) x;
  insert into engine_0202 values (v_eng);
end $$;

do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      perform pg_temp.probe_0202();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0202 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 4. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  v_d     record;
  v_h     record;
  v_pp    record;
  v_def   text;
  v_eng   jsonb := (select j from engine_0202);
  v_n     int;
  v_s     int;
  v_bad   int;
  v_ex    jsonb;
begin
  select * into v_b from before_0202;
  select count(*), count(*) filter (where old->>'outcome' = 'STRIPPED') into v_n, v_s from duel_0202;
  if v_n <> 960 or v_eng is null then
    raise exception '0202 self-assert FAIL: the probe returned % duel day(s) of 960, engine %', v_n, v_eng;
  end if;
  -- (a) NON-VACUOUS: the old body strips on some of the probe's days (else this proves nothing)
  if v_s = 0 then
    raise exception '0202 self-assert FAIL: the old body stripped on none of the probe''s 960 days — it proves nothing';
  end if;
  -- (b) EVERY DAY THE OLD BODY DID NOT STRIP IS THE SAME FIGHT, word for word
  select count(*) into v_bad from duel_0202 where old->>'outcome' <> 'STRIPPED' and old is distinct from new;
  if v_bad > 0 then
    select jsonb_build_object('old', old, 'new', new) into v_ex from duel_0202
     where old->>'outcome' <> 'STRIPPED' and old is distinct from new limit 1;
    raise exception '0202 self-assert FAIL: % fight(s) that did not end STRIPPED changed: %', v_bad, v_ex;
  end if;
  -- (c) EVERY DAY IT STRIPPED, THE CREW SURRENDERS: PLUNDERED; the same sighting, rounds, hits and hull; the
  --     closing line and the sentence say so
  select count(*) into v_bad from duel_0202
   where old->>'outcome' = 'STRIPPED'
     and not (new->>'outcome' = 'PLUNDERED'
              and new->>'sentence' = 'We surrendered, and they took what they could carry.'
              and (new - 'outcome' - 'sentence' - 'rounds') = (old - 'outcome' - 'sentence' - 'rounds')
              and jsonb_array_length(new->'rounds') = jsonb_array_length(old->'rounds')
              and (new->'rounds') - (jsonb_array_length(new->'rounds') - 1) = (old->'rounds') - (jsonb_array_length(old->'rounds') - 1)
              and (new->'rounds'->>(jsonb_array_length(new->'rounds') - 1)) like 'Close quarters: % You surrender; they board and take what they can carry.'
              and (new->'rounds'->>(jsonb_array_length(new->'rounds') - 1))
                  = replace(old->'rounds'->>(jsonb_array_length(old->'rounds') - 1),
                            ' They board and take everything but the ships.', ' You surrender; they board and take what they can carry.'));
  if v_bad > 0 then
    select jsonb_build_object('old', old, 'new', new) into v_ex from duel_0202 where old->>'outcome' = 'STRIPPED' limit 1;
    raise exception '0202 self-assert FAIL: % stripped day(s) did not become a surrender, e.g. %', v_bad, v_ex;
  end if;
  -- (d) THE NEW BODY NEVER STRIPS
  if exists (select 1 from duel_0202 where new->>'outcome' = 'STRIPPED') or (v_eng->'heavy'->>'stripped')::int <> 0
     or (v_eng->'base'->>'stripped')::int <> 0 then
    raise exception '0202 self-assert FAIL: a fight still ended STRIPPED: %', v_eng;
  end if;
  -- (e) THE ENGINE: range, accuracy and attack each win more often; crew loses less; unarmed wins less; one day
  --     fought twice is the same fight
  if not ((v_eng->'reach'->>'won')::int > (v_eng->'base'->>'won')::int
          and (v_eng->'accuracy'->>'won')::int > (v_eng->'base'->>'won')::int
          and (v_eng->'attack'->>'won')::int > (v_eng->'base'->>'won')::int
          and (v_eng->'crew'->>'lost')::int < (v_eng->'base'->>'lost')::int
          and (v_eng->'unarmed'->>'won')::int < (v_eng->'base'->>'won')::int
          and (v_eng->>'same')::boolean) then
    raise exception '0202 self-assert FAIL: the engine''s properties do not hold: %', v_eng;
  end if;

  -- (f) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; the rest untouched
  for v_d in select * from defs_before_0202 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0202 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0202(v_def, v_h.new) <> 1 then
        raise exception '0202 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0202 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0202 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from untouched_before_0202 loop
    if replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '') <> v_d.def then
      raise exception '0202 self-assert FAIL: % moved — it was to be left untouched', v_d.fn;
    end if;
  end loop;

  -- (g) THE READER: the core is read by voyage.fight alone (and by nothing this file planted)
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
         and p.prosrc like '%voyage.fight_resolve(%' and p.proname <> 'fight_resolve') is distinct from 'voyage.fight' then
    raise exception '0202 self-assert FAIL: voyage.fight_resolve is read by something other than voyage.fight';
  end if;

  -- (h) THE KNOBS AND THE SWITCHES are what they were (the probe's values rolled back); the wall unmoved
  if (select jsonb_object_agg(key, value) from public.world_config
       where key like 'fight\_%' or key in ('combat_bite', 'armour_turns_pct')) is distinct from v_b.knobs then
    raise exception '0202 self-assert FAIL: a fight knob or a switch moved: before % after %', v_b.knobs,
      (select jsonb_object_agg(key, value) from public.world_config where key like 'fight\_%' or key in ('combat_bite', 'armour_turns_pct'));
  end if;
  if (select description from public.world_config where key = 'fight_board_bands') not like '0189 / 0202:%surrenders%' then
    raise exception '0202 self-assert FAIL: fight_board_bands does not say where the crew surrenders';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, 'voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 'execute')) then
    raise exception '0202 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach the core';
  end if;

  raise notice '0202 self-assert ok: A CREW THAT CANNOT HOLD THE DECK SURRENDERS. DUEL (a lone carlat and an unarmed barca × raiders 6 / 12 / 18 / 24 × 120 days, old body vs new, 0189''s knobs, armour 0.5, rolled back): % of % day(s) the old body STRIPPED — each now PLUNDERED with the same rounds, hits and hull and "We surrendered, and they took what they could carry."; the other % word for word. ENGINE (300 days, fixed seed, won / lost): base %/%, reach 60 %/%, accuracy 70 %/%, attack 110 %/%, crew 40 lost %, unarmed won %; a barca against raiders 24: won %, lost %, stripped %. Probe % ms. 1 body reverses, 8 untouched, knobs and switches unmoved (combat_bite %, armour_turns_pct %), the core read by voyage.fight alone, no entry point.',
    v_s, v_n, v_n - v_s,
    v_eng->'base'->>'won', v_eng->'base'->>'lost', v_eng->'reach'->>'won', v_eng->'reach'->>'lost',
    v_eng->'accuracy'->>'won', v_eng->'accuracy'->>'lost', v_eng->'attack'->>'won', v_eng->'attack'->>'lost',
    v_eng->'crew'->>'lost', v_eng->'unarmed'->>'won',
    v_eng->'heavy'->>'won', v_eng->'heavy'->>'lost', v_eng->'heavy'->>'stripped', v_eng->>'ms',
    v_b.knobs->>'combat_bite', v_b.knobs->>'armour_turns_pct';
end $$;
