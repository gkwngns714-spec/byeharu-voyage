-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0320 — A FIGHT HAS TWO SIDES: voyage.fight_resolve stops being the engine and becomes a skin; the engine takes real hulls on both sides. No fight changes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Slice W5 of docs/WORLD_POWERS.md, sections 2.5, 2.6 (owner rows 283, 288). It comes before anything else that fights. Nothing here lets anyone attack anyone: no verb, no job, no client door.
-- WHAT THIS FILE DOES
--   public.fight_sides(seed, round, a, b, opts)  THE ENGINE, new. Hulls on both sides, in the p_ships shape. `a` is the side set upon, `b` the side that closes. Returns numbers, never words:
--                                                the outcome from a's side, each round's figures, and hull_lost for BOTH sides by ship id. Reads no table but world_config (through public.wc*).
--   public.fight_volley(...)                     ONE side's guns in one round: the one firing rule, so neither side has a rule of its own.
--   voyage.raider_hulls(strength)                THE builder of raiders, new: the only reader of fight_raider_class and ship_classes in a fight.
--   voyage.fight_resolve                         THE SKIN: same arguments, same answer. It builds the raiders, calls the engine and writes the battle report in today's words.
-- A RAID IS ONE SQUADRON HULL, NOT WHOLE XEBECS (decided by default; docs/dev-log/2026-11-06-a-fight-has-two-sides.md). A raid's strength is fractional (say 2.3 xebecs), its hull one pool, its shots
--   ceil(strength). Whole hulls would waste overkill on a sunk hull and silence her guns, and that is a different fight. So raider_hulls returns ONE hull, every figure scaled, with `shots`: a hull
--   fires `shots` shots, each attack / shots. Every real hull has no `shots`, so 1. One rule for both sides.
-- THE STREAMS ARE FROZEN: 'fight:<round>:you:<n>' is side a, ':they:' side b, ':at' and ':dmg' as before, 'fight:evade' as before. n counts shots along the side; a hull that cannot fire keeps her numbers.
--   A shot's target on side b is a new stream, ':you:<n>:at', which moves no other number: voyage.rng is keyed, not sequential.
-- WHAT DOES NOT CHANGE: every raid, word for word. voyage.fight, voyage.settle, voyage.escort_score, public.armour_soak, voyage.rng, every knob. No table, no job, no money.
-- ONE CORNER MOVES, ON NO LIVE STATE (dev-log): a raider class with no guns (fight_raider_class is 'xebec') no longer 'hits' for nothing, and shots at a sunk squadron (only if fight_raider_break were above 1)
--   stop. A broken knob on a fleet that stands off now raises in the engine exactly as before; a broken class with an empty fleet names the class first.
-- THERE IS NO SWITCH: section 2.5 has none, and two fight bodies would be two authorities. Dark here means this: the two-sided path has no caller, and the one live path answers byte for byte as before.
-- SELF-ASSERT, all on crafted hulls, no row written, no economy door (no credit, no treasury_post): the pre-image is the one this was cut against; the old body (a pg_temp copy of the live one) and the skin
--   agree as text on 0202's 960-day probe and on a 120-day convoy probe; both sides lose hull by ship id; the engine names no table; the raiders are built once; grants; nothing else moved; no knob moved.
--   The wider matrix and a real fleet: proof 28, scripts/db/proofs/28_fight_sides.sql. Mutation controls: scripts/ops/harness/two-sides/proof-0320.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. About 2,200 pure fights, no market row. Self-assert fails above 40 s.
-- ROLLBACK (forward, a NEW migration, owner only): the pre-image is held whole in proof 28 (digest in the PR's PROD CHECK 1); put it back, drop the three new functions.
-- SUPERSEDES (re-cut): voyage.fight_resolve (0189, re-cut by 0202, 0204, 0213, 0276) is replaced whole: its engine moves to public.fight_sides, its raiders to voyage.raider_hulls, its words stay. The self-assert proves the guard digest and the answers, not hunks: the whole body changes.
-- VERSION: 0320, after 0318 (#514) and 0319 (#513), which touch none of these bodies. Prod head 0317 when cut.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_pre  constant text := '8fc074d4f0a09332b321eb55a600c2fc';
  c_fr   constant text := 'voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)';
  c_new  constant text[] := array['public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)',
    'public.fight_volley(uuid,integer,integer,text,text,numeric,boolean,numeric,numeric[],numeric[],numeric[],numeric[],integer[],numeric,numeric[],numeric[],numeric[])',
    'voyage.raider_hulls(numeric)'];
  c_seed constant uuid := '00000000-0320-4000-8000-0000000000ff';
  v_def0 text;
  v_fn_before text;
  v_cfg_before text;
  v_meta_before text;
  v_carlat jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a1', 'name', 'Probe Carlat',
                      'tier', 1, 'hull', 550, 'maxd', 550, 'crew', 12, 'attack', 55, 'accuracy', 40, 'reach', 25, 'armour', 12,
                      'sighting', 10, 'gear', jsonb_build_array('Boarding Gear')));
  v_barca  jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a2', 'name', 'Probe Barca',
                      'tier', 1, 'hull', 400, 'maxd', 400, 'crew', 8, 'attack', 35, 'accuracy', 0, 'reach', 0, 'armour', 5,
                      'sighting', 8));
  v_three  jsonb := jsonb_build_array(
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a3', 'name', 'Probe Nau', 'tier', 3, 'hull', 1500, 'maxd', 1800, 'crew', 90, 'attack', 180,
                        'accuracy', 55, 'reach', 60, 'armour', 30, 'sighting', 40, 'boarder_pct', 0.12, 'boarder', 'Probe Boarder', 'gunner', 'Probe Gunner', 'gear', jsonb_build_array('Swivel Guns', 'Boarding Gear')),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a4', 'name', 'Probe Galion', 'tier', 4, 'hull', 2400, 'maxd', 2400, 'crew', 140, 'attack', 260,
                        'accuracy', 48, 'reach', 40, 'armour', 44, 'sighting', 22),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a5', 'name', 'Probe Wreck', 'tier', 1, 'hull', 0, 'maxd', 500, 'crew', 6, 'attack', 40,
                        'accuracy', 40, 'reach', 90, 'armour', 0, 'sighting', 5));
  v_two    jsonb := jsonb_build_array(
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000b1', 'name', 'Probe One', 'tier', 2, 'hull', 9000, 'maxd', 9000, 'crew', 40, 'attack', 120,
                        'accuracy', 60, 'reach', 50, 'armour', 20, 'sighting', 22),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000b2', 'name', 'Probe Two', 'tier', 2, 'hull', 9000, 'maxd', 9000, 'crew', 40, 'attack', 120,
                        'accuracy', 60, 'reach', 50, 'armour', 20, 'sighting', 22));
  v_x    record;
  v_n    int := 0;
  v_bad  int := 0;
  v_ex   jsonb;
  v_old  jsonb;
  v_new  jsonb;
  v_kinds jsonb := '{}'::jsonb;
  v_f    jsonb;
  v_src  text;
  v_seen_a int := 0;
  v_seen_b int := 0;
  v_seen1 int := 0;
  v_seen2 int := 0;
  v_t0   timestamptz := clock_timestamp();
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)') is not null then
    raise exception '0320 refuses: it has been applied once';
  end if;
  v_def0 := replace(pg_get_functiondef(c_fr::regprocedure), E'\r', '');
  if md5(v_def0) <> c_pre then
    raise exception '0320 refuses: voyage.fight_resolve is not the body this file was cut against (%)', md5(v_def0);
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fr::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c where c.key like 'fight%' or c.key in ('armour_turns_pct', 'combat_bite', 'world_secret');
  select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || pg_get_userbyid(p.proowner) into v_meta_before
    from pg_proc p where p.oid = c_fr::regprocedure;

  -- the old body, kept for this transaction only, for the parity below
  execute replace(v_def0, 'CREATE OR REPLACE FUNCTION voyage.fight_resolve(', 'CREATE FUNCTION pg_temp.fight_resolve_old_0320(');

  -- ── 1. ONE SIDE'S GUNS ──
  execute $f$
