-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0013 — A PRICE REMEMBERS WHAT IT WAS: the market keeps a record, so a line can be drawn
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ────────────────────────────────────────────────────────────────────────
--   "do the migrations - price history, player row, officers, skills"
--
-- ── THE HOLE THIS FILLS ────────────────────────────────────────────────────────────────────────
-- Every price in this game is DERIVED at read time (0005: "every price is derived, never stored").
-- That is right, and it is also why the market has no memory: `world.market()` can say what salt
-- costs at Lisboa NOW, and nothing anywhere can say what it cost an hour ago. So:
--
--   src/features/market/MarketScreen.tsx  prints, on screen, "No seven-day line is drawn: a price
--                                         history is a record that has to be KEPT before it can be
--                                         shown, and nothing in the chain keeps one yet."
--   src/lib/db/README.md §4               lists `history7` as NOT SERVED.
--   docs/UI_DIRECTION.md §5               names it first among the server gaps — EVE's price graph
--                                         is the one thing a trade game must have.
--
-- A derived price and a remembered price are not two authorities for one number. The derivation
-- stays the only way a price is COMPUTED; this table only records what the derivation said, and
-- when. Nothing reads a price from here to trade on — `world.quote()` is still the only price the
-- money moves at, and this file does not touch it.
--
-- ── WHY IT IS KEYED ON A DRIFT SLOT ────────────────────────────────────────────────────────────
-- The same reason 0010's Ornstein-Uhlenbeck walk is: a snapshot that used `now()` as its key would
-- write a second row every time a cron run was retried, and the graph would show two points for one
-- moment. `(port_id, good_id, slot)` is the primary key, so a retried run is a no-op by
-- construction rather than by a check that has to be remembered.
--
-- THE SLOT FORMULA NOW HAS A NAME. 0010 computes `floor(epoch / drift_slot_seconds)` inline (line
-- 97). This file needs the same slot, and restating the expression would be a second authority for
-- "which slot is it". 0010 is DEPLOYED and may not be re-cut, so instead: `public.drift_slot_of()`
-- is minted here as the named authority, and the self-assert PROVES it returns the slot that
-- `tick_market_drift()` itself reports rather than assuming the two agree.
--
-- ── WHAT IS DELIBERATELY NOT HERE ──────────────────────────────────────────────────────────────
-- No moving averages, no Donchian channel, no candles. The client can compute a mean over what it
-- is given; the server's job is the record. And no per-player watchlist: what a captain is WATCHING
-- is a preference, not a fact about the world, and it has no table yet.
--
-- Depends ONLY on: 0001-0012 (ports/goods 0002-0003, port_goods + mid_price 0005, world_config +
-- wc_* 0001, drift_slot_seconds 0010, tick_cron_expression 0012).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('price_history_slots', to_jsonb(288),
   'How many drift slots of price history to keep per (port, good). At drift_slot_seconds = 600 that is 288 x 10 min = 48 hours, which covers the 7-day graph a client would draw in GAME days (one voyage-day is three real minutes at TIME_COMPRESSION 480, so 48 real hours is 960 game-days). The snapshot tick prunes beyond it, so the table has a ceiling instead of a slope.')
on conflict (key) do nothing;

-- ── THE RECORD ─────────────────────────────────────────────────────────────────────────────────
create table if not exists public.price_history (
  port_id uuid    not null references public.ports(id) on delete cascade,
  good_id uuid    not null references public.goods(id) on delete cascade,
  slot    bigint  not null,
  at      timestamptz  not null default now(),
  mid     numeric(12,4) not null check (mid > 0),
  stock   numeric(12,2) not null check (stock >= 0),
  primary key (port_id, good_id, slot)
);

comment on table public.price_history is
  'What the derived price WAS, sampled once per drift slot. Never the price anything trades at — '
  'world.quote() remains the only price the money moves at (0005). This is a record, not a source.';
