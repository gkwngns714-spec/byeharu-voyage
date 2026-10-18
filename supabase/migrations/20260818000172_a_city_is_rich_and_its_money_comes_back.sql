-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0172 — A CITY IS RICH, AND ITS MONEY COMES BACK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-17 ~23:50 UTC: *"Right now you said that london does not have enough money to do a trade.
-- But this should not happen. Cities are powerful, and they should have some millions of gold as a
-- start. Especially capitals. Provide capitals to capital cities, and then make the economy
-- circulate."* Numbers (the brief, default yes): an ordinary city 2,000,000 d., a capital
-- 10,000,000 d. The circulation design (coordinator, 2026-10-18, default yes, the owner may reverse
-- it): a city earns from what it makes and from every service in its port (already true — measured
-- below); the CAPITAL is the crown treasury — it takes a small share of its cities' tax and tops up a
-- city of its country that falls below its reserve; a city has a DEVELOPMENT INCOME set by its
-- development and its works, so investment visibly raises what it earns.
--
-- ── WHY LONDON WAS BROKE (prod, read-only, head 0169, 2026-10-17 23:50 UTC; docs/dev-log/2026-10-18-city-purses.md)
-- * Every harbour was SEEDED 20,000 d. at the switch (city_seed_min — 0122 seeds 10 × the mean
--   game-day SELL outflow, and at the first switch there were no books, so every harbour got the floor).
-- * London's trade over the 15 full game-days since the switch was nearly flat: it was paid
--   1,234,736 d. for its goods (BUY) and paid 1,292,186 d. for cargo (SELL), +40 k of services, net
--   −15,871 with the works and the shares. Its day-to-day swing is ±100–200 k (22:24 UTC: −124,046 in
--   one game-day). A 20 k purse cannot carry a ±100 k day; its reserve (3 × its SELL day) is 220,305,
--   so it sat at 4,129 — bid factor 0.51. No inflow was MISSING at London: the purse was simply too
--   small for its own turnover. 142 of 238 harbours were under their reserve for the same reason.
-- * The faucets and sinks (§1 of the dev-log): every trade and every port service already pays the
--   city where it happens (BUY, TAX, WAGES, PROVISION, REPAIR — gear repair too —, HIRE, TOW, BUILD,
--   TUITION, OFFICER_WAGE, SHARE, DONATION); wages are NOT a sink — 0122 pays them into the harbour
--   the voyage makes. What leaves a city: SELL, NPC_REFOUND, DIVIDEND, BOUNTY, WORKS_OUT (to its
--   region). Over the 15 game-days the cities as a whole GAINED +761 k a game-day (merchants return
--   their surplus as shares); 120 harbours lost, together −106 k a game-day.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE STANDING PURSE. public.city_standing(port) — city_purse_capital (10,000,000) for the
--     capital of a country (nations.capital_port_code), city_purse_city (2,000,000) for every other
--     harbour. ONE reader.
-- (2) THE GRANT (lit only). Every harbour whose live balance is under its standing purse is topped
--     up to it — never down — through public.treasury_post as one `GRANT` flow each (append-only,
--     dated by created_at, kind GRANT), under the harbour's lock; world_config `city_grant_0172`
--     records when, how many and how much. Dark (a fresh chain), nothing is posted: the switch's seed
--     becomes greatest(standing, city_seed_min, 10 × outflow) instead (one hunk), so a world lit later
--     starts capitalised too. The reserve rule (3 × the SELL day) is untouched: the largest reserve on
--     prod is 534,414, under 2,000,000, so a capitalised city bids 1 (asserted for every harbour).
-- (3) THE CROWN. public.city_capital(port) — the capital of the country that holds the harbour TODAY
--     (public.port_nation, 0143), null for a harbour no country holds. Once a game-day:
--     crown_tax_share (0.10) of the TAX a city took that day goes to its capital (`CROWN_TAX`, −/+);
--     and every hour a city of the country below its reserve is topped up to its reserve from what the
--     capital holds above ITS reserve (`CROWN_AID`, −/+). City to city: conserved, never minted.
-- (4) DEVELOPMENT INCOME. public.city_earnings(port) = city_earnings_per_dev (100) × (dev_industry +
--     dev_commerce + dev_military) × (1 + city_earnings_per_level (0.10) × Σ its works' levels) a
--     game-day — 1,700 to 5,000 d. a game-day at level 0, up to 3× with all twenty levels. Posted once
--     a game-day as `EARNINGS`, and ONLY up to the standing purse: a city earns back what it lost, so
--     the world's money cannot run away (a rich city earns nothing more; its gains are other houses'
--     money). Coupons (0123) are paid from what a city holds above its reserve, so they are paid from
--     this too.
-- (5) public.city_day(p_now) — (3) and (4), called by public.tick_city as its step 6b (one hunk; an
--     error rolls back the step alone and is reported, the 0122 shape); its receipt joins the hour's.
--     port_treasury.earned_day marks the last game-day counted (set to yesterday here: no back-pay).
-- (6) THE CITY BUILDS FROM WHAT IT EARNED, NOT FROM ITS CAPITAL. tick_city's step 4 subscribed a
--     city's own works from everything above its RESERVE. With a 2,000,000 purse every harbour would
--     buy out all twenty levels (~1.26 M) inside a day — no share left for any house to buy, so a
--     merchant's surplus could never return to a city as shares (0123 §3.4) and influence through
--     shares (0144) would stop. Step 4 now subscribes from what a city holds above
--     greatest(reserve, standing). Two hunks.
-- (7) The Town Hall's "Yesterday" names the new kinds (client: src/features/map/CityTownHall.tsx).
--
-- ── NOT THE OWNER'S — CONFIRM (stated, not hidden) ──────────────────────────────────────────────
-- * The figures of (3)/(4): crown_tax_share 0.10, city_earnings_per_dev 100, city_earnings_per_level
--   0.10 — sized from the 7-day replay in the dev-log, each one knob.
-- * Earnings stop at the standing purse (the brake on inflation), and (6) the self-build gate.
-- * Harbour dues: NOT added. docs/ECONOMY_LOOP.md §11 (owner, 2026-10-15): "no harbour dues".
-- * No new sink: the world's money grows by what (4) mints back into cities that lost it (replay:
--   ~3.3–6.8 M d. a real day against ~700 M after the grant). Prices do not read the world's money.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- ACCESS SHARE / ROW EXCLUSIVE on port_treasury and treasury_flows; one transaction advisory lock per
-- harbour granted (238), held to commit — a sale at a harbour waits for this file's commit. ALTER TABLE
-- port_treasury ADD COLUMN (nullable, no default: catalog only; ACCESS EXCLUSIVE for an instant).
-- CREATE OR REPLACE FUNCTION. The probes run tick_city / city_day inside sub-transactions rolled back
-- (asserted). No LOCK TABLE, no set role, no set local, no begin. Deploy with the clock unwound.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0171, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): public.tick_city (0123/0148),
-- public.city_treasury_switch (0122).
-- ROLLBACK: knobs to 0 (city_earnings_per_dev 0, crown_tax_share 0) stop (3)/(4) at once; a forward
-- slice restores the two bodies (each hunk's OLD text is here verbatim). The GRANT is money: it stays.
-- VERSION: 0172 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0171.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0172(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0172 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('public.tick_city(timestamp with time zone)'),
               ('public.city_treasury_switch(boolean)')) f(fn);

create temp table before_0172 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select coalesce(max(id), 0) from public.treasury_flows) as max_flow,
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('city_standing', 'city_capital', 'city_earnings', 'city_day')) as n_found;

