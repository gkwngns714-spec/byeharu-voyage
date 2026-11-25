-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 229 - ROUNDS, BY SEA  (migration 0535)
--
--   Its own company and fleet. Rolled back by proof.mjs.
--
-- @pass RS_SEAS   each sea once, the nearest base first, her own sea at 0 miles
-- @pass RS_QUOTE  a quote before any Send; a stranger's fleet has none; dark says off
-- @pass RS_LOG    the log of a run that is out is, word for word, what the settle books
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a constant uuid := '00000000-0229-4000-8000-0000000000a1';
  v_a uuid; v_f uuid; v_code text; x jsonb; y jsonb; l1 jsonb; l2 jsonb; v_n integer;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 229', 'PRT');
  select f.id, h.code into v_f, v_code from public.fleets f join public.ports h on h.id = f.port_id where f.player_id = v_a;
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 40 where s.fleet_id = v_f;
  perform cmd.assume_identity(c_a);
  update public.world_config set value = 'false'::jsonb where key = 'rounds_enabled';
  if (world.round_quote(v_f, 'expedition', v_code, '{}')->>'on')::boolean then raise exception 'RS_QUOTE: lit while dark'; end if;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'expedition_rounds_enabled');

  x := world.rounds(v_f)->'seas';
  select count(distinct e->>'sea') into v_n from jsonb_array_elements(x) e;
  if v_n <> jsonb_array_length(x) or v_n < 2 or (x #>> '{0,nm}')::numeric <> 0
     or exists (select 1 from jsonb_array_elements(x) with ordinality a(e, o) join jsonb_array_elements(x) with ordinality b(e, o) on b.o = a.o + 1
                 where (a.e->>'nm')::numeric > (b.e->>'nm')::numeric) then
    raise exception 'RS_SEAS: %', x;
  end if;
  -- a normal chain of none: every other sea is far; of a thousand legs: none is; her own never; each with its sailed time
  update public.world_config set value = '0'::jsonb where key = 'round_far_legs';
  if exists (select 1 from jsonb_array_elements(world.rounds(v_f)->'seas') e where (e->>'far')::boolean <> ((e->>'nm')::numeric > 0) or ((e->>'nm')::numeric > 0) <> ((e->>'seconds')::numeric > 0)) then
    raise exception 'RS_SEAS far: %', world.rounds(v_f)->'seas';
  end if;
  update public.world_config set value = '1000'::jsonb where key = 'round_far_legs';
  if exists (select 1 from jsonb_array_elements(world.rounds(v_f)->'seas') e where (e->>'far')::boolean) then raise exception 'RS_SEAS near'; end if;
  raise notice 'PASS: RS_SEAS - % seas from %', v_n, v_code;

  x := world.round_quote(v_f, 'expedition', v_code, '{}');
  y := world.round_quote(gen_random_uuid(), 'expedition', v_code, '{}');
  if (x #>> '{terms,food}')::numeric <= 0 or coalesce(y->'terms', 'null'::jsonb) <> 'null'::jsonb
     or exists (select 1 from public.round_runs r where r.fleet_id = v_f) then
    raise exception 'RS_QUOTE: % / %', x, y;
  end if;
  raise notice 'PASS: RS_QUOTE - a round: food %, crew %; nothing sent', x #>> '{terms,food}', x #>> '{terms,crew}';

  perform public.round_send_for(v_a, v_f, 'expedition', '{"rounds": 4, "days": 0}', now() - interval '35 minutes');
  l1 := world.rounds(null) #> '{runs,0,log}';
  perform public.round_settle(v_f, now());
  l2 := world.rounds(null) #> '{runs,0,log}';
  if jsonb_array_length(l1) <> 2 or l1 <> l2 then raise exception 'RS_LOG: % / %', l1, l2; end if;
  raise notice 'PASS: RS_LOG - two lines before the settle and the same two after';
end $p$;
