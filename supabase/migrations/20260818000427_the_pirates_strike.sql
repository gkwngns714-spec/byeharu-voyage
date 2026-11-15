-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0427 - THE PIRATES STRIKE  (a pirate ship hunting her waters sets upon a merchant within reach every few minutes, through the one battle;
--        the pirates are woken, built and reborn five times faster; the Stats tab counts the battles)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "spawn rate of pirates should be faster alot. attack rate of pirates with other merchants should be done also
--   frequently. in stats i see no engagement". Earlier: pirates "engage combat more aggressively with other npcs and players"; no PvP, ever.
--
-- WHY THERE HAS NEVER BEEN A BATTLE (prod, read-only, 2026-11-15 00:19 UTC, head 0425; docs/dev-log/2026-11-15-pirates-strike.md):
--   public.battles holds 0 rows, all time, with attack_enabled, pirates_bite and combat_bite all true. THE ROOT CAUSE: nothing a pirate does
--   ever reaches the battle. public.battle_open has exactly one caller, public.attack_for (0327), the PLAYER'S door (cmd.attack): its first
--   gate is "if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = p_player)" with a human's p_player, and
--   battle_open itself answers "kind PROBE or ATTACK" only and refuses every human defender ("E_HUMAN_TARGET"). A pirate ship's own step
--   (public.pirate_ship_step, run by tick_pirates) only sails, lies at her haunt, trades and sails home: it calls no attack. The pirates' raids
--   are the anonymous/named PIRATES days that voyage.settle rolls inside a merchant's voyage (0339: a fight in one call, no battles row),
--   and the navy's fights with pirates are public.navy_fight (0340: one call, a NAVY_FIGHT event, no battles row). So battles stays empty
--   unless a player presses Attack, and no player has.
--   A SECOND CAUSE of "no engagement": of 87 pirate fleets, 79 are LAID UP and unpaid since 2026-11-14 12:40-15:15 UTC. Their hourly pay comes
--   from the day's room (pirate_spend_day_pct 0.24 % of the 951 M hoard = 2.28 M a UTC day); on 2026-11-14 5.21 M was spent (gifts, refits,
--   pay), the room ran out, each ship it could not pay was laid up, and a laid-up fleet is woken one at a time, one in pirate_add_minutes (5),
--   only while the room can pay her hour. 3 pirates were cruising at 00:19 UTC; each had merchants within reach (33 among the three).
--
-- WHAT THIS FILE DOES:
--   S1. A PIRATE STRIKES (new: public.raid_target, public.pirate_strike, public.pirate_strikes, public.raid_close; kind RAID):
--       every minute, after its steps, its add and its pay, the pirates' job (public.tick_pirates, one hunk) lets the pirate ships that are
--       HUNTING (public.pirate_ships_cruising, THE rule of "she is in a sea": out for her haunt or lying at it, a hull left; and free) strike:
--       each picks the nearest merchant within attack_reach_nm (240) of her (a company's merchant, a crown's cargo ship, or a PLAYER'S ship:
--       never a navy or a pirate ship, never one of the pirates' own country, never a ship in port, never one set upon in the last
--       attack_ship_minutes (60)), and opens THE battle on her through public.battle_open, kind RAID. One authority: the same rounds, the
--       same sheet, the same navy call (a crown's cargo ship calls her country's ships), the same close, the same map.
--       RATE (decided by default): a pirate strikes at most once in pirate_strike_minutes (5); at most pirate_strikes_per_run (2) battles
--       are opened a minute, among at most pirate_strike_tries_per_run (8) pirates asked, in a turning order. So at most 120 raids an hour.
--   S2. A RAID IS A PIRATE'S: public.battle_open (three hunks) takes kind RAID only with a pirate ship attacking a merchant (MERCHANT,
--       CARGO_SHIP or COMPANY); for RAID alone the human-defender refusal does not apply, because a pirate is no player. Every other kind keeps
--       the law as it was: no player fights another player. A raid calls the navy and freezes its sheet as an attack does.
--   S3. A RAID CLOSES (public.battle_resolve, one hunk; public.raid_close): won (PLUNDERED or RANSOM), a crown's cargo ship's funds aboard are
--       looted to the pirate's home (public.pirate_loot_book, loot_share) and any other merchant pays a ransom from her company's purse
--       (public.pirate_ransom: ransom_share of her cargo at cost; a purse pays what it holds); thrown back, the pirate loses hands. A ship of
--       either side with every hull at 0 at sea is a wreck by 0322's rule. A player's ship set upon gets a BATTLE_REPORT. Gold only, moved,
--       never minted (the closed economy's kinds RANSOM and LOOT, 0339's).
--   S4. FASTER (knobs, each moved only from the value prod had): pirate_add_minutes 5 -> 1 (a laid-up fleet woken, or a roster fleet built,
--       every minute); pirate_respawn_minutes 60 -> 5 (a wreck lies 5 minutes at home before she is paid, mended and manned); and
--       pirate_spend_day_pct 0.0024 -> 0.006 (the day's room 2.28 M -> 5.7 M of a 951 M hoard: yesterday's 5.21 M spend fits, so the
--       hour's pay, the wakes and a wreck's refit no longer wait for 00:00 UTC). WHO PAYS IS UNCHANGED (the owner's rule "just like before"):
--       her own purse, her home, another pirate city, then the hoard inside the room (public.pirate_refit_pay). Decided by default.
--   S5. THE STATS COUNT THE BATTLES (public.stats_fleets_count, world.stats_fleets, one hunk each): each count's window adds raids opened,
--       raids the pirates won, raids the merchants held, raids the navy came to, and players' attacks; the Stats face sums 24 hours and shows
--       them on a Battles card beside the navy's fights.
-- RETENTION: -- retention: a closed RAID battle (and its sides, rounds, stances, by cascade) is deleted raid_keep_hours (48) after it closed,
--   by public.pirate_strikes, at most 20 a run (more than the 2 a run opened). An ATTACK or PROBE battle is never deleted here.
-- LOAD: -- budget: at most 2 battles opened a minute (each ~40 rows over its 10 minutes, battle_seconds: the battle, 2-3 sides, 7 rounds, holds, hulls, crew,
--   1-3 money rows, an event) = ~80 rows a minute, plus ~20 rows a minute of retention; the add every minute ~+5 rows a minute. About +100
--   rows a minute at the ceiling; the target search reads the sailing voyages once a pirate asked (~1,500 rows, two sums each), 8 a minute.
--   No job is added or rescheduled; no table is made; one partial index.
-- LOCKS: CREATE OR REPLACE x5 by hunks; CREATE FUNCTION x4; battles_kind_check dropped and added (0 rows on prod). BUDGET: statement_timeout 45 s,
--   lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/pirate-war/rollback-0427.sql (a draft). Quick: pirate_strikes_per_run 0 stops every new
--   raid at once (running ones close); the three knobs back to 5, 60, 0.0024.
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the new functions
--   server-only; the knobs; then THE PROBE, rolled back: a hunting pirate in this world (if any) strikes through public.pirate_strike and the
--   battle is a RAID on a merchant; and battle_open still refuses a RAID by a ship that is not a pirate's.
-- VERSION: 0427 = 0426 (more ships at sea 3, #703) + 1. 0426 hunks none of these bodies.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array[
    'public.battle_open(text,uuid,uuid,timestamp with time zone)', 'public.battle_resolve(uuid,timestamp with time zone)',
    'public.tick_pirates(timestamp with time zone)', 'public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 'world.stats_fleets()'];
  c_new constant text[] := array[
    'public.raid_target(uuid,timestamp with time zone)', 'public.pirate_strike(uuid,timestamp with time zone)',
    'public.pirate_strikes(timestamp with time zone)', 'public.raid_close(uuid,jsonb,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_kept      text := '';
  v_note      text := 'no hunting pirate with a merchant in reach in this world: proof 128 strikes one';
  v_p         uuid;
  v_s         text;
  v_b         record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'pirate_strike_minutes')
     or exists (select 1 from pg_constraint c where c.conname = 'battles_kind_check' and pg_get_constraintdef(c.oid) like '%RAID%') then
    raise exception '0427 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.pirate_add_roster(timestamp with time zone)') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regprocedure('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)') is null
     or to_regprocedure('public.pirate_loot_book(uuid,uuid,numeric,uuid)') is null or to_regclass('public.pirate_ships_cruising') is null then
    raise exception '0427 refuses: 0418 (the roster), 0419 (the fleets'' stats), 0339 (the plunder) or the news are not all in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KIND, THE INDEX, THE KNOBS ──
  alter table public.battles drop constraint battles_kind_check, add constraint battles_kind_check check (kind in ('PROBE', 'ATTACK', 'RAID'));
  create index battles_raid_done on public.battles (resolves_at) where kind = 'RAID' and status <> 'FIGHTING';
  insert into public.world_config (key, value, description) values
    ('pirate_strike_minutes', to_jsonb(5), '0427: a hunting pirate ship strikes a merchant at most once in this many minutes (public.pirate_strikes). Decided by default.'),
    ('pirate_strikes_per_run', to_jsonb(2), '0427: at most this many raids are opened a minute by the pirates'' job (public.pirate_strikes): 2 = at most 120 an hour. 0 stops every new raid (running ones close).'),
    ('pirate_strike_tries_per_run', to_jsonb(8), '0427: at most this many hunting pirates are asked a minute for a target (each one read of the sailing voyages), in a turning order.'),
    ('raid_keep_hours', to_jsonb(48), '0427: a closed RAID battle (sides, rounds, stances by cascade) is deleted this many hours after it closed, by public.pirate_strikes, at most 20 a run.');
  update public.world_config set value = to_jsonb(1),
         description = description || ' 0427: 5 -> 1 (the owner, 2026-11-15: "spawn rate of pirates should be faster alot").'
   where key = 'pirate_add_minutes' and value = to_jsonb(5);
  if not found then v_kept := v_kept || 'pirate_add_minutes '; end if;
  update public.world_config set value = to_jsonb(5),
         description = description || ' 0427: 60 -> 5 (a wreck lies five minutes at home, then is paid for, mended and manned).'
   where key = 'pirate_respawn_minutes' and value = to_jsonb(60);
  if not found then v_kept := v_kept || 'pirate_respawn_minutes '; end if;
  update public.world_config set value = to_jsonb(0.006),
         description = description || ' 0427: 0.0024 -> 0.006 (2.28 M -> 5.7 M a day of a 951 M hoard; 2026-11-14 spent 5.21 M and laid 79 fleets up unpaid until 00:00 UTC).'
   where key = 'pirate_spend_day_pct' and value = to_jsonb(0.0024);
  if not found then v_kept := v_kept || 'pirate_spend_day_pct '; end if;

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.raid_target(p_pirate uuid, p_now timestamptz)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0427: THE MERCHANT A PIRATE SETS UPON: the nearest within attack_reach_nm of her (voyage.fleet_point, the one "where is a fleet"), at sea or at
-- anchor and free; a company's merchant, a crown's cargo ship or a player's ship (public.fleet_kind MERCHANT, CARGO_SHIP, COMPANY), never one of the
-- pirates' own country, never one set upon in the last attack_ship_minutes, with a hull left. The sailing voyages are read once, each placed roughly
-- between her two harbours by the clock (a sieve, reach + 120 miles); the nearest 8 are then placed exactly. Null: nobody in reach.
declare
  v_lat   float8;
  v_lon   float8;
  v_reach numeric := public.wc_num('attack_reach_nm');
  v_rest  int := public.wc_int('attack_ship_minutes');
  v_pir   uuid := public.pirate_nation();
  v_nm    numeric;
  r       record;
begin
  select pt.lat::float8, pt.lon::float8 into v_lat, v_lon from voyage.fleet_point(p_pirate, p_now) pt;
  if v_lat is null or v_reach is null then
    return null;
  end if;
  for r in
    select c.id
      from (select s.id, s.nm
              from (select f.id, voyage.gc_distance_nm(v_lat, v_lon,
                                   (a.lat + (b.lat - a.lat) * w.k)::float8, (a.lon + (b.lon - a.lon) * w.k)::float8)::numeric as nm
                      from public.voyages v
                      join public.fleets f on f.id = v.fleet_id
                      join public.players pl on pl.id = f.player_id
                      join public.ports a on a.id = v.origin_port_id
                      join public.ports b on b.id = v.dest_port_id
                     cross join lateral (select least(1, greatest(0, extract(epoch from p_now - v.departed_at)
                                                                   / nullif(extract(epoch from v.eta - v.departed_at), 0)))::numeric as k) w
                     where v.status = 'SAILING' and f.status = 'SAILING' and f.busy_until is null and pl.nation_id is distinct from v_pir
                    union all
                    select f.id, voyage.gc_distance_nm(v_lat, v_lon, f.lat::float8, f.lon::float8)::numeric
                      from public.fleets f join public.players pl on pl.id = f.player_id
                     where f.status = 'ANCHORED' and f.busy_until is null and f.lat is not null and pl.nation_id is distinct from v_pir) s
             where s.nm <= v_reach + 120
             offset 0) c
     where public.fleet_kind(c.id) in ('MERCHANT', 'CARGO_SHIP', 'COMPANY')
     order by c.nm, c.id
     limit 8
  loop
    continue when exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                           where bs.fleet_id = r.id and bs.side = 'DEFENDER' and b.started_at > p_now - make_interval(mins => v_rest));
    continue when not exists (select 1 from public.ships s where s.fleet_id = r.id and s.durability > 0);
    select voyage.gc_distance_nm(v_lat, v_lon, pt.lat::float8, pt.lon::float8)::numeric into v_nm from voyage.fleet_point(r.id, p_now) pt;
    if v_nm <= v_reach then
      return r.id;
    end if;
  end loop;
  return null;
