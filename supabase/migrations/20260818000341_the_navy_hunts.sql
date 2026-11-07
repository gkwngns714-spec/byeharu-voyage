-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0341 — THE NAVY HUNTS: a navy ship sails for the most dangerous sea in reach, and a navy ship and a pirate ship in one sea fight, once an hour, nobody watching. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner rows 284, 285 (2026-11-05): *"npcs that attack these ships as well as merchants"*; *"each country will also have battle ships. they defend or attack pirates"*; 2026-11-07: *"do it fast"*.
-- Slice W19 of docs/WORLD_POWERS.md (6.4 Hunt, "Navy against pirate"; 7.7 row W19: "Hunt mission, navy against pirate, regard hooks"; proof: "at most once an hour; fight written on both hulls; arrivals bound").
-- Step 4 of 4 of the pirate plan: W16 (0338, the Brethren), W17 (0339, pirate ships), W18 (pirate merchants). It builds on W17's CONTRACT (docs/dev-log/2026-11-07-pirate-ships-sail.md) and nothing else of W17.
--
-- BEHIND BOTH SWITCHES: navy_enabled (public.navy_on, 0331) AND pirates_bite (public.pirates_on, W17), read together through public.navy_hunts_on(), THE one reader of "the hunt is lit". Both are false. Dark, the sea and
-- the navy job read BYTE-IDENTICAL to before this file: public.tick_navy answers the same keys (the `fights` key is served only when the hunt ran), world.navy_ship_card the same keys (`fought` only after a fight), a navy
-- ship's step reaches the hunt only on duty with the pirates lit, a battle's hulls are written by the same statement, lifted. Parity is proved, not argued: scripts/ops/harness/the-navy-hunts/dark-scene.sql beside the navy and
-- navy-comes scenes, before and after this file, every line equal.
--
-- THE HUNT (6.4: "Hunt | Lit with pirates | Sails to the sea with the highest sea_danger in reach"). public.navy_hunt_step, from public.navy_ship_step, after the escort's step and before she goes home:
--   At her station, on duty, lit: public.navy_hunt_targets reads every sea within navy_reach_nm sailed of the station (her own too), each at voyage.sea_danger NOW (0330; W17's pirate ships press on it), the most dangerous first.
--   If that is her own sea she lies at her station (HUNTING) for navy_hunt_hours; else she sails for the nearest open harbour of it that a course reaches, a real voyage through public.navy_sail (hands, free stores, voyage.depart),
--   mission HUNT, and lies there navy_hunt_hours from her arrival; then she sails home, and at her station picks again. Nothing is in reach, or nothing lit: she patrols as before (mission PATROL). She is never turned at sea (W13's rule).
--   ARRIVALS BOUND: a patrol is navy_patrol_stops + 1 legs (4) in about 45 minutes; a hunt is 2 legs and a lie of navy_hunt_hours (6 h) or 0 legs and a lie. So a hunting ship makes FEWER arrivals than a patrolling one; the
--   design's estimate for 75 ships (about 7 arrivals a minute, 6.5) stands as the bound. Proof 48 measures a hunter's legs against her patrol's.
--
-- NAVY AGAINST PIRATE (6.4): public.navy_hunt_pass, from public.tick_navy, every minute, before the ships' steps, at most navy_hunts_per_run fights a run, null while dark. For each navy ship at work and on duty, in no battle,
--   with a hull left and no fight within the hour: her sea now (public.fleet_sea: her port's sea in port; at sea the sea of her voyage's current segment, voyage.position's closed form; at anchor the sea of her point), then
--   THE one reader of who is there, public.pirate_ship_in_sea(sea) (W17's). Null: no fight. Found, whole, in no battle, no fight of hers within the hour: public.navy_fight, both settled first (D.2), both rows taken SKIP LOCKED.
--   THE FIGHT IS ONE CALL, no timer, nobody watching: public.fight_sides(p_seed := her fleet, p_round := the UTC hour, p_a := public.pirate_side(pirate), p_b := voyage.fleet_hulls(navy ship), '{}'), as the contract says:
--   the same hour fought twice is the same fight. Hull loss lands on BOTH through public.fight_hulls_write, THE hull writer, lifted from public.battle_resolve (the statement 0323 wrote and 0327 / 0333 close battles with).
--   THE HOUR: navy_ships.fought_at (new, this file's) and pirate_ships.fought_at (W17's column, W19's to write) are both stamped; a ship with either stamp inside the hour is passed over. One row each, no table of fights.
--   AFTER THE HULLS, the lines a battle's close uses and no new path: a ship in port whose flagship is at 0 is UNABLE_TO_SAIL (0323's line); every hull at 0 at sea under 0322's rule is voyage.npc_wreck (0333's lines):
--   a pirate ship respawns at her home, UNABLE_TO_SAIL, and public.npc_refit_step pays her REFIT from her home's purse (public.fleet_origin, W17's hunk); a navy ship at her station's cost. A wreck in port is found by her step.
--   REPORTED: one public event, public.emit_event(null, 'NAVY_FIGHT', {navy, pirate, sea, at, result, outcome, hull_lost, sunk}): the world's own line (DESIGN J.3's world feed; player null, as ECONOMY_SWITCH is), and her
--   last fight on her card: navy_ships.fought {at, result, foe, sea}, served as `fought` by world.navy_ship_card only after one. result: WON (she boarded or was paid off), LOST (thrown back, or she broke off), DREW (stood off,
--   slipped, nobody touched), SUNK (every pirate hull at 0). NO GOLD MOVES in a fight: no purse, no book, no ledger row. W (players + merchants + purses + set aside + funds aboard) is unchanged, proved.
--
-- THE REGARD HOOK (2.1, the pirate row that is a fight's: "Drive off a pirate ship | +30, every great power | regard_pirate"): in public.attack_close, a company whose attack beat a pirate ship (boarded, paid off, or every
--   hull at 0) earns regard_pirate with EVERY great power but the pirates, reason DROVE_OFF_PIRATE, once a battle, through public.regard_add (dark with regard_enabled: writes nothing). Beaten by her: nothing. Sinking her
--   costs nothing with the pirates: public.crown_nation answers null for her, so 0333's sink line writes nothing. The trade row (-5 at a pirate port) is the pirate port's limit, W18's table (7.6). A navy's fight moves no regard.
--
-- THE RE-CUTS (hunks of the live bodies, read on the world at head 0338 + W17; each occurs once and reverses to its pre-image; these supersede the same lines of 0323, 0327, 0331, 0333 and 0334):
--   public.tick_navy (3):          v_fights; the hunt pass before the steps, lit only; the answer gains `fights` only when the pass ran.
--   public.navy_ship_step (2):     v_hunt; the hunt's step after her home is read, answering null for every other ship.
--   public.battle_resolve (1):     the hull statement lifted into public.fight_hulls_write. Same statement.
--   public.attack_close (1):       the regard hook, before 0334's mark.
--   world.navy_ship_card (1):      `fought`, after a fight only.
-- NEW: navy_ships.fought_at, fought, hunt_port, hunt_until. Knobs navy_hunt_hours 6, navy_hunts_per_run 5, regard_pirate 30. Functions navy_hunts_on, fleet_sea, navy_hunt_targets, navy_hunt_step, fight_hulls_write,
--   navy_fight, navy_hunt_pass. No new job, no new entry point, no new word of money. Nothing minted.
--
-- SELF-ASSERT: the catalog, stable reads and arithmetic only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob or job; both switches off; no row written; the targets of one station in order.
-- THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 48, scripts/db/proofs/48_the_navy_hunts.sql. Mutation controls: scripts/ops/harness/the-navy-hunts/proof-0341.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, owner only): pirates_bite false: no hunt and no fight; a ship out on a hunt sails home at her next port and patrols. navy_enabled false: 0331's rollback. To remove: a NEW migration swapping old and new of each hunk.
-- VERSION: 0341 (provisional: W18 is 0340 and may swap with this one; the number is in this name, the dev-log, the harness and proof 48) - follows 0338 (W16) and 0339 (W17, whose contract this builds on).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fid  uuid;
  v_sea  uuid;
  v_port uuid;
  v_fn_before    text;
  v_cfg_before   text;
  v_meta_before  text;
  v_cron_before  text;
  v_cron_after   text;
  c_keys constant text[] := array['navy_hunt_hours', 'navy_hunts_per_run', 'regard_pirate'];
  c_new_fns constant text[] := array[
    'public.navy_hunts_on()', 'public.fleet_sea(uuid,timestamp with time zone)', 'public.navy_hunt_targets(uuid,timestamp with time zone)',
    'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)', 'public.fight_hulls_write(jsonb)', 'public.navy_fight(uuid,uuid,timestamp with time zone)',
    'public.navy_hunt_pass(timestamp with time zone,uuid)'];
  c_hunked constant text[] := array[
    'public.tick_navy(timestamp with time zone,uuid)', 'public.navy_ship_step(uuid,timestamp with time zone)', 'public.battle_resolve(uuid,timestamp with time zone)',
    'public.attack_close(uuid,jsonb,timestamp with time zone)', 'world.navy_ship_card(uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.navy_hunt_pass(timestamp with time zone,uuid)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from pg_attribute a where a.attrelid = 'public.navy_ships'::regclass and a.attname in ('fought_at', 'fought', 'hunt_port', 'hunt_until') and not a.attisdropped) then
    raise exception '0341 refuses: something of it is already in this world';
  end if;
  if to_regclass('public.navy_ships') is null or to_regprocedure('public.navy_on_duty(uuid,integer,timestamp with time zone)') is null or to_regprocedure('public.navy_escort_step(uuid,uuid,boolean,timestamp with time zone)') is null then
    raise exception '0341 refuses: 0331 / 0333 (the navy, its duty and its escort) are not in this world';
  end if;
  if to_regprocedure('public.pirate_power(uuid)') is null then
    raise exception '0341 refuses: 0338 (the pirates, the 11th power) is not in this world';
  end if;
  if to_regclass('public.pirate_ships') is null or to_regprocedure('public.pirates_on()') is null or to_regprocedure('public.pirate_ship_in_sea(uuid)') is null
     or to_regprocedure('public.pirate_side(uuid)') is null
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.pirate_ships'::regclass and a.attname = 'fought_at' and not a.attisdropped) then
    raise exception '0341 refuses: W17 (the pirate ships, their switch, public.pirate_ship_in_sea, public.pirate_side, pirate_ships.fought_at) is not in this world';
  end if;
  if to_regprocedure('voyage.sea_danger(uuid,timestamp with time zone)') is null or to_regprocedure('voyage.fleet_hulls(uuid)') is null or to_regprocedure('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)') is null then
    raise exception '0341 refuses: 0320 / 0323 / 0330 (the fight, a fleet as a side, the danger) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE KNOBS AND THE COLUMNS (all new; no existing key is touched) ──
  insert into public.world_config (key, value, description) values
    ('navy_hunt_hours', to_jsonb(6), '0341: how long a navy ship on the hunt lies at the harbour of the sea she hunts (or at her station, watching her own sea) before she sails home and picks again (public.navy_hunt_step).'),
    ('navy_hunts_per_run', to_jsonb(5), '0341: the most navy-against-pirate fights one run of public.tick_navy resolves (public.navy_hunt_pass). The rest wait a minute. Each fight is at most once an hour a ship, which is no knob.'),
    ('regard_pirate', to_jsonb(30), '0341 (docs/WORLD_POWERS.md 2.1): regard with EVERY great power but the pirates for beating a pirate ship in an attack (public.attack_close, reason DROVE_OFF_PIRATE).');

  alter table public.navy_ships
    add column fought_at  timestamptz,
    add column fought     jsonb,
    add column hunt_port  uuid references public.ports(id),
    add column hunt_until timestamptz;
  comment on column public.navy_ships.fought_at is '0341: her last fight with a pirate ship (public.navy_fight). THE hour: a ship with a stamp inside the hour fights no pirate until it is past.';
  comment on column public.navy_ships.fought is '0341: her last fight, for her card: {at, result (WON | LOST | DREW | SUNK), foe (the pirate ship''s name), sea (code)}. Null until one. The world''s record of each fight is the NAVY_FIGHT event.';
  comment on column public.navy_ships.hunt_port is '0341: the harbour of her hunt while mission is HUNT: where she is bound, or lies (her station when her own sea is the most dangerous in reach).';
  comment on column public.navy_ships.hunt_until is '0341: when her lie at hunt_port ends (her arrival + navy_hunt_hours). Null while she sails there, and when she is not hunting.';

  -- ── 2. THE NEW FUNCTIONS ──
  execute $f$
create function public.navy_hunts_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0341: THE one reader of "the hunt is lit" (docs/WORLD_POWERS.md 6.4: Hunt, lit with pirates): the navy's own switch AND the pirates'. Either off: no hunt is sailed and no fight is fought.
  select public.navy_on() and public.pirates_on()
$$
  $f$;

  execute $f$
create function public.fleet_sea(p_fleet uuid, p_now timestamptz default now())
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0341: THE sea a fleet is in now (W17's contract: her port's sea in port; at sea, the sea of her voyage's current segment, voyage.position's closed-form place; at anchor, the sea of her point). voyage.where_now says
-- where she is, so a passage whose true arrival has come reads as her harbour. Null for a fleet that is nowhere, or a leg frozen before 0047 (no sea on it). A pure read: nothing is settled or written.
declare
  w   record;
  f   public.fleets%rowtype;
  v   public.voyages%rowtype;
  v_i int;
begin
  select * into w from voyage.where_now(p_fleet, p_now);
  if w.status is null then
    return null;
  end if;
  if w.voyage_id is not null then
    select * into v from public.voyages x where x.id = w.voyage_id;
    select p.seg_index into v_i from voyage.position(v.id, p_now) p;
    return (v.path -> coalesce(v_i, 0) ->> 'sea_id')::uuid;
  end if;
  if w.port_id is not null then
    return (select p.sea_id from public.ports p where p.id = w.port_id);
  end if;
  select * into f from public.fleets x where x.id = p_fleet;
  if f.lat is not null and f.lon is not null then
    return voyage.sea_near(f.lat::double precision, f.lon::double precision);
  end if;
  return null;
end
$$
  $f$;

  execute $f$
create function public.navy_hunt_targets(p_station uuid, p_now timestamptz)
returns table (sea_id uuid, danger numeric, port_id uuid, nm numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0341: THE seas a hunt from this station may sail for, the most dangerous first (docs/WORLD_POWERS.md 6.4: "the sea with the highest sea_danger in reach"): the station's own sea and the sea of every open harbour within
  -- navy_reach_nm sailed of it (voyage.reach_from, the figure every quote reads), each at voyage.sea_danger at p_now, so a pirate ship's pressure (0330, W17) counts. One row a sea: its nearest harbour (the station itself for
  -- its own sea), ties by code. A prod check may ask it: read only.
  select y.sea_id, y.danger, y.port_id, y.nm
    from (select distinct on (x.sea_id) x.sea_id, x.danger, x.port_id, x.nm, x.code
            from (select p.sea_id, voyage.sea_danger(p.sea_id, p_now) as danger, r.port_id, r.nm, r.code
                    from voyage.reach_from(p_station) r
                    join public.ports p on p.id = r.port_id
                   where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> p_station and r.nm <= public.wc_num('navy_reach_nm')
                  union all
                  select p.sea_id, voyage.sea_danger(p.sea_id, p_now), p.id, 0::numeric, p.code
                    from public.ports p where p.id = p_station) x
           order by x.sea_id, x.nm, x.code) y
   order by y.danger desc, y.nm, y.code
$$
  $f$;

  execute $f$
create function public.navy_hunt_step(p_fleet uuid, p_port uuid, p_home uuid, p_duty boolean, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0341: THE HUNT, what a navy ship does about it in port (docs/WORLD_POWERS.md 6.4). Called by public.navy_ship_step after her home is read; the caller holds her fleet row. Answers HUNTING (she lies, watching), HUNT (she
-- sailed for the most dangerous sea in reach), or null: she is no hunter now, and her step goes on (home, patrol, laid up) as before this file.
--   Off duty or dark: a hunt is forgotten (mission PATROL), nothing else.
--   Lying at her hunt harbour: until hunt_until she stays; past it, away from home she sails home (the step's own path); at home she picks again.
--   At home, on duty, lit: the most dangerous sea in reach (public.navy_hunt_targets). Her own: she lies at her station navy_hunt_hours. Another: the nearest harbour of it a course reaches (the first three seas are tried),
--   a real voyage through public.navy_sail, mission HUNT, her lie set from her arrival. She is mended free at her station as she sets out, as a patrol's end mends her. No sea, no course: she patrols (mission PATROL).
--   Never turned at sea: this runs in port only, as every step of hers.
declare
  n       public.navy_ships%rowtype;
  t       record;
  v_leg   jsonb;
  v_hours numeric := public.wc_num('navy_hunt_hours');
  v_tries int := 0;
begin
  select * into n from public.navy_ships x where x.fleet_id = p_fleet;
  if not (p_duty and public.navy_hunts_on()) then
    if n.mission = 'HUNT' then
      update public.navy_ships x set mission = 'PATROL', hunt_port = null, hunt_until = null where x.fleet_id = p_fleet;
    end if;
    return null;
  end if;
  if n.mission = 'HUNT' and n.hunt_port = p_port then
    if n.hunt_until is not null and n.hunt_until > p_now then
      return 'HUNTING';
    end if;
    if p_port <> p_home then
      update public.navy_ships x set hunt_port = null, hunt_until = null where x.fleet_id = p_fleet;   -- her lie is over: the step sails her home, mission HUNT until she is there
      return null;
    end if;
  end if;
  if p_port <> p_home then
    return null;
  end if;
  for t in select * from public.navy_hunt_targets(p_home, p_now) loop
    v_tries := v_tries + 1;
    exit when v_tries > 3;
    if t.port_id = p_home then
      perform public.fleet_mend(p_fleet);
      update public.navy_ships x set mission = 'HUNT', hunt_port = p_home, hunt_until = p_now + make_interval(secs => (v_hours * 3600)::double precision) where x.fleet_id = p_fleet;
      return 'HUNTING';
    end if;
    v_leg := public.cargo_circuit_plan(n.nation_id, p_home, t.port_id) #> '{legs,0}';
    continue when v_leg is null;
    perform public.fleet_mend(p_fleet);
    perform public.navy_sail(p_fleet, p_home, voyage.segments_from_course(v_leg -> 'course'), t.port_id, null, 0, p_now);
    update public.navy_ships x
       set mission = 'HUNT', hunt_port = t.port_id,
           hunt_until = (select v.eta from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING') + make_interval(secs => (v_hours * 3600)::double precision)
     where x.fleet_id = p_fleet;
    return 'HUNT';
  end loop;
  if n.mission = 'HUNT' then
    update public.navy_ships x set mission = 'PATROL', hunt_port = null, hunt_until = null where x.fleet_id = p_fleet;
  end if;
  return null;
end
$$
  $f$;

  execute $f$
create function public.fight_hulls_write(p_fight jsonb)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  -- 0341: THE hull writer: what public.fight_sides answered lands on every hull of both sides, by ship id, never below 0. public.battle_resolve's own statement (0323), lifted, so a battle's close and the navy's fight with a pirate share one.
  update public.ships sh set durability = greatest(0, sh.durability - l.lost)
    from (select x.key::uuid as id, x.value::numeric as lost from jsonb_each_text(coalesce(p_fight->'hull_lost'->'a', '{}'::jsonb)) x
          union all
          select x.key::uuid, x.value::numeric from jsonb_each_text(coalesce(p_fight->'hull_lost'->'b', '{}'::jsonb)) x) l
   where sh.id = l.id
$$
  $f$;

  execute $f$
create function public.navy_fight(p_navy uuid, p_pirate uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0341: NAVY AGAINST PIRATE, one fight (docs/WORLD_POWERS.md 6.4; W17's contract): public.fight_sides seeded by her fleet and keyed by the UTC hour, the pirate ship the side set upon (public.pirate_side), the navy ship the
-- side that closes (voyage.fleet_hulls, as a player's fleet is built), no sizing up, no timer. Hull loss lands on both (public.fight_hulls_write). Both hour-stamps are written. Then the lines a battle's close uses: a flagship
-- at 0 in port cannot sail (0323); every hull at 0 at sea under 0322's rule is a wreck now (0333's lines): she respawns at her origin and her home pays the refit. A wreck in port is found by her step. One public event,
-- NAVY_FIGHT, the world's line; her card keeps the last. No gold moves. The caller holds both fleet rows and has settled both. Answers {result, outcome, event, hull_lost{navy, pirate}, sunk{navy, pirate}}.
declare
  v_round  int := floor(extract(epoch from p_now) / 3600)::int;
  v_a      jsonb := public.pirate_side(p_pirate);
  v_b      jsonb := voyage.fleet_hulls(p_navy);
  v_f      jsonb;
  v_res    text;
  v_sunk_p boolean;
  v_sunk_n boolean;
  v_x      uuid;
  v_voy    public.voyages%rowtype;
  v_sea    uuid := public.fleet_sea(p_navy, p_now);
  v_line   jsonb;
  v_ev     uuid;
  nf       public.fleets%rowtype;
  pf       public.fleets%rowtype;
  n        public.navy_ships%rowtype;
begin
  select * into nf from public.fleets x where x.id = p_navy;
  select * into pf from public.fleets x where x.id = p_pirate;
  select * into n from public.navy_ships x where x.fleet_id = p_navy;
  if n.fleet_id is null or pf.id is null or not exists (select 1 from public.pirate_ships x where x.fleet_id = p_pirate) then
    raise exception 'E_NOT_A_FIGHT: % is no navy ship or % is no pirate ship', p_navy, p_pirate using errcode = 'P0001';
  end if;
  if coalesce(jsonb_array_length(v_a), 0) = 0 or coalesce(jsonb_array_length(v_b), 0) = 0 then
    raise exception 'E_NO_SHIPS: a fight needs at least one hull on each side' using errcode = 'P0001';
  end if;
  v_f := public.fight_sides(p_navy, v_round, v_a, v_b, '{}'::jsonb);
  perform public.fight_hulls_write(v_f);
  v_sunk_p := not exists (select 1 from public.ships s where s.fleet_id = p_pirate and s.durability > 0);
  v_sunk_n := not exists (select 1 from public.ships s where s.fleet_id = p_navy and s.durability > 0);
  v_res := case when v_sunk_p then 'SUNK'
                when v_f ->> 'outcome' in ('PLUNDERED', 'RANSOM') then 'WON'
                when v_f ->> 'outcome' = 'DRIVEN_OFF' then 'LOST'
                else 'DREW' end;
  v_line := jsonb_build_object('at', p_now, 'result', v_res, 'foe', pf.name, 'sea', (select s.code from public.seas s where s.id = v_sea));
  update public.navy_ships x set fought_at = p_now, fought = v_line where x.fleet_id = p_navy;
  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;

  -- after the hulls: the same lines a battle's close uses (0323, 0333), on both. Every hull at 0 at sea is a wreck now, by 0322's rule; a flagship at 0 in port cannot sail; a wreck in port is found by her step.
  foreach v_x in array array[p_navy, p_pirate] loop
    if exists (select 1 from public.ships s where s.fleet_id = v_x)
       and not exists (select 1 from public.ships s where s.fleet_id = v_x and s.durability > 0)
       and public.npc_wrecked(v_x) then
      select * into v_voy from public.voyages v where v.fleet_id = v_x and v.status = 'SAILING';
      if v_voy.id is not null then
        perform voyage.npc_wreck(v_x, v_voy.id, v_voy.last_settled_day + 1);
      end if;
    end if;
    update public.fleets f
       set status = 'UNABLE_TO_SAIL', version = version + 1
     where f.id = v_x and f.status = 'DOCKED'
       and (select sh.durability from public.ships sh where sh.fleet_id = f.id and sh.is_flagship) <= 0;
  end loop;

  v_ev := public.emit_event(null, 'NAVY_FIGHT', jsonb_build_object(
    'navy', jsonb_build_object('fleet', p_navy, 'name', nf.name, 'nation', (select x.code from public.nations x where x.id = n.nation_id)),
    'pirate', jsonb_build_object('fleet', p_pirate, 'name', pf.name, 'home', (select p.code from public.pirate_ships x join public.ports p on p.id = x.home_port where x.fleet_id = p_pirate)),
    'sea', v_line ->> 'sea', 'at', p_now, 'result', v_res, 'outcome', v_f ->> 'outcome',
    'hull_lost', jsonb_build_object('navy', (select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(coalesce(v_f -> 'hull_lost' -> 'b', '{}'::jsonb)) h),
                                    'pirate', (select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(coalesce(v_f -> 'hull_lost' -> 'a', '{}'::jsonb)) h)),
    'sunk', jsonb_build_object('navy', v_sunk_n, 'pirate', v_sunk_p)));
  return jsonb_build_object('result', v_res, 'outcome', v_f ->> 'outcome', 'event', v_ev,
    'hull_lost', jsonb_build_object('navy', v_f -> 'hull_lost' -> 'b', 'pirate', v_f -> 'hull_lost' -> 'a'),
    'sunk', jsonb_build_object('navy', v_sunk_n, 'pirate', v_sunk_p));
end
$$
  $f$;

  execute $f$
create function public.navy_hunt_pass(p_now timestamptz, p_only_nation uuid default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0341: THE PASS, from public.tick_navy, every minute: a navy ship and a pirate ship in one sea fight (docs/WORLD_POWERS.md 6.4), at most navy_hunts_per_run a run, at most once an hour a ship. Null while dark
-- (public.navy_hunts_on), so the job's answer is what it was; 0 when no pirate ship is out. Each navy ship at work, on duty, in no battle, with a hull left and no stamp inside the hour: her sea (public.fleet_sea), then
-- THE reader of who is there, public.pirate_ship_in_sea (W17's). Both rows are taken SKIP LOCKED (a press on either just means no fight this minute), both settled first (D.2), then public.navy_fight in a block of its
-- own: a fight that raises is warned of, and the rest go on. Answers the fights fought.
declare
  r       record;
  v_max   int := public.wc_int('navy_hunts_per_run');
  v_n     int := 0;
  v_sea   uuid;
  v_p     uuid;
  v_st    text;
begin
  if not public.navy_hunts_on() then
    return null;
  end if;
  if not exists (select 1 from public.pirate_ships_at_work x where x.sea_id is not null) then
    return 0;
  end if;
  for r in select n.fleet_id
             from public.navy_ships n join public.fleets f on f.id = n.fleet_id
            where n.laid_up_at is null and (p_only_nation is null or n.nation_id = p_only_nation)
              and n.battle_id is null and f.busy_until is null and f.status in ('DOCKED', 'SAILING', 'ANCHORED')
              and (n.fought_at is null or n.fought_at <= p_now - interval '1 hour')
              and public.navy_on_duty(n.nation_id, n.ord, n.unpaid_since)
              and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)
            order by n.fought_at nulls first, n.nation_id, n.ord loop
    exit when v_n >= v_max;
    v_sea := public.fleet_sea(r.fleet_id, p_now);
    continue when v_sea is null;
    v_p := public.pirate_ship_in_sea(v_sea);
    continue when v_p is null;
    continue when exists (select 1 from public.pirate_ships x where x.fleet_id = v_p and x.fought_at > p_now - interval '1 hour')
               or not exists (select 1 from public.ships s where s.fleet_id = v_p and s.durability > 0)
               or exists (select 1 from public.fleets f where f.id = v_p and (f.busy_until is not null or f.status not in ('DOCKED', 'SAILING', 'ANCHORED')));
    perform 1 from public.fleets x where x.id = r.fleet_id for update skip locked;
    continue when not found;
    perform 1 from public.fleets x where x.id = v_p for update skip locked;
    continue when not found;
    begin
      perform voyage.settle(r.fleet_id, p_now);
      perform voyage.settle(v_p, p_now);
      continue when exists (select 1 from public.fleets f where f.id in (r.fleet_id, v_p) and (f.busy_until is not null or f.status not in ('DOCKED', 'SAILING', 'ANCHORED')))
                 or not exists (select 1 from public.ships s where s.fleet_id = r.fleet_id and s.durability > 0)
                 or not exists (select 1 from public.ships s where s.fleet_id = v_p and s.durability > 0);
      perform public.navy_fight(r.fleet_id, v_p, p_now);
      v_n := v_n + 1;
    exception when others then
      raise warning 'navy_hunt_pass: fleet % and % did not fight (SQLSTATE %: %)', r.fleet_id, v_p, sqlstate, sqlerrm;
    end;
  end loop;
  return v_n;
end
$$
  $f$;

  revoke all on function public.navy_hunts_on() from public, anon, authenticated;
  revoke all on function public.fleet_sea(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_hunt_targets(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_hunt_step(uuid, uuid, uuid, boolean, timestamptz) from public, anon, authenticated;
  revoke all on function public.fight_hulls_write(jsonb) from public, anon, authenticated;
  revoke all on function public.navy_fight(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_hunt_pass(timestamptz, uuid) from public, anon, authenticated;

  -- ── 3. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0341 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0341 values
  ('public.tick_navy(timestamp with time zone,uuid)', 1,
$h$  v_s     text;
begin
$h$,
$h$  v_s     text;
  v_fights int;   -- 0341: null while the hunt is dark
begin
$h$),
  ('public.tick_navy(timestamp with time zone,uuid)', 2,
$h$  for r in select n.fleet_id from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
$h$,
$h$  if v_lit then   -- 0341: the hunt, behind both switches (public.navy_hunts_on): a navy ship and a pirate ship in one sea fight, before the steps; null while the pirates are dark
    begin
      v_fights := public.navy_hunt_pass(p_now, p_only_nation);
    exception when others then
      raise warning 'tick_navy: the hunt stayed (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
  end if;
  for r in select n.fleet_id from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
$h$),
  ('public.tick_navy(timestamp with time zone,uuid)', 3,
$h$  return jsonb_build_object('plan', v_plan, 'steps', v_steps, 'added', v_add, 'paid', v_paid);
$h$,
$h$  return jsonb_build_object('plan', v_plan, 'steps', v_steps, 'added', v_add, 'paid', v_paid)
    || case when v_fights is null then '{}'::jsonb else jsonb_build_object('fights', v_fights) end;   -- 0341: served only when the hunt ran, so a dark run answers byte for byte
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 1,
$h$  v_esc   text;   -- 0333
begin
$h$,
$h$  v_esc   text;   -- 0333
  v_hunt  text;   -- 0341
begin
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 2,
$h$  v_home := case when v_duty then coalesce(public.navy_station_of(n.nation_id, n.ord), n.station_port) else n.station_port end;
$h$,
$h$  v_home := case when v_duty then coalesce(public.navy_station_of(n.nation_id, n.ord), n.station_port) else n.station_port end;
  -- 0341: the hunt (docs/WORLD_POWERS.md 6.4), lit with the pirates: at her station she sails for the most dangerous sea in reach, or lies watching her own; answers null for every other ship
  v_hunt := public.navy_hunt_step(p_fleet, f.port_id, v_home, v_duty, p_now);
  if v_hunt is not null then
    return v_hunt;
  end if;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$h$  update public.ships sh set durability = greatest(0, sh.durability - l.lost)
    from (select x.key::uuid as id, x.value::numeric as lost from jsonb_each_text(coalesce(v_f->'hull_lost'->'a', '{}'::jsonb)) x
          union all
          select x.key::uuid, x.value::numeric from jsonb_each_text(coalesce(v_f->'hull_lost'->'b', '{}'::jsonb)) x) l
   where sh.id = l.id;
$h$,
$h$  perform public.fight_hulls_write(v_f);   -- 0341: these lines, lifted: THE hull writer, which the navy's fight with a pirate ship shares
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 1,
$h$  -- 0334: her country remembers what it did not answer (docs/WORLD_POWERS.md section 5.3): she won, or no ship of it came in time.
$h$,
$h$  -- 0341 (docs/WORLD_POWERS.md 2.1, the pirate row): a pirate ship beaten (boarded, paid off, or every hull at 0) earns the company regard_pirate with EVERY great power but the pirates, once a battle. Beaten by her: nothing.
  if public.fleet_kind(v_d) = 'PIRATE'
     and (v_out in ('PLUNDERED', 'RANSOM') or not exists (select 1 from public.ships s where s.fleet_id = v_d and s.durability > 0)) then
    perform public.regard_add(v_a.player_id, g.nation_id, public.wc_num('regard_pirate'), 'DROVE_OFF_PIRATE')
       from public.great_powers g join public.nations gn on gn.id = g.nation_id where not g.pirate order by gn.code;
  end if;
  -- 0334: her country remembers what it did not answer (docs/WORLD_POWERS.md section 5.3): she won, or no ship of it came in time.
$h$),
  ('world.navy_ship_card(uuid)', 1,
$h$                from public.ships s where s.fleet_id = p_fleet))
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0333: as a cargo ship's card: the key is served only while attacks are lit
$h$,
$h$                from public.ships s where s.fleet_id = p_fleet))
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end   -- 0333: as a cargo ship's card: the key is served only while attacks are lit
    || case when n.fought is null then '{}'::jsonb else jsonb_build_object('fought', n.fought) end;   -- 0341: her last fight with a pirate ship, {at, result, foe, sea}; absent until one, so the card is what it was
$h$);

  for v_h in select h.fn from hunks_0341 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0341 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0341 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0341 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0341 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0341 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 4. THE SELF-ASSERT: the catalog, stable reads and arithmetic. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0341 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0341 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0341 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0341 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if (select c.value from public.world_config c where c.key = 'navy_enabled') <> 'false'::jsonb or (select c.value from public.world_config c where c.key = 'pirates_bite') <> 'false'::jsonb then
    raise exception '0341 self-assert FAIL: a switch is not off';
  end if;
  if (select string_agg(c.key || '=' || c.value::text, ',' order by c.key) from public.world_config c where c.key = any (c_keys)) <> 'navy_hunt_hours=6,navy_hunts_per_run=5,regard_pirate=30' then
    raise exception '0341 self-assert FAIL: the knobs are not as shipped: %', (select string_agg(c.key || '=' || c.value::text, ',' order by c.key) from public.world_config c where c.key = any (c_keys));
  end if;
  if exists (select 1 from public.navy_ships n where n.fought_at is not null or n.fought is not null or n.hunt_port is not null or n.hunt_until is not null)
     or exists (select 1 from public.navy_ships n where n.mission = 'HUNT')
     or exists (select 1 from public.events e where e.kind = 'NAVY_FIGHT') then
    raise exception '0341 self-assert FAIL: a row was written dark';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.navy_hunts_on()'::regprocedure, 'public.fleet_sea(uuid,timestamp with time zone)'::regprocedure, 'public.navy_hunt_targets(uuid,timestamp with time zone)'::regprocedure]::oid[])) <> 'sss' then
    raise exception '0341 self-assert FAIL: a read is not stable';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)'::regprocedure, 'public.fight_hulls_write(jsonb)'::regprocedure,
                                'public.navy_fight(uuid,uuid,timestamp with time zone)'::regprocedure, 'public.navy_hunt_pass(timestamp with time zone,uuid)'::regprocedure]::oid[])) <> 'vvvv' then
    raise exception '0341 self-assert FAIL: a writer is not volatile';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0341 self-assert FAIL: a new function can be called from a client';
  end if;
  if public.navy_hunts_on() then
    raise exception '0341 self-assert FAIL: the hunt reads lit with both switches off';
  end if;
  -- the sea of a fleet in port is her harbour's, on the first docked fleet there is (a read of one row; none: proof 48 reads it on its own ships)
  select f.id, p.sea_id into v_fid, v_sea from public.fleets f join public.ports p on p.id = f.port_id where f.status = 'DOCKED' order by f.id limit 1;
  if v_fid is not null and public.fleet_sea(v_fid, now()) is distinct from v_sea then
    raise exception '0341 self-assert FAIL: a docked fleet reads a sea that is not her harbour''s';
  end if;
  -- the targets of one station, in order: the most dangerous first, one row a sea, none beyond reach, the station's own sea with the station as its harbour
  select p.id, p.sea_id into v_port, v_sea from public.ports p where p.code = 'LIS';
  if v_port is null then
    raise exception '0341 self-assert FAIL: no Lisbon to read the targets from';
  end if;
  if (select count(*) from public.navy_hunt_targets(v_port, now())) < 2
     or (select count(*) from public.navy_hunt_targets(v_port, now()) t where t.nm > public.wc_num('navy_reach_nm')) <> 0
     or (select count(*) - count(distinct t.sea_id) from public.navy_hunt_targets(v_port, now()) t) <> 0
     or (select count(*) from public.navy_hunt_targets(v_port, now()) t where t.sea_id = v_sea and t.port_id = v_port and t.nm = 0) <> 1
     or exists (select 1 from (select t.danger, lag(t.danger) over (order by t.danger desc, t.nm, t.port_id) as prev from public.navy_hunt_targets(v_port, now()) t) z where z.prev < z.danger)
     or exists (select 1 from public.navy_hunt_targets(v_port, now()) t where t.danger is distinct from voyage.sea_danger(t.sea_id, now())) then
    raise exception '0341 self-assert FAIL: the targets of Lisbon are not in order, one a sea, within reach, with her own sea at 0 nm';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0341 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0341 self-assert ok: THE NAVY HUNTS, dark behind navy_enabled and pirates_bite. % hunks once each and reversing; no other function, knob or job; no row written; Lisbon reads % seas in reach; no game step ran (proof 48 runs them in CI). % ms.',
    (select count(*) from hunks_0341), (select count(*) from public.navy_hunt_targets(v_port, now())), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0341;
end
$m$;
