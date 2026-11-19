-- 0458 PROD CHECK, AFTER the deploy (mules, Repeat and rare finds), read-only, one SELECT inside `begin transaction read only; ... commit;`:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/after-0458.sql
-- Calls no function but the catalog's own (pg_get_functiondef, to_regprocedure) and reads small tables.
-- Wanted: head 20260818000458; drops 167; land_packs the four mules; columns mules / repeat_on / found_waiting true;
--   doors both true; new_hunks every count 1; land_enabled false; land_yield_pct 100; parties 0.
begin transaction read only;
with hn(ord, fn, new) as (values
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
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'drops', (select count(*) from public.land_drops),
  'land_packs', (select c.value from public.world_config c where c.key = 'land_packs'),
  'columns', (select jsonb_object_agg(a.attname, true) from pg_attribute a where a.attrelid = 'public.land_parties'::regclass
               and a.attname in ('mules', 'repeat_on', 'found_waiting') and not a.attisdropped),
  'doors', jsonb_build_object('land_pack', to_regprocedure('cmd.land_pack()') is not null, 'land_repeat', to_regprocedure('cmd.land_repeat(boolean)') is not null),
  'new_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new))
                  from hn h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'land_yield_pct', (select c.value from public.world_config c where c.key = 'land_yield_pct'),
  'parties', (select count(*) from public.land_parties)) as r;
commit;
