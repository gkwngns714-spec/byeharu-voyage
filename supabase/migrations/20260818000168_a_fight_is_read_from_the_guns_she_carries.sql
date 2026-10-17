-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0168 — A FIGHT IS READ FROM THE GUNS SHE CARRIES  (SHIPS_AND_GEAR S4 "combat stats bite", with
--        SKILLS_AND_CAPTAINS K10 "combat traits" — DARK: combat_bite false, armour_turns_pct 0)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_GEAR.md §5 and §8 row S4 (§4.4: what each stat feeds), docs/SKILLS_AND_CAPTAINS.md §4.2,
-- §4.11, §5 and §8 row K10 ("lands in S4's own proof … S4's switch"), docs/SHIPS_AND_SKILLS.md §8 (S4
-- "stays where it was"). The danger roll is the game's whole combat (DESIGN B.6: no visual combat, ever —
-- a probability table resolved here and reported as prose). Its PIRATES arm still reads the class's
-- `guns`: the broadside guns, boarding gear and every attack piece since 0068 buy `attack` that NO roll
-- reads, and armour — on every hull since 0074 — turns nothing. The Gunner and the Boarder (0156) sit in
-- kits saying "Works when combat arrives", and public.crew_pct refuses their ship effects (0157).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) KNOBS (only where absent): combat_bite false — S4's switch (SKILLS_AND_CAPTAINS §4.11 "S4's combat
--     switch"); armour_turns_pct 0 — SHIPS_AND_GEAR S4's own knob, landing at 0.
-- (2) THE READINGS:
--       public.combat_bite_on()          THE switch (inlinable, as public.skills_bite_on).
--       voyage.escort_score(fleet)       THE escort score of the pirate roll, moved out of voyage.settle's
--                                        PIRATES arm. Off: DESIGN B.6's Σ(guns + crew × 0.02 + tier × 3),
--                                        verbatim. On: Σ(world.ship_stat(attack) / 10 + crew × 0.02 + tier × 3)
--                                        — §5's formula: what she CARRIES (gear, and K10's Boarder) counts.
--                                        A hull with nothing mounted reads the same either way (`guns` =
--                                        attack / 10 for every class, asserted below).
--       public.armour_turns(ship, loss)  THE armour rule: a hull loss × (1 − armour / 100 × armour_turns_pct),
--                                        never below 0, rounded to the hundredth; the knob at 0 gives back
--                                        the loss ITSELF (the same numeric, not × 1).
--       public.ship_crew_terms(ship, st) K10: while combat_bite is on, each SHIP-scope crew effect whose
--                                        reader is world.ship_stats (Gunner: accuracy, reach; Boarder:
--                                        attack) × (1 + public.crew_pct(fleet, ship, effect)), rounded to the
--                                        stat's own scale — the order public.ship_hold_capacity applies the
--                                        Quartermaster in (the captains last). Off: the stats untouched.
-- (3) THE HUNKS (sliced from the LIVE bodies): voyage.settle — the PIRATES arm reads voyage.escort_score; the
--     STORM arm's and the raid's hull loss go through public.armour_turns. world.ship_stats — both
--     branches' answers through public.ship_crew_terms. public.crew_pct — a ship effect is answered (for the
--     captains seated on p_ship) while combat_bite is on, refused as before while it is off.
--     world.captain_card — a combat trait's "Works when combat arrives." is not served while combat_bite is
--     on (it would no longer be true).
-- (4) public.ship_classes.guns is commented as what it now is: a data mirror of attack / 10.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No row moves, no ALTER, no cron, no entry point, no client write. DARK, every live answer is the old
-- one: every hull's ship_stats and ship_view, every fleet's escort, every fleet × crew effect's crew_pct
-- (a refusal compared as a refusal), every captain's card, every hull's storm and raid loss — old body vs
-- new, one statement each. NOT HERE, said plainly (docs/dev-log/2026-10-18-s4-k10-combat-stats.md):
--   • accuracy, reach and sighting feed no roll (§4.4: the roll has no "shot tells" or range step) — so the
--     Gunner's accuracy and reach show on the ship and change no outcome;
--   • gear actives (SHIPS_AND_SKILLS §6.1: a PIRATES / STORM trigger, a consumable spent, half without it;
--     `gear_actives_bite`) — "S4 and the hazard re-cut"; the hazard re-cut is not planned to a row;
--   • trait actives with trigger = PIRATES (SKILLS_AND_CAPTAINS §4.11, Origin's combat actives) — no such
--     trait or value is authored, and Origin's are hex-board battle moves; none is invented here;
--   • SHOAL_WATER's hull loss (S4 names storm and raid only).
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Heavy reads first (pre-images, the old bodies under pg_temp names). Then ROW EXCLUSIVE on world_config
-- (two inserts) and a COMMENT on public.ship_classes (SHARE UPDATE EXCLUSIVE — conflicts with no read or
-- row write). CREATE OR REPLACE FUNCTION locks no table. Probe writes are rolled back; a probe that meets a
-- lock is retried 5 × 0.2 s, then LOCK CONTENTION. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once and
-- to reverse to its pre-image, ACL / volatility / definer / config unchanged: voyage.settle (0165),
-- world.ship_stats (0163), public.crew_pct (0161), world.captain_card (0166).
--
-- ROLLBACK: combat_bite false and armour_turns_pct 0 (one UPDATE each) is every answer of today. Full
-- (forward migration): reverse the four bodies' hunks (old text in hunks_0168); drop voyage.escort_score,
-- public.armour_turns, public.ship_crew_terms, public.combat_bite_on; delete the two knobs.
-- VERSION: 0168 (provisional; renumbered to head + 1 at deploy). Applies on 0167 (S18).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0168(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- one call's OUTCOME: its answer as text, or the refusal itself — so an old and a new body are compared
-- answer for answer AND refusal for refusal, whatever plan reaches the row (0166's lesson)
create or replace function pg_temp.outcome_0168(p_sql text)
returns text
language plpgsql
as $$
declare
  r text;
begin
  execute p_sql into r;
  return coalesce(r, '<null>');
exception when others then
  return 'REFUSED ' || sqlstate || ': ' || sqlerrm;
end $$;

-- run one statement with its writes rolled back; its jsonb answer, or the refusal it raised
create or replace function pg_temp.rb_0168(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r jsonb;
begin
  begin
    execute p_sql into r;
    raise exception 'RB_0168';
  exception when others then
    if sqlerrm <> 'RB_0168' then r := jsonb_build_object('refused', sqlerrm); end if;
  end;
  return r;
end $$;

create temp table reads_0168 (phase text, what text, n bigint, ms numeric) on commit drop;
create or replace function pg_temp.time_reads_0168(p_phase text)
returns void
language plpgsql
as $$
declare
  v_t0  timestamptz;
  v_ids uuid[];
  v_fl  uuid[];
begin
  select array_agg(s.id order by s.id) into v_ids from public.ships s join public.players p on p.id = s.player_id where p.is_npc;
  select array_agg(f.id order by f.id) into v_fl from public.fleets f join public.players p on p.id = f.player_id where p.is_npc;
  v_t0 := clock_timestamp();
  perform world.ship_stats(x) from unnest(v_ids) x;
  insert into reads_0168 values (p_phase, 'ship_stats', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(x), public.ship_hold_capacity(x) from unnest(v_ids) x;
  insert into reads_0168 values (p_phase, 'speed+hold', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  -- (ship_view is not timed here: section 5 reads it old and new for every hull, and on prod each read is ~16 ms)
  v_t0 := clock_timestamp();
  if p_phase = 'before' then
    perform (select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0)
               from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = x) from unnest(v_fl) x;
  else
    perform voyage.escort_score(x) from unnest(v_fl) x;
  end if;
  insert into reads_0168 values (p_phase, 'escort', coalesce(cardinality(v_fl), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0168 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.settle(uuid, timestamp with time zone)'), ('world.ship_stats(uuid)'),
               ('public.crew_pct(uuid, uuid, text, uuid, timestamp with time zone)'), ('world.captain_card(uuid)')) f(fn);

create temp table untouched_before_0168 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
  from (values ('world.ship_stat(uuid, text)'), ('world.ship_view(uuid)'), ('public.crew_terms(uuid, timestamp with time zone)'),
               ('public.raid_crew_lost(uuid, numeric, numeric)'), ('voyage.storm_hull_lost(uuid, numeric, numeric)'),
               ('public.ship_hold_capacity(uuid)'), ('world.crew_bonuses(uuid)'), ('public.trait_in_use(text)'),
               ('world.ship_seats(uuid)')) f(fn);

create temp table before_0168 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config where key in ('combat_bite', 'armour_turns_pct')) as own_knobs;

-- the old bodies under pg_temp names: ship_stats, crew_pct, captain_card; the old ship_view composing the old stats
do $$
declare
  d     record;
  v_def text;
  v_new text;
begin
  for d in select * from defs_before_0168 where fn <> 'voyage.settle(uuid, timestamp with time zone)' loop
    v_new := 'CREATE OR REPLACE FUNCTION pg_temp.' || replace(split_part(d.fn, '(', 1), '.', '_') || '_b0168(';
    v_def := replace(d.def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(', v_new);
    if pg_temp.occurs_0168(v_def, v_new) <> 1 then
      raise exception '0168 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    execute v_def;
  end loop;
  v_def := replace(pg_get_functiondef('world.ship_view(uuid)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0168(v_def, 'world.ship_stats(s.id)') <> 1 then
    raise exception '0168 self-assert FAIL: world.ship_view does not read world.ship_stats exactly once where expected';
  end if;
  v_def := replace(replace(v_def, 'world.ship_stats(s.id)', 'pg_temp.world_ship_stats_b0168(s.id)'),
                   'CREATE OR REPLACE FUNCTION world.ship_view(', 'CREATE OR REPLACE FUNCTION pg_temp.world_ship_view_b0168(');
  execute v_def;
end $$;

select pg_temp.time_reads_0168('before');

-- ── 2. THE KNOBS (only where absent: a knob already set is left alone) ──────────────────────────
insert into public.world_config (key, value, description) values
  ('combat_bite', 'false'::jsonb,
   '0168 (S4 + K10, docs/SHIPS_AND_GEAR.md §5, docs/SKILLS_AND_CAPTAINS.md §4.11): THE switch of combat stats. '
   'Off: the pirate roll''s escort is DESIGN B.6''s Σ(guns + crew × 0.02 + tier × 3), the combat traits '
   'add nothing and public.crew_pct refuses their ship effects. On: the escort reads what she carries '
   '(world.ship_stat attack / 10), and a seated Gunner / Boarder adds to her accuracy, reach / attack '
   '(public.ship_crew_terms; counted while crew_bite is on, as every trait beyond a job''s live effect).'),
  ('armour_turns_pct', '0'::jsonb,
   '0168 (S4, docs/SHIPS_AND_GEAR.md §5): the share of a storm''s or a raid''s hull loss armour turns — '
   'loss × (1 − armour / 100 × this), public.armour_turns. 0 = off (the loss itself).')
on conflict (key) do nothing;

-- ── 3. THE READINGS ────────────────────────────────────────────────────────────────────────────
create or replace function public.combat_bite_on()
returns boolean
language sql
stable
as $$
  -- 0168 (S4): THE switch (world_config combat_bite). A plain SQL read — no SET, no SECURITY DEFINER — so the
  -- planner inlines it, as public.skills_bite_on (0133). Missing row = off.
  select coalesce((select c.value = 'true'::jsonb from public.world_config c where c.key = 'combat_bite'), false)
$$;
comment on function public.combat_bite_on() is
  '0168 (S4): THE switch of combat stats (world_config combat_bite), inlinable. Server-only.';
revoke all on function public.combat_bite_on() from public, anon, authenticated;

create or replace function voyage.escort_score(p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0168 (S4, docs/SHIPS_AND_GEAR.md §5): THE ESCORT SCORE of the pirate roll for this fleet — moved verbatim out
-- of voyage.settle's PIRATES arm (0027 onward), as voyage.storm_hull_lost was out of its STORM arm (0154).
-- Who reads it: voyage.settle's PIRATES arm, nothing else. Why here: the one place "how hard she is to take"
-- lives, so the next reader (a report, a screen) composes it instead of summing again.
declare
  v numeric;
begin
  if not public.combat_bite_on() then
    -- DESIGN B.6: escort_score = Σ(guns + crew×0.02 + hull_class×3). The class's guns — nothing she carries.
    select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) into v
      from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet;
    return v;
  end if;
  -- §5: what she CARRIES — world.ship_stat, the one reading of a hull's attack (the class, her gear, her
  -- company's skills and, K10, the Boarder in her cabins) — a tenth of it, as `guns` was a tenth of the class's.
  select coalesce(sum(world.ship_stat(sh.id, 'attack') / 10 + sh.crew * 0.02 + c.tier * 3), 0) into v
    from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet;
  return v;
end $$;
comment on function voyage.escort_score(uuid) is
  '0168 (S4): THE escort score of the pirate roll (DESIGN B.6). Off (combat_bite false): Σ(guns + crew × 0.02 + '
  'tier × 3); on: Σ(world.ship_stat attack / 10 + crew × 0.02 + tier × 3). Read by voyage.settle''s PIRATES arm. Server-only.';
revoke all on function voyage.escort_score(uuid) from public, anon, authenticated;

create or replace function public.armour_turns(p_ship uuid, p_loss numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0168 (S4, docs/SHIPS_AND_GEAR.md §4.4 and §5): THE ARMOUR RULE — what is left of a hull loss once her armour
-- (world.ship_stat, the one reading) has turned its share: loss × (1 − armour / 100 × armour_turns_pct), never
-- below 0, to the hundredth. Read by voyage.settle's STORM arm and its raid. The knob at 0 is OFF: the loss
-- itself comes back — the same numeric, so a settled day writes what it wrote before, to the digit.
declare
  v_k numeric := public.wc_num('armour_turns_pct');
begin
  if v_k <= 0 then
    return p_loss;
  end if;
  return round(p_loss * greatest(0, 1 - world.ship_stat(p_ship, 'armour') / 100.0 * v_k), 2);
end $$;
comment on function public.armour_turns(uuid, numeric) is
  '0168 (S4): THE armour rule — a hull loss × (1 − armour / 100 × armour_turns_pct), ≥ 0; the knob at 0 returns '
  'the loss itself. Read by voyage.settle (STORM, the raid). Server-only.';
revoke all on function public.armour_turns(uuid, numeric) from public, anon, authenticated;

create or replace function public.ship_crew_terms(p_ship uuid, p_stats jsonb)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
-- 0168 (K10, docs/SKILLS_AND_CAPTAINS.md §4.2, §4.11, §5): THE CAPTAINS' SHARE OF A HULL'S STATS — while combat_bite
-- is on, each SHIP-scope crew effect read by world.ship_stats (the Gunner's accuracy and reach, the Boarder's
-- attack; public.crew_effects, data) × (1 + public.crew_pct(her fleet, her, effect)) — the captains seated on HER,
-- capped, Command-lifted — rounded to the stat's own scale. Applied last, as public.ship_hold_capacity applies the
-- Quartermaster. Called only by world.ship_stats (both branches). Off, or no ship: the stats as given.
declare
  v       jsonb := p_stats;
  e       record;
  x       numeric;
  v_pct   numeric;
  v_fleet uuid;
begin
  if p_stats is null or not public.combat_bite_on() then
    return p_stats;
  end if;
  select s.fleet_id into v_fleet from public.ships s where s.id = p_ship;
  for e in select ce.code from public.crew_effects ce
            where ce.scope = 'ship' and ce.reader = 'world.ship_stats' order by ce.ord loop
    if not (v ? e.code) then
      -- NO_SPAGHETTI §7C: a ship effect whose stat the hull does not serve is a broken catalogue, not a zero
      raise exception 'E_NO_SUCH_STAT: crew effect % names no stat of world.ship_stats', e.code using errcode = 'P0001';
    end if;
    x := (v ->> e.code)::numeric;
    v_pct := public.crew_pct(v_fleet, p_ship, e.code);
    if x is not null and v_pct > 0 then
      v := jsonb_set(v, array[e.code], to_jsonb(round(x * (1 + v_pct), scale(x))));
    end if;
  end loop;
  return v;
end $$;
comment on function public.ship_crew_terms(uuid, jsonb) is
  '0168 (K10): while combat_bite, a hull''s ship-scope crew effects (Gunner: accuracy, reach; Boarder: attack) × '
  '(1 + public.crew_pct for her) — called by world.ship_stats only. Server-only.';
revoke all on function public.ship_crew_terms(uuid, jsonb) from public, anon, authenticated;

-- ── 4. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0168 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0168 values
-- voyage.settle: the PIRATES arm reads the one escort score
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$      -- DESIGN B.6: escort_score = Σ(guns + crew×0.02 + hull_class×3). The ENTIRE combat system.
      select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) into v_escort
        from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet;
$h$,
$h$      -- DESIGN B.6's escort score — 0168 (S4): voyage.escort_score, the one reading (the class's own figure
      -- while combat_bite is off; what she carries, attack / 10, while it is on). The ENTIRE combat system.
      v_escort := voyage.escort_score(p_fleet);
$h$),
-- voyage.settle: the STORM's loss, less what her armour turns
('voyage.settle(uuid, timestamp with time zone)', 2,
$h$        v_lost := voyage.storm_hull_lost(v.id, s.maxd, h.magnitude);   -- 0154 (K2): the one storm rule (Weather Lore at departure)
$h$,
$h$        -- 0154 (K2): the one storm rule (Weather Lore at departure); 0168 (S4): less what her armour turns
        v_lost := public.armour_turns(s.id, voyage.storm_hull_lost(v.id, s.maxd, h.magnitude));
$h$),
-- voyage.settle: the raid's loss, less what her armour turns
('voyage.settle(uuid, timestamp with time zone)', 3,
$h$               durability = greatest(0, sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                        when 'PLUNDERED' then 0.80
                                                                        else 1.00 end))
$h$,
$h$               -- 0168 (S4): the raid's hull loss less what her armour turns (public.armour_turns; at 0, the loss itself)
               durability = greatest(0, sh.durability - public.armour_turns(sh.id,
                              sh.durability - sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                              when 'PLUNDERED' then 0.80
                                                                              else 1.00 end)))
$h$),
-- world.ship_stats: both branches' answers through the captains' share (K10)
('world.ship_stats(uuid)', 1,
$h$  if 'ship' = any(public.house_skill_scopes(null, p_ship)) then
    return (
    with d as (
$h$,
$h$  if 'ship' = any(public.house_skill_scopes(null, p_ship)) then
    -- 0168 (K10): … and the captains seated on her (public.ship_crew_terms: nothing while combat_bite is off)
    return public.ship_crew_terms(p_ship, (
    with d as (
$h$),
('world.ship_stats(uuid)', 2,
$h$     where s.id = p_ship
    );
  end if;
  end if;
$h$,
$h$     where s.id = p_ship
    ));
  end if;
  end if;
$h$),
('world.ship_stats(uuid)', 3,
$h$  return (
  -- 0124: A HULL'S TEN EFFECTIVE STATS, ONE QUERY.$h$,
$h$  -- 0168 (K10): … and the captains seated on her (public.ship_crew_terms: nothing while combat_bite is off)
  return public.ship_crew_terms(p_ship, (
  -- 0124: A HULL'S TEN EFFECTIVE STATS, ONE QUERY.$h$),
('world.ship_stats(uuid)', 4,
$h$   where s.id = p_ship
  );
end $function$$h$,
$h$   where s.id = p_ship
  ));
end $function$$h$),
-- public.crew_pct: a ship effect, for the captains on her, while combat_bite is on
('public.crew_pct(uuid, uuid, text, uuid, timestamp with time zone)', 1,
$h$  if v_scope <> 'fleet' then
    raise exception 'E_NOT_YET: % is a ship effect, read only when combat arrives (S4, K10)', p_effect using errcode = 'P0001';
  end if;
$h$,
$h$  -- 0168 (S4, K10): a SHIP effect (the combat traits) is answered for the captains seated on p_ship while
  -- combat_bite is on; while it is off, refused exactly as before
  if v_scope <> 'fleet' and not public.combat_bite_on() then
    raise exception 'E_NOT_YET: % is a ship effect, read only when combat arrives (S4, K10)', p_effect using errcode = 'P0001';
  end if;
$h$),
('public.crew_pct(uuid, uuid, text, uuid, timestamp with time zone)', 2,
$h$   where t.effect = p_effect
     and (p_effect <> 'category_spread'
$h$,
$h$   where t.effect = p_effect
     and (v_scope = 'fleet' or t.ship_id = p_ship)   -- 0168: a ship effect counts her own captains only
     and (p_effect <> 'category_spread'
$h$),
-- world.captain_card: "Works when combat arrives." is not served once it has
('world.captain_card(uuid)', 1,
$h$                                    (select ce.waits from public.trait_effects te join public.crew_effects ce on ce.code = te.effect
$h$,
$h$                                    -- 0168 (K10): a combat trait's "Works when combat arrives." goes once combat_bite is on
                                    (select case when ce.scope = 'ship' and public.combat_bite_on() then null else ce.waits end
                                       from public.trait_effects te join public.crew_effects ce on ce.code = te.effect
$h$);

create or replace function pg_temp.recut_0168(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0168 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0168(v_def, h.old);
    if v_n <> 1 then
      raise exception '0168 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0168(fn) from defs_before_0168 order by fn;

comment on column public.ship_classes.guns is
  '0003/0074/0168: a DATA MIRROR of attack / 10 for every class (asserted equal; scripts/build-ships.mjs writes it so). '
  'Since 0168 the pirate roll reads it only while combat_bite is off (voyage.escort_score); on, it reads world.ship_stat attack.';

select pg_temp.time_reads_0168('after');

-- ── 5. DARK, EVERY ROW: the old body vs the new, one statement each ────────────────────────────
create temp table hulls_0168 on commit drop as
select s.id as ship_id,
       world.ship_stats(s.id)::text as new_stats, pg_temp.world_ship_stats_b0168(s.id)::text as old_stats,
       world.ship_view(s.id)::text as new_view, pg_temp.world_ship_view_b0168(s.id)::text as old_view,
       -- the storm's loss at a middling sea, and the raid's three outcomes, as the column stores them
       (select round(c.durability * (0.08 + 0.17 * 0.5), 2) from public.ship_classes c where c.id = s.class_id) as storm_loss,
       public.armour_turns(s.id, (select round(c.durability * (0.08 + 0.17 * 0.5), 2) from public.ship_classes c where c.id = s.class_id))::text as new_storm,
       (select string_agg(greatest(0, s.durability * k)::numeric(8,2)::text, '/' order by k) from unnest(array[0.95, 0.80, 1.00]) k) as old_raid,
       (select string_agg(greatest(0, s.durability - public.armour_turns(s.id, s.durability - s.durability * k))::numeric(8,2)::text, '/' order by k)
          from unnest(array[0.95, 0.80, 1.00]) k) as new_raid
  from public.ships s;

create temp table fleets_0168 on commit drop as
select f.id as fleet_id,
       voyage.escort_score(f.id)::text as new_escort,
       (select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0)
          from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = f.id)::text as old_escort
  from public.fleets f;

-- every fleet × every crew effect (and, for a ship effect, every ship of hers): the answer or the refusal
create temp table crew_0168 on commit drop as
select q.fleet_id, q.ship_id, q.effect,
       pg_temp.outcome_0168(format('select public.crew_pct(%L, %L, %L)::text', q.fleet_id, q.ship_id, q.effect)) as new_out,
       pg_temp.outcome_0168(format('select pg_temp.public_crew_pct_b0168(%L, %L, %L)::text', q.fleet_id, q.ship_id, q.effect)) as old_out
  from (select f.id as fleet_id, null::uuid as ship_id, ce.code as effect
          from public.fleets f cross join public.crew_effects ce where ce.scope = 'fleet'
        union all
        select s.fleet_id, s.id, ce.code
          from public.ships s cross join public.crew_effects ce where ce.scope <> 'fleet') q;

create temp table cards_0168 on commit drop as
select o.id as officer_id,
       pg_temp.outcome_0168(format('select world.captain_card(%L)::text', o.id)) as new_out,
       pg_temp.outcome_0168(format('select pg_temp.world_captain_card_b0168(%L)::text', o.id)) as old_out
  from public.officers o;

-- ── 6. THE PROBE (its own company; lit inside, rolled back whole) ──────────────────────────────
-- is this captain (by code) in that cabin of that ship?
create or replace function pg_temp.seated_0168(p_code text, p_ship uuid)
returns boolean
language sql
as $$
  select exists (select 1 from public.captain_seats cs
                   join public.player_officers po on po.id = cs.player_officer_id
                   join public.officers o on o.id = po.officer_id
                  where o.code = p_code and cs.ship_id = p_ship and cs.seat = 1)
$$;

create or replace function pg_temp.probe_0168()
returns jsonb
language plpgsql
as $$
declare
  c_p     constant uuid := '00000000-0168-4000-8000-000000000001';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_p     uuid;
  v_pf    uuid;
  v_barca uuid;
  v_nau   uuid;
  v_out   jsonb := '{}'::jsonb;
  v_r     jsonb;
  v_old   numeric;
begin
  begin
    -- OWN PRECONDITIONS: combat, crew and skills dark; armour off
    update public.world_config set value = 'false'::jsonb where key in ('combat_bite', 'crew_bite', 'skills_bite');
    update public.world_config set value = '0'::jsonb where key = 'armour_turns_pct';
    -- P: a company at Lisbon — the barca it was founded with (Gaivota) and a nau
    v_p := public.new_house(c_p, 'Casa das Armas 0168', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0168', 10000000);
    select id into v_barca from public.ships where fleet_id = v_pf;
    v_nau := public.commission_ship(v_p, v_pf, 'nau', 'Prova Nau', false, true);
    v_old := (select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0)
                from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_pf);
    v_out := v_out || jsonb_build_object('bare', jsonb_build_object('old', v_old, 'dark', voyage.escort_score(v_pf)));

    -- (L1) LIT, NOTHING MOUNTED: the same escort to 4 places (guns = attack / 10)
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    v_out := jsonb_set(v_out, '{bare,lit}', to_jsonb(voyage.escort_score(v_pf)));
    -- (L2) BROADSIDE GUNS on the nau, through the door: dark the same as before, lit higher by their attack / 10
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_p, v_lis, 'broadside-guns', 1)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    v_r := cmd.do_fit(v_pf, jsonb_build_object('item', 'broadside-guns', 'ship', 'Prova Nau'));
    v_out := v_out || jsonb_build_object('guns', jsonb_build_object(
      'fit', v_r, 'mounted', exists (select 1 from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'broadside-guns'),
      'dark', voyage.escort_score(v_pf), 'attack', world.ship_stat(v_nau, 'attack'),
      'gun_attack', (select e.delta from public.item_effects e where e.item_code = 'broadside-guns' and e.stat = 'attack')));
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    v_out := jsonb_set(v_out, '{guns,lit}', to_jsonb(voyage.escort_score(v_pf)));

    -- (K1) THE BOARDER in the nau's Captain's cabin (seat 1, 100 %), her job active; crew still dark:
    --      a combat job is no live effect, so nothing yet (the stats = the old body's)
    v_r := public.sign_officer(v_p, 'TURGUT', v_pf);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0168 self-assert FAIL: the probe could not sign the Boarder: %', v_r;
    end if;
    v_r := public.seat_captain_for(v_p, 'TURGUT', v_nau, 1);
    v_out := v_out || jsonb_build_object('boarder', jsonb_build_object(
      'seat', v_r, 'seated', pg_temp.seated_0168('TURGUT', v_nau),
      'crew_dark', world.ship_stats(v_nau), 'crew_dark_old', pg_temp.world_ship_stats_b0168(v_nau)));
    -- (K2) crew lit too: her attack × (1 + her share), on HER ship only; the barca untouched; the escort rises again
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    perform public.captain_traits_set_for(v_p, 'TURGUT', array['BOARDER']);
    v_out := jsonb_set(v_out, '{boarder,lit}', jsonb_build_object(
      'pct_nau', public.crew_pct(v_pf, v_nau, 'attack'), 'pct_barca', public.crew_pct(v_pf, v_barca, 'attack'),
      'nau', world.ship_stats(v_nau), 'nau_old', pg_temp.world_ship_stats_b0168(v_nau),
      'barca', world.ship_stats(v_barca), 'barca_old', pg_temp.world_ship_stats_b0168(v_barca),
      'escort', voyage.escort_score(v_pf),
      'card_note', (select t->>'note' from jsonb_array_elements(world.captain_card((select id from public.officers where code = 'TURGUT'))->'traits') t
                     where t->>'code' = 'BOARDER')));
    -- (K3) combat off again (crew still lit): the stats are the old body's, and a ship effect is refused as before
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    v_out := jsonb_set(v_out, '{boarder,off}', jsonb_build_object(
      'nau', world.ship_stats(v_nau), 'nau_old', pg_temp.world_ship_stats_b0168(v_nau),
      'refusal', pg_temp.outcome_0168(format('select public.crew_pct(%L, %L, %L)::text', v_pf, v_nau, 'attack')),
      'card_note', (select t->>'note' from jsonb_array_elements(world.captain_card((select id from public.officers where code = 'TURGUT'))->'traits') t
                     where t->>'code' = 'BOARDER')));

    -- (K4) THE GUNNER in the nau's Captain's cabin (the Boarder put ashore; a hull that aims, accuracy and reach
    --      above 0): her accuracy and reach rise, her attack does not
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    v_r := public.seat_captain_for(v_p, 'TURGUT', null);
    v_r := public.sign_officer(v_p, 'TARTAGLIA', v_pf);
    v_r := public.seat_captain_for(v_p, 'TARTAGLIA', v_nau, 1);
    perform public.captain_traits_set_for(v_p, 'TARTAGLIA', array['GUNNER']);
    v_out := v_out || jsonb_build_object('gunner', jsonb_build_object(
      'seat', v_r, 'seated', pg_temp.seated_0168('TARTAGLIA', v_nau), 'acc_pct', public.crew_pct(v_pf, v_nau, 'accuracy'), 'reach_pct', public.crew_pct(v_pf, v_nau, 'reach'),
      'ship', world.ship_stats(v_nau), 'ship_old', pg_temp.world_ship_stats_b0168(v_nau)));

    -- (A) ARMOUR at 0.5: the nau (armour 30) keeps 85 % of a loss, the barca (armour 5) 97.5 %
    update public.world_config set value = 'false'::jsonb where key in ('combat_bite', 'crew_bite');
    update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';
    v_out := v_out || jsonb_build_object('armour', jsonb_build_object(
      'nau_armour', world.ship_stat(v_nau, 'armour'), 'barca_armour', world.ship_stat(v_barca, 'armour'),
      'nau', public.armour_turns(v_nau, 100), 'barca', public.armour_turns(v_barca, 100),
      'raid_nau', greatest(0, 1000 - public.armour_turns(v_nau, 1000 - 1000 * 0.80))));
    raise exception 'PROBE_ROLLBACK_0168';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0168' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0168 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0168 select pg_temp.probe_0168();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0168 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  v_d     record;
  v_h     record;
  v_pp    record;
  v_rd    record;
  v_bad   bigint;
  v_n     bigint;
  v_m     bigint;
  v_def   text;
  v_pr    jsonb := (select j from probe_0168);
  v_x     jsonb;
  v_pct   numeric;
  v_notes text := '';
begin
  select * into v_b from before_0168;
  if v_pr is null then
    raise exception '0168 self-assert FAIL: the probe returned nothing';
  end if;

  -- (a) DARK, EVERY HULL: ship_stats and the whole ship_view = the old bodies'; the storm and the raid lose what they lost
  select count(*), count(*) filter (where new_stats is distinct from old_stats or new_view is distinct from old_view
                                       or new_storm is distinct from storm_loss::text or new_raid is distinct from old_raid)
    into v_n, v_bad from hulls_0168;
  if v_n = 0 or v_bad <> 0 then
    raise exception '0168 self-assert FAIL: % of % hull(s) read a different ship_stats, ship_view, storm loss or raid loss', v_bad, v_n;
  end if;
  -- (b) DARK, EVERY FLEET: the escort is DESIGN B.6's, to the digit
  select count(*), count(*) filter (where new_escort is distinct from old_escort) into v_m, v_bad from fleets_0168;
  if v_m = 0 or v_bad <> 0 then
    raise exception '0168 self-assert FAIL: % of % fleet(s) read a different escort score', v_bad, v_m;
  end if;
  -- (c) DARK, EVERY FLEET × CREW EFFECT: the same answer, or the same refusal
  select count(*) filter (where new_out is distinct from old_out) into v_bad from crew_0168;
  if v_bad <> 0 then
    raise exception '0168 self-assert FAIL: % crew_pct outcome(s) moved, e.g. %', v_bad,
      (select format('%s/%s/%s: %s → %s', fleet_id, ship_id, effect, old_out, new_out) from crew_0168 where new_out is distinct from old_out limit 1);
  end if;
  if exists (select 1 from crew_0168 where ship_id is not null and new_out not like 'REFUSED P0001: E_NOT_YET%') then
    raise exception '0168 self-assert FAIL: a ship effect was answered while combat_bite is off';
  end if;
  -- (d) DARK, EVERY CAPTAIN: the same card, or the same refusal
  select count(*) filter (where new_out is distinct from old_out) into v_bad from cards_0168;
  if v_bad <> 0 then
    raise exception '0168 self-assert FAIL: % captain card(s) moved', v_bad;
  end if;

  -- (e) THE DATA RULE the dark/lit equality of an unfitted hull rests on: guns = attack / 10 for every class
  select count(*) into v_bad from public.ship_classes where guns * 10 <> attack;
  if v_bad <> 0 then
    raise exception '0168 self-assert FAIL: % class(es) carry guns that are not attack / 10', v_bad;
  end if;

  -- (f) THE PROBE: escort
  v_x := v_pr->'bare';
  if (v_x->>'dark')::numeric <> (v_x->>'old')::numeric or round((v_x->>'lit')::numeric, 4) <> round((v_x->>'old')::numeric, 4) then
    raise exception '0168 self-assert FAIL: an unfitted fleet''s escort moved (old %, dark %, lit %)', v_x->>'old', v_x->>'dark', v_x->>'lit';
  end if;
  v_x := v_pr->'guns';
  if not coalesce((v_x->>'mounted')::boolean, false) then
    raise exception '0168 self-assert FAIL: the probe could not fit the broadside guns: %', v_x->'fit';
  end if;
  if (v_x->>'dark')::numeric <> (v_pr->'bare'->>'old')::numeric then
    raise exception '0168 self-assert FAIL: dark, the guns she carries moved the escort (% → %)', v_pr->'bare'->>'old', v_x->>'dark';
  end if;
  if (v_x->>'lit')::numeric <> (v_pr->'bare'->>'lit')::numeric + (v_x->>'gun_attack')::numeric / 10 then
    raise exception '0168 self-assert FAIL: lit, broadside guns gave escort % (expected % + % / 10)', v_x->>'lit', v_pr->'bare'->>'lit', v_x->>'gun_attack';
  end if;
  -- the Boarder: crew dark → nothing; crew lit → her ship's attack × (1 + share), the barca untouched, the escort up
  v_x := v_pr->'boarder';
  if not coalesce((v_x->>'seated')::boolean, false) then
    raise exception '0168 self-assert FAIL: the probe could not seat the Boarder: %', v_x->'seat';
  end if;
  if v_x->'crew_dark' is distinct from v_x->'crew_dark_old' then
    raise exception '0168 self-assert FAIL: with crew_bite off a Boarder''s job moved the nau''s stats (% vs %)', v_x->'crew_dark', v_x->'crew_dark_old';
  end if;
  v_pct := (v_x->'lit'->>'pct_nau')::numeric;
  if not (v_pct > 0) or (v_x->'lit'->>'pct_barca')::numeric <> 0 then
    raise exception '0168 self-assert FAIL: the Boarder''s share is % on her nau and % on the barca', v_pct, v_x->'lit'->>'pct_barca';
  end if;
  if (v_x->'lit'->'nau'->>'attack')::numeric
       <> round((v_x->'lit'->'nau_old'->>'attack')::numeric * (1 + v_pct), scale((v_x->'lit'->'nau_old'->>'attack')::numeric))
     or (v_x->'lit'->'nau') - 'attack' is distinct from (v_x->'lit'->'nau_old') - 'attack'
     or v_x->'lit'->'barca' is distinct from v_x->'lit'->'barca_old' then
    raise exception '0168 self-assert FAIL: lit, the Boarder gave % (old %, share %) — or moved another stat or ship', v_x->'lit'->'nau', v_x->'lit'->'nau_old', v_pct;
  end if;
  if not ((v_x->'lit'->>'escort')::numeric > (v_pr->'guns'->>'lit')::numeric) then
    raise exception '0168 self-assert FAIL: the Boarder did not raise the escort (% → %)', v_pr->'guns'->>'lit', v_x->'lit'->>'escort';
  end if;
  if jsonb_typeof(v_x->'lit'->'card_note') is distinct from 'null' then
    raise exception '0168 self-assert FAIL: lit, the Boarder''s card still says %', v_x->'lit'->'card_note';
  end if;
  if v_x->'off'->'nau' is distinct from v_x->'off'->'nau_old' or v_x->'off'->>'refusal' not like 'REFUSED P0001: E_NOT_YET%'
     or v_x->'off'->>'card_note' is distinct from 'Works when combat arrives.' then
    raise exception '0168 self-assert FAIL: combat off again, the nau read % (old %), crew_pct %, the card %',
      v_x->'off'->'nau', v_x->'off'->'nau_old', v_x->'off'->>'refusal', v_x->'off'->>'card_note';
  end if;
  -- the Gunner: accuracy and reach up on her ship, attack not
  v_x := v_pr->'gunner';
  if not coalesce((v_x->>'seated')::boolean, false) then
    raise exception '0168 self-assert FAIL: the probe could not seat the Gunner on the nau: %', v_x->'seat';
  end if;
  if not ((v_x->>'acc_pct')::numeric > 0 and (v_x->>'reach_pct')::numeric > 0)
     or not ((v_x->'ship'->>'accuracy')::numeric > (v_x->'ship_old'->>'accuracy')::numeric)
     or not ((v_x->'ship'->>'reach')::numeric > (v_x->'ship_old'->>'reach')::numeric)
     or (v_x->'ship'->>'attack') is distinct from (v_x->'ship_old'->>'attack')
     or (v_x->'ship'->>'accuracy')::numeric
          <> round((v_x->'ship_old'->>'accuracy')::numeric * (1 + (v_x->>'acc_pct')::numeric), scale((v_x->'ship_old'->>'accuracy')::numeric))
     or (v_x->'ship'->>'reach')::numeric
          <> round((v_x->'ship_old'->>'reach')::numeric * (1 + (v_x->>'reach_pct')::numeric), scale((v_x->'ship_old'->>'reach')::numeric)) then
    raise exception '0168 self-assert FAIL: the Gunner gave % (old %, accuracy share %, reach share %)',
      v_x->'ship', v_x->'ship_old', v_x->>'acc_pct', v_x->>'reach_pct';
  end if;
  -- armour at 0.5
  v_x := v_pr->'armour';
  if (v_x->>'nau')::numeric <> round(100 * (1 - (v_x->>'nau_armour')::numeric / 100.0 * 0.5), 2)
     or (v_x->>'barca')::numeric <> round(100 * (1 - (v_x->>'barca_armour')::numeric / 100.0 * 0.5), 2)
     or not ((v_x->>'nau')::numeric < (v_x->>'barca')::numeric) then
    raise exception '0168 self-assert FAIL: at 0.5 armour turned the nau''s loss of 100 to % (armour %) and the barca''s to % (armour %)',
      v_x->>'nau', v_x->>'nau_armour', v_x->>'barca', v_x->>'barca_armour';
  end if;

  -- (g) THE READERS: settle reads no `guns`; the escort is read by settle alone; the armour rule by settle alone;
  --     the captains' share by ship_stats alone (a planted reader is seen)
  if strpos(replace(pg_get_functiondef('voyage.settle(uuid, timestamp with time zone)'::regprocedure), E'\r', ''), 'guns') <> 0 then
    raise exception '0168 self-assert FAIL: voyage.settle still reads guns';
  end if;
  create or replace function pg_temp.readers_0168(p_name text)
  returns text
  language sql
  as $f$
    select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema', 'pg_temp') and n.nspname not like 'pg\_%'
       and p.prosrc like '%' || p_name || '(%'
       and n.nspname || '.' || p.proname <> p_name
  $f$;
  if pg_temp.readers_0168('voyage.escort_score') is distinct from 'voyage.settle'
     or pg_temp.readers_0168('public.armour_turns') is distinct from 'voyage.settle'
     or pg_temp.readers_0168('public.ship_crew_terms') is distinct from 'world.ship_stats' then
    raise exception '0168 self-assert FAIL: readers — escort %, armour %, crew terms %', pg_temp.readers_0168('voyage.escort_score'),
      pg_temp.readers_0168('public.armour_turns'), pg_temp.readers_0168('public.ship_crew_terms');
  end if;
  begin
    execute $planted$create function public.zz_planted_reader_0168() returns numeric language sql as
      'select voyage.escort_score(null)'$planted$;
    if pg_temp.readers_0168('voyage.escort_score') is not distinct from 'voyage.settle' then
      raise exception '0168 self-assert FAIL: the reader scan did not see a planted reader — it proves nothing';
    end if;
    raise exception 'CONTROL_ROLLBACK_0168';
  exception when others then
    if sqlerrm <> 'CONTROL_ROLLBACK_0168' then raise; end if;
  end;

  -- (h) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved; the rest untouched
  for v_d in select * from defs_before_0168 order by fn loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0168 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0168(v_def, v_h.new) <> 1 then
        raise exception '0168 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0168 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0168 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from untouched_before_0168 loop
    if replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '') <> v_d.def then
      raise exception '0168 self-assert FAIL: % moved — it was to be left untouched', v_d.fn;
    end if;
  end loop;

  -- (i) THE KNOBS (only this file's two) and THE WALL: no entry point; nothing new reachable by a client
  if (select count(*) from public.world_config where key in ('combat_bite', 'armour_turns_pct')) <> 2 then
    raise exception '0168 self-assert FAIL: the knobs combat_bite / armour_turns_pct are not both present';
  end if;
  if v_b.own_knobs = 0 and ((select value from public.world_config where key = 'combat_bite') <> 'false'::jsonb
                            or (select value from public.world_config where key = 'armour_turns_pct') <> '0'::jsonb) then
    raise exception '0168 self-assert FAIL: the knobs did not land dark';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['public.combat_bite_on()', 'voyage.escort_score(uuid)', 'public.armour_turns(uuid, numeric)',
                                           'public.ship_crew_terms(uuid, jsonb)']) f(fn),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, f.fn, 'execute')) then
    raise exception '0168 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach a new function';
  end if;

  for v_rd in select bf.what, bf.ms as before_ms, af.ms as after_ms, bf.n
             from reads_0168 bf join reads_0168 af on af.what = bf.what and af.phase = 'after'
            where bf.phase = 'before' order by bf.what loop
    v_notes := v_notes || format('%s over %s merchant row(s) %s ms → %s ms; ', v_rd.what, v_rd.n, v_rd.before_ms, v_rd.after_ms);
  end loop;

  raise notice '0168 self-assert ok: A FIGHT IS READ FROM THE GUNS SHE CARRIES (dark: combat_bite false, armour_turns_pct 0). DARK: % hull(s) — ship_stats, ship_view, a storm''s and a raid''s loss = the old bodies''; % fleet(s) — the escort = DESIGN B.6''s; % crew_pct outcome(s) and % captain card(s) unmoved (ship effects refused alike); guns = attack / 10 for every class. LIT (rolled back): an unfitted probe fleet''s escort % = % to 4 places; broadside guns on her nau: dark %, lit % (+ attack % / 10); the Boarder in the nau''s Captain''s cabin: nothing with crew_bite off, then attack % → % (share %), the barca untouched, escort %, her card''s "works when combat arrives" gone and back when combat is off; the Gunner on the nau (the Boarder ashore): accuracy % → %, reach % → %; armour at 0.5: a loss of 100 → % on the nau (armour %), % on the barca (armour %). READERS: settle reads no guns; escort and armour by settle alone, the captains'' share by ship_stats alone (a planted reader seen). 4 bodies reverse, 9 untouched, no entry point. READS: %',
    v_n, v_m, (select count(*) from crew_0168), (select count(*) from cards_0168),
    v_pr->'bare'->>'lit', v_pr->'bare'->>'old', v_pr->'guns'->>'dark', v_pr->'guns'->>'lit', v_pr->'guns'->>'gun_attack',
    v_pr->'boarder'->'lit'->'nau_old'->>'attack', v_pr->'boarder'->'lit'->'nau'->>'attack', v_pr->'boarder'->'lit'->>'pct_nau',
    v_pr->'boarder'->'lit'->>'escort',
    v_pr->'gunner'->'ship_old'->>'accuracy', v_pr->'gunner'->'ship'->>'accuracy', v_pr->'gunner'->'ship_old'->>'reach', v_pr->'gunner'->'ship'->>'reach',
    v_pr->'armour'->>'nau', v_pr->'armour'->>'nau_armour', v_pr->'armour'->>'barca', v_pr->'armour'->>'barca_armour', v_notes;
end $$;