create function public.fight_volley(
  p_seed uuid, p_day int, p_g int, p_tag text, p_range text, p_mult numeric, p_unready boolean, p_k numeric,
  p_att numeric[], p_acc numeric[], p_reach numeric[], p_hull numeric[], p_shots int[],
  p_bar numeric, p_e_arm numeric[], p_e_hull numeric[], p_e_maxd numeric[],
  out can int, out fired int, out hits int, out raw numeric, out dealt numeric, out taken numeric[])
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0320: ONE SIDE'S GUNS IN ONE ROUND, the one firing rule of a fight, called once for each side by public.fight_sides.
-- A hull with attack, accuracy and hull left CAN fire. She does not when her side is caught unready, nor at LONG range unless her reach is at least the other side's best (p_bar): range decides who fires.
-- A hull fires p_shots[i] shots (1 for a real hull). A shot hits on accuracy / 100 × the range's share (5-95 %), falls on the other side's hulls afloat by their size, and takes
-- attack / shots × p_k × (0.75-1.25) of hull, less her armour. Nothing lands here: the two sides' figures land together in the caller. n counts shots along the side, so a hull that cannot fire keeps her numbers.
declare
  i      int;
  s      int;
  j      int;
  n      int := 0;
  t      int;
  v_size numeric := 0;
  v_pick numeric;
  v_sum  numeric;
  v_d    numeric;
begin
  can := 0; fired := 0; hits := 0; raw := 0; dealt := 0;
  taken := array_fill(0::numeric, array[cardinality(p_e_hull)]);
  for j in 1 .. cardinality(p_e_hull) loop
    if p_e_hull[j] > 0 then
      v_size := v_size + p_e_maxd[j];
    end if;
  end loop;
  for i in 1 .. cardinality(p_att) loop
    if p_att[i] <= 0 or p_acc[i] <= 0 or p_hull[i] <= 0 then
      n := n + p_shots[i];
      continue;
    end if;
    can := can + 1;
    if p_unready or (p_range = 'LONG' and p_reach[i] < p_bar) then
      n := n + p_shots[i];
      continue;
    end if;
    for s in 1 .. p_shots[i] loop
      n := n + 1;
      fired := fired + 1;
      continue when voyage.rng(p_seed, p_day, format('fight:%s:%s:%s', p_g, p_tag, n))
                      >= least(0.95, greatest(0.05, p_acc[i] / 100.0 * p_mult));
      v_pick := voyage.rng(p_seed, p_day, format('fight:%s:%s:%s:at', p_g, p_tag, n)) * v_size;
      t := null;
      v_sum := 0;
      for j in 1 .. cardinality(p_e_hull) loop
        continue when p_e_hull[j] <= 0;
        v_sum := v_sum + p_e_maxd[j];
        t := j;
        exit when v_pick < v_sum;
      end loop;
      if t is null then
        return;
      end if;
      hits := hits + 1;
      v_d := p_att[i] / p_shots[i] * p_k * (0.75 + 0.5 * voyage.rng(p_seed, p_day, format('fight:%s:%s:%s:dmg', p_g, p_tag, n)));
      raw := raw + v_d;
      v_d := public.armour_soak(p_e_arm[t], v_d);
      dealt := dealt + v_d;
      taken[t] := taken[t] + v_d;
    end loop;
  end loop;
