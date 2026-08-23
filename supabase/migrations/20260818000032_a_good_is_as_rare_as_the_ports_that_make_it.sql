-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0032 — a good is as rare as the ports that make it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-08-23: "i want you to categorize trade goods, common, uncommon, rare, and so
-- on. and make appropirate color or sign so that it is unique."
--
-- WHAT THIS ESTABLISHES. Every trade good now has a RARITY — one of exactly four tiers: common,
-- uncommon, rare, exotic — served on the wire beside its name and category, so the compendium,
-- the pickers and the market can all say it without any of them deciding it.
--
-- ── DERIVED, NOT AUTHORED — AND FROM SCARCITY, NOT PRICE ─────────────────────────────────────
-- Rarity is DERIVED from one fact the world already authors: HOW MANY PORTS PRODUCE THE GOOD
-- (`public.port_specialties`, the same single editorial fact 0005 derives fifteen thousand
-- prices from). Two alternatives were considered and both are worse:
--
--   * An authored per-good column would be a SECOND opinion running parallel to
--     port_specialties: nothing would stop a good authored "rare" being produced by thirty
--     ports, and every world growth (12 ports -> 214 already happened once) would silently
--     falsify the hand-set labels. The authored fact is who-produces-what; rarity restates it.
--   * Deriving from PRICE (`goods.base_value` / valueBand) would make the tier redundant with
--     the price column beside it — and wrong as a rarity: in this world every port trades every
--     good, so a good that is merely expensive is not rare. What is scarce is a cheap SOURCE.
--     Gold has 22 producing ports in this world; it is dear, and it is common. Murano-style
--     glassware has ONE; it is mid-priced, and finding its port is an event. The tier answers
--     "how hard is a source to find", which is the question price cannot answer.
--
-- ── THE LAW, in one immutable function ───────────────────────────────────────────────────────
--   producers <= 2   -> 'exotic'    a monopoly or a duopoly; the world makes it in 1-2 harbours
--   producers <= 5   -> 'rare'      a handful of sources; one region holds it
--   producers <= 12  -> 'uncommon'  a sea or two
--   otherwise        -> 'common'    you are never far from a source
--
-- Measured on the seeded world (214 ports, 70 goods, 834 specialty rows) this tiers the goods
-- 6 exotic / 20 rare / 22 uncommon / 22 common — a thin apex over three broad bands, so the top
-- tier stays special and no tier swallows the list. The self-assert below requires the SHAPE
-- (every good tiered, all four tiers inhabited, no tier holding more than 60% of the catalogue)
-- rather than those exact counts, because the counts are the world's and the shape is the rule's
-- (docs/NO_SPAGHETTI.md §6: derive it, or find it — never pin the seed).
--
-- ── SUPERSEDES ───────────────────────────────────────────────────────────────────────────────
--   * world.snapshot()  — 0028:256 (`20260818000028_a_fair_happens_because_the_game_is_played.
--     sql`). The goods catalogue gains ONE field, `rarity`. Everything else is byte-identical:
--     the body below was extracted from 0028 by script, not retyped, and the self-assert proves
--     the no-op by capturing the OLD payload before the replace and requiring the new one,
--     stripped of `rarity`, to equal it exactly.
--   * world.market(uuid) — 0029:132 (`20260818000029_the_market_says_when_it_next_moves.sql`).
--     Each priced row gains the same field from the same authority — one rule, two callers,
--     which is composition, not duplication (docs/NO_SPAGHETTI.md §1: ten screens calling one
--     function is the function working). Same extraction, same parity proof.
--
-- WHY THE FIELD RIDES ON BOTH READS: the compendium reads the catalogue (snapshot.goods); the
-- good picker on COMMAND reads market rows. If only the catalogue carried it, every consumer of
-- a market row would grow its own code->catalogue join to reach one word — N little joins for
-- one fact. Both payloads say it; ONE function decides it; no client ever sees the thresholds.
--
-- ── WHAT THIS DELIBERATELY DOES NOT TOUCH ────────────────────────────────────────────────────
-- Prices. Rarity is a READING of the world, not a knob in it: `world.mid_price` (0005) is not a
-- caller of this function and must not become one — scarcity already reaches the price through
-- the affinity gradient 0005 derives from the very same port_specialties rows. Wiring rarity
-- into pricing would make one authored fact push prices twice through two doors.
-- The client helpers stay unexecutable to client roles: the tier is served as a FIELD; the
-- formula never crosses the wire.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE LAW — thresholds live here and nowhere else ─────────────────────────────────────────
create or replace function public.rarity_from_producers(p_producers int)
returns text
language sql
immutable
as $$
  select case
    when p_producers <= 2  then 'exotic'
    when p_producers <= 5  then 'rare'
    when p_producers <= 12 then 'uncommon'
    else 'common'
  end
