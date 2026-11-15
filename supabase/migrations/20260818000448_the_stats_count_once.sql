-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0448 - THE STATS COUNT ONCE  (one authority says which state a fleet is in, one function counts, and every Stats face reads that one count)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-16, verbatim: "stats is messed up. the ships at sea, in port, laid up, wrecked are all different numbers. i want you to make
--   it so that this error does not happen again. fix it". docs/dev-log/2026-11-16-stats-one.md has the read and the reasoning.
--
-- WHAT PROD SAID (one read-only read, 2026-11-15 16:25:16 UTC, head 0446, scripts/ops/harness/stats-one/before.sql; the count was 16:21:00):
--   MERCHANTS, two faces, two rules, two times. The Merchants face read the fleets LIVE (public.stats_merchant_fleets): 885 fleets, and under them
--     Sailing 732 + In port 148 + Repairing 4 + Cannot sail 1 + Laid up 88 = 973. The 88 laid-up fleets were counted twice (a laid-up merchant lies
--     DOCKED: she was in "In port" and in "Laid up"). The Ships face read the COUNT of 16:21 and its own arithmetic: At sea 727, In port 68 (what was
--     left over), Laid up 90, Wrecked 0. So: in port 148 against 68, laid up 88 against 90, at sea 732 against 727, "Cannot sail" 1 against "Wrecked" 0.
--   A FIGHT WAS NOWHERE. 3 battles were being fought; their 3 merchants and 3 pirate fleets (6 ships) were held where they stood and counted "at sea"
--     (a fleet held under sail keeps the status SAILING); a fleet fought in a harbour (IN_BATTLE) was counted "in port".
--   FLEETS AGAINST SHIPS. Every card's big figure was SHIPS (pirates 193, merchants 943) and the bar under it counted FLEETS (pirates 121, merchants
--     885) with no word saying so: 117 + 3 + 1 "ships" under "193 ships".
--   THE RULE WAS WRITTEN FIVE TIMES: three `case` lines in public.stats_fleets_count, one in public.stats_fleet_list_rows, one in world.stats_fleet,
--     beside the merchants' two (public.stats_merchant_fleets, world.stats_fleets' arithmetic). The navy, pirate and cargo faces agreed with the Ships
--     face that day (48 / 121 / 119, the same rule copied, the same count), but they were written by two statements of the count, each with its own
--     view of a moving sea, and the next edit of one copy would have parted them.
--   A fleet's own page (world.stats_fleet) is read live: its word could differ from her line in the list (counted up to 15 minutes before).
--   Not wrong, and unmoved: 259 retired cargo ships are rows and out of every count since 0437; no merchant fleet is hidden (885 of npc_fleet_max 885).
--
-- THE DEFINITIONS (decided by default; the owner may reverse any of them):
--   A FLEET IS IN EXACTLY ONE STATE, the first of these that is true:
--     laid_up   she is laid up: a merchant whose route is paused `laid_up`; a navy, pirate or cargo ship with laid_up_at;
--     wrecked   she cannot sail: no hull above 0 (or no ship at all), a pirate whose wreck lies at home (wrecked_at), or the status UNABLE_TO_SAIL or
--               ADRIFT. The Merchants face's "Cannot sail" was this; it now says "Wrecked" like every other face;
--     battle    she is in a fight: on a side of a battle that is FIGHTING, or her status is IN_BATTLE. Shown as its own state, "In battle", on every
--               face (not folded into "At sea": a fight is in a harbour as often as at sea);
--     sea       her status is SAILING;
--     port      anything else (DOCKED, ANCHORED, REPAIRING). The Merchants face's "Repairing" is in port.
--   WHAT IS COUNTED: every merchant fleet, navy ship and pirate ship, and every cargo ship IN SERVICE. A retired cargo ship (laid_up_at, 0326/0437)
--     is hidden on every face: her state is `laid_up` on her own page, and she is in no count. So the cargo ships' "Laid up" is always 0.
--   THE UNIT: the five states count FLEETS, always, and the faces say so ("121 fleets · 193 ships" over the bar). The count also serves the ships
--     by state (`ships_by`), and it holds the same rule: ships = the sum of its five.
--   THE TIME: every state on every Stats face is the COUNT's (four an hour), all from one statement of it, and each face says "Counted at". Only a
--     fleet's own page is read live (it is one fleet, asked at a press); it says the same word by the same rule, as of now.
--   THE RULE: fleets = sea + port + battle + laid_up + wrecked, for every kind, on every face; and a face's header is the Ships face's card.
--
-- WHAT THIS FILE DOES:
--   1. THE ONE AUTHORITY (new, server-only):
--      public.fleet_state_of(laid, wrecked, battle, sailing)  IMMUTABLE: the order above, in one `case`. The only place the five words are chosen.
--      public.fleet_census(fleet default null)                STABLE: every fleet (or one): fleet_id, kind (MERCHANT, NAVY, PIRATE, CARGO, OTHER),
--                                                             state, ships, counted. The only place the facts the rule needs are read.
--      public.fleet_state(fleet)                              STABLE: one fleet's state (the census of one).
--      public.fleet_tally()                                   STABLE: {MERCHANT, NAVY, PIRATE, CARGO}, each {fleets, ships, sea, port, battle, laid_up,
--                                                             wrecked, ships_by {sea, port, battle, laid_up, wrecked}}. The only counter.
--   2. EVERY READER GOES THROUGH IT (14 hunks over 7 bodies):
--      public.stats_fleets_count     the three `case` lines go; each kind's counts are public.fleet_tally's; the merchants' are in the row at last.
--      public.stats_fleet_list_rows  a fleet's state is the census's, the header is public.fleet_tally's.
--      public.tick_stats             the fleets' row and the three lists are written by ONE statement (one view of the sea), where there were two.
--      public.stats_merchant_fleets  the merchants' row of the count (the charts' "at sea" and "laid up") is the tally's.
--      world.stats_fleets            the merchants' card is the row's tally (its own arithmetic goes).
--      world.stats_merchants         the face's states are the count's row (it read the fleets live, each second, by another rule): fleets, ships,
--                                    sea, port, battle, laid_up, wrecked. The keys sailing / docked / repairing / unable are no longer served.
--      world.stats_fleet             a fleet's page says public.fleet_state.
--      (world.stats_fleet_list is unmoved: it serves the list row as written.)
--   3. THE NEWEST COUNT IS RE-STATED ONCE, so the faces are whole from the deploy and not from the next count (up to 15 minutes later): the newest
--      public.stats_fleets row takes the tally and the three lists are rebuilt, in one statement. Until the next count those states are the deploy's,
--      under the last count's time. Rows of this file's own writing only; nothing is deleted.
--
-- NOT IN THIS FILE: the Stats strip's "Fleets at sea" (world.stats_now's at_sea) stays the live journal of EVERY fleet under sail, the players' too
--   (a fleet held in a fight is under sail there); it is not a state of the four kinds and is not a count. docs/STATS_ONE_COUNT.md says so.
-- LOAD (docs/DATABASE_BUDGET.md): -- budget: no table, no job, no index, no knob; 0 new rows a minute. The count (4 an hour) reads the census twice
--   (the tally, and the cargo ships' and the lists' states): ~1,300 fleets with their ships by key and the few battles being fought, where it read
--   the three small ship tables once. The Merchants face no longer reads ~885 fleets a second a viewer: its states are one stored row by key.
-- LOCKS: CREATE FUNCTION x4, CREATE OR REPLACE x7 by hunks. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner of the re-cut bodies unmoved; no other function moved;
--   the four new functions server-only, the rule IMMUTABLE and the rest STABLE; the rule's whole truth table. THE PROBE, rolled back, on its own
--   rows only: four merchant fleets of the world are borrowed (one laid up, one wrecked, one put on a battle being fought, one left alone) and each
--   reads its state; all three marks on one fleet read laid_up; the tally moves by exactly those three and its fleets do not; for every kind
--   fleets = the five states and ships = `ships_by`; a planted count row and its lists read back with every list header equal to the Ships face's
--   card and to its own rows, and the Merchants face equal to the Ships face's merchants. Nothing counts or sums a growing table.
-- ROLLBACK (forward, owner only): scripts/ops/harness/stats-one/rollback-0448.sql, a draft (the hunks reversed, the four functions dropped). The
--   client must be reverted with it (it reads `battle`, and the Merchants face reads the new keys).
-- VERSION: 0448 (production head 0446 on 2026-11-16; 0447 is another branch's). 0445 and 0446 touch none of these bodies.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array[
    'public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 'public.stats_fleet_list_rows(text,timestamp with time zone)',
    'public.tick_stats(timestamp with time zone)', 'public.stats_merchant_fleets()', 'world.stats_fleets()', 'world.stats_merchants(text)',
    'world.stats_fleet(uuid)'];
  c_new constant text[] := array[
    'public.fleet_state_of(boolean,boolean,boolean,boolean)', 'public.fleet_census(uuid)', 'public.fleet_state(uuid)', 'public.fleet_tally()'];
  c_states constant text[] := array['sea', 'port', 'battle', 'laid_up', 'wrecked'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_k         text;
  v_f         uuid[];
  v_b         uuid;
  v_t         jsonb;
  v_t2        jsonb;
  v_r         jsonb;
  v_l         jsonb;
  v_s         jsonb;
  v_slot      bigint;
  v_was       text;
  v_note      text := 'not run';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.fleet_census(uuid)') is not null or to_regprocedure('public.fleet_tally()') is not null then
    raise exception '0448 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null) or to_regclass('public.stats_fleets') is null
     or to_regclass('public.stats_fleet_list') is null or to_regclass('public.battle_sides') is null
     or to_regprocedure('public.cargo_ship_state(uuid)') is null or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0448 refuses: 0419 (the fleets'' row), 0431 (the fleet faces), 0437 (the retired cargo ship), the battles or the news are not all in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0448 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0448
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE ONE AUTHORITY ──
  execute $f$
create function public.fleet_state_of(p_laid boolean, p_wrecked boolean, p_battle boolean, p_sailing boolean)
returns text
language sql
immutable
as $body$
  -- 0448: THE ONE RULE. A fleet is in exactly one of five states, the first that is true: laid_up, wrecked, battle, sea, else port. Every Stats
  -- face, every count and every fleet's page gets its word here (through public.fleet_census). A new state is a new line HERE, and nowhere else
  -- (docs/STATS_ONE_COUNT.md). A null fact is false, so the answer is never null.
  select case when coalesce(p_laid, false) then 'laid_up'
              when coalesce(p_wrecked, false) then 'wrecked'
              when coalesce(p_battle, false) then 'battle'
              when coalesce(p_sailing, false) then 'sea'
              else 'port' end
$body$
  $f$;

  execute $f$
create function public.fleet_census(p_fleet uuid default null)
returns table (fleet_id uuid, kind text, state text, ships integer, counted boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0448 (the owner, 2026-11-16: "the ships at sea, in port, laid up, wrecked are all different numbers ... make it so that this error does not
  -- happen again"): THE ONE READING OF EVERY FLEET (or of one, p_fleet): her kind, her state by public.fleet_state_of, her ships, and whether the
  -- Stats count her. Kind: MERCHANT (public.npc_fleets), NAVY, PIRATE, CARGO (their ship tables), else OTHER (a player's fleet: never counted).
  -- The facts: laid up = a merchant's route paused `laid_up`, or laid_up_at; wrecked = no hull above 0, a pirate's wreck lying (wrecked_at), or the
  -- status UNABLE_TO_SAIL / ADRIFT; battle = on a side of a FIGHTING battle, or the status IN_BATTLE; sailing = the status SAILING.
  -- Counted: all but a RETIRED cargo ship (laid_up_at, 0326 / 0437), who is hidden on every face. One row a fleet. Reads the four small ship
  -- tables, the fleets and their ships by key, and the battles being fought (public.battles_due). Writes nothing.
  with k as (
    select nf.fleet_id, 1 as pri, 'MERCHANT'::text as kind, true as counted, false as wreck,
           exists (select 1 from public.standing_routes r where r.id = nf.route_id and r.paused_reason = 'laid_up') as laid
      from public.npc_fleets nf where p_fleet is null or nf.fleet_id = p_fleet
    union all
    select n.fleet_id, 2, 'NAVY', true, false, n.laid_up_at is not null from public.navy_ships n where p_fleet is null or n.fleet_id = p_fleet
    union all
    select p.fleet_id, 3, 'PIRATE', true, p.wrecked_at is not null, p.laid_up_at is not null from public.pirate_ships p where p_fleet is null or p.fleet_id = p_fleet
    union all
    select c.fleet_id, 4, 'CARGO', c.laid_up_at is null, false, c.laid_up_at is not null from public.cargo_ships c where p_fleet is null or c.fleet_id = p_fleet),
  o as (select distinct on (k.fleet_id) k.fleet_id, k.kind, k.counted, k.wreck, k.laid from k order by k.fleet_id, k.pri),
  fight as (select bs.fleet_id from public.battles b join public.battle_sides bs on bs.battle_id = b.id where b.status = 'FIGHTING')
  select f.id, coalesce(o.kind, 'OTHER'),
         public.fleet_state_of(o.laid,
                               o.wreck or not s.alive or f.status in ('UNABLE_TO_SAIL', 'ADRIFT'),
                               f.status = 'IN_BATTLE' or f.id in (select fight.fleet_id from fight),
                               f.status = 'SAILING'),
         s.ships, coalesce(o.counted, false)
    from public.fleets f
    left join o on o.fleet_id = f.id
    cross join lateral (select count(*)::int as ships, coalesce(bool_or(x.durability > 0), false) as alive from public.ships x where x.fleet_id = f.id) s
   where p_fleet is null or f.id = p_fleet
$body$
  $f$;

  execute $f$
create function public.fleet_state(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0448: ONE fleet's state, now: sea, port, battle, laid_up or wrecked (public.fleet_census, THE ONE AUTHORITY). Null: no such fleet.
  select c.state from public.fleet_census(p_fleet) c
$body$
  $f$;

  execute $f$
create function public.fleet_tally()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0448: THE ONE COUNT. For each kind the Stats show (MERCHANT, NAVY, PIRATE, CARGO): its counted fleets and ships, the FLEETS in each of the five
  -- states, and the ships in each (`ships_by`), all from public.fleet_census. fleets = sea + port + battle + laid_up + wrecked and ships = the sum
  -- of ships_by, always: each fleet has one state. A kind with no fleet is served with zeros. Every Stats count and face reads THIS (the count
  -- stores it; the faces read the stored row): no reader counts for itself. Writes nothing.
  select jsonb_object_agg(z.kind, z.j)
    from (select k.kind, jsonb_build_object(
                   'fleets', count(c.fleet_id), 'ships', coalesce(sum(c.ships), 0),
                   'sea', count(*) filter (where c.state = 'sea'), 'port', count(*) filter (where c.state = 'port'),
                   'battle', count(*) filter (where c.state = 'battle'),
                   'laid_up', count(*) filter (where c.state = 'laid_up'), 'wrecked', count(*) filter (where c.state = 'wrecked'),
                   'ships_by', jsonb_build_object(
                     'sea', coalesce(sum(c.ships) filter (where c.state = 'sea'), 0), 'port', coalesce(sum(c.ships) filter (where c.state = 'port'), 0),
                     'battle', coalesce(sum(c.ships) filter (where c.state = 'battle'), 0),
                     'laid_up', coalesce(sum(c.ships) filter (where c.state = 'laid_up'), 0), 'wrecked', coalesce(sum(c.ships) filter (where c.state = 'wrecked'), 0))) as j
            from (values ('MERCHANT'), ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)
            left join public.fleet_census() c on c.kind = k.kind and c.counted
           group by k.kind) z
$body$
  $f$;
  revoke all on function public.fleet_state_of(boolean, boolean, boolean, boolean) from public, anon, authenticated;
  revoke all on function public.fleet_census(uuid) from public, anon, authenticated;
  revoke all on function public.fleet_state(uuid) from public, anon, authenticated;
  revoke all on function public.fleet_tally() from public, anon, authenticated;
  comment on function public.fleet_state_of(boolean, boolean, boolean, boolean) is
    '0448: THE ONE RULE of a fleet''s state: laid_up, else wrecked, else battle, else sea, else port. Called by public.fleet_census alone. A new state is a new line here and nowhere else (docs/STATS_ONE_COUNT.md).';
  comment on function public.fleet_census(uuid) is
    '0448: THE ONE READING of every fleet (or one): kind (MERCHANT, NAVY, PIRATE, CARGO, OTHER), state (public.fleet_state_of), ships, and whether the Stats count her (a retired cargo ship is not counted). Read by public.fleet_tally, public.fleet_state, public.stats_fleets_count and public.stats_fleet_list_rows. Server-only.';
  comment on function public.fleet_state(uuid) is '0448: one fleet''s state now (sea, port, battle, laid_up, wrecked), from public.fleet_census. Read by world.stats_fleet. Server-only.';
  comment on function public.fleet_tally() is
    '0448: THE ONE COUNT of the Stats'' four kinds: fleets, ships, the fleets in each of the five states and the ships in each (ships_by). fleets = the sum of the five. Stored by the Stats count (public.stats_fleets_count, public.stats_fleet_list_rows, public.stats_merchant_fleets); every face reads the stored count. Server-only.';

  -- ── 3. THE HUNKS ──
  create temp table hunk_0448 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunk_0448 values
  -- public.stats_fleets_count: the three copies of the rule go; the counts are the tally's
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$  with
  nv as (select n.nation_id, n.fought_at, n.fought, f.status, s.ships,
$h$,
$h$  with
  -- 0448: THE ONE COUNT (public.fleet_tally) and THE ONE READING of a fleet's state (public.fleet_census): this body no longer decides a state
  tl as materialized (select public.fleet_tally() as t),
  nv as (select n.nation_id, n.fought_at, n.fought, f.status, s.ships,
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 2,
$h$    'merchants', jsonb_build_object('ships', (select count(*) from public.npc_fleets nf join public.ships x on x.fleet_id = nf.fleet_id)),
    'navy', (select jsonb_build_object('fleets', count(*), 'ships', coalesce(sum(nv.ships), 0),
                                       'sea', count(*) filter (where nv.state = 'sea'), 'port', count(*) filter (where nv.state = 'port'),
                                       'laid_up', count(*) filter (where nv.state = 'laid_up'), 'wrecked', count(*) filter (where nv.state = 'wrecked'),
                                       'nations', coalesce((select jsonb_agg(jsonb_build_array(z.code, z.fleets, z.ships) order by z.ships desc, z.code)
                                                              from (select na.code, count(*) as fleets, sum(y.ships) as ships
                                                                      from nv y join public.nations na on na.id = y.nation_id group by na.code) z), '[]'::jsonb))
               from nv),
    'pirates', (select jsonb_build_object('fleets', count(*), 'ships', coalesce(sum(pr.ships), 0),
                                          'sea', count(*) filter (where pr.state = 'sea'), 'port', count(*) filter (where pr.state = 'port'),
                                          'laid_up', count(*) filter (where pr.state = 'laid_up'), 'wrecked', count(*) filter (where pr.state = 'wrecked'),
                                          'wrecked_rows', count(*) filter (where pr.wrecked_at <= p_now),
                                          'roster', (select count(*) from public.pirate_roster),
                                          'homes', coalesce((select jsonb_agg(jsonb_build_array(z.code, z.name, z.fleets, z.ships) order by z.ships desc, z.code)
                                                               from (select po.code, po.name, count(*) as fleets, sum(y.ships) as ships
                                                                       from pr y join public.ports po on po.id = y.home_port group by po.code, po.name) z), '[]'::jsonb))
                  from pr),
    'cargo', (select jsonb_build_object('fleets', count(*), 'ships', coalesce(sum(cg.ships), 0),
                                        'sea', count(*) filter (where cg.state = 'sea'), 'port', count(*) filter (where cg.state = 'port'),
                                        'laid_up', count(*) filter (where cg.state = 'laid_up'), 'wrecked', count(*) filter (where cg.state = 'wrecked'),
                                        'tuns', round(coalesce(sum(cg.tuns), 0)), 'tuns_at_sea', round(coalesce(sum(cg.tuns) filter (where cg.state = 'sea'), 0)),
                                        'funds', public.funds_aboard())
                from cg),
$h$,
$h$    -- 0448: each kind's fleets, ships and five states are public.fleet_tally's (fleets = sea + port + battle + laid_up + wrecked); beside them its own figures
    'merchants', (select tl.t -> 'MERCHANT' from tl),
    'navy', (select tl.t -> 'NAVY' from tl) || jsonb_build_object(
                                       'nations', coalesce((select jsonb_agg(jsonb_build_array(z.code, z.fleets, z.ships) order by z.ships desc, z.code)
                                                              from (select na.code, count(*) as fleets, sum(y.ships) as ships
                                                                      from nv y join public.nations na on na.id = y.nation_id group by na.code) z), '[]'::jsonb)),
    'pirates', (select tl.t -> 'PIRATE' from tl) || jsonb_build_object(
                                          'wrecked_rows', (select count(*) from pr where pr.wrecked_at <= p_now),
                                          'roster', (select count(*) from public.pirate_roster),
                                          'homes', coalesce((select jsonb_agg(jsonb_build_array(z.code, z.name, z.fleets, z.ships) order by z.ships desc, z.code)
                                                               from (select po.code, po.name, count(*) as fleets, sum(y.ships) as ships
                                                                       from pr y join public.ports po on po.id = y.home_port group by po.code, po.name) z), '[]'::jsonb)),
    'cargo', (select tl.t -> 'CARGO' from tl) || jsonb_build_object(
                                        'tuns', (select round(coalesce(sum(cg.tuns), 0)) from cg),
                                        'tuns_at_sea', (select round(coalesce(sum(cg.tuns) filter (where cg.state = 'sea'), 0)) from cg),
                                        'funds', public.funds_aboard()),
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 3,
$h$  nv as (select n.nation_id, n.fought_at, n.fought, f.status, s.ships,
                case when n.laid_up_at is not null then 'laid_up' when not s.alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end as state
$h$,
$h$  nv as (select n.nation_id, n.fought_at, n.fought, f.status, s.ships
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 4,
$h$  pr as (select n.home_port, n.wrecked_at, s.ships,
                case when n.laid_up_at is not null then 'laid_up' when n.wrecked_at is not null or not s.alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end as state
$h$,
$h$  pr as (select n.home_port, n.wrecked_at, s.ships
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 5,
$h$                case when c.laid_up_at is not null then 'laid_up' when not s.alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end as state
           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id and c.laid_up_at is null   -- 0437: a retired (laid-up) cargo ship is out of the fleet's count
$h$,
$h$                z.state   -- 0448: public.fleet_census
           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id and c.laid_up_at is null   -- 0437: a retired (laid-up) cargo ship is out of the fleet's count
           join public.fleet_census() z on z.fleet_id = c.fleet_id and z.counted   -- 0448: her state, and the same ships the tally counts
$h$),
    -- public.stats_fleet_list_rows: a fleet's state is the census's, the header is the tally's
  ('public.stats_fleet_list_rows(text,timestamp with time zone)', 1,
$h$           case when f.laid is not null then 'laid_up' when f.wreck is not null or not x.alive then 'wrecked' when fl.status = 'SAILING' then 'sea' else 'port' end as state
      from f join public.fleets fl on fl.id = f.id
$h$,
$h$           z.state   -- 0448: public.fleet_census, THE ONE AUTHORITY
      from f join public.fleets fl on fl.id = f.id
      join public.fleet_census() z on z.fleet_id = f.id and z.counted   -- 0448: the fleets the tally counts, each in the state it counts her in
$h$),
  ('public.stats_fleet_list_rows(text,timestamp with time zone)', 2,
$h$  select jsonb_build_object(
    'kind', p_kind,
    'fleets', (select count(*) from s), 'ships', (select coalesce(sum(s.ships), 0) from s),
    'sea', (select count(*) from s where s.state = 'sea'), 'port', (select count(*) from s where s.state = 'port'),
    'laid_up', (select count(*) from s where s.state = 'laid_up'), 'wrecked', (select count(*) from s where s.state = 'wrecked'),
$h$,
$h$  select coalesce(public.fleet_tally() -> p_kind, '{}'::jsonb) || jsonb_build_object(   -- 0448: the header is THE ONE COUNT's, as the Ships face's card is
    'kind', p_kind,
$h$),
  -- public.tick_stats: one statement writes the fleets' row and the lists
  ('public.tick_stats(timestamp with time zone)', 1,
$h$  insert into public.stats_fleets (slot, at, figures)
  values (v_slot, p_now, public.stats_fleets_count(v_prev_at, p_now))
  on conflict (slot) do nothing;
  get diagnostics v_fl = row_count;
  delete from public.stats_fleets x where x.at < p_now - interval '26 hours';
  -- 0431: THE NAVY, PIRATES AND CARGO FACES (the owner, 2026-11-15: "a separate tab for navy, pirates, and cargoships like merchants"): one row a
  -- kind, replaced (public.stats_fleet_list_rows); and the fleets' book and lines kept 8 days.
  -- budget: 3 rows written a count; the book's hours older than 8 days deleted (about what one hour wrote 8 days ago: ~130-250 rows) and lines past 8 days (a few rows); ~45,000 small book rows read
  insert into public.stats_fleet_list (kind, at, figures)
  select k.kind, p_now, public.stats_fleet_list_rows(k.kind, p_now) from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)
  on conflict (kind) do update set at = excluded.at, figures = excluded.figures;
$h$,
$h$  -- 0431: THE NAVY, PIRATES AND CARGO FACES (the owner, 2026-11-15: "a separate tab for navy, pirates, and cargoships like merchants"): one row a
  -- kind, replaced (public.stats_fleet_list_rows); and the fleets' book and lines kept 8 days.
  -- budget: 3 rows written a count; the book's hours older than 8 days deleted (about what one hour wrote 8 days ago: ~130-250 rows) and lines past 8 days (a few rows); ~45,000 small book rows read
  -- 0448: ONE STATEMENT writes the fleets' row and the three lists, so both are one view of the sea (they were two statements: a fleet that sailed
  -- between them was at sea on one face and in port on another). Their counts are public.fleet_tally's, their states public.fleet_census's.
  with l as (
    insert into public.stats_fleet_list (kind, at, figures)
    select k.kind, p_now, public.stats_fleet_list_rows(k.kind, p_now) from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)
    on conflict (kind) do update set at = excluded.at, figures = excluded.figures
    returning 1)
  insert into public.stats_fleets (slot, at, figures)
  values (v_slot, p_now, public.stats_fleets_count(v_prev_at, p_now))
  on conflict (slot) do nothing;
  get diagnostics v_fl = row_count;
  delete from public.stats_fleets x where x.at < p_now - interval '26 hours';
$h$),
  -- public.stats_merchant_fleets: the count's merchants row is the tally's
  ('public.stats_merchant_fleets()', 1,
$h$  select jsonb_build_object(
           'houses',    (select count(*) from public.npc_houses),
           'fleets',    (select count(*) from public.npc_fleets),
           'sailing',   count(*) filter (where f.status = 'SAILING'),
           'docked',    count(*) filter (where f.status in ('DOCKED', 'ANCHORED')),
           'repairing', count(*) filter (where f.status = 'REPAIRING'),
           'unable',    count(*) filter (where f.status in ('UNABLE_TO_SAIL', 'ADRIFT')),
           'laid_up',   (select count(*) from public.npc_fleets nf join public.standing_routes r on r.id = nf.route_id
                          where r.paused_reason = 'laid_up'))
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
$h$,
$h$  -- 0448: THE ONE COUNT's merchants (public.fleet_tally), in the columns of public.stats_merchants: sailing = at sea, docked = in port,
  -- unable = wrecked, laid_up = laid up; a fleet in a battle is in none of them (the row's `fleets` less the four). `repairing` is in port: 0.
  select jsonb_build_object(
           'houses',    (select count(*) from public.npc_houses),
           'fleets',    (t.m ->> 'fleets')::int,
           'sailing',   (t.m ->> 'sea')::int,
           'docked',    (t.m ->> 'port')::int,
           'repairing', 0,
           'unable',    (t.m ->> 'wrecked')::int,
           'laid_up',   (t.m ->> 'laid_up')::int)
    from (select public.fleet_tally() -> 'MERCHANT' as m) t
$h$),
  -- world.stats_fleets: the merchants' card is the row's tally
  ('world.stats_fleets()', 1,
$h$           'merchants', case when m.slot is null then null else jsonb_build_object(
                          'houses', m.houses, 'fleets', m.fleets, 'ships', (f.figures -> 'merchants' ->> 'ships')::int,
                          'sea', m.sailing, 'port', greatest(0, m.fleets - m.sailing - m.laid_up - m.unable), 'laid_up', m.laid_up, 'wrecked', m.unable,
                          'profit_day', m.profit_day, 'laps_day', m.laps_day) end,
$h$,
$h$           -- 0448: the merchants' fleets, ships and five states are the row's own tally (public.fleet_tally), as the other three kinds' are
           'merchants', case when m.slot is null then null else (f.figures -> 'merchants') || jsonb_build_object(
                          'houses', m.houses, 'profit_day', m.profit_day, 'laps_day', m.laps_day) end,
$h$),
  -- world.stats_merchants: the face's states are the count's
  ('world.stats_merchants(text)', 1,
$h$  v_f := public.stats_merchant_fleets();
$h$,
$h$  -- 0448: where the fleets are is THE COUNT's (the newest public.stats_fleets row, public.fleet_tally's merchants), as on the Ships face. It was
  -- read live here, by another rule, so the two faces never said the same.
  v_f := coalesce((select x.figures -> 'merchants' from public.stats_fleets x order by x.slot desc limit 1), '{}'::jsonb);
$h$),
  ('world.stats_merchants(text)', 2,
$h$  return jsonb_build_object(
    'at', now(), 'counted_at', m.at, 'age_seconds', round(extract(epoch from now() - m.at)), 'slot_seconds', public.wc_num('drift_slot_seconds'), 'span', p_span,
    'houses', (v_f->>'houses')::int, 'fleets', (v_f->>'fleets')::int, 'sailing', (v_f->>'sailing')::int, 'docked', (v_f->>'docked')::int,
    'repairing', (v_f->>'repairing')::int, 'unable', (v_f->>'unable')::int, 'laid_up', (v_f->>'laid_up')::int, 'purse', v_p,
$h$,
$h$  return v_f || jsonb_build_object(   -- 0448: fleets, ships, sea, port, battle, laid_up, wrecked, ships_by: the count's tally, word for word
    'at', now(), 'counted_at', m.at, 'age_seconds', round(extract(epoch from now() - m.at)), 'slot_seconds', public.wc_num('drift_slot_seconds'), 'span', p_span,
    'houses', m.houses, 'purse', v_p,
$h$),
  ('world.stats_merchants(text)', 3,
$h$                                                      'sailing', (v_f->>'sailing')::int, 'laid_up', (v_f->>'laid_up')::int,
$h$,
$h$                                                      'sailing', (v_f->>'sea')::int, 'laid_up', (v_f->>'laid_up')::int,   -- 0448: the count's
$h$),
  -- world.stats_fleet: a fleet's page says the one word
  ('world.stats_fleet(uuid)', 1,
$h$    'state', case when v_laid is not null then 'laid_up' when v_wreck is not null or not v_alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end,
$h$,
$h$    'state', public.fleet_state(p_fleet),   -- 0448: THE ONE AUTHORITY, as of now (her line in the list is the count's)
$h$);

  for h in select * from hunk_0448 order by fn, ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0448 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0448 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0448 p where p.fn = h.fn) then
      raise exception '0448 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0448 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0448 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0448 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select count(distinct x.fn) from hunk_0448 x) <> cardinality(c_cut) then
    raise exception '0448 self-assert FAIL: a body named in the cut has no hunk';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)
         and not exists (select 1 from unnest(c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0448 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from unnest(c_new) f where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute'))
     or (select p.provolatile from pg_proc p where p.oid = c_new[1]::regprocedure) <> 'i'
     or exists (select 1 from unnest(c_new[2:4]) f join pg_proc p on p.oid = f::regprocedure where p.provolatile <> 's') then
    raise exception '0448 self-assert FAIL: a new function is open to a client, the rule is not IMMUTABLE or a reading is not STABLE';
  end if;
  -- no body of the Stats decides a state any more: the old rule's words are gone from every re-cut body
  if exists (select 1 from unnest(c_cut) f where pg_get_functiondef(f::regprocedure) like '%then ''sea'' else ''port''%') then
    raise exception '0448 self-assert FAIL: a Stats body still decides a fleet''s state for itself';
  end if;

  -- ── 4. THE RULE'S WHOLE TRUTH TABLE (pure) ──
  if exists (
    select 1 from (values (true), (false), (null::boolean)) a(l), (values (true), (false), (null::boolean)) b(w),
                  (values (true), (false), (null::boolean)) c(bt), (values (true), (false), (null::boolean)) d(s)
     where public.fleet_state_of(a.l, b.w, c.bt, d.s) is distinct from
           case when a.l is true then 'laid_up' when b.w is true then 'wrecked' when c.bt is true then 'battle' when d.s is true then 'sea' else 'port' end) then
    raise exception '0448 self-assert FAIL: the rule is not laid_up, wrecked, battle, sea, port in that order over its 81 inputs';
  end if;

  -- ── 5. THE NEWEST COUNT, RE-STATED ONCE (one statement: the row's tally and the three lists are one view) ──
  with r as (
    update public.stats_fleets x
       set figures = x.figures || (select jsonb_build_object(
                       'merchants', t.t -> 'MERCHANT',
                       'navy', coalesce(x.figures -> 'navy', '{}'::jsonb) || (t.t -> 'NAVY'),
                       'pirates', coalesce(x.figures -> 'pirates', '{}'::jsonb) || (t.t -> 'PIRATE'),
                       'cargo', coalesce(x.figures -> 'cargo', '{}'::jsonb) || (t.t -> 'CARGO')) from (select public.fleet_tally() as t) t)
     where x.slot = (select max(y.slot) from public.stats_fleets y)
    returning 1)
  update public.stats_fleet_list l set figures = public.stats_fleet_list_rows(l.kind, l.at);

  -- ── 6. THE PROBE, rolled back: four merchant fleets borrowed, a planted count read back through every face ──
  begin
    v_t := public.fleet_tally();
    select array_agg(z.fleet_id) into v_f
      from (select c.fleet_id from public.fleet_census() c
             where c.kind = 'MERCHANT' and c.counted and c.state in ('sea', 'port')
               and exists (select 1 from public.npc_fleets nf where nf.fleet_id = c.fleet_id and nf.route_id is not null)
             order by c.fleet_id limit 4) z;
    if coalesce(cardinality(v_f), 0) = 4 then
      v_was := public.fleet_state(v_f[4]);
      -- one laid up, one wrecked, one on a battle being fought, one left alone
      update public.standing_routes r set paused_reason = 'laid_up' where r.id = (select nf.route_id from public.npc_fleets nf where nf.fleet_id = v_f[1]);
      update public.ships s set durability = 0 where s.fleet_id = v_f[2];
      insert into public.battles (kind, site, started_at, resolves_at, status)
      values ('PROBE', '{"lat": 0, "lon": 0}'::jsonb, now(), now() + interval '1 minute', 'FIGHTING') returning id into v_b;
      insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_f[3], 'DEFENDER', now(), now());
      if public.fleet_state(v_f[1]) <> 'laid_up' or public.fleet_state(v_f[2]) <> 'wrecked' or public.fleet_state(v_f[3]) <> 'battle'
         or public.fleet_state(v_f[4]) <> v_was or public.fleet_state(gen_random_uuid()) is not null then
        raise exception '0448 self-assert FAIL: the borrowed fleets read %, %, %, % (wanted laid_up, wrecked, battle, %)',
          public.fleet_state(v_f[1]), public.fleet_state(v_f[2]), public.fleet_state(v_f[3]), public.fleet_state(v_f[4]), v_was;
      end if;
      v_t2 := public.fleet_tally();
      if (v_t2 #>> '{MERCHANT,fleets}')::int <> (v_t #>> '{MERCHANT,fleets}')::int
         or (v_t2 #>> '{MERCHANT,laid_up}')::int <> (v_t #>> '{MERCHANT,laid_up}')::int + 1
         or (v_t2 #>> '{MERCHANT,wrecked}')::int <> (v_t #>> '{MERCHANT,wrecked}')::int + 1
         or (v_t2 #>> '{MERCHANT,battle}')::int <> (v_t #>> '{MERCHANT,battle}')::int + 1
         or (v_t2 #>> '{MERCHANT,sea}')::int + (v_t2 #>> '{MERCHANT,port}')::int <> (v_t #>> '{MERCHANT,sea}')::int + (v_t #>> '{MERCHANT,port}')::int - 3 then
        raise exception '0448 self-assert FAIL: the tally did not move by the three borrowed fleets: % -> %', v_t -> 'MERCHANT', v_t2 -> 'MERCHANT';
      end if;
      -- all three marks on one fleet: laid up comes first
      update public.ships s set durability = 0 where s.fleet_id = v_f[1];
      insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_f[1], 'DEFENDER', now(), now());
      if public.fleet_state(v_f[1]) <> 'laid_up' then
        raise exception '0448 self-assert FAIL: a fleet laid up, wrecked and in a battle reads %', public.fleet_state(v_f[1]);
      end if;
      v_note := 'four merchant fleets borrowed: laid_up, wrecked, battle and one unmoved; the tally moved by those three';
    else
      v_note := 'no four merchant fleets in this world to borrow';
    end if;

    -- every kind: fleets = the five states, ships = ships_by; one row a fleet
    v_t := public.fleet_tally();
    foreach v_k in array array['MERCHANT', 'NAVY', 'PIRATE', 'CARGO'] loop
      if (v_t -> v_k) is null
         or (v_t -> v_k ->> 'fleets')::int <> (select sum((v_t -> v_k ->> s)::int) from unnest(c_states) s)
         or (v_t -> v_k ->> 'ships')::int <> (select sum((v_t -> v_k -> 'ships_by' ->> s)::int) from unnest(c_states) s) then
        raise exception '0448 self-assert FAIL: the tally of % is not whole: %', v_k, v_t -> v_k;
      end if;
    end loop;
    if exists (select 1 from public.fleet_census() c group by c.fleet_id having count(*) > 1)
       or exists (select 1 from public.fleet_census() c where c.state is null or c.state <> all (c_states)) then
      raise exception '0448 self-assert FAIL: the census holds a fleet twice, or in no state';
    end if;

    -- a planted count (the count's own statement), read back through every face
    select coalesce(max(x.slot), 0) + 1 into v_slot from public.stats_fleets x;
    with l as (
      insert into public.stats_fleet_list (kind, at, figures)
      select k.kind, now(), public.stats_fleet_list_rows(k.kind, now()) from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)
      on conflict (kind) do update set at = excluded.at, figures = excluded.figures
      returning 1)
    insert into public.stats_fleets (slot, at, figures) values (v_slot, now(), public.stats_fleets_count(now() - interval '15 minutes', now()));
    v_r := world.stats_fleets();
    for h in select * from (values ('NAVY', 'navy'), ('PIRATE', 'pirates'), ('CARGO', 'cargo')) k(kind, key) loop
      v_l := world.stats_fleet_list(h.kind);
      select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) into v_s
        from (select e ->> 'state' as st, count(*) as n from jsonb_array_elements(v_l -> 'list') e group by 1) z;
      if (v_l ->> 'counted_at') is distinct from (v_r ->> 'counted_at') or (v_l -> 'ships_by') is distinct from (v_r -> h.key -> 'ships_by')
         or exists (select 1 from unnest(c_states || array['fleets', 'ships']) s where (v_l -> s) is null or (v_l -> s) <> (v_r -> h.key -> s))
         or exists (select 1 from unnest(c_states) s where (v_l ->> s)::int <> coalesce((v_s ->> s)::int, 0))
         or jsonb_array_length(v_l -> 'list') <> (v_l ->> 'fleets')::int
         or (v_l ->> 'fleets')::int <> (select sum((v_l ->> s)::int) from unnest(c_states) s) then
        raise exception '0448 self-assert FAIL: the % face is not the Ships face''s card, or not its own rows: header %, card %, rows %', h.kind, v_l - 'list' - 'day' - 'week', v_r -> h.key, v_s;
      end if;
    end loop;
    if exists (select 1 from public.stats_merchants) then
      v_l := world.stats_merchants(null);
      if (v_r -> 'merchants') is null or (v_l -> 'ships_by') is distinct from (v_r -> 'merchants' -> 'ships_by')
         or exists (select 1 from unnest(c_states || array['fleets', 'ships', 'houses']) s where (v_l -> s) is null or (v_l -> s) <> (v_r -> 'merchants' -> s))
         or (v_l ->> 'fleets')::int <> (select sum((v_l ->> s)::int) from unnest(c_states) s)
         or v_l ? 'docked' or v_l ? 'unable' then
        raise exception '0448 self-assert FAIL: the Merchants face is not the Ships face''s merchants: % against %', v_l - 'list' - 'series' - 'top' - 'bottom', v_r -> 'merchants';
      end if;
      v_note := v_note || '; the Merchants face equals the Ships face''s merchants';
    end if;
    select n.fleet_id into v_b from public.navy_ships n order by n.fleet_id limit 1;
    if v_b is not null and world.stats_fleet(v_b) ->> 'state' is distinct from public.fleet_state(v_b) then
      raise exception '0448 self-assert FAIL: a navy ship''s page does not say her state';
    end if;
    v_note := v_note || format('; a planted count read back: every list header is the Ships face''s card and its own rows (merchants %s, navy %s, pirates %s, cargo %s fleets)',
                               v_r -> 'merchants' ->> 'fleets', v_r -> 'navy' ->> 'fleets', v_r -> 'pirates' ->> 'fleets', v_r -> 'cargo' ->> 'fleets');
    raise exception sqlstate 'BV448';
  exception when sqlstate 'BV448' then null;
  end;
  if to_regprocedure('public.fleet_tally()') is null or v_note not like '%a planted count read back%' then
    raise exception '0448 self-assert FAIL: the probe did not run to its end: %', v_note;
  end if;
  if exists (select 1 from public.battles b where b.kind = 'PROBE' and b.status = 'FIGHTING') then
    raise exception '0448 self-assert FAIL: the probe was not rolled back';
  end if;

  perform public.news_update('0448', 'Stats: every tab counts ships the same way', '통계: 모든 탭이 선박을 같은 방식으로 셉니다');
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0448 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0448 self-assert ok: THE STATS COUNT ONCE. Fourteen hunks over seven bodies, each once and reversing; grants and volatility unmoved; no other function moved; public.fleet_state_of (the rule, its 81 inputs), public.fleet_census, public.fleet_state, public.fleet_tally (server-only). Probe: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