end $body$;
$f$;
  comment on function public.fight_volley(uuid, int, int, text, text, numeric, boolean, numeric, numeric[], numeric[], numeric[], numeric[], int[], numeric, numeric[], numeric[], numeric[]) is
    '0320: one side''s guns in one round, the one firing rule of a fight. Read by public.fight_sides. Server-only.';
  revoke all on function public.fight_volley(uuid, int, int, text, text, numeric, boolean, numeric, numeric[], numeric[], numeric[], numeric[], int[], numeric, numeric[], numeric[], numeric[]) from public, anon, authenticated;

  -- ── 2. THE ENGINE ──
  execute $f$
create function public.fight_sides(p_seed uuid, p_round int, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0320: THE FIGHT, the one combat authority (docs/WORLD_POWERS.md 2.5). Hulls on both sides, each an object
--   {id, name, tier, hull, maxd, crew, attack, accuracy, reach, armour, sighting, boarder_pct, shots}; shots is 1 unless said, and only raiders say (voyage.raider_hulls).
-- p_a is the side set upon, p_b the side that closes; p_round is the voyage day of a raid, whichever turn the caller keys a fight by. A pure function of its arguments, the fight_* knobs, armour_turns_pct and the world secret: the same (seed, round) fought twice is the same fight.
-- Numbers only: no word of a report is written here, and no table is named here; those are the callers'.
--   SIZING UP  p_opts {a_score, b_score}: b does not close on a side fight_standoff_ratio times its score or more; nor does a side with no hull. stood_off, no shot fired.
--   SIGHTING   the better best sighting fires the first round alone; if that is a, a lead may let her slip away (fight_evade_per_sighting × lead, at most fight_evade_max). The side that closes never slips.
--   ROUNDS     fight_ranges in order, each side's guns by public.fight_volley, both broadsides landing together. b breaks off at fight_raider_break of its hull lost: EVADED if a was never touched, else DRIVEN_OFF.
--   BOARDING   if b has not broken off: each side's hulls, (crew × fight_hand_value × (1 + boarder_pct) + tier × 3) × the share of hull left, read against fight_board_bands: DRIVEN_OFF, RANSOM, PLUNDERED;
--              below the last band a surrenders (0202), and that is still PLUNDERED.
-- Returns {outcome, stood_off, slipped, broke_off, first (A, B, BOTH), rounds_fought, rounds[{round, range, a{can, fired, hits, raw, dealt, struck[[hull index, percent of her size]], left}, b{...}}],
--   board{a_power, b_power, ratio, surrender, a_crew, b_crew}, hull_lost{a{ship id: points}, b{ship id: points}}, hull{a, b, a_start, b_start}, hits{a, b}}.
declare
  v_ranges jsonb := public.wc('fight_ranges');
  v_k      numeric := public.wc_num('fight_damage_per_attack');
  v_break  numeric := public.wc_num('fight_raider_break');
  v_bands  jsonb := public.wc('fight_board_bands');
  v_hand   numeric := public.wc_num('fight_hand_value');
  v_na     int := coalesce(jsonb_array_length(p_a), 0);
  v_nb     int := coalesce(jsonb_array_length(p_b), 0);
  x        jsonb;
  i        int;
  g        int;
  a_id     uuid[] := '{}';
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
  a_shots  int[] := '{}';
  b_id     uuid[] := '{}';
  b_att    numeric[] := '{}';
  b_acc    numeric[] := '{}';
  b_reach  numeric[] := '{}';
  b_arm    numeric[] := '{}';
  b_hull0  numeric[] := '{}';
  b_hull   numeric[] := '{}';
  b_maxd   numeric[] := '{}';
  b_crew   numeric[] := '{}';
  b_bpct   numeric[] := '{}';
  b_tier   numeric[] := '{}';
  b_shots  int[] := '{}';
  v_sa     numeric := 0;
  v_sb     numeric := 0;
  v_ba     numeric := 0;
  v_bb     numeric := 0;
  v_h0a    numeric := 0;
  v_h0b    numeric := 0;
  v_la     numeric;
  v_lb     numeric;
  v_first  text;
  v_range  text;
  v_mult   numeric;
  v_va     record;
  v_vb     record;
  v_sta    jsonb;
  v_stb    jsonb;
  v_pct    numeric;
  v_rows   jsonb := '[]'::jsonb;
  v_tot_a  int := 0;
  v_tot_b  int := 0;
  v_fought int := 0;
  v_outcome text;
  v_broke  boolean := false;
  v_board  jsonb;
  p_you    numeric := 0;
  p_they   numeric := 0;
  c_you    numeric := 0;
  c_they   numeric := 0;
  v_ratio  numeric;
begin
  if v_na = 0 or v_nb = 0 then
    raise exception 'E_NO_SHIPS: a fight needs at least one hull' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_ranges) <> 'array' or jsonb_array_length(v_ranges) = 0 or jsonb_typeof(v_bands) <> 'array'
     or jsonb_array_length(v_bands) <> 3 then
    raise exception 'E_FIGHT_KNOBS: fight_ranges must list at least one round and fight_board_bands three bands'
      using errcode = 'P0001';
  end if;

  -- each side, one array per figure (index = her place in the side)
  for i in 1 .. v_na loop
    x := p_a -> (i - 1);
    a_id[i]    := (x->>'id')::uuid;
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
    a_shots[i] := greatest(1, coalesce((x->>'shots')::int, 1));
    v_sa       := greatest(v_sa, coalesce((x->>'sighting')::numeric, 0));
    v_h0a      := v_h0a + a_hull0[i];
    if a_att[i] > 0 and a_acc[i] > 0 then
      v_ba := greatest(v_ba, a_reach[i]);
    end if;
  end loop;
  for i in 1 .. v_nb loop
    x := p_b -> (i - 1);
    b_id[i]    := (x->>'id')::uuid;
    b_att[i]   := greatest(0, coalesce((x->>'attack')::numeric, 0));
    b_acc[i]   := greatest(0, coalesce((x->>'accuracy')::numeric, 0));
    b_reach[i] := greatest(0, coalesce((x->>'reach')::numeric, 0));
    b_arm[i]   := greatest(0, coalesce((x->>'armour')::numeric, 0));
    b_hull0[i] := greatest(0, coalesce((x->>'hull')::numeric, 0));
    b_hull[i]  := b_hull0[i];
    b_maxd[i]  := greatest(1, coalesce((x->>'maxd')::numeric, 1));
    b_crew[i]  := greatest(0, coalesce((x->>'crew')::numeric, 0));
    b_bpct[i]  := greatest(0, coalesce((x->>'boarder_pct')::numeric, 0));
    b_tier[i]  := greatest(0, coalesce((x->>'tier')::numeric, 0));
    b_shots[i] := greatest(1, coalesce((x->>'shots')::int, 1));
    v_sb       := greatest(v_sb, coalesce((x->>'sighting')::numeric, 0));
    v_h0b      := v_h0b + b_hull0[i];
    if b_att[i] > 0 and b_acc[i] > 0 then
      v_bb := greatest(v_bb, b_reach[i]);
    end if;
  end loop;

  -- SIZING UP
  if v_h0b <= 0 or (p_opts ? 'a_score' and coalesce((p_opts->>'a_score')::numeric, 0) >= public.wc_num('fight_standoff_ratio') * (p_opts->>'b_score')::numeric) then
    return jsonb_build_object('outcome', 'EVADED', 'stood_off', true, 'slipped', false, 'broke_off', false, 'first', 'BOTH', 'rounds_fought', 0, 'rounds', '[]'::jsonb,
                              'hull_lost', jsonb_build_object('a', '{}'::jsonb, 'b', '{}'::jsonb),
                              'hull', jsonb_build_object('a', v_h0a, 'b', v_h0b, 'a_start', v_h0a, 'b_start', v_h0b), 'hits', jsonb_build_object('a', 0, 'b', 0));
  end if;

  -- SIGHTING
  v_first := case when v_sa > v_sb then 'A' when v_sa < v_sb then 'B' else 'BOTH' end;
  if v_first = 'A'
     and voyage.rng(p_seed, p_round, 'fight:evade') < least(public.wc_num('fight_evade_max'), (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')) then
    return jsonb_build_object('outcome', 'EVADED', 'stood_off', false, 'slipped', true, 'broke_off', false, 'first', v_first, 'rounds_fought', 0, 'rounds', '[]'::jsonb,
                              'hull_lost', jsonb_build_object('a', '{}'::jsonb, 'b', '{}'::jsonb),
                              'hull', jsonb_build_object('a', v_h0a, 'b', v_h0b, 'a_start', v_h0a, 'b_start', v_h0b), 'hits', jsonb_build_object('a', 0, 'b', 0));
  end if;

  -- THE ROUNDS
  for g in 1 .. jsonb_array_length(v_ranges) loop
    v_fought := g;
    v_range := v_ranges -> (g - 1) ->> 0;
    v_mult  := (v_ranges -> (g - 1) ->> 1)::numeric;
    select * into v_va from public.fight_volley(p_seed, p_round, g, 'you', v_range, v_mult, g = 1 and v_first = 'B', v_k,
                                                a_att, a_acc, a_reach, a_hull, a_shots, v_bb, b_arm, b_hull, b_maxd);
    select * into v_vb from public.fight_volley(p_seed, p_round, g, 'they', v_range, v_mult, g = 1 and v_first = 'A', v_k,
                                                b_att, b_acc, b_reach, b_hull, b_shots, v_ba, a_arm, a_hull, a_maxd);
    -- both broadsides land together
    v_sta := '[]'::jsonb;
    v_la := 0;
    for i in 1 .. v_na loop
      if v_vb.taken[i] > 0 then
        v_pct := greatest(1, round(least(v_vb.taken[i], a_hull[i]) / a_maxd[i] * 100));
        v_sta := v_sta || jsonb_build_array(jsonb_build_array(i, v_pct));
        a_hull[i] := greatest(0, a_hull[i] - v_vb.taken[i]);
      end if;
      v_la := v_la + a_hull[i];
    end loop;
    v_stb := '[]'::jsonb;
    v_lb := 0;
    for i in 1 .. v_nb loop
      if v_va.taken[i] > 0 then
        v_pct := greatest(1, round(least(v_va.taken[i], b_hull[i]) / b_maxd[i] * 100));
        v_stb := v_stb || jsonb_build_array(jsonb_build_array(i, v_pct));
        b_hull[i] := greatest(0, b_hull[i] - v_va.taken[i]);
      end if;
      v_lb := v_lb + b_hull[i];
    end loop;
    v_tot_a := v_tot_a + v_va.hits;
    v_tot_b := v_tot_b + v_vb.hits;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('round', g, 'range', v_range,
      'a', jsonb_build_object('can', v_va.can, 'fired', v_va.fired, 'hits', v_va.hits, 'raw', v_va.raw, 'dealt', v_va.dealt, 'struck', v_sta, 'left', v_la),
      'b', jsonb_build_object('can', v_vb.can, 'fired', v_vb.fired, 'hits', v_vb.hits, 'raw', v_vb.raw, 'dealt', v_vb.dealt, 'struck', v_stb, 'left', v_lb)));

    if v_h0b - v_lb >= v_break * v_h0b then
      v_outcome := case when v_h0a - v_la = 0 then 'EVADED' else 'DRIVEN_OFF' end;
      v_broke := true;
      exit;
    end if;
  end loop;

  -- THE BOARDING
  if v_outcome is null then
    for i in 1 .. v_na loop
      c_you := c_you + a_crew[i];
      p_you := p_you + (a_crew[i] * v_hand * (1 + a_bpct[i]) + a_tier[i] * 3)
                       * case when a_hull0[i] > 0 then a_hull[i] / a_hull0[i] else 0 end;
    end loop;
    -- b's share of hull left is taken after the product, a's before: as written since 0189, and numeric division rounds
    for i in 1 .. v_nb loop
      continue when b_hull0[i] <= 0;
      c_they := c_they + b_crew[i] * b_hull[i] / b_hull0[i];
      p_they := p_they + (b_crew[i] * v_hand * (1 + b_bpct[i]) + b_tier[i] * 3) * b_hull[i] / b_hull0[i];
    end loop;
    v_ratio := case when p_they <= 0 then 99 else p_you / p_they end;
    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'
                      when v_ratio >= (v_bands->>1)::numeric then 'RANSOM'
                      else 'PLUNDERED' end;
    v_board := jsonb_build_object('a_power', p_you, 'b_power', p_they, 'ratio', v_ratio, 'surrender', v_ratio < (v_bands->>2)::numeric,
                                  'a_crew', c_you, 'b_crew', c_they);
  end if;

  return jsonb_build_object(
    'outcome', v_outcome, 'stood_off', false, 'slipped', false, 'broke_off', v_broke, 'first', v_first, 'rounds_fought', v_fought, 'rounds', v_rows, 'board', v_board,
    'hull_lost', jsonb_build_object(
      'a', coalesce((select jsonb_object_agg(a_id[k]::text, round(a_hull0[k] - a_hull[k], 2)) from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k]), '{}'::jsonb),
      'b', coalesce((select jsonb_object_agg(b_id[k]::text, round(b_hull0[k] - b_hull[k], 2)) from generate_subscripts(b_id, 1) k where b_hull0[k] > b_hull[k]), '{}'::jsonb)),
    'hull', jsonb_build_object('a', v_la, 'b', v_lb, 'a_start', v_h0a, 'b_start', v_h0b),
    'hits', jsonb_build_object('a', v_tot_a, 'b', v_tot_b));