end
$body$;
$f$;

  execute $f$
create function public.pirate_strike(p_fleet uuid, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0427: ONE PIRATE STRIKES, the one place a pirate opens a battle. Answers OFF (attacks or the pirates dark), NOT_HUNTING (not in
-- public.pirate_ships_cruising or not free), RESTING (she struck within pirate_strike_minutes), NO_TARGET (public.raid_target), BUSY (her row or
-- the merchant's is held right now: taken now or not at all, so the job never waits on the beat or a press) or STRUCK: public.battle_open, kind RAID.
declare
  v_t uuid;
  v_n int := 0;
  r   record;
begin
  if not (public.attack_on() and public.pirates_on()) then
    return 'OFF';
  end if;
  if not exists (select 1 from public.pirate_ships_cruising c join public.fleets f on f.id = c.fleet_id where c.fleet_id = p_fleet and f.busy_until is null) then
    return 'NOT_HUNTING';
  end if;
  if exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id
              where bs.fleet_id = p_fleet and bs.side = 'ATTACKER' and b.kind = 'RAID'
                and bs.joined_at > p_now - make_interval(mins => public.wc_int('pirate_strike_minutes'))) then
    return 'RESTING';
  end if;
  v_t := public.raid_target(p_fleet, p_now);
  if v_t is null then
    return 'NO_TARGET';
  end if;
  for r in select f.id from public.fleets f where f.id in (p_fleet, v_t) order by f.id for update skip locked loop
    v_n := v_n + 1;
  end loop;
  if v_n < 2 then
    return 'BUSY';
  end if;
  perform public.battle_open('RAID', p_fleet, v_t, p_now);
  return 'STRUCK';
end
$body$;
$f$;

  execute $f$
create function public.pirate_strikes(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0427: THE PIRATES STRIKE, once a minute, from public.tick_pirates (after its steps, its add and its pay; never behind a trade's locks). The hunting
-- pirates not resting, in an order that turns with the minute, are asked in turn (public.pirate_strike, each in a block of her own: a fault is one
-- warning and the next is asked) until pirate_strikes_per_run have struck or pirate_strike_tries_per_run have been asked. Then the retention: closed
-- RAID battles older than raid_keep_hours, at most 20. Never raises. Answers {each answer: count, kept_out}.
declare
  v_max   int := coalesce(public.wc_int('pirate_strikes_per_run'), 0);
  v_tries int := coalesce(public.wc_int('pirate_strike_tries_per_run'), 0);
  v_rest  int := public.wc_int('pirate_strike_minutes');
  v_turn  text := floor(extract(epoch from p_now) / 60)::bigint::text;
  v_n     int := 0;
  v_k     int := 0;
  v_s     text;
  v_out   jsonb := '{}'::jsonb;
  v_gone  int := 0;
  r       record;
begin
  begin
    if v_max > 0 and v_tries > 0 and public.attack_on() and public.pirates_on() then
      for r in select c.fleet_id
                 from public.pirate_ships_cruising c join public.fleets f on f.id = c.fleet_id
                where f.busy_until is null
                  and not exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                                   where bs.fleet_id = c.fleet_id and bs.side = 'ATTACKER' and b.kind = 'RAID'
                                     and bs.joined_at > p_now - make_interval(mins => v_rest))
                order by md5(c.fleet_id::text || v_turn), c.fleet_id loop
        exit when v_n >= v_max or v_k >= v_tries;
        v_k := v_k + 1;
        begin
          v_s := public.pirate_strike(r.fleet_id, p_now);
        exception when others then
          raise warning 'pirate_strikes: fleet % did not strike (SQLSTATE %: %)', r.fleet_id, sqlstate, sqlerrm;
          v_s := 'ERROR';
        end;
        v_out := v_out || jsonb_build_object(v_s, coalesce((v_out ->> v_s)::int, 0) + 1);
        if v_s = 'STRUCK' then
          v_n := v_n + 1;
        end if;
      end loop;
    end if;
    with gone as (
      delete from public.battles b
       where b.id in (select x.id from public.battles x
                       where x.kind = 'RAID' and x.status <> 'FIGHTING' and x.resolves_at < p_now - make_interval(hours => public.wc_int('raid_keep_hours'))
                       order by x.resolves_at limit 20)
      returning 1)
    select count(*) into v_gone from gone;
  exception when others then
    raise warning 'pirate_strikes: the run stopped (SQLSTATE %: %)', sqlstate, sqlerrm;
    v_out := v_out || jsonb_build_object('ERROR', coalesce((v_out ->> 'ERROR')::int, 0) + 1);
  end;
  return v_out || jsonb_build_object('kept_out', v_gone);
end
$body$;
$f$;

  execute $f$
create function public.raid_close(p_battle uuid, p_fight jsonb, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0427: WHAT A RAID'S END DOES beyond the hulls. Called by public.battle_resolve alone, for kind RAID, under the battle's lock, once, after
-- public.navy_close (p_fight carries its {navy}). Gold, then the hands, then a wreck, then the merchant's report if she is a player's:
--   won (PLUNDERED or RANSOM): a crown's cargo ship's funds aboard, loot_share of them, to the pirate's home (public.pirate_loot_book, LOOT); any
--     other merchant pays a ransom from her company's purse (public.pirate_ransom: ransom_share of her cargo at cost, what the purse holds, RANSOM).
--   thrown back or broken off: the pirate loses attack_crew_lost.beaten of her hands, the merchant drove_off; boarded: the merchant loses boarded.
--   every hull of a side at 0 at sea: a wreck now, by 0322's rule (a player's ship is never a wreck: public.npc_wrecked).
-- Moved, never made. Answers {raid: {pirate, merchant, merchant_kind, taken}}.
declare
  v_a     uuid;
  v_aname text;
  v_d     uuid;
  v_dp    uuid;
  v_dname text;
  v_human boolean;
  v_kind  text;
  v_out   text := p_fight ->> 'outcome';
  v_broke boolean := coalesce((p_fight ->> 'broke_off')::boolean, false);
  v_rates jsonb := public.wc('attack_crew_lost');
  v_gold  bigint := 0;
  v_x     uuid;
  v_voy   public.voyages%rowtype;
  v_line  text;
begin
  select bs.fleet_id, f.name into v_a, v_aname
    from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
   where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';
  select bs.fleet_id, f.player_id, f.name, not p.is_npc into v_d, v_dp, v_dname, v_human
    from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id join public.players p on p.id = f.player_id
   where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';
  perform 1 from public.fleets f where f.id = v_d for update;
  v_kind := public.fleet_kind(v_d);

  if v_out in ('PLUNDERED', 'RANSOM') then
    if v_kind = 'CARGO_SHIP' then
      v_gold := public.pirate_loot_book(v_a, v_d, public.wc_num('loot_share'), null);
    else
      v_gold := public.pirate_ransom(v_a, v_dp, public.fleet_stock_at_cost(v_d), null);
    end if;
  end if;

  if v_out = 'DRIVEN_OFF' or v_broke then
    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_a, s.crew, (v_rates ->> 'beaten')::numeric)) where s.fleet_id = v_a;
    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_d, s.crew, (v_rates ->> 'drove_off')::numeric)) where s.fleet_id = v_d;
  elsif v_out = 'PLUNDERED' then
    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_d, s.crew, (v_rates ->> 'boarded')::numeric)) where s.fleet_id = v_d;
  end if;

  foreach v_x in array array[v_d, v_a] loop
    if exists (select 1 from public.ships s where s.fleet_id = v_x)
       and not exists (select 1 from public.ships s where s.fleet_id = v_x and s.durability > 0)
       and public.npc_wrecked(v_x) then
      select * into v_voy from public.voyages v where v.fleet_id = v_x and v.status = 'SAILING';
      if v_voy.id is not null then
        perform voyage.npc_wreck(v_x, v_voy.id, v_voy.last_settled_day + 1);
      end if;
    end if;
  end loop;

  if v_human then
    v_line := case when v_out = 'NO_FIGHT' then 'Pirates came up, and there was no fight.'
                   when coalesce((p_fight ->> 'slipped')::boolean, false) then 'We saw the pirates first and slipped away.'
                   when coalesce((p_fight ->> 'stood_off')::boolean, false) or v_broke then 'The pirates broke off.'
                   when v_out = 'DRIVEN_OFF' then 'Pirates came alongside, and we threw them back.'
                   when v_out = 'RANSOM' then 'Pirates came alongside, and we paid them off.'
                   when v_out = 'PLUNDERED' then 'Pirates boarded us.'
                   else 'Pirates came up, and we kept clear of them.' end;
    perform public.emit_event(v_dp, 'BATTLE_REPORT', jsonb_build_object(
      'fleet', v_dname, 'battle_id', p_battle, 'outcome', v_out, 'raid', true, 'pirate', v_aname, 'lost', v_gold,
      'lines', jsonb_build_array(v_line) || case when p_fight #>> '{navy,line}' is not null then jsonb_build_array(p_fight #>> '{navy,line}') else '[]'::jsonb end,
      'fights', '[]'::jsonb));
  end if;
  return jsonb_build_object('raid', jsonb_build_object('pirate', v_aname, 'merchant', v_dname, 'merchant_kind', v_kind, 'taken', v_gold));
