-- 0495 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add
-- "-- news: none" and deploy it as any migration (owner only). THE QUICK ROLLBACK NEEDS NO FILE: dividend_hourly_enabled false (owner);
-- the next tick pays the daily way again, into `accrued`. This draft is the full reversal: it reverses 0495's two hunks
-- (public.tick_city, public.city_coupons), drops public.city_coupon_hour, public.real_hour and public.dividend_hourly_on, drops
-- port_treasury.profit_hours, coupon_hour and coupon_owed (hours still owed to a skipped holder are dropped with it), and deletes the knob. What was paid stays paid (the ledger is never rewritten).
-- Each hunk's NEW text must occur once in the live body (else it refuses: a later file re-cut the same lines and this draft is stale).
-- Proof 198 must be withdrawn with the same PR.
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
  if public.dividend_hourly_on() then
    raise exception '0495 rollback refuses: dividend_hourly_enabled is lit; the owner darkens it first';
  end if;
  create temp table back_0495 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0495 values
  (1, 'public.tick_city(timestamp with time zone)',
$h$      for hp in select t.port_id from public.port_treasury t
                 where t.coupon_day < v_rday
                    -- 0495 (dark: dividend_hourly_enabled): lit, every harbour once per real hour (public.city_coupon_hour pays, through public.city_coupons)
                    or ((select public.dividend_hourly_on()) and t.coupon_hour < public.real_hour(p_now))
                 order by t.port_id loop
$h$,
$h$      for hp in select t.port_id from public.port_treasury t where t.coupon_day < v_rday order by t.port_id loop
$h$),
  (2, 'public.city_coupons(uuid,timestamp with time zone)',
$h$begin
  -- 0495 (dark: dividend_hourly_enabled): lit, the coupon is paid every real hour, straight to each holder's purse, by public.city_coupon_hour;
  -- the daily form below then never runs. Dark, the lines below are all that runs, as before.
  if public.dividend_hourly_on() then
    return public.city_coupon_hour(p_port, p_now);
  end if;
  perform public.treasury_lock(p_port);   -- before the purse is judged
$h$,
$h$begin
  perform public.treasury_lock(p_port);   -- before the purse is judged
$h$);
  for h in select * from back_0495 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0495 rollback refuses: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop function public.city_coupon_hour(uuid, timestamptz);
  drop function public.real_hour(timestamptz);
  drop function public.dividend_hourly_on();
  alter table public.port_treasury drop column profit_hours, drop column coupon_hour, drop column coupon_owed;
  delete from public.world_config where key = 'dividend_hourly_enabled';
  raise notice '0495 rollback ok: public.tick_city % and public.city_coupons % are their bodies of before 0495; three functions, three columns and the knob are gone',
    md5(replace(pg_get_functiondef('public.tick_city(timestamp with time zone)'::regprocedure), E'\r', '')),
    md5(replace(pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure), E'\r', ''));
end $r$;
