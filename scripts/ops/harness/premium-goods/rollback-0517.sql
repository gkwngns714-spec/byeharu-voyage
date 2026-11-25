-- 0517 FORWARD ROLLBACK, A DRAFT (owner only). THE QUICK ROLLBACK NEEDS NO FILE: premium_goods_enabled false. To use this one, strip the guard line, give it
-- the next number, add "-- news: none", and withdraw 0517's proof with the same PR. It reverses 0517's 16 hunks and drops what it made.
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
  if public.wc('premium_goods_enabled') = 'true'::jsonb then
    raise exception '0517 rollback refuses: premium_goods_enabled is lit; the owner darkens it first';
  end if;
  create temp table back_0517 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0517 values
  (1, 'world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)',
$h$  v_wper   bigint;    -- 0255: the row's want marker (port_goods.want_period), read with its stock
  v_pmult  numeric;   -- 0517: what this city pays for its one premium good, times the normal price (none dark)
  v_pleft  numeric := 0;   -- 0517: the units it still takes at it today
  v_prem   boolean := false;   -- 0517: units are still left at the premium (the walk tests this one flag)
$h$,
$h$  v_wper   bigint;    -- 0255: the row's want marker (port_goods.want_period), read with its stock
$h$),
  (2, 'world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)',
$h$  -- 0517 (dark: premium_goods_enabled): lit, THE ONE CITY THAT WANTS THIS MADE GOOD pays its multiple to a company for the units still left
  -- today (public.premium_left, read once a sale; no row for a quote with no fleet, a merchant, another city, or a purse with none to spare).
  if p_side = 'sell' and p_fleet is not null and public.premium_on() then
    select w.mult, w.left_units into v_pmult, v_pleft from public.premium_left(p_fleet, p_port, p_good) w;
    v_pleft := coalesce(v_pleft, 0);
    v_prem  := v_pleft > 0;
  end if;

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
$h$,
$h$  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
$h$),
  (3, 'world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)',
$h$    if v_prem then   -- 0517: the premium units first (never times a want too); the shelf splits where they run out
      v_n     := least(v_n, v_pleft);
      v_mid   := v_mid * v_pmult;
      v_pleft := v_pleft - v_n;
      v_prem  := v_pleft > 0;
    elsif v_want then   -- 0255 (E6b): a sale's units at the want price; the shelf splits where the want runs out (a sale's mid
$h$,
$h$    if v_want then   -- 0255 (E6b): a sale's units at the want price; the shelf splits where the want runs out (a sale's mid
$h$),
  (4, 'cmd.do_sell(uuid,jsonb)',
$h$  v_prem    numeric := 0;  -- 0517: the units of this sale at the city's premium (0 dark)
  v_trip    bigint;        -- 0490$h$,
$h$  v_trip    bigint;        -- 0490$h$),
  (5, 'cmd.do_sell(uuid,jsonb)',
$h$  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;
  perform public.premium_hold(f.port_id, g.id);   -- 0517 (dark: nothing): one sale at a time of a city's premium good, so two never share its last units
$h$,
$h$  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;
$h$),
  (6, 'cmd.do_sell(uuid,jsonb)',
$h$  -- 0517 (dark: 0): the units of it the quote paid the premium on, read before anything moves (public.premium_left, the quote's own reader)
  v_prem   := coalesce((select least(q.units, w.left_units) from public.premium_left(p_fleet, f.port_id, g.id) w), 0);
  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);
$h$,
$h$  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);
$h$),
  (7, 'cmd.do_sell(uuid,jsonb)',
$h$  if v_prem > 0 then   -- 0517: they count against the city's day
    perform public.premium_spend(f.port_id, g.id, v_prem);
  end if;
  -- 0255 (E6b): the units this sale took at the city's want price count against the period's cap
$h$,
$h$  -- 0255 (E6b): the units this sale took at the city's want price count against the period's cap
$h$),
  (8, 'cmd.do_sell(uuid,jsonb)',
$h$least(q.units - v_prem, w.left_units)   -- 0517: less those at the premium
    from world.want_left(f.port_id, g.id) w
   where w.left_units > 0 and q.units > v_prem
$h$,
$h$least(q.units, w.left_units)
    from world.want_left(f.port_id, g.id) w
   where w.left_units > 0
$h$),
  (9, 'cmd.do_sell(uuid,jsonb)',
$h$      || coalesce(v_gift, '{}'::jsonb)
      || case when v_prem > 0 then jsonb_build_object('premium_units', v_prem) else '{}'::jsonb end;   -- 0517 (absent when none)
$h$,
$h$      || coalesce(v_gift, '{}'::jsonb);
$h$),
  (10, 'world.mid_terms(uuid,uuid)',
$h$  select g.base_value * case when g.premium_port_id is null then 1 else public.premium_lift() end   -- 0517 (dark: x 1): a premium good costs more, everywhere
       , pg.affinity$h$,
$h$  select g.base_value, pg.affinity$h$),
  (11, 'world.good_mids(uuid)',
$h$mid_from_terms(g.base_value * case when g.premium_port_id is null then 1 else (select public.premium_lift()) end,   -- 0517: world.mid_terms' own base
                              pg.affinity$h$,
$h$mid_from_terms(g.base_value, pg.affinity$h$),
  (12, 'world.market(uuid)',
$h$'range_lo', world.mid_from_terms(g.base_value * case when g.premium_port_id is null then 1 else public.premium_lift() end,   -- 0517: world.mid_terms' own base
                      $h$,
$h$'range_lo', world.mid_from_terms(g.base_value, $h$),
  (13, 'world.market(uuid)',
$h$'range_hi', world.mid_from_terms(g.base_value * case when g.premium_port_id is null then 1 else public.premium_lift() end,   -- 0517: world.mid_terms' own base
                      $h$,
$h$'range_hi', world.mid_from_terms(g.base_value, $h$),
  (14, 'world.market(uuid)',
$h$                       from world.want_left(pg.port_id, pg.good_id) w), '{}'::jsonb)
        -- 0517: a premium good carries {premium: its one city, what it pays, the units left today} (absent dark and otherwise)
        || coalesce(case when g.premium_port_id is not null then public.premium_face(g.id) end, '{}'::jsonb)
$h$,
$h$                       from world.want_left(pg.port_id, pg.good_id) w), '{}'::jsonb)
$h$),
  (15, 'world.goods_forge(uuid)',
$h$             where gr.product_id = g.id))
          -- 0517: a premium good's one city and its pay (absent dark and otherwise)
          || coalesce(case when g.premium_port_id is not null then public.premium_face(g.id) end, '{}'::jsonb)
        order by g.tier, g.name), '[]'::jsonb)$h$,
