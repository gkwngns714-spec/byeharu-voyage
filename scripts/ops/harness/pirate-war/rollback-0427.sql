-- 0427 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- QUICK WAY BACK, no file: pirate_strikes_per_run 0 (no new raid; running ones close within battle_seconds), and the knobs pirate_add_minutes 5,
-- pirate_respawn_minutes 60, pirate_spend_day_pct 0.0024. This draft then removes the rest: the eight hunks reversed (each checked once), the four
-- functions and the partial index dropped, kind RAID taken off battles_kind_check (the closed RAID battles are deleted first: they are 0427's own
-- rows; it refuses while one is still FIGHTING), the four knobs deleted.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_h   record;
  x     record;
  v_def text;
begin
  if exists (select 1 from public.battles b where b.kind = 'RAID' and b.status = 'FIGHTING') then
    raise exception 'rollback-0427 refuses: a raid is still being fought (set pirate_strikes_per_run 0 and wait battle_seconds)';
  end if;
  create temp table hunks_r0427 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_r0427 values
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1,
$h$  if p_kind is null or p_kind not in ('PROBE', 'ATTACK') then   -- 0327: ATTACK comes from public.attack_for alone$h$,
$h$  if p_kind is null or p_kind not in ('PROBE', 'ATTACK', 'RAID') then   -- 0327: ATTACK comes from public.attack_for alone; 0427: RAID from public.pirate_strike alone$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 2,
$h$  if not (select p.is_npc from public.players p where p.id = d.player_id) then
    raise exception 'E_HUMAN_TARGET: no player fights another player' using errcode = 'P0001';
  end if;$h$,
$h$  -- 0427: a RAID is a pirate ship's, on a merchant; a pirate is no player, so she may set upon a player's ship. Every other kind keeps the law: no player fights another player.
  if p_kind = 'RAID' and (not exists (select 1 from public.pirate_ships x where x.fleet_id = p_attacker)
                          or (select p.is_npc from public.players p where p.id = a.player_id) is not true
                          or public.fleet_kind(p_defender) not in ('MERCHANT', 'CARGO_SHIP', 'COMPANY')) then
    raise exception 'E_BAD_TARGET: a raid is a pirate ship''s, on a merchant' using errcode = 'P0001';
  end if;
  if p_kind is distinct from 'RAID' and not (select p.is_npc from public.players p where p.id = d.player_id) then
    raise exception 'E_HUMAN_TARGET: no player fights another player' using errcode = 'P0001';
  end if;$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 3,
$h$  if p_kind = 'ATTACK' then   -- 0333: her country answers; a probe calls nobody$h$,
$h$  if p_kind in ('ATTACK', 'RAID') then   -- 0333: her country answers; a probe calls nobody (0427: a raid is fought as an attack is)$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$h$    update public.battles set result = result || v_spoils where id = p_battle;
  end if;$h$,
$h$    update public.battles set result = result || v_spoils where id = p_battle;
  elsif b.kind = 'RAID' then   -- 0427: a pirate's raid: the navy called is freed first, then her plunder, the hands, a wreck and a player's report (public.raid_close), once, under this row's lock
    v_spoils := public.navy_close(p_battle, p_now);
    v_spoils := v_spoils || public.raid_close(p_battle, v_f || v_spoils, p_now);
    update public.battles set result = result || v_spoils where id = p_battle;
  end if;$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$  return jsonb_build_object('steps', v_steps, 'pressure', v_press, 'added', v_add, 'paid', v_paid);$h$,
$h$  -- 0427: THE PIRATES STRIKE (public.pirate_strikes, which never raises): after the steps, the add and the pay, and never behind a trade's locks, as they are
  return jsonb_build_object('steps', v_steps, 'pressure', v_press, 'added', v_add, 'paid', v_paid)
         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('struck', public.pirate_strikes(p_now)) else '{}'::jsonb end;$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$      'raids_paid', (select loot.n from loot)))$h$,
$h$      'raids_paid', (select loot.n from loot),
      -- 0427: THE BATTLES of the window (public.battles; a closed RAID is kept raid_keep_hours): raids the pirates opened on merchants, how those that closed
      -- in it ended (the pirates won: PLUNDERED or RANSOM; else the merchant held), those the navy came to, and players' attacks
      'raids', (select count(*) from public.battles b where b.kind = 'RAID' and b.started_at > p_since and b.started_at <= p_now),
      'raids_won', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                      and b.result ->> 'outcome' in ('PLUNDERED', 'RANSOM')),
      'raids_held', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                       and coalesce(b.result ->> 'outcome', '') not in ('PLUNDERED', 'RANSOM')),
      'raids_navy', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                       and coalesce((b.result #>> '{navy,came}')::int, 0) > 0),
      'attacks', (select count(*) from public.battles b where b.kind = 'ATTACK' and b.started_at > p_since and b.started_at <= p_now)))$h$),
  ('world.stats_fleets()', 1,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'raids_paid')::int), 0) as raids$h$,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'raids_paid')::int), 0) as raids,
                              coalesce(sum((x.figures -> 'win' ->> 'raids')::int), 0) as b_raids,          -- 0427: the battles
                              coalesce(sum((x.figures -> 'win' ->> 'raids_won')::int), 0) as b_won,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_held')::int), 0) as b_held,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_navy')::int), 0) as b_navy,
                              coalesce(sum((x.figures -> 'win' ->> 'attacks')::int), 0) as b_attacks$h$),
  ('world.stats_fleets()', 2,
$h$           'cargo', f.figures -> 'cargo') end$h$,
$h$           'cargo', f.figures -> 'cargo',
           -- 0427: THE BATTLES of the last 24 hours: raids opened, won by the pirates, held by the merchants, the navy came to; players' attacks; and the navy's fights with pirates
           'battles', jsonb_build_object('raids_day', d.b_raids, 'won_day', d.b_won, 'held_day', d.b_held, 'navy_day', d.b_navy,
                                         'attacks_day', d.b_attacks, 'navy_fights_day', d.fights)) end$h$);


  for v_h in select h.fn from hunks_r0427 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_r0427 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception 'rollback-0427 refuses: hunk % of % is not in the live body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    execute v_def;
  end loop;
  drop function public.pirate_strikes(timestamptz);
  drop function public.pirate_strike(uuid, timestamptz);
  drop function public.raid_target(uuid, timestamptz);
  drop function public.raid_close(uuid, jsonb, timestamptz);
  drop index public.battles_raid_done;
  delete from public.battles b where b.kind = 'RAID';
  alter table public.battles drop constraint battles_kind_check, add constraint battles_kind_check check (kind in ('PROBE', 'ATTACK'));
  delete from public.world_config where key in ('pirate_strike_minutes', 'pirate_strikes_per_run', 'pirate_strike_tries_per_run', 'raid_keep_hours');
  update public.world_config set value = to_jsonb(5) where key = 'pirate_add_minutes' and value = to_jsonb(1);
  update public.world_config set value = to_jsonb(60) where key = 'pirate_respawn_minutes' and value = to_jsonb(5);
  update public.world_config set value = to_jsonb(0.0024) where key = 'pirate_spend_day_pct' and value = to_jsonb(0.006);
  raise notice 'rollback-0427 ok: the eight hunks reversed; no RAID kind, no strike; knobs % / % / %',
    public.wc_int('pirate_add_minutes'), public.wc_int('pirate_respawn_minutes'), public.wc_num('pirate_spend_day_pct');
  drop table hunks_r0427;
end $r$;
