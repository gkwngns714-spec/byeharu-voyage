-- 0507 FORWARD ROLLBACK, A DRAFT (owner only). THE QUICK ROLLBACK NEEDS NO FILE: buy_tax_enabled false. To use this one, strip the guard line, give it
-- the next number, add "-- news: none", and withdraw 0507's proof with the same PR. It reverses 0507's 1 hunks and drops what it made.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  if public.wc('buy_tax_enabled') = 'true'::jsonb then
    raise exception '0507 rollback refuses: buy_tax_enabled is lit; the owner darkens it first';
  end if;
  create temp table back_0507 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0507 values
  (1, 'world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)',
$h$    v_total := v_total * v_unit;
  end if;
  -- 0507 (dark: buy_tax_enabled): lit, A TAX WHEN BUYING (public.buy_tax_rate, asked here alone), on what she pays after her bargain, in
  -- the total and in tax_total. (v_unit is free once the walk is done; it holds the rate.)
  if p_side = 'buy' and p_fleet is not null and public.buy_tax_on() then
    v_unit  := public.buy_tax_rate(p_fleet, p_port);
    v_tax_t := v_tax_t + v_total * v_unit;
    v_total := v_total + v_total * v_unit;
  end if;
  units     := v_units;
$h$,
$h$    v_total := v_total * v_unit;
  end if;
  units     := v_units;
$h$);
  for h in select * from back_0507 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0507 rollback refuses: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop function public.buy_tax_rate(uuid,uuid);
  drop function public.buy_tax_on();
  delete from public.world_config where key in ('buy_tax_enabled', 'buy_tax_share', 'buy_tax_max');
  raise notice '0507 rollback ok: %', (select string_agg(x.fn || ' ' || md5(replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '')), ', ' order by x.fn)
                                       from (select distinct fn from back_0507) x);
end $r$;
