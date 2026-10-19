-- PROTOTYPE of 0213's functional core (no proofs) — for the calibration sweep only
insert into public.world_config (key, value, description) values
  ('far_glut_power', to_jsonb(0), 'proto'),
  ('far_glut_decay', to_jsonb(0.25), 'proto'),
  ('spoilage_scale', to_jsonb(0), 'proto');
alter table public.port_goods drop constraint if exists port_goods_glut_check;
alter table public.port_goods add constraint port_goods_glut_check check (glut >= 0 and glut <= 0.9999);

create or replace function world.glut_after(p_glut numeric, p_units numeric, p_target numeric, p_haul numeric,
                                            p_per_depth numeric, p_max numeric, p_power numeric, p_far_only boolean)
returns numeric language sql immutable parallel safe as $$
  select least(case when p_power > 0 then greatest(p_max, 1 - (1 - coalesce(nullif(current_setting('far.floor', true), '')::numeric, p_max)) / greatest(p_haul, 1)) else p_max end,
               p_glut + p_per_depth * (coalesce(nullif(current_setting('far.gain', true), '')::numeric, 1) * (power(greatest(p_haul, 1), greatest(p_power, 0)) - 1) + case when p_far_only then 0 else 1 end)
                        * p_units / greatest(p_target, 1))
$$;
create or replace function world.glut_faded(p_glut numeric, p_days numeric, p_haul numeric,
                                            p_decay numeric, p_far_decay numeric, p_power numeric)
returns numeric language sql immutable parallel safe as $$
  select p_glut * power(1 - case when p_power > 0
                                 then p_decay + (p_far_decay - p_decay) * (1 - 1 / greatest(p_haul, 1))
                                 else p_decay end, p_days)
$$;

create temp table hunks_p (fn text, n int, old text, new text) on commit drop;
insert into hunks_p values
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 1,
$h$  k        record;    -- 0169: the four terms (world.quote_terms), when none were handed over
begin$h$,
$h$  k        record;    -- 0169: the four terms (world.quote_terms), when none were handed over
  v_g      numeric;   -- 0213: the glut this quote walks on: the row's (t.m_glut), raised step by step on a sale while far gluts are lit
  v_gpow   numeric;   -- 0213: far_glut_power (0 = dark: nothing moves the glut inside a quote, as 0194)
  v_gper   numeric;
  v_gmax   numeric;
begin$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 2,
$h$  select * into t from world.mid_terms(p_port, p_good);
$h$,
$h$  select * into t from world.mid_terms(p_port, p_good);
  v_g    := t.m_glut;                              -- 0213
  v_gpow := public.wc_num('far_glut_power');       -- 0213: read once a quote
  if v_gpow > 0 and p_side = 'sell' then
    v_gper := public.wc_num('glut_per_depth');
    v_gmax := public.wc_num('glut_max');
  end if;
$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 3,
$h$      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * v_bidf, 2);$h$,
$h$      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194; 0213: the walked glut
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * v_bidf, 2);$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 4,
$h$      v_stock := v_stock + v_n;
$h$,
$h$      v_stock := v_stock + v_n;
      if v_gpow > 0 then   -- 0213: lit, each ton sold pushes the glut up for the next step (world.glut_after, the one rule)
        v_g := world.glut_after(v_g, v_n, t.m_target, t.m_haul, v_gper, v_gmax, v_gpow, true);
      end if;
$h$),
('cmd.do_sell(uuid, jsonb)', 1,
$h$         glut = round(least(public.wc_num('glut_max'),
                            glut + public.wc_num('glut_per_depth') * q.units / greatest(stock_target, 1)), 4)   -- 0194: a sale leaves a mark$h$,
$h$         glut = round(world.glut_after(glut, q.units, stock_target, haul, public.wc_num('glut_per_depth'),
                                       public.wc_num('glut_max'), public.wc_num('far_glut_power'), false), 4)   -- 0194: a sale leaves a mark; 0213: world.glut_after$h$),
('public.tick_market_drift(timestamp with time zone, uuid)', 1,
$h$  v_rate   numeric := public.wc_num('stock_regen_fraction');
$h$,
$h$  v_rate   numeric := public.wc_num('stock_regen_fraction');
  v_gdec   numeric := public.wc_num('glut_decay');       -- 0213: the fade's three knobs, read once a tick (world.glut_faded)
  v_gfar   numeric := public.wc_num('far_glut_decay');
  v_gpow   numeric := public.wc_num('far_glut_power');
$h$),
('public.tick_market_drift(timestamp with time zone, uuid)', 2,
$h$         glut = round(pg.glut * power(1 - public.wc_num('glut_decay'), v_day - pg.last_regen_day), 4),   -- 0194: the glut fades$h$,
$h$         glut = round(world.glut_faded(pg.glut, v_day - pg.last_regen_day, pg.haul, v_gdec, v_gfar, v_gpow), 4),   -- 0194: the glut fades; 0213: world.glut_faded$h$),
('public.price_path(uuid, uuid, integer)', 1,
$h$  v_fade  numeric := 1 - public.wc_num('glut_decay');
$h$,
$h$  v_gdec  numeric := public.wc_num('glut_decay');     -- 0213: the tick's fade, its one rule (world.glut_faded)
  v_gfar  numeric := public.wc_num('far_glut_decay');
  v_gpow  numeric := public.wc_num('far_glut_power');
$h$),
('public.price_path(uuid, uuid, integer)', 2,
$h$        v_g   := round(v_g * power(v_fade, v_d - v_day), 4);   -- 0194: the column's scale, the tick's rule$h$,
$h$        v_g   := round(world.glut_faded(v_g, v_d - v_day, t.m_haul, v_gdec, v_gfar, v_gpow), 4);   -- 0194: the column's scale, the tick's rule (0213: world.glut_faded)$h$);

do $$
declare d record; h record; v_def text;
begin
  for d in select distinct fn from hunks_p loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_p where fn = d.fn order by n loop
      if (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old) <> 1 then
        raise exception 'proto: % hunk % does not occur once', d.fn, h.n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;
