-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 206 - THE CHART IS BLACK UNTIL SHE SAILS  (migration 0504, dark: chart_fog_enabled; docs/dev-log/2026-11-25-chart-fog.md)
--
--   The owner: "The MAP itself will be black, and your fleet will provide a radius ... larger based on your NAVIGATION SKILL ... where
--   your fleets moved and been will be in grey". Played on the proof's own company and its own hand-made courses: nothing here reads a
--   price, a roll of the sea's dice or how old the world is. Rolled back by proof.mjs.
--
-- @pass CF_DARK      dark: an arrival through the real arm writes no chart row, the read is {"on": false}, the backfill is the only thing that may write
-- @pass CF_ARRIVAL   lit: ONE row for her company after an arrival, the squares under both ends of the course set, none out of her sight of it; the same course again writes nothing
-- @pass CF_SIGHT     her sight is the one knob and a third of it more for each NAVIGATION level; a wider sight paints a wider grey
-- @pass CF_MERCHANT  a merchant's arrival writes nothing, the backfill refuses her, the read gives her no company
-- @pass CF_BACKFILL  every live company is backfilled in bounded calls until none is left; no company loses a city of her logbook: each one's square is on her chart
-- @pass CF_REACH     the fog refuses nothing: lit, with a black chart, her SAIL to a harbour she has never seen is accepted with the same miles as it is dark; no door, path or job reads the chart
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0504-4000-8000-0000000002a1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_set  uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_la   record; v_sa record;
  v_segs jsonb; v_a uuid; v_f uuid; v_voy uuid; v_eta timestamptz; v_st text;
  v_c    bytea; v_c2 bytea; v_r jsonb; v_n int; v_n2 int; v_stray int; v_npc uuid; v_nv uuid;
  v_s0   numeric; v_s3 numeric; v_left int; v_calls int := 0; v_lost int; v_co int;
  v_far  text; v_p0 jsonb; v_p1 jsonb; v_readers text;
