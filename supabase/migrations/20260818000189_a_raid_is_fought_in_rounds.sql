-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0189 — A RAID IS FOUGHT IN ROUNDS  (the owner's automatic fight — DARK: combat_bite false,
--        armour_turns_pct 0)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18 ~13:40 UTC: "yes lets do a automatic fight, so that range and accuracy is an
-- important factor. … yes shoals and damage too." Text and tabs; no visual combat, ever; the map only
-- shows. Today a raid is DESIGN B.6's one ratio — escort against raider, five bands — and 0168 (S4)
-- made the escort read what she carries, but accuracy, reach and sighting still feed no roll
-- (docs/dev-log/2026-10-18-s4-k10-combat-stats.md, "Not in this slice"). This file is that combat slice:
-- the raid becomes a FIGHT resolved on the server in rounds and reported as words.
-- docs/dev-log/2026-10-18-auto-fight.md has the design, the measured balance and the open questions.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) KNOBS (only where absent; every one NOT the owner's — confirm, dev-log §"Not the owner's"):
--       fight_raider_class    'xebec'   the raiders' hull: their accuracy, reach, armour, sighting, attack,
--                                       hull and crew are that class's own figures (data, not new powers)
--       fight_ranges          3 × LONG 0.6, 2 × MEDIUM 0.8, CLOSE 1.0 — the rounds, in
--                                       order, each a range and the share of a gun's accuracy that hits there
--       fight_damage_per_attack, fight_raider_break, fight_evade_per_sighting, fight_evade_max,
--       fight_board_bands     (the old table's 1.2 / 0.7 / 0.3, now read at the boarding)
-- (2) THE READINGS:
--       public.armour_soak(armour, loss)   THE armour formula, loss × (1 − armour / 100 × armour_turns_pct),
--                                          ≥ 0, to the hundredth; the knob at 0 gives the loss itself.
--                                          public.armour_turns (0168) now composes it for a hull; the
--                                          fight composes it for the raiders, who are no hull.
--       voyage.fight_resolve(voyage, day, raider, ships)  THE FIGHT, a pure function of its arguments,
--                                          the knobs and the world secret: sighting (who fires first, or an
--                                          escape), then the rounds (range decides who can fire, accuracy the
--                                          hit, attack the damage, armour the soak), then — if the raiders
--                                          have not broken off — the boarding (crew, and a Boarder's share).
--                                          Deterministic per (voyage, day): voyage.rng streams, like the
--                                          hazard roll, so a re-settle writes the same fight.
--       voyage.fight(voyage, day, fleet, raider)  gathers the fleet (world.ship_stats, her hull and crew,
--                                          the captains' shares, the gear that works on a PIRATES day) and
--                                          calls the core. Refused while combat_bite is off.
-- (3) THE HUNKS (sliced from the LIVE bodies):
--       voyage.settle   PIRATES: while combat_bite is on, voyage.fight decides the outcome and writes each
--                       hull's loss; the crew loss and the cargo keep DESIGN B.6's table by outcome; the day's
--                       sentence is the fight's own (the table's "We fired twice …" would contradict the rounds);
--                       the payload carries the rounds. SHOAL_WATER: the loss goes through
--                       public.armour_turns (the owner: "shoals and damage too"). The VOYAGE_REPORT carries
--                       `fights` — for each fought day, the index of its line and its rounds — only when
--                       there was one, so a dark report is the old report to the byte.
--       public.armour_turns   its formula is public.armour_soak's (the same expression).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No row moves, no ALTER, no cron, no entry point, no client write. DARK (combat_bite off and the knob at
-- 0, as production stands), every settled day is the old one: a probe passage of nothing but raids, one of
-- nothing but shoals and one as the sea deals it are settled by the old body and by the new and compared —
-- events, hulls, crew, cargo, report, experience, purse. NOT HERE (dev-log): a ship taken (DESIGN B.6:
-- "the flagship is never captured"; taking any hull is the owner's call); gear actives and consumables
-- (shot and powder are named, not spent — gear_actives_bite has no row); a raider class by sea.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Pre-images first. Then ROW EXCLUSIVE on world_config (the inserts). CREATE OR REPLACE FUNCTION locks no
-- table. The probe's writes are rolled back; a probe that meets a lock is retried 5 × 0.2 s, then LOCK
-- CONTENTION. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE. Timings by RAISE NOTICE only.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once and
-- to reverse to its pre-image, ACL / volatility / definer / config unchanged: voyage.settle (0168),
-- public.armour_turns (0168).
--
-- ROLLBACK: combat_bite false and armour_turns_pct 0 (as landed) is every answer of today. Full (forward
-- migration): reverse the two bodies' hunks (old text in hunks_0189); drop voyage.fight, voyage.fight_resolve,
-- public.armour_soak; delete the nine fight_* knobs.
-- VERSION: 0189 (provisional; renumbered to head + 1 at deploy). Applies on 0188 (deploy order set by the coordinator: 0187 great powers, 0188 plan-reach-2, 0189 this, 0190 its switch).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0189(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0189 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.settle(uuid, timestamp with time zone)'), ('public.armour_turns(uuid, numeric)')) f(fn);

create temp table untouched_before_0189 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
  from (values ('voyage.escort_score(uuid)'), ('voyage.storm_hull_lost(uuid, numeric, numeric)'),
               ('public.raid_crew_lost(uuid, numeric, numeric)'), ('voyage.report_line(integer, text, jsonb)'),
               ('voyage.hazard_roll(uuid, integer)'), ('world.ship_stats(uuid)'),
               ('public.crew_pct(uuid, uuid, text, uuid, timestamp with time zone)'),
               ('public.crew_terms(uuid, timestamp with time zone)'), ('public.fight_points(text)'),
               ('public.wear_units_for(uuid, uuid)'), ('public.voyage_xp_tracks(uuid)')) f(fn);

create temp table before_0189 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config where key like 'fight\_%') as own_knobs;

-- the old settle under a pg_temp name, so the probe can settle one passage by both bodies
do $$
declare
  v_def text := (select def from defs_before_0189 where fn = 'voyage.settle(uuid, timestamp with time zone)');
  v_new text := 'CREATE OR REPLACE FUNCTION pg_temp.voyage_settle_b0189(';
begin
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION voyage.settle(', v_new);
  if pg_temp.occurs_0189(v_def, v_new) <> 1 then
    raise exception '0189 self-assert FAIL: could not rename the pre-image of voyage.settle';
  end if;
  execute v_def;
end $$;

-- ── 2. THE KNOBS (only where absent: a knob already set is left alone) ──────────────────────────
insert into public.world_config (key, value, description) values
  ('fight_raider_class', '"xebec"'::jsonb,
   '0189 (the automatic fight): the class whose own figures the raiders fight with — accuracy, reach, armour, '
   'sighting, attack per hull, hull and crew (crew_required). The hazard''s strength (piracy × 40 × (0.5 + '
   'magnitude), DESIGN B.6) says how many of them: strength / that class''s escort score. NOT the owner''s — confirm.'),
  ('fight_ranges', '[["LONG",0.6],["LONG",0.6],["LONG",0.6],["MEDIUM",0.8],["MEDIUM",0.8],["CLOSE",1.0]]'::jsonb,
   '0189: the rounds of a fight, in order — a range (LONG: only guns whose reach is at least the other side''s '
   'fire) and the share of a gun''s accuracy that hits at it. After the last, the boarding. NOT the owner''s — confirm.'),
  ('fight_damage_per_attack', '0.7'::jsonb,
   '0189: hull points one hit takes per point of the firing hull''s attack (× 0.75–1.25 by the roll), before '
   'armour (public.armour_soak). NOT the owner''s — confirm.'),
  ('fight_raider_break', '0.15'::jsonb,
   '0189: the raiders break off once they have taken this share of their hull. NOT the owner''s — confirm.'),
  ('fight_evade_per_sighting', '0.03'::jsonb,
   '0189: when the fleet''s best sighting beats the raiders'', the chance per point of the lead that it slips away '
   'before a shot (capped by fight_evade_max). NOT the owner''s — confirm.'),
  ('fight_evade_max', '0.30'::jsonb,
   '0189: the cap on that chance. NOT the owner''s — confirm.'),
  ('fight_standoff_ratio', '2.0'::jsonb,
   '0189: raiders do not close on a fleet whose escort score (voyage.escort_score) is this many times their strength '
   'or more — DESIGN B.6''s own EVADED band. NOT the owner''s — confirm.'),
  ('fight_hand_value', '0.15'::jsonb,
   '0189: what one hand weighs at a boarding, beside tier × 3 (DESIGN B.6''s escort weighs a hand 0.02, beside guns). '
   'NOT the owner''s — confirm.'),
  ('fight_board_bands', '[1.2, 0.7, 0.3]'::jsonb,
   '0189: at the boarding, your hulls'' (crew × fight_hand_value × (1 + a Boarder''s share) + tier × 3) × hull left '
   'against theirs: at least the first → driven off, the second → ransom, the third → plundered, below → stripped (DESIGN B.6''s '
   'own bands). NOT the owner''s — confirm.')
on conflict (key) do nothing;

-- ── 3. THE READINGS ────────────────────────────────────────────────────────────────────────────
create or replace function public.armour_soak(p_armour numeric, p_loss numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0189: THE ARMOUR FORMULA (docs/SHIPS_AND_GEAR.md §5, as 0168 wrote it in public.armour_turns): what is left
-- of a hull loss once this much armour has turned its share — loss × (1 − armour / 100 × armour_turns_pct),
-- never below 0, to the hundredth. The knob at 0 is OFF: the loss itself comes back, the same numeric.
-- Read by public.armour_turns (a hull, its armour from world.ship_stat) and voyage.fight_resolve (the
-- raiders, who are no hull; and a hull's shot, its armour from the fight's own reading).
declare
  v_k numeric := public.wc_num('armour_turns_pct');
begin
  if v_k <= 0 then
    return p_loss;
  end if;
  return round(p_loss * greatest(0, 1 - coalesce(p_armour, 0) / 100.0 * v_k), 2);
end $$;
comment on function public.armour_soak(numeric, numeric) is
  '0189: THE armour formula — loss × (1 − armour / 100 × armour_turns_pct), ≥ 0; the knob at 0 returns the loss '
  'itself. Read by public.armour_turns and voyage.fight_resolve. Server-only.';
revoke all on function public.armour_soak(numeric, numeric) from public, anon, authenticated;

create or replace function voyage.fight_resolve(p_voyage uuid, p_day int, p_raider numeric, p_escort numeric, p_ships jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0189: THE FIGHT — the one combat authority. A raid on (voyage, day) by raiders of strength p_raider
-- (DESIGN B.6's piracy × 40 × (0.5 + magnitude)) against a fleet whose escort score is p_escort
-- (voyage.escort_score) and whose hulls are p_ships, an array of
--   {id, name, tier, hull, maxd, crew, attack, accuracy, reach, armour, sighting, boarder_pct, boarder, gunner, gear[]}
-- (voyage.fight builds it from the live fleet; a simulation may pass its own). A pure function of its
-- arguments, the fight_* knobs, armour_turns_pct and the world secret: every chance is a voyage.rng stream
-- of (voyage, day), so the same day fought twice is the same fight, word for word.
--   SIZING UP raiders do not close on a fleet fight_standoff_ratio times their strength or more (DESIGN B.6's
--             EVADED band, escort / raider): EVADED, no shot fired.
--   SIGHTING  the better lookout (her best sighting against the raiders' class) fires the first round alone;
--             a lead may let her slip away before a shot (fight_evade_per_sighting × lead, ≤ fight_evade_max).
--   ROUNDS    fight_ranges, in order. At LONG range only guns whose reach is at least the other side's fire —
--             range decides WHO can fire. A gun hits on accuracy / 100 × the range's share (5–95 %); a hit
--             takes attack × fight_damage_per_attack × (0.75–1.25) of hull, less armour (public.armour_soak).
--             The raiders' shots fall on the hulls by their size. They break off at fight_raider_break of
--             their hull lost: EVADED if they never touched her, DRIVEN_OFF if they did.
--   BOARDING  if they have not broken off: each side's hulls, (crew × fight_hand_value × (1 + the Boarder's
--             share) + tier × 3) × the share of its hull left — DESIGN B.6's crew and size terms, a hand
--             weighed for a fight hand to hand — read against fight_board_bands: DRIVEN_OFF, RANSOM,
--             PLUNDERED, STRIPPED.
-- Returns {outcome, sentence (the day's one line, in DESIGN B.6's voice, true of THIS fight), rounds[] (the battle
-- report, in words), hull_lost {ship id: points}, raiders{…}, first, hits{yours, theirs}}. What an outcome costs in crew and cargo stays DESIGN B.6's, in voyage.settle.
declare
  c        public.ship_classes%rowtype;
  v_ranges jsonb := public.wc('fight_ranges');
  v_k      numeric := public.wc_num('fight_damage_per_attack');
  v_break  numeric := public.wc_num('fight_raider_break');
  v_bands  jsonb := public.wc('fight_board_bands');
  v_n      int := coalesce(jsonb_array_length(p_ships), 0);
  x        jsonb;
  i        int;
  j        int;
  g        int;
  t        int;
  a_id     uuid[] := '{}';
  a_name   text[] := '{}';
  a_att    numeric[] := '{}';
  a_acc    numeric[] := '{}';
  a_reach  numeric[] := '{}';
  a_arm    numeric[] := '{}';
  a_hull0  numeric[] := '{}';
  a_hull   numeric[] := '{}';
  a_maxd   numeric[] := '{}';
  a_crew   numeric[] := '{}';
  a_bpct   numeric[] := '{}';
  a_tier   numeric[] := '{}';
  v_hand   numeric := public.wc_num('fight_hand_value');
  a_taken  numeric[];
  v_one    numeric;
  r_n      numeric;
  r_hull0  numeric;
  r_hull   numeric;
  r_att    numeric;
  r_crew   numeric;
  r_shots  int;
  p_sight  numeric := 0;
  p_reach  numeric := 0;
  v_first  text;
  v_lines  text[] := '{}';
  v_outcome text;
  v_sentence text;
  v_range  text;
  v_mult   numeric;
  v_can    int;
  v_fired  int;
  v_hits   int;
  v_dealt  numeric;
  r_can    boolean;
  r_fired  int;
  r_hits   int;
  v_raw    numeric;
  v_soaked numeric;
  v_d      numeric;
  v_pick   numeric;
  v_acc_sum numeric;
  v_you    text;
  v_they   text;
  v_hit_on text;
  v_tot_you  int := 0;
  v_tot_they int := 0;
  v_fought int := 0;
  v_txt    text;
  b_you    numeric := 0;
  b_crew   numeric := 0;
  b_they   numeric;
  v_ratio  numeric;
begin
  if v_n = 0 then
    raise exception 'E_NO_SHIPS: a fight needs at least one hull' using errcode = 'P0001';
  end if;
  select * into c from public.ship_classes where code = public.wc_text('fight_raider_class');
  if c.id is null then
    -- NO_SPAGHETTI §7C: raiders with no class have no figures; that is a broken knob, not a calm sea
    raise exception 'E_NO_RAIDER_CLASS: fight_raider_class names no ship class' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_ranges) <> 'array' or jsonb_array_length(v_ranges) = 0 or jsonb_typeof(v_bands) <> 'array'
     or jsonb_array_length(v_bands) <> 3 then
    raise exception 'E_FIGHT_KNOBS: fight_ranges must list at least one round and fight_board_bands three bands'
      using errcode = 'P0001';
  end if;

  -- the fleet, one array per figure (index = her place in p_ships)
  for i in 1 .. v_n loop
    x := p_ships -> (i - 1);
    a_id[i]    := (x->>'id')::uuid;
    a_name[i]  := coalesce(x->>'name', 'Your ship');
    a_att[i]   := greatest(0, coalesce((x->>'attack')::numeric, 0));
    a_acc[i]   := greatest(0, coalesce((x->>'accuracy')::numeric, 0));
    a_reach[i] := greatest(0, coalesce((x->>'reach')::numeric, 0));
    a_arm[i]   := greatest(0, coalesce((x->>'armour')::numeric, 0));
    a_hull0[i] := greatest(0, coalesce((x->>'hull')::numeric, 0));
    a_hull[i]  := a_hull0[i];
    a_maxd[i]  := greatest(1, coalesce((x->>'maxd')::numeric, 1));
    a_crew[i]  := greatest(0, coalesce((x->>'crew')::numeric, 0));
    a_bpct[i]  := greatest(0, coalesce((x->>'boarder_pct')::numeric, 0));
    a_tier[i]  := greatest(0, coalesce((x->>'tier')::numeric, 0));
    p_sight    := greatest(p_sight, coalesce((x->>'sighting')::numeric, 0));
    if a_att[i] > 0 and a_acc[i] > 0 then
      p_reach := greatest(p_reach, a_reach[i]);
    end if;
  end loop;

  -- the raiders: the hazard's strength in hulls of the raiders' class (DESIGN B.6's escort score of one)
  v_one   := c.attack / 10.0 + c.crew_required * 0.02 + c.tier * 3;
  r_n     := greatest(0, coalesce(p_raider, 0)) / v_one;
  r_hull0 := r_n * c.durability;
  r_hull  := r_hull0;
  r_att   := r_n * c.attack;
  r_crew  := r_n * c.crew_required;
  r_shots := greatest(1, ceil(r_n))::int;

  -- SIZING UP: no raiders, or a fleet too strong for them — they never close
  if r_n <= 0 or coalesce(p_escort, 0) >= public.wc_num('fight_standoff_ratio') * p_raider then
    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'They stood off and did not close.',
                              'rounds', to_jsonb(array[case when r_n <= 0 then 'The sail stood off and never closed.'
                                                            else format('Raiders: about %s × %s, %s crew. They looked you over and stood off.',
                                                                        greatest(1, round(r_n)), c.name, round(r_crew)) end]),
                              'hull_lost', '{}'::jsonb, 'first', 'BOTH', 'rounds_fought', 0,
                              'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0),
                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  end if;

  v_lines := v_lines || case when r_n < 0.75
                               then format('Raiders: one small %s, %s crew.', c.name, round(r_crew))
                               else format('Raiders: about %s × %s, %s crew.', round(r_n), c.name, round(r_crew)) end;
  -- what works on a raid day: the gear whose trigger is PIRATES (item_use, 0158), and a Gunner at the guns
  select string_agg(format('%s (%s)', e->>'name', (select string_agg(gname, ', ' order by gname)
                                                      from jsonb_array_elements_text(e->'gear') gname)), '; ' order by o)
    into v_txt
    from jsonb_array_elements(p_ships) with ordinality q(e, o)
   where jsonb_typeof(e->'gear') = 'array' and jsonb_array_length(e->'gear') > 0;
  if v_txt is not null then
    v_lines := v_lines || ('Ready for them: ' || v_txt || '.');
  end if;
  select string_agg(format('%s lays the guns on %s.', e->>'gunner', e->>'name'), ' ' order by o)
    into v_txt
    from jsonb_array_elements(p_ships) with ordinality q(e, o)
   where coalesce(e->>'gunner', '') <> '';
  if v_txt is not null then
    v_lines := v_lines || v_txt;
  end if;

  -- SIGHTING
  v_first := case when p_sight > c.sighting then 'YOU' when p_sight < c.sighting then 'THEY' else 'BOTH' end;
  if v_first = 'YOU' then
    if voyage.rng(p_voyage, p_day, 'fight:evade')
         < least(public.wc_num('fight_evade_max'), (p_sight - c.sighting) * public.wc_num('fight_evade_per_sighting')) then
      v_lines := v_lines || 'Your lookout saw them first, and you slipped away before they could close.'::text;
      return jsonb_build_object('outcome', 'EVADED', 'sentence', 'We saw them first and slipped away.',
                                'rounds', to_jsonb(v_lines), 'hull_lost', '{}'::jsonb,
                                'first', v_first, 'rounds_fought', 0,
                                'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0),
                                'hits', jsonb_build_object('yours', 0, 'theirs', 0));
    end if;
    v_lines := v_lines || 'Your lookout saw them first.'::text;
  elsif v_first = 'THEY' then
    v_lines := v_lines || 'They saw you before your lookout saw them.'::text;
  else
    v_lines := v_lines || 'Both sides saw each other at the same moment.'::text;
  end if;

  -- THE ROUNDS
  for g in 1 .. jsonb_array_length(v_ranges) loop
    v_fought := g;
    v_range := v_ranges -> (g - 1) ->> 0;
    v_mult  := (v_ranges -> (g - 1) ->> 1)::numeric;
    -- your guns
    v_can := 0; v_fired := 0; v_hits := 0; v_dealt := 0;
    for i in 1 .. v_n loop
      continue when a_att[i] <= 0 or a_acc[i] <= 0 or a_hull[i] <= 0;
      v_can := v_can + 1;
      continue when g = 1 and v_first = 'THEY';
      continue when v_range = 'LONG' and a_reach[i] < c.reach;
      v_fired := v_fired + 1;
      if voyage.rng(p_voyage, p_day, format('fight:%s:you:%s', g, i))
           < least(0.95, greatest(0.05, a_acc[i] / 100.0 * v_mult)) then
        v_hits := v_hits + 1;
        v_dealt := v_dealt + public.armour_soak(c.armour,
                     a_att[i] * v_k * (0.75 + 0.5 * voyage.rng(p_voyage, p_day, format('fight:%s:you:%s:dmg', g, i))));
      end if;
    end loop;
    -- their guns
    a_taken := array_fill(0::numeric, array[v_n]);
    r_fired := 0; r_hits := 0; v_raw := 0; v_soaked := 0;
    r_can := r_hull > 0 and not (g = 1 and v_first = 'YOU') and (v_range <> 'LONG' or c.reach >= p_reach);
    if r_can then
      for j in 1 .. r_shots loop
        r_fired := r_fired + 1;
        continue when voyage.rng(p_voyage, p_day, format('fight:%s:they:%s', g, j))
                        >= least(0.95, greatest(0.05, c.accuracy / 100.0 * v_mult));
        -- whom it hits: the hulls still afloat, by their size
        v_pick := voyage.rng(p_voyage, p_day, format('fight:%s:they:%s:at', g, j))
                  * (select coalesce(sum(a_maxd[k]), 0) from generate_subscripts(a_hull, 1) k where a_hull[k] > 0);
        t := null;
        v_acc_sum := 0;
        for i in 1 .. v_n loop
          continue when a_hull[i] <= 0;
          v_acc_sum := v_acc_sum + a_maxd[i];
          t := i;
          exit when v_pick < v_acc_sum;
        end loop;
        exit when t is null;
        r_hits := r_hits + 1;
        v_d := r_att / r_shots * v_k * (0.75 + 0.5 * voyage.rng(p_voyage, p_day, format('fight:%s:they:%s:dmg', g, j)));
        v_raw := v_raw + v_d;
        v_d := public.armour_soak(a_arm[t], v_d);
        v_soaked := v_soaked + v_d;
        a_taken[t] := a_taken[t] + v_d;
      end loop;
    end if;
    -- both broadsides land together
    r_hull := greatest(0, r_hull - v_dealt);
    v_hit_on := null;
    for i in 1 .. v_n loop
      continue when a_taken[i] <= 0;
      v_hit_on := coalesce(v_hit_on || ', ', '')
                  || format('%s for %s%% damage', a_name[i], greatest(1, round(least(a_taken[i], a_hull[i]) / a_maxd[i] * 100)));
      a_hull[i] := greatest(0, a_hull[i] - a_taken[i]);
    end loop;
    v_tot_you := v_tot_you + v_hits;
    v_tot_they := v_tot_they + r_hits;

    v_you := case when g = 1 and v_first = 'THEY' then 'you are caught unready'
                  when v_can = 0 then 'you have no guns to answer with'
                  when v_fired = 0 then 'your guns cannot reach them'
                  when v_hits = 0 then format('you miss with %s shot%s', v_fired, case when v_fired = 1 then '' else 's' end)
                  else format('you hit with %s of %s shot%s', v_hits, v_fired, case when v_fired = 1 then '' else 's' end) end;
    v_they := case when g = 1 and v_first = 'YOU' then 'they are caught unready'
                   when not r_can then 'their guns cannot reach you'
                   when r_hits = 0 then 'they miss'
                   else format('they hit %s', v_hit_on)
                        || case when v_raw > v_soaked + 0.005
                                then format(' (armour turned %s%%)', round((1 - v_soaked / v_raw) * 100)) else '' end end;
    v_lines := v_lines || (format('Round %s · %s range — %s; %s.', g, lower(v_range), v_you, v_they)
                           || case when v_hits > 0 then format(' The raiders are %s%% damaged.', round((1 - r_hull / r_hull0) * 100)) else '' end);

    if r_hull0 - r_hull >= v_break * r_hull0 then
      v_outcome := case when (select coalesce(sum(a_hull0[k] - a_hull[k]), 0) from generate_subscripts(a_hull, 1) k) = 0
                        then 'EVADED' else 'DRIVEN_OFF' end;
      v_lines := v_lines || 'They break off and run.'::text;
      v_sentence := 'They broke off and ran.';
      exit;
    end if;
  end loop;

  -- THE BOARDING
  if v_outcome is null then
    for i in 1 .. v_n loop
      b_crew := b_crew + a_crew[i];
      b_you := b_you + (a_crew[i] * v_hand * (1 + a_bpct[i]) + a_tier[i] * 3)
                       * case when a_hull0[i] > 0 then a_hull[i] / a_hull0[i] else 0 end;
    end loop;
    b_they := r_n * (c.crew_required * v_hand + c.tier * 3) * r_hull / r_hull0;
    v_ratio := case when b_they <= 0 then 99 else b_you / b_they end;
    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'
                      when v_ratio >= (v_bands->>1)::numeric then 'RANSOM'
                      when v_ratio >= (v_bands->>2)::numeric then 'PLUNDERED'
                      else 'STRIPPED' end;
    select string_agg(format('%s leads the crew on %s (+%s%%).', e->>'boarder', e->>'name',
                             round((e->>'boarder_pct')::numeric * 100)), ' ' order by o)
      into v_txt
      from jsonb_array_elements(p_ships) with ordinality q(e, o)
     where coalesce(e->>'boarder', '') <> '' and coalesce((e->>'boarder_pct')::numeric, 0) > 0;
    v_lines := v_lines || (format('Close quarters: they come alongside — your %s crew against their %s.', round(b_crew),
                                  round(r_crew * r_hull / r_hull0))
                           || coalesce(' ' || v_txt, '')
                           || case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                             when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                             when 'PLUNDERED'  then ' They board and take what they can carry.'
                                             else ' They board and take everything but the ships.' end);
    v_sentence := case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                 when 'RANSOM'     then 'They came alongside and we paid them off.'
                                 when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
                                 else 'They took everything but the ships themselves.' end;
  end if;

  return jsonb_build_object(
    'outcome', v_outcome,
    'sentence', v_sentence,
    'rounds', to_jsonb(v_lines),
    'hull_lost', coalesce((select jsonb_object_agg(a_id[k]::text, round(a_hull0[k] - a_hull[k], 2))
                             from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k]), '{}'::jsonb),
    'first', v_first,
    'rounds_fought', v_fought,
    'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew),
                                  'damaged_pct', round((1 - r_hull / r_hull0) * 100)),
    'hits', jsonb_build_object('yours', v_tot_you, 'theirs', v_tot_they));
end $$;
comment on function voyage.fight_resolve(uuid, int, numeric, numeric, jsonb) is
  '0189: THE FIGHT — sighting, rounds of range / accuracy / attack / armour, boarding; deterministic per (voyage, '
  'day). Returns {outcome, rounds[], hull_lost, raiders, first, hits}. Read by voyage.fight. Server-only.';
revoke all on function voyage.fight_resolve(uuid, int, numeric, numeric, jsonb) from public, anon, authenticated;

create or replace function voyage.fight(p_voyage uuid, p_day int, p_fleet uuid, p_raider numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0189: A RAID ON THIS FLEET, FOUGHT — the fleet as it is (world.ship_stats, the one reading of a hull: her
-- class, gear, company skills and seated captains; her hull and crew), the share of a Boarder seated on each
-- hull (public.crew_pct 'attack', K10's ship effect), the Boarder and the Gunner by name, and the gear that
-- works on a PIRATES day (item_use, 0158) — handed to voyage.fight_resolve. Read by voyage.settle's PIRATES
-- arm while combat_bite is on. Refused while it is off: a fight read dark would be a second, unlit authority.
begin
  if not public.combat_bite_on() then
    raise exception 'E_NOT_YET: a raid is fought in rounds only while combat_bite is on' using errcode = 'P0001';
  end if;
  return voyage.fight_resolve(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), (
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'name', s.name, 'tier', c.tier, 'hull', s.durability, 'maxd', c.durability, 'crew', s.crew,
             'attack', (x.st->>'attack')::numeric, 'accuracy', (x.st->>'accuracy')::numeric,
             'reach', (x.st->>'reach')::numeric, 'armour', (x.st->>'armour')::numeric,
             'sighting', (x.st->>'sighting')::numeric,
             'boarder_pct', public.crew_pct(p_fleet, s.id, 'attack'),
             'boarder', (select o.name from public.crew_terms(p_fleet) t join public.officers o on o.id = t.officer_id
                          where t.ship_id = s.id and t.effect = 'attack' and t.value_pct > 0
                          order by t.value_pct desc, o.name limit 1),
             'gunner', (select o.name from public.crew_terms(p_fleet) t join public.officers o on o.id = t.officer_id
                         where t.ship_id = s.id and t.effect in ('accuracy', 'reach') and t.value_pct > 0
                         order by t.value_pct desc, o.name limit 1),
             'gear', (select coalesce(jsonb_agg(distinct ik.name), '[]'::jsonb)
                        from public.fitted_units fu
                        join public.item_use iu on iu.item_code = fu.item_code and iu.trigger = 'PIRATES'
                        join public.item_kinds ik on ik.code = fu.item_code
                       where fu.ship_id = s.id))
           order by s.is_flagship desc, s.created_at, s.id)
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      cross join lateral (select world.ship_stats(s.id) as st) x
     where s.fleet_id = p_fleet));
end $$;
comment on function voyage.fight(uuid, int, uuid, numeric) is
  '0189: a raid on this fleet fought (voyage.fight_resolve over her live hulls). Read by voyage.settle''s PIRATES '
  'arm while combat_bite is on; refused while it is off. Server-only.';
revoke all on function voyage.fight(uuid, int, uuid, numeric) from public, anon, authenticated;

-- ── 4. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0189 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0189 values
-- voyage.settle: a place for the fight's answer
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$  v_bonus     jsonb;     -- 0155 (K3): the sailing bonus's answer, for the report
$h$,
$h$  v_bonus     jsonb;     -- 0155 (K3): the sailing bonus's answer, for the report
  v_fight     jsonb;     -- 0189: the fight's answer (voyage.fight) while combat_bite is on, else null
$h$),
-- voyage.settle: THE FIGHT decides, while combat_bite is on
('voyage.settle(uuid, timestamp with time zone)', 2,
$h$      v_ratio := case when v_raider <= 0 then 99 else v_escort / v_raider end;
      if    v_ratio >= 2.0 then v_outcome := 'EVADED';
      elsif v_ratio >= 1.2 then v_outcome := 'DRIVEN_OFF';
      elsif v_ratio >= 0.7 then v_outcome := 'RANSOM';
      elsif v_ratio >= 0.3 then v_outcome := 'PLUNDERED';
      else                      v_outcome := 'STRIPPED';
      end if;
$h$,
$h$      -- 0189: THE FIGHT. While combat_bite is on, voyage.fight decides — sighting, rounds of range, accuracy,
      -- attack and armour, then the boarding — and says what each hull lost to the shot, written here whatever
      -- the outcome. While it is off, DESIGN B.6's ratio table, as before.
      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
      if v_fight is not null then
        v_outcome := v_fight->>'outcome';
        update public.ships sh
           set durability = greatest(0, sh.durability - (v_fight->'hull_lost'->>sh.id::text)::numeric)
         where sh.fleet_id = p_fleet and v_fight->'hull_lost' ? sh.id::text;
      else
      v_ratio := case when v_raider <= 0 then 99 else v_escort / v_raider end;
      if    v_ratio >= 2.0 then v_outcome := 'EVADED';
      elsif v_ratio >= 1.2 then v_outcome := 'DRIVEN_OFF';
      elsif v_ratio >= 0.7 then v_outcome := 'RANSOM';
      elsif v_ratio >= 0.3 then v_outcome := 'PLUNDERED';
      else                      v_outcome := 'STRIPPED';
      end if;
      end if;
$h$),
-- voyage.settle: once the fight has written the hull, the raid's update takes the crew only
('voyage.settle(uuid, timestamp with time zone)', 3,
$h$               durability = greatest(0, sh.durability - public.armour_turns(sh.id,
                              sh.durability - sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                              when 'PLUNDERED' then 0.80
                                                                              else 1.00 end)))
$h$,
$h$               -- 0189: while the fight decides (v_fight), it has written the hull already — the crew loss only
               durability = case when v_fight is not null then sh.durability
                            else greatest(0, sh.durability - public.armour_turns(sh.id,
                              sh.durability - sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                              when 'PLUNDERED' then 0.80
                                                                              else 1.00 end))) end
$h$),
-- voyage.settle: the rounds go into the day's payload (only when fought)
('voyage.settle(uuid, timestamp with time zone)', 4,
$h$                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2));
$h$,
$h$                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2))
                   -- 0189: the battle report, in words, and what the fight was (only when one was fought)
                   || case when v_fight is null then '{}'::jsonb
                           else jsonb_build_object('rounds', v_fight->'rounds',
                                                   'fight', (v_fight - 'rounds' - 'outcome' - 'sentence' - 'hull_lost')
                                                            || jsonb_build_object('hull_lost',
                                                                 (select coalesce(sum(hl.value::numeric), 0)
                                                                    from jsonb_each_text(v_fight->'hull_lost') hl))) end;
