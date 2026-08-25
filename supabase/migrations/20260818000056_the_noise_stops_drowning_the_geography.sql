-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0056 — THE NOISE STOPS DROWNING THE GEOGRAPHY
--        `drift_sigma` 0.04 -> 0.02. The market still moves; it stops paying more than the map
--        does. This SUPERSEDES the value migration 0001 seeded at 0001:159 and nothing else.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW: A GATE THAT WAS MEASURING THE WRONG THING ─────────────────────────────────────────
-- `scripts/db/proofs/05_first_voyage_balance.sql` has reported that a first voyage pays 12-18 per
-- cent of the stake since it was written, against a designed band of 4-16. On 2026-08-25 that
-- proof's market was pinned (migration-free, scripts/db/market-fixture.mjs) and the figure turned
-- out to be an artefact of the harness, not a fact about the game:
--
--   A FRESHLY APPLIED CHAIN IS NOT A LIVE WORLD. `public.tick_market_drift` (0010:107) steps every
--   price once per drift slot, and the chain's own self-asserts happen to call it about once while
--   applying. So a fresh apply has taken ONE step on the 14,980 market rows 0003 seeded and NONE
--   on the 39,468 that 0041 added: 72 per cent of its prices sit at exactly drift 0. Proof 05 was
--   measuring how many ticks the harness ran.
--
-- Driving the chain's OWN tick forward one slot at a time from a fresh apply (2026-08-25, PGlite
-- 0.5.5 / PostgreSQL 18.3) shows where a live world actually sits:
--
--     ticks (10 min each)     0       1       2       4       8      16      32
--     sd(drift)           0.0210  0.0442  0.0566  0.0706  0.0827  0.0890  0.0905
--     median voyage        13.2%   20.2%   21.1%   28.8%   32.5%   34.1%   35.2%
--
-- Every deployed world is at the right-hand end of that table within about two hours — `pg_cron`
-- winds the tick (0012) and `world.market()` winds it too on every read (0029). The walk is
-- heading for the Ornstein-Uhlenbeck stationary law, sd = sigma / sqrt(1 - theta^2)
-- = 0.04 / sqrt(1 - 0.81) = 0.0918: prices swinging +/- 9 per cent around their own mid, and a
-- first voyage — the best of ~243 goods against every port in a 600 nm radius — paying 37.4.
--
-- ── AND THE DECIDING NUMBER IS NOT THAT ONE ────────────────────────────────────────────────────
-- 37 per cent is over twice the designed pace, but a pace can be argued about. This cannot:
--
--     BALANCE_DISTANCE_PAYS   long legs (>800 nm)   short legs (<400 nm)   long / short
--     one drift step               10.80%                 3.26%              3.31x
--     the settled market           18.87%                16.19%              1.17x
--
-- This is a game about carrying goods from where they are made to where they are not. The reason
-- to cross an ocean is that the far quay pays more, and at sigma = 0.04 the noise had all but
-- erased that: sailing 800 nm was worth 17 per cent more than staying inside 400, where the world's
-- own geography makes it worth three and a third times as much. A knob that drowns the premise is
-- not a balance preference. That is what this migration is for; the pace coming back inside the
-- band is a consequence, not the goal.
--
-- ── THE MECHANISM, AND WHY sigma AND NOT SOMETHING ELSE ────────────────────────────────────────
-- `world.mid_price` (0005:355-360) multiplies by `(1 + drift)`, so `drift`'s amplitude IS the
-- price noise, and the balance statistic is a MAX over thousands of (good, destination) pairs of
-- noised gaps — which is dominated by that amplitude and by nothing else. Halving sigma halves the
-- stationary sd exactly: 0.02 / sqrt(1 - 0.81) = 0.0459.
--
-- WHAT WAS REJECTED, AND WHY:
--   * THE AFFINITY KNOBS (`affinity_*`, 0005). They author the gradient — the geography — and they
--     do not touch this. Migration 0041 flattened the gradient by 30 per cent on the sweep's own
--     statistic and proof 05's median barely moved (15.9 / 17.3 after). Measured again here: with
--     the drift taken out entirely, the authored economy pays 7.0 per cent, against the 7.5 that
--     0005:125 tuned it to. THE AUTHORED ECONOMY IS DOING EXACTLY WHAT IT WAS DESIGNED TO DO.
--     Everything above 7.5 was noise, and flattening the gradient to compensate would have made
--     the geography WORSE while leaving the printer running.
--   * WIDENING THE MARKET SPREAD. It taxes every unhaggled trader to chase a target, and
--     docs/DEV_LOG.md:613 already records that the brief's "a third of a voyage's margin" is
--     arithmetically impossible without doing exactly that. It also would not touch this number:
--     a round trip pays one spread, and spreads average 3.6 per cent against a 30-point overshoot.
--   * `drift_theta` INSTEAD OF `drift_sigma`. theta is the walk's MEMORY, not its size: cutting it
--     shrinks the stationary sd but also shortens the time constant (10 min / (1 - theta)), so the
--     market would flicker rather than wander. A price that changes character is a different
--     mechanic; a price with less noise in it is this one, quieter.
--   * `drift_clamp`. It is a guard rail, not an amplitude — at sigma 0.04 it bound on well under
--     one per cent of rows, so moving it changes almost nothing and turns a Gaussian into a wall.
--   * MOVING THE BAND INSTEAD AND LEAVING THE ECONOMY ALONE. That was the previous slice's
--     conclusion and it is superseded by this one: a band of 30-45 certifies the money printer
--     the proof exists to prevent, and no band at all restores the reason to leave home waters.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT TOUCH ─────────────────────────────────────────────────
-- ONE ROW OF ONE TABLE. Not `drift_theta`, not `drift_clamp`, not `drift_slot_seconds`, not a
-- spread knob, not an affinity knob, not a single stored price — `world.mid_price` derives every
-- price on read (0005), so the world re-prices itself the next time the tick runs and there is no
-- stored total anywhere to migrate. The self-assert below proves the "one row" claim rather than
-- asserting it in prose.
--
-- IT ALSO DOES NOT TOUCH THE FUNCTION. `public.tick_market_drift` reads `wc_num('drift_sigma')`
-- (0010:100) and is the one authority for the step; this file changes what it reads, never how it
-- steps, so nothing is re-cut and no grant moves.
--
-- ── THE BAND THAT JUDGES THIS MOVED IN THE SAME SLICE ──────────────────────────────────────────
-- `BALANCE_MEDIAN_IN_BAND` in scripts/db/proofs/05_first_voyage_balance.sql is set to the reality
-- this migration creates, in the same commit, so the knob and the band that judges it are never in
-- two states at once. `BALANCE_GRADIENT_IN_BAND` is measured on a FLAT market — amplitude 0, which
-- no sigma can scale — and is unchanged at 7.0 per cent inside 4-16. That was confirmed by
-- measurement, not assumed: see the table in that file's header.
--
-- Depends ONLY on: 0001 (world_config, wc_num), 0010 (tick_market_drift, drift_slot).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── THE CHANGE, AND THE SELF-ASSERT THAT PROVES IT ────────────────────────────────────────────
-- The write happens INSIDE the assert block, the way migration 0031 writes the world secret inside
-- its own. That is not tidiness: it is the only way to take a picture of the knob table BEFORE the
-- change and compare it with the one after, which is what turns "this migration moves exactly one
-- knob" from a sentence into a measurement. The first draft of this file asserted it from
-- `updated_at` instead, and `node scripts/db/breaktest-0056.mjs` walked straight through it — a
-- write that does not touch `updated_at` was invisible to it.
--
-- And it is not enough that the row says 0.02. What has to be true is that THE MARKET STEPS BY
-- 0.02, and that is measured here with the chain's own `public.tick_market_drift` — twice: once at
-- the new setting, and once with the old one restored, which is the POSITIVE CONTROL proving the
-- instrument can tell them apart. Both probes run inside a plpgsql block that unwinds itself, so
-- every row they touch is rolled back to the subtransaction's savepoint and only the number
-- escapes, carried out in the sentinel's message. The probe writes 54,432 rows twice and throws
-- both away; that is a few seconds, once, and it is the difference between reading a knob back and
-- watching it work.
do $$
declare
  k_probe    constant text    := 'PROBE ';
  k_old      constant numeric := 0.04;   -- what 0001:159 seeded, named because this refuses it
  k_new      constant numeric := 0.02;
  -- The two knobs this file DOES NOT TOUCH, named so that touching them is a red rather than a
  -- diff nobody reads. They are 0001's values and this migration leaves them exactly there.
  k_theta    constant numeric := 0.90;
  k_clamp    constant numeric := 0.25;
  v_sigma    numeric;
  v_theta    numeric;
  v_clamp    numeric;
  v_new_sd   numeric;
  v_old_sd   numeric;
  v_stat_new numeric;
  v_stat_old numeric;
  v_before   jsonb;
  v_after    jsonb;
  v_touched  int;
  v_key      text;
  v_zeroed   int;
