-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0010 — THE CLOCK TICKS FOR EVERYONE
--        tick_arrivals · tick_market_drift · tick_reconcile — and the honest statement that the
--        ticks are an OPTIMISATION, not a correctness requirement.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT A TICK IS FOR HERE, AND WHAT IT IS NOT ─────────────────────────────────────────────────
--   DESIGN §D.2: "The cron job is an OPTIMISATION FOR LEADERBOARD FRESHNESS, NOT A CORRECTNESS
--   REQUIREMENT." 0007's settle() and 0009's reads already bring any fleet fully up to date the
--   moment anyone looks at it. tick_arrivals exists so that a fleet nobody is looking at is still
--   current — for a shared market, a leaderboard, another player's %NBR column.
--
--   That is why 0009 was written first and this file second. If the ticks were load-bearing, a
--   missed cron run would be a bug in the game rather than a delay in a statistic.
--
-- ── EACH TICK IS IDEMPOTENT AND KEYED (DESIGN §D.2) ─────────────────────────────────────────────
--   tick_arrivals      — keyed on (voyage_id, day_index); settle() already refuses to resolve a day
--                        twice, so running the tick twice in a second is a no-op.
--   tick_market_drift  — keyed on a DRIFT SLOT, floor(epoch / drift_slot_seconds). A row whose
--                        drift_slot already equals the current slot is skipped. Without a key an
--                        Ornstein-Uhlenbeck step is NOT idempotent: two runs in one minute would
--                        walk the market twice as far as one, and a retried cron job would quietly
--                        double the volatility of the whole world.
--   Stock regeneration — applied in CLOSED FORM over the elapsed game-days,
--                        stock = target - (target - stock) x (1 - rate)^days, so a tick that has
--                        not run for six hours catches up to exactly the same number a tick that
--                        ran every ten minutes would have reached. Same discipline as movement.
--   tick_reconcile     — reads only. It asserts the two invariants of Appendix 1 and writes nothing.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * tick_arrivals brings a due voyage home with NOBODY looking, and a second call changes nothing.
--   * tick_market_drift moves the market on a new slot and DOES NOTHING on a repeat call in the
--     same slot — proven both ways, because idempotence claimed on one direction is half a claim.
--   * drift stays inside the §G.1 clamp after 20 forced slots, and stock regenerates TOWARD its
--     target without overshooting it.
--   * tick_reconcile passes on a healthy world AND RAISES on a purse deliberately falsified — the
--     positive control, without which "reconciliation passed" would mean nothing.
--
-- Depends ONLY on: 0001-0009.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('drift_slot_seconds', to_jsonb(600),
   'DESIGN D.2: tick_market_drift runs every 10 minutes. The slot index floor(epoch/600) is what makes the OU step idempotent — a row already stepped in this slot is skipped.')
on conflict (key) do nothing;

alter table public.port_goods add column if not exists drift_slot    bigint not null default 0;
alter table public.port_goods add column if not exists last_regen_day int   not null default 0;
comment on column public.port_goods.drift_slot is
  'The last drift slot in which this row was stepped. The KEY that makes an Ornstein-Uhlenbeck '
  'walk idempotent: a retried tick in the same slot must not walk the market twice.';

-- ── tick_arrivals (DESIGN §D.2, every 60 s) ────────────────────────────────────────────────────
create or replace function public.tick_arrivals(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         record;
  v_fleets  int := 0;
  v_days    int := 0;
begin
  -- Only fleets with something actually due. FOR UPDATE SKIP LOCKED so two overlapping cron runs
  -- divide the work instead of blocking on each other or double-resolving it.
  for r in select v.fleet_id
             from public.voyages v
            where v.status = 'SAILING'
              and (v.eta <= p_now or voyage.day_ends_at(v.id, v.last_settled_day + 1) <= p_now)
            order by v.eta
              for update skip locked loop
    v_days   := v_days + voyage.settle(r.fleet_id, p_now);
    v_fleets := v_fleets + 1;
  end loop;

  -- A fleet whose yard time has elapsed is released by the same rule the queue runner uses; there
  -- is no second "is the repair finished?" test anywhere in the chain.
  for r in select f.id from public.fleets f
            where f.status = 'REPAIRING' and f.busy_until is not null and f.busy_until <= p_now
              for update skip locked loop
    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;

  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now);