$h$),
-- voyage.settle: SHOAL_WATER's loss, less what her armour turns (the owner, 2026-10-18: "shoals and damage too")
('voyage.settle(uuid, timestamp with time zone)', 5,
$h$        v_lost := round(s.maxd * (0.04 + 0.11 * h.magnitude), 2);
$h$,
$h$        -- 0189: less what her armour turns (public.armour_turns; at 0, the loss itself)
        v_lost := public.armour_turns(s.id, round(s.maxd * (0.04 + 0.11 * h.magnitude), 2));
$h$),
-- voyage.settle: the VOYAGE_REPORT says where each fight's rounds belong (only when there was one)
('voyage.settle(uuid, timestamp with time zone)', 6,
$h$      || case when v_bonus is null then '{}'::jsonb else jsonb_build_object('training', v_bonus) end);
$h$,
$h$      || case when v_bonus is null then '{}'::jsonb else jsonb_build_object('training', v_bonus) end
      -- 0189: `fights` — for each day fought in rounds, the index of its line in `lines` (the same order) and
      -- its rounds; absent when none was, so a report without a fight is the report it always was
      || (select case when count(*) = 0 then '{}'::jsonb
                      else jsonb_build_object('fights', jsonb_agg(jsonb_build_object('line', z.n - 1, 'rounds', z.payload->'rounds')
                                                                  order by z.n)) end
            from (select ve.payload, row_number() over (order by ve.day_index) as n
                    from public.voyage_events ve where ve.voyage_id = v.id) z
           where z.payload ? 'rounds'));