comment on column public.price_history.slot is
  'The drift slot the sample belongs to (public.drift_slot_of). Part of the primary key, so a '
  'retried tick cannot write a second point for one moment.';
comment on column public.price_history.mid is
  'world.mid_price(port, good, stock) at sample time — the mid, before spread and tax, because the '
  'mid is the number that moves for reasons about the WORLD rather than about the port''s cut.';

-- A price that was true is not a secret: the same signed-in players who may read `port_goods`
-- through world.market() may read what it used to say. `anon` may read neither.
alter table public.price_history enable row level security;
create policy price_history_read on public.price_history for select to authenticated using (true);
grant select on public.price_history to authenticated;

-- ── THE SLOT, NAMED ────────────────────────────────────────────────────────────────────────────
create or replace function public.drift_slot_of(p_at timestamptz default now())
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select floor(extract(epoch from p_at) / public.wc_num('drift_slot_seconds'))::bigint;
$$;

comment on function public.drift_slot_of(timestamptz) is
  'THE ONE named answer to "which drift slot is it". 0010 computes the same expression inline and '
  'is deployed, so it cannot be re-cut to call this; 0013''s self-assert proves the two agree '
  'instead of assuming it.';

revoke all on function public.drift_slot_of(timestamptz) from public, anon, authenticated;

-- ── THE WRITER ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.tick_price_snapshot(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot  bigint := public.drift_slot_of(p_now);
  v_keep  int    := public.wc_int('price_history_slots');
  v_wrote int;
  v_pruned int;
begin
  -- ON CONFLICT DO NOTHING, not DO UPDATE: the first sample in a slot is the sample. A later call
  -- in the same slot must not move a point that a client may already have drawn.
  insert into public.price_history (port_id, good_id, slot, at, mid, stock)
  select pg.port_id,
         pg.good_id,
         v_slot,
         p_now,
         world.mid_price(pg.port_id, pg.good_id, pg.stock),
         pg.stock
    from public.port_goods pg
  on conflict (port_id, good_id, slot) do nothing;
  get diagnostics v_wrote = row_count;

  delete from public.price_history where slot <= v_slot - v_keep;
  get diagnostics v_pruned = row_count;

  return jsonb_build_object('slot', v_slot, 'wrote', v_wrote, 'pruned', v_pruned, 'keep', v_keep);
end $$;

comment on function public.tick_price_snapshot(timestamptz) is
  'Samples every (port, good) mid once per drift slot and prunes beyond price_history_slots. '
  'Idempotent by primary key, not by a remembered check.';

revoke all on function public.tick_price_snapshot(timestamptz) from public, anon, authenticated;

-- ── THE READ ───────────────────────────────────────────────────────────────────────────────────
-- ONE call per PORT, not one per good. A market screen draws a line on every row it shows; 70 goods
-- would be 70 round trips, and the client would then be the thing deciding how many points a line
-- has. The payload is keyed by good id, oldest point first, so a caller draws it left to right
-- without sorting.
create or replace function world.price_history(p_port uuid, p_slots int default 48)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_slots int := least(greatest(coalesce(p_slots, 48), 1), public.wc_int('price_history_slots'));
  v_from  bigint := public.drift_slot_of(now()) - v_slots + 1;
  v_out   jsonb;
begin
  if p_port is null then
    raise exception 'E_NO_SUCH_PORT: a price history needs a port' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_object_agg(g.code, g.points), '{}'::jsonb) into v_out
    from (
      select gd.code,
             jsonb_agg(jsonb_build_object('slot', h.slot, 'at', h.at, 'mid', round(h.mid, 2))
                       order by h.slot) as points
        from public.price_history h
        join public.goods gd on gd.id = h.good_id
       where h.port_id = p_port
         and h.slot >= v_from
       group by gd.code
    ) g;

  return jsonb_build_object(
    'port', p_port,
    'slots', v_slots,
    'slot_seconds', public.wc_int('drift_slot_seconds'),
    'goods', v_out);
end $$;

