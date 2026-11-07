-- 0335 PROD CHECK, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/realm-pays/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regprocedure, replace) or a count. No game function is called.
-- Wanted: every `times` 1; new_fns 0; navy_on false; navy_rows 0; probe_codes 0; call_kind 'moved'; head the number before 0335.
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.crown_call(jsonb)'::regprocedure, 1, $h$-- that lock; a busy one is passed over till the next hour. Answers {called, donors}.
$h$),
  ('public.crown_call(jsonb)'::regprocedure, 2, $h$    for d in select h.id
               from public.ports h join public.port_treasury t on t.port_id = h.id
              cross join lateral (select public.crown_call_room(h.id) as room) c
              where h.kind = 'HARBOUR' and h.id <> k.cap and public.city_capital(h.id) = k.cap and c.room > 0
              order by c.room desc, h.code loop
$h$),
  ('public.navy_add(timestamp with time zone,uuid)'::regprocedure, 1, $h$-- BUILT, when her capital's surplus covers the class and a yard can be reached. A CAPITAL THAT CANNOT PAY JUST WAITS: nothing is written, and it is asked again next run, so a hull appears the run its capital can pay, and never before.
-- The surplus is read twice: once with no lock, so a poor capital is never locked, and again under the lock, which is what counts. A busy capital is passed over. Answers BUILT, WOKEN or null.
$h$),
  ('public.navy_add(timestamp with time zone,uuid)'::regprocedure, 2, $h$    continue when v_cap is null or v_st is null or public.city_surplus(v_cap) < v_need;
$h$),
  ('public.navy_add(timestamp with time zone,uuid)'::regprocedure, 3, $h$    continue when not public.treasury_try_lock(v_cap);
    continue when public.city_surplus(v_cap) < v_need;
$h$),
  ('public.navy_add(timestamp with time zone,uuid)'::regprocedure, 4, $h$      continue when v_yard is null;
      perform public.navy_commission(r.nation_id, v_ord, v_cap, v_yard, v_st, p_now);
$h$),
  ('public.navy_pay(timestamp with time zone,uuid)'::regprocedure, 1, $h$-- nothing. One row out and one row a harbour, so 46 stations write about 1,300 rows a day, whatever the ships. A busy capital is asked again next run. Answers the ducats moved.
$h$),
  ('public.navy_pay(timestamp with time zone,uuid)'::regprocedure, 2, $h$  v_can := floor(greatest(public.city_surplus(v_cap), 0) / v_slice);
$h$)
)
select jsonb_build_object(
  'hunks', (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'ord', h.ord,
                     'times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
              from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as def) d),
  'new_fns', (select count(*) from unnest(array['public.crown_donors(uuid)', 'public.capital_can_draw(uuid,bigint)', 'public.capital_draw(uuid,bigint,boolean)']) x where to_regprocedure(x) is not null),
  'navy_on', (select c.value from public.world_config c where c.key = 'navy_enabled'),
  'navy_rows', (select count(*) from public.navy_ships),
  'probe_codes', (select count(*) from public.ports p where p.code like 'QZ_') + (select count(*) from public.nations n where n.code = 'QX5'),
  'call_kind', (select w.side from public.stats_flow_words w where w.kind = 'CROWN_CALL'),
  'head', (select max(version) from supabase_migrations.schema_migrations)
) as checks;
commit;