$h$),
-- voyage.settle: while the fight decides, the day's sentence is the fight's own (the table's would contradict the rounds)
('voyage.settle(uuid, timestamp with time zone)', 7,
$h$      v_prose := case v_outcome
        when 'EVADED'     then 'They stood off and did not close.'
        when 'DRIVEN_OFF' then 'We fired twice and they sheered away.'
        when 'RANSOM'     then 'We paid them off rather than fight.'
        when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
        else 'They took everything but the ship itself.' end;
$h$,
$h$      -- 0189: while the fight decides, its own sentence ("They came alongside and we threw them back."): true of
      -- THIS fight, where the table's "We fired twice …" would contradict the rounds printed beneath it
      v_prose := coalesce(v_fight->>'sentence', case v_outcome
        when 'EVADED'     then 'They stood off and did not close.'
        when 'DRIVEN_OFF' then 'We fired twice and they sheered away.'
        when 'RANSOM'     then 'We paid them off rather than fight.'
        when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
        else 'They took everything but the ship itself.' end);
$h$),
-- public.armour_turns: the formula is public.armour_soak's
('public.armour_turns(uuid, numeric)', 1,
$h$  return round(p_loss * greatest(0, 1 - world.ship_stat(p_ship, 'armour') / 100.0 * v_k), 2);
$h$,
$h$  -- 0189: the one formula, public.armour_soak (shared with the fight's raiders)
  return public.armour_soak(world.ship_stat(p_ship, 'armour'), p_loss);
$h$);

create or replace function pg_temp.recut_0189(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0189 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0189(v_def, h.old);
    if v_n <> 1 then
      raise exception '0189 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0189(fn) from defs_before_0189 order by fn;

comment on function public.armour_turns(uuid, numeric) is
  '0168/0189: THE armour rule for a hull — public.armour_soak with her armour (world.ship_stat); the knob at 0 '
  'returns the loss itself. Read by voyage.settle (STORM, SHOAL_WATER, the old raid). Server-only.';

-- ── 5. THE PROBE (its own company and passages; rolled back whole) ─────────────────────────────
-- a passage between two harbours' anchorages, departed 30 days ago (0158's helper)
create or replace function pg_temp.passage_0189(p_fleet uuid, p_from uuid, p_to uuid)
returns uuid
language plpgsql
as $$
declare
  v_leg jsonb;
begin
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b where a.port_id = p_from and b.port_id = p_to;
  return voyage.depart(p_fleet, voyage.segments_from_course(v_leg), p_from, p_to, now() - interval '30 days');
end $$;

-- one passage settled by the old body or the new, everything it left captured, and the writes rolled back
create or replace function pg_temp.settle_0189(p_voyage uuid, p_fleet uuid, p_old boolean)
returns jsonb
language plpgsql
as $$
declare
  v_p  uuid := (select player_id from public.fleets where id = p_fleet);
  v_t0 timestamptz;
  r    jsonb;
begin
  begin
    v_t0 := clock_timestamp();
    if p_old then
      perform pg_temp.voyage_settle_b0189(p_fleet, now());
    else
      perform voyage.settle(p_fleet, now());
    end if;
    r := jsonb_build_object(
      'voyage', (select jsonb_build_object('status', v.status, 'eta', v.eta, 'delay_hours', v.delay_hours, 'days', v.last_settled_day)
                   from public.voyages v where v.id = p_voyage),
      'events', (select coalesce(jsonb_agg(jsonb_build_object('day', ve.day_index, 'kind', ve.kind, 'payload', ve.payload, 'at', ve.resolved_at)
                                           order by ve.day_index), '[]'::jsonb)
                   from public.voyage_events ve where ve.voyage_id = p_voyage),
      'ships', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'd', s.durability, 'crew', s.crew, 'cargo', s.cargo,
                                                             'water', s.water_t, 'food', s.food_t) order by s.id), '[]'::jsonb)
                  from public.ships s where s.fleet_id = p_fleet),
      'fleet', (select jsonb_build_object('status', f.status, 'port', f.port_id) from public.fleets f where f.id = p_fleet),
      'report', (select e.payload from public.events e
                  where e.player_id = v_p and e.kind = 'VOYAGE_REPORT' and e.payload->>'voyage_id' = p_voyage::text),
      'xp', (select coalesce(jsonb_agg(jsonb_build_object('ship', x.ship_id, 'xp', x.xp) order by x.ship_id), '[]'::jsonb)
               from public.ship_xp x join public.ships s on s.id = x.ship_id where s.fleet_id = p_fleet),
      'units', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'wear', u.wear) order by u.id), '[]'::jsonb)
                  from public.fitted_units u join public.ships s on s.id = u.ship_id where s.fleet_id = p_fleet),
      'ducats', (select ducats from public.players where id = v_p));
    r := r || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    raise exception 'RB_0189';
  exception when others then
    if sqlerrm <> 'RB_0189' then raise; end if;
  end;
  return r;
