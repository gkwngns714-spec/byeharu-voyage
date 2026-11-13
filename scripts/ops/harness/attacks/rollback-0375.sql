do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- 0375 FORWARD ROLLBACK, A DRAFT (it WRITES: local PGlite only while it carries the line above). To deploy it: copy it into supabase/migrations/ under the next number and delete
-- its first line (the guard). Owner only. It is the migration form of the owner's one line:
--   update public.world_config set value = 'false'::jsonb where key = 'attack_enabled'
-- WHAT IT DOES: attack_enabled false. From that instant cmd.attack, cmd.preview_attack and cmd.battle_stance refuse (E_NOT_IN_USE), the Attack section draws nothing and no new
-- battle can open. WHAT IT LEAVES, on purpose: a battle already being fought finishes at its clock by the minute job, under the stance each side last held, and still pays
-- (0327, 4.6; proof 75 LIT_SWITCH_OFF); loot already taken stays taken; regard lost and WANTED marks stand and fade by their own clocks. 0374's loot rule is not touched.
-- It posts its own news row, so players are told the door is shut (0347's law).
-- Tested locally by scripts/ops/harness/attacks/proof-0375.mjs's world: BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/run.mjs scripts/ops/harness/attacks/rollback-0375.sql
do $m$
declare
  v_n int;
begin
  perform set_config('lock_timeout', '5s', true);
  if not public.attack_on() then
    raise exception 'rollback of 0375 refuses: attack_enabled is not on';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.attack_on() then
    raise exception 'rollback of 0375 FAIL: the switch did not go off (% row(s))', v_n;
  end if;
  perform public.news_update('0375-off', 'Attacks closed for now', '공격 일시 중단');
  raise notice 'rollback of 0375 ok: attack_enabled is off; % battle(s) still being fought will finish at their clocks',
    (select count(*) from public.battles b where b.status = 'FIGHTING');
end $m$;
