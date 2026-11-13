do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- rollback-0390.sql — THE FORWARD ROLLBACK OF 0390 (gear wear bites), A DRAFT. LOCAL PGlite WORLD ONLY while it carries the guard line above (scripts/ops/harness/README.md).
-- To deploy it: copy it into supabase/migrations/ under the next number, delete its FIRST line (the guard), and put the new number in the news call and the messages.
-- The quick way is the owner's one line, the same row: update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite' returning key, value;
-- WHAT IT DOES: puts the switch out. At once no fitting is served a wear card, the yard's bill names no fitting, every figure counts every piece whole (proof 72, WEAR_DARK_AGAIN;
-- 0390's own probe plays it). The wear stays on the units and goes on accruing, unseen, as it did from 0158 to 0390. NOT UNDONE: gold a company paid a city for fittings while lit.
do $m$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select c.value from public.world_config c where c.key = 'gear_wear_bite') is distinct from 'true'::jsonb then
    raise exception 'rollback of 0390 refuses: gear_wear_bite is % and this file puts it out from true', (select c.value from public.world_config c where c.key = 'gear_wear_bite');
  end if;
  update public.world_config c set value = 'false'::jsonb, updated_at = now() where c.key = 'gear_wear_bite' and c.value = 'true'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.gear_wear_on() then
    raise exception 'rollback of 0390 self-assert FAIL: % row(s) written, the switch reads %', v_n, public.gear_wear_on();
  end if;
  perform public.news_update('0390-rollback', 'Fittings wear: paused', '장비 마모: 일시 중지');
  raise notice 'rollback of 0390 self-assert ok: gear_wear_bite is out; the wear stays on the units, unseen';
end
$m$;
