-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0477 - EARLY SIGHTING  (dark: the owner's switch early_sighting_enabled, false; lit, once in a company's life, between Trading 3 and
--        Master, a weak named pirate sights her on a near trip and she meets the real fight: Run, Pay or Fight; the worst is a small loss)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 7 ("Something can go wrong, a little, early"; slice 8's "survive the sighting" reads
--   it); docs/dev-log/2026-11-23-early-sighting.md.
--
-- WHY: the beginner's peace (0464, raid_company_title_min 3 = Master) passes a young company over, so the rule "something can go wrong"
--   never fires in her first hours (play-test 3 #12, #25). EVE (risk and insurance) and Pirates! (a sail on the horizon) put a small,
--   survivable danger early, so insurance and guns mean something before a loss can hurt.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   WHO, AND WHEN IT IS SET (the trigger point is her DEPARTURE, voyage.depart's human arm, one hunk; never a scan of the companies):
--     a company (not a merchant) with no sighting fought yet, Trading at least early_sighting_trading_min (3: her paid mark, the one reading
--     public.first_voyage_have 'trading'), her title under raid_company_title_min (0464's beginner's peace: Master), leaving a harbour for
--     another with cargo aboard (public.fleet_stock_at_cost > 0) on a NEAR trip: early_sighting_trip_min_seconds (240) to
--     early_sighting_trip_max_seconds (1800) real seconds. One row a company (public.early_sightings, its key the guard): DUE at
--     early_sighting_at (0.4) of the trip. A trip that ends before it is sighted leaves the row MISSED, and her next such departure sets it again.
--   THE SIGHTING (the pirates' minute job, public.tick_pirates, one hunk: a partial index over the few DUE rows, never the beat): the
--     nearest pirate at work, free and afloat, of the weakest rungs (public.npc_rung_of under early_sighting_rung_max: 1, a Raider, the
--     roster's lone fustas and brigantines, each with her own name), with no bounty on her, opens THE battle on her through
--     public.battle_open, kind RAID: the same sheet, the same ticks, the battle card, the action bar (Run, Pay, her abilities), her standing
--     order as her opening stance (cmd.raid_order), the same close (public.raid_close: the ransom, ransom_share of her cargo at cost; the
--     hands), her BATTLE_REPORT. Nothing of the fight is new. TWO THINGS MAKE IT A SIGHTING AND NOT A RAID:
--       WEAK: the pirate's guns on the sheet are early_sighting_strength (0.5) of hers, and the sheet is re-run (public.tick_battle_run, as
--         an act or a joiner re-runs it); if the timeline would take any hull of her side under early_sighting_hull_floor (0.5) of its
--         most (or under what it had, if less), the guns are halved again, three times, then silenced. So THE WORST CASE IS THE RANSOM,
--         A SMALL LOSS OF CARGO'S WORTH, NEVER THE SHIP. Nobody joins it (public.battle_npc_joins, one hunk).
--       TOLD: at the close (the next minute's run), the step writes her EARLY_SIGHTING event, the arrival card's lines: what happened (the
--         pirate, the end, the loss), what insurance did (an insured voyage is paid back by public.insurance_claim, cause EARLY_SIGHTING:
--         (1 - insurance_keep_pct) of the loss) or would have done, and, when she had no guns, what guns would have done (the same sheet
--         re-run by public.tick_fight with her hulls armed like the pirate: its end). Her hulls are held at the floor (a net; the guard
--         above already keeps them there).
--   THE READ, world.early_sighting() (the client's one door, registered): dark {"on": false}; lit {on, state, report}. The Buy & sell
--     sheet shows its "If attacked" line (the standing order's press) while on.
-- ONE AUTHORITY EACH: whether a departure is set, public.early_sighting_plan; the sighting, public.early_sighting_open; its close,
--   public.early_sighting_close; the minute's run, public.early_sighting_step; the one writer of public.early_sightings is these three.
-- NOT CHANGED: the fight, the sheet freeze, the close, the ransom, Run and Pay, the standing order, insurance's price, the pirates' own
--   strikes (raid_target, the beginner's peace), the bounties. No knob of another feature moves.
-- ROWS: dark none. Lit: one public.early_sightings row a company, ever; its one battle (as a raid's: ~40 rows, deleted with the raids at
--   raid_keep_hours), one EARLY_SIGHTING event, at most one INSURANCE_PAID. About one fight per new company, ever.
--   -- budget: one new table of one row a company (no job, no cron; two partial indexes over its few DUE / OPEN rows, a unique battle_id).
-- COST: a human departure, dark one knob read; lit a key probe of the table and a few reads of her own rows. The minute job, dark one knob
--   read; lit two probes of the partial indexes (empty almost always). The joins' battle list: one key probe per live raid (at most 10).
-- LOCKS: CREATE TABLE (new, no foreign key: one would lock public.players); CREATE FUNCTION x5; CREATE OR REPLACE x4 by a hunk each
--   (voyage.depart, public.tick_pirates, public.battle_npc_joins, public.client_rpc_entry_points); eight knobs. TIME: seconds.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, early_sighting_enabled false (departures set nothing, the step answers {} and opens and closes
--   nothing; a battle already open is fought and closed by the raids' own close; its row stays OPEN, inert). Full: a new migration reversing
--   the four hunks (OLD texts below verbatim), dropping the five functions and the table, deleting the knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants unmoved; the knobs; the table and the
--   server-only functions unreachable by a client, world.early_sighting registered for authenticated alone. THE PROBE (rolled back): DARK a
--   company that would be set departs and nothing is written, the step answers {} and the read {"on": false}; LIT the departure sets one
--   DUE row at its share of the trip, an untrained company none; the step opens a RAID by the nearest weak pirate (a probe fusta lying
--   where she is), its guns cut, her hulls safe in the timeline, nobody joins; closed, the next step tells it once (EARLY_SIGHTING), her
--   ship afloat, the row DONE; her next departure sets nothing (once). Proof 180 plays it with the purses lit, insurance, the guard, a miss.
-- VERSION: 0477 = 0476 + 1 (0476, #815, hunks client_rpc_entry_points; this file's registry hunk is anchored on 0476's own new line).
-- news: none (dark: nothing changes for a player until the owner lights early_sighting_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'public.tick_pirates(timestamp with time zone)',
                                    'public.battle_npc_joins(timestamp with time zone)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.early_sighting_plan(uuid,timestamp with time zone)', 'public.early_sighting_open(uuid,timestamp with time zone)',
                                    'public.early_sighting_close(uuid,timestamp with time zone)', 'public.early_sighting_step(timestamp with time zone)',
                                    'world.early_sighting()'];
  c_uid    constant uuid := '00000000-0477-4000-8000-000000000001';
  c_raw    constant uuid := '00000000-0477-4000-8000-000000000002';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_lived     boolean := false;
  v_lis       uuid;
  v_set       uuid;
  v_me        uuid;
  v_raw       uuid;
  v_fl        uuid;
  v_fr        uuid;
  v_ship      uuid;
  v_segs      jsonb;
  v_voy       uuid;
  v_e         record;   -- a row of public.early_sightings (made below: a %rowtype would be resolved before it exists)
  v_mp        uuid;
  v_pf        uuid;
  v_pos       record;
  v_r         jsonb;
  v_b         public.battles%rowtype;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'early_sighting_enabled') or to_regclass('public.early_sightings') is not null then
    raise exception '0477 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.first_voyage_have(uuid,text)') is null or to_regprocedure('public.title_level(uuid)') is null
     or to_regprocedure('public.battle_open(text,uuid,uuid,timestamp with time zone)') is null or to_regprocedure('public.tick_battle_run(uuid)') is null
     or to_regprocedure('public.insurance_claim(uuid,integer,jsonb,text)') is null or to_regprocedure('public.npc_rung_of(uuid)') is null
     or to_regclass('public.pirate_bounties') is null or not exists (select 1 from public.world_config where key = 'raid_company_title_min')
     or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0477 refuses: 0476 (the Trading reading), 0471 (bounties), 0464 (the beginner''s peace), 0451 (the rungs), 0435 (the tick fight) or 0213 (insurance) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS AND THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('early_sighting_enabled', 'false'::jsonb,
     '0477: THE SWITCH (the owner''s). true: once in a company''s life, between Trading early_sighting_trading_min and Master (raid_company_title_min), a near trip with cargo is set at her departure, and at early_sighting_at of it the nearest weak pirate opens the real fight on her (a RAID), its guns cut so her ship is never lost; its close is told on the arrival card (EARLY_SIGHTING). false: nothing is set, opened or told; a battle already open is closed by the raids'' own close.'),
    ('early_sighting_trading_min', to_jsonb(3), '0477: a company is sighted only from this Trading level (her paid mark, public.first_voyage_have ''trading''), and only while her title is under raid_company_title_min (the beginner''s peace).'),
    ('early_sighting_trip_min_seconds', to_jsonb(240), '0477: the shortest trip (real seconds, departure to arrival) a sighting is set on: time for the fight and the close before she arrives.'),
    ('early_sighting_trip_max_seconds', to_jsonb(1800), '0477: the longest trip (real seconds) a sighting is set on: a NEAR trip.'),
    ('early_sighting_at', to_jsonb(0.4), '0477: the share of the trip at which she is sighted (0.4: two fifths of the way).'),
    ('early_sighting_rung_max', to_jsonb(1), '0477: the pirate who sights her is of this rung or under (public.npc_rung_of: 1 a Raider, one small hull). None free: she is asked for again the next minute.'),
    ('early_sighting_strength', to_jsonb(0.5), '0477: the pirate''s guns on the sheet, as a share of her own (0 to 1). Halved again (three times, then silenced) while the timeline would take her hulls under early_sighting_hull_floor.'),
    ('early_sighting_hull_floor', to_jsonb(0.5), '0477: no hull of her side ends the sighting under this share of its most (or under what it had, if less): the guard on the pirate''s guns and the net at the close.');

  -- retention: none, bounded by one row a company, ever (its primary key); no row is deleted. Its battle goes with the raids (raid_keep_hours).
  create table public.early_sightings (
    player_id    uuid        not null primary key,
    fleet_id     uuid        not null,
    voyage_id    uuid        not null,
    state        text        not null default 'due' check (state in ('due', 'open', 'done', 'missed')),
    due_at       timestamptz not null,
    tries        int         not null default 0,
    pirate_fleet uuid,
    battle_id    uuid        unique,
    strength     numeric,
    order_word   text,
    planned_at   timestamptz not null default now(),
    sighted_at   timestamptz,
    closed_at    timestamptz,
    report       jsonb
  );
  create index early_sightings_due on public.early_sightings (due_at) where state = 'due';
  create index early_sightings_open on public.early_sightings (sighted_at) where state = 'open';
  comment on table public.early_sightings is
    '0477: THE EARLY SIGHTING, one row a company, ever (its primary key the guard): set DUE at a departure (public.early_sighting_plan), OPEN when '
    'the weak pirate opens the fight (public.early_sighting_open: battle_id), DONE when its close is told (public.early_sighting_close: report), '
    'MISSED when the trip ended first (set again at her next such departure). No foreign key on purpose: one would lock public.players.';
  alter table public.early_sightings enable row level security;
  revoke all on table public.early_sightings from public, anon, authenticated;

  -- ── 3. THE RULES ──
  execute $f$
create function public.early_sighting_plan(p_voyage uuid, p_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0477: IS THIS DEPARTURE THE ONE A WEAK PIRATE SIGHTS? Called by voyage.depart for a human company alone. Dark: one knob read, false.
-- Lit: a harbour-to-harbour trip of early_sighting_trip_min_seconds .. early_sighting_trip_max_seconds, cargo aboard, her Trading mark at
-- least early_sighting_trading_min, her title under raid_company_title_min, and no sighting fought yet: her row is set DUE at
-- early_sighting_at of the trip (a DUE or MISSED row is moved to this trip; an OPEN or DONE one never). Never raises: a fault is a warning
-- and false, so a departure never fails here.
declare
  v      public.voyages%rowtype;
  v_secs numeric;
begin
  if public.wc('early_sighting_enabled') is distinct from 'true'::jsonb then
    return false;
  end if;
  begin
    select * into v from public.voyages x where x.id = p_voyage;
    if v.id is null or v.origin_port_id is null or v.dest_port_id is null or v.origin_port_id = v.dest_port_id
       or exists (select 1 from public.early_sightings e where e.player_id = v.player_id and e.state in ('open', 'done'))
       or not exists (select 1 from public.players p where p.id = v.player_id and not p.is_npc) then
      return false;
    end if;
    v_secs := extract(epoch from v.eta - v.departed_at);
    if v_secs < public.wc_num('early_sighting_trip_min_seconds') or v_secs > public.wc_num('early_sighting_trip_max_seconds')
       or public.fleet_stock_at_cost(v.fleet_id) <= 0
       or public.first_voyage_have(v.player_id, 'trading') < public.wc_num('early_sighting_trading_min')
       or coalesce(public.title_level(v.player_id), 1) >= coalesce(public.wc_int('raid_company_title_min'), 3) then
      return false;
    end if;
    insert into public.early_sightings (player_id, fleet_id, voyage_id, state, due_at, planned_at)
    values (v.player_id, v.fleet_id, v.id, 'due',
            v.departed_at + make_interval(secs => (v_secs * least(1, greatest(0, public.wc_num('early_sighting_at'))))::double precision), p_at)
    on conflict (player_id) do update
      set fleet_id = excluded.fleet_id, voyage_id = excluded.voyage_id, state = 'due', due_at = excluded.due_at, planned_at = excluded.planned_at
      where public.early_sightings.state in ('due', 'missed');
    return found;
  exception when others then
    raise warning 'early_sighting_plan: voyage % was not set (SQLSTATE %: %)', p_voyage, sqlstate, sqlerrm;
    return false;
  end;
end
$body$
  $f$;

  execute $f$
create function public.early_sighting_open(p_player uuid, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0477: THE SIGHTING. Her DUE row (held by the caller): her trip over or not hers any more, MISSED; she is in another battle, BUSY;
-- else the nearest pirate at work, free and afloat, of rung early_sighting_rung_max or under, with no open bounty and in no battle
-- (NO_PIRATE: asked again next minute) opens THE battle on her (public.battle_open, kind RAID; both fleets taken SKIP LOCKED, BUSY if
-- either is held). Then the pirate's guns on the sheet are cut to early_sighting_strength and the fight re-run (public.tick_battle_run);
-- while the timeline would leave a hull of her side under early_sighting_hull_floor of its most (or under what it had, if less) they are
-- halved again, three times, then silenced. The row goes OPEN with the battle. Answers OPENED, MISSED, BUSY or NO_PIRATE.
declare
  e       public.early_sightings%rowtype;
  v       public.voyages%rowtype;
  v_lat   double precision;
  v_lon   double precision;
  v_pir   uuid;
  v_n     int := 0;
  v_bat   uuid;
  b       public.battles%rowtype;
  v_b0    jsonb;
  v_s0    numeric := least(1, greatest(0, coalesce(public.wc_num('early_sighting_strength'), 0)));
  v_s     numeric;
  v_floor numeric := least(1, greatest(0, coalesce(public.wc_num('early_sighting_hull_floor'), 0)));
  v_tl    jsonb;
  v_res   jsonb;
  v_ok    boolean := false;
  i       int;
  r       record;
begin
  select * into e from public.early_sightings x where x.player_id = p_player;
  select * into v from public.voyages x where x.id = e.voyage_id;
  if e.player_id is null or e.state <> 'due' then
    return 'MISSED';
  end if;
  if v.id is null or v.status <> 'SAILING' or v.fleet_id <> e.fleet_id
     or not exists (select 1 from public.fleets f where f.id = e.fleet_id and f.status = 'SAILING') then
    update public.early_sightings x set state = 'missed', tries = x.tries + 1 where x.player_id = p_player;
    return 'MISSED';
  end if;
  if exists (select 1 from public.fleets f where f.id = e.fleet_id and f.busy_until is not null) then
    update public.early_sightings x set tries = x.tries + 1 where x.player_id = p_player;
    return 'BUSY';
  end if;
  select q.lat::double precision, q.lon::double precision into v_lat, v_lon from voyage.position(v.id, p_now) q;

  select n.fleet_id into v_pir
    from public.pirate_ships_at_work n
    join public.fleets f on f.id = n.fleet_id
    left join public.ports p on p.id = f.port_id
    left join lateral (select q.lat, q.lon from public.voyages pv cross join lateral voyage.position(pv.id, p_now) q
                        where pv.fleet_id = f.id and pv.status = 'SAILING' limit 1) sp on f.status = 'SAILING'
   where f.busy_until is null and f.status in ('DOCKED', 'ANCHORED', 'SAILING')
     and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)
     and coalesce(public.npc_rung_of(n.fleet_id), 99) <= coalesce(public.wc_int('early_sighting_rung_max'), 1)
     and not exists (select 1 from public.pirate_bounties pb where pb.fleet_id = n.fleet_id and pb.closed_at is null)
     and not exists (select 1 from public.battle_sides bs join public.battles bt on bt.id = bs.battle_id
                      where bs.fleet_id = n.fleet_id and bt.status = 'FIGHTING')
   order by voyage.gc_distance_nm(v_lat, v_lon, coalesce(sp.lat, f.lat, p.lat)::double precision, coalesce(sp.lon, f.lon, p.lon)::double precision) nulls last,
            n.fleet_id
   limit 1;
  if v_pir is null then
    update public.early_sightings x set tries = x.tries + 1 where x.player_id = p_player;
    return 'NO_PIRATE';
  end if;
  for r in select f.id from public.fleets f where f.id in (e.fleet_id, v_pir) order by f.id for update skip locked loop
    v_n := v_n + 1;
  end loop;
  if v_n < 2 then
    update public.early_sightings x set tries = x.tries + 1 where x.player_id = p_player;
    return 'BUSY';
  end if;

  v_bat := public.battle_open('RAID', v_pir, e.fleet_id, p_now);
  select * into b from public.battles x where x.id = v_bat;
  v_b0 := coalesce(b.sheet -> 'b', '[]'::jsonb);
  for i in 0 .. 4 loop
    v_s := case when i < 4 then round(v_s0 / power(2::numeric, i), 4) else 0 end;
    update public.battles x
       set sheet = x.sheet || jsonb_build_object(
             'b', (select coalesce(jsonb_agg(h || jsonb_build_object('attack', round(coalesce((h ->> 'attack')::numeric, 0) * v_s, 2)) order by o), '[]'::jsonb)
                     from jsonb_array_elements(v_b0) with ordinality q(h, o)),
             'early_sighting', v_s,
             'word', public.attack_word(voyage.escort_score(v_pir) * v_s, voyage.escort_score(e.fleet_id)))
     where x.id = v_bat;
    if b.ticks is not null then
      v_tl := public.tick_battle_run(v_bat);
      v_res := v_tl -> 'r';
    else
      v_res := public.battle_fight(v_bat, null);
    end if;
    v_ok := not exists (select 1 from public.battles bx cross join lateral jsonb_array_elements(coalesce(bx.sheet -> 'a', '[]'::jsonb)) h
                         where bx.id = v_bat
                           and coalesce((h ->> 'hull')::numeric, 0) - coalesce((v_res #>> array['hull_lost', 'a', h ->> 'id'])::numeric, 0)
                               < least(coalesce((h ->> 'hull')::numeric, 0), v_floor * coalesce((h ->> 'maxd')::numeric, 0)) - 0.001);
    exit when v_ok;
  end loop;

  update public.early_sightings x
     set state = 'open', battle_id = v_bat, pirate_fleet = v_pir, strength = v_s, sighted_at = p_now, tries = x.tries + 1,
         order_word = public.battle_stance_at(v_bat, e.fleet_id, 'infinity')
   where x.player_id = p_player;
  return 'OPENED';
end
$body$
  $f$;

  execute $f$
create function public.early_sighting_close(p_player uuid, p_now timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0477: THE SIGHTING TOLD, once its battle is over (the raids' own close, public.battle_resolve, has run: the ransom, the hands, her
-- BATTLE_REPORT). Her row OPEN (held by the caller); its battle still FIGHTING: false, nothing written. Else: her hulls held at the floor
-- (early_sighting_hull_floor of their most, or what they had; a net); the loss (the raid's `taken`, the ransom from her purse); an insured
-- voyage claimed for it (public.insurance_claim, cause EARLY_SIGHTING: its cargo's units in the loss's share of its value), else what it
-- would have paid back ((1 - insurance_keep_pct) of the loss); with no guns, what guns would have done (the same sheet, her hulls armed
-- like the pirate's, through public.tick_fight on the battle's own seed: its end). One EARLY_SIGHTING event, the row DONE with its report.
declare
  e       public.early_sightings%rowtype;
  b       public.battles%rowtype;
  c       public.insured_voyages%rowtype;
  v_mine  jsonb;
  v_lost  bigint;
  v_out   text;
  v_h0    numeric;
  v_h1    numeric;
  v_hmax  numeric;
  v_c0    numeric;
  v_c1    numeric;
  v_claim jsonb;
  v_paid  bigint := 0;
  v_keep  numeric := coalesce(public.wc_num('insurance_keep_pct'), 0);
  v_guns  boolean;
  v_armed text;
  v_pa    numeric;
  v_pc    numeric;
  v_pr    numeric;
  v_floor numeric := least(1, greatest(0, coalesce(public.wc_num('early_sighting_hull_floor'), 0)));
  v_rep   jsonb;
  v_ev    uuid;
begin
  select * into e from public.early_sightings x where x.player_id = p_player;
  if e.player_id is null or e.state <> 'open' then
    return false;
  end if;
  select * into b from public.battles x where x.id = e.battle_id;
  if b.id is not null and b.status = 'FIGHTING' then
    return false;
  end if;
  v_out := coalesce(b.result ->> 'outcome', 'NO_FIGHT');
  v_lost := greatest(0, coalesce((b.result #>> '{raid,taken}')::bigint, 0));
  -- her side's hulls on the sheet that are hers now: as they went in, as they are
  select coalesce(jsonb_agg(h), '[]'::jsonb) into v_mine
    from jsonb_array_elements(coalesce(b.sheet -> 'a', '[]'::jsonb)) h
    join public.ships s on s.id = (h ->> 'id')::uuid and s.fleet_id = e.fleet_id;
  select coalesce(sum((h ->> 'hull')::numeric), 0), coalesce(sum((h ->> 'maxd')::numeric), 0), coalesce(sum((h ->> 'crew')::numeric), 0)
    into v_h0, v_hmax, v_c0 from jsonb_array_elements(v_mine) h;
  select coalesce(sum(s.durability), 0), coalesce(sum(s.crew), 0) into v_h1, v_c1
    from public.ships s where s.id in (select (h ->> 'id')::uuid from jsonb_array_elements(v_mine) h);
  -- the net: no hull of hers under the floor (or what it had)
  update public.ships s
     set durability = least(greatest(s.durability, least((h ->> 'hull')::numeric, ceil(v_floor * (h ->> 'maxd')::numeric))), (h ->> 'maxd')::numeric)
    from jsonb_array_elements(v_mine) h
   where s.id = (h ->> 'id')::uuid
     and s.durability < least((h ->> 'hull')::numeric, ceil(v_floor * (h ->> 'maxd')::numeric));

  -- insurance: claimed for an insured voyage, else what it would have paid back
  select * into c from public.insured_voyages x where x.voyage_id = e.voyage_id;
  if c.voyage_id is not null and v_lost > 0 and c.value > 0 then
    v_claim := public.insurance_claim(e.voyage_id, 0,
                 (select coalesce(jsonb_object_agg(k.key, round((k.value)::numeric * least(1, v_lost::numeric / c.value), 4)), '{}'::jsonb)
                    from jsonb_each_text(coalesce(c.cargo, '{}'::jsonb)) k),
                 'EARLY_SIGHTING');
    v_paid := coalesce((v_claim ->> 'paid')::bigint, 0);
  end if;

  -- guns: had she any that could fire? If not, the same sheet with her hulls armed like the pirate's, on the battle's own seed
  v_guns := exists (select 1 from jsonb_array_elements(v_mine) h
                     where coalesce((h ->> 'attack')::numeric, 0) > 0 and coalesce((h ->> 'accuracy')::numeric, 0) > 0);
  if not v_guns and b.id is not null and jsonb_array_length(coalesce(b.sheet -> 'b', '[]'::jsonb)) > 0 and jsonb_array_length(coalesce(b.sheet -> 'a', '[]'::jsonb)) > 0 then
    begin
      -- her hulls armed like the pirate's own (her guns as they are, not as the sighting cut them: voyage.fleet_hulls)
      select max(coalesce((y ->> 'attack')::numeric, 0)), max(coalesce((y ->> 'accuracy')::numeric, 0)), max(coalesce((y ->> 'reach')::numeric, 0))
        into v_pa, v_pc, v_pr from jsonb_array_elements(coalesce(voyage.fleet_hulls(e.pirate_fleet), '[]'::jsonb)) y;
      v_armed := public.tick_fight(b.id,
                   (select jsonb_agg(h || jsonb_build_object(
                             'attack', greatest(coalesce((h ->> 'attack')::numeric, 0), coalesce(v_pa, 0)),
                             'accuracy', greatest(coalesce((h ->> 'accuracy')::numeric, 0), coalesce(v_pc, 0)),
                             'reach', greatest(coalesce((h ->> 'reach')::numeric, 0), coalesce(v_pr, 0)))
                           order by o)
                      from jsonb_array_elements(b.sheet -> 'a') with ordinality q(h, o)),
                   b.sheet -> 'b',
                   jsonb_build_object('a_ai', 'FIGHT', 'b_ai', 'FIGHT') || case when b.sheet ? 'a_flee' then jsonb_build_object('a_flee', b.sheet -> 'a_flee') else '{}'::jsonb end)
                 #>> '{r,outcome}';
    exception when others then
      v_armed := null;
    end;
  end if;

  v_rep := jsonb_build_object(
    'fleet', (select f.name from public.fleets f where f.id = e.fleet_id),
    'battle_id', e.battle_id,
    'pirate', (select f.name from public.fleets f where f.id = e.pirate_fleet),
    'outcome', v_out,
    'order', e.order_word,
    'lost', v_lost,
    'hull_lost', greatest(0, round(v_h0 - v_h1)),
    'hull_max', round(v_hmax),
    'crew_lost', greatest(0, round(v_c0 - v_c1)),
    'insured', c.voyage_id is not null,
    'insurance_paid', v_paid,
    'insurance_back', round(v_lost * (1 - v_keep)),
    'keep_pct', v_keep,
    'guns', v_guns,
    'guns_outcome', v_armed,
    'to', (select p.code from public.voyages vv join public.ports p on p.id = vv.dest_port_id where vv.id = e.voyage_id));
  v_ev := public.emit_event(p_player, 'EARLY_SIGHTING', v_rep);
  update public.early_sightings x set state = 'done', closed_at = p_now, report = v_rep where x.player_id = p_player;
  return true;
end
$body$
  $f$;

  execute $f$
create function public.early_sighting_step(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0477: THE MINUTE'S RUN, from public.tick_pirates (lit pirates, never behind a trade's locks), after the strikes and the joins. Dark: '{}'
-- at once. Lit: the OPEN rows whose battle is over are told (public.early_sighting_close, at most 5 a run), then the DUE rows whose time
-- has come are sighted (public.early_sighting_open, at most 3 a run), each row taken SKIP LOCKED and each in a block of its own (a fault is
-- a warning, and it is asked again next minute). Two probes of partial indexes when there is nothing to do. Never raises. Answers '{}'
-- when nothing happened, else {sighting: {each answer: count}}.
declare
  r     record;
  v_out jsonb := '{}'::jsonb;
  v_s   text;
begin
  if public.wc('early_sighting_enabled') is distinct from 'true'::jsonb then
    return '{}'::jsonb;
  end if;
  begin
    for r in select e.player_id from public.early_sightings e where e.state = 'open' order by e.sighted_at, e.player_id limit 5 for update skip locked loop
      begin
        v_s := case when public.early_sighting_close(r.player_id, p_now) then 'TOLD' else null end;
      exception when others then
        raise warning 'early_sighting_step: % was not told (SQLSTATE %: %)', r.player_id, sqlstate, sqlerrm;
        v_s := 'ERROR';
      end;
      if v_s is not null then
        v_out := v_out || jsonb_build_object(v_s, coalesce((v_out ->> v_s)::int, 0) + 1);
      end if;
    end loop;
    for r in select e.player_id from public.early_sightings e where e.state = 'due' and e.due_at <= p_now order by e.due_at, e.player_id limit 3 for update skip locked loop
      begin
        v_s := public.early_sighting_open(r.player_id, p_now);
      exception when others then
        raise warning 'early_sighting_step: % was not sighted (SQLSTATE %: %)', r.player_id, sqlstate, sqlerrm;
        v_s := 'ERROR';
      end;
      v_out := v_out || jsonb_build_object(v_s, coalesce((v_out ->> v_s)::int, 0) + 1);
    end loop;
  exception when others then
    raise warning 'early_sighting_step: the run stopped (SQLSTATE %: %)', sqlstate, sqlerrm;
    v_out := v_out || jsonb_build_object('ERROR', 1);
  end;
  return case when v_out = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('sighting', v_out) end;
end
$body$
  $f$;

  execute $f$
create function world.early_sighting()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0477: THE EARLY SIGHTING, the client's one door. Dark (early_sighting_enabled false): {"on": false}. Lit: {on, state (due, open, done,
-- missed, or null: none set), report (once told: the EARLY_SIGHTING event's payload)} for the signed-in company. Writes nothing.
declare
  v_me uuid := public.current_player_id();
  e    public.early_sightings%rowtype;
begin
  if public.wc('early_sighting_enabled') is distinct from 'true'::jsonb then
    return jsonb_build_object('on', false);
  end if;
  select * into e from public.early_sightings x where x.player_id = v_me;
  return jsonb_build_object('on', true, 'state', e.state, 'report', e.report);
end
$body$
  $f$;
  revoke all on function public.early_sighting_plan(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.early_sighting_open(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.early_sighting_close(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.early_sighting_step(timestamptz) from public, anon, authenticated;
  revoke all on function world.early_sighting() from public, anon;
  grant execute on function world.early_sighting() to authenticated;
  comment on function world.early_sighting() is
    '0477: the early sighting (dark {"on": false}): whether it is lit, the caller''s row state and, once told, its report. A read. Client door.';

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0477 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0477 values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$h$    perform voyage.hostile_freeze(v_voyage, v_player, p_at);$h$,
$h$    perform voyage.hostile_freeze(v_voyage, v_player, p_at);
    perform public.early_sighting_plan(v_voyage, p_at);   -- 0477: is this the trip a weak pirate sights? (dark: one knob read; never raises)$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         -- 0445: LAST, the one ship of this run that may trade takes her step$h$,
$h$         -- 0477: the early sighting (public.early_sighting_step, which never raises): a weak pirate sights a young company once, and its close is told ('{}' dark)
         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then public.early_sighting_step(p_now) else '{}'::jsonb end
         -- 0445: LAST, the one ship of this run that may trade takes her step$h$),
  ('public.battle_npc_joins(timestamp with time zone)', 1,
$h$              where x.status = 'FIGHTING' and x.kind = 'RAID' and x.ticks is not null and x.resolves_at > p_now$h$,
$h$              where x.status = 'FIGHTING' and x.kind = 'RAID' and x.ticks is not null and x.resolves_at > p_now
                and not exists (select 1 from public.early_sightings es where es.battle_id = x.id)   -- 0477: nobody joins an early sighting: the pirate stays weak$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'first_voyages',         ''),$h$,
$h$      ('world',       'first_voyages',         ''),
      -- 0477: the early sighting (dark: {"on": false})
      ('world',       'early_sighting',        ''),$h$);

  for v_h in select h.fn from hunks_0477 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0477 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0477 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0477 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0477 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0477 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0477 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0477 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if public.wc('early_sighting_enabled') <> 'false'::jsonb or public.wc_int('early_sighting_trading_min') <> 3
     or public.wc_int('early_sighting_trip_min_seconds') <> 240 or public.wc_int('early_sighting_trip_max_seconds') <> 1800
     or public.wc_num('early_sighting_at') <> 0.4 or public.wc_int('early_sighting_rung_max') <> 1
     or public.wc_num('early_sighting_strength') <> 0.5 or public.wc_num('early_sighting_hull_floor') <> 0.5 then
    raise exception '0477 self-assert FAIL: the knobs are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'early_sighting', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or has_function_privilege('authenticated', 'public.early_sighting_plan(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.early_sighting_open(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.early_sighting_close(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.early_sighting_step(timestamptz)', 'execute')
     or has_table_privilege('authenticated', 'public.early_sightings', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.early_sightings', 'select')
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0477 self-assert FAIL: world.early_sighting is not registered for authenticated alone, or a client reaches a server-only function or the table';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel ──
  begin
    -- the fight lit as prod is (whatever this world's switches), on a trip of any length
    update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'raid_orders_enabled');
    update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
    update public.world_config set value = to_jsonb(1) where key = 'early_sighting_trip_min_seconds';
    update public.world_config set value = to_jsonb(1000000) where key = 'early_sighting_trip_max_seconds';
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select p.id into v_set from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR';
    select voyage.segments_from_course(jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b2.roadstead_lat, b2.roadstead_lon)))
           || voyage.segments_from_course(jsonb_build_array(jsonb_build_array(b2.roadstead_lat, b2.roadstead_lon), jsonb_build_array(a.roadstead_lat, a.roadstead_lon)))
      into v_segs from public.sea_reaches a, public.sea_reaches b2 where a.port_id = v_lis and b2.port_id = v_set;
    -- her company at Trading 3 (title Apprentice: Exploration 1), cargo aboard; and an untrained one beside her
    v_me := public.new_house(c_uid, 'Casa do Avistamento 0477', 'PRT');
    v_raw := public.new_house(c_raw, 'Casa Crua 0477', 'PRT');
    insert into public.house_level_marks (player_id, track, level) values (v_me, 'trading', 3) on conflict (player_id, track) do update set level = 3;
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    select f.id into v_fr from public.fleets f where f.player_id = v_raw;
    select s.id into v_ship from public.ships s where s.fleet_id = v_fl;
    update public.ships s set cargo = '{"WINE": 10}'::jsonb, cargo_basis = '{"WINE": 50}'::jsonb where s.fleet_id in (v_fl, v_fr);

    -- (a) DARK: a departure that would be set writes nothing; the step answers {}; the read {"on": false}
    v_voy := voyage.depart(v_fl, v_segs, v_lis, v_set, now() - interval '20 seconds');
    perform voyage.depart(v_fr, v_segs, v_lis, v_set, now() - interval '20 seconds');
    perform cmd.assume_identity(c_uid);
    if exists (select 1 from public.early_sightings) or public.early_sighting_step(now()) <> '{}'::jsonb
       or world.early_sighting() is distinct from '{"on": false}'::jsonb then
      raise exception '0477 self-assert FAIL: dark, a departure was set, the step did something or the read is not {"on": false}';
    end if;

    -- (b) LIT: her departure is set DUE at its share of the trip; the untrained company's is not
    update public.world_config set value = 'true'::jsonb where key = 'early_sighting_enabled';
    update public.voyages v set status = 'ABORTED' where v.fleet_id in (v_fl, v_fr) and v.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null where f.id in (v_fl, v_fr);
    v_voy := voyage.depart(v_fl, v_segs, v_lis, v_set, now() - interval '20 seconds');
    perform voyage.depart(v_fr, v_segs, v_lis, v_set, now() - interval '20 seconds');
    select * into v_e from public.early_sightings e where e.player_id = v_me;
    if v_e.player_id is null or v_e.state <> 'due' or v_e.voyage_id <> v_voy
       or abs(extract(epoch from v_e.due_at - ((select v.departed_at + (v.eta - v.departed_at) * 0.4 from public.voyages v where v.id = v_voy)))) > 0.01
       or exists (select 1 from public.early_sightings e where e.player_id = v_raw)
       or world.early_sighting() <> '{"on": true, "state": "due", "report": null}'::jsonb then
      raise exception '0477 self-assert FAIL: lit, her departure was not set DUE at 0.4 of the trip, or the untrained one was: %', to_jsonb(v_e);
    end if;

    -- (c) THE SIGHTING: a probe fusta of the Brethren (rung 1: a Raider) lying where she is now; the step opens the raid
    select q.lat, q.lon into v_pos from voyage.position(v_voy, now()) q;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Lobo 0477', public.pirate_nation(), 0, true) returning id into v_mp;
    v_pf := public.form_fleet(v_mp, 'Lobo 0477', v_lis);
    perform public.commission_ship(v_mp, v_pf, 'fusta', 'Lobo 0477', true, true);
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port) values (v_pf, v_mp, 900002, v_lis, v_lis);
    update public.ships s set crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id), durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_pf;
    update public.fleets f set status = 'ANCHORED', port_id = null, lat = v_pos.lat, lon = v_pos.lon, busy_until = null, ready_at = null where f.id = v_pf;
    update public.early_sightings e set due_at = now() - interval '1 second' where e.player_id = v_me;
    v_r := public.early_sighting_step(now());
    select * into v_e from public.early_sightings e where e.player_id = v_me;
    select * into v_b from public.battles b where b.id = v_e.battle_id;
    if v_r -> 'sighting' ->> 'OPENED' is distinct from '1' or v_e.state <> 'open' or v_e.pirate_fleet <> v_pf or v_b.kind <> 'RAID'
       or not exists (select 1 from public.battle_sides bs where bs.battle_id = v_b.id and bs.fleet_id = v_pf and bs.side = 'ATTACKER' and bs.how = 'OPENED')
       or not exists (select 1 from public.battle_sides bs where bs.battle_id = v_b.id and bs.fleet_id = v_fl and bs.side = 'DEFENDER' and bs.how = 'OPENED')
       or v_e.strength > 0.5 or (v_b.sheet ->> 'early_sighting')::numeric <> v_e.strength
       or exists (select 1 from jsonb_array_elements(v_b.sheet -> 'a') h
                   where (h ->> 'hull')::numeric - coalesce((v_b.ticks #>> array['r', 'hull_lost', 'a', h ->> 'id'])::numeric, 0)
                         < least((h ->> 'hull')::numeric, 0.5 * (h ->> 'maxd')::numeric) - 0.001) then
      raise exception '0477 self-assert FAIL: the step did not open a weak raid on her by the probe pirate with her hulls safe: % % %', v_r, to_jsonb(v_e), left(v_b.sheet::text, 400);
    end if;
    if public.early_sighting_step(now()) <> '{}'::jsonb then
      raise exception '0477 self-assert FAIL: a second step did something while the fight is on';
    end if;

    -- (d) THE CLOSE: the raids' own close, then the next step tells it once; her ship afloat; the row DONE
    perform public.battle_resolve(v_b.id, v_b.resolves_at + interval '1 second');
    v_r := public.early_sighting_step(v_b.resolves_at + interval '2 seconds');
    select * into v_e from public.early_sightings e where e.player_id = v_me;
    if v_r -> 'sighting' ->> 'TOLD' is distinct from '1' or v_e.state <> 'done' or v_e.report ->> 'outcome' is null
       or (select count(*) from public.events ev where ev.player_id = v_me and ev.kind = 'EARLY_SIGHTING') <> 1
       or (v_e.report ->> 'lost')::bigint <> coalesce((select (b.result #>> '{raid,taken}')::bigint from public.battles b where b.id = v_b.id), 0)
       or (select s.durability from public.ships s where s.id = v_ship) < least(400, 0.5 * (select sb.durability from public.ship_base(v_ship) sb))
       or (select f.status from public.fleets f where f.id = v_fl) = 'UNABLE_TO_SAIL'
       or public.early_sighting_step(v_b.resolves_at + interval '3 seconds') <> '{}'::jsonb then
      raise exception '0477 self-assert FAIL: the close was not told once, or her ship was not kept: % %', v_r, to_jsonb(v_e);
    end if;
    v_note := format('the raid opened by the probe Raider at strength %s, ended %s, lost %s, guns %s -> %s',
                     v_e.strength, v_e.report ->> 'outcome', v_e.report ->> 'lost', v_e.report ->> 'guns', coalesce(v_e.report ->> 'guns_outcome', '-'));

    -- (e) ONCE: her next departure sets nothing
    update public.voyages v set status = 'ABORTED' where v.fleet_id = v_fl and v.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null where f.id = v_fl;
    perform voyage.depart(v_fl, v_segs, v_lis, v_set, now());
    if (select e.state from public.early_sightings e where e.player_id = v_me) <> 'done' then
      raise exception '0477 self-assert FAIL: a company sighted once was set again';
    end if;
    raise exception using errcode = 'ZX477', message = 'PROBE_ROLLBACK_0477';
  exception when sqlstate 'ZX477' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0477 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0477' or p.auth_uid in (c_uid, c_raw))
     or exists (select 1 from public.early_sightings)
     or public.wc('early_sighting_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0477 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0477 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0477 self-assert ok: EARLY SIGHTING (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; the table, five functions, eight knobs (early_sighting_enabled false). Probe (rolled back): dark nothing set or done; lit set DUE at 0.4, an untrained company not; %; told once, her ship kept, set once. % ms.',
    (select count(*) from hunks_0477), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