end $body$;
$f$;
  comment on function public.fight_sides(uuid, int, jsonb, jsonb, jsonb) is
    '0320: THE FIGHT, the one combat authority: hulls on both sides, numbers only, hull_lost for both by ship id; deterministic per (seed, round). Names no table. Read by voyage.fight_resolve, the skin of a raid. Server-only.';
  revoke all on function public.fight_sides(uuid, int, jsonb, jsonb, jsonb) from public, anon, authenticated;

  -- ── 3. THE BUILDER ──
  execute $f$
create function voyage.raider_hulls(p_raider numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0320: THE RAIDERS OF A HAZARD, as a side for public.fight_sides: the hazard's strength (DESIGN B.6's piracy × 40 × (0.5 + magnitude)) in hulls of fight_raider_class. The one reader of that knob and of
-- ship_classes in a fight. ONE hull, the squadron: the strength is fractional and its hull one pool, so every figure is scaled by the strength and `shots` is the whole hulls rounded up. `ships` and `class`
-- are for the report. The id is no ship's: a raid's squadron is no row. Read by voyage.fight_resolve. Refused with no class: raiders with no class have no figures; that is a broken knob, not a calm sea.
declare
  c      public.ship_classes%rowtype;
  v_one  numeric;
  r_n    numeric;