end $$;

-- a fight's outcome over many days of one crafted fleet: the engine's properties, on a fixed seed
create or replace function pg_temp.engine_0189(p_ships jsonb, p_raider numeric, p_days int, p_escort numeric default 11.74)
returns jsonb
language sql
as $$
  with f as (select voyage.fight_resolve('00000000-0189-4000-8000-0000000000ff'::uuid, d, p_raider, p_escort, p_ships) j
               from generate_series(1, p_days) d)
  select jsonb_build_object(
    'won', count(*) filter (where j->>'outcome' in ('EVADED', 'DRIVEN_OFF')),
    'lost', count(*) filter (where j->>'outcome' in ('PLUNDERED', 'STRIPPED')),
    'stripped', count(*) filter (where j->>'outcome' = 'STRIPPED'),
    'hull', round(coalesce(sum((select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(j->'hull_lost') h)), 0), 2),
    'n', count(*))
  from f
$$;

-- the probe's company at Lisbon: the barca it was founded with and a nau with broadside guns; with p_captains,
-- Turgut Reis (Boarder) in the barca's Captain's cabin and Tartaglia (Gunner) in the nau's
create or replace function pg_temp.house_0189(p_captains boolean)
returns jsonb
language plpgsql
as $$
declare
  c_p     constant uuid := '00000000-0189-4000-8000-000000000001';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_p     uuid;
  v_pf    uuid;
  v_barca uuid;
  v_nau   uuid;
  v_r     jsonb;
