// ═══════════════════════════════════════════════════════════════════════════════════════════════
// market-fixture.mjs — THE ONE AUTHORITY FOR "PIN THE MARKET SO A MEASUREMENT MEANS SOMETHING"
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS FILE EXISTS
//   `public.tick_market_drift` (0010:107) moves every price by `random()`, DELIBERATELY — "a market
//   a player could replay would be a market a player could front-run." Every `db:apply` therefore
//   builds a DIFFERENT market, and the chain's own self-asserts call the tick while applying. Any
//   proof or spec that measures the economy is measuring whatever that apply happened to deal it.
//
//   That is not a small effect. Measured (docs/OWNER_REQUESTS.md:99): zero the drift and proof 05's
//   median first voyage drops from ~15 to 8.8 per cent, because the statistic is a MAX over ~243
//   goods x ~8 ports of drift-noised gaps — a max over thousands of draws is dominated by the noise
//   amplitude, not by any affinity knob. So the drift is most of the number, and an unpinned drift
//   is most of the variance.
//
//   The consequence is a gate that cries wolf: an unchanged chain has measured 15.1 / 9.0 / 12.4 /
//   14.4 / 12.4 / 12.1 / 16.2 / 18.3 / 14.1 against a 4-16 band (docs/RESUME.md, and twice again on
//   2026-08-25). A red that means "bad roll" as often as it means "bad balance" gets scrolled past,
//   and then it gates nothing at all.
//
// WHAT IT DOES — REPLACE THE DRIFT, NEVER REMOVE IT
//   Pinning drift to ZERO was tried in proof 04 and is recorded there as WRONG: the quay names 36
//   routes out of Lisboa on a drifted market and 20 on a flat one, so a flat market is not "the
//   economy without noise", it is an economy with less trade in it than the game ever has.
//
//   So every row is REDRAWN from the distribution the real process settles into — the OU stationary
//   law N(0, sigma / sqrt(1 - theta^2)), clamped exactly as 0010 clamps it — by Box-Muller over
//   `voyage.rng_raw`, which is IMMUTABLE and takes its seed AS AN ARGUMENT (0006:113), so calling it
//   with a fixture's own secret discloses nothing about the world's. Both knobs are READ, never
//   retyped: retuning the economy retunes the fixture with it.
//
//   AMPLITUDE 1 IS "THE MARKET A LIVE WORLD SITS IN", AND THAT IS A MEASUREMENT, NOT AN OPINION.
//   Driving the chain's OWN `public.tick_market_drift` forward one slot at a time from a freshly
//   applied world (2026-08-25, PGlite 0.5.5 / PostgreSQL 18.3), the drift's standard deviation and
//   proof 05's median first voyage go:
//
//     ticks (10 min each)     0       1       2       4       8      16      32
//     sd(drift)           0.0210  0.0442  0.0566  0.0706  0.0827  0.0890  0.0905
//     median voyage        13.2%   20.2%   21.1%   28.8%   32.5%   34.1%   35.2%
//
//   sigma / sqrt(1 - theta^2) = 0.04 / sqrt(1 - 0.9^2) = 0.0918 is where that walk is heading, and
//   it is there within a couple of hours of the clock running. A freshly applied chain is NOT that
//   world: it has taken about one step on the 14,980 rows migration 0003 seeded and NONE at all on
//   the 39,468 that 0041 added, so 72 per cent of its market rows sit at exactly drift 0. Measuring
//   the balance there measures how many ticks an apply happened to run — an artefact of the
//   harness, not a property of the game.
//
//   THE KEY IS THE AUTHORED CODE, NOT THE ROW ID. `ports.id` and `goods.id` are `gen_random_uuid()`
//   (0003), so a draw keyed on them is another random number wearing a seed's clothes. `ports.code`
//   and `goods.code` are authored ('LIS', 'silver'), so a draw keyed on them is the same market on
//   every run, on every machine, and after any rebuild.
//
//   AND THE SLOT IS PINNED FORWARD. `world.market()` winds the drift before pricing (0029), so a
//   read that lands in a later slot than the fixture would REDRAW all 14,980 rows and destroy it.
//   Proof 04 pinned the slot to `now()`, which holds only until the next 10-minute boundary — long
//   enough for a proof that runs in seconds, not for a Playwright spec that spends two minutes
//   building the world first. This pins it `p_hold` ahead (a day by default), so the wind is a
//   no-op for the whole life of the measurement whatever the wall clock does.
//
//   STOCK IS PINNED TOO, to `stock_target`. Regeneration is a function of `world.game_day(now())`,
//   so how full a port is depends on the wall clock at apply time — and that moves every price
//   through the elasticity term and decides whether a queued cargo can fill at all. `stock_target`
//   is the equilibrium the regeneration pulls toward: a DEFINED state of the world rather than an
//   arbitrary one.
//
// WHAT IT DOES NOT DO
//   It does not touch hazards, fairs, officers, or any knob. It is the MARKET's ambient and nothing
//   else. A caller that needs the weather held still says so itself, in its own file.
//
// IT IS A FIXTURE, NEVER A MIGRATION. It lives in scripts/ (schema `proof`, like
// `scripts/db/proof-courses.mjs` and the Supabase preamble), so the Supabase CLI — which only ever
// reads supabase/migrations/ — cannot deploy it.
//
// CALLERS: scripts/db/proof.mjs installs it for every proof; proofs 04 and 05 call it, and so does
// tests/rpc.firstSession.spec.ts. Each caller passes ITS OWN key, so each measures its own draw and
// none can move another's numbers.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/**
 * Create `proof.pin_market(...)` on an applied chain.
 *
 * @param {{exec: (sql: string) => Promise<unknown>, query: (sql: string, params?: unknown[]) => Promise<{rows: Record<string, unknown>[]}>}} db
 */