end $$;

-- ── tick_market_drift (DESIGN §D.2, every 10 min; §G.1 OU step, §G.2 regeneration) ─────────────
create or replace function public.tick_market_drift(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot   bigint := floor(extract(epoch from p_now) / public.wc_num('drift_slot_seconds'))::bigint;
  v_day    int    := world.game_day(p_now);
  v_theta  numeric := public.wc_num('drift_theta');
  v_sigma  numeric := public.wc_num('drift_sigma');
  v_clamp  numeric := public.wc_num('drift_clamp');
  v_rate   numeric := public.wc_num('stock_regen_fraction');
  v_n      int;
  v_regen  int;
begin
  -- §G.1: drift <- theta x drift + N(0, sigma), clamped. Box-Muller from two uniforms; the market
  -- is deliberately NOT deterministic, unlike the hazard rolls — a market a player could replay
  -- would be a market a player could front-run.
  update public.port_goods pg
     set drift = greatest(-v_clamp, least(v_clamp,
                   v_theta * pg.drift
                   + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))),
         drift_slot = v_slot,
         updated_at = p_now
   where pg.drift_slot < v_slot;
  get diagnostics v_n = row_count;

  -- §G.2 regeneration, in closed form over however many game-days have passed. A tick that missed
  -- six hours lands on exactly the number an unbroken sequence of ticks would have reached.
  update public.port_goods pg
     set stock = least(pg.stock_target,
                   pg.stock_target - (pg.stock_target - pg.stock) * power(1 - v_rate, v_day - pg.last_regen_day)
                   + pg.production_rate * (v_day - pg.last_regen_day)),
         last_regen_day = v_day,
         updated_at = p_now
   where pg.last_regen_day < v_day;
  get diagnostics v_regen = row_count;

  return jsonb_build_object('slot', v_slot, 'drifted', v_n, 'regenerated', v_regen, 'game_day', v_day);
end $$;

-- ── tick_reconcile — reads only, asserts the invariants of Appendix 1 ──────────────────────────
create or replace function public.tick_reconcile()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r       record;
  v_n     int := 0;
  v_grants int;
begin
  for r in select id from public.players loop
    perform public.assert_ledger_reconciles(r.id);   -- raises on a mismatch
    v_n := v_n + 1;
  end loop;
  perform voyage.assert_sailing_invariant();
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception 'RECONCILE FAIL: % client write grant(s) have appeared since deploy', v_grants
      using errcode = '42501';
  end if;
  return jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok', 'client_write_grants', 0);
end $$;

revoke all on function public.tick_arrivals(timestamptz)     from public, anon, authenticated;
revoke all on function public.tick_market_drift(timestamptz) from public, anon, authenticated;
revoke all on function public.tick_reconcile()               from public, anon, authenticated;
grant execute on function public.tick_arrivals(timestamptz)     to service_role;
grant execute on function public.tick_market_drift(timestamptz) to service_role;
grant execute on function public.tick_reconcile()               to service_role;

-- Scheduling, where the platform provides it. PGlite has no pg_cron and neither does a bare
-- PostgreSQL, so this is attempted and REPORTED rather than assumed — the chain must apply
-- identically in both places, and DESIGN D.2 has already established that a missed tick is a
-- staleness problem and never a correctness one.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('voyage-tick-arrivals',     '* * * * *',    'select public.tick_arrivals()');
    perform cron.schedule('voyage-tick-market-drift', '*/10 * * * *', 'select public.tick_market_drift()');
    perform cron.schedule('voyage-tick-reconcile',    '0 * * * *',    'select public.tick_reconcile()');
    raise notice '0010: pg_cron present — tick_arrivals (60s), tick_market_drift (10m), tick_reconcile (hourly) scheduled';
  else
    raise notice '0010: pg_cron absent — the tick functions exist and are proven, but nothing schedules them here. Reads still settle (DESIGN D.2).';
  end if;
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe constant uuid := '00000000-0010-4000-8000-000000000001';
  v_player uuid; v_fleet uuid; v_cad uuid; v_lis uuid; v_sal uuid;
  v_t1 jsonb; v_t2 jsonb; v_d1 jsonb; v_d2 jsonb; v_rec jsonb;
  v_drift0 numeric; v_drift1 numeric; v_drift2 numeric;
  v_moved  int; v_rows int;
  v_stock0 numeric; v_stock1 numeric; v_target numeric;
  v_status text; v_port text; v_events1 int; v_events2 int;
  v_outside int; v_sampled int; v_over int; v_grants int; n int; k int;
  f_arrive boolean := false; f_arrive_idem boolean := false;
  f_drift boolean := false; f_drift_idem boolean := false;
  f_clamp boolean := false; f_regen boolean := false;
  f_rec_ok boolean := false; f_rec_bites boolean := false;