begin
  v_p := public.new_house(c_p, 'Casa da Peleja 0189', 'PRT', 'LIS');
  select id into v_pf from public.fleets where player_id = v_p;
  perform public.credit(v_p, 'PROBE_0189', 10000000);
  select id into v_barca from public.ships where fleet_id = v_pf;
  v_nau := public.commission_ship(v_p, v_pf, 'nau', 'Prova Nau', false, true);
  insert into public.player_items (player_id, port_id, item_code, qty) values (v_p, v_lis, 'broadside-guns', 1)
  on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
  v_r := cmd.do_fit(v_pf, jsonb_build_object('item', 'broadside-guns', 'ship', 'Prova Nau'));
  if p_captains then
    perform public.sign_officer(v_p, 'TURGUT', v_pf);
    perform public.seat_captain_for(v_p, 'TURGUT', v_barca, 1);
    perform public.captain_traits_set_for(v_p, 'TURGUT', array['BOARDER']);
    perform public.sign_officer(v_p, 'TARTAGLIA', v_pf);
    perform public.seat_captain_for(v_p, 'TARTAGLIA', v_nau, 1);
    perform public.captain_traits_set_for(v_p, 'TARTAGLIA', array['GUNNER']);
  end if;
  return jsonb_build_object('player', v_p, 'fleet', v_pf, 'barca', v_barca, 'nau', v_nau, 'fit', v_r,
    'mounted', exists (select 1 from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'broadside-guns'));
