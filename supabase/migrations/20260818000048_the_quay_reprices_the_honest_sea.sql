-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0048 — THE QUAY REPRICES THE HONEST SEA
--        (cut as 0041 in the helm worktree against a 37-migration base; landed here as 0048,
--        after 0040/0041/0045 and the regenerated 0046/0047 — same knobs, same one function)
--        The affinity gradient is retuned to the free sea's honest distances: the same knobs, new
--        values, and every derived affinity recomputed through the ONE function that seeded it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ────────────────────────────────────────────────────────────────────────────────────────
-- 0046/0047 made every sailed distance HONEST — and honest water reaches better-paying markets
-- than the old 782-leg graph did within the same first-voyage horizon. Proof 05's median
-- first-voyage return, tuned to 13.5-14.8% under the graph (DEV_LOG D21), measured 14.7-17.8%
-- across runs under the free sea, straddling the 4-16 band's ceiling. The band is the design;
-- the knobs are the sanctioned lever (D11/D21 precedent); the sweep is the evidence:
--
--   scripts/db/tune-balance.mjs, 2026-08-24, repointed to the SAME 600 nm honest reach the proof
--   measures (14 top-tier ports, best opening voyage priced through world.quote):
--
--     knobs                                              median   p25    p75   worst   best
--     prod 0.92 home 0.99 span 0.85 reach 9000 curve 0.80   8.9%   7.6%   9.7%   5.0%  10.3%   <- current (D21)
--     prod 0.92 home 1.00 span 0.80 reach 9000 curve 0.85   8.4%   7.1%   9.1%   4.7%   9.8%
--     prod 0.93 home 1.00 span 0.76 reach 9500 curve 0.88   6.2%   5.1%   7.1%   3.1%   7.7%   <- CHOSEN
--     prod 0.94 home 1.00 span 0.72 reach 9500 curve 0.90   4.7%   4.0%   5.5%   2.0%   6.1%
--
--   The sweep's metric and the proof's differ in sampling and drift, so the mapping is by RELATIVE
--   delta: proof 05 measured medians of 14.6 / 14.7 / 15.2 / 15.5 / 16.8 / 17.8 across six full
--   runs at the current knobs (mean ~15.8, ~40%% of runs over the 16 ceiling); the chosen row is
--   -30%% relative in the sweep, which lands the proof's spread at roughly 10-12.5 - mid-band,
--   with the run-to-run lottery no longer able to cross either edge.
--
-- The chosen row lands the sweep's median at mid-band with the whole inter-quartile range inside
-- 4-16, which is what survives the proof's own run-to-run lottery (market drift varies with the
-- boot instant; the note in docs/OWNER_REQUESTS.md's KNOWN table records that pre-existing
-- non-determinism).
--
-- ── WHAT MOVES, AND WHAT DELIBERATELY DOES NOT ─────────────────────────────────────────────────
--   * The five affinity knobs (0005's), by UPDATE — 0005 itself is applied history and is not
--     edited (docs/NO_SPAGHETTI.md §3).
--   * Every port_goods.affinity, recomputed through world.affinity_for — THE function the seed
--     used, so the world cannot drift from its own rule. stock_target follows affinity (0005's
--     own formula), and stock is CLAMPED down to a fallen target, never re-seeded upward: on a
--     live world, stock is player-made state and a reprice must not mint goods.
--   * drift is NOT reset: it is live market state, a walk around zero, and zeroing it would move
--     every price at once for no reason the ledger could name.
--
-- Depends on: 0001 (knobs), 0005 (affinity_for, port_goods), 0041 (the grown catalogue these
-- knob values were already reconciled against at D21 values; this file moves them to the
-- honest-sea values), 0046/0047 (the honest distances that made the retune necessary).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config set value = to_jsonb(0.93::numeric)  where key = 'affinity_producer';
update public.world_config set value = to_jsonb(1.00::numeric)  where key = 'affinity_home';
update public.world_config set value = to_jsonb(0.76::numeric)  where key = 'affinity_span';
update public.world_config set value = to_jsonb(9500::numeric)  where key = 'affinity_reach_nm';
update public.world_config set value = to_jsonb(0.88::numeric)  where key = 'affinity_curve';

update public.port_goods pg
   set affinity = world.affinity_for(pg.port_id, pg.good_id);

update public.port_goods pg
   set stock_target = greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity))),
       stock        = least(pg.stock, greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity))))
  from public.ports p
 where p.id = pg.port_id;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_n   int;
  v_bad int;
begin
  -- (a) the knobs read back as exactly what this file set — a knob that did not land would leave
  --     the recompute below rewriting the same world it found.
  if public.wc_num('affinity_producer') is distinct from 0.93::numeric
     or public.wc_num('affinity_home') is distinct from 1.00::numeric
     or public.wc_num('affinity_span') is distinct from 0.76::numeric
     or public.wc_num('affinity_reach_nm') is distinct from 9500::numeric
     or public.wc_num('affinity_curve') is distinct from 0.88::numeric then
    raise exception '0048 self-assert FAIL: the knobs did not land (% / % / % / % / %)',
      public.wc_num('affinity_producer'), public.wc_num('affinity_home'),
      public.wc_num('affinity_span'), public.wc_num('affinity_reach_nm'),
      public.wc_num('affinity_curve');
  end if;

  -- (b) EVERY stored affinity equals the one function, over the WHOLE table — non-vacuous by the
  --     count itself.
  select count(*) into v_n from public.port_goods;
  if v_n < 1000 then
    raise exception '0048 self-assert FAIL: only % port_goods row(s) — the world is not here', v_n;
  end if;
  select count(*) into v_bad
    from public.port_goods pg
   where pg.affinity is distinct from world.affinity_for(pg.port_id, pg.good_id);
  if v_bad <> 0 then
    raise exception '0048 self-assert FAIL: % of % affinities disagree with world.affinity_for', v_bad, v_n;
  end if;

  -- (c) no stock was minted: every stock is at or under its (possibly new) target… except where
  --     drift regeneration already held it above a FALLEN target, which the clamp above ends.
  select count(*) into v_bad from public.port_goods where stock > stock_target;
  if v_bad <> 0 then
    raise exception '0048 self-assert FAIL: % row(s) hold stock above target — the reprice minted goods', v_bad;
  end if;

  -- (d) the gradient still slopes the right way: a producer is cheaper than a non-producer,
  --     asserted on the world's own rows rather than on a seed (README §3).
  select count(*) into v_bad
    from (select pg.good_id,
                 min(pg.affinity) filter (where exists (select 1 from public.port_specialties sp
                                                         where sp.port_id = pg.port_id and sp.good_id = pg.good_id)) as prod_min,
                 max(pg.affinity) as world_max
            from public.port_goods pg group by pg.good_id) x
   where x.prod_min is not null and x.prod_min >= x.world_max;
  if v_bad <> 0 then
    raise exception '0048 self-assert FAIL: % good(s) are no cheaper at their producer than anywhere else — the gradient is gone', v_bad;
  end if;

  raise notice '0048 self-assert ok: the affinity gradient is retuned to the honest sea (producer 0.93 / home 1.00 / span 0.76 / reach 9500 / curve 0.88), all % derived affinities recomputed through the one seeding function and none disagree, no stock minted, and every produced good is still cheaper at a source than at the far end of the world. Balance is measured, not argued: the sweep behind these values is in the header, and proof 05 re-measures the median on every run',
    v_n;
end $$;
