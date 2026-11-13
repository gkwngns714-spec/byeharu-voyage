do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- 0374 FORWARD ROLLBACK, A DRAFT (it WRITES: local PGlite only while it carries the line above). To deploy it: copy it into supabase/migrations/ under the next number, delete
-- its first line (the guard), and add its `-- news: none` line or its news row. Owner only.
-- THE QUICK ROLLBACK IS A KNOB, not this file: update public.world_config set value = '0'::jsonb where key = 'loot_risk_full' turns the rule off at once (the loot of 0327).
-- This file takes 0374 out whole: the one line of public.loot_take and the one line of public.battle_sheet_freeze back to their pre-images, public.loot_risk and public.attack_ready dropped, the two knobs deleted.
-- Do not run it while 0375 (which calls public.attack_ready in its guard) is still to be deployed. Loot already taken stays taken.
-- Tested locally: BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/run.mjs scripts/ops/harness/attacks/rollback-0374.sql  (after it public.loot_take is the body of
-- head 0367 to the byte, and proof 34 as it stood before 0374 would be green again).
do $m$
declare
  v_def0 text;
  c_fn   constant text := 'public.loot_take(uuid,uuid,text,timestamp with time zone)';
  c_old  constant text := $o$  v_take := public.loot_due(p_outcome, v_left, public.loot_today(p_player, p_now));
$o$;
  c_new  constant text := $n$  -- 0374: LOOT FOLLOWS THE RISK TAKEN (public.loot_risk): what is aboard counts for the share of her own hull the attacker lost in this fight, whole at loot_risk_full.
  -- Read from the kept result of the battle this ship was set upon in (public.battle_resolve writes it before the close). The caps are public.loot_due's, as they were.
  v_take := public.loot_due(p_outcome,
                            floor(v_left * public.loot_risk((select b.result from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                                                               where bs.fleet_id = p_fleet and bs.side = 'DEFENDER' and bs.how = 'OPENED' and b.kind = 'ATTACK'
                                                               order by b.started_at desc, b.id desc limit 1)))::bigint,
                            public.loot_today(p_player, p_now));
$n$;
  c_frz_old constant text := $o$            where bs.battle_id = p_battle and bs.arrives_at <= p_now
$o$;
  c_frz_new constant text := $n$            where bs.battle_id = p_battle and bs.arrives_at <= p_now
              and bs.how <> 'CALLED'   -- 0374: a called ship joins through public.battle_advance alone (round 1 if she is there already), once and marked: frozen here too she fought as two
$n$;
begin
  perform set_config('lock_timeout', '5s', true);
  -- the called ship's line of public.battle_sheet_freeze, back (this brings 0357's fault back with it: a called ship already there is on the sheet twice)
  v_def0 := replace(pg_get_functiondef('public.battle_sheet_freeze(uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  if (length(v_def0) - length(replace(v_def0, c_frz_new, ''))) / length(c_frz_new) is distinct from 1 then
    raise exception 'rollback of 0374 refuses: the line 0374 wrote is not in public.battle_sheet_freeze exactly once';
  end if;
  execute replace(v_def0, c_frz_new, c_frz_old);
  v_def0 := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def0) - length(replace(v_def0, c_new, ''))) / length(c_new) is distinct from 1 then
    raise exception 'rollback of 0374 refuses: the line 0374 wrote is not in public.loot_take exactly once';
  end if;
  execute replace(v_def0, c_new, c_old);
  drop function public.loot_risk(jsonb);
  drop function public.attack_ready();
  delete from public.world_config where key in ('loot_risk_full', 'loot_risk_floor');
  if position('loot_risk' in pg_get_functiondef(c_fn::regprocedure)) > 0 or to_regprocedure('public.loot_risk(jsonb)') is not null
     or exists (select 1 from public.world_config c where c.key like 'loot_risk%') then
    raise exception 'rollback of 0374 FAIL: something of 0374 is left';
  end if;
  raise notice 'rollback of 0374 ok: public.loot_take is its pre-image (md5 %), public.loot_risk and public.attack_ready are gone, the two knobs deleted',
    md5(replace(pg_get_functiondef(c_fn::regprocedure), E'\r', ''));
end $m$;
