-- 0458 PROD CHECK, BEFORE the deploy (mules, Repeat and rare finds), read-only, one SELECT inside `begin transaction read only; ... commit;`:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/before-0458.sql
-- One row, one jsonb column `r`. It reads the catalog, the knobs and small tables (land_actions, land_parties, goods, regions, ports) and
-- port_goods for the land's goods in their regions (as before-0457 did): no volatile function.
-- Wanted: head 20260818000457; applied false; old_hunks every count 1; new_hunks every count 0 (else a deploy since re-cut a body: 0458
--   refuses); rows_as_0457 true; land_enabled false; land_yield_pct 100; parties 0; bal_harbour true; secret_ok true;
--   worst_job and worst_find: share at most 1 = THE GUARD on production's own port_goods with the top mule (30 packs, the least march
--   15 s, trips back to back), Mining 100, the best tool and the crowd's full chance; and the finds (generator's rows, one die a turn).
-- Generated from the migration's own hunks and scripts/build-land-migration.mjs --drops (the same text: the check cannot drift).
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.land_terms(uuid,text)', $h$  v_p := public.wc_int('land_pack_base');
$h$),
  (2, 'public.land_terms(uuid,text)', $h$    'short', v_short);$h$),
  (3, 'public.land_progress(uuid,timestamp with time zone)', $h$  v_trips := floor(v_e / v_trip);
$h$),
  (4, 'public.land_settle(uuid,timestamp with time zone)', $h$  v_end   boolean := false;
begin
$h$),
  (5, 'public.land_settle(uuid,timestamp with time zone)', $h$  if lp.action is not null then
    v_pr := public.land_progress(lp.id, p_at);
$h$),
  (6, 'public.land_settle(uuid,timestamp with time zone)', $h$      lp.booked := lp.booked + v_new;
$h$),
  (7, 'public.land_settle(uuid,timestamp with time zone)', $h$    if v_pr ->> 'state' = 'returning' and v_pr ->> 'phase' = 'home' then
$h$),
  (8, 'public.land_settle(uuid,timestamp with time zone)', $h$waiting = lp.waiting, waiting_good = lp.waiting_good
$h$),
  (9, 'public.land_settle(uuid,timestamp with time zone)', $h$'ended', v_end);$h$),
  (10, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  if lp.waiting > 0 then
$h$),
  (11, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$'over_cap') || jsonb_build_object('sent', floor(extract(epoch from p_at) * 1000)::bigint)
$h$),
  (12, 'public.land_door(text,text)', $h$      when 'tool'    then public.land_tool_for(v_player, p_arg) end;$h$),
  (13, 'world.land(text)', $h$      'tools', coalesce(to_jsonb(v_party.tools), '[]'::jsonb)),