begin
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_sal from public.goods where code = 'salt';

  begin
    -- ── (a) tick_arrivals brings a fleet home with nobody looking, and is idempotent.
    v_player := public.new_house(v_probe, 'Casa Relogio', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform cmd.assume_identity(v_probe);
    perform cmd.issue(v_fleet, 'SAIL TO Cadiz');
    update public.voyages set departed_at = departed_at - interval '9 hours',
                              eta = eta - interval '9 hours'
     where fleet_id = v_fleet and status = 'SAILING';

    v_t1 := public.tick_arrivals();
    select status, (select code from public.ports where id = f.port_id) into v_status, v_port
      from public.fleets f where f.id = v_fleet;
    select count(*) into v_events1 from public.voyage_events ve
      join public.voyages vv on vv.id = ve.voyage_id where vv.fleet_id = v_fleet;
    if v_status = 'DOCKED' and v_port = 'CAD' and (v_t1->>'fleets_touched')::int >= 1
       and (v_t1->>'days_resolved')::int >= 1 then
      f_arrive := true;
    end if;

    v_t2 := public.tick_arrivals();
    select count(*) into v_events2 from public.voyage_events ve
      join public.voyages vv on vv.id = ve.voyage_id where vv.fleet_id = v_fleet;
    if (v_t2->>'fleets_touched')::int = 0 and v_events1 = v_events2 then f_arrive_idem := true; end if;

    -- ── (b) tick_market_drift steps once per slot, and only once.
    --
    -- IT ASKS WHETHER THE MARKET MOVED, NOT WHETHER ONE ROW DID. This used to read the drift of a
    -- single row (Lisboa x Salt) before and after and require it to change — and it flaked, once,
    -- in a player's browser: "the drift did not move (0.0000 -> 0.0000)" while the tick reported
    -- all 14,980 rows stepped. Both facts were true. `port_goods.drift` is numeric(6,4), so an OU
    -- step smaller than 0.00005 rounds to no change at all, and from a zeroed drift that is a
    -- perfectly ordinary draw. The assert was a lottery on one row, and the boot it failed had
    -- done nothing wrong. It self-healed on the one-shot retry, which is how it stayed hidden.
    --
    -- So the claim is measured where it lives: the tick promises to step EVERY row, and a stepped
    -- market is one that has MOVED. A handful of rows rounding to zero is the arithmetic working;
    -- a market where almost nothing moved is the defect this is looking for, and the count is
    -- printed rather than implied.
    update public.port_goods set drift = 0, drift_slot = 0;
    select drift into v_drift0 from public.port_goods where port_id = v_lis and good_id = v_sal;
    v_d1 := public.tick_market_drift();
    select drift into v_drift1 from public.port_goods where port_id = v_lis and good_id = v_sal;
    select count(*) into v_moved from public.port_goods where drift <> 0;
    select count(*) into v_rows  from public.port_goods;
    if (v_d1->>'drifted')::int = v_rows and v_moved * 10 >= v_rows * 9 then f_drift := true; end if;

    v_d2 := public.tick_market_drift();
    select drift into v_drift2 from public.port_goods where port_id = v_lis and good_id = v_sal;
    if (v_d2->>'drifted')::int = 0 and v_drift2 = v_drift1 then f_drift_idem := true; end if;

    -- ── (c) forced slots, and the drift is still inside the §G.1 clamp.
    --
    --        The clamp is a per-row property of the OU step, so it does not need all 14,980 rows
    --        walked twenty times — that is 300,000 rewrites, and this migration applies inside a
    --        player's browser tab on first boot. Only the rows of twenty ports are pushed back a
    --        slot, so each forced tick touches those and nothing else, and the count is printed
    --        rather than implied. Twenty steps is past the point where an unclamped walk would
    --        have reached its stationary spread (theta 0.85), so an escape would show.
    select count(*) into v_sampled from public.port_goods
     where port_id in (select id from public.ports order by code limit 20);
    for k in 1 .. 20 loop
      update public.port_goods set drift_slot = drift_slot - 1
       where port_id in (select id from public.ports order by code limit 20);
      perform public.tick_market_drift();
    end loop;
    select count(*) into v_outside from public.port_goods
     where abs(drift) > public.wc_num('drift_clamp') + 1e-9;
    if v_outside = 0 then f_clamp := true; end if;

    -- ── (d) stock regenerates TOWARD the target and never past it.
    update public.port_goods set stock = round(stock_target / 4), last_regen_day = world.game_day() - 20;
    select stock, stock_target into v_stock0, v_target
      from public.port_goods where port_id = v_lis and good_id = v_sal;
    perform public.tick_market_drift();
    select stock into v_stock1 from public.port_goods where port_id = v_lis and good_id = v_sal;
    select count(*) into v_over from public.port_goods where stock > stock_target + 1e-6;
    if v_stock1 > v_stock0 and v_stock1 <= v_target and v_over = 0 then f_regen := true; end if;

    -- ── (e) reconciliation passes here...
    v_rec := public.tick_reconcile();
    if (v_rec->>'players_checked')::int >= 1 then f_rec_ok := true; end if;

    -- ...and BITES when the purse is falsified. The constraint trigger is DEFERRED, so this write
    -- survives until commit — which is exactly the window an hourly reconciler exists to close.
    update public.players set ducats = ducats + 4242 where id = v_player;
    begin
      perform public.tick_reconcile();
    exception when others then
      if sqlerrm ~ 'LEDGER RECONCILIATION FAILED' then f_rec_bites := true; end if;
    end;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if not f_arrive      then raise exception '0010 self-assert FAIL: tick_arrivals did not bring the fleet home (status %, port %, tick %)', v_status, v_port, v_t1; end if;
  if not f_arrive_idem then raise exception '0010 self-assert FAIL: a second tick_arrivals was not a no-op (% then % events, tick %)', v_events1, v_events2, v_t2; end if;
  if not f_drift       then raise exception '0010 self-assert FAIL: tick_market_drift stepped % of % row(s) and left only % of them moved — a market that does not move is not drifting', (v_d1->>'drifted'), v_rows, v_moved; end if;
  if not f_drift_idem  then raise exception '0010 self-assert FAIL: a repeat tick in the SAME slot stepped % row(s) and moved the drift % -> % — the OU walk is not keyed', (v_d2->>'drifted'), v_drift1, v_drift2; end if;
  if not f_clamp       then raise exception '0010 self-assert FAIL: after 20 slots over % sampled row(s), % row(s) in the world drifted outside the G.1 clamp', v_sampled, v_outside; end if;
  if not f_regen       then raise exception '0010 self-assert FAIL: stock did not regenerate toward the target without overshoot (% -> % of %, % row(s) over target)', v_stock0, v_stock1, v_target, v_over; end if;
  if not f_rec_ok      then raise exception '0010 self-assert FAIL: tick_reconcile checked no players: %', v_rec; end if;
  if not f_rec_bites   then raise exception '0010 self-assert FAIL: tick_reconcile ACCEPTED a purse inflated by 4,242 ducats with no ledger row behind it'; end if;

  select count(*) into n from public.players;
  if n <> 0 then raise exception '0010 self-assert FAIL: % player row(s) survived the probe subtransaction', n; end if;
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0010 self-assert FAIL: the tick surface minted % client write grant(s)', v_grants; end if;

  raise notice '0010 self-assert ok: tick_arrivals settled % voyage-day(s) and docked the fleet at CAD unattended, and a second call touched 0 fleets; tick_market_drift stepped all % rows once per slot with % of them actually moved (the rest round to zero at numeric(6,4), which is the arithmetic working) and 0 rows on a repeat call in the same slot; after 20 forced slots over % sampled rows, 0 rows in the world sit outside the G.1 clamp; stock regenerated % -> % toward a target of % with 0 overshoots; tick_reconcile checked % player(s) and RAISED on a purse falsified by 4,242 d.; 0 client write grants',
    (v_t1->>'days_resolved'), (v_d1->>'drifted'), v_moved, v_sampled, v_stock0, v_stock1, v_target, (v_rec->>'players_checked');
end $$;