end
$body$;
$f$;

  revoke all on function public.raid_target(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_strike(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_strikes(timestamptz) from public, anon, authenticated;
  revoke all on function public.raid_close(uuid, jsonb, timestamptz) from public, anon, authenticated;

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0427 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0427 values
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1,
$h$  if p_kind is null or p_kind not in ('PROBE', 'ATTACK') then   -- 0327: ATTACK comes from public.attack_for alone$h$,
$h$  if p_kind is null or p_kind not in ('PROBE', 'ATTACK', 'RAID') then   -- 0327: ATTACK comes from public.attack_for alone; 0427: RAID from public.pirate_strike alone$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 2,
$h$  if not (select p.is_npc from public.players p where p.id = d.player_id) then
    raise exception 'E_HUMAN_TARGET: no player fights another player' using errcode = 'P0001';
  end if;$h$,
$h$  -- 0427: a RAID is a pirate ship's, on a merchant; a pirate is no player, so she may set upon a player's ship. Every other kind keeps the law: no player fights another player.
  if p_kind = 'RAID' and (not exists (select 1 from public.pirate_ships x where x.fleet_id = p_attacker)
                          or (select p.is_npc from public.players p where p.id = a.player_id) is not true
                          or public.fleet_kind(p_defender) not in ('MERCHANT', 'CARGO_SHIP', 'COMPANY')) then
    raise exception 'E_BAD_TARGET: a raid is a pirate ship''s, on a merchant' using errcode = 'P0001';
  end if;
  if p_kind is distinct from 'RAID' and not (select p.is_npc from public.players p where p.id = d.player_id) then
    raise exception 'E_HUMAN_TARGET: no player fights another player' using errcode = 'P0001';
  end if;$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 3,
$h$  if p_kind = 'ATTACK' then   -- 0333: her country answers; a probe calls nobody$h$,
$h$  if p_kind in ('ATTACK', 'RAID') then   -- 0333: her country answers; a probe calls nobody (0427: a raid is fought as an attack is)$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$h$    update public.battles set result = result || v_spoils where id = p_battle;
  end if;$h$,
$h$    update public.battles set result = result || v_spoils where id = p_battle;
  elsif b.kind = 'RAID' then   -- 0427: a pirate's raid: the navy called is freed first, then her plunder, the hands, a wreck and a player's report (public.raid_close), once, under this row's lock
    v_spoils := public.navy_close(p_battle, p_now);
    v_spoils := v_spoils || public.raid_close(p_battle, v_f || v_spoils, p_now);
    update public.battles set result = result || v_spoils where id = p_battle;
  end if;$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$  return jsonb_build_object('steps', v_steps, 'pressure', v_press, 'added', v_add, 'paid', v_paid);$h$,
$h$  -- 0427: THE PIRATES STRIKE (public.pirate_strikes, which never raises): after the steps, the add and the pay, and never behind a trade's locks, as they are
  return jsonb_build_object('steps', v_steps, 'pressure', v_press, 'added', v_add, 'paid', v_paid)
         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('struck', public.pirate_strikes(p_now)) else '{}'::jsonb end;$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$      'raids_paid', (select loot.n from loot)))$h$,
