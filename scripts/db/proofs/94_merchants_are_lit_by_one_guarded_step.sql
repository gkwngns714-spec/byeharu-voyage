-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 94 - MERCHANTS ARE LIT BY ONE GUARDED STEP  (migration 0394; owner rows 166 and 324)
--
--   0394 lights nothing: it installs public.sea_conditions_npc_ready (the guards, as figures) and public.sea_conditions_npc_light (the step). This proof
--   breaks each guard, lights a ready world, reads the planner and the news, and throws the switch back. All rolled back with proof.mjs's transaction.
--
-- @pass NL_AS_SHIPPED  the chain's world is not ready (the players' seas are dark): the read says so, the step refuses naming that guard, the merchants' switch stays dark and no news row is written
-- @pass NL_NO_LEG      the players' seas lit and every sea made to ask a wave no hull holds: the read counts merchants left with no known leg, and the step refuses naming them
-- @pass NL_LIT         a ready world: the step lights sea_conditions_bite_npc, posts exactly one news row (update:0394, English and Korean) and answers its figures; asked again it refuses (already lit) and posts nothing
-- @pass NL_PLANNER     lit by the step: a merchant with a known leg her hull cannot hold is no longer offered it, and is offered others
-- @pass NL_BACK        the switch thrown back: she is offered it again
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_r    jsonb;
  v_g    jsonb;
  v_err  text;
  v_news bigint;
  v_m    record;
  v_dark jsonb;
  v_lit  jsonb;
begin
  if to_regprocedure('public.sea_conditions_npc_light()') is null then
    raise exception 'PROOF 94 FAIL: 0394 is not in this world';
  end if;
  select count(*) into v_news from public.world_news;

  -- ── NL_AS_SHIPPED ──
  v_r := public.sea_conditions_npc_ready();
  if (v_r ->> 'lit')::boolean or (v_r ->> 'ready')::boolean or (v_r ->> 'players_lit')::boolean or (v_r ->> 'merchant_loops')::int < 1 then
    raise exception 'PROOF 94 FAIL: the chain''s world reads ready, lit, or with no merchant: %', v_r;
  end if;
  begin
    perform public.sea_conditions_npc_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like 'sea_conditions_npc_light refuses: %' or v_err not like '%sea_conditions_bite is off%'
     or public.sea_conditions_npc_on() or (select count(*) from public.world_news) <> v_news then
    raise exception 'PROOF 94 FAIL: as shipped the step did not refuse naming the players'' switch, or changed something: %', v_err;
  end if;
  raise notice 'PASS: NL_AS_SHIPPED - not ready (the players'' seas are dark; % of % merchant loops have a leg the sea would close): refused, the switch dark, no news',
    v_r ->> 'loops_closed', v_r ->> 'merchant_loops';

  -- ── NL_NO_LEG ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  create temp table z72 on commit drop as select code, wave_min from public.sea_zones;
  update public.sea_zones set wave_min = 99;
  v_r := public.sea_conditions_npc_ready();
  begin
    perform public.sea_conditions_npc_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if (v_r ->> 'merchants_with_no_open_leg')::int < 1 or (v_r ->> 'ready')::boolean
     or v_err is null or v_err not like '%merchant(s) would be left with no known leg their hull can hold%' or v_err like '%sea_conditions_bite is off%'
     or public.sea_conditions_npc_on() then
    raise exception 'PROOF 94 FAIL: with every sea asking wave 99 the step did not refuse naming the merchants left with no leg: % / %', v_r, v_err;
  end if;
  update public.sea_zones z set wave_min = b.wave_min from z72 b where b.code = z.code;
  raise notice 'PASS: NL_NO_LEG - every sea asking a wave no hull holds: % merchants would have no leg; refused, naming them', v_r ->> 'merchants_with_no_open_leg';

  -- ── a merchant with a leg her hull cannot hold and one it can (read dark) ──
  select q.* into v_m
    from (select nf.fleet_id, nf.route_id, public.fleet_wave(nf.fleet_id) as wave, greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
                 (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as home, nf.roster_ord
            from public.npc_fleets nf where nf.route_id is not null) q
   where exists (select 1 from jsonb_array_elements(public.npc_feasible_legs(q.home, q.fleet_id, q.speed, 400)) x
                  where public.npc_sea_shut(q.wave, (x ->> 'port_id')::uuid, x -> 'course') is not null)
     and exists (select 1 from jsonb_array_elements(public.npc_feasible_legs(q.home, q.fleet_id, q.speed, 400)) x
                  where public.npc_sea_shut(q.wave, (x ->> 'port_id')::uuid, x -> 'course') is null)
   order by q.roster_ord limit 1;
  if v_m.fleet_id is null then
    raise exception 'PROOF 94 FAIL: no merchant has both a known leg her hull cannot hold and one it can';
  end if;
  v_dark := public.npc_feasible_legs(v_m.home, v_m.fleet_id, v_m.speed, 400);

  -- ── NL_LIT ──
  v_r := public.sea_conditions_npc_ready();
  if not (v_r ->> 'ready')::boolean then
    raise exception 'PROOF 94 FAIL: the players'' seas lit and the zones restored, and the world is still not ready: %', v_r;
  end if;
  v_g := public.sea_conditions_npc_light();
  if not public.sea_conditions_npc_on() or not (v_g ->> 'lit')::boolean
     or (select count(*) from public.world_news) <> v_news + 1
     or not exists (select 1 from public.world_news n where n.key = 'update:0394' and n.kind = 'UPDATE'
                      and n.detail -> 'words' -> 'title' ->> 'en' = 'Merchants keep to seas their ships hold'
                      and n.detail -> 'words' -> 'title' ->> 'ko' = '상선도 내파에 맞는 바다만 항해') then
    raise exception 'PROOF 94 FAIL: the step did not light a ready world with one news row in both languages: %', v_g;
  end if;
  begin
    perform public.sea_conditions_npc_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is distinct from 'sea_conditions_npc_light refuses: the sea conditions are already lit for merchants' or (select count(*) from public.world_news) <> v_news + 1 then
    raise exception 'PROOF 94 FAIL: asked again the step did not refuse as already lit, or posted again: %', v_err;
  end if;
  raise notice 'PASS: NL_LIT - a ready world is lit by the step, with one news row (EN and KO); asked again it refuses and posts nothing';

  -- ── NL_PLANNER ──
  v_lit := public.npc_feasible_legs(v_m.home, v_m.fleet_id, v_m.speed, 400);
  if jsonb_array_length(v_lit) < 1 or jsonb_array_length(v_lit) >= jsonb_array_length(v_dark)
     or exists (select 1 from jsonb_array_elements(v_lit) x where public.npc_sea_shut(v_m.wave, (x ->> 'port_id')::uuid, x -> 'course') is not null) then
    raise exception 'PROOF 94 FAIL: lit by the step, the merchant is still offered a leg her hull cannot hold (% lit, % dark)', jsonb_array_length(v_lit), jsonb_array_length(v_dark);
  end if;
  raise notice 'PASS: NL_PLANNER - lit by the step, a merchant (wave %) is offered % of her % known legs, none through a sea her hull cannot hold', v_m.wave, jsonb_array_length(v_lit), jsonb_array_length(v_dark);

  -- ── NL_BACK ──
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  if public.npc_feasible_legs(v_m.home, v_m.fleet_id, v_m.speed, 400) is distinct from v_dark or public.sea_conditions_npc_on() then
    raise exception 'PROOF 94 FAIL: the switch thrown back, her legs are not what they were';
  end if;
  raise notice 'PASS: NL_BACK - the switch thrown back: she is offered every leg again';
end $$;