$h$),
  (14, 'world.land(text)', $h$               'over_cap', (t.v ->> 'over_cap')::boolean,
$h$),
  (15, 'public.client_rpc_entry_points()', $h$      ('cmd',         'land_tool',             'text'),
$h$)
), hn(ord, fn, new) as (values
  (1, 'public.land_terms(uuid,text)', $h$  v_p := public.land_packs_of(v_party.mules);   -- 0458: the packs by the party's mules (land_pack_base with none)
$h$),
  (2, 'public.land_terms(uuid,text)', $h$    'short', v_short,
    -- 0458: the rare finds of the land the party would work: those of the job whose good lies on that land, in their order
    'finds', (select coalesce(jsonb_agg(jsonb_build_object('code', g.code, 'one_in', d.one_in) order by d.ord), '[]'::jsonb)
                from public.land_drops d join public.goods g on g.id = d.good_id
               where d.action = j.code and (v_pass ->> 'region') = any(g.origin_regions)));$h$),
  (3, 'public.land_progress(uuid,timestamp with time zone)', $h$  v_trips := floor(v_e / v_trip);
  -- 0458: Repeat off (terms.last): once its last trip is home the party is home, and the first press after ends the job
  if t ? 'last' and v_trips >= (t ->> 'last')::int then
    return jsonb_build_object('state', 'out', 'phase', 'home', 'done', true,
      'turns', (t ->> 'last')::int * v_p, 'new', greatest(0, (t ->> 'last')::int * v_p - lp.booked), 'trips', (t ->> 'last')::int,
      'in_packs', 0, 'u', 0, 'trip', v_trip, 'next_home_at', null, 'stopped', false, 'waiting', lp.waiting);
  end if;
$h$),
  (4, 'public.land_settle(uuid,timestamp with time zone)', $h$  v_end   boolean := false;
  -- 0458: rare finds
  v_found jsonb := '{}'::jsonb;
  v_f     record;
  v_g     public.goods%rowtype;
  v_n     int;
begin
$h$),
  (5, 'public.land_settle(uuid,timestamp with time zone)', $h$  -- 0458: rare finds that waited for room: as much as fits now
  for v_f in select e.key as code, e.value::int as qty from jsonb_each_text(lp.found_waiting) e order by e.key loop
    select * into v_g from public.goods where code = v_f.code;
    v_fit := floor(greatest(public.storage_cap(lp.port_id) - public.storage_used(lp.player_id, lp.port_id), 0) / v_g.bulk);
    v_n := least(v_f.qty, v_fit)::int;
    if v_n > 0 then
      perform public.storage_put(lp.player_id, lp.port_id, v_g.id, v_n, 0);
      lp.found_waiting := case when v_n = v_f.qty then lp.found_waiting - v_f.code
                               else jsonb_set(lp.found_waiting, array[v_f.code], to_jsonb(v_f.qty - v_n)) end;
    end if;
  end loop;
  if lp.action is not null then
    v_pr := public.land_progress(lp.id, p_at);
$h$),
  (6, 'public.land_settle(uuid,timestamp with time zone)', $h$      -- 0458: RARE FINDS, one die a turn (voyage.rng by party, turn and Send): the turn finds the first of the frozen finds whose share
      -- of [0, 1) holds the roll, each 1 / one_in wide; the same turns give the same finds however they are booked
      for v_f in
        select fx.code, count(*)::int as qty
          from generate_series(lp.booked + 1, lp.booked + v_new) n
          cross join lateral (select voyage.rng(lp.id, n, 'find:' || (lp.terms ->> 'sent')) as r) z
          join (select e ->> 'code' as code,
                       coalesce(sum(1.0 / (e ->> 'one_in')::numeric) over (order by o rows between unbounded preceding and 1 preceding), 0) as lo,
                       sum(1.0 / (e ->> 'one_in')::numeric) over (order by o) as hi
                  from jsonb_array_elements(coalesce(lp.terms -> 'finds', '[]'::jsonb)) with ordinality f(e, o)) fx
            on z.r >= fx.lo and z.r < fx.hi
         group by fx.code order by fx.code
      loop
        select * into v_g from public.goods where code = v_f.code;
        v_fit := floor(greatest(public.storage_cap(lp.port_id) - public.storage_used(lp.player_id, lp.port_id), 0) / v_g.bulk);
        v_n := least(v_f.qty, greatest(v_fit, 0))::int;
        if v_n > 0 then
          perform public.storage_put(lp.player_id, lp.port_id, v_g.id, v_n, 0);
        end if;
        if v_f.qty > v_n then
          lp.found_waiting := jsonb_set(lp.found_waiting, array[v_f.code], to_jsonb(coalesce((lp.found_waiting ->> v_f.code)::int, 0) + v_f.qty - v_n));
          v_end := true;
        end if;
        v_found := v_found || jsonb_build_object(v_f.code, v_f.qty);
      end loop;
      lp.booked := lp.booked + v_new;
$h$),
  (7, 'public.land_settle(uuid,timestamp with time zone)', $h$    if (v_pr ->> 'state' = 'returning' and v_pr ->> 'phase' = 'home') or coalesce((v_pr ->> 'done')::boolean, false) then   -- 0458: or Repeat's last trip home
$h$),
  (8, 'public.land_settle(uuid,timestamp with time zone)', $h$waiting = lp.waiting, waiting_good = lp.waiting_good,
         found_waiting = lp.found_waiting   -- 0458
$h$),
  (9, 'public.land_settle(uuid,timestamp with time zone)', $h$'ended', v_end,
                            'found', v_found, 'found_waiting', lp.found_waiting);   -- 0458: the rare finds this press booked or kept$h$),
  (10, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  if lp.waiting > 0 or lp.found_waiting <> '{}'::jsonb then   -- 0458: a rare find waiting is a haul waiting
$h$),
  (11, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$'over_cap') || jsonb_build_object('sent', floor(extract(epoch from p_at) * 1000)::bigint)
                 || case when lp.repeat_on then '{}'::jsonb else '{"last": 1}'::jsonb end   -- 0458: Repeat off: one trip