export async function installMarketFixture(db, { log = () => {} } = {}) {
  await db.exec(`
    create schema if not exists proof;

    create or replace function proof.pin_market(
      p_key    uuid,                                -- this draw's voyage key
      p_secret text,                                -- ... and its secret; rng_raw takes it as an
                                                    --     argument, so nothing about the world's
                                                    --     own secret is involved or disclosed
      p_a      text    default 'u1:',               -- stream prefix for the first uniform
      p_b      text    default 'u2:',               -- ... and the second
      p_hold   interval default interval '1 day',   -- how far ahead to park the drift slot
      p_amp    numeric default 1.0                  -- multiple of the stationary sd; 0 = flat
    )
    returns jsonb
    language plpgsql
    as $fx$
    declare
      v_rows      int;
      v_nonzero   int;
      v_distinct  int;
      v_behind    int;
      v_stock_off int;
      v_sd        numeric;
    begin
      -- THE DRIFT: every row redrawn from the OU stationary law, clamped as 0010 clamps it.
      -- p_amp scales the amplitude: 1 is the law the process settles into, 0 is a flat market.
      -- Nothing else about the fixture changes with it, which is what makes the two comparable.
      update public.port_goods pg
         set drift_slot = public.drift_slot_of(now() + p_hold),
             drift = greatest(-public.wc_num('drift_clamp'),
                       least(public.wc_num('drift_clamp'),
                         round((p_amp * (public.wc_num('drift_sigma')
                                / sqrt(1 - power(public.wc_num('drift_theta'), 2)))
                               * sqrt(-2 * ln(greatest(
                                   voyage.rng_raw(p_key, 0, p_a || p.code || ':' || g.code, p_secret),
                                   1e-12)))
                               * cos(2 * pi() * voyage.rng_raw(
                                   p_key, 1, p_b || p.code || ':' || g.code, p_secret)))::numeric,
                               6)))
        from public.ports p, public.goods g
       where p.id = pg.port_id and g.id = pg.good_id;
      get diagnostics v_rows = row_count;

      -- THE STOCK: the equilibrium regeneration pulls toward, rather than whatever the clock dealt.
      update public.port_goods set stock = stock_target, last_regen_day = world.game_day();

      select count(*) filter (where drift <> 0), count(distinct drift),
             count(*) filter (where drift_slot < public.drift_slot_of(now())),
             count(*) filter (where stock <> stock_target), round(stddev(drift), 6)
        into v_nonzero, v_distinct, v_behind, v_stock_off, v_sd
        from public.port_goods;

      -- A FIXTURE THAT HAS SILENTLY STOPPED APPLYING IS WORSE THAN NONE (docs/CORE_REUSE.md:1443).
      -- It must have touched every row, left nothing behind the current drift slot for 0029's
      -- wind to redraw, and pinned the stock it said it pinned — and at a non-zero amplitude it
      -- must have produced a SPREAD of real values rather than an all-zero or all-clamped market.
      -- At p_amp = 0 the same assert runs INVERTED: a flat market must be exactly flat, or the
      -- comparison it exists for is between two drifted markets and says nothing.
      if v_rows < 14000 or v_behind <> 0 or v_stock_off <> 0
         or (p_amp <> 0 and (v_nonzero < 14000 or v_distinct < 1000))
         or (p_amp = 0 and v_nonzero <> 0) then
        raise exception 'proof.pin_market FAILED to model the market it was asked for (amplitude %): % row(s) touched, % non-zero, % distinct value(s), % behind the current drift slot, % row(s) off stock_target',
          p_amp, v_rows, v_nonzero, v_distinct, v_behind, v_stock_off;
      end if;

      return jsonb_build_object('rows', v_rows, 'nonzero', v_nonzero, 'distinct', v_distinct,
                                'stddev', v_sd, 'amplitude', p_amp,
                                'slot', public.drift_slot_of(now() + p_hold));
    end $fx$;
  `)

  // The installer proves the function works before anything trusts it — inside a transaction it
  // throws away, so installing the fixture never changes the world the proofs then measure.
  await db.exec('begin;')
  let receipt
  try {
    const r = await db.query(
      `select proof.pin_market('00000000-0f00-4000-8000-00000000000f'::uuid, 'install-probe') as r`,
    )
    receipt = r.rows[0].r
  } finally {
    await db.exec('rollback;')
  }
  log(
    `market-fixture: proof.pin_market installed — probe redrew ${receipt.rows} row(s), ` +
      `${receipt.distinct} distinct drift value(s), sd ${receipt.stddev} (rolled back)`,
  )
  return receipt
}