begin
  select a.roadstead_lat as lat, a.roadstead_lon as lon into v_la from public.sea_reaches a where a.port_id = v_lis;
  select a.roadstead_lat as lat, a.roadstead_lon as lon into v_sa from public.sea_reaches a where a.port_id = v_set;
  if v_la.lat is null or v_sa.lat is null then
    raise exception 'CF_DARK: Lisbon or Setubal has no roadstead in this world: the scene proves nothing';
  end if;
  v_segs := voyage.segments_from_course(jsonb_build_array(jsonb_build_array(v_la.lat, v_la.lon), jsonb_build_array(v_sa.lat, v_sa.lon)));
  v_a := public.new_house(c_a, 'Casa da Carta 206', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;

  -- CF_DARK
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_f;
  v_voy := voyage.depart(v_f, v_segs, v_lis, v_set, now() - interval '20 seconds');
  select v.eta into v_eta from public.voyages v where v.id = v_voy;
  perform voyage.settle(v_f, v_eta + interval '1 second');
  perform public.chart_mark(v_a, v_voy);   -- and called outright: still nothing while dark
  perform cmd.assume_identity(c_a);
  if exists (select 1 from public.company_chart) or world.chart() is distinct from '{"on": false}'::jsonb then
    raise exception 'CF_DARK: dark, a chart row was written or the read is not {"on": false}: %', world.chart() - 'cells';
  end if;
  raise notice 'PASS: CF_DARK — her voyage ended %; no chart row in the world; the read {"on": false}', (select v.status from public.voyages v where v.id = v_voy);

  -- CF_REACH, the dark half: the nearest harbour out of her sight (300 nm and more from Lisbon, her sight is 150) she may sail to, asked dark
  update public.fleets f set status = 'DOCKED', port_id = v_set, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_f;
  for v_far in select p.code from public.ports p
                where p.kind = 'HARBOUR' and voyage.gc_distance_nm(p.lat::float8, p.lon::float8, v_la.lat::float8, v_la.lon::float8) > 300
                order by voyage.gc_distance_nm(p.lat::float8, p.lon::float8, v_la.lat::float8, v_la.lon::float8), p.code limit 20 loop
    v_p0 := cmd.preview(v_f, 'SAIL ' || v_far);
    exit when (v_p0->>'ok')::boolean;
  end loop;

  -- CF_ARRIVAL
  update public.world_config set value = 'true'::jsonb where key = 'chart_fog_enabled';
  v_p1 := cmd.preview(v_f, 'SAIL ' || v_far);   -- CF_REACH, the lit half: her chart is black (no row yet)
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_f;
  v_voy := voyage.depart(v_f, v_segs, v_lis, v_set, now() - interval '20 seconds');
  select v.eta into v_eta from public.voyages v where v.id = v_voy;
  perform voyage.settle(v_f, v_eta + interval '1 second');
  select v.status into v_st from public.voyages v where v.id = v_voy;
  if v_st is distinct from 'ARRIVED' then   -- the dice kept her out: the write is called as the arrival arm calls it
    perform public.chart_mark(v_a, v_voy);
  end if;
  select c.cells into v_c from public.company_chart c where c.player_id = v_a;
  v_s0 := public.chart_sight_nm(v_a);
  select count(*) into v_stray from generate_series(0, 64799) g(k)
   where get_bit(v_c, g.k) = 1
     and least(voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, v_la.lat::float8, v_la.lon::float8),
               voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, v_sa.lat::float8, v_sa.lon::float8),
               voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, ((v_la.lat + v_sa.lat) / 2)::float8, ((v_la.lon + v_sa.lon) / 2)::float8)) > v_s0 + 45;
  v_n := bit_count(v_c);
  v_r := world.chart();
  if v_c is null or (select count(*) from public.company_chart) <> 1 or v_stray <> 0 or v_n < 2
     or get_bit(v_c, floor(90 - v_la.lat)::int * 360 + floor(v_la.lon + 180)::int) <> 1
     or get_bit(v_c, floor(90 - v_sa.lat)::int * 360 + floor(v_sa.lon + 180)::int) <> 1
     or decode(v_r->>'cells', 'base64') <> v_c or (v_r->>'sight_nm')::numeric <> v_s0 or (v_r->>'company')::boolean is not true then
    raise exception 'CF_ARRIVAL: lit, her arrival did not paint her course and only her course: % squares, % out of sight, read %', v_n, v_stray, v_r - 'cells';
  end if;
  update public.company_chart c set updated_at = '2000-01-01'::timestamptz where c.player_id = v_a;
  perform public.chart_mark(v_a, v_voy);
  if (select c.updated_at from public.company_chart c where c.player_id = v_a) <> '2000-01-01'::timestamptz then
    raise exception 'CF_ARRIVAL: a course already charted was written again';
  end if;
  raise notice 'PASS: CF_ARRIVAL — Lisbon to Setubal (%): one row, % squares of 64,800 at % nm, both ends set, 0 out of sight; served in % characters; the same course again: no write',
    v_st, v_n, v_s0, length(v_r->>'cells');

  -- CF_SIGHT
  insert into public.player_skills (player_id, skill_id, level, studied_at)
  select v_a, s.id, 3, now() from public.skills s where s.code = 'NAVIGATION'
  on conflict (player_id, skill_id) do update set level = 3;
  v_s3 := public.chart_sight_nm(v_a);
  perform public.chart_mark(v_a, v_voy);
  select c.cells into v_c2 from public.company_chart c where c.player_id = v_a;
  v_n2 := bit_count(v_c2);
  if v_s0 <> public.wc_num('chart_sight_nm') or v_s3 <> round(public.wc_num('chart_sight_nm') * (3 + public.skill_level(v_a, 'NAVIGATION')) / 3.0)
     or (public.skill_level(v_a, 'NAVIGATION') = 3 and (v_s3 <> 2 * v_s0 or v_n2 <= v_n))
     or exists (select 1 from generate_series(0, 64799) g(k) where get_bit(v_c, g.k) = 1 and get_bit(v_c2, g.k) = 0) then
    raise exception 'CF_SIGHT: her sight is not the knob and a third of it a level, or a wider sight did not widen the grey: % then % nm, % then % squares', v_s0, v_s3, v_n, v_n2;
  end if;
  raise notice 'PASS: CF_SIGHT — level 0: % nm; NAVIGATION %: % nm; the same course painted again: % squares, then %', v_s0, public.skill_level(v_a, 'NAVIGATION'), v_s3, v_n, v_n2;

  -- CF_MERCHANT
  select n.id into v_npc from public.players n where n.is_npc order by n.id limit 1;
  if v_npc is null then
    raise exception 'CF_MERCHANT: this world has no merchant: the scene proves nothing';
  end if;
  perform public.chart_mark(v_npc, v_voy);
  perform set_config('request.jwt.claims', null, true);
  if exists (select 1 from public.company_chart c where c.player_id = v_npc)
     or public.chart_backfill(v_npc, 500)->>'ok' <> 'false' or exists (select 1 from public.company_chart c where c.player_id = v_npc) then
    raise exception 'CF_MERCHANT: a merchant has a chart row';
  end if;
  raise notice 'PASS: CF_MERCHANT — a merchant: the arrival''s write wrote nothing; the backfill answers %', public.chart_backfill(v_npc, 500);

  -- CF_BACKFILL: every company of this world, two at a call, until none is left
  select count(*) into v_co from public.players pl where not pl.is_npc;
  loop
    v_calls := v_calls + 1;
    v_left := (public.chart_backfill_next(2, 500)->>'left')::int;
    exit when v_left = 0 or v_calls > 200;
  end loop;
  select count(*) into v_lost
    from public.logbook l join public.ports p on p.code = l.code join public.players pl on pl.id = l.player_id
    left join public.company_chart c on c.player_id = l.player_id
   where l.kind = 'harbour' and not pl.is_npc
     and (c.cells is null or get_bit(c.cells, least(179, greatest(0, floor(90 - round(p.lat * 2) / 2.0)::int)) * 360 + (((floor(round(p.lon * 2) / 2.0 + 180)::int % 360) + 360) % 360)) <> 1);
  if v_left <> 0 or v_lost <> 0
     or (select count(*) from public.company_chart c where c.backfilled_at is not null) <> v_co
     or exists (select 1 from public.company_chart c join public.players pl on pl.id = c.player_id where pl.is_npc)
     or exists (select 1 from generate_series(0, 64799) g(k) where get_bit(v_c2, g.k) = 1 and get_bit((select c.cells from public.company_chart c where c.player_id = v_a), g.k) = 0) then
    raise exception 'CF_BACKFILL: % left after % calls, % logbook harbours off their company''s chart, or what she had charted was lost', v_left, v_calls, v_lost;
  end if;
  raise notice 'PASS: CF_BACKFILL — % companies in % calls of two, 0 left; % logbook harbours, each on its company''s chart; no merchant row; her own chart only grew',
    v_co, v_calls, (select count(*) from public.logbook l join public.players pl on pl.id = l.player_id where l.kind = 'harbour' and not pl.is_npc);

  -- CF_REACH
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_readers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and (p.prosrc ilike '%company_chart%' or p.prosrc ilike '%chart_mark%' or p.prosrc ilike '%chart_sight_nm%' or p.prosrc ilike '%world.chart%');
  -- (the preview mints a voyage it rolls back: its id is not part of the answer)
  if v_p0->'parsed' is distinct from v_p1->'parsed' or v_p0#>'{estimate,total_nm}' is distinct from v_p1#>'{estimate,total_nm}'
     or (v_p1->>'ok')::boolean is not true or (v_p0->>'ok')::boolean is not true
     or v_readers is distinct from 'chart_backfill(uuid,integer), chart_backfill_next(integer,integer), chart_mark(uuid,uuid), chart_sight_nm(uuid), voyage.settle(uuid,timestamp with time zone), world.chart()' then
    raise exception 'CF_REACH: the fog changed a SAIL''s answer, or something else reads the chart: dark % / lit % / readers %', left(v_p0::text, 300), left(v_p1::text, 300), v_readers;
  end if;
  raise notice 'PASS: CF_REACH — SAIL % (over 300 nm from Lisbon, never seen) with a black chart: accepted, the same order and the same miles dark and lit (ok %); the chart is read by: %',
    v_far, v_p0->>'ok', v_readers;
end
$p$;