$h$),
  (12, 'public.land_door(text,text)', $h$      when 'tool'    then public.land_tool_for(v_player, p_arg)
      -- 0458: a mule; Repeat on or off
      when 'pack'    then public.land_pack_for(v_player)
      when 'repeat'  then public.land_repeat_for(v_player, p_arg::boolean, now()) end;$h$),
  (13, 'world.land(text)', $h$      'tools', coalesce(to_jsonb(v_party.tools), '[]'::jsonb),
      -- 0458: the mules, Repeat, and rare finds waiting for room
      'mules', coalesce(v_party.mules, 0), 'repeat', coalesce(v_party.repeat_on, true), 'found_waiting', coalesce(v_party.found_waiting, '{}'::jsonb)),
    -- 0458: what a trip carries now, and the next mule (null: it has them all)
    'packs', jsonb_build_object('now', public.land_packs_of(coalesce(v_party.mules, 0)),
                                'next', public.wc('land_packs') -> coalesce(v_party.mules, 0)),
$h$),
  (14, 'world.land(text)', $h$               'over_cap', (t.v ->> 'over_cap')::boolean,
               'finds', coalesce(t.v -> 'finds', '[]'::jsonb),   -- 0458
$h$),
  (15, 'public.client_rpc_entry_points()', $h$      ('cmd',         'land_tool',             'text'),
      -- 0458: a mule; Repeat on or off
      ('cmd',         'land_pack',             ''),
      ('cmd',         'land_repeat',           'boolean'),
$h$)
),
k as (
  select max(case when c.key = 'land_yield_pct' then (c.value #>> '{}')::numeric end) as yield,
         max(case when c.key = 'land_level_speed_pct' then (c.value #>> '{}')::numeric end) as lvl,
         max(case when c.key = 'land_crowd_max' then (c.value #>> '{}')::numeric end) as crowd,
         (select max(t.speed_pct) from public.land_tools t) as tool
    from public.world_config c where c.key in ('land_yield_pct', 'land_level_speed_pct', 'land_crowd_max')),
pace as (
  select a.code, a.good_id,
         30.0 * 3600 / (2 * (select min(s.march_seconds) from public.land_sites s where s.ground = a.ground)
                       + 30 * greatest(1, round(a.seconds * 100.0 / k.yield * (1 - k.lvl / 100 * 99) * (1 - k.tool / 100)))) as turns_h
    from public.land_actions a cross join k where a.kind = 'gather'),
mid as (
  select g.id as good_id, rg.code as region, percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
    from public.goods g
    cross join unnest(g.origin_regions) o(rc)
    join public.regions rg on rg.code = o.rc
    join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
    join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
   where g.id in (select a.good_id from public.land_actions a)
   group by g.id, rg.code),
drops(action, good, one_in) as (values ('iron', 'amber', 100), ('iron', 'baltic-amber', 100), ('iron', 'jade', 100), ('iron', 'nephrite', 100), ('clay', 'amber', 100), ('clay', 'baltic-amber', 100), ('clay', 'turquoise', 100), ('clay', 'carnelian', 100), ('clay', 'malachite', 100), ('clay', 'onyx', 100), ('clay', 'lapis-lazuli', 100), ('clay', 'opals', 100), ('clay', 'peridot', 100), ('clay', 'jade', 100), ('clay', 'nephrite', 100), ('clay', 'pounamu', 100), ('clay', 'emeralds', 100), ('clay', 'emerald-muzo', 100), ('clay', 'rubies', 100), ('clay', 'burma-rubies', 100), ('clay', 'ceylon-sapphires', 100), ('clay', 'diamonds', 100), ('clay', 'golconda-diamonds', 100), ('stone', 'amber', 100), ('stone', 'baltic-amber', 100), ('stone', 'carnelian', 100), ('stone', 'onyx', 100), ('stone', 'opals', 100), ('stone', 'jade', 100), ('stone', 'nephrite', 100), ('stone', 'pounamu', 100), ('stone', 'emeralds', 100), ('stone', 'emerald-muzo', 100), ('stone', 'rubies', 100), ('stone', 'diamonds', 100), ('stone', 'golconda-diamonds', 100), ('sand', 'amber', 100), ('sand', 'baltic-amber', 100), ('sand', 'turquoise', 100), ('sand', 'carnelian', 100), ('sand', 'malachite', 100), ('sand', 'onyx', 100), ('sand', 'lapis-lazuli', 100), ('sand', 'opals', 100), ('sand', 'peridot', 100), ('sand', 'jade', 100), ('sand', 'nephrite', 100), ('sand', 'pounamu', 100), ('sand', 'emeralds', 100), ('sand', 'emerald-muzo', 100), ('sand', 'rubies', 100), ('sand', 'burma-rubies', 100), ('sand', 'ceylon-sapphires', 100), ('sand', 'diamonds', 100), ('sand', 'golconda-diamonds', 100), ('copper', 'amber', 100), ('copper', 'baltic-amber', 100), ('copper', 'turquoise', 100), ('copper', 'onyx', 100), ('copper', 'lapis-lazuli', 100), ('copper', 'peridot', 100), ('salt', 'amber', 100), ('salt', 'baltic-amber', 100), ('salt', 'turquoise', 100), ('salt', 'carnelian', 100), ('salt', 'malachite', 100), ('salt', 'onyx', 100), ('salt', 'lapis-lazuli', 100), ('salt', 'opals', 100), ('salt', 'peridot', 100), ('salt', 'jade', 100), ('salt', 'nephrite', 100), ('salt', 'pounamu', 100), ('salt', 'emeralds', 100), ('salt', 'rubies', 100), ('salt', 'diamonds', 100), ('salt', 'golconda-diamonds', 100), ('tin', 'rubies', 100), ('tin', 'burma-rubies', 100), ('tin', 'ceylon-sapphires', 100), ('tin', 'diamonds', 100), ('tin', 'golconda-diamonds', 100), ('lead', 'amber', 100), ('lead', 'baltic-amber', 100), ('lime', 'amber', 100), ('lime', 'baltic-amber', 100), ('lime', 'turquoise', 100), ('lime', 'carnelian', 100), ('lime', 'malachite', 100), ('lime', 'onyx', 100), ('lime', 'lapis-lazuli', 100), ('lime', 'opals', 100), ('lime', 'peridot', 100), ('lime', 'jade', 100), ('lime', 'nephrite', 100), ('lime', 'pounamu', 100), ('lime', 'emeralds', 100), ('lime', 'emerald-muzo', 100), ('lime', 'rubies', 100), ('lime', 'burma-rubies', 100), ('lime', 'ceylon-sapphires', 100), ('lime', 'diamonds', 100), ('lime', 'golconda-diamonds', 100), ('gypsum', 'onyx', 100), ('gypsum', 'jade', 100), ('saltpetre', 'carnelian', 100), ('saltpetre', 'rubies', 100), ('saltpetre', 'diamonds', 100), ('saltpetre', 'golconda-diamonds', 100), ('zinc-spelter', 'rubies', 100), ('zinc-spelter', 'diamonds', 100), ('zinc-spelter', 'golconda-diamonds', 100), ('feldspar', 'carnelian', 100), ('feldspar', 'jade', 100), ('feldspar', 'nephrite', 100), ('feldspar', 'burma-rubies', 100), ('feldspar', 'ceylon-sapphires', 100), ('feldspar', 'diamonds', 100), ('quartz', 'carnelian', 100), ('quartz', 'jade', 100), ('quartz', 'nephrite', 100), ('quartz', 'rubies', 100), ('quartz', 'burma-rubies', 100), ('quartz', 'ceylon-sapphires', 100), ('quartz', 'diamonds', 100), ('quartz', 'golconda-diamonds', 100), ('silver', 'nephrite', 100), ('silver', 'emeralds', 100), ('silver', 'emerald-muzo', 100), ('antimony', 'jade', 100), ('cobalt', 'turquoise', 100), ('cobalt', 'lapis-lazuli', 100), ('cobalt', 'peridot', 100), ('bar-iron', 'amber', 100), ('bar-iron', 'baltic-amber', 100), ('gold', 'malachite', 100), ('gold', 'onyx', 100), ('gold', 'jade', 100), ('gold', 'emeralds', 100), ('gold', 'burma-rubies', 100), ('gold', 'ceylon-sapphires', 100), ('gold', 'diamonds', 100), ('amber', 'baltic-amber', 100), ('baltic-amber', 'amber', 100), ('lodestone', 'jade', 100), ('potosi-silver', 'emerald-muzo', 100), ('turquoise', 'lapis-lazuli', 100), ('turquoise', 'peridot', 100), ('lapis-lazuli', 'turquoise', 100), ('lapis-lazuli', 'peridot', 100), ('opals', 'pounamu', 100), ('peridot', 'turquoise', 100), ('peridot', 'lapis-lazuli', 100), ('pounamu', 'opals', 100), ('rubies', 'diamonds', 100), ('rubies', 'golconda-diamonds', 100), ('burma-rubies', 'ceylon-sapphires', 100), ('burma-rubies', 'diamonds', 100), ('ceylon-sapphires', 'burma-rubies', 100), ('ceylon-sapphires', 'diamonds', 100), ('diamonds', 'rubies', 100), ('diamonds', 'burma-rubies', 100), ('diamonds', 'ceylon-sapphires', 100), ('diamonds', 'golconda-diamonds', 100), ('golconda-diamonds', 'rubies', 100), ('golconda-diamonds', 'diamonds', 100), ('platinum', 'emerald-muzo', 100)),
share as (
  select 'job' as kind, pace.code, null::text as find, mid.region, mid.target, round(pace.turns_h * (1 + k.crowd / 100) / (mid.target / 100.0), 4) as share
    from pace join mid on mid.good_id = pace.good_id cross join k
  union all
  select 'find', d.action, d.good, mid.region, mid.target, round(pace.turns_h / d.one_in / (mid.target / 100.0), 4)
    from drops d join pace on pace.code = d.action join public.goods g on g.code = d.good join mid on mid.good_id = g.id)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regclass('public.land_drops') is not null or exists (select 1 from public.world_config c where c.key = 'land_packs')
             or exists (select 1 from pg_attribute a where a.attrelid = 'public.land_parties'::regclass and a.attname = 'mules' and not a.attisdropped),
  'old_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old))
                  from hk h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'new_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new))
                  from hn h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'rows_as_0457', (select md5(string_agg(a.code || ':' || a.seconds || ':' || a.xp, ',' order by a.ord)) from public.land_actions a) = 'bd9026a3e5eb6ef5f240215fa438e73f',
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'land_yield_pct', (select c.value from public.world_config c where c.key = 'land_yield_pct'),
  'parties', (select count(*) from public.land_parties),
  'knobs', (select to_jsonb(k) from k),
  'bal_harbour', exists (select 1 from public.ports p join public.regions r on r.id = p.region_id where r.code = 'BAL' and p.kind = 'HARBOUR'),
  'secret_ok', (select length(c.value #>> '{}') >= 64 from public.world_config c where c.key = 'world_secret'),
  'job_regions', (select count(*) from share s where s.kind = 'job'),
  'find_regions', (select count(*) from share s where s.kind = 'find'),
  'worst_job', (select jsonb_build_object('code', s.code, 'region', s.region, 'target', s.target, 'share', s.share) from share s where s.kind = 'job' order by s.share desc, s.code limit 1),
  'worst_find', (select jsonb_build_object('code', s.code, 'find', s.find, 'region', s.region, 'target', s.target, 'share', s.share) from share s where s.kind = 'find' order by s.share desc, s.code limit 1)) as r;
commit;