comment on function world.price_history(uuid, int) is
  'One port''s remembered mids, keyed by good CODE, oldest first. Carries slot_seconds so a client '
  'can label a time axis without knowing the tick cadence.';

revoke all on function world.price_history(uuid, int) from public, anon;
grant execute on function world.price_history(uuid, int) to authenticated;

-- ── WIND IT ────────────────────────────────────────────────────────────────────────────────────
-- 0012 owns "when a tick runs" and is deployed, so a fourth job cannot be added to it without
-- re-cutting it. This schedules its own, under 0012's naming convention and — importantly — with
-- the cadence DERIVED from the same knob through 0012's own `tick_cron_expression()`, so there is
-- still exactly one answer to "how often does the market step". 0012 unschedules `byeharu-voyage:%`
-- before it schedules, and it runs BEFORE this file, so re-applying the chain cannot orphan a job.
do $$
declare
  v_expr      text := public.tick_cron_expression(public.wc_int('drift_slot_seconds'));
  v_have_cron boolean;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_have_cron;

  if not v_have_cron then
    raise notice '0013: pg_cron is not available here, so the price snapshot was NOT scheduled — as expected under PGlite. The record stays empty until something calls public.tick_price_snapshot(); it would have run on "%".', v_expr;
    return;
  end if;

  perform cron.schedule('byeharu-voyage:price-snapshot', v_expr, 'select public.tick_price_snapshot()');
  raise notice '0013: pg_cron present — the price snapshot runs on "%" (from drift_slot_seconds = %), the same cadence the market steps on.',
    v_expr, public.wc_int('drift_slot_seconds');
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_pairs    int;
  v_slot_fn  bigint;
  v_slot_ck  bigint;
  v_drift    jsonb;
  v_s1       jsonb;
  v_s2       jsonb;
  v_rows1    int;
  v_rows2    int;
  v_hist     jsonb;
  v_points   int;
  v_first    numeric;
  v_moved    boolean;
  v_left     int;
  v_grants   int;
  v_anon_x   boolean;
  v_auth_x   boolean;
  v_rls      boolean;
  v_now      timestamptz := now();
