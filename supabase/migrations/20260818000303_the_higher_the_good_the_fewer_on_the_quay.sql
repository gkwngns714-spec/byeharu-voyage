-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0303 — THE HIGHER THE GOOD, THE FEWER ON THE QUAY   (stock by production tier; designated rare raw materials carry less still)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ORDER (owner, 2026-11-02) ───────────────────────────────────────────────────────────────
--   "higher tier items should have less quantity for purchase. Also designate rare raw materials such as gold, diamond, and make the quantities less."
--
-- ── THE MECHANISM TODAY (found, not assumed) ────────────────────────────────────────────────────
--   What a buyer can purchase of a good at a harbour is port_goods.stock, held at or under port_goods.stock_target (the harbour's max stock for that good; 0252 keeps
--   base_target beside it and sets stock_target = base_target x the day's depth multiple). Every per-trade / per-day limit is a fraction of stock_target:
--   the daily cap is world_config.daily_cap_fraction x stock_target (0005 :472, 0027), the walk shelves and the press (0211, 0271) are per stock_target.
--   stock_target was seeded ONCE, by migrations, as greatest(60, round(200 x ports.size_tier x (1.60 - affinity))) (0005, 0058, 0065, 0280): it knows the city's
--   size and its affinity for the good and NOTHING about the good's tier or rarity. So a tier-3 luxury and a bale of sand had the same depth. There is no
--   client-side stock logic: the client prints what the server serves.
--
-- ── THE TWO RULES, APART ────────────────────────────────────────────────────────────────────────
--   (a) TIER:  stock scale by goods.tier 0..3 = world_config.stock_tier_scale (a four-number jsonb array, index tier+1).
--   (b) RARE:  goods.is_rare (the designation, new column, default false) -> world_config.stock_rare_scale. A rare good takes the SMALLER of its tier scale and the
--              rare scale (never both multiplied: one cut, the deeper of the two).
--   public.good_stock_scale(good) is THE ONE READER of both knobs and the designation. A floor, world_config.stock_floor_units, keeps a max stock from rounding to nothing.
--
-- ── THE RE-CUT (one time, price-neutral) ─────────────────────────────────────────────────────────
--   For each port_goods row whose good has scale < 1: r = new_base / old_base, new_base = greatest(floor, round(old_base x scale, 2)), old_base = base_target when
--   the 0252 depth multiple has set one, else stock_target. stock_target, base_target (if set), stock and production_rate are ALL multiplied by r. The price reads
--   stock_target / stock, which r leaves as it was: no price moves at the instant of the cut; only how much can be bought at that price (and so the daily cap,
--   which is a fraction of stock_target) falls. Stock is scaled, not clipped: that is the one time the cut removes goods, and it is the order.
--   NOT touched: any economy switch, knob other than the three new ones, cron job, clock, purse, price, drift, demand.
--
-- ── THE NUMBERS (recommended; the owner tunes the knobs, the served stock follows the next daily re-set, no deploy) ──
--   stock_tier_scale [1, 0.6, 0.35, 0.15]   raw 100 %, tier 1 60 %, tier 2 35 %, tier 3 15 %.
--   stock_rare_scale 0.15                   a rare raw good holds 15 % of what an ordinary raw good would.
--   stock_floor_units 5                     no max stock under 5 tuns.
--   RARE (24 raw goods, tier 0, all in the metal / gems categories of data/goods.json): gold, gold-dust, andacollo-gold, platinum, silver, potosi-silver,
--   zacatecas-silver, diamonds, golconda-diamonds, rubies, burma-rubies, emeralds, emerald-muzo, ceylon-sapphires, opals, peridot, lapis-lazuli, jade, nephrite,
--   malachite, onyx, pearls, seed-pearls, baja-pearls. Not designated: quicksilver (a bulk mine product), amber, ivory, coral, tortoiseshell (animal / organic),
--   spices (valueBand 5 but grown, not mined or dived). ashanti-goldwork is a crafted good (tier >= 1) and takes its tier scale.
--
-- ── NEW ROWS ──────────────────────────────────────────────────────────────────────────────────
--   A later migration that seeds port_goods rows for new goods must multiply its seed by public.good_stock_scale(good) (server-only reader); this file re-cuts the
--   rows that exist.
--
-- ── SELF-ASSERT (all inside the one block; any failure rolls the lot back) ──────────────────────
--   (a) the designation: exactly the 24 codes, all raw, all existing; knobs are four ascending-to-descending valid numbers in (0,1];
--   (b) the rule: good_stock_scale of a plain raw good is 1, of a tier-1/2/3 good is the knob, of a rare good is least(tier scale, rare scale);
--   (c) the cut: no row grew; every cut row's stock_target is its old one x scale within rounding, or the floor; stock / stock_target unchanged within rounding;
--       rows with scale 1 are byte-identical; the mean stock_target falls tier by tier and a rare good's mean is under half the plain raw mean;
--   (d) nothing else moved: world_config (md5 without the three new keys), every other function's md5, the cron jobs.
-- ROLLBACK (forward, a NEW migration, owner only): divide by the same scales; the knobs and the column stay.
-- VERSION: 0303 - prod head 0302 (2026-11-02).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_rare constant text[] := array['gold','gold-dust','andacollo-gold','platinum','silver','potosi-silver','zacatecas-silver',
    'diamonds','golconda-diamonds','rubies','burma-rubies','emeralds','emerald-muzo','ceylon-sapphires','opals','peridot',
    'lapis-lazuli','jade','nephrite','malachite','onyx','pearls','seed-pearls','baja-pearls'];
  v_cfg_before  text;
  v_fn_before   text;
  v_cron_before text;
  v_cron_after  text;
  v_n          int;
  v_tiers       numeric[];
  v_rare_scale  numeric;
  v_floor       numeric;
  v_t           int;
  v_prev        numeric;
  v_mean        numeric;
  v_plain0      numeric;
  v_rare_mean   numeric;
  v_cut         int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: not applied before ──
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'goods' and column_name = 'is_rare')
     or exists (select 1 from public.world_config where key in ('stock_tier_scale', 'stock_rare_scale', 'stock_floor_units')) then
    raise exception '0303 refuses: the stock scale has been applied once';
  end if;
  if (select count(*) from public.goods where code = any (c_rare)) <> array_length(c_rare, 1) then
    raise exception '0303 refuses: not every rare code is a good in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE DESIGNATION ──
  alter table public.goods add column is_rare boolean not null default false;
  comment on column public.goods.is_rare is
    '0303: the owner''s designation of a rare raw material (precious metals, gems). Read only by public.good_stock_scale, which cuts its stock. Not derived: public.good_rarity is how few harbours make a good, a different idea.';
  update public.goods set is_rare = true where code = any (c_rare);
  get diagnostics v_n = row_count;
  if v_n <> array_length(c_rare, 1) then
    raise exception '0303 FAIL: % goods designated, expected %', v_n, array_length(c_rare, 1);
  end if;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('stock_tier_scale', '[1, 0.6, 0.35, 0.15]'::jsonb,
     '0303: the share of a harbour''s max stock a good of production tier 0, 1, 2, 3 keeps (array index tier+1). Read by public.good_stock_scale alone. Owner-tunable; takes effect on rows seeded or re-cut after the change.'),
    ('stock_rare_scale', to_jsonb(0.15),
     '0303: the share of a harbour''s max stock a designated rare good (goods.is_rare) keeps. A rare good takes the smaller of this and its tier scale.'),
    ('stock_floor_units', to_jsonb(5),
     '0303: no max stock is cut below this many tuns.');

  -- ── 3. THE ONE READER ──
  create function public.good_stock_scale(p_good uuid)
  returns numeric
  language sql
  stable
  set search_path = public, pg_temp
  as $f$
    select case when g.is_rare
                then least(t.scale, public.wc_num('stock_rare_scale'))
                else t.scale end
      from public.goods g
      cross join lateral (
        select (public.wc('stock_tier_scale') ->> g.tier::int)::numeric as scale
      ) t
     where g.id = p_good
  $f$;
  comment on function public.good_stock_scale(uuid) is
    '0303: the share of a harbour''s max stock a good keeps: its tier''s scale (world_config.stock_tier_scale) or, for a designated rare good, the smaller of that and stock_rare_scale. THE one reader of both knobs and the designation. Server-only.';
  revoke all on function public.good_stock_scale(uuid) from public, anon, authenticated;

  -- ── 4. THE CUT (one statement; price-neutral: stock, stock_target, base_target, production_rate all x r) ──
  create temp table pre_0303 on commit drop as
    select pg.port_id, pg.good_id, pg.stock, pg.stock_target, pg.base_target, pg.production_rate,
           public.good_stock_scale(pg.good_id) as scale
      from public.port_goods pg;
  v_floor := public.wc_num('stock_floor_units');

  update public.port_goods pg
     set stock_target    = greatest(0.01, round(pre.stock_target * k.r, 2)),
         base_target     = case when pre.base_target is null then null else k.new_base end,
         stock           = least(round(pre.stock * k.r, 2), greatest(0.01, round(pre.stock_target * k.r, 2))),
         production_rate = round(pre.production_rate * k.r, 2)
    from pre_0303 pre
    cross join lateral (
      select greatest(v_floor, round(coalesce(pre.base_target, pre.stock_target) * pre.scale, 2)) as new_base
    ) nb
    cross join lateral (
      select least(1, nb.new_base / coalesce(pre.base_target, pre.stock_target)) as r, nb.new_base
    ) k
   where pre.port_id = pg.port_id and pre.good_id = pg.good_id and pre.scale < 1;
  get diagnostics v_cut = row_count;

  -- ── 5. SELF-ASSERT ──
  -- (a) designation and knobs
  select array_agg(e::numeric order by o) into v_tiers from jsonb_array_elements_text(public.wc('stock_tier_scale')) with ordinality x(e, o);
  v_rare_scale := public.wc_num('stock_rare_scale');
  if array_length(v_tiers, 1) <> 4 or v_tiers[1] <> 1 or exists (select 1 from unnest(v_tiers) s where s <= 0 or s > 1)
     or v_tiers[1] < v_tiers[2] or v_tiers[2] < v_tiers[3] or v_tiers[3] < v_tiers[4] or v_rare_scale <= 0 or v_rare_scale >= 1 or v_floor <= 0 then
    raise exception '0303 self-assert FAIL: a knob is not a valid descending scale in (0,1]';
  end if;
  if (select count(*) from public.goods where is_rare) <> array_length(c_rare, 1)
     or exists (select 1 from public.goods where is_rare and tier <> 0) then
    raise exception '0303 self-assert FAIL: the rare designation is not the 24 raw goods';
  end if;

  -- (b) the rule
  for v_t in 0..3 loop
    select count(*) into v_n from public.goods g
     where g.tier = v_t and not g.is_rare and public.good_stock_scale(g.id) is distinct from v_tiers[v_t + 1];
    if v_n > 0 then raise exception '0303 self-assert FAIL: % tier-% good(s) do not take the tier scale', v_n, v_t; end if;
  end loop;
  if exists (select 1 from public.goods g where g.is_rare and public.good_stock_scale(g.id) is distinct from least(v_tiers[1], v_rare_scale)) then
    raise exception '0303 self-assert FAIL: a rare good does not take the rare scale';
  end if;

  -- (c) the cut
  if v_cut = 0 then raise exception '0303 self-assert FAIL: no row was cut'; end if;
  if exists (select 1 from pre_0303 pre join public.port_goods pg using (port_id, good_id)
              where pg.stock_target > pre.stock_target or pg.stock > pre.stock or pg.production_rate > pre.production_rate) then
    raise exception '0303 self-assert FAIL: a row grew';
  end if;
  if exists (select 1 from pre_0303 pre join public.port_goods pg using (port_id, good_id)
              where pre.scale >= 1 and (pg.stock, pg.stock_target, pg.base_target, pg.production_rate)
                    is distinct from (pre.stock, pre.stock_target, pre.base_target, pre.production_rate)) then
    raise exception '0303 self-assert FAIL: a row of scale 1 moved';
  end if;
  select count(*) into v_n from pre_0303 pre join public.port_goods pg using (port_id, good_id)
   where pre.scale < 1
     and pg.stock_target > v_floor * 1.05 and pre.stock_target * pre.scale > v_floor * 1.05
     and abs(pg.stock_target / (pre.stock_target * pre.scale) - 1) > 0.01;
  if v_n > 0 then raise exception '0303 self-assert FAIL: % cut row(s) are not at old x scale', v_n; end if;
  select count(*) into v_n from pre_0303 pre join public.port_goods pg using (port_id, good_id)
   where pre.scale < 1 and pre.stock_target >= 20 and pg.stock_target >= 20
     and abs(pg.stock / pg.stock_target - pre.stock / pre.stock_target) > 0.02;
  if v_n > 0 then raise exception '0303 self-assert FAIL: % row(s) changed their stock/target ratio (a price would move)', v_n; end if;
  if exists (select 1 from public.port_goods where stock > stock_target) and not exists (select 1 from pre_0303 where stock > stock_target) then
    raise exception '0303 self-assert FAIL: a cut left stock over its max';
  end if;

  v_prev := null;
  for v_t in 0..3 loop
    select avg(pg.stock_target) into v_mean from public.port_goods pg join public.goods g on g.id = pg.good_id where g.tier = v_t and not g.is_rare;
    if v_prev is not null and v_mean >= v_prev then
      raise exception '0303 self-assert FAIL: mean max stock of tier % (%) is not under tier % (%)', v_t, v_mean, v_t - 1, v_prev;
    end if;
    v_prev := v_mean;
    if v_t = 0 then v_plain0 := v_mean; end if;
  end loop;
  select avg(pg.stock_target) into v_rare_mean from public.port_goods pg join public.goods g on g.id = pg.good_id where g.is_rare;
  if v_rare_mean >= v_plain0 * 0.5 then
    raise exception '0303 self-assert FAIL: rare mean max stock % is not under half the plain raw mean %', v_rare_mean, v_plain0;
  end if;

  -- (d) nothing else moved
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('stock_tier_scale', 'stock_rare_scale', 'stock_floor_units')) is distinct from v_cfg_before then
    raise exception '0303 self-assert FAIL: a world_config row other than the three new knobs moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> 'public.good_stock_scale(uuid)'::regprocedure) is distinct from v_fn_before then
    raise exception '0303 self-assert FAIL: an existing function changed';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0303 self-assert FAIL: a cron job moved';
    end if;
  end if;
end
$m$;
