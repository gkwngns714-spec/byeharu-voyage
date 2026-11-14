-- 0413 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). FIRST, WITH NO FILE: level_perks_on false. Every benefit then reads 0 for everyone and the page lists none:
-- supplies, repairs, wear, Reputation, regard and the count of routes are what they were before 0413. That is the whole rollback of the rule.
-- This draft also takes the ten hunks out of the eight bodies (each hunk's NEW text must occur once, else it refuses: a later file re-cut that line and the
-- draft is stale). public.level_perks, public.level_perk and the knob are LEFT in place and unread. A company that keeps one or two routes more than the
-- cap keeps them (the cap's trigger judges only a new route). The client needs no change: with no step served it draws none.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_0413 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0413 values
  (1, 'public.stores_cost(uuid,numeric,numeric)',
$h$               * public.running_cost_mult(p_player)
               * (1 - public.level_perk(p_player, 'supplies_price') / 100)   -- 0413: her Supplies level (a merchant: 0)
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: running costs keep pace with the goods
$h$,
$h$               * public.running_cost_mult(p_player)
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: running costs keep pace with the goods
$h$),
  (2, 'public.fleet_repair_cost(uuid,numeric,jsonb)',
$h$               * public.running_cost_mult(f.player_id)
               * (1 - public.level_perk(f.player_id, 'repair_price') / 100)   -- 0413: her Shipbuilding level, on the hull's price (a merchant: 0)
               * public.wc_num('running_cost_level'))::bigint
$h$,
$h$               * public.running_cost_mult(f.player_id)
               * public.wc_num('running_cost_level'))::bigint
$h$),
  (3, 'public.wear_units_for(uuid,uuid)',
$h$  v_n      int;
  v_storm_x numeric := 1;   -- 0413: what her Weather level leaves of a storm day's wear
  v_gear_x  numeric := 1;   -- 0413: what her Craft level leaves of the wear of miles and fights
begin
$h$,
$h$  v_n      int;
begin
$h$),
  (4, 'public.wear_units_for(uuid,uuid)',
$h$    from public.voyage_events ve where ve.voyage_id = p_voyage;
  -- 0413: her company's levels, read once a passage (public.level_perk). This function runs for a player's fleet only.
  select 1 - public.level_perk(f.player_id, 'storm_wear') / 100, 1 - public.level_perk(f.player_id, 'gear_wear') / 100
    into v_storm_x, v_gear_x from public.fleets f where f.id = p_fleet;
$h$,
$h$    from public.voyage_events ve where ve.voyage_id = p_voyage;
$h$),
  (5, 'public.wear_units_for(uuid,uuid)',
$h$                   when 'MILES'   then v_nm / 1000 * public.wc_num('gear_wear_per_1000nm') * v_gear_x
                   when 'PIRATES' then v_fights * public.wc_num('gear_wear_per_fight') * v_gear_x
                   when 'STORM'   then v_storms * public.wc_num('gear_wear_per_storm') * v_storm_x
$h$,
$h$                   when 'MILES'   then v_nm / 1000 * public.wc_num('gear_wear_per_1000nm')
                   when 'PIRATES' then v_fights * public.wc_num('gear_wear_per_fight')
                   when 'STORM'   then v_storms * public.wc_num('gear_wear_per_storm')
$h$),
  (6, 'public.reputation_request(uuid,bigint,uuid,jsonb)',
$h$    -- 0413: and her Requests level's share more (public.level_perk)
    floor(least(greatest(floor(p_premium / v_per), public.wc_int('rep_request_min')), public.wc_int('rep_request_max'))
          * (1 + public.level_perk(p_player, 'request_reputation') / 100))::int,
$h$,
$h$    least(greatest(floor(p_premium / v_per), public.wc_int('rep_request_min')), public.wc_int('rep_request_max'))::int,
$h$),
  (7, 'public.reputation_lap(uuid,uuid,bigint,text,integer)',
$h$  -- 0413: and her Routes level's share more (public.level_perk)
  return public.reputation_credit(p_player, 'lap', floor(public.wc_int('rep_lap') * (1 + public.level_perk(p_player, 'lap_reputation') / 100))::int, 'lap:' || p_lap,
$h$,
$h$  return public.reputation_credit(p_player, 'lap', public.wc_int('rep_lap'), 'lap:' || p_lap,
$h$),
  (8, 'public.standing_route_max_for(uuid)',
$h$  if p_player is null then
    return v_max;
  end if;
  v_max := v_max + public.level_perk(p_player, 'route_room')::int;   -- 0413: and the routes her Routes level gives
  if not public.skills_bite_on() then
    return v_max;
  end if;
$h$,
$h$  if p_player is null or not public.skills_bite_on() then
    return v_max;
  end if;
$h$),
  (9, 'public.invest_for(uuid,uuid,text,integer)',
$h$  -- 0413: her Investment level makes the stake count for more regard (public.level_perk; a merchant: 0, and public.regard_add turns her away)
  perform public.regard_gift(p_player, p_port, round(v_cost * (1 + public.level_perk(p_player, 'share_regard') / 100))::bigint, 'SHARE');   -- 0319: dark, nothing
$h$,
$h$  perform public.regard_gift(p_player, p_port, v_cost, 'SHARE');   -- 0319: dark, nothing
$h$),
  (10, 'public.level_benefits(text,integer)',
$h$       where p_skill in ('trading', 'exploration') and t.level between 2 and public.wc_int('title_max')
      union all
      -- 0413: perk: a step of public.level_perks at this level: its amount, and `total`, what the benefit is worth from this level on
      select k.level, 5, jsonb_build_object('level', k.level, 'kind', 'perk', 'perk', k.perk, 'unit', k.unit, 'word', k.word, 'amount', k.amount,
               'total', (select sum(k2.amount) from public.level_perks k2 where k2.perk = k.perk and k2.level <= k.level))
        from public.level_perks k
       where k.skill = p_skill and public.wc('level_perks_on') = 'true'::jsonb
    ) b
$h$,
$h$       where p_skill in ('trading', 'exploration') and t.level between 2 and public.wc_int('title_max')
    ) b
$h$);
  for h in select * from back_0413 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0413 rollback: hunk % of % occurs % time(s), not once: a later file re-cut it and this draft is stale', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world') and p.proname <> 'level_perk' and p.prosrc like '%level\_perk(%') then
    raise exception '0413 rollback: a body still reads the level benefits';
  end if;
  raise notice '0413 rollback ok: ten hunks out of eight bodies, level_perks_on false; the steps, the reader and the knob are left in place.';
end $r$;
