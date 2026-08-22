-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0024 — A BARGAIN WORTH STRIKING
--        0022 built the negotiation and tuned it to a rounding error. Three magnitudes move and
--        NOTHING else does: the shape, the odds, the hardening, the opt-in and the floor all stay
--        exactly as 0022 built them.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE MEASUREMENT THAT FORCED IT ──────────────────────────────────────────────────────────────
-- Driven in a real browser against the live client, Lisbon, alum, published spread 2.6%, no purser:
--
--     BUY 40:   before 5,283 d.  ·  one win 5,274 d.  ·  bargained to the cap 5,264 d.
--               = 19 ducats on 40 tuns. 0.36 per cent.
--
-- Three finite, hardening attempts that save a third of a per cent read as broken, not as subtle.
-- The mayor's untouchable 3% tax is larger than the entire spread being bargained over.
--
-- ── WHAT ACTUALLY BINDS, WHICH IS NOT WHAT IT LOOKED LIKE ──────────────────────────────────────
-- The brief said the floor binds before the concession cap ever does. Measured, that is true only
-- WITH a purser aboard, and the browser figure above has none:
--
--     haggling alone at the cap   executed = spread x (1 - 0.30) = 0.70 x spread
--     the floor                            = spread x 0.55
--     0.70 > 0.55, so for an unpursered house the FLOOR NEVER ENTERS IT.
--
-- What bound that 0.36 per cent was `haggle_concession_max` = 0.30 and the thinness of the spread.
-- So all three magnitudes move together: the cap, the step that reaches it, and the floor that
-- would otherwise start clipping the moment the cap grew past 0.45.
--
-- ── AND THE PART OF THE BRIEF THAT CANNOT BE DELIVERED, SAID PLAINLY ───────────────────────────
-- The target was "a fifth to a third of a voyage's margin", against a median first voyage of
-- 12-14 per cent of stake. Measured over all 214 ports (PGlite 0.5.5 / PostgreSQL 18.3,
-- 2026-08-23): published spreads run 0.0240 to 0.0460 and average 0.0384. A house pays half the
-- spread on each leg, so a round trip pays one whole spread, and a bargain worth a fraction `c` of
-- it saves `c x spread` of the stake. Therefore:
--
--     THE ABSOLUTE CEILING, at c = 1.0 with no floor at all — the quay keeping NOTHING —
--     is 3.84 per cent of stake, which is 30 per cent of a 13 per cent voyage.
--
--     "a fifth"  (2.6% of stake) needs c = 0.68   -> reachable
--     "a third"  (4.3% of stake) needs c = 1.12   -> IMPOSSIBLE. It is more than the whole spread.
--
-- So the lower half of the target is reachable and the upper half is not, at ANY setting of these
-- knobs. This file takes it to c = 0.75, which is 22 per cent of a 13 per cent voyage — just over
-- a fifth, and near enough the ceiling that the remaining headroom is not worth the quay keeping
-- nothing.
--
-- **IF THE OWNER WANTS THE FULL THIRD, THE SPREAD ITSELF IS THE THING TO CHANGE, AND THAT IS A
-- DIFFERENT DECISION FROM THIS ONE.** Measured projection: `spread_base` 0.06 -> 0.09 would put
-- the average spread at 5.76 per cent, and a 0.75 bargain then worth 4.32 per cent of stake — 33
-- per cent of a 13 per cent voyage, target met. But every UNHAGGLED round trip would also pay 1.92
-- more points of spread, so the median first voyage falls about two points toward the bottom of
-- `BALANCE_MEDIAN_IN_BAND`'s 4-16 band. That is a real economy retune that makes trading costlier
-- for every house in order to make one optional mechanic feel bigger, and it is the owner's call,
-- not a side effect of a haggling tune. This file does not touch `spread_base`.
--
-- ── THE THREE NUMBERS, AND WHY EACH ─────────────────────────────────────────────────────────────
--     haggle_concession_step  0.15 -> 0.25   Three attempts x 0.25 lands EXACTLY on the cap, so
--                                            every one of the day's attempts is worth taking and
--                                            none is wasted. That is asserted below, not arranged.
--     haggle_concession_max   0.30 -> 0.75   c = 0.75 x avg spread 0.0384 = 2.88% of stake per
--                                            round trip = 22% of a 13% voyage.
--     haggle_spread_floor_frac 0.55 -> 0.20  At 0.55 the floor would clip anything past c = 0.45
--                                            and the new cap would be dead on arrival. At 0.20 it
--                                            still does its job: haggling ALONE at the cap executes
--                                            at 0.25 x spread and is NOT clipped, while a purser
--                                            at the officer cap on top gives 0.75 x 0.25 = 0.1875,
--                                            which IS clipped to 0.20. The floor still fires, on
--                                            exactly the case it was written for — the stack — and
--                                            never on the mechanic alone.
--
-- Measured effect, same 8 ports the brief's figure came from (avg spread 0.0303):
--
--     one win            0.455%  ->  0.758% of stake per round trip
--     bargained to cap   0.910%  ->  2.275%
--     with a purser too  1.365%  ->  2.427%
--
-- and the browser case reprojected: Lisbon alum BUY 40, one win saves 10 d. -> 17 d., bargained to
-- the cap 21 d. -> 48 d. On the round trip that is roughly 96 d. on a 5,283 d. stake.
--
-- ── WHAT DOES NOT MOVE, AND IT IS ASSERTED RATHER THAN PROMISED ────────────────────────────────
--   * Still THREE attempts a day (`haggle_attempts_per_day`), still hardening by 0.25 per refusal,
--     still a base chance of 0.45 clamped at 0.85, still keyed on the attempt index so a retry
--     costs a chance, still opt-in, still capped by a floor, still composing MULTIPLICATIVELY with
--     the purser rather than summing. Every one of those knobs is read back below and required
--     unchanged against a pre-image.
--   * THE UNHAGGLED ECONOMY IS BYTE-IDENTICAL. A knob change must not move a price for a house
--     that never bargains, and that is proven the 0022 way: real quotes captured through the
--     current path before the update and re-taken after, requiring zero drift.
--   * `BALANCE_MEDIAN_IN_BAND` (4-16%) measures the UNHAGGLED median and is therefore untouched.
--     What changes is what a bargained trader sits at: a 12-14 per cent voyage bargained on both
--     legs becomes roughly 15-17 per cent, which is AT or JUST OVER the top of that band. That is
--     stated rather than absorbed: the band is a claim about the economy every house gets, and a
--     house that spends three finite attempts to sit at the top of it is the mechanic working.
--
-- ── THIS MIGRATION NEITHER GRANTS NOR REVOKES ──────────────────────────────────────────────────
-- Three `update public.world_config` statements and a self-assert. Nothing is created, no ACL is
-- touched, so the pooler path would carry it — but it is chained behind 0018/0022/0023, which do
-- need the Management API.
--
-- Depends ONLY on: 0001 (world_config, wc_num), 0015 (fleet_officer_bonus), 0022 (the mechanic and
--                  world.spread_effective).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE TWO PRE-IMAGES. Real quotes through the CURRENT pricing path, and the knob values as they
-- stand, so both halves of the claim — "prices did not move" and "the magnitudes did" — are
-- comparisons rather than sentences. Scaffolding; both dropped at the foot of this file.
create temporary table quote_before_0024 as
  select pg.port_id, pg.good_id, s.side, s.qty, q.units, q.total, q.avg_price, q.end_stock
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 40) pg
   cross join (values ('buy'::text, 10::numeric), ('buy', 130), ('sell', 25)) as s(side, qty)
   cross join lateral world.quote(pg.port_id, pg.good_id, s.qty, s.side) q;