$h$             where gr.product_id = g.id))
        order by g.tier, g.name), '[]'::jsonb)$h$),
  (16, 'world.board_sell_memo(uuid,uuid,jsonb,jsonb)',
$h$order by (c.nm is null), (c.id is not distinct from (select public.premium_port(p_good))) desc,   -- 0517: the city that pays the premium is always priced (dark: none)
                                       c.mid desc, c.nm nulls last, c.code) as rk$h$,
$h$order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk$h$);
  for h in select * from back_0517 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0517 rollback refuses: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop function public.premium_face(uuid);
  drop function public.premium_port(uuid);
  drop function public.premium_spend(uuid,uuid,numeric);
  drop function public.premium_hold(uuid,uuid);
  drop function public.premium_left(uuid,uuid,uuid);
  drop function public.premium_units(uuid,uuid);
  drop function public.premium_mult(numeric);
  drop function public.premium_lift();
  drop function public.premium_on();
  drop index public.goods_premium_port_one;
  alter table public.goods drop column premium_port_id;
  alter table public.port_goods drop column premium_day, drop column premium_units;
  delete from public.world_config where key like 'premium\_%' and description like '0517:%';
  raise notice '0517 rollback ok: %', (select string_agg(x.fn || ' ' || md5(replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '')), ', ' order by x.fn)
                                       from (select distinct fn from back_0517) x);
end $r$;
