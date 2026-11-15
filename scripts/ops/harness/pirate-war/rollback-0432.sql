-- 0432 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- QUICK WAY BACK, no file: raid_flee_ratio 0 (no ship of the world runs by the rule), peace_after_flee_minutes 0 (no peace). This draft reverses the
-- ten hunks (each checked once), drops the two functions and deletes the six knobs. A raid running when it lands keeps the a_flee on its sheet: harmless,
-- 0357's fight_sides ignores an option it does not know.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_h   record;
  x     record;
  v_def text;
begin
  create temp table hunks_r0432 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_r0432 values
  ('public.raid_target(uuid,timestamp with time zone)', 1,
$h$     order by c.nm, c.id$h$,
$h$     order by public.fleet_kind(c.id) = 'COMPANY', c.nm, c.id   -- 0432: the world's merchants first ("pirates' main goal is to attack other npcs"), then a player's$h$),
  ('public.raid_target(uuid,timestamp with time zone)', 2,
$h$    continue when exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                           where bs.fleet_id = r.id and bs.side = 'DEFENDER' and b.started_at > p_now - make_interval(mins => v_rest));$h$,
$h$    continue when public.fleet_peace_until(r.id) > p_now;   -- 0432: five minutes of peace after a battle she was set upon in (was 0427's attack_ship_minutes rest)$h$),
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 1,
$h$                   'word', public.attack_word(voyage.escort_score(v_att), voyage.escort_score(v_def))),$h$,
$h$                   'word', public.attack_word(voyage.escort_score(v_att), voyage.escort_score(v_def)))
                 -- 0432: a raid's flee bonus for the side set upon (public.flee_bonus), frozen with her hulls
                 || case when b.kind = 'RAID' then jsonb_build_object('a_flee', public.flee_bonus(v_def, v_att)) else '{}'::jsonb end,$h$),
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 2,
$h$  v_st := public.battle_opening_stance(v_def);$h$,
$h$  -- 0432: a ship of the world set upon by a pirate runs when she is outgunned (her side's score under the raider's x raid_flee_ratio)
  v_st := case when b.kind = 'RAID' and public.fleet_kind(v_def) in ('MERCHANT', 'CARGO_SHIP')
                    and voyage.escort_score(v_def) < voyage.escort_score(v_att) * coalesce(public.wc_num('raid_flee_ratio'), 0) then 'FLEE'
               else public.battle_opening_stance(v_def) end;$h$),
  ('public.battle_fight(uuid,integer)', 1,
$h$  return public.fight_sides(p_battle, 1, b.sheet->'a', b.sheet->'b', v_opts);$h$,
$h$  if b.sheet ? 'a_flee' then
    v_opts := v_opts || jsonb_build_object('a_flee', b.sheet->'a_flee');   -- 0432: a raid's flee bonus, frozen on the sheet
  end if;
  return public.fight_sides(p_battle, 1, b.sheet->'a', b.sheet->'b', v_opts);$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 1,
$h$      v_pf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')));$h$,
$h$      -- 0432: a raid's flee bonus (p_opts.a_flee: her speed and her company's handling, public.flee_bonus) within raid_flee_floor..raid_flee_max; without one, 0357's chance
      v_pf := case when p_opts ? 'a_flee'
                   then least(public.wc_num('raid_flee_max'), greatest(public.wc_num('raid_flee_floor'),
                          public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting') + (p_opts ->> 'a_flee')::numeric))
                   else least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                          public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting'))) end;$h$),
  ('world.fleets()', 1,
$h$    || case when f.busy_until is not null then public.battle_navy_served(f.id) else '{}'::jsonb end   -- 0333: "Navy arrives 5:10" on the card of a fleet in a battle; absent otherwise$h$,
$h$    || case when f.busy_until is not null then public.battle_navy_served(f.id) else '{}'::jsonb end   -- 0333: "Navy arrives 5:10" on the card of a fleet in a battle; absent otherwise
    || coalesce((select jsonb_build_object('peace_until', x.u) from (select public.fleet_peace_until(f.id) as u) x where x.u > now()), '{}'::jsonb)   -- 0432: "Peace 4:12"; absent otherwise$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$      'attacks', (select count(*) from public.battles b where b.kind = 'ATTACK' and b.started_at > p_since and b.started_at <= p_now)))$h$,
$h$      'attacks', (select count(*) from public.battles b where b.kind = 'ATTACK' and b.started_at > p_since and b.started_at <= p_now),
      -- 0432: the raids that closed in the window with the side set upon gone (she ran and slipped away)
      'raids_fled', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                       and coalesce((b.result ->> 'fled')::boolean, false))))$h$),
  ('world.stats_fleets()', 1,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'attacks')::int), 0) as b_attacks$h$,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'attacks')::int), 0) as b_attacks,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_fled')::int), 0) as b_fled   -- 0432$h$),
  ('world.stats_fleets()', 2,
$h$                                         'attacks_day', d.b_attacks, 'navy_fights_day', d.fights)) end$h$,
$h$                                         'attacks_day', d.b_attacks, 'navy_fights_day', d.fights, 'fled_day', d.b_fled)) end   -- 0432: fled_day$h$);


  for v_h in select h.fn from hunks_r0432 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), chr(13), '');
    for x in select * from hunks_r0432 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception 'rollback-0432 refuses: hunk % of % is not in the live body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    execute v_def;
  end loop;
  drop function public.fleet_peace_until(uuid);
  drop function public.flee_bonus(uuid, uuid);
  delete from public.world_config where key in ('peace_after_flee_minutes', 'raid_flee_ratio', 'raid_flee_floor', 'raid_flee_max', 'raid_flee_per_speed', 'raid_flee_per_handling');
  raise notice 'rollback-0432 ok: the ten hunks reversed, the two functions dropped, the six knobs deleted';
  drop table hunks_r0432;
end $r$;
