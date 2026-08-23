-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0029 — THE MARKET SAYS WHEN IT NEXT MOVES, AND MOVES WHEN IT SAID IT WOULD
--        A countdown a client could fake is a second authority for "when do prices change";
--        the read that serves the PRICES now serves the clock they run on, and honours it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THIS SUPERSEDES, AND WHY ──────────────────────────────────────────────────────────────
--   world.market(uuid)   0009:115, re-cut 0019:568 — gains ONE served object, `clock`, and ONE
--                        opening statement: it winds the drift tick before it prices anything.
--                        Nothing else in its payload moves; the self-assert below proves that on
--                        the PAYLOAD (0028 (b)'s instrument — the source cannot be strip-compared
--                        here because the language changes from `sql STABLE` to `plpgsql`, which
--                        the write requires: PostgreSQL refuses a write inside a non-volatile
--                        function, the same fact that disqualified snapshot() as 0028's home).
--
-- The two changes are one file because they are the two halves of one promise the player reads.
-- The COMMAND tab is to print "prices move in 4 m 12 s". Serve the instant without the wind and,
-- on every deployment without pg_cron — which is every browser, because the chain applies under
-- PGlite where NOTHING calls tick_market_drift (0010 and 0012 both print exactly that on apply) —
-- the countdown reaches zero, the client re-asks, and the prices have not moved and never will:
-- a promise with no mechanism. Wind without serving and the world moves on a rhythm no screen can
-- print. 0017:50-55's rule, applied: everything that must move together moves in one file.
--
-- ── THE DESIGN QUESTION: WHY THE CLIENT MUST NOT MULTIPLY ITS WAY TO THIS NUMBER ───────────────
-- The client could ALMOST fake it: world.price_history() serves `slot_seconds` (0013:170) and
-- world.buffs() serves `now` (0026:401). `now + slot_seconds` LOOKS like a countdown and is a
-- second authority for "when do prices change", wrong in two ways the self-assert measures:
--   * it restarts the full slot on every read — the boundary is a fact about the WALL CLOCK
--     (floor(epoch / slot)), not about when somebody last looked; mid-slot the guess is stale by
--     exactly the time already elapsed in the slot, and (g) prints that error on a constructed
--     instant where it is 137 seconds by arithmetic, not by luck;
--   * it goes silently wrong THE DAY THE CADENCE CHANGES: a client holding a cached
--     `slot_seconds` keeps promising the old rhythm while the server steps on the new one — (h)
--     retunes the knob 600 → 300 in a rolled-back probe and prints the two answers disagreeing.
-- So the read that serves the prices serves their clock, once, and the client's countdown is
-- subtraction against a served instant — never multiplication against a knob.
--
-- ── WHAT `clock` CARRIES, AND WHAT IT DELIBERATELY DOES NOT ────────────────────────────────────
--   now             The server's reading of this instant — the payload's own timestamp, the same
--                   per-payload fact world.buffs() already serves as `now` (0026:401). Not a
--                   duplicate: each payload stamps its OWN read instant; there is no stored fact
--                   two payloads could disagree about.
--   next_change_at  The instant the drift walk next steps, from public.next_drift_change_at() —
--                   minted below as the named inverse of public.drift_slot_of() (0013:79), the
--                   slot authority this file composes rather than restates.
--   NOT slot_seconds   Serving the cadence beside the instant would invite the client to compute
--                   `next + slot_seconds` for the boundary after — the exact multiplication this
--                   file exists to end. When the countdown reaches zero the client RE-ASKS.
--                   world.price_history() keeps serving `slot_seconds`: that is the width of a
--                   history bucket for labelling a time axis (0013:174-176), a different question
--                   with the same knob behind it — one authority (world_config), two projections.
--   NOT priced_at      There is no stored fact for "when the drift last stepped": the tick keys
--                   on a slot NUMBER (0010:47-51), `updated_at` also moves on trades and regen,
--                   and `slot × slot_seconds` would claim an instant that is false on any wound
--                   world that sat idle past a boundary. A field that cannot be served honestly
--                   is not served.
--
-- ── THE WIND: THE READ IS THE CATCH-UP (0009), APPLIED TO THE MARKET'S OWN CLOCK ───────────────
-- world.market() now performs public.tick_market_drift() before it prices — a third CALLER of
-- 0010's one writer, beside pg_cron (0012) and nothing else; the tick is not re-cut and not one
-- line of what a step IS moves here. The tick is idempotent by its slot key, so every call after
-- the first in a slot updates nothing. Why THIS read and not world.fleets(), though 0028 put the
-- fair calendar there — the difference is measured, not argued:
--   * the countdown's contract is with THIS read. It is the read the client re-asks the moment
--     the countdown hits zero, and the answer must already contain the moved prices — winding
--     anywhere else leaves the promise false at the only moment anyone tests it.
--   * cost. On this machine (PGlite 0.5.5 / PostgreSQL 18.3, chain through 0028, 2026-08-23) a
--     settled-slot tick_market_drift() is 5–9 ms — noise against world.market()'s own ~335 ms,
--     but 3–5× the ENTIRE 1.7 ms world.fleets() read that runs every thirty seconds; 0028 spent
--     a header defending that read's 0.240 ms wind and this file does not hand it back. The
--     once-per-slot real step is 208–353 ms, paid by one read per slot — exactly the work a cron
--     deployment schedules out of band.
--   * unlike a fair — an AUTHORED real-time window a player standing at the quay must encounter
--     whether or not anyone reads a price — a skipped OU step is a legal quieter walk (D.2: a
--     missed tick is a staleness problem, never a correctness one). Its staleness is observable
--     ONLY through a price read, and every price read now catches it up first.
-- tick_price_snapshot() is deliberately NOT wound here: measured 2.3 s per first-in-slot call and
-- 1.6–2.1 s even as a same-slot no-op (ON CONFLICT still computes all 14,980 mids before it
-- conflicts). A read must not pay seconds for a record that is an optimisation; the record stays
-- pg_cron's (0013), and 0013's apply notice already states what that means where there is none.
--
-- ── WHAT next_change_at PROMISES, PRECISELY ────────────────────────────────────────────────────
-- It is the instant the DRIFT WALK next steps — the scheduled movement of the whole market. Two
-- things can nudge an individual price sooner and are not schedulable: another captain's trade
-- (stock moves the derived mid, 0005) and stock regeneration (game-day cadence, 0010:120-126,
-- applied by the same tick). The walk itself moves at this instant and not before — asserted
-- below by running the tick one second before the served instant (0 rows) and AT it (every row).
--
-- ── GRANTS: NO NEW ENTRY POINT ─────────────────────────────────────────────────────────────────
-- world.market is already on public.client_rpc_entry_points() (0018); it stays `authenticated`
-- only, re-issued explicitly after the re-cut (0017/0019/0028's discipline). The new authority
-- public.next_drift_change_at() reaches the client only through the payload, like drift_slot_of.
--
-- Depends ONLY on: 0001 (world_config, wc_*), 0005 (port_goods, mid_price, price), 0010
--                  (tick_market_drift, drift_slot), 0013 (drift_slot_of, price_history),
--                  0019 (world.market's current definition), 0018/0023 (grant authorities).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGE. Settle the slot FIRST — in this transaction now() is one instant, so after this
-- the new definition's wind is a no-op by construction and the parity comparison below measures
-- the payload shape, never a legitimate drift step that happened to be due at apply time.
do $$ begin perform public.tick_market_drift(); end $$;

create temporary table market_before_0029 as
  select p.id as port_id, world.market(p.id) as payload
    from public.ports p
   where p.id = (select id from public.ports order by code limit 1);

-- ── THE NEXT STEP, NAMED ───────────────────────────────────────────────────────────────────────
-- The inverse of public.drift_slot_of() (0013): not "which slot is this instant in" but "when
-- does the next one begin". COMPOSED on the slot authority and the one knob — the floor()
-- expression itself lives in 0010:97 and 0013:86 and is not written a third time here.
create or replace function public.next_drift_change_at(p_at timestamptz default now())
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select to_timestamp(((public.drift_slot_of(p_at) + 1) * public.wc_num('drift_slot_seconds'))::double precision);
$$;

comment on function public.next_drift_change_at(timestamptz) is
  'THE ONE named answer to "when does the market next step". The next drift slot boundary, '
  'composed on public.drift_slot_of (0013) and the drift_slot_seconds knob. Serves the client '
  'through world.market()''s clock; a client must never recompute it from slot_seconds and a '
  'wall clock — that is a second authority that goes wrong the day the cadence changes.';

revoke all on function public.next_drift_change_at(timestamptz) from public, anon, authenticated;

-- ── SUPERSEDES 0019:568 — THE PRICE READ WINDS THE CLOCK IT REPORTS ────────────────────────────
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

comment on function world.market(uuid) is
  'One quay''s prices (0019), and since 0029 their CLOCK: it winds public.tick_market_drift '
  'before pricing — the read is the catch-up (0009) — and serves clock.now and '
  'clock.next_change_at so a countdown is subtraction against served instants. When the countdown '
  'reaches zero the client re-asks; the re-ask is itself what steps the market where pg_cron is '
  'absent.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_port      uuid;
  v_good      uuid;
  v_good_code text;
  v_pairs     int;
  v_pre       jsonb;
  v_new       jsonb;
  v_keys      text[];
  v_next      timestamptz;
  v_slot_s    numeric := public.wc_num('drift_slot_seconds');
  v_at        timestamptz;
  v_fake      timestamptz;
  v_next_at   timestamptz;
  v_next600   timestamptz;
  v_next300   timestamptz;
  v_d0        jsonb;
  v_d1        jsonb;
  v_m1        jsonb;
  v_m2        jsonb;
  v_behind    int;
  v_hist0     int;
  v_hist1     int;
  v_served    numeric;
  v_ask       numeric;
  v_callers   int;
  v_names     text;
  v_users     int;
  v_seen      int;
  v_grants    int;
  f_parity    boolean := false;
  f_clock     boolean := false;
  f_authority boolean := false;
  f_seam      boolean := false;
  f_wind      boolean := false;
  f_idem      boolean := false;
  f_norecord  boolean := false;
  f_fresh     boolean := false;
  f_reset     boolean := false;
  f_cadence   boolean := false;
  f_grant     boolean := false;
begin
  select count(*) into v_pairs from public.port_goods;
  if v_pairs = 0 then
    raise exception '0029 self-assert FAIL: there are no market rows, so every winding and seam test below would pass vacuously';
  end if;

  select port_id into v_port from market_before_0029;
  select payload into v_pre  from market_before_0029;
  -- A DETERMINISTIC SUBJECT for the freshness check: the first good this port trades, by code —
  -- never `limit 1` on whatever the heap hands back (docs/NO_SPAGHETTI.md §4).
  select g.id, g.code into v_good, v_good_code
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_port order by g.code limit 1;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) THE PAYLOAD GAINED EXACTLY `clock` AND NOTHING ELSE. The pre-image was captured through
  --     the 0019 definition after the slot was settled, and now() is one instant in this
  --     transaction, so the new definition's wind is a no-op here by construction: any other
  --     difference is a defect. Proven on the payload, 0028 (b)'s instrument, because the source
  --     cannot be strip-compared across a language change.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_new := world.market(v_port);
  select array_agg(k order by k) into v_keys from jsonb_object_keys(v_new->'clock') k;
  if (v_new - 'clock') = v_pre
     and not (v_pre ? 'clock')
     and (v_new ? 'clock') then
    f_parity := true;
  end if;

  -- (b) THE CLOCK CARRIES EXACTLY TWO INSTANTS, and `now` is this transaction's own read instant.
  if v_keys = array['next_change_at', 'now']
     and (v_new->'clock'->>'now')::timestamptz = now() then
    f_clock := true;
  end if;

  -- (c) THE SERVED INSTANT IS THE AUTHORITY'S, and the authority is the slot authority's inverse:
  --     the instant it names lies in exactly the NEXT slot, and one second before it lies in this
  --     one. drift_slot_of is the function 0013 proved agrees with the tick's own report.
  v_next := public.next_drift_change_at(now());
  if (v_new->'clock'->>'next_change_at')::timestamptz = v_next
     and public.drift_slot_of(v_next) = public.drift_slot_of(now()) + 1
     and public.drift_slot_of(v_next - interval '1 second') = public.drift_slot_of(now()) then
    f_authority := true;
  end if;

  select count(*) into v_hist0 from public.price_history;

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────

    -- (d) THE SEAM, END TO END: the served instant IS the instant the drift tick next fires —
    --     measured on the TICK'S OWN BEHAVIOUR, never on a retyped formula. One second before the
    --     served instant the tick steps NOTHING; at the served instant it steps EVERY row.
    v_d0 := public.tick_market_drift(v_next - interval '1 second');
    v_d1 := public.tick_market_drift(v_next);
    if (v_d0->>'drifted')::int = 0 and (v_d1->>'drifted')::int = v_pairs then
      f_seam := true;
    end if;
    raise exception '__PROBE_ROLLBACK_0029A__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0029A__' then raise; end if;
  end;

  begin
    -- (e) THE WIND, FROM THE READ ITSELF: push every row back one slot — a world where the drift
    --     is due — and require that ONE call to world.market() catches the whole market up and
    --     serves the STEPPED numbers, not a stale copy: the served ask for a deterministic good
    --     must equal world.price() recomputed against the post-step state, to the digit.
    update public.port_goods set drift_slot = drift_slot - 1;
    v_m1 := world.market(v_port);
    select count(*) into v_behind from public.port_goods
     where drift_slot < public.drift_slot_of(now());
    select (e->>'buy')::numeric into v_served
      from jsonb_array_elements(v_m1->'goods') e where e->>'code' = v_good_code;
    select q.ask into v_ask from world.price(v_port, v_good) q;
    if v_behind = 0 and v_served = v_ask then f_wind := true; end if;
    if v_behind = 0 then f_fresh := true; end if;

    -- (f) AND IT IS IDEMPOTENT FROM THIS CALLER: a second read in the same slot serves the
    --     IDENTICAL goods payload and the identical promise — the wind is a catch-up, not a walk
    --     on every read.
    v_m2 := world.market(v_port);
    if (v_m2->'goods') = (v_m1->'goods')
       and (v_m2->'clock'->>'next_change_at') = (v_m1->'clock'->>'next_change_at') then
      f_idem := true;
    end if;

    -- (g) THE RECORD IS NOT TOUCHED: the wind deliberately excludes tick_price_snapshot (header:
    --     seconds per call, measured), so a stepped read must leave price_history exactly as it
    --     found it.
    select count(*) into v_hist1 from public.price_history;
    if v_hist1 = v_hist0 then f_norecord := true; end if;

    -- (h) NEGATIVE CONTROL 1 — the client guess this file exists to forbid. `now + slot_seconds`
    --     (price_history's knob × buffs' clock) restarts the countdown on every read. On an
    --     instant built 137 seconds into a slot — CONSTRUCTED, so this is arithmetic and never a
    --     lottery on when the migration runs — the guess misses the true boundary by exactly 137
    --     seconds.
    v_at      := to_timestamp(((public.drift_slot_of(now()) * v_slot_s) + 137)::double precision);
    v_fake    := v_at + make_interval(secs => v_slot_s::double precision);
    v_next_at := public.next_drift_change_at(v_at);
    if v_fake <> v_next_at
       and v_fake - v_next_at = interval '137 seconds' then
      f_reset := true;
    end if;

    -- (i) NEGATIVE CONTROL 2 — the day the cadence changes. Retune drift_slot_seconds 600 → 300
    --     (in this rolled-back probe) and the AUTHORITY follows the knob at once, while a client
    --     holding the old slot_seconds keeps promising the old boundary. On the same constructed
    --     instant the two answers are 300 seconds apart — again by construction: 137 into the old
    --     slot is 137 into a new one too, so the boundaries land 163 s and 463 s out.
    v_next600 := v_next_at;
    update public.world_config set value = to_jsonb(300) where key = 'drift_slot_seconds';
    v_next300 := public.next_drift_change_at(v_at);
    if v_next300 <> v_next600
       and v_next600 - v_next300 = interval '300 seconds'
       and v_next300 - v_at = interval '163 seconds' then
      f_cadence := true;
    end if;

    raise exception '__PROBE_ROLLBACK_0029B__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0029B__' then raise; end if;
  end;

  -- ── the probes are rolled back; the findings survive in plpgsql variables (0026's shape) ─────

  if not f_parity then
    raise exception '0029 self-assert FAIL: world.market() did not gain exactly the clock object — stripped of `clock` the payload differs from the 0019 pre-image, or the pre-image already carried one';
  end if;
  if not f_clock then
    raise exception '0029 self-assert FAIL: the clock carries keys % (expected exactly next_change_at, now) or its now (%) is not this transaction''s read instant (%)', v_keys, v_new->'clock'->>'now', now();
  end if;
  if not f_authority then
    raise exception '0029 self-assert FAIL: the served next_change_at (%) is not public.next_drift_change_at (%), or that instant does not open the very next drift slot (slot % against now''s %)', v_new->'clock'->>'next_change_at', v_next, public.drift_slot_of(v_next), public.drift_slot_of(now());
  end if;
  if not f_seam then
    raise exception '0029 self-assert FAIL: the tick stepped % row(s) one second BEFORE the served instant and % row(s) AT it (market of %) — the promise on the wire is not the instant the drift tick actually fires', (v_d0->>'drifted'), (v_d1->>'drifted'), v_pairs;
  end if;
  if not f_wind or not f_fresh then
    raise exception '0029 self-assert FAIL: after one world.market() call % of % row(s) still sit behind the current slot, or the served ask (%) is not world.price()''s post-step ask (%) — the read did not catch the market up before pricing', v_behind, v_pairs, v_served, v_ask;
  end if;
  if not f_idem then
    raise exception '0029 self-assert FAIL: a second world.market() in the same slot served a different goods payload or a different next_change_at — the wind is walking the market on every read instead of once per slot';
  end if;
  if not f_norecord then
    raise exception '0029 self-assert FAIL: a stepped world.market() moved price_history % -> % row(s) — the read is paying for the record the header deliberately left to cron', v_hist0, v_hist1;
  end if;
  if not f_reset then
    raise exception '0029 self-assert FAIL: the forbidden client guess (now + slot_seconds = %) does not miss the served boundary (%) by the constructed 137 seconds — the negative control cannot see the error it exists to measure', v_fake, v_next_at;
  end if;
  if not f_cadence then
    raise exception '0029 self-assert FAIL: with drift_slot_seconds retuned 600 -> 300 the authority answered % against the stale-knob promise of % — expected the served answer to follow the knob and the stale arithmetic to miss by 300 s exactly', v_next300, v_next600;
  end if;

  -- THE ROLLBACKS REALLY ROLLED BACK: no row behind the slot, the record at its prior count, and
  -- the cadence knob back at its deployed value.
  select count(*) into v_behind from public.port_goods
   where drift_slot < public.drift_slot_of(now());
  select count(*) into v_hist1 from public.price_history;
  if v_behind <> 0 or v_hist1 <> v_hist0
     or public.wc_num('drift_slot_seconds') <> v_slot_s then
    raise exception '0029 self-assert FAIL: the probe leaked — % row(s) behind the slot, price_history % -> %, drift_slot_seconds reads % against %', v_behind, v_hist0, v_hist1, public.wc_num('drift_slot_seconds'), v_slot_s;
  end if;

  -- ONE WRITER, NAMED CALLERS (0028 (i)'s guard). tick_market_drift is called by exactly one
  -- function — world.market — beside pg_cron; next_drift_change_at is read by exactly that same
  -- function. `v_users` is the positive control: the same scan must be able to SEE the slot
  -- authority's other readers, or a count of one is a scan that found nothing.
  select count(*), string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
    into v_callers, v_names
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.proname <> 'tick_market_drift'
     and position('tick_market_drift' in p.prosrc) > 0;
  select count(*) into v_seen
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and position('drift_slot_of' in p.prosrc) > 0;
  select count(*) into v_users
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.proname <> 'next_drift_change_at'
     and position('next_drift_change_at' in p.prosrc) > 0;
  if v_callers <> 1 or v_names <> 'world.market' or v_users <> 1 or v_seen < 3 then
    raise exception '0029 self-assert FAIL: tick_market_drift is called by % function(s) [%] (exactly world.market may), next_drift_change_at by % (exactly world.market may), and the scan sees % drift_slot_of reader(s) (at least 3, or it is finding nothing)', v_callers, coalesce(v_names, '(none)'), v_users, v_seen;
  end if;

  -- POSTURE. The re-cut entry point exactly where 0018/0023 left it; the new authority and the
  -- ticks unreachable by any client; the whole grant family still at zero.
  if has_function_privilege('authenticated', 'world.market(uuid)', 'execute')
     and not has_function_privilege('anon', 'world.market(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public.next_drift_change_at(timestamptz)', 'execute')
     and not has_function_privilege('anon', 'public.next_drift_change_at(timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public.tick_market_drift(timestamptz)', 'execute')
     and not has_function_privilege('anon', 'public.tick_market_drift(timestamptz)', 'execute')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0029 self-assert FAIL: a grant moved — world.market must be executable by authenticated and never anon, next_drift_change_at and tick_market_drift by no client at all, with 0 client write grants, 0 client-executable writers, 0 read-wall gaps and every catalogued entry point resolving';
  end if;

  select count(*) into v_grants from public.client_write_grants();
  raise notice '0029 self-assert ok: THE MARKET SAYS WHEN IT NEXT MOVES, AND MOVES THEN. world.market() gained exactly one object, clock — the payload minus it is byte-identical jsonb to the 0019 pre-image — carrying now (this read''s own instant) and next_change_at (%); that instant is public.next_drift_change_at''s answer and the drift tick''s OWN behaviour: 0 rows step one second before it and all % step at it; a market pushed one slot behind was caught up by ONE read — 0 rows left behind, the served ask equal to world.price() recomputed post-step to the digit — a second read in the same slot served the identical payload, and price_history moved % row(s), because the record deliberately stays cron''s; the forbidden guesses are measurably wrong: now+slot_seconds misses the boundary by 137 s on a constructed mid-slot instant, and with the cadence retuned 600 -> 300 the served answer follows the knob while the stale arithmetic misses by 300 s; ONE function calls tick_market_drift [%] and one reads next_drift_change_at, with % drift_slot_of readers seen by the same scan; grants unchanged, % client write grants',
    v_next, v_pairs, v_hist1 - v_hist0, v_names, v_seen, v_grants;
end $$;

drop table market_before_0029;