$$;

comment on function public.rarity_from_producers(int) is
  'THE RARITY LAW (0032): producer count -> tier. <=2 exotic, <=5 rare, <=12 uncommon, else '
  'common. The one place the thresholds exist. Change a threshold in a superseding migration and '
  'every serving of rarity moves with it.';

-- ── 2. THE ONE AUTHORITY a payload asks ────────────────────────────────────────────────────────
create or replace function public.good_rarity(p_good uuid)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select public.rarity_from_producers(
    (select count(*)::int from public.port_specialties ps where ps.good_id = p_good))
$$;

comment on function public.good_rarity(uuid) is
  'How rare a good is (0032): the count of ports that produce it (port_specialties — the same '
  'authored fact 0005 prices from) put through public.rarity_from_producers. Served as the '
  '`rarity` field on snapshot.goods[] and market.goods[]; clients read the word, never the rule.';

-- Server-only, like every helper that is not itself an entry point: the tier reaches a client as
-- a served field, and the formula does not cross the wire.
revoke all on function public.rarity_from_producers(int) from public, anon, authenticated;
revoke all on function public.good_rarity(uuid) from public, anon, authenticated;

-- ── 3. THE OLD PAYLOADS, captured before the replace — the no-op proof reads these ─────────────
-- The subject port is deterministic: first port by code, never heap order (NO_SPAGHETTI §4).
-- Within this transaction now() is frozen, so the drift slot cannot roll between the capture and
-- the re-read below, and market parity is exact, not probabilistic.
create temporary table payload_before_0032 as
select world.snapshot() as snap,
       world.market((select id from public.ports order by code limit 1)) as market;