begin
  -- ── 1. THE KNOB TABLE, BEFORE ───────────────────────────────────────────────────────────────
  select jsonb_object_agg(key, value) into v_before from public.world_config;

  update public.world_config
     set value       = to_jsonb(k_new),
         description = 'DESIGN G.1 OU step standard deviation. 0056: 0.04 -> 0.02. At 0.04 the '
                       'stationary law sd/sqrt(1-theta^2) reached 0.0918, and the price noise paid '
                       'more than the map did — a first voyage returned 37.4 per cent of the stake '
                       'and an 800 nm leg out-earned a 400 nm one by 17 per cent where the authored '
                       'geography makes it worth 3.3x. Measured, not argued; see 0056.',
         updated_at  = clock_timestamp()
   where key = 'drift_sigma';

  -- ── 2. THE ROW SAYS WHAT THE HEADER SAYS, AND THE OLD VALUE IS GONE ─────────────────────────
  v_sigma := public.wc_num('drift_sigma');
  v_theta := public.wc_num('drift_theta');
  v_clamp := public.wc_num('drift_clamp');
  if v_sigma <> k_new or v_sigma = k_old then
    raise exception '0056 self-assert FAIL: drift_sigma reads % — the update did not take (it must be %, and must no longer be 0001''s %)',
      v_sigma, k_new, k_old;
  end if;
  if v_theta <> k_theta or v_clamp <> k_clamp then
    raise exception '0056 self-assert FAIL: this file moves ONE knob and drift_theta reads % (must be %) / drift_clamp reads % (must be %) — the walk''s memory and its guard rail are not this migration''s to touch',
      v_theta, k_theta, v_clamp, k_clamp;
  end if;

  -- ── 3. ONE ROW OF ONE TABLE, BY COMPARISON AND NOT BY TIMESTAMP ─────────────────────────────
  -- Every key in either picture whose value differs from the other, in both directions, so an
  -- added or deleted knob counts too. A write that forgot to touch updated_at cannot hide here.
  select jsonb_object_agg(key, value) into v_after from public.world_config;
  select count(*), min(k) into v_touched, v_key
    from (
      select b.key as k from jsonb_each(v_before) b
       where b.value is distinct from (v_after -> b.key)
      union
      select a.key from jsonb_each(v_after) a
       where a.value is distinct from (v_before -> a.key)
    ) d;
  if v_touched <> 1 or v_key <> 'drift_sigma' then
    raise exception '0056 self-assert FAIL: % world_config row(s) differ across this migration (first: %) — it claims to move exactly one knob',
      v_touched, coalesce(v_key, '(none)');
  end if;

  -- ── 4. THE MARKET ACTUALLY STEPS BY 0.02 ────────────────────────────────────────────────────
  -- One OU step from a flat market has, by construction, standard deviation sigma. So: flatten,
  -- tick once through the game's own function, measure, and unwind.
  begin
    update public.port_goods set drift = 0, drift_slot = 0;
    get diagnostics v_zeroed = row_count;
    perform public.tick_market_drift(now());
    select stddev(drift) into v_new_sd from public.port_goods;
    raise exception 'PROBE %|%', v_new_sd, v_zeroed;
  exception when others then
    if left(sqlerrm, length(k_probe)) <> k_probe then raise; end if;
    v_new_sd := split_part(substr(sqlerrm, length(k_probe) + 1), '|', 1)::numeric;
    v_zeroed := split_part(substr(sqlerrm, length(k_probe) + 1), '|', 2)::int;
  end;
  if v_zeroed < 14000 then
    raise exception '0056 self-assert FAIL: the step probe only had % market row(s) to move, so it measured almost nothing', v_zeroed;
  end if;
  if v_new_sd < k_new * 0.9 or v_new_sd > k_new * 1.1 then
    raise exception '0056 self-assert FAIL: one tick from a flat market moved the world by sd %, not the % this knob now asks for — tick_market_drift is not reading drift_sigma',
      round(v_new_sd, 5), k_new;
  end if;

  -- ── 5. THE POSITIVE CONTROL — the same probe at the OLD setting must NOT pass step 4 ────────
  -- Without this, step 3 is a number with nothing to be compared against, and a probe that would
  -- have passed at either setting proves nothing about the change.
  begin
    update public.world_config set value = to_jsonb(k_old) where key = 'drift_sigma';
    update public.port_goods set drift = 0, drift_slot = 0;
    perform public.tick_market_drift(now());
    select stddev(drift) into v_old_sd from public.port_goods;
    raise exception 'PROBE %|', v_old_sd;
  exception when others then
    if left(sqlerrm, length(k_probe)) <> k_probe then raise; end if;
    v_old_sd := split_part(substr(sqlerrm, length(k_probe) + 1), '|', 1)::numeric;
  end;
  if public.wc_num('drift_sigma') <> k_new then
    raise exception '0056 self-assert FAIL: the control probe leaked — drift_sigma is % after it, not %',
      public.wc_num('drift_sigma'), k_new;
  end if;
  if v_old_sd >= k_new * 0.9 and v_old_sd <= k_new * 1.1 then
    raise exception '0056 self-assert FAIL: the old setting % measured sd % too, which is inside the window step 4 accepted — the probe cannot tell the two apart and proves nothing',
      k_old, round(v_old_sd, 5);
  end if;

  -- ── 6. WHAT THE PLAYER MEETS: the stationary law, halved, with the clamp still out of reach ──
  v_stat_new := k_new / sqrt(1 - power(v_theta, 2));
  v_stat_old := k_old / sqrt(1 - power(v_theta, 2));
  if round(v_stat_old / v_stat_new, 6) <> 2.0 then
    raise exception '0056 self-assert FAIL: the settled amplitude did not halve — % against %',
      round(v_stat_new, 5), round(v_stat_old, 5);
  end if;
  if v_clamp / v_stat_new < 3 then
    raise exception '0056 self-assert FAIL: the clamp % now stands at only % standard deviations of the settled law, so it would bite the ordinary market instead of guarding its tail',
      v_clamp, round(v_clamp / v_stat_new, 2);
  end if;

  raise notice '0056 self-assert ok: THE NOISE STOPS DROWNING THE GEOGRAPHY. drift_sigma is % (0001 seeded %, and this row is the ONLY world_config row this migration wrote); one tick of public.tick_market_drift from a flat market moved all % market rows by a measured sd of %, which is the knob and not a coincidence — the SAME probe with % restored measured % and would have failed the window step 4 accepted, and it leaked nothing, sigma still reading % afterwards; the settled Ornstein-Uhlenbeck amplitude the game runs at is therefore % where it was % (theta % unmoved, so the walk keeps its 100-minute memory and only its size changes), and drift_clamp % still stands % sd out at the tail where a guard rail belongs; no function was re-cut, no grant moved and no stored price exists to migrate',
    v_sigma, k_old, v_zeroed, round(v_new_sd, 5), k_old, round(v_old_sd, 5), public.wc_num('drift_sigma'),
    round(v_stat_new, 5), round(v_stat_old, 5), v_theta, v_clamp, round(v_clamp / v_stat_new, 1);
end $$;