create temp table purse_before_0172 on commit drop as
select p.id as port_id, p.code, public.treasury_balance(p.id) as bal
  from public.ports p where p.kind = 'HARBOUR';

do $$
begin
  if (select count(*) from defs_before_0172 where def is not null) <> 2 then
    raise exception '0172 self-assert FAIL: % of the 2 bodies found', (select count(*) from defs_before_0172 where def is not null);
  end if;
  if (select n_found from before_0172) <> 0 then
    raise exception '0172 self-assert FAIL: a city_standing / city_capital / city_earnings / city_day already exists';
  end if;
end $$;

-- ── 2. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('city_purse_city', to_jsonb(2000000),
   '0172 (owner, 2026-10-17): the standing purse of a city — what it is granted, and what its earnings refill it to.'),
  ('city_purse_capital', to_jsonb(10000000),
   '0172 (owner, 2026-10-17): the standing purse of a country''s capital (nations.capital_port_code).'),
  ('crown_tax_share', to_jsonb(0.10),
   '0172: the share of a city''s tax (each game-day) that goes to its country''s capital (CROWN_TAX). 0 stops it.'),
  ('city_earnings_per_dev', to_jsonb(100),
   '0172: a city earns this × (dev_industry + dev_commerce + dev_military) a game-day (EARNINGS), only up to its standing purse. 0 stops it.'),
  ('city_earnings_per_level', to_jsonb(0.10),
   '0172: each level of a city''s works raises its earnings by this fraction.')