-- ── 4. SUPERSEDE 0028:256 — the goods catalogue says how rare each good is ─────────────────────
create or replace function world.snapshot()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    -- 0028 WIND: THE NATIONS, as a catalogue — the shape ports, goods and ship classes are already
    -- 0028 WIND: served in. Every payload in this game that mentions a nation says its CODE and
    -- 0028 WIND: only its code: snapshot.ports[].nation (0009:78) and world.standings().board[]
    -- 0028 WIND: .nation (0025:326). Nothing on the wire could turn one into a name, so a screen
    -- 0028 WIND: could only print "PRT" or grow its own code -> name table — which is exactly the
    -- 0028 WIND: second authority src/live/worldStore.ts:192-208 records having deleted once
    -- 0028 WIND: already, for ports, after it had been hand-written seven times. ONE catalogue,
    -- 0028 WIND: cached with the static world, resolves every nation code the game ever serves.
    'nations', (select coalesce(jsonb_agg(jsonb_build_object(                          -- 0028 WIND
        'id', n.id, 'code', n.code, 'name', n.name, 'flag_char', n.flag_char,          -- 0028 WIND
        'capital', n.capital_port_code) order by n.code), '[]'::jsonb)                 -- 0028 WIND
      from public.nations n),                                                          -- 0028 WIND
    'ports', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'name', p.name, 'country', p.country,
        'nation', n.code, 'lat', p.lat, 'lon', p.lon, 'sea', s.name, 'region', r.code,
        'culture', p.culture, 'size_tier', p.size_tier, 'max_draft', p.max_draft,
        'has_yard', p.has_yard, 'yard_tier', p.yard_tier, 'has_academy', p.has_academy,
        'is_ice_closed', p.is_ice_closed, 'tax_rate', p.tax_rate, 'crew_pool', p.crew_pool,
        'dev_industry', p.dev_industry, 'dev_commerce', p.dev_commerce, 'dev_military', p.dev_military)
        order by p.code), '[]'::jsonb)
      from public.ports p
      left join public.nations n on n.id = p.nation_id
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id),
    'legs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'from', a.code, 'to', b.code, 'nm', l.distance_nm,
        'hazard_mult', l.hazard_mult, 'notes', l.notes) order by a.code, b.code), '[]'::jsonb)
      from public.legs l join public.ports a on a.id = l.from_port_id
                         join public.ports b on b.id = l.to_port_id),
    'goods', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'code', g.code, 'name', g.name, 'base_value', g.base_value,
        'bulk', g.bulk, 'category', g.category, 'perishable_pct_day', g.perishable_pct_day,
        -- 0032 RARITY: the one served reading of how rare this good is. Derived by the ONE
        -- 0032 RARITY: authority public.good_rarity (this file, above) — never by a client.
        'rarity', public.good_rarity(g.id),
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),
    'ship_classes', (select coalesce(jsonb_agg(to_jsonb(c) order by c.tier), '[]'::jsonb)
      from public.ship_classes c),
    -- The knobs the CLIENT legitimately needs, named one by one. Serving world_config wholesale
    -- would ship the hazard seed to every browser; an allow-list is the only safe shape.
    'config', jsonb_build_object(
        -- 0028 WIND: THE CALENDAR CLOCK (0005:44), beside the voyage clock it does NOT run at. Both
        -- 0028 WIND: are DESIGN D.1's, both are counted in "days", and until this line only one of
        -- 0028 WIND: them crossed the wire — so a client served a figure in game-days could print it
        -- 0028 WIND: on the wrong clock or not at all, and 0026's catalogue chose not at all.
        'game_day_seconds',  public.wc_num('game_day_seconds'),  -- 0028 WIND
        'time_compression',  public.wc_int('time_compression'),
        'order_queue_max',   public.wc_int('order_queue_max'),
        'fleet_max',         public.wc_int('fleet_max'),
        'ship_max',          public.wc_int('ship_max'),
        'endurance_margin',  public.wc_num('endurance_margin'),
        'trade_step_tuns',   public.wc_int('trade_step_tuns'),
        'water_per_crew_day', public.wc_num('water_per_crew_day'),
        'food_per_crew_day',  public.wc_num('food_per_crew_day'),
        'wage_per_crew_day',  public.wc_num('wage_per_crew_day'),
        -- 0019: the three numbers MARKET used to declare for itself.
        'neighbour_radius_nm', public.wc_num('neighbour_radius_nm'),
        'advice_buy_below',    public.wc_num('advice_buy_below'),
        'advice_sell_above',   public.wc_num('advice_sell_above')),
    'verbs', cmd.verb_schema())
$$;

revoke all on function world.snapshot() from public, anon;
grant execute on function world.snapshot() to authenticated;

-- ── 5. SUPERSEDE 0029:132 — each priced market row says it too, from the same authority ────────
create or replace function world.market(p_port uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
begin
  -- 0029 WIND: the read is the catch-up (0009), applied to the market's own clock. On any
  -- 0029 WIND: deployment without pg_cron this is the ONLY thing that steps the drift, and it is
  -- 0029 WIND: what makes the served next_change_at a promise with a mechanism: the re-ask the
  -- 0029 WIND: countdown triggers at zero is itself the call that moves the prices. ONE writer
  -- 0029 WIND: still owns the step (public.tick_market_drift, 0010); this is a caller of it,
  -- 0029 WIND: idempotent by the slot key, so every call after the first in a slot moves nothing.
  -- 0029 WIND: DO NOT make it conditional, and DO NOT add tick_price_snapshot beside it — the
  -- 0029 WIND: snapshot costs seconds per call (measured, header) and the record is cron's.
  perform public.tick_market_drift(v_now);

  return (
  -- MATERIALIZED, and that word is load-bearing. `cross join lateral (select
  -- world.pct_of_neighbours(...))` reads as one call per good and is NOT: the planner pulls the
  -- sublink up and substitutes the expression at every reference, so four references cost four
  -- neighbourhood walks — which is precisely what 0009 was doing by hand. Measured on this chain:
  -- 1,303 ms with the lateral, 245 ms with this CTE. A fence is the only thing that makes "once"
  -- mean once. (0019's words, kept with 0019's body.)
  with nbr as materialized (
    select pg.good_id, world.pct_of_neighbours(p_port, pg.good_id) as pct
      from public.port_goods pg
     where pg.port_id = p_port
  ),
  band as materialized (
    select public.wc_num('advice_buy_below') as lo, public.wc_num('advice_sell_above') as hi
  )
  select jsonb_build_object(
    'port', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                       'tax_rate', p.tax_rate, 'spread', world.spread(p.id),
                                       'culture', p.culture, 'dev_commerce', p.dev_commerce)
               from public.ports p where p.id = p_port),
    'goods', (select coalesce(jsonb_agg(jsonb_build_object(
        'good_id', g.id, 'code', g.code, 'name', g.name, 'category', g.category,
        -- 0032 RARITY: same field, same authority as snapshot.goods[] — one rule, two callers.
        'rarity', public.good_rarity(g.id),
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,
        'pct_nbr', n.pct,
        'stock', pg.stock, 'stock_target', pg.stock_target,
        'stock_band', round(least(1.0, pg.stock / pg.stock_target) * 6),
        -- DESIGN B.4: culture gates what a port will trade at all. UNAVAILABLE is a fact about the
        -- port, not a price, so it is a flag beside the price rather than a price of zero.
        'available', not (pr.culture = any(g.culture_mask)),
        -- The BAND of the price index, not a recommendation to trade.
        'advice', case when n.pct is null then 'hold'
                       when n.pct < b.lo then 'buy'
                       when n.pct > b.hi then 'sell'
                       else 'hold' end)
        order by g.code), '[]'::jsonb)
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports pr on pr.id = pg.port_id
      join nbr n on n.good_id = pg.good_id
     cross join band b
     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port),
    -- 0029 CLOCK: the prices' own clock, beside the prices. `now` is this payload's read instant;
    -- 0029 CLOCK: `next_change_at` is the instant the drift walk next steps, from the named
    -- 0029 CLOCK: authority. A client counts down by SUBTRACTION against these two instants and
    -- 0029 CLOCK: RE-ASKS at zero — it never multiplies a cadence knob back into a boundary.
    'clock', jsonb_build_object(
        'now', v_now,
        'next_change_at', public.next_drift_change_at(v_now))));