end $$;

-- a probe passage Lisbon -> Funchal. With p_kind: every day a hazard day (its OWN path's hazard_mult; the seas
-- untouched) and nearly every hazard of that one kind (the other kinds' mix_base at 0.0001, the column's least).
-- Without: the passage as the sea deals it — NOT every day a hazard, because a run of calms and storms that each
-- add days to a passage whose every day is a hazard never arrives (the first cut of this probe met exactly that).
create or replace function pg_temp.forced_passage_0189(p_fleet uuid, p_kind text)
returns uuid
language plpgsql
as $$
declare
  v_voy uuid;
begin
  if p_kind is not null then
    update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
    update public.voyage_event_kinds set mix_base = case when code = p_kind then 1 else 0.0001 end where in_sea_mix;
  end if;
  v_voy := pg_temp.passage_0189(p_fleet, (select id from public.ports where code = 'LIS'), (select id from public.ports where code = 'FNC'));
  if p_kind is not null then
    update public.voyages vo
       set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o)
                     from jsonb_array_elements(vo.path) with ordinality t(e, o))
     where vo.id = v_voy;
  end if;
  return v_voy;
end $$;

create or replace function pg_temp.probe_0189()
returns jsonb
language plpgsql
as $$
declare
  v_h     jsonb;
  v_pf    uuid;
  v_voy   uuid;
  v_out   jsonb := '{}'::jsonb;
  v_base  jsonb;
  v_t0    timestamptz;
  v_t1    timestamptz := clock_timestamp();