begin
  select * into c from public.ship_classes where code = public.wc_text('fight_raider_class');
  if c.id is null then
    raise exception 'E_NO_RAIDER_CLASS: fight_raider_class names no ship class' using errcode = 'P0001';
  end if;
  v_one := c.attack / 10.0 + c.crew_required * 0.02 + c.tier * 3;
  r_n   := greatest(0, coalesce(p_raider, 0)) / v_one;
  return jsonb_build_array(jsonb_build_object(
    'id', '00000000-0320-4000-8000-00000000000b', 'name', c.name, 'class', c.code, 'ships', r_n, 'shots', greatest(1, ceil(r_n))::int,
    'tier', r_n * c.tier, 'hull', r_n * c.durability, 'maxd', r_n * c.durability, 'crew', r_n * c.crew_required, 'attack', r_n * c.attack,
    'accuracy', c.accuracy, 'reach', c.reach, 'armour', c.armour, 'sighting', c.sighting));
end $body$;
$f$;
  comment on function voyage.raider_hulls(numeric) is
    '0320: the raiders of a hazard as one squadron hull for public.fight_sides; the one reader of fight_raider_class. Read by voyage.fight_resolve. Server-only.';
  revoke all on function voyage.raider_hulls(numeric) from public, anon, authenticated;

  -- ── 4. THE SKIN ──
  execute $f$