on conflict (key) do nothing;

-- ── 3. THE BOOK MARK ───────────────────────────────────────────────────────────────────────────
alter table public.port_treasury add column if not exists earned_day int;
comment on column public.port_treasury.earned_day is
  '0172: the last game-day whose EARNINGS and CROWN_TAX public.city_day has counted for this city.';
update public.port_treasury set earned_day = world.game_day() - 1 where earned_day is null;

-- ── 4. THE READERS ─────────────────────────────────────────────────────────────────────────────
create or replace function public.city_standing(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0172: THE standing purse of a harbour: a country's capital holds city_purse_capital, every other
  -- harbour city_purse_city. What the grant tops up to, and what EARNINGS refill to.
  select case when exists (select 1 from public.nations n join public.ports p on p.code = n.capital_port_code
                            where p.id = p_port)
              then public.wc_int('city_purse_capital') else public.wc_int('city_purse_city') end::bigint
$$;

create or replace function public.city_capital(p_port uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0172: THE crown of a harbour — the capital harbour of the country that holds it today
  -- (public.port_nation, 0143). Null for a harbour no country holds.
  select cp.id from public.nations n
    join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
   where n.id = public.port_nation(p_port)
$$;

create or replace function public.city_earnings(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0172: THE development income of a city for one game-day: its development (industry + commerce +
  -- military) × city_earnings_per_dev, raised by city_earnings_per_level for every level of its works.
  select coalesce(round(public.wc_num('city_earnings_per_dev')
                        * (coalesce(p.dev_industry, 0) + coalesce(p.dev_commerce, 0) + coalesce(p.dev_military, 0))
                        * (1 + public.wc_num('city_earnings_per_level')
                               * coalesce((select sum(w.level) from public.city_works w where w.port_id = p.id), 0))), 0)::bigint
    from public.ports p where p.id = p_port and p.kind = 'HARBOUR'
$$;

-- ── 5. THE DAY ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.city_day(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0172: called by public.tick_city (step 6b) while the purses are lit. Per harbour, once for every
-- game-day completed since port_treasury.earned_day (at most treasury_days_kept):
--   CROWN_TAX  crown_tax_share of the TAX the city took on those days, to its capital (never more
--              than it holds; a capital pays none to itself);
--   EARNINGS   city_earnings × the days, never past its standing purse.
-- Then, every call, CROWN_AID: a city of a country below its reserve is topped up to it from what the
-- capital holds above ITS reserve. Every movement is public.treasury_post; harbours are locked
-- (public.treasury_lock) before an outflow is judged, the city before its capital.
declare
  v_last   int := world.game_day(p_now) - 1;
  v_keep   int := public.wc_int('treasury_days_kept');
  r        record;
  v_since  int;
  v_n      int;
  v_cap    uuid;
  v_tax    bigint;
  v_s      bigint;
  v_e      bigint;
  v_a      bigint;
  v_cities int := 0;
  v_crown  bigint := 0;
  v_earned bigint := 0;
  v_aided  int := 0;
  v_aid    bigint := 0;
begin
  if not public.city_treasury_on() then
    return jsonb_build_object('enabled', false);
  end if;

  for r in select t.port_id, t.earned_day from public.port_treasury t
             join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
            where coalesce(t.earned_day, v_last - 1) < v_last
            order by p.code
              for update of t skip locked loop
    v_since := greatest(coalesce(r.earned_day, v_last - 1), v_last - v_keep);
    v_n := v_last - v_since;
    -- THE CROWN'S SHARE of the city's tax on those days
    v_cap := public.city_capital(r.port_id);
    if v_cap is not null and v_cap <> r.port_id then
      select coalesce(sum(d.ducats), 0) into v_tax from public.treasury_daybook d
       where d.port_id = r.port_id and d.kind = 'TAX' and d.game_day > v_since and d.game_day <= v_last;
      v_s := round(v_tax * public.wc_num('crown_tax_share'))::bigint;
      if v_s > 0 then
        perform public.treasury_lock(r.port_id);
        v_s := least(v_s, greatest(0, public.treasury_balance(r.port_id)));
        if v_s > 0 then
          perform public.treasury_post(r.port_id, 'CROWN_TAX', -v_s, null, null);
          perform public.treasury_post(v_cap, 'CROWN_TAX', v_s, null, null);
          v_crown := v_crown + v_s;
        end if;
      end if;
    end if;
    -- THE CITY'S EARNINGS, back up to its standing purse and no further
    v_e := least(public.city_earnings(r.port_id) * v_n,
                 greatest(0, public.city_standing(r.port_id) - public.treasury_balance(r.port_id)));
    if v_e > 0 then
      perform public.treasury_post(r.port_id, 'EARNINGS', v_e, null, null);
      v_earned := v_earned + v_e;
    end if;
    update public.port_treasury set earned_day = v_last where port_id = r.port_id;
    v_cities := v_cities + 1;
  end loop;

  -- THE CROWN'S AID: a city under its reserve, from what its capital holds above its own
  for r in select t.port_id, t.reserve, public.city_capital(t.port_id) as cap
             from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
            where t.reserve > 0 and public.treasury_balance(t.port_id) < t.reserve
            order by p.code loop
    continue when r.cap is null or r.cap = r.port_id;
    perform public.treasury_lock(r.port_id);
    perform public.treasury_lock(r.cap);
    v_a := least(r.reserve - public.treasury_balance(r.port_id), greatest(0, public.city_surplus(r.cap)));
    if v_a > 0 then
      perform public.treasury_post(r.cap, 'CROWN_AID', -v_a, null, null);
      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;

  return jsonb_build_object('cities', v_cities, 'crown_tax', v_crown, 'earnings', v_earned,
                            'aided', v_aided, 'aid', v_aid);
end $$;
comment on function public.city_day(timestamptz) is
  '0172: the crown''s share of a city''s tax, its development earnings (up to its standing purse) and the '
  'crown''s aid to a city under its reserve. Called by public.tick_city. Server-only.';

revoke all on function public.city_standing(uuid)    from public, anon, authenticated;
revoke all on function public.city_capital(uuid)     from public, anon, authenticated;
revoke all on function public.city_earnings(uuid)    from public, anon, authenticated;
revoke all on function public.city_day(timestamptz)  from public, anon, authenticated;

-- ── 6. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0172 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0172 values
('public.tick_city(timestamp with time zone)', 1,
$h$  v_world   bigint;
begin$h$,
$h$  v_world   bigint;
  v_day     jsonb := '{}'::jsonb;   -- 0172: the day's crown share, earnings and aid
begin$h$),
('public.tick_city(timestamp with time zone)', 2,
$h$        continue when floor(greatest(0, wb.rolled - wb.reserve) / v_price) < 1;$h$,
$h$        -- 0172: a city builds from what it holds above its standing purse, never from its capital.
        continue when floor(greatest(0, wb.rolled - greatest(wb.reserve, public.city_standing(wb.port_id))) / v_price) < 1;$h$),
('public.tick_city(timestamp with time zone)', 3,
$h$                     floor(greatest(0, least(wb.rolled, public.treasury_balance(wb.port_id)) - wb.reserve) / v_price))::int;$h$,
$h$                     floor(greatest(0, least(wb.rolled, public.treasury_balance(wb.port_id))
                                       - greatest(wb.reserve, public.city_standing(wb.port_id))) / v_price))::int;   -- 0172$h$),
('public.tick_city(timestamp with time zone)', 4,
$h$  -- 7. ASSERT: every purse equals its books; none below zero (the CHECK holds it too).$h$,
$h$  -- 6b. THE DAY (0172, lit): the crown's share of the day's tax, the city's earnings back up to its
  --     standing purse, the crown's aid to a city of its country under its reserve (public.city_day).
  v_t := clock_timestamp();
  if v_lit then
    begin
      v_day := public.city_day(p_now);
    exception when others then
      v_err := v_err || jsonb_build_object('day', sqlerrm);
    end;
  end if;
  v_ms := v_ms || jsonb_build_object('day', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 7. ASSERT: every purse equals its books; none below zero (the CHECK holds it too).$h$),
('public.tick_city(timestamp with time zone)', 5,
$h$                            'inns', v_inns, 'coupons_paid', v_paid, 'coupons_skipped', v_skipped,$h$,
$h$                            'inns', v_inns, 'coupons_paid', v_paid, 'coupons_skipped', v_skipped,
                            'day', v_day,   -- 0172$h$),
('public.city_treasury_switch(boolean)', 1,
$h$                    greatest(public.wc_int('city_seed_min'),$h$,
$h$                    greatest(public.city_standing(p.id), public.wc_int('city_seed_min'),   -- 0172: its standing purse$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_n   int;
begin
  for d in select * from defs_before_0172 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0172 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0172(v_def, h.old);
      if v_n <> 1 then
        raise exception '0172 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
          h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 7. THE GRANT (lit only; dark, the switch's seed carries the standing purse) ─────────────────
create temp table grant_0172 (port_id uuid primary key, gap bigint not null) on commit drop;

do $$
declare
  r     record;
  v_gap bigint;
begin
  if not public.city_treasury_on() then
    raise notice '0172: the city purses are dark here — no GRANT is posted; public.city_treasury_switch(true) seeds each harbour with its standing purse.';
    return;
  end if;
  for r in select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code loop
    perform public.treasury_lock(r.id);
    v_gap := public.city_standing(r.id) - public.treasury_balance(r.id);
    if v_gap > 0 then
      perform public.treasury_post(r.id, 'GRANT', v_gap, null, null);
      insert into grant_0172 values (r.id, v_gap);
    end if;
  end loop;
  insert into public.world_config (key, value, description)
  values ('city_grant_0172',
          jsonb_build_object('at', now(), 'cities', (select count(*) from grant_0172),
                             'ducats', (select coalesce(sum(gap), 0) from grant_0172)),
          '0172 (owner, 2026-10-17 "cities ... should have some millions of gold as a start. Especially capitals"): '
          'the one-time GRANT that topped every harbour up to its standing purse (public.city_standing).')
  on conflict (key) do nothing;
end $$;

-- ── 8. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
create temp table proven_0172 (k text primary key, v text) on commit drop;

-- (a) the grant, the standing purses and the bid they buy
do $$
declare
  v_caps   int;
  v_n      int;
  v_lit    boolean := public.city_treasury_on();
begin
  select count(*) into v_caps from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR';
  if (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.city_standing(p.id) = 10000000) <> v_caps
     or (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.city_standing(p.id) = 2000000)
        <> (select count(*) from public.ports p where p.kind = 'HARBOUR') - v_caps then
    raise exception '0172 self-assert FAIL: the standing purses are not 10,000,000 for the % capitals and 2,000,000 for every other harbour', v_caps;
  end if;
  -- the reserve never reaches the standing purse, so a capitalised city bids 1
  select count(*) into v_n from public.port_treasury t where t.reserve > public.city_standing(t.port_id);
  if v_n > 0 then
    raise exception '0172 self-assert FAIL: % harbour(s) keep a reserve above their standing purse — capitalised, they would still bid under 1', v_n;
  end if;
  if v_lit then
    -- every GRANT this file posted is one of its own, equal to the gap it found; no harbour lost a ducat
    if (select count(*) from public.treasury_flows f where f.id > (select max_flow from before_0172) and f.kind = 'GRANT')
         <> (select count(*) from grant_0172)
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > (select max_flow from before_0172) and f.kind = 'GRANT')
         <> (select coalesce(sum(gap), 0) from grant_0172) then
      raise exception '0172 self-assert FAIL: the GRANT flows are not exactly the gaps this file found';
    end if;
    select count(*) into v_n from purse_before_0172 b
     where public.treasury_balance(b.port_id) < greatest(b.bal, public.city_standing(b.port_id));
    if v_n > 0 then
      raise exception '0172 self-assert FAIL: % harbour(s) are under their standing purse or below what they held', v_n;
    end if;
    insert into proven_0172 values ('grant', format('%s harbours granted %s d. (London %s → %s)',
      (select count(*) from grant_0172), (select coalesce(sum(gap), 0) from grant_0172),
      (select b.bal from purse_before_0172 b where b.code = 'LON'),
      (select public.treasury_balance(b.port_id) from purse_before_0172 b where b.code = 'LON')));
  else
    if exists (select 1 from public.treasury_flows f where f.id > (select max_flow from before_0172) and f.kind = 'GRANT') then
      raise exception '0172 self-assert FAIL: dark, this file posted a GRANT';
    end if;
    insert into proven_0172 values ('grant', 'dark: none posted; the switch seeds the standing purse');
  end if;
end $$;

-- (b) THE DAY, on a city of this file's own choosing (rolled back): its crown share, its earnings, the
--     crown's aid, and that a second call the same day posts nothing.
do $$
declare
  x        record;
  v_lit    boolean := public.city_treasury_on();
  v_last   int := world.game_day() - 1;
  v_mark   bigint;
  v_balx   bigint;
  v_tax    bigint;
  v_s      bigint;
  v_e      bigint;
  v_a      bigint;
  v_got    jsonb;
  v_again  int;
  v_msg    text;
begin
  -- a harbour held by a country that has a capital, not the capital itself, and some harbour else
  select p.id, p.code, public.city_capital(p.id) as cap into x
    from public.ports p
   where p.kind = 'HARBOUR' and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id
   order by md5(p.code || '0172') limit 1;
  if x.id is null then
    raise exception '0172 self-assert FAIL: no harbour with a crown to probe';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.port_treasury set earned_day = v_last;                       -- only the probe city is due
    update public.port_treasury set earned_day = v_last - 2, reserve = 50000 where port_id = x.id;
    update public.port_treasury set reserve = 0 where port_id <> x.id;         -- only the probe city is aided
    -- the probe city holds 10,000 and took 10,000 of tax yesterday; its capital holds 5 M above its reserve
    perform public.treasury_lock(x.id);
    perform public.treasury_lock(x.cap);
    v_balx := public.treasury_balance(x.id);
    perform public.treasury_post(x.id, 'PROBE_0172', 10000 - v_balx, null, null);
    perform public.treasury_post(x.cap, 'PROBE_0172', 5000000, null, null);
    insert into public.treasury_daybook (port_id, game_day, kind, ducats) values (x.id, v_last, 'TAX', 10000)
    on conflict (port_id, game_day, kind) do update set ducats = public.treasury_daybook.ducats + 10000;
    select coalesce(sum(d.ducats), 0) into v_tax from public.treasury_daybook d
     where d.port_id = x.id and d.kind = 'TAX' and d.game_day > v_last - 2 and d.game_day <= v_last;
    v_s := least(round(v_tax * public.wc_num('crown_tax_share'))::bigint, 10000);
    v_e := least(public.city_earnings(x.id) * 2, public.city_standing(x.id) - (10000 - v_s));
    v_a := 50000 - (10000 - v_s + v_e);
    select coalesce(max(id), 0) into v_mark from public.treasury_flows;

    v_got := public.city_day(now());

    if (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'CROWN_TAX') <> -v_s
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.cap and f.kind = 'CROWN_TAX') <> v_s
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'EARNINGS') <> v_e
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'CROWN_AID') <> greatest(v_a, 0)
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.cap and f.kind = 'CROWN_AID') <> -greatest(v_a, 0)
       or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id not in (x.id, x.cap)
                    and f.kind in ('CROWN_TAX', 'CROWN_AID', 'EARNINGS'))
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind in ('CROWN_TAX', 'CROWN_AID')) <> 0
       or (select earned_day from public.port_treasury where port_id = x.id) <> v_last
       or v_s <= 0 or v_e <= 0 or v_a <= 0 then
      raise exception '0172 self-assert FAIL: city_day on % paid %, not crown % / earnings % / aid % (flows %)', x.code, v_got, v_s, v_e, v_a,
        (select jsonb_agg(jsonb_build_array(f.port_id = x.id, f.kind, f.ducats) order by f.id) from public.treasury_flows f where f.id > v_mark);
    end if;
    -- the same day again: nothing more is due, and the city stands at its reserve
    select coalesce(max(id), 0) into v_mark from public.treasury_flows;
    perform public.city_day(now());
    select count(*) into v_again from public.treasury_flows f where f.id > v_mark and f.kind in ('CROWN_TAX', 'CROWN_AID', 'EARNINGS');
    if v_again <> 0 then
      raise exception '0172 self-assert FAIL: a second city_day the same game-day posted % flow(s)', v_again;
    end if;
    -- a city at its standing purse earns nothing (the crown's share held at 0 so it stays there)
    update public.world_config set value = to_jsonb(0) where key = 'crown_tax_share';
    perform public.treasury_post(x.id, 'PROBE_0172', public.city_standing(x.id) - public.treasury_balance(x.id), null, null);
    update public.port_treasury set earned_day = v_last - 1 where port_id = x.id;
    select coalesce(max(id), 0) into v_mark from public.treasury_flows;
    perform public.city_day(now());
    if exists (select 1 from public.treasury_flows f where f.id > v_mark and f.kind = 'EARNINGS') then
      raise exception '0172 self-assert FAIL: a city at its standing purse was paid EARNINGS';
    end if;
    raise exception using errcode = 'P0172', message = format('%s: crown %s, earnings %s, aid %s; again 0; at standing 0', x.code, v_s, v_e, v_a);
  exception when sqlstate 'P0172' then
    v_msg := sqlerrm;
  end;
  if public.city_treasury_on() is distinct from v_lit
     or exists (select 1 from public.treasury_flows f where f.kind = 'PROBE_0172') then
    raise exception '0172 self-assert FAIL: the day probe did not roll back';
  end if;
  insert into proven_0172 values ('day', v_msg);
end $$;

-- (c) THE CITY BUILDS FROM WHAT IT EARNED (rolled back): the whole hour run lit, two cities of this
--     file's own — one at reserve + 50 shares but under its standing purse subscribes NOTHING (the
--     old rule bought 50), one at standing + 50 shares subscribes exactly what the rule says; and no
--     city subscribed beyond what it held above its standing purse.
do $$
declare
  a        record;
  b        record;
  v_pa     bigint;
  v_pb     bigint;
  v_rec    jsonb;
  v_suba   int;
  v_subb   int;
  v_bad    int;
  v_msg    text;
  v_t      timestamptz;
  v_days   jsonb := public.wc('treasury_reserve_days');
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    insert into public.city_works (port_id, kind)
    select p.id, k.kind from public.ports p cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind)
     where p.kind = 'HARBOUR' on conflict (port_id, kind) do nothing;
    -- two harbours whose lowest work has room for 50 more shares
    create temp table low_0172 on commit drop as
    select distinct on (w.port_id) w.port_id, w.kind, w.level, w.subscribed
      from public.city_works w join public.ports p on p.id = w.port_id and p.kind = 'HARBOUR'
     where w.level < public.wc_int('works_level_max')
     order by w.port_id, w.level, array_position(array['docks', 'market', 'production', 'inn'], w.kind);
    select l.*, p.code into a from low_0172 l join public.ports p on p.id = l.port_id
     where l.subscribed <= 40 order by md5(p.code || 'a0172') limit 1;
    select l.*, p.code into b from low_0172 l join public.ports p on p.id = l.port_id
     where l.subscribed <= 40 and l.port_id <> a.port_id order by md5(p.code || 'b0172') limit 1;
    v_pa := public.works_share_price(a.level);
    v_pb := public.works_share_price(b.level);
    -- the reserve is 0 for both, so only the standing purse can stop A
    update public.port_treasury set reserve = 0 where port_id in (a.port_id, b.port_id);
    perform public.treasury_post(a.port_id, 'PROBE_0172', 50 * v_pa + 1 - public.treasury_balance(a.port_id), null, null);
    perform public.treasury_post(b.port_id, 'PROBE_0172',
      public.city_standing(b.port_id) + 50 * v_pb + 1 - public.treasury_balance(b.port_id), null, null);
    -- the reserve the hour sets would be 3 × the SELL day; hold both at 0 through the hour's STATE step
    update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_days';
    create temp table works_before_0172 on commit drop as
    select w.port_id, w.kind, w.level, w.subscribed from public.city_works w;

    v_t := clock_timestamp();
    v_rec := public.tick_city(now());
    raise notice '0172 timing (reported, not gated): one lit tick_city with the day step: % ms (day %)',
      round(extract(epoch from clock_timestamp() - v_t) * 1000), v_rec -> 'ms' -> 'day';

    if v_rec -> 'errors' <> '{}'::jsonb then
      raise exception '0172 self-assert FAIL: the hour reported errors %', v_rec -> 'errors';
    end if;
    select (w.level - x.level) * 100 + w.subscribed - x.subscribed into v_suba
      from public.city_works w join works_before_0172 x using (port_id, kind) where w.port_id = a.port_id and w.kind = a.kind;
    select (w.level - x.level) * 100 + w.subscribed - x.subscribed into v_subb
      from public.city_works w join works_before_0172 x using (port_id, kind) where w.port_id = b.port_id and w.kind = b.kind;
    if v_suba <> 0 then
      raise exception '0172 self-assert FAIL: % at reserve + 50 shares, under its standing purse, subscribed % of its own shares', a.code, v_suba;
    end if;
    if v_subb <> least(100 - b.subscribed, 50) then
      raise exception '0172 self-assert FAIL: % at standing + 50 shares subscribed %, not %', b.code, v_subb, least(100 - b.subscribed, 50);
    end if;
    -- no city bought more of itself than it held above its standing purse at the roll
    select count(*) into v_bad
      from public.city_works w join works_before_0172 x using (port_id, kind)
      join public.port_treasury t on t.port_id = w.port_id
     where (w.level - x.level) * 100 + w.subscribed - x.subscribed > 0
       and ((w.level - x.level) * 100 + w.subscribed - x.subscribed) * public.works_share_price(x.level)
           > t.ducats - public.city_standing(w.port_id);
    if v_bad > 0 then
      raise exception '0172 self-assert FAIL: % work(s) were subscribed from a city''s standing purse', v_bad;
    end if;
    if v_rec -> 'day' is null or jsonb_typeof(v_rec -> 'day') <> 'object' then
      raise exception '0172 self-assert FAIL: the hour''s receipt carries no day step: %', v_rec;
    end if;
    raise exception using errcode = 'P0172', message = format('%s under standing: 0 shares (old rule 50); %s above: %s; hour day step %s',
      a.code, b.code, v_subb, v_rec -> 'day');
  exception when sqlstate 'P0172' then
    v_msg := sqlerrm;
  end;
  if exists (select 1 from public.treasury_flows f where f.kind = 'PROBE_0172')
     or public.wc('treasury_reserve_days') is distinct from v_days then
    raise exception '0172 self-assert FAIL: the build probe did not roll back';
  end if;
  insert into proven_0172 values ('build', v_msg);
