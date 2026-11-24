-- 0495 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add
-- "-- news: none" and deploy it as any migration (owner only). THE QUICK ROLLBACK NEEDS NO FILE: dividend_hourly_enabled false (owner);
-- nothing more is paid out hourly, and what is left waits in `accrued` for an arrival, as before. This draft is the full reversal: it
-- reverses 0495's two hunks (public.tick_city, public.city_coupons), drops public.city_coupon_hour, public.real_hour and
-- public.dividend_hourly_on, drops city_shares.drip_left, drip_hour and drip_at (marks only: the coin itself is in `accrued` and stays),
-- and deletes the knob. What was paid stays paid (the ledger is never rewritten).
-- Each hunk's NEW text must occur once in the live body (else it refuses: a later file re-cut the same lines and this draft is stale).
-- Proof 198 and the workflow step of scripts/ci/dividend-race.sh must be withdrawn with the same PR.
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
$h$        v_skipped := v_skipped + (v_due - v_pay);
      end loop;
      -- 0495 (dark: dividend_hourly_enabled): lit, every hour, each PLAYER's part of the last day's coupon is paid out to her purse, 1/24 an
      -- hour, from what the city set aside for her (public.city_coupon_hour). No city's purse moves; merchants are not paid here.
      if public.dividend_hourly_on() then
        perform public.city_coupon_hour(p_now);
      end if;
$h$,
$h$        v_skipped := v_skipped + (v_due - v_pay);
      end loop;
$h$),
  (2, 'public.city_coupons(uuid,timestamp with time zone)',
$h$    update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today,
           -- 0495 (dark: dividend_hourly_enabled): lit, a PLAYER's part of this coupon (and what is left of the last one) is marked to be paid
           -- out to her purse over the next 24 hours (public.city_coupon_hour). Dark, and for every merchant, both keep their value.
           drip_left = case when (select public.dividend_hourly_on()) and not (select pl.is_npc from public.players pl where pl.id = s.player_id)
                            then least(s.drip_left, s.accrued) + a.pay else s.drip_left end,
           drip_hour = case when (select public.dividend_hourly_on()) and not (select pl.is_npc from public.players pl where pl.id = s.player_id)
                            then greatest(sign((least(s.drip_left, s.accrued) + a.pay)::numeric), round((least(s.drip_left, s.accrued) + a.pay) / 24.0))::bigint
                            else s.drip_hour end
      from a where s.port_id = p_port and s.kind = a.kind and s.player_id = a.player_id
$h$,
$h$    update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today
      from a where s.port_id = p_port and s.kind = a.kind and s.player_id = a.player_id
$h$);
  for h in select * from back_0495 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0495 rollback refuses: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop function public.city_coupon_hour(timestamptz);
  drop function public.real_hour(timestamptz);
  drop function public.dividend_hourly_on();
  alter table public.city_shares drop column drip_left, drop column drip_hour, drop column drip_at;
  delete from public.world_config where key = 'dividend_hourly_enabled';
  raise notice '0495 rollback ok: public.tick_city % and public.city_coupons % are their bodies of before 0495; three functions, three columns and the knob are gone',
    md5(replace(pg_get_functiondef('public.tick_city(timestamp with time zone)'::regprocedure), E'\r', '')),
    md5(replace(pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure), E'\r', ''));
end $r$;
