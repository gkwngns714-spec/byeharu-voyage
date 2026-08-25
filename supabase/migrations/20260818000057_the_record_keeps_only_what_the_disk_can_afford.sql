-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0057 — THE RECORD KEEPS ONLY WHAT THE DISK CAN AFFORD
--        The retention window for public.price_history stops being a constant somebody picked for
--        a 70-good world and becomes a fraction OF THE DISK, derived from the world's own size —
--        the same move 0051 made for rarity, applied to a knob that just took the live game down.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED ON PRODUCTION TODAY (SQL editor) ─────────────────────────────────────
--     public.price_history   1410 MB   7,347,231 rows      <- 98% of a 1.43 GB database
--     public.port_goods        23 MB      54,432 rows
--     everything else        <2.3 MB
--
-- Production hit its disk quota and Postgres flipped the WHOLE project READ-ONLY: every write
-- failed, session refresh returned 500, no player could load the game. A freshly built world from
-- this same chain is 21 MB total, so price_history is the entire problem.
--
-- ── THE CAUSE ───────────────────────────────────────────────────────────────────────────────────
-- `public.tick_price_snapshot` (0013:97) writes one row per (port, good) per drift slot and prunes
-- with `delete from public.price_history where slot <= v_slot - v_keep`, where
-- `v_keep = public.wc_int('price_history_slots')`. That knob was set to the constant 288 in 0013,
-- for the world 0013 was written against:
--
--   * 0013 authored 288 when the world had 214 ports x 70 goods = 14,980 pairs -> a few hundred MB.
--   * 0041 grew the catalogue to 243 goods; the world today carries **54,432 (port, good) pairs**
--     (measured, `select count(*) from public.port_goods` — matches production exactly), 3.63x
--     0013's world, and NOBODY resized 288 to match.
--   * At 288 slots the table's DESIGNED ceiling is 288 x 54,432 = 15,676,416 rows, and at the
--     measured cost below that is **2.94 GB**. Production was caught at 7,347,231 rows / 1,410 MB —
--     barely half way to the ceiling it was already going to blow through.
--
-- Measured row cost, production: 1,410 MB / 7,347,231 rows = **201 bytes/row** (heap plus the
-- (port_id, good_id, slot) primary key). That is the one physical constant this file trusts; every
-- other number below is derived from the world's own tables, in-transaction, every time it runs.
--
-- ── THE KNOB'S OWN COMMENT WAS ALSO STALE, AND IT MATTERS LESS THAN IT LOOKS ──────────────────
-- 0013's description reasons from "drift_slot_seconds = 600" and "TIME_COMPRESSION 480". Checked
-- against the DEPLOYED catalogue on this machine after applying the whole chain (not recalled):
--
--     select public.wc_int('drift_slot_seconds')   ->  600   (UNCHANGED — see below)
--     select public.wc_int('time_compression')      ->  9600  (0045 moved it here, from 480)
--
-- drift_slot_seconds is NOT 300. 0029:367 does write `update world_config ... to_jsonb(300)`, but
-- that statement sits inside a `begin … exception … raise '__PROBE_ROLLBACK_0029B__'` block
-- (0029:361-378) that rolls itself back before the migration commits — it is 0029's own NEGATIVE
-- CONTROL for "the day the cadence changes", never applied for real. The brief that opened this
-- slice repeated the 300 s figure; it is corrected here rather than carried forward, because a
-- migration that reasons from a number nobody re-measured is exactly the failure this file exists
-- to remove. TIME_COMPRESSION did move (0045, 480 -> 9600), so the "hours of game-time" framing
-- 0013 used was already stale on that count alone — one more reason this file does not repeat it.
--
-- NONE OF THAT ARITHMETIC IS LOAD-BEARING BELOW. It explains why the OLD number went stale; it is
-- not consulted to produce the NEW one, which is a DISK BUDGET, not a game-time budget — a policy
-- that survives a compression retune without anyone having to re-derive it.
--
-- ── THE MECHANISM ──────────────────────────────────────────────────────────────────────────────
-- The window is no longer typed. It is DERIVED from a fixed disk budget divided by the world's own
-- pair count and the measured per-row cost, floored at the one number the game actually needs:
--
--     public.price_history_window_for(pairs)                 -- THE LAW, pure arithmetic
--       = greatest(48, floor(629,145,600 / (pairs * 201)))
--
--         629,145,600 bytes = 600 MiB.        THE BUDGET. A sensible few hundred MB, chosen to sit
--           far under the ~1.43 GB that just took the project read-only, with headroom left for
--           every other table and every future migration — not a target to fill, a ceiling not to
--           near. (task brief: "keep the table a few hundred MB rather than 3 GB.")
--         201                                  bytes/row, MEASURED above. Not rounded down: rounding
--           it UP would only make the derived window smaller (more conservative), never larger.
--         48                                   THE FLOOR. `src/lib/rpc/index.ts:289`,
--           `worldPriceHistory(portId, slots = 48)`, is the ONLY client caller and it never asks for
--           more. `world.price_history` already clamps `p_slots` to the window (0013:147), so the
--           window is also the ceiling on every point a client can ever draw — it may never fall
--           below what the one caller asks for. Losing chart points is not an acceptable outcome
--           (docs/NO_SPAGHETTI.md §7C): the conditional below chooses between two ACCEPTABLE
--           results — the derived value, or the floor — never between a derived value and a
--           broken chart.
--
--     public.price_history_window()                          -- THE WORLD-READING WRAPPER
--       = price_history_window_for(count(*) from public.port_goods)
--
-- Split the same way 0051 split `rarity_from_producers(int, numeric)` (pure law) from
-- `rarity_scale()` (reads the world): the arithmetic is testable at ANY pair count without a real
-- table of that size existing, and the world-reading half has exactly one job, reading the count.
--
-- WHAT THIS BUYS TODAY, MEASURED FROM THE DEPLOYED PAIR COUNT (54,432, matches production):
--
--     price_history_window_for(54432) = floor(629,145,600 / (54,432 x 201)) = floor(57.50) = 57
--     table ceiling  54,432 x 57 x 201 bytes = 623,627,424 bytes ≈ 594.7 MB    (was ≈ 2.94 GB)
--
-- 594.7 MB is a 58% CUT from the 1,410 MB that just took the project down, and the growth rate per
-- future (port, good) pair falls from 288 x 201 = 57,888 bytes to 57 x 201 = 11,457 bytes — an 80%
-- cut in how much disk one more good or one more port costs the record, permanently, at today's
-- world size.
--
-- ── WHERE THIS DESIGN IS HONEST ABOUT ITS OWN LIMIT ────────────────────────────────────────────
-- The floor and the budget can conflict, and when they do the floor wins — that is the whole point
-- of a floor. Solving `48 = floor(629,145,600 / (pairs x 201))` gives the crossover:
-- pairs > 629,145,600 / (48 x 201) = 65,213 pairs (about 1.2x today's 54,432), the DERIVED value
-- would fall under 48 and the floor overrides it — the table then costs `pairs x 48 x 201` bytes,
-- which is no longer bounded by the 600 MiB budget. That is not a bug in this file: no rule can
-- promise BOTH a fixed disk ceiling AND a fixed minimum history per pair once the world is large
-- enough that the minimum alone exceeds the ceiling, and the floor is the non-negotiable half
-- (docs/NO_SPAGHETTI.md §7C — a broken chart is not an acceptable branch). What does NOT regress
-- past that point is the per-pair GROWTH RATE: it is 11,457 bytes/pair everywhere, floor-bound or
-- not, against the old rule's 57,888 bytes/pair everywhere — an 80% cut that holds at every scale,
-- proven below by the sweep rather than asserted in prose. The next hand that grows the catalogue
-- past ~65,213 pairs re-measures the budget in a NEW superseding migration exactly the way this one
-- did; that is a sized, understood follow-up, not a silent multi-gigabyte surprise.
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
-- Two deployed functions are SLICED, not retyped, with `pg_temp.recut` (0050:120, copied below —
-- it is `pg_temp` and cannot be inherited across migrations, docs/NO_SPAGHETTI.md's own note on
-- 0053 repeats the reason). Each hunk must occur exactly once in `pg_get_functiondef`, so a
-- deployment that has drifted refuses rather than half-applies.
--
--   * public.tick_price_snapshot(timestamptz) — SUPERSEDES 0013:97. One line moves: the prune's
--     `v_keep` reads `public.price_history_window()` instead of `public.wc_int('price_history_slots')`.
--     Nothing else in the body is retyped — the ON CONFLICT DO NOTHING write, the prune shape, the
--     returned jsonb are all 0013's, untouched.
--   * world.price_history(uuid, int) — SUPERSEDES 0013:139. Same one-line move in the clamp:
--     `least(greatest(coalesce(p_slots, 48), 1), public.price_history_window())`. The read shape,
--     the E_NO_SUCH_PORT guard, the payload are all 0013's, untouched.
--
-- Both comments are re-issued after the slice so neither deployed function's `comment on` still
-- names the retired knob.
--
-- ── THE KNOB IS RETIRED, NOT LEFT TO DRIFT ─────────────────────────────────────────────────────
-- `world_config.price_history_slots` (0013:46) is DELETED once its last reader is gone. Grepped
-- across the whole `supabase/` tree before writing this file: the ONLY file that names
-- `price_history_slots` at all is 0013 itself (the insert that minted it, the two readers this file
-- supersedes, its own comments and self-assert) — no other migration, and no RPC or client file,
-- reads it. `src/lib/rpc/index.ts` and every `.ts`/`.mjs` under this repo were grepped too: zero
-- hits. The self-assert below proves the DEPLOYED catalogue agrees — no `pg_proc` body anywhere
-- contains the string once this migration lands — rather than trusting the grep alone.
--
-- ── VACUUM, DELIBERATELY NOT HERE ──────────────────────────────────────────────────────────────
-- This migration DELETEs the excess rows the moment it applies, inside its own transaction — the
-- table is bounded when this file commits, not at the next cron tick. It does **not** run `VACUUM`:
-- Postgres refuses `VACUUM` inside a transaction block, and every statement in a migration runs
-- inside one. The deleted rows' pages become free space PostgreSQL reuses for future inserts — the
-- table's row COUNT and logical size drop immediately, but the bytes are not returned to the disk
-- until something runs `VACUUM FULL public.price_history` (or `pg_repack`) outside a migration,
-- by hand, against the live database. That follow-up is out of scope for this file and is not
-- silently assumed to have happened — it is a manual step the operator still owes production.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT TOUCH ─────────────────────────────────────────────────
-- The record is still never read to trade on (0013's rule, unrepeated here and unbroken). The
-- sample cadence, the ON CONFLICT idempotence, the `mid`/`stock` columns, the RLS policy and the
-- `authenticated`-only read grant are all 0013's and none of them move. No new client door is
-- opened; the two new functions (`price_history_window_for`, `price_history_window`) are as
-- private as `public.rarity_scale` — internal law, never called from the wire.
--
-- Depends on: 0001 (wc/wc_int lockdown, client_write_grants), 0013 (price_history, drift_slot_of,
--             the two functions superseded here), 0018 (client_executable_writers), 0041 (the
--             243-good catalogue that made 288 wrong), 0050 (pg_temp.recut).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE SLICE TOOL — copied from 0053 (pg_temp, cannot be inherited across migrations) ───────
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0057 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 1. THE LAW — pure arithmetic, testable at any pair count, the numbers exist here and nowhere
--       else ────────────────────────────────────────────────────────────────────────────────────
-- `create`, not `create or replace`: this file claims the function is NEW (0051:252's convention).
create function public.price_history_window_for(p_pairs int)
returns int
language plpgsql
immutable
as $$
begin
  if p_pairs is null or p_pairs <= 0 then
    raise exception '0057: price_history_window_for asked about % (port, good) pair(s) — a world that trades nothing has no budget to divide', p_pairs;
  end if;
  -- 629,145,600 bytes = 600 MiB, THE BUDGET. 201 = measured bytes/row (production, this file's
  -- header). 48 = THE FLOOR: src/lib/rpc/index.ts:289 is the only client caller and it never asks
  -- for more, so the window may never serve fewer points than the one caller draws
  -- (docs/NO_SPAGHETTI.md §7C — a conditional may only choose between two ACCEPTABLE outcomes, and
  -- a chart with fewer than 48 points is not one of them).
  return greatest(48, floor(629145600::numeric / (p_pairs::numeric * 201))::int);
end $$;

comment on function public.price_history_window_for(int) is
  'THE RETENTION LAW (0057): (port, good) pair count -> how many drift slots of price_history to '
  'keep. greatest(48, floor(600 MiB / (pairs x 201 measured bytes/row))). The one place the budget, '
  'the row cost and the floor exist — change any of the three in a superseding migration and every '
  'caller moves with it. Scale-free in the sense that matters for disk: multiplying pairs by k '
  'divides the derived (non-floored) window by k, holding pairs x window x 201 near the budget '
  'until the floor takes over, at which point growth is bounded to 48 x 201 bytes per pair instead '
  'of the retired constant''s 288 x 201.';

revoke all on function public.price_history_window_for(int) from public, anon, authenticated;

-- ── 2. THE WORLD-READING WRAPPER — the only new object that touches a table ────────────────────
create function public.price_history_window()
returns int
language sql
stable
set search_path = public, pg_temp
as $$
  select public.price_history_window_for((select count(*)::int from public.port_goods))
$$;

comment on function public.price_history_window() is
  'How many drift slots of price_history to keep, RIGHT NOW, for the world as it stands (0057). '
  'Reads public.port_goods and nothing else, then hands the count to '
  'public.price_history_window_for — the one place the thresholds live. THE authority for '
  '"how much history is kept"; public.tick_price_snapshot (the prune) and world.price_history '
  '(the read clamp) both call this and neither computes its own answer.';

revoke all on function public.price_history_window() from public, anon, authenticated;

-- ── 3. A REAL PRECONDITION, SET BY THIS FILE — because a fresh chain boots price_history EMPTY
--       (proof.mjs measured 0 rows here before this migration runs) and a proof over an empty
--       table would pass every check below vacuously. This is IN-TRANSACTION and this file owns
--       it (docs/NO_SPAGHETTI.md §4): three real rows for a real port, spanning three real slots —
--       two "recent" (inside any window this law can produce) and one "ancient" (beyond the NEW
--       window but inside the OLD one, so it exists under 0013's rule and must be gone under this
--       one). On production the equivalent excess already exists for real, at every pair; this
--       insert is what makes the same proof run on a fresh chain and in CI.
create temporary table subject_0057 as
  select p.id, p.code
    from public.ports p
   where exists (select 1 from public.port_goods pg where pg.port_id = p.id)
   order by p.code limit 1;

do $$
begin
  if (select count(*) from subject_0057) <> 1 then
    raise exception '0057 self-assert FAIL: no port with a market row was found to seed a precondition on';
  end if;
end $$;

insert into public.price_history (port_id, good_id, slot, at, mid, stock)
select pg.port_id, pg.good_id, s.slot, now(),
       world.mid_price(pg.port_id, pg.good_id, pg.stock), pg.stock
  from public.port_goods pg
  join subject_0057 sub on sub.id = pg.port_id
 cross join lateral (values
   (public.drift_slot_of(now()) - 3),    -- recent: inside every window this law can produce
   (public.drift_slot_of(now()) - 10),   -- recent: inside every window this law can produce
   (public.drift_slot_of(now()) - 100)   -- ancient: inside 0013's old window (288), outside the new one
 ) as s(slot)
-- THE CONFLICT CLAUSE IS NOT DECORATION — IT IS THE PRODUCTION DEPLOY'S OWN BUG REPORT.
-- 2026-08-26: this migration FAILED on the real production push with
--     ERROR: duplicate key value violates unique constraint "price_history_pkey" (SQLSTATE 23505)
--     Key (port_id, good_id, slot)=(c205adb3..., 4c69bf2d..., 2979499) already exists.
-- The comment above already SAID "on production the equivalent excess already exists for real, at
-- every pair" — and then seeded with a bare INSERT anyway. A fresh chain (PGlite, CI's disposable
-- Supabase) boots price_history EMPTY, so nothing collided there and both engines went green on a
-- precondition that cannot hold on the only database that matters. ON CONFLICT DO NOTHING is
-- 0013's own idempotence rule (public.tick_price_snapshot writes the identical way), and it makes
-- this step mean the same thing on both: AFTER it, rows exist at all three slots — written by this
-- file on a fresh chain, by the live tick on production. Every assertion below reads the table, not
-- this statement's row count, so none of them weakens: on production the ancient slot carries REAL
-- rows the prune must remove, which is a stronger positive control than the synthetic one.
on conflict (port_id, good_id, slot) do nothing;

-- NON-VACUITY OF THE PRECONDITION, ASSERTED RATHER THAN ARGUED. The clause above can silently do
-- nothing; what must be true is not "the insert wrote rows" but "the three slots are populated".
do $$
declare v_recent int; v_ancient int;
begin
  select count(*) into v_recent from public.price_history h join subject_0057 s on s.id = h.port_id
   where h.slot in (public.drift_slot_of(now()) - 3, public.drift_slot_of(now()) - 10);
  select count(*) into v_ancient from public.price_history h join subject_0057 s on s.id = h.port_id
   where h.slot = public.drift_slot_of(now()) - 100;
  if v_recent = 0 then
    raise exception '0057 self-assert FAIL: 0 recent row(s) at the seeded slots for the subject port — the parity and span proofs below would run over nothing';
  end if;
  if v_ancient = 0 then
    raise exception '0057 self-assert FAIL: 0 ancient row(s) at slot now-100 for the subject port — the prune positive control below would pass vacuously, proving nothing shrank';
  end if;
  raise notice '0057 precondition ok: subject port carries % recent and % ancient price_history row(s) before the prune', v_recent, v_ancient;
end $$;

-- ── 4. THE BEFORE PAYLOAD — captured while world.price_history is STILL 0013's deployed body,
--       exactly 0051/0053's convention: the parity proof below reads this, not a description of it.
create temporary table payload_before_0057 as
  select world.price_history(sub.id, 48) as hist from subject_0057 sub;

-- ── 5. THE SLICES ──────────────────────────────────────────────────────────────────────────────
select pg_temp.recut('public.tick_price_snapshot(timestamptz)'::regprocedure, false,
  '  v_keep  int    := public.wc_int(''price_history_slots'');',
  '  v_keep  int    := public.price_history_window();');

comment on function public.tick_price_snapshot(timestamptz) is
  'Samples every (port, good) mid once per drift slot and prunes beyond the window '
  'public.price_history_window() reports (SUPERSEDES 0013:97 — same shape, same idempotence by '
  'primary key; only the retention source moved).';

select pg_temp.recut('world.price_history(uuid,int)'::regprocedure, false,
  '  v_slots int := least(greatest(coalesce(p_slots, 48), 1), public.wc_int(''price_history_slots''));',
  '  v_slots int := least(greatest(coalesce(p_slots, 48), 1), public.price_history_window());');

comment on function world.price_history(uuid, int) is
  'One port''s remembered mids, keyed by good CODE, oldest first (0013). SUPERSEDES 0013:139: same '
  'payload shape, same clamp behaviour — p_slots is still bounded to [1, the window] — only the '
  'window''s source moved to public.price_history_window() (0057).';

-- ── 6. THE AFTER PAYLOAD — same data, new code, captured BEFORE the real prune below adds or
--       removes a single row. This isolates "did the slice change what is served" from "did the
--       tick that follows change the data", which are two different claims.
create temporary table payload_after_recut_0057 as
  select world.price_history(sub.id, 48) as hist from subject_0057 sub;

-- ── 7. THE KNOB IS RETIRED — its last two readers are gone as of step 5.
delete from public.world_config where key = 'price_history_slots';

-- ── 8. THE REAL FIX — bound the table THE MOMENT THIS MIGRATION APPLIES, not at the next cron
--       tick. Idempotent by primary key (0013): this also writes today's sample for every pair.
--       On production this prunes the real 7.3M-row excess down to the new window; here it prunes
--       the 100-slot-old synthetic row seeded in step 3.
select public.tick_price_snapshot(now());

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_real_pairs   int;
  v_win          int;
  v_win_k        int;
  v_pairs_k      numeric;
  v_k            numeric;
  v_before       jsonb;
  v_after        jsonb;
  v_slots_before int;
  v_before_def   text;
  v_after_def    text;
  v_n            int;
  v_lo           int;
  v_hi           int;
  v_leftover     int;
  v_recent       int;
  v_min_slot     bigint;
  v_max_slot     bigint;
  v_rows         int;
  v_grants       int;
  v_writers      int;
  v_subj         uuid;
  v_subj_code    text;
begin
  select id, code into strict v_subj, v_subj_code from subject_0057;

  -- ── (0) NON-VACUITY. The seeded precondition really has rows and spans slots, or every
  --        comparison below proves nothing (docs/NO_SPAGHETTI.md §4). The served payload only ever
  --        shows the two RECENT synthetic slots (-3, -10): the ANCIENT one (-100) is seeded 100
  --        slots back specifically so it sits outside the p_slots=48 read range regardless of the
  --        retention window's size — its job is §(4)'s prune proof, on the raw table, not this read.
  select hist into v_before from payload_before_0057;
  select count(distinct pt ->> 'slot') into v_n
    from jsonb_each(v_before -> 'goods') g, lateral jsonb_array_elements(g.value) pt;
  -- Every good this port trades must carry the SAME number of points — proven by MIN = MAX rather
  -- than picked by an unordered `limit 1` (docs/NO_SPAGHETTI.md §4's lottery warning).
  select min(jsonb_array_length(value)), max(jsonb_array_length(value)) into v_lo, v_hi
    from jsonb_each(v_before -> 'goods');
  if v_lo is distinct from v_hi then
    raise exception '0057 self-assert FAIL: the seeded goods do not all carry the same point count (min % , max %) — the precondition is not uniform enough to prove anything by count alone', v_lo, v_hi;
  end if;
  v_slots_before := v_lo;
  if v_before is null or v_n < 2 then
    raise exception '0057 self-assert FAIL: the seeded precondition spans % distinct slot(s), need >= 2 — the parity and pruning proofs below would run over nothing', coalesce(v_n, 0);
  end if;

  -- ── (1) THE WINDOW FUNCTION IS SCALE-FREE: the floor never breaks, and the budget holds
  --        wherever the floor is not the binding constraint. Swept over the REAL pair count at
  --        k = 1/2/3/7/17/50 (0051's own sweep, for the same reason: a hand-picked ladder proves
  --        less than the actual distribution rescaled) plus the sparse end (1, 10, 100 pairs).
  select count(*) into v_real_pairs from public.port_goods;
  if v_real_pairs = 0 then
    raise exception '0057 self-assert FAIL: 0 (port, good) pairs — the sweep below would divide by zero and prove nothing';
  end if;

  foreach v_k in array array[1, 2, 3, 7, 17, 50]::numeric[]
  loop
    v_pairs_k := v_real_pairs * v_k;
    v_win_k := public.price_history_window_for(v_pairs_k::int);
    if v_win_k < 48 then
      raise exception '0057 self-assert FAIL: at % pairs (k=%) the window is % slots — under the 48-point floor the client always draws', v_pairs_k, v_k, v_win_k;
    end if;
    if v_win_k > 48 and v_pairs_k * v_win_k * 201 > 629145600 then
      raise exception '0057 self-assert FAIL: at % pairs (k=%) the derived (non-floored) window of % slots costs % bytes — over the 600 MiB budget', v_pairs_k, v_k, v_win_k, v_pairs_k * v_win_k * 201;
    end if;
  end loop;

  foreach v_pairs_k in array array[1, 10, 100]::numeric[]
  loop
    v_win_k := public.price_history_window_for(v_pairs_k::int);
    if v_win_k < 48 then
      raise exception '0057 self-assert FAIL: at % pair(s) the sparse-regime window is % slots — under the 48-point floor', v_pairs_k, v_win_k;
    end if;
  end loop;

  -- ── (1b) POSITIVE CONTROL. The sweep above must be SHOWN capable of catching the exact defect
  --        this file fixes — the OLD constant (288) against TODAY'S real pair count, not a
  --        hypothetical one. If this reads <= budget the check above proves nothing about the
  --        actual failure that took production down.
  -- v_real_pairs cast to bigint before multiplying: 54,432 x 288 x 201 = 3,150,959,616, which
  -- overflows int4 (max 2,147,483,647) if the arithmetic is left in plain `int`.
  if v_real_pairs::bigint * 288 * 201 <= 629145600 then
    raise exception '0057 self-assert FAIL: the positive control is BLIND — the retired constant (288) at today''s % real pairs costs % bytes, which does not exceed the 600 MiB budget, so nothing above proves this file catches the actual production defect', v_real_pairs, v_real_pairs::bigint * 288 * 201;
  end if;
  v_win := public.price_history_window();
  if v_win * v_real_pairs * 201 > 629145600 and v_win > 48 then
    raise exception '0057 self-assert FAIL: today''s DERIVED window (%) still costs more than the 600 MiB budget (% bytes) — the fix this file ships does not fix today''s world', v_win, v_win * v_real_pairs * 201;
  end if;

  -- ── (2) BOTH RE-CUT BODIES, READ BACK OFF THE DEPLOYED CATALOGUE: each names the new authority
  --        exactly once and no longer names the retired knob at all.
  v_before_def := pg_get_functiondef('public.tick_price_snapshot(timestamptz)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_before_def, 'public\.price_history_window\(\)', 'g');
  if v_n <> 1 or strpos(v_before_def, 'price_history_slots') > 0 then
    raise exception '0057 self-assert FAIL: the deployed tick_price_snapshot names public.price_history_window() % time(s) (expected 1) and % contain the retired knob name', v_n, case when strpos(v_before_def, 'price_history_slots') > 0 then 'DOES' else 'does not' end;
  end if;

  v_after_def := pg_get_functiondef('world.price_history(uuid,int)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_after_def, 'public\.price_history_window\(\)', 'g');
  if v_n <> 1 or strpos(v_after_def, 'price_history_slots') > 0 then
    raise exception '0057 self-assert FAIL: the deployed world.price_history names public.price_history_window() % time(s) (expected 1) and % contain the retired knob name', v_n, case when strpos(v_after_def, 'price_history_slots') > 0 then 'DOES' else 'does not' end;
  end if;

  -- ── (2b) THE CATALOGUE-WIDE CLAIM, not just the two functions this file names: NOTHING deployed
  --        anywhere still names the retired knob. This is the DB-level proof behind the header's
  --        "grepped the whole supabase/ tree" claim.
  select count(*) into v_n from pg_proc where prosrc like '%price_history_slots%';
  if v_n <> 0 then
    raise exception '0057 self-assert FAIL: % deployed function(s) still reference price_history_slots — a reader was missed', v_n;
  end if;

  -- ── (3) VALUE PARITY. Same data (step 3's seed), old code (step 4's capture) against new code
  --        (step 6's capture, taken before the real prune touched anything) — must be byte-equal.
  select hist into v_after from payload_after_recut_0057;
  if v_before <> v_after then
    raise exception '0057 self-assert FAIL: world.price_history(%, 48) served a different payload after the slice, over IDENTICAL data — the recut changed behaviour, not just its source', v_subj_code;
  end if;
  -- non-vacuity of the comparison itself: the compared payload must actually carry the seeded slots.
  if v_slots_before < 2 then
    raise exception '0057 self-assert FAIL: the compared payload carries only % point(s) per good — the parity check ran over too little to mean anything', v_slots_before;
  end if;

  -- ── (4) THE PRUNE ACTUALLY PRUNED — a positive control, not an absence-of-error. The ancient
  --        (100-slots-old) synthetic row must be gone; the two recent ones must have survived.
  select count(*) into v_leftover
    from public.price_history h
    join subject_0057 s on s.id = h.port_id
   where h.slot = public.drift_slot_of(now()) - 100;
  if v_leftover <> 0 then
    raise exception '0057 self-assert FAIL: % row(s) seeded 100 slots old survived the real prune this migration ran — the fix does not actually shrink the table', v_leftover;
  end if;
  select count(*) into v_recent
    from public.price_history h
    join subject_0057 s on s.id = h.port_id
   where h.slot in (public.drift_slot_of(now()) - 3, public.drift_slot_of(now()) - 10);
  if v_recent = 0 then
    raise exception '0057 self-assert FAIL: 0 of the recent seeded rows survived the prune — either the prune is too aggressive or the seed never landed';
  end if;

  -- ── (5) THE TABLE IS NOW BOUNDED. After the real prune, the whole table's slot span must sit
  --        inside the CURRENT window — not the window at the time this file was written, so a
  --        later world growth that shrinks the window cannot silently outrun this check.
  select count(*), min(slot), max(slot) into v_rows, v_min_slot, v_max_slot from public.price_history;
  if v_rows = 0 then
    raise exception '0057 self-assert FAIL: price_history is empty after the real prune — the bounded-table check below would be vacuous';
  end if;
  if v_max_slot - v_min_slot >= public.price_history_window() then
    raise exception '0057 self-assert FAIL: the table spans % slot(s) (% to %) after the prune, which is not less than the window of %', v_max_slot - v_min_slot, v_min_slot, v_max_slot, public.price_history_window();
  end if;
  -- and the span must be a REAL span, not a single-slot table that would satisfy the check above
  -- by construction — the recent seeded rows (step 3) guarantee this.
  if v_max_slot - v_min_slot = 0 then
    raise exception '0057 self-assert FAIL: the post-prune table has a single slot — the bounded check above is vacuous without the seeded span';
  end if;

  -- ── (6) POSTURE UNCHANGED. No new client write grant, no new client-executable writer, the two
  --        new internal-law functions stay unreachable, and world.price_history/tick_price_snapshot
  --        keep exactly the doors 0013 left them.
  select count(*) into v_grants from public.client_write_grants();
  select count(*) into v_writers from public.client_executable_writers();
  if v_grants <> 0 or v_writers <> 0 then
    raise exception '0057 self-assert FAIL: % client write grant(s), % client-executable writer(s)', v_grants, v_writers;
  end if;
  if has_function_privilege('anon', 'public.price_history_window_for(int)', 'execute')
     or has_function_privilege('authenticated', 'public.price_history_window_for(int)', 'execute')
     or has_function_privilege('anon', 'public.price_history_window()', 'execute')
     or has_function_privilege('authenticated', 'public.price_history_window()', 'execute') then
    raise exception '0057 self-assert FAIL: a client role may execute the retention law or its wrapper — this is internal, like public.rarity_scale';
  end if;
  if has_function_privilege('anon', 'world.price_history(uuid,int)', 'execute') then
    raise exception '0057 self-assert FAIL: anon may execute world.price_history — the record is for signed-in captains (0013''s posture)';
  end if;
  if not has_function_privilege('authenticated', 'world.price_history(uuid,int)', 'execute') then
    raise exception '0057 self-assert FAIL: the supersede dropped authenticated''s EXECUTE on world.price_history — the market screen loses its chart';
  end if;
  if has_function_privilege('authenticated', 'public.tick_price_snapshot(timestamptz)', 'execute') then
    raise exception '0057 self-assert FAIL: authenticated may execute tick_price_snapshot — a client could stuff the record';
  end if;
  -- and the retired knob is actually gone, not merely un-read.
  if exists (select 1 from public.world_config where key = 'price_history_slots') then
    raise exception '0057 self-assert FAIL: world_config still carries price_history_slots — a knob nobody reads is drift waiting to be trusted';
  end if;

  raise notice '0057 self-assert ok: window(% real pairs) = % slots (was 288), table now bounded to % byte(s) budget of 629,145,600; scale-free sweep at k=1/2/3/7/17/50 and sparse pairs 1/10/100 never fell under the 48-point floor and never exceeded budget above it; positive control confirms the retired constant costs % bytes today against a 629,145,600 budget; both re-cut bodies name public.price_history_window() exactly once and neither, nor any deployed function in pg_proc, still names price_history_slots; world.price_history(%, 48) served byte-identical payloads across the slice over % identical point(s); the real prune removed the 100-slot-old seed while the recent seed (% row(s)) survived; the whole table spans % slot(s) (% to %), inside the % -slot window; world_config no longer carries the retired knob; % client write grant(s), % client-executable writer(s)',
    v_real_pairs, v_win, v_win * v_real_pairs * 201, v_real_pairs::bigint * 288 * 201, v_subj_code, v_slots_before, v_recent, v_max_slot - v_min_slot, v_min_slot, v_max_slot, public.price_history_window(), v_grants, v_writers;
end $$;

drop table subject_0057;
drop table payload_before_0057;
drop table payload_after_recut_0057;