end $$;

-- (d) the bodies, the doors, the receipt
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  q      record;
begin
  for d in select * from defs_before_0172 order by fn loop
    v_def  := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0172 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0172(v_back, h.new) <> 1 then
        raise exception '0172 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def then
      raise exception '0172 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, pr.proowner as owner,
           coalesce(pr.proconfig::text, '') as cfg
      into q from pg_proc pr where pr.oid = d.fn::regprocedure;
    if q.acl <> d.acl or q.vol <> d.vol or q.secdef <> d.secdef or q.cfg <> d.cfg or q.owner <> d.owner then
      raise exception '0172 self-assert FAIL: % changed its ACL, owner, volatility, definer or config', d.fn;
    end if;
  end loop;
  if v_rev <> 2 then
    raise exception '0172 self-assert FAIL: % bodies checked, not 2', v_rev;
  end if;
  for q in select pr.oid::regprocedure::text as sig, coalesce(pr.proacl::text, '') as acl
             from pg_proc pr where pr.pronamespace = 'public'::regnamespace
              and pr.proname in ('city_standing', 'city_capital', 'city_earnings', 'city_day') loop
    if q.acl ~ '(^|[{,])=X' or q.acl ~ 'anon=' or q.acl ~ 'authenticated=' then
      raise exception '0172 self-assert FAIL: % is not server-only (acl %)', q.sig, q.acl;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0172)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0172 self-assert FAIL: the client doors moved (entry points % → %, write grants %, executable writers %)',
      (select entry_points from before_0172), (select count(*) from public.client_rpc_entry_points()),
      (select count(*) from public.client_write_grants()), (select count(*) from public.client_executable_writers());
  end if;

  raise notice '0172 self-assert ok: A CITY IS RICH, AND ITS MONEY COMES BACK. STANDING PURSES: 10,000,000 for % capitals, 2,000,000 for every other harbour; no reserve reaches one, so a capitalised city bids 1. GRANT: %. THE DAY (rolled back): %. THE BUILD (rolled back): %. BODIES: tick_city and city_treasury_switch reverse to their pre-images hunk by hunk, ACL / owner / volatility / definer / config unmoved; city_standing, city_capital, city_earnings and city_day are server-only; no client door moved.',
    (select count(*) from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'),
    (select v from proven_0172 where k = 'grant'), (select v from proven_0172 where k = 'day'),
    (select v from proven_0172 where k = 'build');
end $$;
