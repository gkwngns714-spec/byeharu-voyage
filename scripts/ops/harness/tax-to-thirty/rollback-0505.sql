-- 0505 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add
-- "-- news: none" and deploy it as any migration (owner only). THE QUICK ROLLBACK NEEDS NO FILE: tax_thirty_enabled false (owner): the dial stops at tax_rate_max again and home gives
--   nothing. A mayor's rate already above tax_rate_max stays in her row and is served (world.tax_rate never capped a mayor's rate): read
--   mayors.over_max first; the owner decides whether those rows are lowered by a forward migration.
-- This draft is the full reversal: it reverses 0505's 5 hunks and then:
--   drop function public.tax_home_half(uuid, uuid, numeric, numeric);
--   drop function public.tax_cap();
--   drop function public.tax_thirty_on();
--   delete from public.world_config where key in ('tax_thirty_enabled', 'tax_rate_cap', 'home_tax_cut');
-- Each hunk's NEW text must occur once in the live body (else it refuses: a later file re-cut the same lines and this draft is stale).
-- The proof of 0505 must be withdrawn with the same PR.
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
  if public.wc('tax_thirty_enabled') = 'true'::jsonb then
    raise exception '0505 rollback refuses: tax_thirty_enabled is lit; the owner darkens it first';
  end if;
  create temp table back_0505 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0505 values
  (1, 'world.tax_rate(uuid,uuid)',
$h$  if not public.influence_on() then
    return public.tax_home_half(p_port, p_player, v_base, v_base);   -- 0505 (dark: tax_thirty_enabled): lit, her home city asks half
  end if;
$h$,
$h$  if not public.influence_on() then
    return v_base;
  end if;
$h$),
  (2, 'world.tax_rate(uuid,uuid)',
$h$    return public.tax_home_half(p_port, p_player,   -- 0505 (dark: tax_thirty_enabled): lit, at her home the lower of this and half the city's rate
             least(v_base * public.country_factor(v_stance) * public.regard_factor(p_player, p_port), greatest(v_base, public.wc_num('tariff_rate_max'))), v_base);
$h$,
$h$    return least(v_base * public.country_factor(v_stance) * public.regard_factor(p_player, p_port), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$),
  (3, 'world.tax_rate(uuid,uuid)',
$h$    return public.tax_home_half(p_port, p_player, v_base * (1 - public.wc_num('influence_citizen_tax_cut')), v_base);   -- 0505: never both cuts
$h$,
$h$    return v_base * (1 - public.wc_num('influence_citizen_tax_cut'));
$h$),
  (4, 'world.tax_rate(uuid,uuid)',
$h$  return public.tax_home_half(p_port, p_player,   -- 0505 (dark: tax_thirty_enabled)
           least(v_base * public.stance_mult(v_stance), greatest(v_base, public.wc_num('tariff_rate_max'))), v_base);
$h$,
$h$  return least(v_base * public.stance_mult(v_stance), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$),
  (5, 'cmd.set_tax(uuid,numeric)',
$h$    -- 0505 (dark: tax_thirty_enabled): the upper bound is public.tax_cap(): the old 20 % cap as before, 30 % when lit
    if p_rate is null or p_rate < 0 or p_rate > public.tax_cap() then
      perform cmd.refuse('E_TAX_BAND', format('the tax is between 0%% and %s%% of the profit',
                                              round(public.tax_cap() * 100)));
$h$,
$h$    if p_rate is null or p_rate < 0 or p_rate > public.wc_num('tax_rate_max') then
      perform cmd.refuse('E_TAX_BAND', format('the tax is between 0%% and %s%% of the profit',
                                              round(public.wc_num('tax_rate_max') * 100)));
$h$);
  for h in select * from back_0505 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0505 rollback refuses: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop function public.tax_home_half(uuid, uuid, numeric, numeric);
  drop function public.tax_cap();
  drop function public.tax_thirty_on();
  delete from public.world_config where key in ('tax_thirty_enabled', 'tax_rate_cap', 'home_tax_cut');
  raise notice '0505 rollback ok: %', (select string_agg(x.fn || ' ' || md5(replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '')), ', ' order by x.fn)
                                       from (select distinct fn from back_0505) x);
end $r$;