$h$      'raids_paid', (select loot.n from loot),
      -- 0427: THE BATTLES of the window (public.battles; a closed RAID is kept raid_keep_hours): raids the pirates opened on merchants, how those that closed
      -- in it ended (the pirates won: PLUNDERED or RANSOM; else the merchant held), those the navy came to, and players' attacks
      'raids', (select count(*) from public.battles b where b.kind = 'RAID' and b.started_at > p_since and b.started_at <= p_now),
      'raids_won', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                      and b.result ->> 'outcome' in ('PLUNDERED', 'RANSOM')),
      'raids_held', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                       and coalesce(b.result ->> 'outcome', '') not in ('PLUNDERED', 'RANSOM')),
      'raids_navy', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                       and coalesce((b.result #>> '{navy,came}')::int, 0) > 0),
      'attacks', (select count(*) from public.battles b where b.kind = 'ATTACK' and b.started_at > p_since and b.started_at <= p_now)))$h$),
  ('world.stats_fleets()', 1,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'raids_paid')::int), 0) as raids$h$,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'raids_paid')::int), 0) as raids,
                              coalesce(sum((x.figures -> 'win' ->> 'raids')::int), 0) as b_raids,          -- 0427: the battles
                              coalesce(sum((x.figures -> 'win' ->> 'raids_won')::int), 0) as b_won,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_held')::int), 0) as b_held,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_navy')::int), 0) as b_navy,
                              coalesce(sum((x.figures -> 'win' ->> 'attacks')::int), 0) as b_attacks$h$),
  ('world.stats_fleets()', 2,
$h$           'cargo', f.figures -> 'cargo') end$h$,
$h$           'cargo', f.figures -> 'cargo',
           -- 0427: THE BATTLES of the last 24 hours: raids opened, won by the pirates, held by the merchants, the navy came to; players' attacks; and the navy's fights with pirates
           'battles', jsonb_build_object('raids_day', d.b_raids, 'won_day', d.b_won, 'held_day', d.b_held, 'navy_day', d.b_navy,
                                         'attacks_day', d.b_attacks, 'navy_fights_day', d.fights)) end$h$);

  for v_h in select h.fn from hunks_0427 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0427 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0427 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0427 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0427 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0427 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q))) and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0427 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0427 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or exists (select 1 from unnest(c_new) f join public.client_rpc_entry_points() e on e.fn = f::regprocedure) then
    raise exception '0427 self-assert FAIL: a function of this file is open to clients';
  end if;
  if public.wc_int('pirate_strike_minutes') <> 5 or public.wc_int('pirate_strikes_per_run') <> 2 or public.wc_int('pirate_strike_tries_per_run') <> 8
     or public.wc_int('raid_keep_hours') <> 48
     or (v_kept not like '%pirate_add_minutes%' and public.wc_int('pirate_add_minutes') <> 1)
     or (v_kept not like '%pirate_respawn_minutes%' and public.wc_int('pirate_respawn_minutes') <> 5)
     or (v_kept not like '%pirate_spend_day_pct%' and public.wc_num('pirate_spend_day_pct') <> 0.006) then
    raise exception '0427 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 6. THE NEWS (0347's law) ──
  perform public.news_update('0427', 'Pirates strike merchants at sea; more pirates sail, and sooner',
                             '해적이 바다의 상선을 습격한다; 더 많은 해적이 더 빨리 출항한다');

  -- ── 7. THE PROBE, rolled back by a raised sentinel ──
  --   (a) a ship that is not a pirate's cannot open a RAID: E_BAD_TARGET, before any row is written (two merchants of the world, both free);
  --   (b) a hunting pirate of this world, if one has a merchant in reach, strikes through public.pirate_strike: STRUCK, and the battle is one RAID
  --       row with her the ATTACKER and a MERCHANT, CARGO_SHIP or COMPANY the DEFENDER. On prod nothing is left: the sentinel rolls it all back.
  begin
    update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'pirates_bite', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
    if public.attack_on() and public.pirates_on() then
      select c.fleet_id into v_p
        from public.pirate_ships_cruising c join public.fleets f on f.id = c.fleet_id
       where f.busy_until is null and public.raid_target(c.fleet_id, now()) is not null
       order by c.ord limit 1;
      if v_p is not null then
        v_s := public.pirate_strike(v_p, now());
        if v_s = 'STRUCK' then
          select b.kind, (select count(*) from public.battle_sides s where s.battle_id = b.id and s.side = 'ATTACKER' and s.fleet_id = v_p and s.how = 'OPENED') as att,
                 (select public.fleet_kind(s.fleet_id) from public.battle_sides s where s.battle_id = b.id and s.side = 'DEFENDER' and s.how = 'OPENED') as dk
            into v_b
            from public.battles b join public.battle_sides s0 on s0.battle_id = b.id and s0.fleet_id = v_p
           order by b.started_at desc limit 1;
          if v_b.kind is distinct from 'RAID' or v_b.att <> 1 or v_b.dk not in ('MERCHANT', 'CARGO_SHIP', 'COMPANY') then
            raise exception '0427 self-assert FAIL: the probe''s strike opened %', to_jsonb(v_b);
          end if;
          v_note := 'a hunting pirate struck a ' || v_b.dk || ' through public.pirate_strike (rolled back)';
        else
          v_note := 'the hunting pirate answered ' || v_s || ' (her merchant was held right now): proof 128 strikes one';
        end if;
      end if;
    end if;
    raise exception sqlstate 'BV427';
  exception when sqlstate 'BV427' then null;
  end;
  if exists (select 1 from public.battles b where b.kind = 'RAID') then
    raise exception '0427 self-assert FAIL: the probe left a raid standing';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0427 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0427 self-assert ok: THE PIRATES STRIKE. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 4 new functions, server-only; kind RAID. Knobs: pirate_add_minutes %, pirate_respawn_minutes %, pirate_spend_day_pct %, strike every % min, % a run.% Probe: %; % ms.',
    (select count(*) from hunks_0427), public.wc_int('pirate_add_minutes'), public.wc_int('pirate_respawn_minutes'), public.wc_num('pirate_spend_day_pct'),
    public.wc_int('pirate_strike_minutes'), public.wc_int('pirate_strikes_per_run'),
    case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0427;
end $m$;
