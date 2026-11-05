-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0314 — INSURANCE PAYS ITS WAY: a ship that reaches her port on her last cask has arrived, so the city does not pay for a hold she never lost
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, slice W0b of docs/WORLD_POWERS.md: cities paid out 29.5 M d. in 24 h and took in 7.4 M d. Measure, root cause. docs/dev-log/2026-11-05-insurance.md holds the numbers.
--
-- WHY (measured on prod, read-only, 2026-11-05, head 0312). Premiums are not the cause and no rate moves here.
--   Every claim on record: 142 FORCED_HOME (cities paid 6.57 M d., 92 %; owed 15.44 M d.) and 31 raids (paid 0.60 M d.; owed 1.09 M d.). Storms take no cargo.
--   Premiums on those same 23,248 policies: 1.90 M d., so raids alone are covered 1.74 times. Insurance earned until 10-29 (+0.62 M d. that day) and turned the day 0279 went live.
--   280 of the 283 forced homes in the record, and ALL 142 of the insured ones, fell on a day whose boundary IS the voyage's ETA: she had arrived. 279 of them were "forced" into their
--   own destination, losing the whole hold on the quay, hull damage on top. The other 3 were real (FOUL_WATER, 0.1 to 0.3 of a day short of port), with empty holds and no claim.
--
-- THE BUG. 0279's guard is `d < v_cap`, written for "the trailing day" that voyage.day_ends_at clamps at the ETA. But a CALM or a STORM stacks SEVERAL days there, not one: voyage.total_days
-- counts the delay (ceil((sim + delay) / 24)), and every boundary after the delay is pushed by it as well (d * 24 + delay), so any day with d * 24 >= sim lands on the ETA instant. A merchant
-- carries ceil(1.15 * sim / 24) + 1 days of stores, so 1.5 to 4 days of delay runs her casks dry on one of those stacked days, d < v_cap holds, and she is turned away from the harbour she is
-- entering. Every such ship was a claim for 100 % of a hold she still had.
--
-- WHAT THIS FILE DOES: one hunk of voyage.settle. The test becomes the fact it meant: `v_bound < v.eta`, a day that ends before she arrives. It covers the old final-day case too (a final day
-- always ends on the ETA). A ship that runs dry at sea is forced home, claims and all, exactly as before.
--
-- NOT TOUCHED: every knob and rate (insurance_raid_loss, insurance_margin, insurance_keep_pct, endurance_margin), voyage.risk_quote, public.insurance_price, public.insurance_claim,
-- voyage.forced_home, voyage.day_ends_at, voyage.total_days, the merchants' stores. Past claims stay paid; `short` was never owed.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - A delay alone never strands her. Once her sailing time is done (d * 24 >= sim) the next boundary IS her arrival, so a ship dry after that docks, even if a long calm held her out for hours
--     on empty casks. The other reading, cutting her mid-calm, loses the same holds, all but on her destination's doorstep: the same drain, then priced as a real risk.
--   - The cover for a real dry day stays as the owner set it (row 223), and it stays unpriced: 3 real ones in 7 hours, all with empty holds.
--
-- SELF-ASSERT: the catalog only (the hunk occurs once and reverses; ACL, volatility and config unmoved; no other function, no knob). THIS FILE RUNS NO GAME STEP AND TOUCHES NO ROW, in every
-- environment (docs/OPS_HEALTH.md section 4: a push runs with the game clock stopped, and 0313's took about 9 minutes). THE REAL voyage.settle IS PROVED IN CI: proof 23,
-- scripts/db/proofs/23_insurance.sql: the bug reproduced on the pre-image body and gone on the new one, at once and day by day; a real dry day at sea still forced home; a dry final day an arrival.
-- Mutation controls: scripts/ops/harness/insurance/proof-0314.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s. The digest of all 711 functions took about 70 ms on prod.
-- ROLLBACK (forward, a NEW migration, owner only): swap this file's v_old and v_new. Nothing else was changed, and no row of data was written.
-- VERSION: 0314 - prod head 0313 (2026-11-05). voyage.settle at that head: md5 e3adabaa9b4007b672b9600bb1129b16.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_old  text := $h$    -- A DRY FINAL DAY IS AN ARRIVAL, NOT A STRANDING: d < v_cap. voyage.day_ends_at clamps the
    -- trailing day at the ETA, so a ship that drinks her last cask as she makes port docks there
    -- (the arrival arm below) instead of being turned away from a harbour she is entering.
    if v_end <= 0 and d < v_cap$h$;
  v_new  text := $h$    -- A DRY DAY THAT ENDS ON THE ETA IS AN ARRIVAL, NOT A STRANDING (0314, was d < v_cap): voyage.day_ends_at
    -- clamps at the ETA, and a delay stacks SEVERAL trailing days there, not one, because voyage.total_days
    -- counts it and every later boundary is pushed by it too. A ship that drinks her last cask on any of them
    -- docks (the arrival arm below) instead of being turned away from the harbour she is entering, and no
    -- insurance pays for a hold she still has. v was re-read at the end of the last day, so v.eta is current.
    if v_end <= 0 and v_bound < v.eta$h$;
  v_settle regprocedure := 'voyage.settle(uuid,timestamp with time zone)'::regprocedure;
  v_def0 text;
  v_def  text;
  v_acl0 text;
  v_cfg0 text;
  v_fn_before  text;
  v_cfg_before text;
  v_t0   timestamptz := clock_timestamp();
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('voyage.forced_home(uuid,integer,uuid)') is null or to_regprocedure('public.insurance_claim(uuid,integer,jsonb,text)') is null then
    raise exception '0314 refuses: 0213 / 0279 (the insurance, the forced home) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> v_settle;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
    into v_def0, v_acl0, v_cfg0
    from pg_proc p where p.oid = v_settle;

  -- ── 1. THE HUNK ──
  if (length(v_def0) - length(replace(v_def0, v_old, ''))) / length(v_old) <> 1 then
    raise exception '0314 self-assert FAIL: the hunk of voyage.settle occurs % time(s), not once: the deployed body is not what this file was written against',
      (length(v_def0) - length(replace(v_def0, v_old, ''))) / length(v_old);
  end if;
  v_def := replace(v_def0, v_old, v_new);
  execute v_def;

  -- ── 2. THE SELF-ASSERT: the hunk reverses, nothing else moved ──
  v_def := replace(pg_get_functiondef(v_settle), E'\r', '');
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception '0314 self-assert FAIL: the hunk is not in the new body once';
  end if;
  if replace(v_def, v_new, v_old) <> v_def0 then
    raise exception '0314 self-assert FAIL: voyage.settle does not reverse to its pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = v_settle) <> v_acl0
     or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_settle) <> v_cfg0 then
    raise exception '0314 self-assert FAIL: the ACL, volatility, definer or config of voyage.settle moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> v_settle) <> v_fn_before then
    raise exception '0314 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0314 self-assert FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0314 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0314 self-assert ok: INSURANCE PAYS ITS WAY. voyage.settle: a dry day is a forced home only when it ends before the ETA. One hunk reverses; no other function, no knob; no game step ran here: proof 23 runs the real settle in CI. % ms',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