begin
  -- Grants are a property of the objects, not of the probe, so they are read OUTSIDE the block
  -- that gets rolled back: a revoke that never happened must fail this migration, not vanish.
  v_anon_x := has_function_privilege('anon', 'world.price_history(uuid, int)', 'execute');
  v_auth_x := has_function_privilege('authenticated', 'world.price_history(uuid, int)', 'execute');
  if v_anon_x then raise exception '0013 self-assert FAIL: anon may execute world.price_history — the record is for signed-in captains'; end if;
  if not v_auth_x then raise exception '0013 self-assert FAIL: authenticated may NOT execute world.price_history — no client could draw a line'; end if;

  select relrowsecurity into v_rls from pg_class where oid = 'public.price_history'::regclass;
  if not v_rls then raise exception '0013 self-assert FAIL: RLS is not enabled on public.price_history'; end if;

  if has_function_privilege('authenticated', 'public.tick_price_snapshot(timestamptz)', 'execute') then
    raise exception '0013 self-assert FAIL: authenticated may execute tick_price_snapshot — a client could stuff the record';
  end if;

  -- The slot function must agree with the slot 0010 ITSELF reports. This is the whole reason the
  -- named authority is allowed to exist beside 0010's inline expression.
  v_slot_fn := public.drift_slot_of(v_now);
  v_drift := public.tick_market_drift(v_now);
  v_slot_ck := (v_drift->>'slot')::bigint;
  if v_slot_fn <> v_slot_ck then
    raise exception '0013 self-assert FAIL: drift_slot_of said % but tick_market_drift said % — two answers to "which slot is it"', v_slot_fn, v_slot_ck;
  end if;

  select count(*) into v_pairs from public.port_goods;
  if v_pairs = 0 then
    raise exception '0013 self-assert FAIL: there are no market rows to sample, so every check below would pass vacuously';
  end if;

  begin
    -- (a) one sample per (port, good), and the count is the market's own size — not a constant.
    v_s1 := public.tick_price_snapshot(v_now);
    v_rows1 := (v_s1->>'wrote')::int;
    if v_rows1 <> v_pairs then
      raise exception '0013 self-assert FAIL: sampled % row(s) from a market of % pair(s)', v_rows1, v_pairs;
    end if;

    -- (b) THE POSITIVE CONTROL FOR IDEMPOTENCE. A second call in the SAME slot must write nothing.
    --     Claimed one way, idempotence is half a claim; (a) proves it writes, this proves it stops.
    v_s2 := public.tick_price_snapshot(v_now);
    v_rows2 := (v_s2->>'wrote')::int;
    if v_rows2 <> 0 then
      raise exception '0013 self-assert FAIL: a repeat snapshot in the same slot wrote % more row(s) — the record is not keyed', v_rows2;
    end if;

    -- (c) the recorded mid is the DERIVED mid, to the cent — not an independently invented number.
    select h.mid into v_first
      from public.price_history h
     where h.slot = v_slot_fn
     order by h.port_id, h.good_id
     limit 1;
    if v_first is null then
      raise exception '0013 self-assert FAIL: nothing was recorded in slot %', v_slot_fn;
    end if;
    select abs(v_first - world.mid_price(h.port_id, h.good_id, h.stock)) < 0.0001 into v_moved
      from public.price_history h
     where h.slot = v_slot_fn
     order by h.port_id, h.good_id
     limit 1;
    if not v_moved then
      raise exception '0013 self-assert FAIL: the recorded mid is not world.mid_price of the recorded stock';
    end if;

    -- (d) the read serves a real port back, with points in it.
    select world.price_history(p.id, 48) into v_hist
      from public.ports p order by p.code limit 1;
    select count(*) into v_points
      from jsonb_each(v_hist->'goods') e,
           lateral jsonb_array_elements(e.value) pt;
    if v_points = 0 then
      raise exception '0013 self-assert FAIL: world.price_history returned no points for a port that was just sampled';
    end if;
    if (v_hist->>'slot_seconds')::int <> public.wc_int('drift_slot_seconds') then
      raise exception '0013 self-assert FAIL: the read reported slot_seconds % against a knob of %', v_hist->>'slot_seconds', public.wc_int('drift_slot_seconds');
    end if;

    -- (e) THE POSITIVE CONTROL FOR PRUNING. Age a row well past the retention window and require
    --     the next tick to remove it. A prune that never removed anything would look identical to
    --     a prune that works, on a table this young.
    insert into public.price_history (port_id, good_id, slot, at, mid, stock)
    select h.port_id, h.good_id, v_slot_fn - public.wc_int('price_history_slots') - 1, v_now, h.mid, h.stock
      from public.price_history h where h.slot = v_slot_fn order by h.port_id, h.good_id limit 1;

    perform public.tick_price_snapshot(v_now);
    select count(*) into v_left from public.price_history
     where slot <= v_slot_fn - public.wc_int('price_history_slots');
    if v_left <> 0 then
      raise exception '0013 self-assert FAIL: % row(s) older than the retention window survived the prune', v_left;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  select count(*) into v_left from public.price_history;
  if v_left <> 0 then
    raise exception '0013 self-assert FAIL: the probe left % history row(s) behind', v_left;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0013 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0013 self-assert ok: drift_slot_of() agrees with tick_market_drift on slot %; a snapshot wrote % row(s) — one per market pair — and a repeat call in the same slot wrote 0; the recorded mid IS world.mid_price of the recorded stock; world.price_history served % point(s) and reported slot_seconds %; a row aged past the % -slot window was pruned; probe rolled back leaving 0 rows; anon may not read the record and may not execute the tick; 0 client write grants',
    v_slot_fn, v_pairs, v_points, public.wc_int('drift_slot_seconds'), public.wc_int('price_history_slots');
end $$;
