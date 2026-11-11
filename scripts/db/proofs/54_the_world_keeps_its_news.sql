-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 54 — THE WORLD KEEPS ITS NEWS  (migration 0347, owner row 216: "when an update or a happening is made, it should make a point on the chart, and i will be able to press it")
--
--   0347 proves its reads on hand-made rows at fixed instants. This proof walks the REAL paths: a house founded by public.new_house, docked at her home city; two great powers' stance
--   changed in power_relations (the RELATIONS writer, a trigger); a news row of her city posted by the one writer; then the two reads AS THAT CLIENT (role authenticated, her JWT):
--   her cities' feed holds her city's row and not another city's; the world feed and the price chart of her city hold the stance change; the writer and the table are shut to her.
--   One transaction, rolled back by proof.mjs.
--
-- @pass NEWS_RELATIONS_WRITER   a changed stance writes one RELATIONS row (before and after, both powers named) through the trigger; the same stance again writes none
-- @pass NEWS_CITIES_FEED        as the client: her cities' feed holds the row of the city her fleet lies at, never another city's, newest first
-- @pass NEWS_CHART_DOT          as the client: the price chart of her city over the last hour holds the stance change (a world headline) and her city's row; stats_now serves the head
-- @pass NEWS_CLIENT_WALL        as the client: news_post and a SELECT of world_news are refused 42501
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth   constant uuid := '00000000-0f54-4000-8000-000000000216';
  v_player uuid;
  v_port   uuid;
  v_other  uuid;
  v_good   uuid;
  v_rel    record;
  v_mark   bigint;
  v_stance bigint;
  v_mine   bigint;
  v_theirs bigint;
  v_res    jsonb;
  v_ids    bigint[];
begin
  v_player := public.new_house(c_auth, 'Casa das Novas', 'PRT');
  select f.port_id into v_port from public.fleets f where f.player_id = v_player and f.port_id is not null limit 1;
  select p.id into v_other from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port
     and not exists (select 1 from public.city_shares s where s.port_id = p.id and s.player_id = v_player) order by p.code limit 1;
  select g.id into v_good from public.goods g order by g.code limit 1;
  if v_port is null or v_other is null then
    raise exception 'PROOF 54 FAILED: the house has no docked fleet, or there is no other harbour';
  end if;
  v_mark := coalesce((select max(id) from public.world_news), 0);

  -- THE RELATIONS WRITER: a real stance change, through the trigger
  select r.* into v_rel from public.power_relations r order by r.a, r.b limit 1;
  update public.power_relations set stance = case when v_rel.stance = 'ally' then 'war' else 'ally' end where a = v_rel.a and b = v_rel.b;
  update public.power_relations set stance = stance where a = v_rel.a and b = v_rel.b;
  select array_agg(w.id) into v_ids from public.world_news w where w.id > v_mark;
  if cardinality(v_ids) is distinct from 1
     or not exists (select 1 from public.world_news w where w.id = v_ids[1] and w.kind = 'RELATIONS' and w.scope = 'world' and w.importance = 3
                       and w.detail->'words'->'a'->>'key' = (select n.code from public.nations n where n.id = v_rel.a)
                       and w.detail->'words'->'b'->>'key' = (select n.code from public.nations n where n.id = v_rel.b)
                       and w.detail ? 'before' and w.detail ? 'after') then
    raise exception 'PROOF 54 FAILED: a stance change (then the same stance again) did not write exactly one RELATIONS row naming both powers: %', v_ids;
  end if;
  v_stance := v_ids[1];
  raise notice 'PASS: NEWS_RELATIONS_WRITER — row % (%), before %, after %', v_stance,
    (select w.detail->'words'->'stance'->>'en' from public.world_news w where w.id = v_stance),
    (select w.detail->'before'->>'en' from public.world_news w where w.id = v_stance), (select w.detail->'after'->>'en' from public.world_news w where w.id = v_stance);

  -- a news row of her city and one of another city, by the one writer (a kind of the proof's own, as a later writer would add one)
  insert into public.news_kinds (kind, importance, scope, en, ko) values ('PROOF_54', 1, 'port', 'News of {city}', '{city} 소식');
  v_theirs := public.news_post('PROOF_54', v_other, null, null, null, null, jsonb_build_object('words', jsonb_build_object('city', public.news_place(v_other))));
  v_mine := public.news_post('PROOF_54', v_port, v_good, null, null, null, jsonb_build_object('words', jsonb_build_object('city', public.news_place(v_port))));

  -- AS THE CLIENT
  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  v_res := world.news_feed('cities', v_mark, null, 50);
  select array_agg((i->>'id')::bigint order by o) into v_ids from jsonb_array_elements(v_res->'items') with ordinality t(i, o);
  if v_ids is distinct from array[v_mine] then
    reset role;
    raise exception 'PROOF 54 FAILED: her cities'' feed is % not her city''s row % alone (another city''s is %)', v_ids, v_mine, v_theirs;
  end if;
  raise notice 'PASS: NEWS_CITIES_FEED — her feed holds row % (her city), not row % (another)', v_mine, v_theirs;

  v_res := world.news_marks('price', v_port, v_good, now() - interval '1 hour', null);
  select array_agg((i->>'id')::bigint order by o) into v_ids from jsonb_array_elements(v_res->'items') with ordinality t(i, o);
  if not (v_ids @> array[v_stance, v_mine]) or v_theirs = any (v_ids) or (world.stats_now()->>'news_head')::bigint <> v_mine then
    reset role;
    raise exception 'PROOF 54 FAILED: the price chart of her city holds % (wanted % and %, never %), head %', v_ids, v_stance, v_mine, v_theirs, world.stats_now()->>'news_head';
  end if;
  raise notice 'PASS: NEWS_CHART_DOT — the price chart of her city holds the stance change % and her city''s row %; news_head %', v_stance, v_mine, v_mine;

  begin
    perform public.news_post('PROOF_54', v_port, null, null, null, null, '{}'::jsonb);
    reset role;
    raise exception 'PROOF 54 FAILED: the client could post news';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.world_news limit 1;
    reset role;
    raise exception 'PROOF 54 FAILED: the client could read world_news directly';
  exception when insufficient_privilege then null;
  end;
  reset role;
  raise notice 'PASS: NEWS_CLIENT_WALL — news_post and SELECT world_news refused to the client';
end $$;
