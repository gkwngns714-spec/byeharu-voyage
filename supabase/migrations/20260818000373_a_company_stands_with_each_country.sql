-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0373 — A COMPANY STANDS WITH EACH COUNTRY: world_config `regard_enabled` false -> true. One knob row is written and one news row is posted. No function, no table, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. Owner row 288: "we need to build systems such as affinity prior to the system". 0319 built a company's regard with each country dark behind this one switch
--   (docs/WORLD_POWERS.md 2.1, slice W1). Owner, 2026-11-13 (row 324): "do all, make everything work. open them if everything is built and is workable." This file is that one light
--   (the form of 0178 and 0179). It comes before attacks on purpose: an attack costs regard only while this is lit.
-- WHAT THE SWITCH TURNS ON (every reader is live already; none is touched here):
--   * a company's score with a country = the base of her power's stance with it (regard_stance_base: home 200, ally 100, peace 0, rival -100, war -200) + what she has earned, which
--     halves every 72 hours. Five bands (regard_bands): Honoured x0.8, Friendly x0.9, Neutral x1, Wary x1.25, Hostile x2;
--   * that factor multiplies her PROFIT TAX (world.tax_rate; still under tariff_rate_max) and her DOCK FEE (public.port_fee) in every city that country holds. A free city: x1;
--   * gifts and stakes earn it (regard_per_100k 10 a 100,000 d.); the Town Hall shows the band and, at a capital, a fine she may pay to buy back bad points (cmd.pay_fine, kind FINE);
--     the Levels page lists her standing with every country instead of "Not open yet.".
--   * A merchant, a cargo ship, a navy ship and a pirate ship have no regard: x1, as today.
-- DAY ONE, WITH NO ROW WRITTEN: at home she is Friendly (x0.9 on tax and dock fee); with a country her power is at war with she is Wary (x1.25); ally, peace and rival are Neutral (x1).
--   scripts/ops/harness/regard/before-light.sql lists it per company, read-only, before the deploy.
-- world.trip_cost (0360) and Trade's board (0361) ask public.port_fee and world.tax_rate, so the figures they name carry the factor
--   (scripts/db/proofs/74_regard_lit.sql sails a trip to a city at war and compares).
-- GUARD (the file refuses, and nothing is written, when any of these is not so):
--   * 0319's functions and table and 0347's news exist;
--   * the switch row exists and reads exactly false;
--   * nobody holds earned regard yet (public.house_regard is empty: every writer was dark);
--   * THE PRECONDITION READ: for EVERY company and EVERY country that holds a harbour, public.regard_of answers and public.regard_band finds a band with a factor. A stance that
--     regard_stance_base does not price raises E_NO_REGARD_BASE inside every tax quote and every arrival in that country's cities; this read is where that would show, before the light.
-- SELF-ASSERT, on a probe company of this file's own, rolled back (the closed economy, the city purses and the influence race set inside the probe, as on prod, so a dock fee is charged and the tax reads the stance): at home the factor is the
--   Friendly band's, her tax rate is the dark rate times it, her dock fee the dark fee times it; in a city of a country at war (where this world has one) the Wary band's; a free
--   city and a merchant x1; the Town Hall's line names the band and the factor she pays; public.regard_add writes her row and an event; THE ROLLBACK PLAYED inside the probe (the
--   switch set false): factor 1, the dark tax and fee to the digit, no line, the fine refused E_NOT_IN_USE. The catalog: no function moved; exactly one world_config row moved.
-- ALTERS LIVE PLAY: its own window, a 30-minute after-check (scripts/ops/harness/regard/after-light.sql: taxes and dock fees taken by band, house_regard rows, FINE flows).
-- ROLLBACK (forward; a draft is scripts/ops/harness/regard/rollback-0373.sql): the same row set back to false. Every factor is 1 at once, the hall serves no line, the fine door
--   refuses; earned rows and FINE ledger rows stay. The one-line form (owner only): update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0373', 'Standing with each country: tax and dock fee', '나라별 평판: 세금과 입항료') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0373 - deploys after 0372 (npc_ship_level_enabled), in its own window. It names no function of 0364 to 0372.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_pairs       int;
  v_bad         int;
  v_bands       jsonb;
  v_fn_before   text;
  v_cfg_before  text;
  v_lived       boolean := false;
  v_lis         uuid;
  v_prt         uuid;
  v_war         uuid;      -- a harbour of a country at war with the probe's, where this world has one
  v_free        uuid;      -- a harbour no country holds, where this world has one
  v_pl          uuid;
  v_npc         uuid;
  v_fl          uuid;
  v_home_f      numeric;
  v_war_f       numeric;
  v_rate_lit    numeric;
  v_rate_dark   numeric;
  v_fee_lit     bigint;
  v_fee_dark    bigint;
  v_line        jsonb;
  v_ev          bigint;
  v_err         text;
  v_note        text := '';
  v_ms_pre      numeric;
  v_ms_probe    numeric;
  c_key         constant text := 'regard_enabled';
  c_stock       constant numeric := 100000;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['public.regard_on()', 'public.regard_of(uuid,uuid)', 'public.regard_band(numeric)', 'public.regard_factor(uuid,uuid)', 'public.regard_line(uuid,uuid)',
                                        'public.regard_add(uuid,uuid,numeric,text)', 'public.fine_for(uuid,uuid,bigint)', 'world.tax_rate(uuid,uuid)', 'public.port_fee(uuid,uuid,numeric)',
                                        'public.port_nation(uuid)', 'public.form_fleet(uuid,text,uuid)', 'public.news_update(text,text,text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.house_regard') is null then
    raise exception '0373 refuses: regard (0319) or the news (0347) are not in this world';
  end if;
  if (select c.value from public.world_config c where c.key = c_key) is distinct from 'false'::jsonb or public.regard_on() then
    raise exception '0373 refuses: % is not false in this world (it reads %): this file lights it once, from dark', c_key, (select c.value from public.world_config c where c.key = c_key);
  end if;
  if exists (select 1 from public.house_regard) then
    raise exception '0373 refuses: % row(s) of earned regard exist while every writer was dark; read scripts/ops/harness/regard/before-light.sql first', (select count(*) from public.house_regard);
  end if;

  -- ── 1. THE PRECONDITION READ: every company with every country that holds a harbour gets a score and a band with a factor (before-light.sql's read, as an assert) ──
  v_t := clock_timestamp();
  begin
    with n as (select distinct public.port_nation(p.id) as nation_id from public.ports p where p.kind = 'HARBOUR'),
    x as (
      select public.regard_band(public.regard_of(pl.id, n.nation_id)) as band
        from public.players pl cross join n
       where not pl.is_npc and n.nation_id is not null
    )
    select count(*), count(*) filter (where x.band is null or (x.band ->> 'factor') is null or (x.band ->> 'factor')::numeric <= 0),
           (select coalesce(jsonb_object_agg(b.k, b.c), '{}'::jsonb) from (select y.band ->> 'band' as k, count(*) as c from x y group by 1) b)
      into v_pairs, v_bad, v_bands from x;
  exception when others then
    get stacked diagnostics v_err = message_text;
    raise exception '0373 refuses: the day-one read failed for a company and a country (%): lit, every tax quote and arrival in that country''s cities would fail the same way', v_err;
  end;
  if v_bad > 0 then
    raise exception '0373 refuses: % of % company-and-country pair(s) get no band or no factor from regard_bands', v_bad, v_pairs;
  end if;
  v_ms_pre := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 2. BEFORE: the catalog and every OTHER knob ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c where c.key <> c_key;

  -- ── 3. THE LIGHT ──
  update public.world_config
     set value = 'true'::jsonb, updated_at = now(), description = description || ' LIT by 0373 (owner row 324, 2026-11-13).'
   where key = c_key and value = 'false'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or not public.regard_on() then
    raise exception '0373 self-assert FAIL: % row(s) written, and the reader says %', v_n, public.regard_on();
  end if;

  -- ── 4. THE SELF-ASSERT: a probe company and a probe merchant of this file's own, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select n.id into v_prt from public.nations n where n.code = 'PRT';
    if v_lis is null or v_prt is null or public.port_nation(v_lis) is distinct from v_prt then
      raise exception '0373 self-assert FAIL: Lisbon is not Portugal''s harbour in this world';
    end if;
    -- the closed economy, the city purses and the influence race lit, inside this probe only (as on prod): a dock fee is charged and the tax reads the stance
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled', 'influence_enabled');   -- world.tax_rate reads the regard only on this path (prod: all three true)
    insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa da Prova 0373', v_prt, 1000000, false) returning id into v_pl;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Mercador da Prova 0373', v_prt, 1000000, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Prova 0373', v_lis);
    select p.id into v_war from public.ports p
     where p.kind = 'HARBOUR' and public.power_stance(v_prt, public.port_nation(p.id)) = 'war' order by p.code limit 1;
    select p.id into v_free from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is null order by p.code limit 1;

    -- (a) AT HOME: the band of the home base, on the tax and on the dock fee
    v_home_f := public.regard_factor(v_pl, v_lis);
    v_rate_lit := world.tax_rate(v_lis, v_pl);
    v_fee_lit := public.port_fee(v_lis, v_pl, c_stock);
    v_line := public.regard_line(v_lis, v_pl);
    if v_home_f is distinct from (public.regard_band((public.wc('regard_stance_base') ->> 'home')::numeric) ->> 'factor')::numeric
       or (v_line -> 'regard' ->> 'factor')::numeric is distinct from v_home_f
       or v_line -> 'regard' ->> 'band' is distinct from public.regard_band((public.wc('regard_stance_base') ->> 'home')::numeric) ->> 'band'
       or public.regard_factor(v_npc, v_lis) <> 1 or public.regard_line(v_lis, v_npc) <> '{}'::jsonb then
      raise exception '0373 self-assert FAIL: lit, at home the factor is % and the hall''s line %, or a merchant has a regard', v_home_f, v_line;
    end if;
    -- (b) A COUNTRY AT WAR, where this world has one: the band of the war base
    if v_war is not null then
      v_war_f := public.regard_factor(v_pl, v_war);
      if v_war_f is distinct from (public.regard_band((public.wc('regard_stance_base') ->> 'war')::numeric) ->> 'factor')::numeric then
        raise exception '0373 self-assert FAIL: lit, in a city of a country at war the factor is %', v_war_f;
      end if;
      v_note := format('in a city of a country at war x%s; ', v_war_f);
    end if;
    -- (c) A FREE CITY, where this world has one: no regard
    if v_free is not null and (public.regard_factor(v_pl, v_free) <> 1 or public.regard_line(v_free, v_pl) <> '{}'::jsonb) then
      raise exception '0373 self-assert FAIL: lit, a free city has a regard';
    end if;
    -- (d) EARNED: the one writer writes her row and an event
    select count(*) into v_ev from public.events e where e.player_id = v_pl and e.kind = 'REGARD_CHANGED';
    perform public.regard_add(v_pl, v_prt, 25, 'PROBE_0373');
    if (select r.points from public.house_regard r where r.player_id = v_pl and r.nation_id = v_prt) is distinct from 25
       or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'REGARD_CHANGED') <> v_ev + 1
       or round(public.regard_of(v_pl, v_prt)) <> (public.wc('regard_stance_base') ->> 'home')::numeric + 25 then
      raise exception '0373 self-assert FAIL: lit, 25 points earned are not her row, her event and her score';
    end if;
    delete from public.house_regard r where r.player_id = v_pl;   -- this probe's own row (not an append-only table): the figures below are the base's again

    -- (e) THE ROLLBACK, PLAYED: the switch set back gives the dark figures, and the lit ones were exactly the dark ones times the factor
    update public.world_config set value = 'false'::jsonb where key = c_key;
    v_rate_dark := world.tax_rate(v_lis, v_pl);
    v_fee_dark := public.port_fee(v_lis, v_pl, c_stock);
    if public.regard_factor(v_pl, v_lis) <> 1 or public.regard_line(v_lis, v_pl) <> '{}'::jsonb or v_fee_dark <= 0 or v_rate_dark <= 0 then
      raise exception '0373 self-assert FAIL: with the switch set back the factor is not 1 or the hall still serves a line (dark rate %, dark fee %)', v_rate_dark, v_fee_dark;
    end if;
    if v_rate_lit is distinct from least(v_rate_dark * v_home_f, greatest(v_rate_dark, public.wc_num('tariff_rate_max')))
       or abs(v_fee_lit - v_fee_dark * v_home_f) > 1 then
      raise exception '0373 self-assert FAIL: lit, the home tax rate % is not the dark % times %, or the dock fee % is not the dark % times it', v_rate_lit, v_rate_dark, v_home_f, v_fee_lit, v_fee_dark;
    end if;
    begin
      perform public.fine_for(v_pl, v_lis, 100);
      raise exception '0373 self-assert FAIL: with the switch set back a fine was taken';
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text;
      if v_err like '0373 self-assert FAIL%' then raise; end if;
      if v_err not like 'E_NOT_IN_USE%' then
        raise exception '0373 self-assert FAIL: with the switch set back the fine door answered: %', v_err;
      end if;
    end;
    raise exception using errcode = 'ZX373', message = 'PROBE_ROLLBACK_0373';
  exception when sqlstate 'ZX373' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0373 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.company_name in ('Casa da Prova 0373', 'Mercador da Prova 0373')) or exists (select 1 from public.house_regard) then
    raise exception '0373 self-assert FAIL: a probe house or a regard row outlived the probe';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 5. AFTER: lit, and nothing else moved ──
  if not public.regard_on() or (select c.value from public.world_config c where c.key = c_key) is distinct from 'true'::jsonb then
    raise exception '0373 self-assert FAIL: the switch is not lit after the probe';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0373 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c where c.key <> c_key) <> v_cfg_before then
    raise exception '0373 self-assert FAIL: another world_config row moved: this file writes one';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0373', 'Standing with each country: tax and dock fee', '나라별 평판: 세금과 입항료');
  if (select count(*) from public.world_news w where w.key = 'update:0373') <> 1 then
    raise exception '0373 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0373 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0373 timings: the day-one read (% company-and-country pair(s)) % ms; the probe % ms', v_pairs, v_ms_pre, v_ms_probe;
  raise notice '0373 self-assert ok: A COMPANY STANDS WITH EACH COUNTRY. regard_enabled was false and is true; nobody held earned regard. Day one, % company-and-country pair(s), every one with a band and a factor: %. A probe company of Portugal: at home x% on the tax rate and on the dock fee (the dark figures times the factor, to the digit and the ducat); %a free city and a merchant x1; the hall''s line names her band and the factor she pays; 25 points earned are her row, her event and her score; with the switch set back (the rollback, played and rolled back) the factor is 1, the hall serves no line and the fine door refuses E_NOT_IN_USE. No function moved, no other knob moved, its UPDATE row is one row. % ms.',
    v_pairs, v_bands, v_home_f, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