create or replace function voyage.fight_resolve(p_voyage uuid, p_day int, p_raider numeric, p_escort numeric, p_ships jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0189 / 0320: A RAID, in words. The fight itself is public.fight_sides; this is its skin for the hazard: the raiders from voyage.raider_hulls (p_raider, DESIGN B.6's piracy × 40 × (0.5 + magnitude)), p_ships
-- (voyage.fight builds it from the live fleet; a simulation may pass its own), p_escort the sizing-up (voyage.escort_score). A pure function of its arguments, the fight_* knobs, armour_turns_pct and the world
-- secret, so the same day fought twice is the same fight, word for word. What an outcome costs in crew and cargo stays DESIGN B.6's, in voyage.settle.
-- Returns {outcome, sentence (the day's one line, in DESIGN B.6's voice, true of THIS fight), rounds[] (the battle report, in words), hull_lost {ship id: points}, raiders{...}, first, hits{yours, theirs}}.
declare
  v_side  jsonb := voyage.raider_hulls(p_raider);
  v_r     jsonb := v_side -> 0;
  v_f     jsonb := public.fight_sides(p_voyage, p_day, p_ships, v_side, jsonb_build_object('a_score', p_escort, 'b_score', p_raider));
  v_name  text := v_r->>'name';
  r_n     numeric := (v_r->>'ships')::numeric;
  r_crew  numeric := (v_r->>'crew')::numeric;
  r_hull0 numeric := (v_r->>'hull')::numeric;
  v_first text := case v_f->>'first' when 'A' then 'YOU' when 'B' then 'THEY' else 'BOTH' end;
  v_lines text[] := '{}';
  v_outcome text := v_f->>'outcome';
  v_sentence text;
  v_txt   text;
  x       jsonb;
  v_a     jsonb;
  v_b     jsonb;
  h       jsonb;
  g       int;
  v_you   text;
  v_they  text;
  v_hit_on text;
  v_can   int;
  v_fired int;
  v_hits  int;
  v_board jsonb := v_f->'board';
  v_surrender boolean;
begin
  -- SIZING UP: no raiders, or a fleet too strong for them, and they never close
  if (v_f->>'stood_off')::boolean then
    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'They stood off and did not close.',
                              'rounds', to_jsonb(array[case when r_n <= 0 then 'The sail stood off and never closed.'
                                                            else format('Raiders: about %s × %s, %s crew. They looked you over and stood off.',
                                                                        greatest(1, round(r_n)), v_name, round(r_crew)) end]),
                              'hull_lost', '{}'::jsonb, 'first', 'BOTH', 'rounds_fought', 0,
                              'raiders', jsonb_build_object('class', v_r->>'class', 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0),
                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  end if;

  v_lines := v_lines || case when r_n < 0.75
                               then format('Raiders: one small %s, %s crew.', v_name, round(r_crew))
                               else format('Raiders: about %s × %s, %s crew.', round(r_n), v_name, round(r_crew)) end;
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
  if (v_f->>'slipped')::boolean then
    v_lines := v_lines || 'Your lookout saw them first, and you slipped away before they could close.'::text;
    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'We saw them first and slipped away.',
                              'rounds', to_jsonb(v_lines), 'hull_lost', '{}'::jsonb,
                              'first', v_first, 'rounds_fought', 0,
                              'raiders', jsonb_build_object('class', v_r->>'class', 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0),
                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  elsif v_first = 'YOU' then
    v_lines := v_lines || 'Your lookout saw them first.'::text;
  elsif v_first = 'THEY' then
    v_lines := v_lines || 'They saw you before your lookout saw them.'::text;
  else
    v_lines := v_lines || 'Both sides saw each other at the same moment.'::text;
  end if;

  -- THE ROUNDS
  for g in 1 .. (v_f->>'rounds_fought')::int loop
    x := v_f->'rounds'->(g - 1);
    v_a := x->'a';
    v_b := x->'b';
    v_can := (v_a->>'can')::int; v_fired := (v_a->>'fired')::int; v_hits := (v_a->>'hits')::int;
    v_hit_on := null;
    for h in select q.e from jsonb_array_elements(v_a->'struck') q(e) loop
      v_hit_on := coalesce(v_hit_on || ', ', '')
                  || format('%s for %s%% damage', coalesce(p_ships->((h->>0)::int - 1)->>'name', 'Your ship'), h->>1);
    end loop;
    v_you := case when g = 1 and v_first = 'THEY' then 'you are caught unready'
                  when v_can = 0 then 'you have no guns to answer with'
                  when v_fired = 0 then 'your guns cannot reach them'
                  when v_hits = 0 then format('you miss with %s shot%s', v_fired, case when v_fired = 1 then '' else 's' end)
                  else format('you hit with %s of %s shot%s', v_hits, v_fired, case when v_fired = 1 then '' else 's' end) end;
    v_they := case when g = 1 and v_first = 'YOU' then 'they are caught unready'
                   when (v_b->>'fired')::int = 0 then 'their guns cannot reach you'
                   when (v_b->>'hits')::int = 0 then 'they miss'
                   else format('they hit %s', v_hit_on)
                        || case when (v_b->>'raw')::numeric > (v_b->>'dealt')::numeric + 0.005
                                then format(' (armour turned %s%%)', round((1 - (v_b->>'dealt')::numeric / (v_b->>'raw')::numeric) * 100)) else '' end end;
    v_lines := v_lines || (format('Round %s · %s range — %s; %s.', g, lower(x->>'range'), v_you, v_they)
                           || case when v_hits > 0 then format(' The raiders are %s%% damaged.', round((1 - (v_b->>'left')::numeric / r_hull0) * 100)) else '' end);
  end loop;

  -- HOW IT ENDED
  if (v_f->>'broke_off')::boolean then
    v_lines := v_lines || 'They break off and run.'::text;
    v_sentence := 'They broke off and ran.';
  else
    v_surrender := (v_board->>'surrender')::boolean;
    select string_agg(format('%s leads the crew on %s (+%s%%).', e->>'boarder', e->>'name',
                             round((e->>'boarder_pct')::numeric * 100)), ' ' order by o)
      into v_txt
      from jsonb_array_elements(p_ships) with ordinality q(e, o)
     where coalesce(e->>'boarder', '') <> '' and coalesce((e->>'boarder_pct')::numeric, 0) > 0;
    v_lines := v_lines || (format('Close quarters: they come alongside — your %s crew against their %s.', round((v_board->>'a_crew')::numeric),
                                  round((v_board->>'b_crew')::numeric))
                           || coalesce(' ' || v_txt, '')
                           || case when v_surrender then ' You surrender; they board and take what they can carry.'
                                   else case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                                       when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                                       else ' They board and take what they can carry.' end end);
    v_sentence := case when v_surrender then 'We surrendered, and they took what they could carry.'
                       else case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                           when 'RANSOM'     then 'They came alongside and we paid them off.'
                                           else 'They came aboard and took what they could carry.' end end;
  end if;

  return jsonb_build_object(
    'outcome', v_outcome,
    'sentence', v_sentence,
    'rounds', to_jsonb(v_lines),
    'hull_lost', v_f->'hull_lost'->'a',
    'first', v_first,
    'rounds_fought', (v_f->>'rounds_fought')::int,
    'raiders', jsonb_build_object('class', v_r->>'class', 'ships', round(r_n, 2), 'crew', round(r_crew),
                                  'damaged_pct', round((1 - (v_f->'hull'->>'b')::numeric / r_hull0) * 100)),
    'hits', jsonb_build_object('yours', (v_f->'hits'->>'a')::int, 'theirs', (v_f->'hits'->>'b')::int));
end $body$;
$f$;
  comment on function voyage.fight_resolve(uuid, int, numeric, numeric, jsonb) is
    '0189 / 0202 / 0320: a raid, in words: the skin of public.fight_sides over voyage.raider_hulls; deterministic per (voyage, day). Returns {outcome, sentence, rounds[], hull_lost, raiders, first, hits}. Read by voyage.fight. Server-only.';

  -- ── 5. PARITY: the old body and the skin, as text, on crafted hulls (0202's probe, plus a convoy with a Gunner, a Boarder, gear, a hurt hull and a wreck) ──
  for v_x in
    select s.ships, s.esc, r.r, d
      from (values (v_carlat, 11.74::numeric), (v_barca, 6.66::numeric)) s(ships, esc)
     cross join (values (6.0), (12.0), (18.0), (24.0)) r(r)
     cross join generate_series(1, 120) d
    union all
    select v_three, 30.5::numeric, r.r, d
      from (values (10.0), (24.0), (60.0), (120.0)) r(r)
     cross join generate_series(1, 30) d
  loop
    v_old := pg_temp.fight_resolve_old_0320(c_seed, v_x.d, v_x.r, v_x.esc, v_x.ships);
    v_new := voyage.fight_resolve(c_seed, v_x.d, v_x.r, v_x.esc, v_x.ships);
    v_n := v_n + 1;
    v_kinds := jsonb_set(v_kinds, array[v_old ->> 'outcome'], to_jsonb(coalesce((v_kinds ->> (v_old ->> 'outcome'))::int, 0) + 1));
    if v_old::text is distinct from v_new::text then
      v_bad := v_bad + 1;
      v_ex := coalesce(v_ex, jsonb_build_object('old', v_old, 'new', v_new));
    end if;
  end loop;
  if v_n <> 1080 then
    raise exception '0320 self-assert FAIL: the probe fought % fights, not 1080', v_n;
  end if;
  if v_bad > 0 then
    raise exception '0320 self-assert FAIL: % fight(s) changed: %', v_bad, v_ex;
  end if;
  if not (v_kinds ?& array['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED']) then
    raise exception '0320 self-assert FAIL: the probe met too few endings to prove anything: %', v_kinds;
  end if;
  -- the two doors with no fight in them
  if pg_temp.fight_resolve_old_0320(c_seed, 7, 0, 5, v_carlat)::text is distinct from voyage.fight_resolve(c_seed, 7, 0, 5, v_carlat)::text
     or pg_temp.fight_resolve_old_0320(c_seed, 7, null, null, v_carlat)::text is distinct from voyage.fight_resolve(c_seed, 7, null, null, v_carlat)::text then
    raise exception '0320 self-assert FAIL: an empty sea changed';
  end if;

  -- ── 6. TWO SIDES: real hulls on both, hull lost on both, by ship id ──
  for v_x in select d from generate_series(1, 40) d loop
    v_f := public.fight_sides(c_seed, v_x.d, v_three, v_two, '{}'::jsonb);
    if v_f is distinct from public.fight_sides(c_seed, v_x.d, v_three, v_two, '{}'::jsonb) then
      raise exception '0320 self-assert FAIL: the same fight fought twice differs';
    end if;
    if v_f -> 'hull_lost' -> 'a' <> '{}'::jsonb then
      v_seen_a := v_seen_a + 1;
    end if;
    if v_f -> 'hull_lost' -> 'b' <> '{}'::jsonb then
      v_seen_b := v_seen_b + 1;
    end if;
    if v_f -> 'hull_lost' -> 'b' ? '00000000-0320-4000-8000-0000000000b1' then
      v_seen1 := v_seen1 + 1;
    end if;
    if v_f -> 'hull_lost' -> 'b' ? '00000000-0320-4000-8000-0000000000b2' then
      v_seen2 := v_seen2 + 1;
    end if;
    if abs((select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(v_f -> 'hull_lost' -> 'b') h) - ((v_f -> 'hull' ->> 'b_start')::numeric - (v_f -> 'hull' ->> 'b')::numeric)) > 0.05 then
      raise exception '0320 self-assert FAIL: hull_lost does not add up to the hull lost: %', v_f;
    end if;
  end loop;
  if v_seen_a = 0 or v_seen_b = 0 or v_seen1 = 0 or v_seen2 = 0 then
    raise exception '0320 self-assert FAIL: both sides must lose hull, by ship id: a % days, b % days, hull 1 %, hull 2 %', v_seen_a, v_seen_b, v_seen1, v_seen2;
  end if;

  -- ── 7. THE GUARDS ──
  for v_x in select unnest(array['public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)'::regprocedure, c_new[2]::regprocedure]) f loop
    select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src from pg_proc p where p.oid = v_x.f;
    if v_src ~* '\m(join|update|insert|delete|execute)\M' or v_src ~* '\mfrom\s+(?!generate_subscripts\(|public\.fight_volley\()' then
      raise exception '0320 self-assert FAIL: % names a table', v_x.f;
    end if;
    if exists (select 1 from regexp_matches(v_src, '\m((public|voyage|world|cmd)\.[a-z_]+)', 'g') w(a)
                where w.a[1] not in ('public.wc', 'public.wc_num', 'public.fight_volley', 'public.armour_soak', 'voyage.rng')) then
      raise exception '0320 self-assert FAIL: % reads through something that is not world_config', v_x.f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%wc_text(''fight_raider_class'')%'
                and p.oid <> 'voyage.raider_hulls(numeric)'::regprocedure) then
    raise exception '0320 self-assert FAIL: raiders are built in a second place';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = c_fr::regprocedure) ~ 'ship_classes|fight:|voyage\.rng' then
    raise exception '0320 self-assert FAIL: the skin still fights';
  end if;
  if exists (select 1 from unnest(c_new) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')
                 or (select p.provolatile from pg_proc p where p.oid = f::regprocedure) <> 's') then
    raise exception '0320 self-assert FAIL: a new function is open to clients, or not stable';
  end if;
  if (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || pg_get_userbyid(p.proowner)
        from pg_proc p where p.oid = c_fr::regprocedure) <> v_meta_before then
    raise exception '0320 self-assert FAIL: the skin''s grants or settings moved';
  end if;
  execute 'drop function pg_temp.fight_resolve_old_0320(uuid, integer, numeric, numeric, jsonb)';
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fr::regprocedure
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_new) f))) <> v_fn_before then
    raise exception '0320 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key like 'fight%' or c.key in ('armour_turns_pct', 'combat_bite', 'world_secret')) <> v_cfg_before then
    raise exception '0320 self-assert FAIL: a knob moved';
  end if;

  if extract(epoch from clock_timestamp() - v_t0) > 40 then
    raise exception '0320 self-assert FAIL: the file took more than 40 s';
  end if;
  raise notice '0320 self-assert ok: % fights word for word through the skin (%), both sides lost hull (a % of 40 days, b % of 40, by ship id), the engine names no table, nothing else moved (% ms)',
    v_n, v_kinds, v_seen_a, v_seen_b, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