begin
  -- OWN PRECONDITIONS in every block: combat dark, armour off (and, for the captains, crew_bite on)
  -- (D1) A PASSAGE OF RAIDS: dark, the old body and the new settle it alike; then lit, fought in rounds
  begin
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    update public.world_config set value = '0'::jsonb where key = 'armour_turns_pct';
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    v_h := pg_temp.house_0189(true);
    v_pf := (v_h->>'fleet')::uuid;
    v_voy := pg_temp.forced_passage_0189(v_pf, 'PIRATES');
    v_out := v_out || jsonb_build_object('house', v_h, 'raids', jsonb_build_object(
      'old', pg_temp.settle_0189(v_voy, v_pf, true), 'new', pg_temp.settle_0189(v_voy, v_pf, false)));
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';
    -- the probe's raiders always close (this passage's seas breed small ones, which a nau would stare down)
    update public.world_config set value = '1000'::jsonb where key = 'fight_standoff_ratio';
    -- … in galleons (good gunners), at close range three rounds, and they never break off: so the passage's fights
    -- take planking to be counted (a hit is 60 % a shot; none in 15 shots is ~1e-6)
    update public.world_config set value = '"galeao"'::jsonb where key = 'fight_raider_class';
    update public.world_config set value = '[["CLOSE",1.0],["CLOSE",1.0],["CLOSE",1.0]]'::jsonb where key = 'fight_ranges';
    update public.world_config set value = '2'::jsonb where key = 'fight_raider_break';
    v_out := jsonb_set(v_out, '{raids,fight1}', voyage.fight(v_voy, 1, v_pf, 20));
    v_out := jsonb_set(v_out, '{raids,fight2}', voyage.fight(v_voy, 1, v_pf, 20));
    v_out := jsonb_set(v_out, '{raids,before}', (select jsonb_agg(jsonb_build_object('id', s.id, 'd', s.durability) order by s.id)
                                                   from public.ships s where s.fleet_id = v_pf));
    v_out := jsonb_set(v_out, '{raids,lit}', pg_temp.settle_0189(v_voy, v_pf, false));
    -- what a lit fight costs to read, over 200 merchant fleets (notice only; a sweep fights a handful)
    v_t0 := clock_timestamp();
    perform voyage.fight(v_voy, 1, z.id, 10)
       from (select f.id from public.fleets f join public.players pl on pl.id = f.player_id
              where pl.is_npc and exists (select 1 from public.ships s where s.fleet_id = f.id) order by f.id limit 200) z;
    v_out := jsonb_set(v_out, '{raids,merchant_fights_ms}', to_jsonb(round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1)));
    v_out := jsonb_set(v_out, '{raids,merchant_fleets}', to_jsonb((select count(*) from (select 1 from public.fleets f join public.players pl on pl.id = f.player_id
                                                                   where pl.is_npc and exists (select 1 from public.ships s where s.fleet_id = f.id) limit 200) z)));
    raise exception 'PROBE_ROLLBACK_0189';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0189' then raise; end if;
  end;
  raise notice '0189 probe: block % done at % ms', 1, round(extract(epoch from clock_timestamp() - v_t1) * 1000);

  -- (D2) A PASSAGE OF SHOALS: dark alike; lit (armour at 0.5, combat still off), less lost on every shoal day
  begin
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    update public.world_config set value = '0'::jsonb where key = 'armour_turns_pct';
    v_h := pg_temp.house_0189(false);
    v_pf := (v_h->>'fleet')::uuid;
    v_voy := pg_temp.forced_passage_0189(v_pf, 'SHOAL_WATER');
    v_out := v_out || jsonb_build_object('shoals', jsonb_build_object(
      'old', pg_temp.settle_0189(v_voy, v_pf, true), 'new', pg_temp.settle_0189(v_voy, v_pf, false)));
    update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';
    v_out := jsonb_set(v_out, '{shoals,lit}', pg_temp.settle_0189(v_voy, v_pf, false));
    raise exception 'PROBE_ROLLBACK_0189';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0189' then raise; end if;
  end;
  raise notice '0189 probe: block % done at % ms', 2, round(extract(epoch from clock_timestamp() - v_t1) * 1000);

  -- (D3) A PASSAGE AS THE SEA DEALS IT (the world's own odds and mix): dark alike
  begin
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    update public.world_config set value = '0'::jsonb where key = 'armour_turns_pct';
    v_h := pg_temp.house_0189(true);
    v_pf := (v_h->>'fleet')::uuid;
    v_voy := pg_temp.forced_passage_0189(v_pf, null);
    v_out := v_out || jsonb_build_object('mixed', jsonb_build_object(
      'old', pg_temp.settle_0189(v_voy, v_pf, true), 'new', pg_temp.settle_0189(v_voy, v_pf, false)));
    raise exception 'PROBE_ROLLBACK_0189';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0189' then raise; end if;
  end;
  raise notice '0189 probe: block % done at % ms', 3, round(extract(epoch from clock_timestamp() - v_t1) * 1000);

  -- (E) THE ENGINE'S PROPERTIES on crafted hulls, a fixed seed, 300 days each (armour at 0.5, rolled back)
  begin
    update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';
    v_base := jsonb_build_array(jsonb_build_object('id', '00000000-0189-4000-8000-0000000000a1', 'name', 'Probe', 'tier', 2, 'hull', 550,
                'maxd', 550, 'crew', 12, 'attack', 55, 'accuracy', 40, 'reach', 25, 'armour', 12, 'sighting', 10));
    v_out := v_out || jsonb_build_object('engine', jsonb_build_object(
      'base',     pg_temp.engine_0189(v_base, 12, 300),
      'reach',    pg_temp.engine_0189(jsonb_set(v_base, '{0,reach}', '60'), 12, 300),
      'accuracy', pg_temp.engine_0189(jsonb_set(v_base, '{0,accuracy}', '70'), 12, 300),
      'attack',   pg_temp.engine_0189(jsonb_set(v_base, '{0,attack}', '110'), 12, 300),
      'armour',   pg_temp.engine_0189(jsonb_set(v_base, '{0,armour}', '50'), 12, 300),
      'crew',     pg_temp.engine_0189(jsonb_set(v_base, '{0,crew}', '40'), 12, 300),
      'boarder',  pg_temp.engine_0189(jsonb_set(jsonb_set(v_base, '{0,boarder_pct}', '0.5'), '{0,boarder}', '"Probe Boarder"'), 12, 300),
      'unarmed',  pg_temp.engine_0189(jsonb_set(jsonb_set(v_base, '{0,attack}', '0'), '{0,accuracy}', '0'), 12, 300),
      'same',     voyage.fight_resolve('00000000-0189-4000-8000-0000000000ff'::uuid, 7, 12, 11.74, v_base)
                    = voyage.fight_resolve('00000000-0189-4000-8000-0000000000ff'::uuid, 7, 12, 11.74, v_base),
      'no_raider', voyage.fight_resolve('00000000-0189-4000-8000-0000000000ff'::uuid, 7, 0, 11.74, v_base),
      'standoff', pg_temp.engine_0189(v_base, 12, 50, 24)));
    raise exception 'PROBE_ROLLBACK_0189';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0189' then raise; end if;
  end;
  raise notice '0189 probe: block % done at % ms', 4, round(extract(epoch from clock_timestamp() - v_t1) * 1000);
  return v_out;
end $$;

create temp table probe_0189 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0189 select pg_temp.probe_0189();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0189 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  v_d     record;
  v_h     record;
  v_pp    record;
  v_pr    jsonb := (select j from probe_0189);
  v_x     jsonb;
  v_e     jsonb;
  v_def   text;
  v_n     int;
  v_m     int;
  v_lines jsonb;
  v_lost  numeric;
  v_drop  numeric;
  v_dark  numeric;
  v_lit   numeric;
  v_eng   jsonb;
begin
  select * into v_b from before_0189;
  if v_pr is null then
    raise exception '0189 self-assert FAIL: the probe returned nothing';
  end if;
  if not coalesce((v_pr->'house'->>'mounted')::boolean, false) then
    raise exception '0189 self-assert FAIL: the probe could not fit its broadside guns: %', v_pr->'house'->'fit';
  end if;

  -- (a) DARK, EVERY PASSAGE: the old body and the new leave the same world, day for day (the time aside)
  for v_x in select v_pr->k from unnest(array['raids', 'shoals', 'mixed']) k loop
    if (v_x->'old') - 'ms' is distinct from (v_x->'new') - 'ms' then
      raise exception '0189 self-assert FAIL: dark, a passage settled differently by the new body: old % new %', v_x->'old', v_x->'new';
    end if;
    if jsonb_array_length(v_x->'old'->'events') < 2 or v_x->'old'->'voyage'->>'status' <> 'ARRIVED' or v_x->'old'->'report' is null then
      raise exception '0189 self-assert FAIL: a probe passage did not settle to an arrival with a report: %', v_x->'old'->'voyage';
    end if;
  end loop;
  select count(*) into v_n from jsonb_array_elements(v_pr->'raids'->'old'->'events') e where e->>'kind' = 'PIRATES';
  select count(*) into v_m from jsonb_array_elements(v_pr->'shoals'->'old'->'events') e where e->>'kind' = 'SHOAL_WATER';
  if v_n = 0 or v_m = 0 then
    raise exception '0189 self-assert FAIL: the forced passages met % raid(s) and % shoal(s) — the probe proves nothing', v_n, v_m;
  end if;
  if exists (select 1 from jsonb_array_elements(v_pr->'raids'->'new'->'events') e where e->'payload' ? 'rounds')
     or v_pr->'raids'->'new'->'report' ? 'fights' then
    raise exception '0189 self-assert FAIL: dark, a raid was fought in rounds';
  end if;

  -- (b) LIT: every raid day fought in rounds, the report pointing at each fought day's line
  v_x := v_pr->'raids'->'lit';
  v_lines := v_x->'report'->'lines';
  select count(*) into v_m from jsonb_array_elements(v_x->'events') e
   where e->>'kind' = 'PIRATES'
     and e->'payload' ? 'rounds' and jsonb_array_length(e->'payload'->'rounds') >= 2
     and e->'payload'->>'outcome' in ('EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED', 'STRIPPED')
     and e->'payload'->'fight' ? 'raiders'
     and e->'payload'->>'prose' in ('They stood off and did not close.', 'We saw them first and slipped away.', 'They broke off and ran.',
                                    'They came alongside and we threw them back.', 'They came alongside and we paid them off.',
                                    'They came aboard and took what they could carry.', 'They took everything but the ships themselves.');
  select count(*) into v_n from jsonb_array_elements(v_x->'events') e where e->>'kind' = 'PIRATES';
  if v_n = 0 or v_m <> v_n then
    raise exception '0189 self-assert FAIL: lit, % of % raid day(s) were fought in rounds: %', v_m, v_n, v_x->'events';
  end if;
  if jsonb_array_length(coalesce(v_x->'report'->'fights', '[]'::jsonb)) <> v_n
     or exists (select 1 from jsonb_array_elements(v_x->'report'->'fights') f
                 where (v_lines->>((f->>'line')::int)) not like
                         format('Day %s. Sail sighted%%', (select e->>'day' from jsonb_array_elements(v_x->'events') e
                                                            where e->'payload'->'rounds' = f->'rounds' limit 1))) then
    raise exception '0189 self-assert FAIL: lit, the report''s fights do not point at their days'' lines: % / %', v_x->'report'->'fights', v_lines;
  end if;
  -- the hull each fight said it took is the hull that went (with any storm's or shoal's own hull_lost)
  select coalesce(sum(coalesce((e->'payload'->'fight'->>'hull_lost')::numeric, (e->'payload'->>'hull_lost')::numeric, 0)), 0) into v_lost
    from jsonb_array_elements(v_x->'events') e;
  select coalesce(sum((b->>'d')::numeric), 0) - coalesce(sum((a->>'d')::numeric), 0) into v_drop
    from jsonb_array_elements(v_pr->'raids'->'before') b
    join jsonb_array_elements(v_x->'ships') a on a->>'id' = b->>'id';
  if not (v_lost > 0) or abs(v_lost - v_drop) > 0.02 * greatest(1, v_n) then
    raise exception '0189 self-assert FAIL: lit, the fights said % hull was lost and the hulls lost %', v_lost, v_drop;
  end if;
  -- the same fight read twice is the same fight; it names the Gunner, the Boarder (at a boarding) and the gear
  if v_pr->'raids'->'fight1' is distinct from v_pr->'raids'->'fight2' then
    raise exception '0189 self-assert FAIL: one day''s fight read twice differed';
  end if;
  if not exists (select 1 from jsonb_array_elements_text(v_pr->'raids'->'fight1'->'rounds') l where l like '%lays the guns on Prova Nau.%')
     or not exists (select 1 from jsonb_array_elements_text(v_pr->'raids'->'fight1'->'rounds') l where l like 'Ready for them: %Prova Nau (Broadside Guns)%') then
    raise exception '0189 self-assert FAIL: the fight did not name the Gunner or the gear that works on a raid: %', v_pr->'raids'->'fight1'->'rounds';
  end if;

  -- (c) SHOALS: dark alike (above); lit, every shoal day takes less, by armour_soak's own formula
  select coalesce(sum((e->'payload'->>'hull_lost')::numeric), 0) into v_dark
    from jsonb_array_elements(v_pr->'shoals'->'new'->'events') e where e->>'kind' = 'SHOAL_WATER';
  select coalesce(sum((e->'payload'->>'hull_lost')::numeric), 0) into v_lit
    from jsonb_array_elements(v_pr->'shoals'->'lit'->'events') e where e->>'kind' = 'SHOAL_WATER';
  if not (v_lit < v_dark) or exists (
       select 1 from jsonb_array_elements(v_pr->'shoals'->'new'->'events') dk
         join jsonb_array_elements(v_pr->'shoals'->'lit'->'events') lt on lt->>'day' = dk->>'day'
        where dk->>'kind' = 'SHOAL_WATER' and not ((lt->'payload'->>'hull_lost')::numeric < (dk->'payload'->>'hull_lost')::numeric)) then
    raise exception '0189 self-assert FAIL: armour did not lessen every shoal day (dark %, lit %)', v_dark, v_lit;
  end if;

  -- (d) THE ENGINE: range, accuracy and attack each win more often; armour takes less hull; crew and a
  --     Boarder lose less at the boarding; an unarmed hull wins less; the same day is the same fight
  v_eng := v_pr->'engine';
  if not ((v_eng->'reach'->>'won')::int > (v_eng->'base'->>'won')::int
          and (v_eng->'accuracy'->>'won')::int > (v_eng->'base'->>'won')::int
          and (v_eng->'attack'->>'won')::int > (v_eng->'base'->>'won')::int
          and (v_eng->'armour'->>'hull')::numeric < (v_eng->'base'->>'hull')::numeric
          and (v_eng->'crew'->>'lost')::int < (v_eng->'base'->>'lost')::int
          and (v_eng->'boarder'->>'lost')::int < (v_eng->'base'->>'lost')::int
          and (v_eng->'unarmed'->>'won')::int < (v_eng->'base'->>'won')::int
          and (v_eng->>'same')::boolean
          and v_eng->'no_raider'->>'outcome' = 'EVADED'
          and (v_eng->'standoff'->>'won')::int = 50 and (v_eng->'standoff'->>'hull')::numeric = 0) then
    raise exception '0189 self-assert FAIL: the engine''s properties do not hold: %', v_eng;
  end if;

  -- (e) THE READERS: armour_soak by armour_turns and the core; the core by voyage.fight; voyage.fight by settle
  create or replace function pg_temp.readers_0189(p_name text)
  returns text
  language sql
  as $f$
    select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
       and p.prosrc like '%' || p_name || '(%'
       and n.nspname || '.' || p.proname <> p_name
  $f$;
  if pg_temp.readers_0189('public.armour_soak') is distinct from 'public.armour_turns,voyage.fight_resolve'
     or pg_temp.readers_0189('voyage.fight_resolve') is distinct from 'voyage.fight'
     or pg_temp.readers_0189('voyage.fight') is distinct from 'voyage.settle'
     or pg_temp.readers_0189('public.armour_turns') is distinct from 'voyage.settle' then
    raise exception '0189 self-assert FAIL: readers — armour_soak %, fight_resolve %, fight %, armour_turns %',
      pg_temp.readers_0189('public.armour_soak'), pg_temp.readers_0189('voyage.fight_resolve'),
      pg_temp.readers_0189('voyage.fight'), pg_temp.readers_0189('public.armour_turns');
  end if;
  begin
    execute $planted$create function public.zz_planted_reader_0189() returns jsonb language sql as
      'select voyage.fight(null, 1, null, 1)'$planted$;
    if pg_temp.readers_0189('voyage.fight') is not distinct from 'voyage.settle' then
      raise exception '0189 self-assert FAIL: the reader scan did not see a planted reader — it proves nothing';
    end if;
    raise exception 'CONTROL_ROLLBACK_0189';
  exception when others then
    if sqlerrm <> 'CONTROL_ROLLBACK_0189' then raise; end if;
  end;

  -- (f) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved; the rest untouched
  for v_d in select * from defs_before_0189 order by fn loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0189 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0189(v_def, v_h.new) <> 1 then
        raise exception '0189 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0189 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0189 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from untouched_before_0189 loop
    if replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '') <> v_d.def then
      raise exception '0189 self-assert FAIL: % moved — it was to be left untouched', v_d.fn;
    end if;
  end loop;

  -- (g) THE KNOBS (this file's nine) and THE WALL: no entry point; nothing new reachable by a client
  if (select count(*) from public.world_config where key in ('fight_raider_class', 'fight_ranges', 'fight_damage_per_attack',
        'fight_raider_break', 'fight_evade_per_sighting', 'fight_evade_max', 'fight_standoff_ratio', 'fight_hand_value',
        'fight_board_bands')) <> 9 then
    raise exception '0189 self-assert FAIL: the nine fight knobs are not all present';
  end if;
  if (select value from public.world_config where key = 'combat_bite') <> 'false'::jsonb
     or (select value from public.world_config where key = 'armour_turns_pct') <> '0'::jsonb then
    raise exception '0189 self-assert FAIL: this file is dark, and combat_bite or armour_turns_pct is not';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['public.armour_soak(numeric, numeric)', 'voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)',
                                           'voyage.fight(uuid, integer, uuid, numeric)']) f(fn),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, f.fn, 'execute')) then
    raise exception '0189 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach a new function';
  end if;

  v_e := (select e from jsonb_array_elements(v_pr->'raids'->'lit'->'events') e where e->>'kind' = 'PIRATES' order by (e->>'day')::int limit 1);
  raise notice '0189 self-assert ok: A RAID IS FOUGHT IN ROUNDS (dark: combat_bite false, armour_turns_pct 0). DARK: three probe passages (% raid day(s), % shoal day(s), and one as the sea deals it) settled by the old body and the new alike — events, hulls, crew, cargo, report, experience, wear, purse. LIT (rolled back): % raid day(s) fought in rounds, the report''s fights at their days'' lines, % hull said = % hull lost; one day read twice the same; the Gunner and the gear named; shoals: % → % hull with armour at 0.5. ENGINE (300 days, fixed seed, won / lost / hull): base %/%/%, reach 60 %/%, accuracy 70 %/%, attack 110 %/%, armour 50 hull %, crew 40 lost %, a Boarder +50%% lost %, unarmed won %. FIRST FIGHT: % — %. READ COST (notice only): voyage.fight over % merchant fleet(s) % ms; the raid passage settled old % ms, new % ms. READERS: armour_soak by armour_turns and the core, the core by voyage.fight, voyage.fight by settle (a planted reader seen). 2 bodies reverse, 11 untouched, nine knobs, no entry point.',
    (select count(*) from jsonb_array_elements(v_pr->'raids'->'old'->'events') e where e->>'kind' = 'PIRATES'),
    (select count(*) from jsonb_array_elements(v_pr->'shoals'->'old'->'events') e where e->>'kind' = 'SHOAL_WATER'),
    v_n, v_lost, v_drop, v_dark, v_lit,
    v_eng->'base'->>'won', v_eng->'base'->>'lost', v_eng->'base'->>'hull', v_eng->'reach'->>'won', v_eng->'reach'->>'lost',
    v_eng->'accuracy'->>'won', v_eng->'accuracy'->>'lost', v_eng->'attack'->>'won', v_eng->'attack'->>'lost',
    v_eng->'armour'->>'hull', v_eng->'crew'->>'lost', v_eng->'boarder'->>'lost', v_eng->'unarmed'->>'won',
    v_e->'payload'->>'outcome', v_e->'payload'->'rounds',
    v_pr->'raids'->>'merchant_fleets', v_pr->'raids'->>'merchant_fights_ms',
    v_pr->'raids'->'old'->>'ms', v_pr->'raids'->'new'->>'ms';
end $$;