create temporary table knobs_before_0024 as
  select key, (value)::text::numeric as value from public.world_config
   where key like 'haggle\_%' or key = 'officer_bonus_cap_pct';

update public.world_config
   set value = to_jsonb(0.25),
       description = 'What one won bargain shaves off the port''s spread, as a fraction of it. '
                     'THREE attempts times this lands exactly on haggle_concession_max, so every '
                     'attempt of the day is worth taking and none is wasted (0024). Supersedes '
                     '0022''s 0.15, which made a full bargain worth 0.36 per cent of a trade.',
       updated_at = now()
 where key = 'haggle_concession_step';

update public.world_config
   set value = to_jsonb(0.75),
       description = 'The most an open bargain may be worth, as a fraction of the port''s spread. '
                     '0.75 x the world average spread of 0.0384 is 2.88 per cent of the stake over '
                     'a round trip, which is 22 per cent of a median 13 per cent voyage (0024). '
                     'The ceiling for ANY value here is the whole spread — 3.84 per cent of stake, '
                     '30 per cent of a voyage — so a bigger negotiation needs a wider spread, not '
                     'a bigger cap.',
       updated_at = now()
 where key = 'haggle_concession_max';

update public.world_config
   set value = to_jsonb(0.20),
       description = 'The executed spread may never fall below this fraction of the port''s '
                     'published spread, whatever the purser and the bargain stack to. At 0024''s '
                     'cap, haggling ALONE executes at 0.25 x spread and is not clipped; a purser '
                     'at the officer cap on top gives 0.1875 and IS clipped to this. The floor '
                     'fires on the STACK, which is what it was written for, and never on the '
                     'mechanic by itself. Supersedes 0022''s 0.55, which would have clipped '
                     'anything past a concession of 0.45 and left the new cap dead on arrival.',
       updated_at = now()
 where key = 'haggle_spread_floor_frac';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_drift    int;
  v_rows     int;
  v_step_old numeric;
  v_cap_old  numeric;
  v_flr_old  numeric;
  v_step     numeric := public.wc_num('haggle_concession_step');
  v_cap      numeric := public.wc_num('haggle_concession_max');
  v_flr      numeric := public.wc_num('haggle_spread_floor_frac');
  v_tries    int     := public.wc_int('haggle_attempts_per_day');
  v_offcap   numeric := public.wc_num('officer_bonus_cap_pct');
  v_purser   numeric;
  v_avg      numeric;
  v_old_pct  numeric;
  v_new_pct  numeric;
  v_stack    numeric;
  v_moved    int;
  v_same     int;
  f_noop     boolean := false;
  f_moved    boolean := false;
  f_shape    boolean := false;
  f_exact    boolean := false;
  f_bigger   boolean := false;
  f_floor    boolean := false;
