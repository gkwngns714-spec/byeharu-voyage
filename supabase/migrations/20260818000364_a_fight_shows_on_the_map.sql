-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0364 - A FIGHT SHOWS ON THE MAP: every battle being fought, and any battle's log for a watcher  (owner row 321)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 321 (2026-11-13): "i want a fight to be visible in map. in red circle surrounding all fleets. if more fleets participate, bigger circle. by clicking that
-- circle, like info i want to see the actual fight". The map needs two reads: where every battle is and who is in it, and one battle's log for anyone who looks.
--
-- NOTHING A PLAYER SEES CHANGES AT THIS DEPLOY. A timed battle exists only behind `attack_enabled` (false; the owner's switch; this file does not write it, nor any key). With no
-- battle row the first read answers an empty list and the second {on: false}.
-- news: none
--   (no ring can be drawn while attacks are dark; the news belongs to the step that lights attack_enabled, 0347's law)
--
-- WHICH FIGHTS ARE TIMED AND PLACED (read on the bodies at head 0357): a row of public.battles is written by public.battle_open alone, and its one caller is public.attack_for
-- (cmd.attack, a company's fleet on a cargo ship, a navy ship or a pirate ship; behind attack_enabled). A pirate raid on a voyage day (voyage.settle) and a navy ship against a
-- pirate ship (public.navy_fight, 0340: "ONE CALL, no timer, nobody watching") are settled in an instant and have no row here. So these reads serve a company's attack, with the
-- escorts and the called navy ships that join it, and nothing else.
--
-- WHAT IT ADDS (three functions and one index; no table, no column, no knob, no job, no write)
--   public.fight_card(battle, player)   ONE battle as the map draws it (server-only): id, status, lat and lon (battles.site: where the ship set upon was), the clock (started_at,
--                         resolves_at, round_seconds, rounds, rounds_done, next_at), `fleets` and `ships` (the sides that are THERE: arrives_at has come), `mine` (the caller's own
--                         fleet if she opened or was set upon, else null), and `sides`: every fleet of public.battle_sides with {fleet, name, side, how, kind (public.fleet_kind),
--                         company, nation, ships, here, at}. `at` [lat, lon] is voyage.fleet_point now, served while the battle is FIGHTING and she is there. Closed: `end`, the
--                         ending from the deck of the side that attacked (public.battle_log's word).
--   world.fights()        THE READ THE MAP POLLS: {on, now, keep_seconds, fights[]}. Every battle FIGHTING with a sheet (0357: fought round by round), and every such battle that
--                         ended within keep_seconds (60), oldest first, 50 at most. `on` is false when attacks are dark and no battle is served: the map then asks seldom.
--   world.fight(battle)   ANY BATTLE'S LOG, FOR A WATCHER: {on, battle, status, watch: true, mine, side: 'ATTACKER', you, foe, the clock, next_range, log}. The log is 0357's own
--                         (public.battle_log from the deck of the side that attacked, shape v 1), cut to a list of keys said below. It never advances a battle.
--   battles_ended         an index on (resolves_at) where status <> 'FIGHTING', so "ended within the last minute" is a range scan when the table has years of battles.
--
-- WHAT A WATCHER CAN SEE, AND WHY IT IS SAFE
--   Served: the place; the clock and the round; each fleet's name, what it is (company, merchant, cargo ship, navy, pirate), its company's name and country, its count of ships;
--   the ships of the side that attacked by name with hull points and crew; the other side's name, ships, crew and hull in sum; each round's range, shots, hits, damage, hull left
--   and the chance rolled to slip; the boarding's two crews; how it ended. These are the fight itself: the owner asked that anyone may watch it.
--   NOT served, and held by the self-assert and proof 66: loot, crew_lost, the navy line and the pre-fight word (world.battle serves those to her alone); a stance or the stances
--   she may take; any purse, cargo, cargo value, funds aboard, route or destination. The log is cut to (v, atk, first, foe, you, r, board, after, end): a key a later file adds to
--   a log does not reach a watcher until a file says so here.
--   NO PLAYER FIGHTS A PLAYER (public.battle_open and public.attack_for refuse; not touched), so a ring is never a way to find a company to attack: nobody can attack one.
--   What is new: until now no read told one company where another's fleet was. A battle's ring does, for the minutes it is fought. The owner asked for it; it is said in the
--   dev-log as a default the owner may reverse.
--
-- SUPERSEDES, BY RE-CUT: public.client_rpc_entry_points (1 hunk, once, reversing), anchored on 0357's own `world.battle` row, a line no other open file cuts
--   (0354: ship_moves; 0355: promote_captain; 0356: levels; 0357: preview_attack; 0360: route_legs; 0358, 0361, 0362, 0363 do not cut it: read on origin/batch-5).
--
-- COST: world.fights() with no battle: one identity probe, two index scans of empty ranges, one knob read. Per battle served: one row, its sides (primary key), a count of ships a
--   side (ships_fleet_id), one voyage.fleet_point a side that is there. Local timings: docs/dev-log/2026-11-13-fight-rings.md. world.fight re-runs the sheet's fight to the rounds
--   logged, as world.battle does.
-- ROLLBACK (forward, owner only): attack_enabled false: no new battle, so no ring after the running ones end. The whole slice: scripts/ops/harness/fight-rings/rollback-0364.sql.
-- SELF-ASSERT: ONE DO block, statement_timeout 30 s, lock_timeout 5 s first; fails above 20 s. The catalog, then a probe battle of this file's own rows, lit inside a subtransaction
--   that a raised sentinel rolls back. No table is counted or summed.
-- LOCKS: CREATE INDEX on public.battles (SHARE; no row on prod), under lock_timeout 5 s.
-- VERSION: 0364, cut on the bodies at head 0357 (it needs 0357's sheet and public.battle_log). 0358 to 0363 share no function with it.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_tp         timestamptz := clock_timestamp();
  v_ms         jsonb := '{}'::jsonb;
  c_reg        constant text := 'public.client_rpc_entry_points()';
  c_new_fns    constant text[] := array['public.fight_card(uuid,uuid)', 'world.fights()', 'world.fight(uuid)'];
  c_doors      constant text[] := array['world.fights()', 'world.fight(uuid)'];
  c_keys       constant text[] := array['v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end'];
  c_old        constant text := $h$      ('world',       'battle',                'uuid'),
$h$;
  c_new        constant text := $h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$;
  v_fn_before  text;
  v_cfg_before text;
  v_rel_before text;
  v_def0       text;
  v_def        text;
  v_p0         record;
  v_p          record;
  v_entry      int;
  v_src        text;
  v_lived      boolean := false;
  v_pl         uuid;
  v_pl2        uuid;
  v_npc        uuid;
  v_fl         uuid;
  v_fl2        uuid;
  v_nfl        uuid;
  v_lis        uuid;
  v_bat        uuid;
  v_t          timestamptz;
  v_r          jsonb;
  v_c          jsonb;
  v_w          jsonb;
  v_own        jsonb;
  v_one_ms     numeric;
  v_tq         timestamptz;
  v_note       text := '';
  c_uid   constant uuid := '00000000-0364-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0364-4000-8000-000000000002';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('world.fights()') is not null or to_regprocedure('world.fight(uuid)') is not null or to_regprocedure('public.fight_card(uuid,uuid)') is not null
     or to_regclass('public.battles_ended') is not null then
    raise exception '0364 refuses: it has been applied once';
  end if;
  if to_regprocedure('world.battle(uuid)') is null or to_regprocedure('public.battle_log(jsonb,jsonb,text)') is null or to_regprocedure('public.battle_fight(uuid,integer)') is null
     or to_regprocedure('public.fleet_kind(uuid)') is null or to_regprocedure('public.crown_nation(uuid)') is null or to_regprocedure('public.attack_on()') is null
     or to_regprocedure('voyage.fleet_point(uuid,timestamp with time zone)') is null or to_regprocedure('public.current_player_id()') is null
     or to_regprocedure('public.battle_open(text,uuid,uuid,timestamp with time zone)') is null or to_regprocedure('cmd.assume_identity(uuid)') is null
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.battles'::regclass and a.attname = 'sheet' and not a.attisdropped) then
    raise exception '0364 refuses: a function or a column it reads is not in this world (0308 / 0327 / 0333 / 0357)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_def0 := replace(pg_get_functiondef(c_reg::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg into v_p0 from pg_proc p where p.oid = c_reg::regprocedure;
  if (length(v_def0) - length(replace(v_def0, c_old, ''))) / length(c_old) is distinct from 1 then
    raise exception '0364 slice: the registry''s world.battle row occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against',
      (length(v_def0) - length(replace(v_def0, c_old, ''))) / length(c_old);
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_reg::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p') and c.relname <> 'battles_ended';
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- ── 2. THE INDEX ──
  create index battles_ended on public.battles (resolves_at) where status <> 'FIGHTING';
  comment on index public.battles_ended is '0364: the battles that are over, by when they ended: world.fights() reads the last minute of it.';

  -- ── 3. THE CARD (server-only) ──
  execute $f$
create function public.fight_card(p_battle uuid, p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0364: ONE BATTLE AS THE MAP DRAWS IT. Its place is battles.site (where the ship set upon was at the open). `fleets` and `ships` count the sides that are THERE (arrives_at
  -- has come: a called ship still on her way is listed with here false and counts for nothing). `mine` is the caller's own fleet when she opened it or was set upon. A side's `at`
  -- is where she is now (voyage.fleet_point), served only while the battle is being fought. Closed, `end` is how it ended from the deck of the side that attacked
  -- (public.battle_log). Names, kinds and counts only: no purse, no cargo, no loot. Null for a battle with no sheet (a probe: nothing to watch) or none.
  select jsonb_build_object(
           'id', b.id, 'status', b.status, 'lat', (b.site ->> 'lat')::numeric, 'lon', (b.site ->> 'lon')::numeric,
           'started_at', b.started_at, 'resolves_at', b.resolves_at, 'round_seconds', b.round_seconds,
           'rounds', jsonb_array_length(public.wc('fight_ranges')), 'rounds_done', b.rounds_done,
           'next_at', case when b.status = 'FIGHTING' then coalesce(b.next_round_at, b.resolves_at) end,
           'fleets', s.fleets, 'ships', s.ships, 'mine', s.mine, 'sides', s.sides)
         || case when b.status = 'FIGHTING' then '{}'::jsonb
                 else jsonb_build_object('end', public.battle_log(b.sheet, coalesce(b.result, '{"outcome": "NO_FIGHT"}'::jsonb), 'ATTACKER') ->> 'end') end
    from public.battles b
   cross join lateral (
     select (count(*) filter (where x.here))::int as fleets,
            coalesce(sum(x.ships) filter (where x.here), 0)::int as ships,
            (min(x.fleet_id::text) filter (where x.how = 'OPENED' and x.player_id = p_player))::uuid as mine,
            coalesce(jsonb_agg(jsonb_build_object(
                'fleet', x.fleet_id, 'name', x.name, 'side', x.side, 'how', x.how, 'kind', x.kind,
                'company', case when x.kind in ('COMPANY', 'MERCHANT') then x.company end,
                'nation', x.nation, 'ships', x.ships, 'here', x.here)
              || case when x.here and b.status = 'FIGHTING' and x.lat is not null then jsonb_build_object('at', jsonb_build_array(x.lat, x.lon)) else '{}'::jsonb end
              order by x.side, x.joined_at, x.how = 'CALLED', x.how = 'ESCORT', x.fleet_id), '[]'::jsonb) as sides
       from (select bs.fleet_id, bs.side, bs.how, bs.joined_at, f.name, f.player_id, k.kind, pl.company_name as company,
                    (select n.code from public.nations n where n.id = coalesce(public.crown_nation(f.id), pl.nation_id)) as nation,
                    (select count(*) from public.ships sh where sh.fleet_id = f.id)::int as ships,
                    h.here, pt.lat, pt.lon
               from public.battle_sides bs
               join public.fleets f on f.id = bs.fleet_id
               join public.players pl on pl.id = f.player_id
              cross join lateral (select public.fleet_kind(f.id) as kind) k
              cross join lateral (select bs.arrives_at <= case when b.status = 'FIGHTING' then now() else b.resolves_at end as here) h
               left join lateral (select p.lat, p.lon from voyage.fleet_point(f.id, now()) p where h.here and b.status = 'FIGHTING') pt on true
              where bs.battle_id = b.id) x
   ) s
   where b.id = p_battle and b.sheet is not null
$body$;
$f$;
  comment on function public.fight_card(uuid, uuid) is '0364: one battle as the map draws it: place, clock, the fleets on each side (name, kind, company, country, ships, where), whether it is the caller''s. Read by world.fights. Server-only.';

  -- ── 4. THE DOORS ──
  execute $f$
create function world.fights()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0364 (owner row 321): THE READ THE MAP POLLS. Every battle being fought round by round (0357: a battle with a sheet), and every such battle that ended within keep_seconds, so
-- the ring can show its ending before it goes; oldest first, 50 at most. Each is public.fight_card. `on` is false when attacks are dark and nothing is served: the map then asks
-- seldom. A caller with no house: nothing. It never advances a battle: the minute job and the stance door do.
declare
  v_player uuid := public.current_player_id();
  c_keep   constant int := 60;
  v_f      jsonb;
begin
  if v_player is null then
    return jsonb_build_object('on', false, 'fights', '[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(public.fight_card(x.id, v_player) order by x.started_at, x.id), '[]'::jsonb) into v_f
    from (select q.id, q.started_at
            from (select b.id, b.started_at from public.battles b where b.status = 'FIGHTING' and b.sheet is not null
                  union all
                  select b.id, b.started_at from public.battles b
                   where b.status <> 'FIGHTING' and b.resolves_at > now() - make_interval(secs => c_keep) and b.sheet is not null) q
           order by q.started_at, q.id limit 50) x;
  return jsonb_build_object('on', public.attack_on() or jsonb_array_length(v_f) > 0, 'now', now(), 'keep_seconds', c_keep, 'fights', v_f);
end
$body$;
$f$;
  comment on function world.fights() is
    '0364: the read the map polls: every battle being fought round by round and those ended within keep_seconds (60): place, clock, the fleets on each side, whether it is the caller''s. Stable; it never advances. {on, now, keep_seconds, fights[]}.';
  revoke all on function world.fights() from public, anon;
  grant execute on function world.fights() to authenticated;

  execute $f$
create function world.fight(p_battle uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0364 (owner row 321): ANY BATTLE'S LOG, FOR A WATCHER. The shape world.battle serves her own in, so ONE client face draws both, with `watch` true and without what is hers
-- alone: no stance, no `may`, no pre-fight word, no loot, no crew_lost, no navy line. The log is public.battle_log from the deck of the side that attacked (shape v 1), cut to
-- the keys named here: a key a later file adds does not reach a watcher. While FIGHTING it is the fight to the rounds logged and nothing past them: no boarding, no ending.
-- `mine`: the caller's own fleet when the battle is hers (the client then shows her own card, with her stance). No such battle, or a caller with no house: {on: false}.
declare
  v_player uuid := public.current_player_id();
  b        public.battles%rowtype;
  v_f      jsonb;
  v_n      int := jsonb_array_length(public.wc('fight_ranges'));
begin
  if v_player is null then
    return jsonb_build_object('on', false);
  end if;
  select * into b from public.battles where id = p_battle and sheet is not null;
  if b.id is null then
    return jsonb_build_object('on', false);
  end if;
  if b.status = 'FIGHTING' then
    -- world.battle's own lines (0357): proof 66 holds the two logs equal for the side that attacked, at every stage
    v_f := public.battle_fight(b.id, greatest(1, b.rounds_done)) - 'board';
    if b.rounds_done = 0 then
      v_f := v_f || jsonb_build_object('rounds', '[]'::jsonb, 'rounds_fought', 0, 'hull_lost', jsonb_build_object('a', '{}'::jsonb, 'b', '{}'::jsonb));
    end if;
    v_f := v_f || jsonb_build_object('open', true, 'outcome', null);
  else
    v_f := coalesce(b.result, '{"outcome": "NO_FIGHT"}'::jsonb);
  end if;
  return jsonb_build_object(
    'on', true, 'battle', b.id, 'status', b.status, 'watch', true, 'side', 'ATTACKER', 'you', b.sheet -> 'you', 'foe', b.sheet -> 'foe',
    'mine', (select bs.fleet_id from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
              where bs.battle_id = b.id and bs.how = 'OPENED' and f.player_id = v_player order by bs.fleet_id limit 1),
    'started_at', b.started_at, 'resolves_at', b.resolves_at, 'now', now(), 'round_seconds', b.round_seconds, 'rounds', v_n, 'rounds_done', b.rounds_done,
    'next_at', case when b.status = 'FIGHTING' then coalesce(b.next_round_at, b.resolves_at) end,
    'next_range', case when b.status = 'FIGHTING' and b.rounds_done < v_n and b.next_round_at is distinct from b.resolves_at then public.wc('fight_ranges') -> b.rounds_done ->> 0 end,
    'log', (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
              from jsonb_each(public.battle_log(b.sheet, v_f, 'ATTACKER')) e
             where e.key in ('v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end')));
end
$body$;
$f$;
  comment on function world.fight(uuid) is
    '0364: any battle''s log for a watcher, in world.battle''s shape with watch true: the clock, the two names, the log from the deck of the side that attacked, cut to a fixed list of keys. No stance, word, loot, crew_lost or navy line. Stable; it never advances. None: {on: false}.';
  revoke all on function world.fight(uuid) from public, anon;
  grant execute on function world.fight(uuid) to authenticated;
  revoke all on function public.fight_card(uuid, uuid) from public, anon, authenticated;

  -- ── 5. THE REGISTRY (one hunk, once) ──
  execute replace(v_def0, c_old, c_new);

  v_ms := v_ms || jsonb_build_object('made_and_cut', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 6. THE SELF-ASSERT: the catalog ──
  v_def := replace(pg_get_functiondef(c_reg::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) is distinct from 1 or replace(v_def, c_new, c_old) is distinct from v_def0 then
    raise exception '0364 self-assert FAIL: the registry''s hunk is not in the new body exactly once, or it does not reverse to its pre-image';
  end if;
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg into v_p from pg_proc p where p.oid = c_reg::regprocedure;
  if v_p.acl is distinct from v_p0.acl or v_p.vol is distinct from v_p0.vol or v_p.secdef is distinct from v_p0.secdef or v_p.cfg is distinct from v_p0.cfg then
    raise exception '0364 self-assert FAIL: the registry changed its ACL, volatility, definer or config';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) is distinct from v_entry + 2
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array['world.fights()'::regprocedure, 'world.fight(uuid)'::regprocedure])) is distinct from 2 then
    raise exception '0364 self-assert FAIL: the two doors are not registered once each';
  end if;
  if exists (select 1 from unnest(c_new_fns) f cross join unnest(array['anon', 'authenticated']) r(role)
              where has_function_privilege(r.role, f, 'execute') and not (r.role = 'authenticated' and f = any (c_doors)))
     or exists (select 1 from unnest(c_doors) f where not has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0364 self-assert FAIL: a client may call the card, anon may call a door, or a door is not granted to authenticated';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where (select p.provolatile from pg_proc p where p.oid = f::regprocedure) is distinct from 's') then
    raise exception '0364 self-assert FAIL: a read is not STABLE';
  end if;
  -- no new function writes, advances a battle, or names a purse, a hold, loot or a stance
  for v_src in select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') from pg_proc p where p.oid = any (select f::regprocedure::oid from unnest(c_new_fns) f) loop
    if v_src ~* '\m(insert|update|delete|execute|perform)\M' or v_src ~* '\m(battle_advance|battle_resolve|tick_battles|battle_sides_come)\M'
       or v_src ~* '\m(ducats|cargo|cargo_basis|funds|loot|crew_lost|stance|ledger)\M' then
      raise exception '0364 self-assert FAIL: a read of this file writes, advances a battle, or names a purse, a hold, loot or a stance';
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_new_fns || c_reg) f)) is distinct from v_fn_before then
    raise exception '0364 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before then
    raise exception '0364 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p') and c.relname <> 'battles_ended') is distinct from v_rel_before
     or to_regclass('public.battles_ended') is null then
    raise exception '0364 self-assert FAIL: a relation other than the one index was made or dropped';
  end if;
  -- a caller with no house reads nothing
  if world.fights() is distinct from '{"on": false, "fights": []}'::jsonb or world.fight(gen_random_uuid()) is distinct from '{"on": false}'::jsonb then
    raise exception '0364 self-assert FAIL: a caller with no house read something: %', world.fights();
  end if;

  v_ms := v_ms || jsonb_build_object('catalog', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 7. THE PROBE, on this file's own rows, rolled back by a raised sentinel ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Ronda 0364', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa Vizinha 0364', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl2;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0364', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Ronda', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Ronda', true, true);
    v_fl2 := public.form_fleet(v_pl2, 'Vizinha', v_lis);
    perform public.commission_ship(v_pl2, v_fl2, 'barca', 'Vizinha', true, true);
    v_nfl := public.form_fleet(v_npc, 'Mercante', v_lis);
    perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante', true, true);
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.6 where id = v_nfl;
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.7, lon = -9.9 where id = v_fl;
    v_t := date_trunc('second', now());

    -- (a) DARK, with a house and no battle of this probe: the map's read serves none of ours, and a battle that is none is {on: false}
    perform cmd.assume_identity(c_uid2);
    v_r := world.fights();
    if not public.attack_on() and ((v_r ->> 'on')::boolean is not false or v_r -> 'fights' is distinct from '[]'::jsonb) and not exists (select 1 from public.battles b where b.sheet is not null) then
      raise exception '0364 self-assert FAIL: dark and with no battle, the read is not {on: false, fights: []}: %', v_r;
    end if;
    if (v_r ->> 'keep_seconds')::int is distinct from 60 or world.fight(gen_random_uuid()) is distinct from '{"on": false}'::jsonb then
      raise exception '0364 self-assert FAIL: the keep time, or a battle that is none: %', v_r;
    end if;

    -- (b) LIT (here only; rolled back): her barca at anchor attacks a merchant's at anchor 18 miles off
    update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
    v_bat := public.battle_open('ATTACK', v_fl, v_nfl, v_t);
    v_tq := clock_timestamp();
    v_r := world.fights();
    v_one_ms := round(extract(epoch from clock_timestamp() - v_tq) * 1000, 1);
    select e into v_c from jsonb_array_elements(v_r -> 'fights') e where e ->> 'id' = v_bat::text;
    if (v_r ->> 'on')::boolean is not true or v_c is null or v_c ->> 'status' is distinct from 'FIGHTING'
       or (v_c ->> 'lat')::numeric is distinct from 38.5 or (v_c ->> 'lon')::numeric is distinct from -9.6
       or (v_c ->> 'fleets')::int is distinct from 2 or (v_c ->> 'ships')::int is distinct from 2 or v_c -> 'mine' is distinct from 'null'::jsonb
       or (v_c ->> 'rounds')::int is distinct from jsonb_array_length(public.wc('fight_ranges')) or (v_c ->> 'rounds_done')::int is distinct from 0
       or (v_c ->> 'next_at')::timestamptz is distinct from v_t + make_interval(secs => (v_c ->> 'round_seconds')::int)
       or (v_c ->> 'started_at')::timestamptz is distinct from v_t or v_c ? 'end' or jsonb_array_length(v_c -> 'sides') is distinct from 2
       or v_c -> 'sides' -> 0 is distinct from jsonb_build_object('fleet', v_fl, 'name', 'Ronda', 'side', 'ATTACKER', 'how', 'OPENED', 'kind', 'COMPANY', 'company', 'Casa da Ronda 0364',
                                                 'nation', 'PRT', 'ships', 1, 'here', true, 'at', jsonb_build_array(38.7, -9.9))
       or v_c -> 'sides' -> 1 is distinct from jsonb_build_object('fleet', v_nfl, 'name', 'Mercante', 'side', 'DEFENDER', 'how', 'OPENED', 'kind', 'COMPANY', 'company', 'Casa Mercante 0364',
                                                 'nation', 'PRT', 'ships', 1, 'here', true, 'at', jsonb_build_array(38.5, -9.6)) then
      raise exception '0364 self-assert FAIL: the card of a battle a neighbour reads: %', v_c;
    end if;
    -- the card's keys, and a side's, are the lists said in the header: nothing else can ride out on them
    if exists (select 1 from jsonb_object_keys(v_c) k where k <> all (array['id', 'status', 'lat', 'lon', 'started_at', 'resolves_at', 'round_seconds', 'rounds', 'rounds_done', 'next_at', 'fleets', 'ships', 'mine', 'sides', 'end']))
       or exists (select 1 from jsonb_array_elements(v_c -> 'sides') s, jsonb_object_keys(s) k where k <> all (array['fleet', 'name', 'side', 'how', 'kind', 'company', 'nation', 'ships', 'here', 'at'])) then
      raise exception '0364 self-assert FAIL: the card carries a key this file does not name: %', v_c;
    end if;
    -- the watcher's read: watch, the two names, an open log with no round, and nothing that is hers alone
    v_w := world.fight(v_bat);
    if (v_w ->> 'on')::boolean is not true or (v_w ->> 'watch')::boolean is not true or v_w -> 'mine' is distinct from 'null'::jsonb or v_w ->> 'status' is distinct from 'FIGHTING'
       or v_w ->> 'you' is distinct from 'Ronda' or v_w ->> 'foe' is distinct from 'Mercante' or v_w ->> 'side' is distinct from 'ATTACKER'
       or v_w -> 'log' -> 'r' is distinct from '[]'::jsonb or v_w -> 'log' ? 'end' or v_w -> 'log' ? 'board' or (v_w -> 'log' ->> 'v')::int is distinct from 1 or (v_w -> 'log' ->> 'atk')::boolean is not true
       or v_w ->> 'next_range' is distinct from (public.wc('fight_ranges') -> 0 ->> 0)
       or exists (select 1 from jsonb_object_keys(v_w) k where k <> all (array['on', 'battle', 'status', 'watch', 'side', 'you', 'foe', 'mine', 'started_at', 'resolves_at', 'now', 'round_seconds', 'rounds', 'rounds_done', 'next_at', 'next_range', 'log']))
       or exists (select 1 from jsonb_object_keys(v_w -> 'log') k where k <> all (c_keys)) then
      raise exception '0364 self-assert FAIL: the watcher''s read before the first round: %', v_w;
    end if;
    -- her own reads: the card says it is hers, and the watcher's log is her own card's log, key for key
    perform cmd.assume_identity(c_uid);
    v_own := world.battle(v_fl);
    select e into v_c from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text;
    if v_c ->> 'mine' is distinct from v_fl::text or world.fight(v_bat) ->> 'mine' is distinct from v_fl::text
       or exists (select 1 from unnest(c_keys) k where (v_own -> 'log' -> k) is distinct from (v_w -> 'log' -> k)) then
      raise exception '0364 self-assert FAIL: her own battle is not said to be hers, or the watcher''s log is not her card''s: % against %', v_w -> 'log', v_own -> 'log';
    end if;
    -- round 1 at its instant: the watcher's log grows by the round her own card shows
    perform public.battle_resolve(v_bat, v_t + make_interval(secs => (v_c ->> 'round_seconds')::int));
    perform cmd.assume_identity(c_uid2);
    v_w := world.fight(v_bat);
    perform cmd.assume_identity(c_uid);
    v_own := world.battle(v_fl);
    if v_w ->> 'status' = 'FIGHTING' and (jsonb_array_length(v_w -> 'log' -> 'r') is distinct from 1 or v_w -> 'log' ? 'end' or v_w -> 'log' ? 'board' or (v_w ->> 'rounds_done')::int is distinct from 1)
       or exists (select 1 from unnest(c_keys) k where (v_own -> 'log' -> k) is distinct from (v_w -> 'log' -> k)) then
      raise exception '0364 self-assert FAIL: after the first round the watcher''s log is not her card''s, or it tells more than the round: % against %', v_w -> 'log', v_own -> 'log';
    end if;
    v_note := format('a probe battle: the card in %s ms, %s round(s) in the watcher''s log', v_one_ms, jsonb_array_length(v_w -> 'log' -> 'r'));
    -- (c) OVER (the probe's own row, closed by hand: the real close is proof 66's): it stays with its ending for keep_seconds, then it is gone
    perform cmd.assume_identity(c_uid2);
    update public.battles set status = 'RESOLVED', result = public.battle_fight(v_bat, null), resolves_at = now() - interval '5 seconds', started_at = now() - interval '2 minutes' where id = v_bat;
    select e into v_c from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text;
    v_w := world.fight(v_bat);
    if v_c is null or coalesce(v_c ->> 'end', '') not in ('A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK') or v_c -> 'next_at' is distinct from 'null'::jsonb
       or exists (select 1 from jsonb_array_elements(v_c -> 'sides') s where s ? 'at')
       or v_w -> 'log' ->> 'end' is distinct from v_c ->> 'end' or v_w ? 'loot' or v_w ? 'crew_lost' or v_w ? 'outcome' or v_w ? 'navy' or v_w ? 'word' or v_w ? 'stance' or v_w ? 'may'
       or exists (select 1 from jsonb_object_keys(v_w -> 'log') k where k <> all (c_keys)) then
      raise exception '0364 self-assert FAIL: a battle just over: card %, watcher %', v_c, v_w;
    end if;
    update public.battles set resolves_at = now() - interval '61 seconds' where id = v_bat;
    if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text) or (world.fight(v_bat) ->> 'on')::boolean is not true then
      raise exception '0364 self-assert FAIL: a battle over for more than keep_seconds is still on the map, or its log can no longer be read';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    if world.fights() is distinct from '{"on": false, "fights": []}'::jsonb or world.fight(v_bat) is distinct from '{"on": false}'::jsonb then
      raise exception '0364 self-assert FAIL: lit, a caller with no house read a battle';
    end if;
    raise exception using errcode = 'ZX364', message = 'PROBE_ROLLBACK_0364';
  exception when sqlstate 'ZX364' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0364 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0364' or p.auth_uid in (c_uid, c_uid2)) or public.current_player_id() is not null then
    raise exception '0364 self-assert FAIL: the probe left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before then
    raise exception '0364 self-assert FAIL: the probe left a world_config row moved';
  end if;

  v_ms := v_ms || jsonb_build_object('probe', round(extract(epoch from clock_timestamp() - v_tp) * 1000));
  if extract(epoch from clock_timestamp() - v_t0) > 20 then
    raise exception '0364 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0364 timings (ms a part): %; total % ms.', v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise notice '0364 self-assert ok: A FIGHT SHOWS ON THE MAP. Three reads and one index; no table, column, knob, job or write. The registry is cut once on 0357''s world.battle row and reverses (+2 doors: world.fights, world.fight); the card is server-only, anon calls nothing, every read is STABLE and none writes, advances a battle or names a purse, a hold, loot or a stance; no other function, relation or world_config row moved. A caller with no house reads nothing. The probe (rolled back; attack_enabled lit inside it only): a neighbour reads the battle of another company with its place, clock, two fleets, two ships and where each lies, `mine` null, only the keys this file names; the watcher''s log is her own card''s log key for key, before the first round and after it, with no stance, word, loot, crew_lost or navy line; over, it stays with its ending for 60 s and then leaves the map; %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
