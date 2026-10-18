-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0137 — AN ARRIVAL NEVER WAITS FOR THE HOUR  (the reconcile and the drift commit step by step —
--        nothing either decides moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Prod, cron.job_run_details, 2026-10-15 12:00 → 2026-10-16 18:00 UTC (read-only). byeharu-voyage:arrivals
-- runs every 15 s on a 10 s budget (normal avg ≈ 3.5 s). Every arrivals run over 12 s in that window
-- ended within 0.5 s of another job's COMMIT:
--   * byeharu-voyage:reconcile (select public.tick_reconcile(), hourly at :07, 63–84 s, ONE transaction):
--     runs of 59.2 / 72.0 / 29.9 / 17.2 / 38.9 / 38.4 s ended 31 / 50 / 168 / 274 / 101 / 55 ms after it
--     committed (e.g. 2026-10-16: arrivals 13:07:24.634 → 13:08:03.082, reconcile commit 13:08:03.027).
--   * byeharu-voyage:drift (select public.tick_market_drift(), every 10 min, 12–26 s, ONE statement per
--     UPDATE over all 132,090 port_goods rows): eleven runs of 12.7–21.2 s ended 59–489 ms after it.
-- WHAT THE SWEEP WAITED ON (read off the function bodies on prod, pg_get_functiondef):
--   * public.npc_tend (called by tick_reconcile) takes, for EVERY merchant route on its walk,
--     `perform 1 from public.fleets where id = <her fleet> for update nowait` and the route row
--     FOR UPDATE NOWAIT — before the budget test, so the whole roster (837 fleets) is locked on every
--     pass — inside a subtransaction whose locks are kept until the TOP transaction commits, i.e. until
--     the compactor and the 838-player ledger check have also finished, 60–80 s later. voyage.settle,
--     the sweep's per-fleet step, opens with `select * from public.fleets where id = p_fleet for update`
--     (a waiting lock). So a merchant who arrives during the reconcile is held at that line until the
--     hour commits. The 13:07:24 run on 2026-10-16 is exactly that: everything it wrote (events at its
--     own now(), 13:07:24.634) is MERCHANT business — 10 VOYAGE_REPORTs, 8 DEPARTED, 3 ROUTE_LAPs, 3
--     BOUGHT, 3 SOLD — all of companies the reconcile had walked.
--   * tick_market_drift updates every port_goods row in two statements; a sale or purchase on arrival
--     (cmd.advance → the trade doors) updates the port_goods row it trades, and waits for the drift.
-- A live probe at 18:07 and 18:10 UTC on 2026-10-16 (pg_stat_activity + pg_locks, read-only, every
-- ~4 s) saw the reconcile run 65 s and no sweep waiting in that hour: no merchant of the walk came due.
-- The stall is the arrival that comes due while the hour holds her — which is why it is not every hour.
--
-- ── WHAT THIS FILE DOES (one authority each; nothing a pass decides moves — asserted) ──────────
-- (1) npc_tend is cut, VERBATIM, into its steps: public.npc_tend_roster (the walk: the route written
--     longest ago first, k = roster rank), public.npc_tend_route (one merchant — the per-route body,
--     run inside a one-row loop so its own `continue`s end her exactly as before), public.npc_tend_houses
--     (investment + refounds; the gate loses `and p_route is null` — the one hunk) and
--     public.npc_tend_sum (the receipt's one adder). npc_tend(p_now, p_route) is their one-transaction
--     composition: same signature, same receipt, same ACL / definer / path.
-- (2) public.tick_reconcile becomes a PROCEDURE (the job says CALL): every merchant in her own
--     transaction, then the companies, then the compactor — each under public.npc_upkeep_scope (0097's
--     lock_timeout 2 s and 0114's deadline, transaction-local, so set again for each transaction; the
--     deadline still runs from the start of the hour). A merchant's locks now live for her step (ms;
--     ≈ 1.3 s for a lap start with its plan), not for the hour.
--     EVERY STEP IS CHECKED BEFORE ITS COMMIT: a merchant's step ends with
--     public.assert_ledger_reconciles(her), the companies' step with it for every company (players.is_npc);
--     the compactor already checks each company it rolls up (0097). A step that breaks a purse raises
--     inside its own block, is rolled back alone and is counted in the receipt (failed + a note,
--     public.npc_step_failed — the one shape of a failed step). Then the whole-world invariants,
--     unchanged and read-only, in a transaction that takes no row lock. p_commit = false runs the same
--     steps in the caller's one transaction (the proofs).
-- (3) public.tick_market_drift(p_now, p_port default null) — two hunks (`and (p_port is null or
--     pg.port_id = p_port)`, one per UPDATE); null is every harbour, as before. The drift job calls the
--     procedure public.tick_market_drift_each_port: every harbour (public.ports, in id order) in its own
--     transaction, all at the job's start time, so every harbour lands on the same slot and game-day.
--     A harbour that DEADLOCKS (40P01 — prod's drift failed 34 of 386 runs, 8.8 %, on one in the
--     regeneration UPDATE) or times out on a lock (55P03) is rolled back alone, warned and counted, and
--     the run goes on; that harbour keeps its slot and day, so the next run drifts it.
-- (4) world.market (the client's read of one quay, ~3,970 calls on prod) drifted the WHOLE market before
--     pricing its quay — 132,090 rows locked by a player's read, and the other side of the drift job's
--     deadlocks. One hunk, sliced from the live body: `tick_market_drift(v_now)` →
--     `tick_market_drift(v_now, p_port)`. It answers the same for its quay (asserted, §6b).
-- (5) The two cron jobs are re-pointed in place (cron.alter_job command only — name, schedule, owner and
--     active flag untouched), so public.wind_the_clock() starts exactly these commands.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change any rule, knob, budget, schedule, receipt key, the walk's order, the compactor, the
-- invariants, the arrivals sweep, voyage.settle, or any client grant / entry point. Run the upkeep in
-- parallel. Re-order a lock (each step keeps its own order: fleet, then route, NOWAIT).
-- WHAT CHANGES ONLY IN FAILURE: before, an error escaping the investment pass rolled back the whole
-- tend, and an invariant failure rolled back the hour's upkeep. Now a step's error — or a purse it
-- broke — is reported and rolled back alone; a purse broken BEFORE the hour fails every step of hers
-- and the whole-world pass still raises on it. A drift run that met a deadlock now completes, one
-- harbour short, instead of failing whole.
-- A price snapshot taken during the drift may now read some harbours on the new slot and the rest on
-- the old one (each is a committed state of its own harbour). WHERE THERE IS NO pg_cron (the local
-- PGlite game) a harbour's prices now step only when its own quay is read, not when any quay is.
--
-- ── THE PROOF (all in this file; production is lived in while it runs, so only OWN writes count) ──
-- §3 cuts the pre-image of npc_tend at six anchors and requires each slice byte-equal in its new home,
-- the houses slice after its one hunk is reversed, and the text between slices to be exactly the
-- loop's own two lines. §4 runs old (pre-image copy) and new npc_tend, each in a rolled-back
-- subtransaction: the whole pass with the hour's budget spent, then 12 merchants (dear work first)
-- ONE PAIR AT A TIME. Compared: the receipts, and each run's OWN writes — per table its inserted /
-- updated / deleted counts (pg_stat_xact_all_tables, read before and after inside the run) and the md5
-- of the rows whose xmin is this backend's open transaction (pg_xact_status = 'in progress'). No
-- count(*) and no whole-table md5: a player's commit between two runs cannot fail the push. The
-- instrument is proven to see a one-row write first.
-- §6 reverses tick_market_drift and world.market to their pre-images. §6b proves old vs new on a
-- BOUNDED SAMPLE of harbours (the ones with the most producing rows, the strongest works, the most
-- short rows, the fewest and most rows, the first and last; 3 harbours / 1,665 rows on the cached
-- world), never the whole market: only the sample's rows are locked (FOR UPDATE in ctid order), at a
-- probe moment T at or before every row's slot and day, so no row outside the sample is due and the
-- old whole-market body writes only the sample (asserted by its own-write count). drift_sigma = 0 in
-- the run (the draw is random() by design, 0010) and six rows are bent so both clamps, a row on its
-- slot, a row on its day, and regeneration below and up to the target are all taken. Each new
-- per-harbour call must move exactly its own harbour's due rows. Then world.market old vs new at T on
-- every sample harbour: payloads equal. Timings: raise notice only.
-- MUTANTS, each caught on the cached PGlite world: the drift filter inverted (§6b per-harbour count);
-- k + 5000 in npc_tend (§4 receipt); world.market drifting at T + 3 days (§6b payload); an extra
-- world_config write in npc_tend with an unchanged receipt (§4 own-write digest).
-- The procedures COMMIT, so they cannot run inside a migration: they were driven, committed, on the
-- cached PGlite world with merchants on (DEV_LOG 2026-10-17 — two hours; a merchant whose step broke
-- her purse rolled back alone; a forced 40P01 and a forced 55P03 harbour skipped while the drift went
-- on), and §7 asserts they are invoker, SET-free, owner-only, and carry the checks above.
--
-- ── WHAT IT BUYS ────────────────────────────────────────────────────────────────────────────────
-- EXPECTED on prod (not measurable before the push): an arrivals run overlapping the reconcile waits at
-- most for the one merchant step holding her (ms; ≈ 1.3 s at most, a lap start)
-- instead of up to 84 s; one overlapping the drift waits for one harbour's update (≈ 132,090 / 238 rows,
-- ~0.1 s) instead of 12–26 s; a quay read locks its own 555 rows, not 132,090. VERIFY after the push.
--
-- ── LOCKS, AND HOW LONG THE PUSH TAKES ──────────────────────────────────────────────────────────
-- DROP / CREATE FUNCTION and PROCEDURE, CREATE OR REPLACE world.market (catalog only); cron.alter_job.
-- The §4 runs write inside rolled-back subtransactions: a merchant's rows are held for her own pair of
-- runs (≤ ≈ 2 × 1.3 s), the whole pass's NOWAIT merchant locks for its run (merchants only — the
-- arrivals sweep is stopped). §6b holds the SAMPLE harbours' port_goods rows from its lock to this
-- file's COMMIT (the rest is §7, catalogue reads): a trade or quay read at those 3 harbours waits that
-- long (≈ 1–3 s), no other harbour waits at all. No LOCK TABLE, no set role, no set local, no begin.
-- Measured on the cached PGlite world: the whole file ≈ 15 s (§4 ≈ 9 s, §6b ≈ 1.5 s). ESTIMATED on
-- prod, NOT measured: 30–90 s — §4's 12 dear-work merchants are ≈ 1.3 s a run there (24 runs), plus the
-- own-row scans of the tables each run wrote (events 79 MB is the largest). The file sets
-- statement_timeout 20 min for itself.
--
-- ── DEPLOY, AND THE CHECKLIST AFTER THE PUSH ────────────────────────────────────────────────────
-- DEPLOY_RUNBOOK: select public.unwind_the_clock(); → supabase db push --linked --include-all → select
-- public.wind_the_clock(). START THE PUSH a minute or two after a quarter hour (drift slots are 900 s,
-- epoch-aligned): until this file commits, the LIVE world.market still drifts the whole market on the
-- first quay read of each slot (~15 s of row locks), and a §4 merchant trade that meets one of those
-- locks waits up to the file's lock_timeout (5 s) — a failed push, rolled back whole (DEPLOY_RUNBOOK §3),
-- not a corrupted one; read the error before pushing again. Then, on the target:
--   1. supabase migration list --linked — 0137 applied (0139 stays the head: it went on first).
--   2. select jobname, command, active from cron.job where jobname in ('byeharu-voyage:reconcile',
--      'byeharu-voyage:drift') — `call public.tick_reconcile()` / `call public.tick_market_drift_each_port()`,
--      both active after wind_the_clock().
--   3. After the next drift slot and the next :07: cron.job_run_details for both jobs — status
--      'succeeded', the reconcile well under the 120 s statement_timeout (it was 63–84 s; failed twice at
--      120 s), the drift no longer failing on `deadlock detected` (a skipped harbour is a WARNING in the
--      Postgres log, not a failed run).
--   4. The overlap query of 0136/0137: arrivals runs > 12 s ending within 1 s of a reconcile or drift end
--      — expected none.
--   5. Open a quay in the game (world.market) and trade: the prices served and the trade go through.
--   NOTE `select public.tick_reconcile()` NO LONGER WORKS — it is a procedure: `call public.tick_reconcile()`
--   (or `call public.tick_reconcile(false)` inside a transaction).
--
-- ROLLBACK WITHOUT A MIGRATION (both old behaviours are still callable after 0137):
--   the drift, one statement over the whole market as before:
--     select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:drift'),
--                           command := 'select public.tick_market_drift()');
--   the reconcile, one transaction as before:
--     select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:reconcile'),
--                           command := 'call public.tick_reconcile(false)');
-- A FULL ROLLBACK is a forward migration that drops the steps and the two procedures, re-creates
-- tick_reconcile() and tick_market_drift(timestamptz) from their pre-images (reconstructible here: the
-- hunks and slices are this file's text), reverses world.market's one hunk, and points the jobs back.
-- SUPERSEDES: public.npc_tend (0123), public.tick_reconcile (0114), public.tick_market_drift (0123),
-- world.market (0122).
-- VERSION: 0137. Applies on 0136 (PR #140; depends on #139 and #140). Prod head is 0139 (0138 S14 #143,
-- 0139 the draft gate removed #145), so 0137 goes on OUT OF ORDER: `supabase db push --linked
-- --include-all`. Nothing here assumes it is the newest file: 0138 adds catalogue rows and 0139 re-cuts
-- npc_feasible_legs / npc_loop_candidates / voyage.sail_refusal — none of which this file reads or
-- replaces; every pre-image is read live from the target (asserted once each). Proved in that order on
-- the cached PGlite world: 0137 applied AFTER 0138 and 0139 (renamed to sort last, not committed) —
-- receipt ok, the same counts as in chain order.
--
-- ── SELF-ASSERT CORRECTED AFTER DEPLOY (2026-10-18; §4's harness only — no function body, no data) ─
-- PRODUCTION RAN THE EARLIER TEXT of this file (pushed 2026-10-17; its self-assert passed there). The
-- ONE change since is in §4's proof harness: pg_temp.pin_hull_order_0137, called at the top of every
-- rolled-back run. WHY: main's full acceptance (job 117389612522, the growth test) failed §4 on one
-- merchant — old and new wrote the same receipt, ducats, quay and ledger, but a different SPLIT of her
-- cargo between two identical hulls (ships 10 vs 8 updates), hence a different laden speed and voyage
-- (orders, voyages). public.fleet_load (`order by cap desc`) and public.fleet_unload (`order by have
-- desc`) — neither touched by 0137 — leave a tie between equal hulls to the heap's physical order, and
-- the first run of a pair, though rolled back, leaves its dead tuples on the pages, so the second run's
-- updated rows land elsewhere and the tie can break the other way. Reproduced on PGlite: NEW against
-- NEW, the same p_now, one merchant in 837 split her two parcels differently (6.1547 vs 6.3263 kn), every
-- repeat; with the hull order pinned, 0 of 837. The corrected file passes there (12 sampled and all 837).
-- The pin re-creates the two loaders, inside each rolled-back run, from their LIVE text with `, s.id`
-- added to that one ORDER BY (asserted to occur exactly once each), so both runs of a pair break the
-- tie alike; the compare itself (receipt + every own write, row by row) is unchanged. The edit moves
-- this file's hash: an edited migration is CI's exemption (docs/CI.md §2) — the growth test runs on
-- the PR. Production is not re-applied (0137 is recorded there); nothing live changes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════


do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0137(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- the text of p_hay from the start of p_from to the end of p_to; each anchor must occur exactly once
create or replace function pg_temp.slice_0137(p_hay text, p_from text, p_to text)
returns text
language plpgsql
immutable
as $$
begin
  if pg_temp.occurs_0137(p_hay, p_from) <> 1 or pg_temp.occurs_0137(p_hay, p_to) <> 1 then
    raise exception '0137 self-assert FAIL: an anchor does not occur exactly once (% × "%", % × "%")',
      pg_temp.occurs_0137(p_hay, p_from), left(p_from, 60), pg_temp.occurs_0137(p_hay, p_to), left(p_to, 60);
  end if;
  if strpos(p_hay, p_to) < strpos(p_hay, p_from) then
    raise exception '0137 self-assert FAIL: anchor "%" lies before "%"', left(p_to, 60), left(p_from, 60);
  end if;
  return substr(p_hay, strpos(p_hay, p_from), strpos(p_hay, p_to) + length(p_to) - strpos(p_hay, p_from));
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0137 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_tend(timestamptz, uuid)'),
               ('public.tick_reconcile()'),
               ('public.tick_market_drift(timestamptz)'),
               ('world.market(uuid)')) f(fn);

-- THE OLD COPIES the proof runs against the new bodies. npc_tend's callees are untouched by this file
-- (npc_plan, npc_invest, the cmd doors, credit), so the copy calls the live ones; asserted below that
-- it calls none of the new steps.
do $$
declare
  v_def text;
begin
  select def into v_def from defs_before_0137 where fn = 'public.npc_tend(timestamptz, uuid)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.npc_tend(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_tend_old_0137(');
  if strpos(v_def, 'FUNCTION pg_temp.npc_tend_old_0137(') = 0 or strpos(v_def, 'npc_tend_route') > 0
     or strpos(v_def, 'npc_tend_roster') > 0 or strpos(v_def, 'npc_tend_houses') > 0 then
    raise exception '0137 self-assert FAIL: the old copy of npc_tend was not made from the pre-image';
  end if;
  execute v_def;
  select def into v_def from defs_before_0137 where fn = 'public.tick_market_drift(timestamptz)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.tick_market_drift(', 'CREATE OR REPLACE FUNCTION pg_temp.tick_market_drift_old_0137(');
  if strpos(v_def, 'FUNCTION pg_temp.tick_market_drift_old_0137(') = 0 or strpos(v_def, 'market_drift_at') > 0 then
    raise exception '0137 self-assert FAIL: the old copy of tick_market_drift was not made from the pre-image';
  end if;
  execute v_def;
end $$;

-- ── 2. THE MERCHANT UPKEEP, CUT INTO ITS OWN STEPS (one authority each; npc_tend composes them) ──
-- The walk: npc_tend's roster query, verbatim (asserted in §3). The walk order and k (the ROSTER rank
-- npc_fleet_max is read against) are this query's and nobody else's.
create function public.npc_tend_roster()
returns table (fleet_id uuid, route_id uuid, player_id uuid, alt_loop jsonb, k bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0137: THE merchant upkeep's walk, moved verbatim out of public.npc_tend — the route written
-- longest ago first, k = the roster rank. Read by npc_tend and by the hourly public.tick_reconcile.
#variable_conflict use_column
begin
  return query select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,
                  row_number() over (order by nf.roster_ord) as k
             from public.npc_fleets nf
             join public.players p on p.id = nf.player_id and p.is_npc
             join public.standing_routes sr0 on sr0.id = nf.route_id
            where nf.route_id is not null
            order by sr0.updated_at, nf.roster_ord;
end $$;
comment on function public.npc_tend_roster() is
  '0137: THE merchant upkeep''s walk (npc_tend''s roster query, verbatim): route written longest ago '
  'first, k = roster rank. Read by public.npc_tend and public.tick_reconcile. Server-only.';
revoke all on function public.npc_tend_roster() from public, anon, authenticated;

-- One merchant: npc_tend's per-route body, verbatim (asserted in §3). It runs inside a one-row loop,
-- so its own `continue` statements end this merchant exactly as they ended her iteration before.
create function public.npc_tend_route(p_now timestamptz, p_fleet uuid, p_route uuid, p_k bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0137: ONE merchant's upkeep — public.npc_tend's per-route body, moved verbatim (fleet then route
-- locked NOWAIT in its own subtransaction; a busy route is skipped and counted). Returns this
-- merchant's counts; public.npc_tend_sum adds them up. Called by npc_tend (one transaction) and by
-- the hourly public.tick_reconcile (one transaction PER MERCHANT, so the locks she takes are held
-- for her step and no longer).
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  r         record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
    begin
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;

      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'dark', 'The merchants keep to port.');
          v_dark := v_dark + 1;
        end if;
        continue;
      end if;

      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
        v_laid_n := v_laid_n + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'cannot_sail', f.status);
        continue;
      end if;

      -- A PAUSE THE WORLD MAY LIFT, and only when it may: dark/losing/reserve/edited at once;
      -- laid_up after npc_laid_up_hours; error after 6 h (updated_at dates the pause — the hourly
      -- plan skips error routes, so it cannot keep the date fresh). off_route re-assigns where she
      -- lies, if that is a stop. 'player' is never a merchant's.
      --
      -- updated_at DATES A PAUSE ONLY WHILE NOTHING HAS WRITTEN THE ROUTE SINCE. That holds for
      -- 'error' (the plan skips those) and it is what the ageing test below reads; it does NOT hold
      -- after the plan has saved — see the receipt test further down.
      if sr.paused_reason = 'off_route' then
        if f.status = 'DOCKED'
           and exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
          v_resumed := v_resumed + 1;
        else
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'off_route', f.status);
        end if;
        continue;
      end if;
      if sr.paused_reason is not null
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited', 'laid_up')   -- 0115: laid_up at once
                  or (sr.paused_reason = 'error' and sr.updated_at < p_now - interval '6 hours')) then
        continue;
      end if;

      -- 0114: THE BUDGET gates the dear work only — a plan and a start or a resume, and the halt
      -- law's release below. The dark and cannot-sail lay-ups above stay unconditional.
      if (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;

      -- NOT STARTED, OR A PAUSE TO LIFT: plan first (the lines are the market's NOW), then start
      -- her where she lies, or resume her. The plan may lay her up (nothing pays): then she waits.
      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'resumed_after_error', true);
        end if;
        v_res := public.npc_plan(p_now, sr.id);
        select * into sr from public.standing_routes where id = r.route_id;
        -- DID THIS PLAN LAY HER UP? THE PLAN'S OWN RECEIPT SAYS SO — NEVER updated_at. The save
        -- door (cmd.standing_route_save_for) sets updated_at = now(), so after a SUCCESSFUL plan an
        -- `updated_at >= p_now - v_laid` test is always true at p_now = now(): it skipped every
        -- laid-up route it had just re-planned, the resume and start branches below were
        -- unreachable for that reason, and every merchant laid up for want of cargo stayed laid up
        -- for ever (found by the 2026-10-08 review; the ageing test above still gates WHEN she is
        -- re-planned at all). `planned` is this call's own count, and p_route pins the call to this
        -- one route, so planned = 0 means she was NOT re-planned — laid up again (nothing pays),
        -- busy, or failed — and she waits. Both arms are acceptable outcomes (NO_SPAGHETTI §7C):
        -- resume on fresh lines, or wait; she is never resumed on stale ones.
        --
        -- AND THAT HOLDS FOR EVERY PAUSE, not only 'laid_up' (the 2026-10-10 review): a dark or
        -- losing route whose plan RAISED would otherwise have been resumed on week-old lines, which
        -- is the very thing the sentence above claims never happens. Counted in the notes, so a
        -- route that is never planned is visible in the receipt rather than silently stuck.
        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        if sr.fleet_id is null then
          if f.status = 'DOCKED' then
            v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
            if coalesce((v_res->>'ok')::boolean, false) then
              v_started := v_started + 1;
            else
              v_notes := v_notes || jsonb_build_object('route', sr.name, 'start', v_res->>'error_code');
            end if;
          end if;
        elsif sr.paused_reason is not null then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
          v_resumed := v_resumed + 1;
        end if;
        continue;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
      if fo.id is not null and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
          'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
          'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        if v_clears >= 3 then
          perform public.npc_plan(p_now, sr.id);
        end if;
        perform cmd.clear_for(sr.player_id, r.fleet_id, false);
        perform cmd.advance(r.fleet_id, p_now);
        v_cleared := v_cleared + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dark', v_dark, 'started', v_started, 'resumed', v_resumed, 'cleared', v_cleared,
                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'notes', v_notes);
end $$;
comment on function public.npc_tend_route(timestamptz, uuid, uuid, bigint) is
  '0137: ONE merchant''s upkeep (npc_tend''s per-route body, verbatim). Composed by public.npc_tend '
  '(one transaction) and public.tick_reconcile (one transaction per merchant). Server-only.';
revoke all on function public.npc_tend_route(timestamptz, uuid, uuid, bigint) from public, anon, authenticated;

-- The companies: npc_tend's investment and refound passes, verbatim (asserted in §3) but for the
-- gate, which loses `and p_route is null` — the caller decides whether the companies are tended.
create function public.npc_tend_houses(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0137: THE companies' upkeep — public.npc_tend's investment (public.npc_invest) and refound passes,
-- moved verbatim. npc_tend runs it after the routes when no single route was asked for; the hourly
-- public.tick_reconcile runs it in its own transaction after the routes.
declare
  v_on      boolean := public.npc_traders_on();
  hh        record;
  v_last    timestamptz;
  v_week    int;
  v_refound int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_can      bigint;
  v_unfunded int := 0;
  v_inv      jsonb := '{}'::jsonb;
  v_notes   jsonb := '[]'::jsonb;
begin
  -- 0123: INVESTMENT — merchants put their surplus into the cities of their loop (public.npc_invest).
  if v_on then
    v_inv := public.npc_invest(p_now);
    v_deferred := v_deferred + coalesce((v_inv->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_inv->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- REFOUNDS, per company, only while the switch is on.
  if v_on then
    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        -- 0115: NO WEEKLY CAP THAT PARKS A COMPANY. A purse under the floor is refounded (the
        -- cooldown still spaces refounds); the cap's lay-up and loop swap are deleted.
        if not public.city_treasury_on() then
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        else
          -- 0122: lit, the HOME HARBOUR pays, from its surplus — partially, or not at all. A merchant
          -- whose home cannot pay sails on at her purse floor until it earns (never parked, 0115).
          v_can := greatest(0, least(hh.capital - hh.ducats, public.city_surplus(hh.home_port_id)));
          if v_can > 0 then
            perform public.city_pays(hh.home_port_id, hh.player_id, 'NPC_REFOUND', v_can,
              public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
                'company', hh.company_name, 'amount', v_can, 'week', coalesce(v_week, 0) + 1,
                'port', (select p.code from public.ports p where p.id = hh.home_port_id),
                'partial', v_can < hh.capital - hh.ducats)));
            v_refound := v_refound + 1;
          else
            v_unfunded := v_unfunded + 1;
          end if;
        end if;
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('refounded', v_refound, 'refound_unfunded', v_unfunded,
                            'invested', coalesce((v_inv->>'invested')::int, 0),
                            'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $$;
comment on function public.npc_tend_houses(timestamptz) is
  '0137: THE companies'' upkeep (npc_tend''s investment and refound passes, verbatim). Composed by '
  'public.npc_tend and public.tick_reconcile. Server-only.';
revoke all on function public.npc_tend_houses(timestamptz) from public, anon, authenticated;

-- The receipt's one adder: every count npc_tend has ever reported, summed; notes in order.
create function public.npc_tend_sum(p_a jsonb, p_b jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
-- 0137: THE one place npc_tend's receipt is added up — the counts of two steps summed (a missing
-- count is 0), their notes concatenated in order. npc_tend_sum(x, '{}') is x with every count present.
declare
  v_k text;
  v   jsonb := jsonb_build_object('notes', coalesce(p_a->'notes', '[]'::jsonb) || coalesce(p_b->'notes', '[]'::jsonb));
begin
  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up', 'refounded', 'refound_unfunded',
                             'invested', 'busy', 'failed', 'deferred'] loop
    v := v || jsonb_build_object(v_k, coalesce((p_a->>v_k)::int, 0) + coalesce((p_b->>v_k)::int, 0));
  end loop;
  return v;
end $$;
comment on function public.npc_tend_sum(jsonb, jsonb) is
  '0137: THE adder of npc_tend''s receipt (counts summed, notes concatenated). Server-only.';
revoke all on function public.npc_tend_sum(jsonb, jsonb) from public, anon, authenticated;

-- A step of the hourly upkeep that raised: the receipt fragment npc_tend_sum adds — one failure,
-- one note naming the step and the error, the same shape npc_tend_route's own failures have.
create function public.npc_step_failed(p_where jsonb, p_error text)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
-- 0137: THE receipt of an hourly-upkeep step that raised and was rolled back alone (its error, or
-- the purse it broke — public.tick_reconcile checks the ledger inside the step, before its COMMIT):
-- failed 1, and one note, p_where || {error}. Added up by public.npc_tend_sum like any count.
begin
  return jsonb_build_object('failed', 1, 'notes', jsonb_build_array(p_where || jsonb_build_object('error', p_error)));
end $$;
comment on function public.npc_step_failed(jsonb, text) is
  '0137: THE receipt of an hourly-upkeep step that raised and was rolled back alone (failed 1, one '
  'note). Read by public.tick_reconcile. Server-only.';
revoke all on function public.npc_step_failed(jsonb, text) from public, anon, authenticated;

-- The budget's scope: set here and nowhere else (0114's deadline and 0097's lock_timeout, both
-- transaction-local — so the hourly upkeep sets them again at the start of each of its transactions).
create function public.npc_upkeep_scope(p_deadline timestamptz)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
-- 0137: THE scope of one transaction of the hourly merchant upkeep: never wait on a lock longer than
-- 2 s (0097), and stop the dear work at the hour's deadline (0114; read by public.npc_upkeep_spent).
-- Both transaction-local. Called by public.tick_reconcile alone.
begin
  perform set_config('lock_timeout', '2s', true);
  perform set_config('byeharu.npc_upkeep_deadline', p_deadline::text, true);
end $$;
comment on function public.npc_upkeep_scope(timestamptz) is
  '0137: THE scope of one transaction of the hourly merchant upkeep (lock_timeout 2 s, the 0114 '
  'deadline), transaction-local. Called by public.tick_reconcile alone. Server-only.';
revoke all on function public.npc_upkeep_scope(timestamptz) from public, anon, authenticated;

-- npc_tend: the same receipt, the same work, in one transaction — now the composition of the above.
create or replace function public.npc_tend(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- What the world does for a merchant that a player would do by hand — through the route cores,
-- cmd.clear_for + cmd.advance, and public.credit; nothing else. Per route, fleet then route locked
-- NOWAIT inside its own subtransaction (a busy route is skipped, counted, never waited for):
--   switch OFF, or beyond npc_fleet_max in roster order -> paused 'dark' (fleets at sea finish
--     their leg and lie in port).
--   ADRIFT / UNABLE_TO_SAIL -> counted and left (0115: never parked; there is no RECALL or salvage
--     verb for anybody, so the executor waits for her).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once (0115: a lay-up is
--     legacy — nothing writes one any more); whether THIS call re-planned her is read off the
--     plan's receipt, not off updated_at (the save bumps it). error -> the same after 6 h (the
--     pause is dated by updated_at). off_route -> re-assigned if she lies at a stop; otherwise
--     reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between re-plans her lines first (0115).
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- 0137: the steps live in their own functions — public.npc_tend_roster (the walk),
-- public.npc_tend_route (one merchant), public.npc_tend_houses (the companies), public.npc_tend_sum (the
-- receipt). This is their one-transaction composition; the hourly public.tick_reconcile composes the
-- same steps one transaction each.
declare
  v_on  boolean := public.npc_traders_on();
  r     record;
  v_acc jsonb := '{}'::jsonb;
begin
  for r in select * from public.npc_tend_roster() loop
    continue when p_route is not null and r.route_id <> p_route;
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
  end loop;
  if p_route is null then
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_houses(p_now));
  end if;
  return jsonb_build_object('enabled', v_on) || public.npc_tend_sum(v_acc, '{}'::jsonb);
end $$;

-- ── 3. THE MOVED TEXT IS THE OLD TEXT (reverse-to-original, byte for byte) ──────────────────────
-- The pre-image is cut at six anchors into: [head] roster [glue] route [glue] houses [receipt]. The
-- roster, route and houses slices must be found, byte-equal, in the new functions (the houses slice
-- after its one hunk is reversed), and the two glues must be exactly the loop's own lines — so no
-- line of the old body was dropped between the slices. The head (declarations) and the receipt are
-- re-written in the new bodies; §4 proves them by behaviour.
do $$
declare
  v_old    text := (select def from defs_before_0137 where fn = 'public.npc_tend(timestamptz, uuid)');
  v_roster text := replace(pg_get_functiondef('public.npc_tend_roster()'::regprocedure), E'\r', '');
  v_route  text := replace(pg_get_functiondef('public.npc_tend_route(timestamptz, uuid, uuid, bigint)'::regprocedure), E'\r', '');
  v_houses text := replace(pg_get_functiondef('public.npc_tend_houses(timestamptz)'::regprocedure), E'\r', '');
  v_tend   text := replace(pg_get_functiondef('public.npc_tend(timestamptz, uuid)'::regprocedure), E'\r', '');
  a1 text := 'select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,';
  a2 text := 'order by sr0.updated_at, nf.roster_ord';
  a3 text := E'    begin\n      perform 1 from public.fleets where id = r.fleet_id for update nowait;';
  a4 text := E'        v_notes := v_notes || jsonb_build_object(''route'', r.route_id, ''error'', sqlerrm);\n    end;';
  a5 text := '  -- 0123: INVESTMENT';
  a6 text := E'        v_notes := v_notes || jsonb_build_object(''company'', hh.company_name, ''error'', sqlerrm);\n      end;\n    end loop;\n  end if;';
  s_roster text;
  s_route  text;
  s_houses text;
  v_new_h  text;
  v_glue1  text;
  v_glue2  text;
  b        record;
begin
  s_roster := pg_temp.slice_0137(v_old, a1, a2);
  s_route  := pg_temp.slice_0137(v_old, a3, a4);
  s_houses := pg_temp.slice_0137(v_old, a5, a6);
  if pg_temp.slice_0137(v_roster, a1, a2) <> s_roster then
    raise exception '0137 self-assert FAIL: npc_tend_roster''s query is not npc_tend''s walk, verbatim';
  end if;
  if pg_temp.slice_0137(v_route, a3, a4) <> s_route then
    raise exception '0137 self-assert FAIL: npc_tend_route''s body is not npc_tend''s per-route body, verbatim';
  end if;
  v_new_h := pg_temp.slice_0137(v_houses, a5, a6);
  if pg_temp.occurs_0137(v_new_h, E'\n  if v_on then\n') <> 2 or strpos(v_new_h, 'p_route') > 0 then
    raise exception '0137 self-assert FAIL: npc_tend_houses'' two gates are not the one hunk';
  end if;
  if replace(v_new_h, E'\n  if v_on then\n', E'\n  if v_on and p_route is null then\n') <> s_houses then
    raise exception '0137 self-assert FAIL: npc_tend_houses'' body does not reverse to npc_tend''s companies passes';
  end if;
  v_glue1 := substr(v_old, strpos(v_old, a2) + length(a2), strpos(v_old, a3) - strpos(v_old, a2) - length(a2));
  v_glue2 := substr(v_old, strpos(v_old, a4) + length(a4), strpos(v_old, a5) - strpos(v_old, a4) - length(a4));
  if v_glue1 <> E' loop\n    continue when p_route is not null and r.route_id <> p_route;\n'
     or v_glue2 <> E'\n  end loop;\n\n'
     or right(substr(v_old, 1, strpos(v_old, a1) - 1), 11) <> '  for r in '
     or strpos(substr(v_old, strpos(v_old, a6) + length(a6)), E'\n\n  return jsonb_build_object(''enabled'', v_on, ') <> 1 then
    raise exception '0137 self-assert FAIL: the pre-image has text between its slices that this file did not account for';
  end if;
  -- the new npc_tend carries none of the moved text, and keeps its attributes and ACL
  if strpos(v_tend, a3) > 0 or strpos(v_tend, a5) > 0 or strpos(v_tend, a1) > 0 then
    raise exception '0137 self-assert FAIL: npc_tend still carries a moved step (a second copy)';
  end if;
  select * into b from defs_before_0137 where fn = 'public.npc_tend(timestamptz, uuid)';
  if (select p.prosecdef from pg_proc p where p.oid = 'public.npc_tend(timestamptz, uuid)'::regprocedure) <> b.secdef
     or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.npc_tend(timestamptz, uuid)'::regprocedure) <> b.cfg
     or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.npc_tend(timestamptz, uuid)'::regprocedure) <> b.acl then
    raise exception '0137 self-assert FAIL: npc_tend''s security, settings or ACL moved';
  end if;
  -- the steps are server-only
  if exists (select 1 from unnest(array['public.npc_tend_roster()', 'public.npc_tend_route(timestamptz, uuid, uuid, bigint)',
                                        'public.npc_tend_houses(timestamptz)', 'public.npc_tend_sum(jsonb, jsonb)',
                                        'public.npc_step_failed(jsonb, text)', 'public.npc_upkeep_scope(timestamptz)']) f
              where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0137 self-assert FAIL: a client can execute an upkeep step';
  end if;
end $$;

-- ── 4. OLD AND NEW TEND THE SAME WORLD (each run rolled back; only the run's OWN writes compared) ──
-- Production is lived in while this file applies: players trade and settle, and their commits land
-- between two runs. So nothing here counts or hashes a whole table. What is compared, per run:
--   * npc_tend's receipt;
--   * the run's OWN writes, per table of public / world / cmd / voyage: the rows it inserted, updated
--     and deleted (pg_stat_xact_all_tables — this backend's transaction alone, an aborted
--     subtransaction's attempts included, so it is read before and after the run, inside it), and,
--     for every table it wrote, the md5 of the rows whose xmin is a transaction of THIS backend still
--     in progress (pg_xact_status = 'in progress'; another session's rows are committed or invisible),
--     uuids blanked because the doors mint fresh ones.
-- Runs, old then new, each pair on the world as it stands:
--   (a) the WHOLE pass with the hour's budget already spent — every merchant walked (the dark and
--       cannot-sail lay-ups, off-route re-assigns, the halt law's deferral), the investment pass
--       deferred, every refound due;
--   (b) 12 merchants ONE AT A TIME (p_route), budget unset, those with dear work first (unstarted,
--       paused, or a failed order at the head of her queue): plans, starts, resumes, clears. One pair
--       per merchant, so the rows a merchant's trade locks are held for her two runs, never for twelve.
-- The merchants are switched on inside each run when the world has them off (PGlite / CI); prod has
-- them on, and the update then writes nothing. The instrument is proven able to see a write first.
create or replace function pg_temp.writes_0137()
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  select coalesce(jsonb_object_agg(s.schemaname || '.' || s.relname,
                                   jsonb_build_array(s.n_tup_ins, s.n_tup_upd, s.n_tup_del)), '{}'::jsonb)
    into v
    from pg_stat_xact_all_tables s
   where s.schemaname in ('public', 'world', 'cmd', 'voyage');
  return v;
end $$;

-- what the run wrote since p_before: per table it touched, its [inserted, updated, deleted] and the
-- md5 of the rows this backend's open transaction wrote (p_base: this file's xid, low 32 bits;
-- p_epoch: its epoch × 2^32, so a 32-bit xmin can be asked about as an xid8)
create or replace function pg_temp.digest_0137(p_before jsonb, p_base bigint, p_epoch bigint)
returns jsonb
language plpgsql
as $$
declare
  v_after jsonb := pg_temp.writes_0137();
  v       jsonb := '{}'::jsonb;
  v_k     text;
  v_w     jsonb;
  v_n     bigint;
  v_md5   text;
begin
  for v_k in select k from jsonb_object_keys(v_after) k order by k loop
    v_w := jsonb_build_array((v_after->v_k->>0)::bigint - coalesce((p_before->v_k->>0)::bigint, 0),
                             (v_after->v_k->>1)::bigint - coalesce((p_before->v_k->>1)::bigint, 0),
                             (v_after->v_k->>2)::bigint - coalesce((p_before->v_k->>2)::bigint, 0));
    continue when v_w = '[0, 0, 0]'::jsonb;
    execute format($q$select count(*), md5(coalesce(string_agg(t.r, E'\n' order by t.r), ''))
                        from (select regexp_replace(row_to_json(x)::text,
                                       '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g') as r
                                from %I.%I x
                               where x.xmin::text::bigint >= $1
                                 and pg_xact_status(($2 + x.xmin::text::bigint)::text::xid8) = 'in progress') t$q$,
                   split_part(v_k, '.', 1), split_part(v_k, '.', 2))
      into v_n, v_md5 using p_base, p_epoch;
    v := v || jsonb_build_object(v_k, jsonb_build_object('writes', v_w, 'own_rows', v_n, 'md5', v_md5));
  end loop;
  return v;
end $$;

create temp table tend_sample_0137 on commit drop as
select nf.route_id
  from public.npc_fleets nf
  join public.players p on p.id = nf.player_id and p.is_npc
  join public.standing_routes sr on sr.id = nf.route_id
 order by (sr.fleet_id is null or sr.paused_reason is not null
           or exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status = 'failed')) desc,
          md5(nf.route_id::text), nf.route_id
 limit 12;

-- THE HULL ORDER, PINNED FOR THE PROOF (added after deploy — see the header). fleet_load and
-- fleet_unload give a parcel to hulls `order by cap desc` / `order by have desc`; between equal hulls
-- the heap's physical order decides, and a rolled-back first run changes where the second run's rows
-- land. Each run re-creates both from their LIVE text with `, s.id` added to that ORDER BY, inside its
-- own rolled-back subtransaction, so old and new break the tie alike and nothing outlives the run.
create or replace function pg_temp.pin_hull_order_0137()
returns void
language plpgsql
as $$
declare
  r     record;
  v_def text;
  v_n   int;
begin
  for r in select * from (values
             ('public.fleet_load(uuid,text,numeric,numeric)'::regprocedure,
              'where s.fleet_id = p_fleet order by cap desc loop',
              'where s.fleet_id = p_fleet order by cap desc, s.id loop'),
             ('public.fleet_unload(uuid,text,numeric)'::regprocedure,
              'where s.fleet_id = p_fleet order by have desc loop',
              'where s.fleet_id = p_fleet order by have desc, s.id loop')) v(fn, old_line, new_line) loop
    v_def := pg_get_functiondef(r.fn);
    v_n := (length(v_def) - length(replace(v_def, r.old_line, ''))) / length(r.old_line);
    if v_n <> 1 then
      raise exception '0137 self-assert FAIL: the hull order of % was not found exactly once (% times): %', r.fn, v_n, r.old_line;
    end if;
    execute replace(v_def, r.old_line, r.new_line);
  end loop;
end $$;

-- one run: p_route null = the whole pass, budget spent; else that one merchant, no budget
create or replace function pg_temp.tend_run_0137(p_old boolean, p_now timestamptz, p_route uuid, p_base bigint, p_epoch bigint)
returns jsonb
language plpgsql
as $$
declare
  v_before jsonb;
  v_t0     timestamptz;
  v_r      jsonb;
begin
  perform pg_temp.pin_hull_order_0137();   -- after deploy: catalogue only, no table row written
  v_before := pg_temp.writes_0137();
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
  perform set_config('byeharu.npc_upkeep_deadline', case when p_route is null then '2000-01-01 00:00:00+00' else '' end, true);
  v_t0 := clock_timestamp();
  if p_old and p_route is null then
    v_r := pg_temp.npc_tend_old_0137(p_now);
  elsif p_old then
    v_r := pg_temp.npc_tend_old_0137(p_now, p_route);
  elsif p_route is null then
    v_r := public.npc_tend(p_now);
  else
    v_r := public.npc_tend(p_now, p_route);
  end if;
  return jsonb_build_object('receipt', v_r, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                            'digest', pg_temp.digest_0137(v_before, p_base, p_epoch));
end $$;

-- old then new, each rolled back; raises on any difference; returns the pair's measure
create or replace function pg_temp.tend_pair_0137(p_now timestamptz, p_route uuid, p_base bigint, p_epoch bigint)
returns jsonb
language plpgsql
as $$
declare
  v_old  jsonb;
  v_new  jsonb;
  v_what text := coalesce('merchant route ' || p_route::text, 'the whole pass (budget spent)');
begin
  begin
    v_old := pg_temp.tend_run_0137(true, p_now, p_route, p_base, p_epoch);
    raise exception using errcode = 'ZX137', message = v_old::text;
  exception when sqlstate 'ZX137' then
    v_old := sqlerrm::jsonb;
  end;
  begin
    v_new := pg_temp.tend_run_0137(false, p_now, p_route, p_base, p_epoch);
    raise exception using errcode = 'ZX137', message = v_new::text;
  exception when sqlstate 'ZX137' then
    v_new := sqlerrm::jsonb;
  end;
  if v_old->'receipt' is distinct from v_new->'receipt' then
    raise exception '0137 self-assert FAIL: % — the receipt moved: old % / new %', v_what, v_old->'receipt', v_new->'receipt';
  end if;
  if v_old->'digest' is distinct from v_new->'digest' then
    raise exception '0137 self-assert FAIL: % — the run wrote a different state: old % / new %', v_what, v_old->'digest', v_new->'digest';
  end if;
  return jsonb_build_object('old_ms', v_old->'ms', 'new_ms', v_new->'ms', 'receipt', v_new->'receipt',
    'tables',  (select count(*) from jsonb_object_keys(v_new->'digest')),
    'rows',    (select coalesce(sum((e.value->>'own_rows')::bigint), 0) from jsonb_each(v_new->'digest') e),
    'deleted', (select coalesce(sum((e.value->'writes'->>2)::bigint), 0) from jsonb_each(v_new->'digest') e));
end $$;

do $$
declare
  v_xid   bigint := pg_current_xact_id()::text::bigint;
  v_base  bigint := v_xid % 4294967296;
  v_epoch bigint := v_xid - v_xid % 4294967296;
  v_now   timestamptz := now();
  v_probe jsonb;
  v_whole jsonb;
  v_one   jsonb;
  s       record;
  v_n     int := 0;
  v_tabs  int := 0;
  v_rows  bigint := 0;
  v_ms_o  bigint := 0;
  v_ms_n  bigint := 0;
begin
  -- THE INSTRUMENT SEES A WRITE (positive control): one row updated in a rolled-back subtransaction
  -- is exactly one updated row of exactly one table, and exactly one own row.
  begin
    v_probe := pg_temp.writes_0137();
    update public.world_config set value = value where key = 'drift_sigma';
    v_probe := pg_temp.digest_0137(v_probe, v_base, v_epoch);
    raise exception using errcode = 'ZX137', message = v_probe::text;
  exception when sqlstate 'ZX137' then
    v_probe := sqlerrm::jsonb;
  end;
  if (select count(*) from jsonb_object_keys(v_probe)) <> 1
     or v_probe->'public.world_config'->'writes' is distinct from '[0, 1, 0]'::jsonb
     or (v_probe->'public.world_config'->>'own_rows')::int <> 1 then
    raise exception '0137 self-assert FAIL: the own-write instrument did not see exactly one updated row: %', v_probe;
  end if;

  v_whole := pg_temp.tend_pair_0137(v_now, null, v_base, v_epoch);
  raise notice '0137 probe: the whole pass (budget spent) old % ms / new % ms', v_whole->>'old_ms', v_whole->>'new_ms';
  for s in select route_id from tend_sample_0137 order by route_id loop
    v_one := pg_temp.tend_pair_0137(v_now, s.route_id, v_base, v_epoch);
    v_n := v_n + 1;
    v_tabs := v_tabs + (v_one->>'tables')::int;
    v_rows := v_rows + (v_one->>'rows')::bigint;
    v_ms_o := v_ms_o + (v_one->>'old_ms')::bigint;
    v_ms_n := v_ms_n + (v_one->>'new_ms')::bigint;
  end loop;
  raise notice '0137 probe: % merchants one by one, old % ms / new % ms', v_n, v_ms_o, v_ms_n;
  raise notice '0137: the tend, old = new, run by run — whole pass % (budget spent; % table(s), % own row(s) written, % deleted), % merchants one by one (% table-writes, % own row(s)); compared: receipts and each run''s own writes, never a whole table',
    (v_whole->'receipt') - 'notes', v_whole->>'tables', v_whole->>'rows', v_whole->>'deleted', v_n, v_tabs, v_rows;
end $$;

-- ── 5. THE HOURLY RECONCILE, ONE TRANSACTION PER STEP ──────────────────────────────────────────
-- A PROCEDURE, so it can COMMIT between steps (pg_cron calls it with CALL, one statement, outside any
-- transaction block — prod runs cron.use_background_workers = off, i.e. a plain libpq session).
-- Transaction control forbids SECURITY DEFINER and a SET clause on the procedure itself: it runs as
-- the job's owner, every name schema-qualified; each step it calls keeps its own definer and path.
drop function public.tick_reconcile();

create procedure public.tick_reconcile(p_commit boolean default true)
language plpgsql
as $$
-- 0137: THE hourly reconcile. Merchant upkeep first — npc_tend's steps, ONE TRANSACTION EACH: every
-- merchant (public.npc_tend_route), then the companies (public.npc_tend_houses), then the compactor
-- (public.npc_compact) — each under the hour's scope (public.npc_upkeep_scope: lock_timeout 2 s and
-- 0114's deadline, which runs from the start of the hour's pass). A step's row locks are held for
-- that step and released at its COMMIT, so the arrivals sweep waits for one merchant at most, never
-- for the hour. A step that fails is reported in the receipt and rolled back alone (0097).
-- EVERY STEP IS CHECKED BEFORE IT COMMITS: a merchant's step ends with her ledger reconciling
-- (public.assert_ledger_reconciles), the companies' step with every company's — so a step that
-- breaks a purse raises inside its own block and is rolled back alone, counted in the receipt
-- (failed + a note, public.npc_step_failed) like any other step error. The compactor checks each
-- company it rolls up itself (0097). A purse already broken before the hour fails every step of
-- hers, and the whole-world pass below raises on it.
-- THEN the invariants, in their own transaction, which take no row lock (plain reads): every
-- player's ledger reconciles, the sailing invariant, no client write grant. A failure RAISES.
-- p_commit = false runs the SAME steps in the caller's transaction, committing nothing (a proof inside
-- BEGIN … ROLLBACK: `call public.tick_reconcile(false)`); the job runs the default, true. Either way
-- the steps, their order and what they decide are the same — only where the transaction ends moves.
-- What a whole pass decides is npc_tend's (asserted, 0137 §4): the same walk, the same per-merchant
-- body, the same companies' passes, the same compactor — only the commits between them are new.
declare
  v_now      timestamptz := now();
  v_deadline timestamptz := clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds'));
  v_on       boolean := public.npc_traders_on();
  r          record;
  h          record;
  v_step     jsonb;
  v_tend     jsonb := '{}'::jsonb;
  v_upkeep   jsonb := '{}'::jsonb;
  v_n        int := 0;
  v_grants   int;
begin
  for r in select * from public.npc_tend_roster() loop
    perform public.npc_upkeep_scope(v_deadline);
    begin
      v_step := public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);
      perform public.assert_ledger_reconciles(r.player_id);   -- her purse, before her COMMIT
      v_tend := public.npc_tend_sum(v_tend, v_step);
    exception when others then
      v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('route', r.route_id), sqlerrm));
    end;
    if p_commit then commit; end if;
  end loop;
  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_step := public.npc_tend_houses(v_now);
    for h in select p.id from public.players p where p.is_npc order by p.id loop
      perform public.assert_ledger_reconciles(h.id);   -- every company's purse, before the COMMIT
    end loop;
    v_tend := public.npc_tend_sum(v_tend, v_step);
  exception when others then
    v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('step', 'companies'), sqlerrm));
  end;
  if p_commit then commit; end if;
  v_upkeep := v_upkeep || jsonb_build_object('tend', jsonb_build_object('enabled', v_on) || public.npc_tend_sum(v_tend, '{}'::jsonb));
  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_upkeep := v_upkeep || jsonb_build_object('compact', public.npc_compact(v_now));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('compact_error', sqlerrm);
  end;
  if p_commit then commit; end if;
  -- THE INVARIANTS (0010/0097, unchanged — a read-only whole-world pass), on the world the upkeep left.
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
  raise notice 'tick_reconcile: %', jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok',
                                                       'client_write_grants', 0, 'merchant_upkeep', v_upkeep);
end $$;
comment on procedure public.tick_reconcile(boolean) is
  '0137: THE hourly reconcile (pg_cron byeharu-voyage:reconcile, CALL): merchant upkeep one '
  'transaction per merchant / the companies / the compactor, then the invariants. Server-only.';
revoke all on procedure public.tick_reconcile(boolean) from public, anon, authenticated;

-- THE JOB SAYS CALL. The job keeps its name, schedule, owner and active flag (0012 defined it,
-- 0078's clock_jobs() owns its activation; wind_the_clock() activates exactly this command).
do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.alter_job(j.jobid, command := 'call public.tick_reconcile()')
       from cron.job j where j.jobname = 'byeharu-voyage:reconcile';
  end if;
end $cron$;

-- ── 6. THE MARKET DRIFTS ONE HARBOUR AT A TIME, AND A QUAY DRIFTS ONLY ITSELF ──────────────────
-- public.tick_market_drift keeps its body; it gains p_port (default null = every harbour, exactly
-- as before) through two hunks, one per UPDATE. A new signature cannot be a CREATE OR REPLACE, so
-- the old one is dropped and the new one made from the pre-image's text; its ACL is the pre-image's
-- (asserted). The drift job then calls a procedure that drifts each harbour in its own transaction,
-- so a port_goods row the drift writes is held for one harbour's update, never for the whole market.
-- world.market — the client's read of one quay, ~4,000 calls a day on prod — no longer drifts the
-- WHOLE market before pricing its quay: one hunk passes its own harbour (p_port). Every harbour is
-- the drift job's; a quay a player opens is caught up for that quay alone.
create temp table hunks_0137 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0137 values
('public.tick_market_drift(timestamptz)', 0,
$h$CREATE OR REPLACE FUNCTION public.tick_market_drift(p_now timestamp with time zone DEFAULT now())$h$,
$h$CREATE OR REPLACE FUNCTION public.tick_market_drift(p_now timestamp with time zone DEFAULT now(), p_port uuid DEFAULT NULL::uuid)$h$),
('public.tick_market_drift(timestamptz)', 1,
$h$   where pg.drift_slot < v_slot;$h$,
$h$   where pg.drift_slot < v_slot
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for$h$),
('public.tick_market_drift(timestamptz)', 2,
$h$   where pg.last_regen_day < v_day;$h$,
$h$   where pg.last_regen_day < v_day
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for$h$),
('world.market(uuid)', 0,
$h$  perform public.tick_market_drift(v_now);$h$,
$h$  perform public.tick_market_drift(v_now, p_port);   -- 0137: this quay only; every harbour is the drift job's$h$);

do $$
declare
  b     record;
  h     record;
  v_def text;
  v_rev text;
begin
  select * into b from defs_before_0137 where fn = 'public.tick_market_drift(timestamptz)';
  v_def := b.def;
  for h in select * from hunks_0137 where fn = b.fn order by n loop
    if pg_temp.occurs_0137(v_def, h.old) <> 1 then
      raise exception '0137 self-assert FAIL: tick_market_drift hunk % occurs % time(s), not once', h.n, pg_temp.occurs_0137(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  -- THE PRE-IMAGE'S GRANTS, carried over grantee by grantee (a new function starts from the
  -- default privileges, which are not the same on every database)
  create temp table drift_grants_0137 on commit drop as
  select case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end as grantee
    from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.oid = 'public.tick_market_drift(timestamptz)'::regprocedure and a.grantee <> p.proowner
     and a.privilege_type = 'EXECUTE';
  drop function public.tick_market_drift(timestamptz);
  execute v_def;
  revoke all on function public.tick_market_drift(timestamptz, uuid) from public, anon, authenticated, service_role;
  for h in select grantee from drift_grants_0137 order by grantee loop
    execute format('grant execute on function public.tick_market_drift(timestamptz, uuid) to %s', h.grantee);
  end loop;
  -- REVERSE TO ORIGINAL: the live body, its hunks undone, is the pre-image byte for byte
  v_rev := replace(pg_get_functiondef('public.tick_market_drift(timestamptz, uuid)'::regprocedure), E'\r', '');
  for h in select * from hunks_0137 where fn = b.fn order by n desc loop
    if pg_temp.occurs_0137(v_rev, h.new) <> 1 then
      raise exception '0137 self-assert FAIL: tick_market_drift''s new hunk % is not in the live body once', h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> b.def then
    raise exception '0137 self-assert FAIL: tick_market_drift does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure), '') <> b.acl
     or (select p.prosecdef from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) <> b.secdef
     or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) <> b.cfg
     or (select p.provolatile from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) <> b.vol then
    raise exception '0137 self-assert FAIL: tick_market_drift''s ACL, security, settings or volatility moved';
  end if;

  -- world.market: ONE hunk, sliced out of the live body (same signature: CREATE OR REPLACE keeps
  -- its ACL, owner, definer and path — asserted), and the live body reverses to the pre-image.
  select * into b from defs_before_0137 where fn = 'world.market(uuid)';
  select * into h from hunks_0137 where fn = b.fn and n = 0;
  if pg_temp.occurs_0137(b.def, h.old) <> 1 or pg_temp.occurs_0137(b.def, 'tick_market_drift(') <> 1 then
    raise exception '0137 self-assert FAIL: world.market does not call the drift exactly once, as "%" (% × the hunk, % × any call) — the deployed body is not what this file was written against',
      h.old, pg_temp.occurs_0137(b.def, h.old), pg_temp.occurs_0137(b.def, 'tick_market_drift(');
  end if;
  execute replace(b.def, h.old, h.new);
  v_rev := replace(pg_get_functiondef('world.market(uuid)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0137(v_rev, h.new) <> 1 or replace(v_rev, h.new, h.old) <> b.def then
    raise exception '0137 self-assert FAIL: world.market does not reverse to its pre-image through its one hunk';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'world.market(uuid)'::regprocedure), '') <> b.acl
     or (select p.prosecdef from pg_proc p where p.oid = 'world.market(uuid)'::regprocedure) <> b.secdef
     or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.market(uuid)'::regprocedure) <> b.cfg
     or (select p.provolatile from pg_proc p where p.oid = 'world.market(uuid)'::regprocedure) <> b.vol then
    raise exception '0137 self-assert FAIL: world.market''s ACL, security, settings or volatility moved';
  end if;
end $$;

create procedure public.tick_market_drift_each_port()
language plpgsql
as $$
-- 0137: THE drift job (pg_cron byeharu-voyage:drift, CALL). public.tick_market_drift, one harbour
-- per transaction, every harbour in order, all at the one moment the job started (so every harbour
-- lands on the same drift slot and game-day the whole-market call would have). No SECURITY DEFINER,
-- no SET: a procedure that commits may carry neither; it runs as the job's owner.
-- A HARBOUR THAT DEADLOCKS (40P01 — prod's drift failed 8.8 % of its runs on one, in the
-- regeneration UPDATE, against a quay read or a trade) OR TIMES OUT ON A LOCK (55P03) is rolled back
-- alone, WARNED (the server log) and counted, and the run goes on to the next harbour. It loses
-- this slot's drift step only: its rows keep their slot and day, so the next run drifts it, and
-- the regeneration is closed-form over the days missed. Any other error still raises.
declare
  v_now  timestamptz := now();
  p      record;
  v_n    int := 0;
  v_r    int := 0;
  v_skip int := 0;
  v_j    jsonb;
  v_last jsonb;
begin
  for p in select po.id, po.code from public.ports po order by po.id loop
    begin
      v_j := public.tick_market_drift(v_now, p.id);
      v_n := v_n + (v_j->>'drifted')::int;
      v_r := v_r + (v_j->>'regenerated')::int;
      v_last := v_j;
    exception when deadlock_detected or lock_not_available then
      v_skip := v_skip + 1;
      raise warning 'tick_market_drift_each_port: harbour % skipped this slot (SQLSTATE %: %); the next run drifts it',
        p.code, sqlstate, sqlerrm;
    end;
    commit;
  end loop;
  raise notice 'tick_market_drift_each_port: % drifted, % regenerated, % harbour(s) skipped (deadlock / lock timeout), slot %, game-day %',
    v_n, v_r, v_skip, v_last->>'slot', v_last->>'game_day';
end $$;
comment on procedure public.tick_market_drift_each_port() is
  '0137: THE drift job (CALL): public.tick_market_drift one harbour per transaction, all at the job''s '
  'start time; a harbour that deadlocks or times out on a lock is skipped, warned and counted. Server-only.';
revoke all on procedure public.tick_market_drift_each_port() from public, anon, authenticated;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.alter_job(j.jobid, command := 'call public.tick_market_drift_each_port()')
       from cron.job j where j.jobname = 'byeharu-voyage:drift';
  end if;
end $cron$;

-- ── 6b. OLD AND NEW DRIFT, AND OLD AND NEW QUAY READS, ON A BOUNDED SAMPLE ─────────────────────
-- NOT the whole market: an UPDATE of all 132,090 port_goods rows would hold every row a player can
-- trade for tens of seconds while this file is open (a trade gives up at 8 s). The sample is a
-- handful of harbours chosen to cover every arm of the drift (below), and ONLY their rows are
-- locked — FOR UPDATE, in ctid order (the order a whole-market UPDATE walks, so the two cannot
-- deadlock), from here to this file's COMMIT (the rest of the file is catalogue checks, ms). A
-- locked row cannot move under the probe, so old and new read the same input.
--   THE PROBE MOMENT T lies at or before every row's drift slot and regeneration day in the whole
-- market, so at T NO row outside the sample is due — the old whole-market body therefore writes
-- the sample's rows and nothing else (asserted: its own-write count is the sample's). Inside each
-- run the sample's rows are made due at T (slot and day one before), drift_sigma is 0 (the draw is
-- random() by design, 0010) and six rows are bent so every arm is taken whatever the world holds:
--   row 1 drift = +2·clamp/θ (the upper clamp binds), row 2 −2·clamp/θ (the lower clamp binds),
--   row 3 already on T's slot (NOT drifted), row 4 already on T's day (NOT regenerated),
--   row 5 stock 0 (regenerates below the target), row 6 stock 2 × target (least() pulls it to target).
-- Production > 0 and a works factor ≠ 1 are taken from the world (a harbour with each is in the
-- sample whenever the world has one — asserted).
-- old: the pre-image, whole market, at T. new: the new body harbour by harbour, as the job runs it —
-- each call must drift exactly its own harbour's due rows. Compared: the counts, and the run's own
-- writes (§4's instrument — so a row outside the sample written by either run is a difference).
-- THEN world.market, old (pre-image: drifts the whole market, then prices) vs new (drifts its quay,
-- then prices), every sample harbour, the same moment and bending: the payloads must be equal.
-- The two copies differ from their live bodies in ONE line each — `v_now := now()` reads T — and the
-- old one calls the old drift (asserted, each replacement exactly once).
create temp table drift_sample_0137 on commit drop as
with per_port as (
  select pg.port_id,
         count(*) filter (where pg.production_rate > 0) as producing,
         count(*) filter (where pg.stock < pg.stock_target) as short,
         count(*) as n
    from public.port_goods pg group by pg.port_id
), works as (
  -- 2026-10-18 (self-assert only): a harbour WITH A MARKET. Over every port, a world whose works all
  -- read 1 (any fresh world) took the lowest id, which is a SEA_PLACE 14 times in 252: no port_goods,
  -- no roster, an empty quay, and the quay probe below failed on a correct system.
  select po.id as port_id, public.works_factor(po.id, 'production', 'production_per_level') as f
    from public.ports po where po.id in (select port_id from per_port)
)
select distinct s.port_id from (
  (select port_id from per_port order by producing desc, port_id limit 1)
  union all (select port_id from works order by f desc, port_id limit 1)
  union all (select port_id from per_port order by short desc, port_id limit 1)
  union all (select port_id from per_port order by n, port_id limit 1)
  union all (select port_id from per_port order by n desc, port_id limit 1)
  union all (select port_id from per_port order by port_id limit 1)
  union all (select port_id from per_port order by port_id desc limit 1)) s;

create temp table drift_rows_0137 on commit drop as
select pg.port_id, pg.good_id, row_number() over (order by pg.port_id, pg.good_id) as ord
  from public.port_goods pg
 where pg.port_id in (select port_id from drift_sample_0137);

-- the in-run preparation, the same for every run: the sample due at T, six rows bent (header above)
create or replace function pg_temp.drift_prepare_0137(p_slot bigint, p_day int)
returns void
language plpgsql
as $$
declare
  v_bend numeric := round(2 * public.wc_num('drift_clamp') / public.wc_num('drift_theta'), 4);
begin
  update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
  update public.port_goods pg
     set drift_slot     = case when s.ord = 3 then p_slot else p_slot - 1 end,
         last_regen_day = case when s.ord = 4 then p_day else p_day - 1 end,
         drift          = case s.ord when 1 then v_bend when 2 then -v_bend else pg.drift end,
         stock          = case s.ord when 5 then 0 when 6 then pg.stock_target * 2 else pg.stock end
    from pg_temp.drift_rows_0137 s
   where s.port_id = pg.port_id and s.good_id = pg.good_id;
end $$;

create or replace function pg_temp.drift_run_0137(p_old boolean, p_at timestamptz, p_slot bigint, p_day int, p_base bigint, p_epoch bigint)
returns jsonb
language plpgsql
as $$
declare
  v_before jsonb := pg_temp.writes_0137();
  p        record;
  v_t0     timestamptz;
  v_n      int := 0;
  v_r      int := 0;
  v_j      jsonb;
begin
  perform pg_temp.drift_prepare_0137(p_slot, p_day);
  v_t0 := clock_timestamp();
  if p_old then
    v_j := pg_temp.tick_market_drift_old_0137(p_at);
    v_n := (v_j->>'drifted')::int;
    v_r := (v_j->>'regenerated')::int;
  else
    for p in select s.port_id,
                    count(*) filter (where s.ord <> 3) as due_drift,
                    count(*) filter (where s.ord <> 4) as due_regen
               from pg_temp.drift_rows_0137 s group by s.port_id order by s.port_id loop
      v_j := public.tick_market_drift(p_at, p.port_id);
      if (v_j->>'drifted')::int <> p.due_drift or (v_j->>'regenerated')::int <> p.due_regen then
        raise exception '0137 self-assert FAIL: tick_market_drift(T, %) moved % / % row(s), not its own harbour''s % / %',
          p.port_id, v_j->>'drifted', v_j->>'regenerated', p.due_drift, p.due_regen;
      end if;
      v_n := v_n + (v_j->>'drifted')::int;
      v_r := v_r + (v_j->>'regenerated')::int;
    end loop;
  end if;
  return jsonb_build_object('drifted', v_n, 'regenerated', v_r, 'slot', v_j->>'slot', 'game_day', v_j->>'game_day',
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                            'digest', pg_temp.digest_0137(v_before, p_base, p_epoch));
end $$;

do $$
declare
  b       record;
  v_old   text;
  v_new   text;
  v_line  text := '  v_now timestamptz := now();';
  v_probe text := $l$  v_now timestamptz := current_setting('byeharu.probe_now_0137')::timestamptz;   -- 0137 probe copy$l$;
  v_call  text := (select old from hunks_0137 where fn = 'world.market(uuid)' and n = 0);
begin
  select * into b from defs_before_0137 where fn = 'world.market(uuid)';
  v_old := b.def;
  v_new := replace(pg_get_functiondef('world.market(uuid)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0137(v_old, v_line) <> 1 or pg_temp.occurs_0137(v_new, v_line) <> 1
     or pg_temp.occurs_0137(v_old, 'CREATE OR REPLACE FUNCTION world.market(') <> 1
     or pg_temp.occurs_0137(v_new, 'CREATE OR REPLACE FUNCTION world.market(') <> 1 then
    raise exception '0137 self-assert FAIL: world.market''s clock line or header is not where the probe copies expect it';
  end if;
  v_old := replace(replace(replace(v_old, v_line, v_probe), v_call, '  perform pg_temp.tick_market_drift_old_0137(v_now);'),
                   'CREATE OR REPLACE FUNCTION world.market(', 'CREATE OR REPLACE FUNCTION pg_temp.market_old_0137(');
  v_new := replace(replace(v_new, v_line, v_probe), 'CREATE OR REPLACE FUNCTION world.market(', 'CREATE OR REPLACE FUNCTION pg_temp.market_new_0137(');
  execute v_old;
  execute v_new;
end $$;

create or replace function pg_temp.market_run_0137(p_old boolean, p_at timestamptz, p_slot bigint, p_day int, p_base bigint, p_epoch bigint)
returns jsonb
language plpgsql
as $$
declare
  v_before jsonb := pg_temp.writes_0137();
  p        record;
  v_pay    jsonb := '{}'::jsonb;
begin
  perform pg_temp.drift_prepare_0137(p_slot, p_day);
  perform set_config('byeharu.probe_now_0137', p_at::text, true);
  for p in select port_id from drift_sample_0137 order by port_id loop
    if p_old then
      v_pay := v_pay || jsonb_build_object(p.port_id::text, pg_temp.market_old_0137(p.port_id));
    else
      v_pay := v_pay || jsonb_build_object(p.port_id::text, pg_temp.market_new_0137(p.port_id));
    end if;
  end loop;
  return jsonb_build_object('payload', v_pay, 'digest', pg_temp.digest_0137(v_before, p_base, p_epoch));
end $$;

do $$
declare
  v_xid   bigint := pg_current_xact_id()::text::bigint;
  v_base  bigint := v_xid % 4294967296;
  v_epoch bigint := v_xid - v_xid % 4294967296;
  v_ss    numeric := public.wc_num('drift_slot_seconds');
  v_ds    numeric := public.wc_num('game_day_seconds');
  v_smin  bigint;
  v_dmin  int;
  v_at    timestamptz;
  v_slot  bigint;
  v_day   int;
  v_rows  int := (select count(*) from drift_rows_0137);
  v_ports int := (select count(*) from drift_sample_0137);
  v_old   jsonb;
  v_new   jsonb;
  v_mo    jsonb;
  v_mn    jsonb;
  v_t0    timestamptz := clock_timestamp();
  v_k     text;
begin
  if (select count(*) from public.world_config where key in ('drift_sigma', 'drift_clamp', 'drift_theta')) <> 3
     or public.wc_num('drift_theta') <= 0 then
    raise exception '0137 self-assert FAIL: world_config lacks drift_sigma / drift_clamp / a positive drift_theta';
  end if;
  if v_rows < 6 then
    raise exception '0137 self-assert FAIL: the drift sample holds % row(s); six are bent', v_rows;
  end if;
  -- the arms the world decides: a producing row, and a works factor other than 1, when the world has one
  if exists (select 1 from public.port_goods where production_rate > 0)
     and not exists (select 1 from public.port_goods pg join drift_rows_0137 s using (port_id, good_id) where pg.production_rate > 0) then
    raise exception '0137 self-assert FAIL: the drift sample holds no producing row, and the world has some';
  end if;
  if exists (select 1 from public.ports po where po.id in (select port_id from public.port_goods)
                and public.works_factor(po.id, 'production', 'production_per_level') <> 1)
     and not exists (select 1 from drift_sample_0137 s where public.works_factor(s.port_id, 'production', 'production_per_level') <> 1) then
    raise exception '0137 self-assert FAIL: the drift sample holds no harbour whose works bend production, and the world has one';
  end if;

  -- ONLY THE SAMPLE'S ROWS ARE LOCKED (ctid order), until this file commits
  perform 1 from public.port_goods pg where pg.port_id in (select port_id from drift_sample_0137) order by pg.ctid for update;

  -- T: at or before every row's slot and day, so nothing outside the sample is due at T
  select min(drift_slot), min(last_regen_day) into v_smin, v_dmin from public.port_goods;
  v_at := least(to_timestamp((v_smin * v_ss)::double precision), to_timestamp((v_dmin * v_ds)::double precision));
  v_slot := floor(extract(epoch from v_at) / v_ss)::bigint;
  v_day  := world.game_day(v_at);
  if v_slot > v_smin or v_day > v_dmin then
    raise exception '0137 self-assert FAIL: the probe moment % (slot %, day %) is past a row''s slot % / day %', v_at, v_slot, v_day, v_smin, v_dmin;
  end if;

  begin
    v_old := pg_temp.drift_run_0137(true, v_at, v_slot, v_day, v_base, v_epoch);
    raise exception using errcode = 'ZX137', message = v_old::text;
  exception when sqlstate 'ZX137' then
    v_old := sqlerrm::jsonb;
  end;
  begin
    v_new := pg_temp.drift_run_0137(false, v_at, v_slot, v_day, v_base, v_epoch);
    raise exception using errcode = 'ZX137', message = v_new::text;
  exception when sqlstate 'ZX137' then
    v_new := sqlerrm::jsonb;
  end;
  if (v_old - 'ms') is distinct from (v_new - 'ms') then
    raise exception '0137 self-assert FAIL: the market drifted differently harbour by harbour: old % / new %', v_old, v_new;
  end if;
  if (v_new->>'drifted')::int <> v_rows - 1 or (v_new->>'regenerated')::int <> v_rows - 1 then
    raise exception '0137 self-assert FAIL: the probe moved % / % row(s), not the sample''s % / % due',
      v_new->>'drifted', v_new->>'regenerated', v_rows - 1, v_rows - 1;
  end if;
  -- the runs wrote the sample's rows and nothing else in port_goods: the bending (one update a row),
  -- the drift and the regeneration — and every sample row is the run's own
  if v_new->'digest'->'public.port_goods'->'writes' is distinct from jsonb_build_array(0, 3 * v_rows - 2, 0)
     or (v_new->'digest'->'public.port_goods'->>'own_rows')::int <> v_rows then
    raise exception '0137 self-assert FAIL: the drift probe wrote % in port_goods (% own rows), not the sample''s [0, %, 0] (% rows)',
      v_new->'digest'->'public.port_goods'->'writes', v_new->'digest'->'public.port_goods'->>'own_rows', 3 * v_rows - 2, v_rows;
  end if;
  -- the arms were taken: both clamps, a row left on its slot, one on its day, one regenerated below
  -- its target, one pulled down to it (read back inside a run, from the new body's own result)
  begin
    perform pg_temp.drift_prepare_0137(v_slot, v_day);
    for v_k in select s.port_id::text from drift_sample_0137 s order by s.port_id loop
      perform public.tick_market_drift(v_at, v_k::uuid);
    end loop;
    if (select count(*) from public.port_goods pg join drift_rows_0137 s using (port_id, good_id)
         where (s.ord = 1 and pg.drift =  public.wc_num('drift_clamp'))
            or (s.ord = 2 and pg.drift = -public.wc_num('drift_clamp'))
            or (s.ord = 3 and pg.drift_slot = v_slot)
            or (s.ord = 4 and pg.last_regen_day = v_day)
            or (s.ord = 5 and pg.stock < pg.stock_target)
            or (s.ord = 6 and pg.stock = pg.stock_target)) <> 6 then
      raise exception '0137 self-assert FAIL: the six bent rows did not take their six arms';
    end if;
    raise exception using errcode = 'ZX137', message = 'arms ok';
  exception when sqlstate 'ZX137' then
    null;
  end;
  raise notice '0137 probe: the drift sample, % harbour(s) / % row(s), old (whole market at T) % ms / new (harbour by harbour) % ms',
    v_ports, v_rows, v_old->>'ms', v_new->>'ms';

  begin
    v_mo := pg_temp.market_run_0137(true, v_at, v_slot, v_day, v_base, v_epoch);
    raise exception using errcode = 'ZX137', message = v_mo::text;
  exception when sqlstate 'ZX137' then
    v_mo := sqlerrm::jsonb;
  end;
  begin
    v_mn := pg_temp.market_run_0137(false, v_at, v_slot, v_day, v_base, v_epoch);
    raise exception using errcode = 'ZX137', message = v_mn::text;
  exception when sqlstate 'ZX137' then
    v_mn := sqlerrm::jsonb;
  end;
  for v_k in select k from jsonb_object_keys(v_mo->'payload') k order by k loop
    if v_mo->'payload'->v_k is distinct from v_mn->'payload'->v_k then
      raise exception '0137 self-assert FAIL: world.market(%) answers differently now it drifts only its quay', v_k;
    end if;
  end loop;
  if (select count(*) from jsonb_object_keys(v_mn->'payload')) <> v_ports
     or (select count(*) from jsonb_object_keys(v_mo->'payload')) <> v_ports
     or exists (select 1 from jsonb_each(v_mn->'payload') e where jsonb_array_length(e.value->'goods') = 0) then
    raise exception '0137 self-assert FAIL: the quay probe priced % / % of % harbour(s), or one served no goods',
      (select count(*) from jsonb_object_keys(v_mo->'payload')), (select count(*) from jsonb_object_keys(v_mn->'payload')), v_ports;
  end if;
  if v_mo->'digest' is distinct from v_mn->'digest' then
    raise exception '0137 self-assert FAIL: the quay reads left a different market: old % / new %', v_mo->'digest', v_mn->'digest';
  end if;
  raise notice '0137: the drift and the quay, old = new on the sample — % harbour(s), % row(s) (% drifted, % regenerated; both clamps, a row on its slot, a row on its day, below and at the target taken), T = % (slot %, day %); world.market answered alike at every one of them (% goods); only the sample was locked or written; % ms in all',
    v_ports, v_rows, v_new->>'drifted', v_new->>'regenerated', v_at, v_slot, v_day,
    (select sum(jsonb_array_length(e.value->'goods')) from jsonb_each(v_mn->'payload') e),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $$;

-- ── 7. THE RECEIPT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cron text := 'pg_cron is not installed here (PGlite): no job to re-point';
  v_n    int;
begin
  -- the two procedures may COMMIT: neither is SECURITY DEFINER nor carries a SET (transaction control
  -- refuses both), and nobody but the owner can run them
  select count(*) into v_n from pg_proc p
   where p.oid in ('public.tick_reconcile(boolean)'::regprocedure, 'public.tick_market_drift_each_port()'::regprocedure)
     and p.prokind = 'p' and not p.prosecdef and p.proconfig is null
     and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute');
  if v_n <> 2 then
    raise exception '0137 self-assert FAIL: % of the 2 procedures are owner-only, invoker, SET-free procedures', v_n;
  end if;
  if to_regprocedure('public.tick_market_drift(timestamptz)') is not null then
    raise exception '0137 self-assert FAIL: the one-argument tick_market_drift survived beside the new one';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'tick_reconcile') <> 1 then
    raise exception '0137 self-assert FAIL: tick_reconcile is not exactly one procedure';
  end if;
  -- every step is checked before it commits; the drift job skips a deadlocked harbour and goes on
  if pg_temp.occurs_0137(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), 'perform public.assert_ledger_reconciles(') <> 3
     or pg_temp.occurs_0137(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), 'public.npc_step_failed(') <> 2
     or pg_temp.occurs_0137(pg_get_functiondef('public.tick_market_drift_each_port()'::regprocedure), 'exception when deadlock_detected or lock_not_available then') <> 1 then
    raise exception '0137 self-assert FAIL: a reconcile step is not checked before its commit, or the drift job does not skip a deadlocked harbour';
  end if;
  -- THE JOBS RUN THE PROCEDURES, by name, with the schedule and active flag they had
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select count(*) from cron.job
                where (jobname = 'byeharu-voyage:reconcile' and command = 'call public.tick_reconcile()')
                   or (jobname = 'byeharu-voyage:drift' and command = 'call public.tick_market_drift_each_port()')$q$
      into v_n;
    if v_n <> 2 then
      raise exception '0137 self-assert FAIL: % of the 2 jobs (reconcile, drift) call their procedure', v_n;
    end if;
    execute $q$select count(*) from cron.job where command like '%tick_reconcile%' or command like '%tick_market_drift%'$q$ into v_n;
    if v_n <> 2 then
      raise exception '0137 self-assert FAIL: % jobs name the reconcile or the drift, not 2', v_n;
    end if;
    v_cron := 'byeharu-voyage:reconcile = call public.tick_reconcile(), byeharu-voyage:drift = call public.tick_market_drift_each_port() (schedule and active flag untouched; wind_the_clock() starts exactly these)';
  end if;
  raise notice '0137 self-assert ok: AN ARRIVAL NEVER WAITS FOR THE HOUR — the hourly reconcile and the drift commit step by step, nothing either decides moved. TEND: npc_tend cut into its walk (npc_tend_roster), one merchant (npc_tend_route), the companies (npc_tend_houses) and the receipt''s adder (npc_tend_sum), each slice byte-equal to the pre-image (the houses gate the one hunk), no line between the slices unaccounted for; old = new run by run (receipts and each run''s OWN writes — counts per table and the md5 of its own rows; never a whole table, so a player''s commit cannot fail the push). RECONCILE: a procedure, one transaction per merchant / the companies / the compactor under npc_upkeep_scope, each merchant''s ledger and every company''s checked BEFORE its commit (a step that breaks a purse rolls back alone, counted), then the read-only whole-world invariants. DRIFT: tick_market_drift(p_now, p_port) reverses to its pre-image, ACL carried; tick_market_drift_each_port commits one harbour at a time and skips (warns, counts) a harbour that deadlocks or times out on a lock; old = new on a bounded sample, every arm taken, only the sample locked. QUAY: world.market drifts its own harbour only (one hunk, reverses to its pre-image, ACL kept), answering alike at every sample harbour. CRON: %.', v_cron;
end $$;