begin
  -- (a) THE UNHAGGLED ECONOMY DID NOT MOVE. No house in this transaction holds a bargain, so every
  --     quote must come back identical. A knob change that moved a price for somebody who never
  --     bargains would be a balance change smuggled in as a tune.
  select count(*) into v_rows from quote_before_0024;
  if v_rows < 60 then
    raise exception '0024 self-assert FAIL: the quote pre-image holds only % row(s); the no-op comparison would be nearly vacuous', v_rows;
  end if;
  select count(*) into v_drift
    from quote_before_0024 b
    cross join lateral world.quote(b.port_id, b.good_id, b.qty, b.side) a
   where (a.units, a.total, a.avg_price, a.end_stock)
         is distinct from (b.units, b.total, b.avg_price, b.end_stock);
  if v_drift = 0 then f_noop := true; end if;

  -- (b) AND THE MAGNITUDES DID MOVE — read from the pre-image, never typed as literals here.
  select value into v_step_old from knobs_before_0024 where key = 'haggle_concession_step';
  select value into v_cap_old  from knobs_before_0024 where key = 'haggle_concession_max';
  select value into v_flr_old  from knobs_before_0024 where key = 'haggle_spread_floor_frac';
  if v_step > v_step_old and v_cap > v_cap_old and v_flr < v_flr_old then f_moved := true; end if;

  -- (c) THE SHAPE IS UNTOUCHED. Every OTHER haggling knob, and the officer cap this composes with,
  --     must read exactly what it read before. This is the assert that stops a "balance pass"
  --     quietly becoming a redesign.
  select count(*) into v_same
    from knobs_before_0024 b
   where b.key not in ('haggle_concession_step', 'haggle_concession_max', 'haggle_spread_floor_frac')
     and b.value = public.wc_num(b.key);
  select count(*) into v_moved
    from knobs_before_0024 b
   where b.key not in ('haggle_concession_step', 'haggle_concession_max', 'haggle_spread_floor_frac');
  if v_same = v_moved and v_moved >= 4 then f_shape := true; end if;

  -- (d) THREE ATTEMPTS LAND EXACTLY ON THE CAP. Asserted, so it stays true if anyone retunes: an
  --     attempt that cannot improve the bargain is an attempt the player is invited to waste.
  if v_step * v_tries = v_cap then f_exact := true; end if;

  -- (e) THE MECHANIC IS ACTUALLY WORTH MORE NOW, MEASURED OVER THE WHOLE WORLD RATHER THAN
  --     ARGUED. A round trip pays one whole spread, so a bargain of `c` saves `c x spread` of the
  --     stake. Both figures are recomputed here — the old from the PRE-IMAGE knobs — so this is a
  --     before-and-after and not a number somebody remembered.
  select avg(world.spread(id)) into v_avg from public.ports;
  v_old_pct := (v_avg - greatest(v_avg * v_flr_old, v_avg * (1 - v_cap_old))) * 100;
  v_new_pct := (v_avg - greatest(v_avg * v_flr,     v_avg * (1 - v_cap)))     * 100;
  -- At least twice what it was, and inside a band that says what "felt but not dominant" means:
  -- 2 to 3.5 per cent of stake, against a median first voyage of 12-14 per cent.
  if v_new_pct >= 2 * v_old_pct and v_new_pct between 2.0 and 3.5 then f_bigger := true; end if;

  -- (f) AND THE FLOOR STILL FIRES ON THE STACK, AND STILL NOT ON THE MECHANIC ALONE. Both halves:
  --     a floor that clipped haggling by itself would make the new cap a lie, and a floor that
  --     clipped nothing at all would be decoration.
  v_purser := 1 - v_offcap / 100.0;
  v_stack  := v_purser * (1 - v_cap);
  if v_stack < v_flr and (1 - v_cap) > v_flr then f_floor := true; end if;

  if not f_noop then
    raise exception '0024 self-assert FAIL: % of % pre-image quote(s) moved for a house holding no bargain. A knob change may not touch the economy of somebody who never haggles', v_drift, v_rows;
  end if;
  if not f_moved then
    raise exception '0024 self-assert FAIL: the magnitudes did not move — step % -> %, cap % -> %, floor % -> %. This file would then be asserting a tune it never made', v_step_old, v_step, v_cap_old, v_cap, v_flr_old, v_flr;
  end if;
  if not f_shape then
    raise exception '0024 self-assert FAIL: % of % untouched knob(s) still read what they did before; a balance pass has changed the shape of the mechanic', v_same, v_moved;
  end if;
  if not f_exact then
    raise exception '0024 self-assert FAIL: % attempt(s) x a step of % is %, which is not the cap of %; one of the day''s attempts cannot improve the bargain and is a wasted tap', v_tries, v_step, v_step * v_tries, v_cap;
  end if;
  if not f_bigger then
    raise exception '0024 self-assert FAIL: a fully bargained round trip is worth % per cent of the stake against % per cent before; it must be at least twice the old figure and inside 2.0-3.5 per cent', round(v_new_pct, 3), round(v_old_pct, 3);
  end if;
  if not f_floor then
    raise exception '0024 self-assert FAIL: the floor of % either clips haggling on its own (executed %) or no longer clips the stack (%), so it is a lie in one direction or decoration in the other', v_flr, 1 - v_cap, v_stack;
  end if;

  raise notice '0024 self-assert ok: haggling is worth striking — a bargain at the cap now saves % per cent of the stake over a round trip against % per cent before (%x), measured across all % ports whose published spreads average %; that is % per cent of a median 13 per cent voyage, and the CEILING for any setting of these knobs is the whole spread — % per cent of stake, % per cent of a voyage — so "a third of a voyage" is arithmetically out of reach and needs a wider spread_base, which this file deliberately does not touch; the unhaggled economy is BYTE-IDENTICAL across % real quotes taken before the update, of which % moved; the shape is untouched — % other knob(s) read exactly what they read before, still % attempts, still hardening, still opt-in, still multiplicative; % x % lands EXACTLY on the cap so no attempt of the day is wasted; and the floor of % still fires on the stack (a purser at the % per cent cap takes it to %) while leaving the mechanic alone unclipped at %',
    round(v_new_pct, 3), round(v_old_pct, 3), round(v_new_pct / nullif(v_old_pct, 0), 1),
    (select count(*) from public.ports), round(v_avg, 4),
    round(v_new_pct / 13 * 100, 0), round(v_avg * 100, 2), round(v_avg / 0.13 * 100, 0),
    v_rows, v_drift,
    v_moved, v_tries,
    v_tries, v_step,
    v_flr, v_offcap, round(v_stack, 4), 1 - v_cap;
end $$;

drop table quote_before_0024;
drop table knobs_before_0024;