end $$;

revoke all on function world.market(uuid) from public, anon;
grant execute on function world.market(uuid) to authenticated;

comment on function world.snapshot() is
  'The static world in one read (0009, +trade routes context 0019, +nations and the calendar '
  'clock 0028, +rarity on each good 0032). Serves an explicit allow-list of config knobs, never '
  'world_config wholesale.';

comment on function world.market(uuid) is
  'One quay''s prices (0019), their CLOCK (0029: winds public.tick_market_drift before pricing — '
  'the read is the catch-up — and serves clock.now / clock.next_change_at), and since 0032 each '
  'row''s rarity from public.good_rarity — the same field snapshot.goods[] carries.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_goods      int;
  v_port       uuid;
  v_snap       jsonb;
  v_market     jsonb;
  v_snap_txt   text;
  v_stripped   jsonb;
  v_wire       text;
  v_bad        int;
  v_n          int;
  v_exotic     int;
  v_rare       int;
  v_uncommon   int;
  v_common     int;
  v_min_good   uuid;
  v_min_code   text;
  v_max_good   uuid;
  v_max_code   text;
  v_secret     text := public.wc_text('world_secret');
  v_grants     int;
  v_writers    int;
  v_pin        record;
begin
  -- (a) THE LAW ITSELF, pinned at its boundaries. These eight pins are a deliberate inventory of
  --     the thresholds this file states in its header (NO_SPAGHETTI §6 case 2): each boundary is
  --     probed from both sides, so a stuck constant or an off-by-one edit cannot pass. Moving a
  --     threshold is a superseding migration moving these pins with it, on purpose.
  for v_pin in
    select * from (values (0, 'exotic'), (1, 'exotic'), (2, 'exotic'),
                          (3, 'rare'), (5, 'rare'),
                          (6, 'uncommon'), (12, 'uncommon'),
                          (13, 'common'), (200, 'common')) as t(n, tier)
  loop
    if public.rarity_from_producers(v_pin.n) <> v_pin.tier then
      raise exception '0032 self-assert FAIL: rarity_from_producers(%) said %, the law says %',
        v_pin.n, public.rarity_from_producers(v_pin.n), v_pin.tier;
    end if;
  end loop;

  -- (b) NON-VACUOUS: there is a catalogue to tier. Every assert below quantifies over goods, so
  --     an empty goods table would green them all while proving nothing.
  select count(*) into v_goods from public.goods;
  if v_goods = 0 then
    raise exception '0032 self-assert FAIL: public.goods is empty — nothing below can prove anything';
  end if;

  -- (c) EVERY GOOD HAS EXACTLY ONE TIER, AND IT IS ONE OF THE FOUR. good_rarity is a function of
  --     the good, so "exactly one" is structural; what can fail is totality and range.
  select count(*) into v_bad
    from public.goods g
   where public.good_rarity(g.id) not in ('common', 'uncommon', 'rare', 'exotic');
  if v_bad <> 0 then
    raise exception '0032 self-assert FAIL: % good(s) tier outside the four named tiers', v_bad;
  end if;

  -- (d) THE DISTRIBUTION CARRIES INFORMATION. All four tiers inhabited — a tier nothing falls
  --     into is a tier that does not exist — and no tier holds more than 60%% of the catalogue,
  --     because "60 of 70 are common" is a label, not a categorisation. The exact counts are the
  --     world's and are REPORTED, not pinned: grow the world and these move as they should.
  select count(*) filter (where r = 'exotic'),
         count(*) filter (where r = 'rare'),
         count(*) filter (where r = 'uncommon'),
         count(*) filter (where r = 'common')
    into v_exotic, v_rare, v_uncommon, v_common
    from (select public.good_rarity(id) as r from public.goods) t;
  if least(v_exotic, v_rare, v_uncommon, v_common) < 1 then
    raise exception '0032 self-assert FAIL: a tier is uninhabited (exotic %, rare %, uncommon %, common % of % goods) — retune the thresholds in a superseding migration rather than serving a tier that does not exist',
      v_exotic, v_rare, v_uncommon, v_common, v_goods;
  end if;
  if greatest(v_exotic, v_rare, v_uncommon, v_common) * 10 > v_goods * 6 then
    raise exception '0032 self-assert FAIL: one tier holds %/% goods — more than 60%%, so the tiering carries no information',
      greatest(v_exotic, v_rare, v_uncommon, v_common), v_goods;
  end if;
  raise notice '0032 rarity distribution over % goods: exotic %, rare %, uncommon %, common %',
    v_goods, v_exotic, v_rare, v_uncommon, v_common;

  -- (e) THE ENDS OF THE SCALE MEAN WHAT THE WORDS SAY. The scarcest good in the world (fewest
  --     producing ports; ties broken by code, never heap order) must be exotic, the most-made
  --     must be common — the derivation actually straddles its own thresholds on this world.
  select g.id, g.code into strict v_min_good, v_min_code
    from public.goods g
    left join public.port_specialties ps on ps.good_id = g.id
   group by g.id, g.code
   order by count(ps.port_id) asc, g.code asc
   limit 1;
  select g.id, g.code into strict v_max_good, v_max_code
    from public.goods g
    left join public.port_specialties ps on ps.good_id = g.id
   group by g.id, g.code
   order by count(ps.port_id) desc, g.code asc
   limit 1;
  if public.good_rarity(v_min_good) <> 'exotic' then
    raise exception '0032 self-assert FAIL: the scarcest good (%) tiers as %, not exotic',
      v_min_code, public.good_rarity(v_min_good);
  end if;
  if public.good_rarity(v_max_good) <> 'common' then
    raise exception '0032 self-assert FAIL: the most-produced good (%) tiers as %, not common',
      v_max_code, public.good_rarity(v_max_good);
  end if;

  -- (f) THE WIRE SAYS WHAT THE AUTHORITY SAYS — snapshot. Every served good carries a rarity and
  --     it is the authority's answer; the count proves the field is on ALL of them, not some.
  v_snap := world.snapshot();
  select count(*) into v_n from jsonb_array_elements(v_snap -> 'goods');
  if v_n <> v_goods then
    raise exception '0032 self-assert FAIL: snapshot serves % goods, the table holds %', v_n, v_goods;
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_snap -> 'goods') elem
   where elem ->> 'rarity' is distinct from public.good_rarity((elem ->> 'id')::uuid);
  if v_bad <> 0 then
    raise exception '0032 self-assert FAIL: % snapshot good(s) serve a rarity that is not public.good_rarity''s answer', v_bad;
  end if;
  -- and the deterministic subject read end-to-end: the scarcest good, by value, off the payload.
  select elem ->> 'rarity' into strict v_wire
    from jsonb_array_elements(v_snap -> 'goods') elem
   where elem ->> 'id' = v_min_good::text;
  if v_wire <> 'exotic' then
    raise exception '0032 self-assert FAIL: the wire says % for the scarcest good (%), the authority says exotic',
      v_wire, v_min_code;
  end if;

  -- (g) THE SUPERSEDE IS A NO-OP BUT FOR THE FIELD — snapshot. The old payload was captured
  --     BEFORE the replace; the new one, stripped of `rarity`, must equal it exactly.
  --     Prose claiming "nothing else changed" is not evidence (NO_SPAGHETTI §3 point 3).
  select jsonb_set(v_snap, '{goods}',
           (select jsonb_agg(elem - 'rarity' order by idx)
              from jsonb_array_elements(v_snap -> 'goods') with ordinality as t(elem, idx)))
    into v_stripped;
  if v_stripped <> (select snap from payload_before_0032) then
    raise exception '0032 self-assert FAIL: world.snapshot() minus `rarity` differs from the 0028 payload — this supersede changed more than it declared';
  end if;

  -- (h) THE SAME TWO PROOFS FOR THE MARKET READ. now() is frozen in this transaction, so the
  --     drift slot cannot roll between the capture above and this read, and parity is exact.
  select id into strict v_port from public.ports order by code limit 1;
  v_market := world.market(v_port);
  select count(*) into v_n from jsonb_array_elements(v_market -> 'goods');
  if v_n = 0 then
    raise exception '0032 self-assert FAIL: world.market() serves no goods — the market asserts below would be vacuous';
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_market -> 'goods') elem
   where elem ->> 'rarity' is distinct from public.good_rarity((elem ->> 'good_id')::uuid);
  if v_bad <> 0 then
    raise exception '0032 self-assert FAIL: % market row(s) serve a rarity that is not public.good_rarity''s answer', v_bad;
  end if;
  select jsonb_set(v_market, '{goods}',
           (select jsonb_agg(elem - 'rarity' order by idx)
              from jsonb_array_elements(v_market -> 'goods') with ordinality as t(elem, idx)))
    into v_stripped;
  if v_stripped <> (select market from payload_before_0032) then
    raise exception '0032 self-assert FAIL: world.market() minus `rarity` differs from the 0029 payload — this supersede changed more than it declared';
  end if;

  -- (i) THE SECRET STILL DOES NOT CROSS THE WIRE — 0009/0028/0031's own instrument, re-run
  --     because this file re-cut the function that serves the payload. Positive controls first:
  --     a null or token payload would make position() vacuous.
  v_snap_txt := v_snap::text;
  if v_snap_txt is null or length(v_snap_txt) < 1000 then
    raise exception '0032 self-assert FAIL: world.snapshot() served % character(s) — too small to be the real payload, so the leak check would be vacuous', coalesce(length(v_snap_txt), 0);
  end if;
  if position('time_compression' in v_snap_txt) = 0 then
    raise exception '0032 self-assert FAIL: position() cannot find time_compression in the payload — the leak instrument is broken, so its zero would prove nothing';
  end if;
  if position(v_secret in v_snap_txt) > 0 then
    raise exception '0032 self-assert FAIL: the world secret appears in the world.snapshot() payload';
  end if;

  -- (j) THE HELPERS ARE NOT CLIENT-EXECUTABLE — the formula is served as a field, never as a
  --     callable — and POSTURE holds, as every migration since 0001/0018 re-asserts it.
  if has_function_privilege('anon', 'public.rarity_from_producers(int)', 'execute')
     or has_function_privilege('authenticated', 'public.rarity_from_producers(int)', 'execute')
     or has_function_privilege('anon', 'public.good_rarity(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.good_rarity(uuid)', 'execute') then
    raise exception '0032 self-assert FAIL: a client role may execute a rarity helper — the formula must not cross the wire';
  end if;
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0032 self-assert FAIL: client_write_grants() found % write grant(s) after this migration', v_grants;
  end if;
  select count(*) into v_writers from public.client_executable_writers();
  if v_writers <> 0 then
    raise exception '0032 self-assert FAIL: client_executable_writers() found % client-executable writer(s)', v_writers;
  end if;

  drop table payload_before_0032;

  raise notice '0032 self-assert ok: % goods each tiered once, four tiers inhabited (exotic %, rare %, uncommon %, common %), snapshot and market serve the one authority''s answer, both supersedes are no-ops but for the field, and the secret still does not cross the wire',
    v_goods, v_exotic, v_rare, v_uncommon, v_common;
end $$;
