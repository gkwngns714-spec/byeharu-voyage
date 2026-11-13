-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0364 - A FIGHT SHOWS ON THE MAP: battles, her own raids and the navy's fights, each with its log  (owner row 321)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 321 (2026-11-13): "i want a fight to be visible in map. in red circle surrounding all fleets. if more fleets participate, bigger circle. by clicking that
-- circle, like info i want to see the actual fight". And the follow-up: with attack_enabled off a battle's ring never shows, so the fights that DO happen today are shown too.
--
-- WHICH FIGHTS THERE ARE (read on the bodies at head 0357), and what this file serves of each:
--   A BATTLE     a row of public.battles, written by public.battle_open alone, whose one caller is public.attack_for (cmd.attack), behind attack_enabled (false). DARK: no row, no ring.
--   A RAID       pirates set upon a company's fleet on a voyage day (voyage.settle's PIRATES arm; combat_bite true on prod). Settled in an instant. 0353 already keeps its log on the
--                day's own row (voyage_events.payload.fight.log) the moment the day settles, and every read of her fleets settles them first: so the row is there while she is still at
--                sea, and NOTHING NEEDS TO BE TOLD: world.fights() reads her own PIRATES days of the last 300 s. voyage.settle IS NOT CUT (the digest of every function this file does
--                not name is held), so docs/COMBAT_LOG.md's C4-lite event is not needed for the map, and 0362's three hunks on the PIRATES arm cannot meet a hunk of this file.
--   A NAVY FIGHT a navy ship against a pirate ship (public.navy_fight, 0340; navy_enabled and pirates_bite true on prod), one call, at most once an hour a ship. Its rounds were
--                computed and thrown away. This file KEEPS them: one hunk in public.navy_fight calls public.navy_fight_keep, which writes the fight's place and log to one row a
--                navy ship (public.navy_fight_log, written over each time). LIT AT THE DEPLOY for every player.
-- NEWS: this file posts its own UPDATE row, public.news_update('0364', 'Fights on the map', '지도에 전투 표시') (0347's law, tests/news.lint.spec.ts): raids and navy fights
--   are on the map from the deploy.
--
-- WHAT IT ADDS
--   public.fight_card(battle, player)   ONE battle as the map draws it (server-only): id, kind BATTLE, size (its fleets that are there), status, lat and lon (battles.site), the
--                         clock (started_at, resolves_at, round_seconds, rounds, rounds_done, next_at), `fleets` and `ships` (the sides that are THERE), `mine` (the caller's own
--                         fleet if she opened it or was set upon), and `sides`: {fleet, name, side, how, kind (public.fleet_kind), company, nation, ships, here, at}. Closed: `end`.
--   world.fights()        THE READ THE MAP POLLS: {on, now, keep_seconds 60, raid_seconds 300, fights[]}, oldest first, each with a kind:
--                           BATTLE  every battle being fought with a sheet, and those ended within 60 s (50 at most);
--                           RAID    the caller's OWN raids of the last 300 s: the place she was at that day's end (voyage.position at the row's own instant), the raiders by the
--                                   log's own count, her fleet, the log and what the day cost her (crew, cargo, ransom: the same figures her History shows). Nobody else's;
--                           NAVY    every navy fight of the last 300 s: its place, the two ships, the log cut to nine keys. Everybody's.
--                         `size` sizes the ring: a battle's fleets; a raid's fleet and its raiders' ships (five xebecs are six); a navy fight's ships on both sides.
--   world.fight(battle)   ANY BATTLE'S LOG, FOR A WATCHER: world.battle's shape with `watch` true, the log from the deck of the side that attacked, cut to nine keys.
--   public.navy_fight_log one row a navy ship: at, lat, lon, card {navy, pirate, nation, navy_ships, pirate_ships, log}. RLS, no client. It does not grow past the navy's ships.
--   public.navy_fight_keep  its one writer (server-only). It decides nothing and NEVER RAISES: an error in it is a warning and the fight stands as it was.
--   battles_ended         an index on (resolves_at) where status <> 'FIGHTING'.
--
-- WHAT A WATCHER CAN SEE, AND WHY IT IS SAFE
--   Of a battle or a navy fight: the place; the clock; each fleet's name, what it is, its company's name and country, its ships; the ships of the side that closed by name with
--   hull points and crew; the other side's name, ships, crew and hull in sum; each round's range, shots, hits, damage, hull left and the chance rolled to slip; the boarding's two
--   crews; how it ended. NOT served: loot, crew_lost, the navy line, the pre-fight word, a stance, any purse, cargo, cargo value, funds, route or destination. Both logs are cut to
--   (v, atk, first, foe, you, r, board, after, end): a key a later file adds to a log does not reach a watcher until a file says so here.
--   Of a raid: ONLY ITS OWN COMPANY reads it, and she reads what her History already tells her.
--   NO PLAYER FIGHTS A PLAYER (not touched), so a ring is never a way to find a company to attack. What is new: a battle's ring tells any player where another company's fleet is
--   fighting, for the minutes of the battle (dark today). A raid's ring tells nobody but her.
--
-- SUPERSEDES, BY RE-CUT (each OLD text once in its live body, each reversing):
--   public.client_rpc_entry_points (1)   the two doors, anchored on 0357's own `world.battle` row, a line no other open file cuts.
--   public.navy_fight (1)                one line after the two hour-stamps: perform public.navy_fight_keep(...). No open file (0358 to 0363, read on origin/batch-5) names public.navy_fight.
--   NPC OUTCOMES ARE BYTE FOR BYTE: the keeper writes one row of its own table and swallows its own errors. Proof 66 fights the same navy fight under the old body and the new and
--   holds the answer, both hulls, both stamps, the event, the card and every purse equal as text.
--
-- COST: world.fights(): one identity probe; two index scans of public.battles (empty while dark); her fleets, each one's voyages under way or ended within 300 s, their PIRATES days
--   (the voyage_events primary key); one scan of public.navy_fight_log (one row a navy ship). Per raid served one voyage.position; per battle one row and its sides.
--   A navy fight: one more insert-or-update and one public.battle_log (the fight's own answer turned round), at most navy_hunts_per_run (5) a minute.
--   Local timings: docs/dev-log/2026-11-13-fight-rings.md.
-- ROLLBACK (forward, owner only): scripts/ops/harness/fight-rings/rollback-0364.sql is the draft: both hunks reversed, the four functions, the table and the index dropped.
-- SELF-ASSERT: ONE DO block, statement_timeout 30 s, lock_timeout 5 s first; fails above 20 s. The catalog, then a probe of this file's own rows (a battle lit inside the probe only,
--   a kept navy fight, a raid day), rolled back by a raised sentinel. No table is counted or summed. THE REAL RAID DAY, THE REAL NAVY PASS AND OLD AGAINST NEW ARE PROOF 66's.
-- LOCKS: CREATE INDEX on public.battles (SHARE; no row on prod); CREATE TABLE with a foreign key to public.fleets (a brief SHARE ROW EXCLUSIVE), under lock_timeout 5 s.
-- VERSION: 0364, cut on the bodies at head 0357. It applies with or without 0358 to 0363 before it (proved on origin/batch-5's chain) and deploys after them by its number.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_tp         timestamptz := clock_timestamp();
  v_ms         jsonb := '{}'::jsonb;
  c_reg        constant text := 'public.client_rpc_entry_points()';
  c_nav        constant text := 'public.navy_fight(uuid,uuid,timestamp with time zone)';
  c_new_fns    constant text[] := array['public.fight_card(uuid,uuid)', 'world.fights()', 'world.fight(uuid)', 'public.navy_fight_keep(uuid,uuid,jsonb,jsonb,jsonb,timestamp with time zone)'];
  c_reads      constant text[] := array['public.fight_card(uuid,uuid)', 'world.fights()', 'world.fight(uuid)'];
  c_nav_old    constant text := $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
$h$;
  c_nav_new    constant text := $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
  perform public.navy_fight_keep(p_navy, p_pirate, v_a, v_b, v_f, p_now);   -- 0364: the fight's log and its place, kept for the map (it never raises and moves nothing of the fight)
$h$;
  v_nav0       text;
  v_n0         record;
  v_voy        uuid;
  v_k          jsonb;
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
     or to_regclass('public.battles_ended') is not null or to_regclass('public.navy_fight_log') is not null then
    raise exception '0364 refuses: it has been applied once';
  end if;
  if to_regprocedure('world.battle(uuid)') is null or to_regprocedure('public.battle_log(jsonb,jsonb,text)') is null or to_regprocedure('public.battle_fight(uuid,integer)') is null
     or to_regprocedure('public.fleet_kind(uuid)') is null or to_regprocedure('public.crown_nation(uuid)') is null or to_regprocedure('public.attack_on()') is null
     or to_regprocedure('voyage.fleet_point(uuid,timestamp with time zone)') is null or to_regprocedure('public.current_player_id()') is null
     or to_regprocedure('public.battle_open(text,uuid,uuid,timestamp with time zone)') is null or to_regprocedure('cmd.assume_identity(uuid)') is null
     or to_regprocedure(c_nav) is null or to_regprocedure('public.navy_hunts_on()') is null or to_regprocedure('public.combat_bite_on()') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('voyage.position(uuid,timestamp with time zone)') is null
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.battles'::regclass and a.attname = 'sheet' and not a.attisdropped) then
    raise exception '0364 refuses: a function or a column it reads is not in this world (0308 / 0327 / 0333 / 0340 / 0347 / 0357)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_def0 := replace(pg_get_functiondef(c_reg::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg into v_p0 from pg_proc p where p.oid = c_reg::regprocedure;
  if (length(v_def0) - length(replace(v_def0, c_old, ''))) / length(c_old) is distinct from 1 then
    raise exception '0364 slice: the registry''s world.battle row occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against',
      (length(v_def0) - length(replace(v_def0, c_old, ''))) / length(c_old);
  end if;
  v_nav0 := replace(pg_get_functiondef(c_nav::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg into v_n0 from pg_proc p where p.oid = c_nav::regprocedure;
  if (length(v_nav0) - length(replace(v_nav0, c_nav_old, ''))) / length(c_nav_old) is distinct from 1 then
    raise exception '0364 slice: the hunk of public.navy_fight occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against',
      (length(v_nav0) - length(replace(v_nav0, c_nav_old, ''))) / length(c_nav_old);
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (array[c_reg::regprocedure::oid, c_nav::regprocedure::oid]);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p') and c.relname <> all (array['battles_ended', 'navy_fight_log', 'navy_fight_log_pkey']);
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- ── 2. THE INDEX ──
  create index battles_ended on public.battles (resolves_at) where status <> 'FIGHTING';
  comment on index public.battles_ended is '0364: the battles that are over, by when they ended: world.fights() reads the last minute of it.';

  -- ── 2b. A NAVY FIGHT'S LOG: one row a navy ship, her LAST fight, written over each time (it never grows past the number of navy ships) ──
  create table public.navy_fight_log (
    fleet_id     uuid        primary key references public.fleets(id) on delete cascade,
    at           timestamptz not null,
    lat          numeric     not null,
    lon          numeric     not null,
    card         jsonb       not null
  );
  comment on table public.navy_fight_log is
    '0364: a navy ship''s LAST fight with a pirate ship, for the map: when, where she was, and `card` {navy, pirate, navy_ships, pirate_ships, nation, log}: the log is public.battle_log''s from the navy ship''s deck (shape v 1), cut to nine keys. One row a navy ship, written over by public.navy_fight_keep. Nothing of the game reads it.';
  alter table public.navy_fight_log enable row level security;
  revoke all on table public.navy_fight_log from public, anon, authenticated;

  execute $f$
create function public.navy_fight_keep(p_navy uuid, p_pirate uuid, p_a jsonb, p_b jsonb, p_f jsonb, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0364: KEEP A NAVY FIGHT FOR THE MAP. Called by public.navy_fight right after both hour-stamps, with the two sides as they went in (p_a the pirate ship, p_b the navy ship: voyage.fleet_hulls
-- before the fight) and public.fight_sides' own answer. It writes ONE row of public.navy_fight_log, over her last: where she is now (voyage.fleet_point), the two names, the ships a side, and
-- the log from the navy ship's deck (public.battle_log, the side that closes, cut to nine keys). IT DECIDES NOTHING AND NEVER RAISES: whatever goes wrong here is a warning and the fight stands
-- as it was; no hull, stamp, event or return value of public.navy_fight depends on it.
declare
  v_lat numeric;
  v_lon numeric;
  v_nn  text;
  v_pn  text;
begin
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(p_navy, p_now) p;
  if v_lat is null or v_lon is null then
    return;
  end if;
  select f.name into v_nn from public.fleets f where f.id = p_navy;
  select f.name into v_pn from public.fleets f where f.id = p_pirate;
  insert into public.navy_fight_log (fleet_id, at, lat, lon, card)
  values (p_navy, p_now, v_lat, v_lon, jsonb_build_object(
    'navy', jsonb_build_object('fleet', p_navy, 'name', v_nn), 'pirate', jsonb_build_object('fleet', p_pirate, 'name', v_pn),
    'nation', (select n.code from public.navy_ships x join public.nations n on n.id = x.nation_id where x.fleet_id = p_navy),
    'navy_ships', jsonb_array_length(p_b), 'pirate_ships', jsonb_array_length(p_a),
    'log', (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
              from jsonb_each(public.battle_log(jsonb_build_object('a', p_a, 'b', p_b, 'foe', v_pn, 'you', v_nn), p_f, 'ATTACKER')) e
             where e.key in ('v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end'))))
  on conflict (fleet_id) do update set at = excluded.at, lat = excluded.lat, lon = excluded.lon, card = excluded.card;
exception when others then
  raise warning 'navy_fight_keep: the fight of % was not kept for the map (SQLSTATE %: %)', p_navy, sqlstate, sqlerrm;
end
$body$;
$f$;
  comment on function public.navy_fight_keep(uuid, uuid, jsonb, jsonb, jsonb, timestamptz) is '0364: keeps a navy ship''s last fight (place, names, ships, the log cut to nine keys) in public.navy_fight_log for the map. Called by public.navy_fight. Never raises; decides nothing. Server-only.';
  revoke all on function public.navy_fight_keep(uuid, uuid, jsonb, jsonb, jsonb, timestamptz) from public, anon, authenticated;

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
           'id', b.id, 'kind', 'BATTLE', 'size', s.fleets, 'status', b.status, 'lat', (b.site ->> 'lat')::numeric, 'lon', (b.site ->> 'lon')::numeric,
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
-- 0364 (owner row 321): THE READ THE MAP POLLS: {on, now, keep_seconds, raid_seconds, fights[]}, each with a `kind`, oldest first.
--   BATTLE  every battle being fought round by round (0357: a battle with a sheet), and every such battle that ended within keep_seconds (60): public.fight_card. 50 at most.
--   RAID    HER OWN: a PIRATES day of a voyage of the caller's own fleets that kept a log (0353), whose day ended within raid_seconds (300). Where she was at that day's end
--           (voyage.position at the row's own instant), the raiders (the log's own count), her fleet, the log and what the day cost her, as her History has them. Nobody else's.
--   NAVY    a navy ship's fight with a pirate ship (0340) fought within raid_seconds, from public.navy_fight_log: where, the two ships, the log cut to nine keys. Everybody's.
-- `size` is what the ring is sized by: a battle's fleets that are there; a raid's fleet and its raiders' ships; a navy fight's ships on both sides.
-- `on` is false only when nothing is served and attacks, the navy's hunt and the fight at sea are all dark. A caller with no house: nothing. It writes nothing and advances nothing.
declare
  v_player uuid := public.current_player_id();
  c_keep   constant int := 60;
  c_raid   constant int := 300;
  v_f      jsonb;
begin
  if v_player is null then
    return jsonb_build_object('on', false, 'fights', '[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(y.card order by y.at, y.card ->> 'id'), '[]'::jsonb) into v_f
    from (
      select x.started_at as at, public.fight_card(x.id, v_player) as card
        from (select q.id, q.started_at
                from (select b.id, b.started_at from public.battles b where b.status = 'FIGHTING' and b.sheet is not null
                      union all
                      select b.id, b.started_at from public.battles b
                       where b.status <> 'FIGHTING' and b.resolves_at > now() - make_interval(secs => c_keep) and b.sheet is not null) q
               order by q.started_at, q.id limit 50) x
      union all
      -- HER OWN RAIDS: her fleets, each one's voyage under way or just ended, its PIRATES days of the last raid_seconds that kept a log
      select r.resolved_at, jsonb_build_object(
               'id', 'raid:' || r.voyage_id || ':' || r.day_index, 'kind', 'RAID', 'status', 'RESOLVED', 'lat', pos.lat, 'lon', pos.lon,
               'started_at', r.resolved_at, 'resolves_at', r.resolved_at, 'until', r.resolved_at + make_interval(secs => c_raid),
               'rounds_done', jsonb_array_length(coalesce(r.log -> 'r', '[]'::jsonb)), 'next_at', null,
               'fleets', 2, 'ships', r.ships + r.raiders, 'size', 1 + r.raiders, 'mine', r.fleet_id,
               'sides', jsonb_build_array(
                 jsonb_build_object('fleet', 'raiders', 'name', r.log -> 'foe' ->> 'n', 'side', 'ATTACKER', 'how', 'OPENED', 'kind', 'PIRATE', 'company', null, 'nation', null, 'ships', r.raiders, 'here', true),
                 jsonb_build_object('fleet', r.fleet_id, 'name', r.fleet_name, 'side', 'DEFENDER', 'how', 'OPENED', 'kind', 'COMPANY', 'company', r.company, 'nation', r.nation, 'ships', r.ships, 'here', true)),
               'end', r.log ->> 'end', 'log', r.log,
               'loss', jsonb_build_object('crew_before', r.payload -> 'crew_before', 'crew', r.payload -> 'crew_lost', 'cargo', coalesce(r.payload -> 'cargo_lost', '{}'::jsonb),
                                          'ransom', coalesce(r.payload -> 'ransom_paid', r.payload -> 'pirate' -> 'ransom', '0'::jsonb)))
        from (select ve.voyage_id, ve.day_index, ve.resolved_at, ve.payload, ve.payload -> 'fight' -> 'log' as log, f.id as fleet_id, f.name as fleet_name,
                     pl.company_name as company, (select n.code from public.nations n where n.id = pl.nation_id) as nation,
                     (select count(*) from public.ships sh where sh.fleet_id = f.id)::int as ships,
                     greatest(1, ceil(coalesce((ve.payload -> 'fight' -> 'log' -> 'foe' ->> 'k')::numeric, 1)))::int as raiders
                from public.fleets f
                join public.players pl on pl.id = f.player_id
                join lateral (select v.id from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING'
                              union all
                              select v.id from public.voyages v where v.fleet_id = f.id and v.status <> 'SAILING' and v.eta > now() - make_interval(secs => c_raid)) vo on true
                join public.voyage_events ve on ve.voyage_id = vo.id and ve.kind = 'PIRATES'
               where f.player_id = v_player and ve.resolved_at > now() - make_interval(secs => c_raid) and ve.resolved_at <= now()
                 and ve.payload -> 'fight' ? 'log') r
       cross join lateral voyage.position(r.voyage_id, r.resolved_at) pos
      union all
      -- THE NAVY'S FIGHTS: the last fight of each navy ship, if it was within raid_seconds
      select l.at, jsonb_build_object(
               'id', 'navy:' || l.fleet_id || ':' || floor(extract(epoch from l.at))::bigint, 'kind', 'NAVY', 'status', 'RESOLVED', 'lat', l.lat, 'lon', l.lon,
               'started_at', l.at, 'resolves_at', l.at, 'until', l.at + make_interval(secs => c_raid),
               'rounds_done', jsonb_array_length(coalesce(l.card -> 'log' -> 'r', '[]'::jsonb)), 'next_at', null,
               'fleets', 2, 'ships', (l.card ->> 'navy_ships')::int + (l.card ->> 'pirate_ships')::int, 'size', (l.card ->> 'navy_ships')::int + (l.card ->> 'pirate_ships')::int, 'mine', null,
               'sides', jsonb_build_array(
                 jsonb_build_object('fleet', l.card -> 'navy' -> 'fleet', 'name', l.card -> 'navy' -> 'name', 'side', 'ATTACKER', 'how', 'OPENED', 'kind', 'NAVY', 'company', null,
                                    'nation', l.card -> 'nation', 'ships', l.card -> 'navy_ships', 'here', true),
                 jsonb_build_object('fleet', l.card -> 'pirate' -> 'fleet', 'name', l.card -> 'pirate' -> 'name', 'side', 'DEFENDER', 'how', 'OPENED', 'kind', 'PIRATE', 'company', null,
                                    'nation', null, 'ships', l.card -> 'pirate_ships', 'here', true)),
               'end', l.card -> 'log' ->> 'end', 'log', l.card -> 'log')
        from public.navy_fight_log l
       where l.at > now() - make_interval(secs => c_raid) and l.at <= now()) y;
  return jsonb_build_object('on', jsonb_array_length(v_f) > 0 or public.attack_on() or public.navy_hunts_on() or public.combat_bite_on(),
                            'now', now(), 'keep_seconds', c_keep, 'raid_seconds', c_raid, 'fights', v_f);
end
$body$;
$f$;
  comment on function world.fights() is
    '0364: the read the map polls: every battle being fought round by round and those ended within keep_seconds (60); the caller''s own raids and every navy fight of the last raid_seconds (300), each with its log. Each has a kind (BATTLE, RAID, NAVY), a place and a size. Stable; it writes and advances nothing. {on, now, keep_seconds, raid_seconds, fights[]}.';
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

  -- ── 5. THE REGISTRY AND THE NAVY'S FIGHT (one hunk each, once) ──
  execute replace(v_def0, c_old, c_new);
  execute replace(v_nav0, c_nav_old, c_nav_new);

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
  v_def := replace(pg_get_functiondef(c_nav::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_nav_new, ''))) / length(c_nav_new) is distinct from 1 or replace(v_def, c_nav_new, c_nav_old) is distinct from v_nav0 then
    raise exception '0364 self-assert FAIL: the hunk of public.navy_fight is not in the new body exactly once, or it does not reverse to its pre-image';
  end if;
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg into v_p from pg_proc p where p.oid = c_nav::regprocedure;
  if v_p.acl is distinct from v_n0.acl or v_p.vol is distinct from v_n0.vol or v_p.secdef is distinct from v_n0.secdef or v_p.cfg is distinct from v_n0.cfg then
    raise exception '0364 self-assert FAIL: public.navy_fight changed its ACL, volatility, definer or config';
  end if;
  -- the keeper is called in one place, after the stamps; it swallows its own errors; the log's table has one writer and no client
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'navy_fight_keep\(') is distinct from 1
     or (select p.prosrc from pg_proc p where p.oid = 'public.navy_fight_keep(uuid,uuid,jsonb,jsonb,jsonb,timestamp with time zone)'::regprocedure) not like '%exception when others then%raise warning%'
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'insert into public\.navy_fight_log'
                   and p.oid is distinct from 'public.navy_fight_keep(uuid,uuid,jsonb,jsonb,jsonb,timestamp with time zone)'::regprocedure)
     or has_table_privilege('anon', 'public.navy_fight_log', 'select,insert,update,delete') or has_table_privilege('authenticated', 'public.navy_fight_log', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.navy_fight_log'::regclass) or (select count(*) from public.client_write_grants()) is distinct from 0 then
    raise exception '0364 self-assert FAIL: the keeper has another caller or can raise, the log has another writer, or a client can touch its table';
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
  if exists (select 1 from unnest(c_reads) f where (select p.provolatile from pg_proc p where p.oid = f::regprocedure) is distinct from 's') then
    raise exception '0364 self-assert FAIL: a read is not STABLE';
  end if;
  -- no read writes or advances a battle; the reads of somebody else's fight name no purse, hold, loot or stance (world.fights serves her OWN raid's cost to her alone)
  for v_src in select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') from pg_proc p where p.oid = any (select f::regprocedure::oid from unnest(c_reads) f) loop
    if v_src ~* '\m(insert|update|delete|execute|perform)\M' or v_src ~* '\m(battle_advance|battle_resolve|tick_battles|battle_sides_come|navy_fight_keep)\M' then
      raise exception '0364 self-assert FAIL: a read of this file writes or advances a battle';
    end if;
  end loop;
  for v_src in select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') from pg_proc p
                where p.oid in ('public.fight_card(uuid,uuid)'::regprocedure, 'world.fight(uuid)'::regprocedure, 'public.navy_fight_keep(uuid,uuid,jsonb,jsonb,jsonb,timestamp with time zone)'::regprocedure) loop
    if v_src ~* '\m(ducats|cargo|cargo_basis|funds|loot|crew_lost|stance|ledger)\M' then
      raise exception '0364 self-assert FAIL: a read of somebody else''s fight names a purse, a hold, loot or a stance';
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_new_fns || c_reg || c_nav) f)) is distinct from v_fn_before then
    raise exception '0364 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before then
    raise exception '0364 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p') and c.relname <> all (array['battles_ended', 'navy_fight_log', 'navy_fight_log_pkey'])) is distinct from v_rel_before
     or to_regclass('public.battles_ended') is null or to_regclass('public.navy_fight_log') is null then
    raise exception '0364 self-assert FAIL: a relation other than the one index and the one table was made or dropped';
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
    if exists (select 1 from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'RAID' or e ->> 'mine' is not null)
       or (v_r ->> 'on')::boolean is distinct from (jsonb_array_length(v_r -> 'fights') > 0 or public.attack_on() or public.navy_hunts_on() or public.combat_bite_on()) then
      raise exception '0364 self-assert FAIL: a new house with no voyage reads a raid or a fight of its own, or `on` is not what the switches say: %', v_r;
    end if;
    if (v_r ->> 'keep_seconds')::int is distinct from 60 or (v_r ->> 'raid_seconds')::int is distinct from 300 or world.fight(gen_random_uuid()) is distinct from '{"on": false}'::jsonb then
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
       or v_c ->> 'kind' is distinct from 'BATTLE' or (v_c ->> 'size')::int is distinct from 2
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
    if exists (select 1 from jsonb_object_keys(v_c) k where k <> all (array['id', 'kind', 'size', 'status', 'lat', 'lon', 'started_at', 'resolves_at', 'round_seconds', 'rounds', 'rounds_done', 'next_at', 'fleets', 'ships', 'mine', 'sides', 'end']))
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
    -- (d) A NAVY FIGHT KEPT (the keeper alone, on this probe's two fleets and a fight of their hulls: the real pass is proof 66's): everybody reads it for raid_seconds, cut to nine keys
    perform public.navy_fight_keep(v_fl2, v_nfl, voyage.fleet_hulls(v_nfl), voyage.fleet_hulls(v_fl2),
                                   public.fight_sides(v_fl2, 1, voyage.fleet_hulls(v_nfl), voyage.fleet_hulls(v_fl2), '{}'::jsonb), now() - interval '10 seconds');
    perform cmd.assume_identity(c_uid);
    select e into v_k from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'NAVY' and e -> 'sides' -> 0 ->> 'fleet' = v_fl2::text;
    if v_k is null or v_k ->> 'status' is distinct from 'RESOLVED' or v_k -> 'mine' is distinct from 'null'::jsonb or (v_k ->> 'size')::int is distinct from 2 or (v_k ->> 'ships')::int is distinct from 2
       or v_k -> 'sides' -> 0 ->> 'name' is distinct from 'Vizinha' or v_k -> 'sides' -> 0 ->> 'kind' is distinct from 'NAVY' or v_k -> 'sides' -> 1 ->> 'name' is distinct from 'Mercante'
       or v_k -> 'sides' -> 1 ->> 'kind' is distinct from 'PIRATE' or (v_k -> 'log' ->> 'v')::int is distinct from 1 or (v_k -> 'log' ->> 'atk')::boolean is not true
       or coalesce(v_k ->> 'end', '') not in ('A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK') or v_k ? 'loss'
       or v_k ->> 'lat' is null or v_k ->> 'lon' is null or (v_k ->> 'until')::timestamptz is distinct from (v_k ->> 'started_at')::timestamptz + interval '300 seconds'
       or exists (select 1 from jsonb_object_keys(v_k -> 'log') k where k <> all (c_keys)) then
      raise exception '0364 self-assert FAIL: a kept navy fight as a neighbour reads it: %', v_k;
    end if;
    update public.navy_fight_log set at = now() - interval '301 seconds' where fleet_id = v_fl2;
    if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'NAVY' and e -> 'sides' -> 0 ->> 'fleet' = v_fl2::text) then
      raise exception '0364 self-assert FAIL: a navy fight older than raid_seconds is still on the map';
    end if;
    -- (e) HER OWN RAID (a stub voyage of this probe with one PIRATES day that kept a log: the real day is proof 66's): she reads it with what it cost her; her neighbour reads nothing of it
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl2, v_pl2, jsonb_build_array(jsonb_build_object('a', jsonb_build_array(38, -10), 'b', jsonb_build_array(38, -12), 'nm', 600, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0)),
            600, '[5]', now() - interval '10 minutes', now() - interval '5 seconds', 'ARRIVED', v_lis, v_lis);
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, 1, 'PIRATES', jsonb_build_object('crew_before', 8, 'crew_lost', 1, 'cargo_lost', '{"SUGAR": 3}'::jsonb, 'fight', jsonb_build_object('log',
              '{"v": 1, "first": "THEY", "foe": {"n": "Probe xebec", "k": 4.2, "crew": 200, "hull": 3000}, "you": [["Vizinha", 400, 400, 8]], "r": [], "end": "TAKEN", "after": [["Vizinha", 400]]}'::jsonb)),
            now() - interval '20 seconds');
    perform cmd.assume_identity(c_uid2);
    select e into v_k from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID';
    if v_k is null or v_k ->> 'id' is distinct from 'raid:' || v_voy || ':1' or v_k ->> 'mine' is distinct from v_fl2::text or (v_k ->> 'size')::int is distinct from 6 or (v_k ->> 'ships')::int is distinct from 6
       or v_k ->> 'end' is distinct from 'TAKEN' or v_k -> 'log' -> 'foe' ->> 'n' is distinct from 'Probe xebec' or v_k -> 'loss' is distinct from '{"crew_before": 8, "crew": 1, "cargo": {"SUGAR": 3}, "ransom": 0}'::jsonb
       or v_k -> 'sides' -> 0 ->> 'kind' is distinct from 'PIRATE' or (v_k -> 'sides' -> 0 ->> 'ships')::int is distinct from 5 or v_k -> 'sides' -> 1 ->> 'fleet' is distinct from v_fl2::text
       or (v_k ->> 'lat')::numeric is distinct from 38 or (v_k ->> 'lon')::numeric > -10 or (v_k ->> 'lon')::numeric < -12 then
      raise exception '0364 self-assert FAIL: her own raid as she reads it: %', v_k;
    end if;
    perform cmd.assume_identity(c_uid);
    if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') then
      raise exception '0364 self-assert FAIL: a company read another company''s raid';
    end if;
    update public.voyage_events set resolved_at = now() - interval '301 seconds' where voyage_id = v_voy;
    perform cmd.assume_identity(c_uid2);
    if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') then
      raise exception '0364 self-assert FAIL: a raid older than raid_seconds is still on her map';
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
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0364' or p.auth_uid in (c_uid, c_uid2)) or public.current_player_id() is not null
     or exists (select 1 from public.navy_fight_log) then
    raise exception '0364 self-assert FAIL: the probe left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before then
    raise exception '0364 self-assert FAIL: the probe left a world_config row moved';
  end if;

  v_ms := v_ms || jsonb_build_object('probe', round(extract(epoch from clock_timestamp() - v_tp) * 1000));

  -- ── 8. THE NEWS (0347's law): her raids and the navy's fights are on the map from this deploy ──
  perform public.news_update('0364', 'Fights on the map', '지도에 전투 표시');
  if extract(epoch from clock_timestamp() - v_t0) > 20 then
    raise exception '0364 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0364 timings (ms a part): %; total % ms.', v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise notice '0364 self-assert ok: A FIGHT SHOWS ON THE MAP. Made: three reads (the card, world.fights, world.fight), the keeper of a navy fight and its table (one row a navy ship; RLS, no client), one index. Cut once each and reversing: the registry on the world.battle row of 0357 (+2 doors), and public.navy_fight (one line after the hour-stamps). voyage.settle and every other function, relation and world_config row did not move. The keeper has one caller, swallows its own errors and is the only writer of its table; no read writes or advances a battle; anon calls nothing. The probe (rolled back; attack_enabled lit inside it only): a neighbour reads another company''s battle with its place, clock, fleets and where each lies, only the keys this file names; the watcher''s log is her own card''s log key for key and carries no stance, word, loot, crew_lost or navy line; over, it stays 60 s; a kept navy fight is read by everybody for 300 s, cut to nine keys; her own raid day is read by her alone with what it cost her, sized by its raiders'' ships, for 300 s; %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
