-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 228 - ARTIFACTS  (migration 0524; docs/design/rounds-2026-11-25.md section 8)
--
--   Its own company, run and capital. The shares are counted over its own 20,000 rolls, with wide bounds. Rolled back by proof.mjs.
--
-- @pass AR_RARE    the tiers come in their shares; from level 15 about twice as often
-- @pass AR_KEPT    found by an expedition's own rounds through the settle, kept with the fleet, served by the read
-- @pass AR_GIVEN   at the capital alone: gold from its purse (the sum moves 0) and Reputation; given once
-- @pass AR_BROKE   a realm that cannot pay: refused, she keeps them, no Reputation
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a constant uuid := '00000000-0228-4000-8000-0000000000a1';
  v_a uuid; v_f uuid; v_lis uuid; v_cap uuid; x jsonb; y jsonb; r jsonb; s0 numeric; s1 numeric; t timestamptz; m numeric;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 228', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'city_treasury_enabled', 'reputation_on', 'expedition_rounds_enabled', 'artifacts_enabled', 'economy_closed');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  perform cmd.assume_identity(c_a);
  insert into public.round_runs (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, terms)
  values (v_f, v_a, 'expedition', (select h.sea_id from public.ports h where h.id = v_lis), 'home', now(), now(), '{"kind": "sea", "level": 1}');
  x := public.round_artifacts(v_f, 1, 20000);
  update public.round_runs set terms = '{"kind": "sea", "level": 15}' where fleet_id = v_f;
  y := public.round_artifacts(v_f, 1, 20000);
  if (x->>'uncommon')::int not between 650 and 950 or (x->>'rare')::int not between 220 and 380 or (x->>'very_rare')::int not between 55 and 150
     or (y->>'uncommon')::int not between 1400 and 1800 or (y->>'very_rare')::int not between 130 and 280 then
    raise exception 'AR_RARE: % %', x, y;
  end if;
  raise notice 'PASS: AR_RARE - of 20,000 rounds: %; at level 15: %', x, y;
  delete from public.fleet_artifacts where fleet_id = v_f;
  delete from public.round_runs where fleet_id = v_f;

  update public.world_config set value = '[{"tier": "uncommon", "pct": 100, "gold": 400, "rp": 15}]'::jsonb where key = 'artifact_tiers';
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 40 where s.fleet_id = v_f;
  perform cmd.round_send(v_f, 'expedition', '{"rounds": 3, "days": 0}');
  t := clock_timestamp();
  perform cmd.advance(v_f, now() + interval '2 hours');
  m := round(extract(epoch from clock_timestamp() - t) * 1000, 1);
  r := world.rounds(null) #> '{artifacts,kept}';
  if r #>> '{0,tier}' is distinct from 'uncommon' or (r #>> '{0,qty}')::int <> 3 then
    raise exception 'AR_KEPT: %', r;
  end if;
  raise notice 'PASS: AR_KEPT - %; the settle of an expedition with its gold, Reputation and artifacts: % ms', r, m;

  v_cap := (select h.id from public.ports h join public.nations q on q.capital_port_code = h.code join public.players p on p.nation_id = q.id where p.id = v_a and h.kind = 'HARBOUR');
  update public.fleets set port_id = v_cap where id = v_f;
  update public.port_treasury z set ducats = 0 where public.port_nation(z.port_id) = (select p.nation_id from public.players p where p.id = v_a) or z.port_id = v_cap;
  r := cmd.artifact_report(v_f);
  if r->>'error_code' is distinct from 'E_CITY_BROKE' or (select sum(a.qty) from public.fleet_artifacts a where a.fleet_id = v_f) <> 3
     or exists (select 1 from public.reputation_book b where b.player_id = v_a and b.kind = 'artifact') then
    raise exception 'AR_BROKE: %', r;
  end if;
  raise notice 'PASS: AR_BROKE - %', r->>'error_message';
  update public.port_treasury z set ducats = 100000000 where z.port_id = v_cap;
  s0 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
  r := cmd.artifact_report(v_f);
  s1 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
  if not (r->>'ok')::boolean or (r->>'gold')::int <> 1200 or (r->>'rp')::int <> 45 or s1 <> s0 or cmd.artifact_report(v_f)->>'error_code' <> 'E_NO_CARGO' then
    raise exception 'AR_GIVEN: % %', r, s1 - s0;
  end if;
  raise notice 'PASS: AR_GIVEN - three uncommon: % gold, % Reputation, the sum moved 0', r->>'gold', r->>'rp';
end $p$;
