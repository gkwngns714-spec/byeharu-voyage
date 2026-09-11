-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0083 — A MANIFEST IS ONE ORDER  (many lines, one quay, one transaction, one receipt)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-09-11, docs/OWNER_REQUESTS.md row 76, docs/QUAY_LEDGER.md) ─────────────────
--   Nine screenshots of a trade house with a basket on the right and a settlement chit at the
--   end: "come up with the same design plan, but different and modern than this" — "make this in
--   game". QUAY_LEDGER §6 slice 2: "a 3-line mixed manifest lands atomically on production and its
--   receipt equals the ledger's BOUGHT/SOLD rows; a refused line refuses the whole basket."
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
--   * `cmd.issue` (0008:453) takes ONE line of words and writes ONE `public.orders` row; a basket
--     of five lines is five round trips, five version bumps, and — the defect — five chances for
--     the third to be refused after the first two have already moved the purse. Nothing in the
--     chain can land several lines together or refuse them together.
--   * `cmd.issue`'s comment (0008:544-547): *"Do not add a structured-order sibling: that would be
--     a second grammar."* DECIDED, and this is the argument: a manifest is NOT a grammar. It carries
--     no words — no verb to parse, no quantity mode, no price limit — and every line of it runs the
--     SAME `cmd.do_buy` / `cmd.do_sell` body `cmd.issue` runs, with exactly the `{good, qty}` args
--     `cmd.parse` (0008:263-300) would have produced. Like `cmd.haggle` (0022:430 — client-direct,
--     no orders row) it is a QUAY verb: it exists only where she is docked, it writes no
--     `public.orders` row, and the record of what happened is `public.events` BOUGHT/SOLD, which
--     the receipt must equal (asserted, (f)). The one grammar stays the one grammar.
--   * `world.quote` (0022:353) answers `total` and nothing about where the total came from. The
--     settlement chit the owner pointed at prints 원가 · 관세 · 할증 (goods at mid, tax, the quay's
--     cut). A client that derived those three from `total` by hand would be a second pricing
--     authority (NO_SPAGHETTI §1, question 1) and would be wrong on the day the step, the tax or
--     the floor changes.
--
-- ── §7B — THE FOUR QUESTIONS ────────────────────────────────────────────────────────────────────
--   1. CONCEPT: a manifest — several buy and sell lines at one quay, landing all together or not
--      at all, receipted as one.
--   2. WHERE IT LIVES: `cmd.run_manifest` is the ONE body — it validates the SHAPE of the lines
--      (never their legality; the verbs refuse), runs every line through the deployed verbs, and
--      assembles the receipt from what the verbs returned and what the leaves read back. Two
--      skins wear it exactly as `cmd.preview` wears the verbs (0008:424-444): `cmd.trade_basket`
--      (ownership, E_STALE, settle, version — `cmd.issue`'s head, mirrored) commits it;
--      `cmd.preview_basket` runs it and throws it away. Neither re-derives a figure.
--   3. THE SECOND CALLER: the manifest face and the receipt (QUAY_LEDGER §3 C/E) read these two;
--      the contracts slice (§6 slice 4) will hand its premium through `trade_basket` rather than
--      minting a third money path.
--   4. WHAT WOULD MAKE IT WRONG, and how anyone finds out: a receipt that disagrees with the
--      ledger, or a refused line that left an earlier line landed. (f) demands the ledger's two
--      new rows equal the receipt; (h) refuses the second line and demands NOTHING moved, with a
--      positive control that runs the same two verbs WITHOUT the savepoint and watches the
--      non-atomic state appear.
--
-- ── THE LEAVES, COMPOSED — NOTHING RE-DERIVED (the tripwires) ──────────────────────────────────
--   price / stepping / cap / hold / stock / funds  → cmd.do_buy, cmd.do_sell (which call world.quote,
--                                                    cmd.resolve_qty, world.daily_cap_remaining,
--                                                    fleet_free_hold, and refuse through cmd.refuse)
--   basis / cost / profit                          → cmd.do_sell's own figures (0081)
--   what the bargain saved, the tax, the quay's cut → world.quote's four NEW columns (below)
--   trading XP                                     → public.player_progress before and after (0069)
--   the refusal's code, sentence, figures          → cmd.refuse / cmd.refusal_caught (0050)
--   hold room                                      → public.fleet_free_hold before and after
--   the purse                                      → READ back from players.ducats, never summed
--
-- ── SUPERSEDE ───────────────────────────────────────────────────────────────────────────────────
-- This file SUPERSEDES the deployed bodies of:
--   * `world.spread_effective` (0022:309) — DROPPED and re-created with a fourth, defaulted
--     argument `p_with_bargain boolean default true` (a 3-arg twin beside a 4-arg default would
--     make every existing 3-arg call ambiguous, 0081's fleet_load rule). `false` answers "what
--     would this house execute at WITHOUT today's bargain" — the one extra reading `world.quote`
--     needs to say what the bargain saved. Every existing call passes three arguments and reads
--     the same number to the digit (assert (b)).
--   * `world.quote` (0022:353) — DROPPED and re-created because its RETURNS TABLE grows (a return
--     type cannot be changed by `create or replace`): `mid_total`, `tax_total`, `spread_total`,
--     `haggle_saved` are accumulated INSIDE the same 10-tun stepped loop, per step, from the same
--     `v_mid`, `v_tax`, `v_spread` the unit price is built from. `total` remains the ONLY figure
--     the purse moves by; the four are exact sums that differ from it only by the per-unit 2-dp
--     rounding of the unit price, and the client never sums them back. Every caller reads the
--     columns by name (`select * into q` / `q.total`), so the change is additive. NO-OP PROVEN:
--     250 (port, good) pairs × both sides × 30 t are captured before the cut and demanded equal
--     on `(units, total, avg_price, end_stock)` after it (assert (b)).
--   * `cmd.do_buy` / `cmd.do_sell` (last cut 0081:293 / 0081:300) — SLICED: the four new quote
--     columns are appended to the returned object AND to the BOUGHT / SOLD event payload, so the
--     receipt and the ledger carry the same breakdown. Nothing else in either body moves.
--   * `public.client_rpc_entry_points` (last cut 0047:1106) — re-cut whole, two rows added, so
--     `client_executable_writers()` (0018) does not list the two new doors as leaks.
-- No ACL is re-declared for the two sliced verbs (0080 §3 says what that habit cost); assert (l)
-- proves each byte-identical to the one this file found. The two DROPPED bodies lose their ACL
-- with the drop, so their posture is DECLARED (revoked from every client role, as 0022:341 and
-- 0018 §4 had them) and then CHECKED.
--
-- ── THE NEW OBJECTS ─────────────────────────────────────────────────────────────────────────────
--   cmd.run_manifest(fleet, lines)            THE body. Raises on refusal; returns the receipt.
--                                             Server-only.
--   cmd.manifest_line_caught(hint)            the inverse of run_manifest's re-raise: which line.
--   cmd.manifest_refused(fleet, state, msg,   THE one refusal envelope of a manifest (0050's
--                        detail, hint)        shape + `line`; E_BUSY for a lock collision).
--   cmd.trade_basket(fleet, lines, version)   the committing skin. authenticated.
--   cmd.preview_basket(fleet, lines)          the dry-run skin. authenticated.
--
-- ── WHICH LINE REFUSED — MEASURED, NOT ASSUMED ──────────────────────────────────────────────────
-- The skin wants to name the refusing line. A session GUC set by the loop (`set_config(..., true)`)
-- does NOT survive: PostgreSQL rolls GUC changes back with the subtransaction that made them —
-- measured on PGlite 0.5.5 / PostgreSQL 18.3 before this file was written (`local=[] session=[]`
-- after the block aborted; a temp sequence survived, which is the only non-transactional channel
-- and is not a shape anybody should read). So `run_manifest` wraps its loop in ONE handler that
-- re-raises the very error it caught — same message, same SQLSTATE, same DETAIL (the figures
-- cmd.refuse put there) — with the line's index in HINT, which nothing in the chain uses. It
-- never swallows and never continues; atomicity is the savepoint in the skin, exactly as
-- cmd.preview's is. `cmd.manifest_line_caught` is the one reader of that HINT, and
-- `cmd.manifest_refused` the ONE envelope builder both skins call.
--
-- ── TWO MANIFESTS AT ONE QUAY, AND A DOUBLE-TAP ─────────────────────────────────────────────────
--   * The version guard is checked and bumped UNDER ONE ROW LOCK inside the savepoint —
--     `update fleets set version = version + 1 where id = … and version = p_expected_version;
--     if not found → E_STALE`. A second call carrying the same expected version blocks on the
--     row, re-evaluates the predicate against the committed bump, and is refused: a double-tap
--     runs the basket once. (`cmd.issue` reads f.version and bumps in two statements, 0008:478/523
--     — the same window, INHERITED and not fixed here; it is 0008's to close.)
--   * A manifest holds one port_goods row lock per line plus the player row. Two manifests at
--     the same quay in different line orders could cycle, so `run_manifest` takes every one of
--     its rows FIRST, in ONE fixed order (`order by good_id for update`), before any verb runs.
--     Against `tick_market_drift`'s whole-table walk a cycle is still possible, so both skins
--     catch deadlock_detected / lock_not_available (40P01 / 55P03) and answer a retryable
--     `E_BUSY` — "the quay is busy; try again" — rather than a 500. The lock ORDER is asserted
--     structurally (the statement is in the live body text); no race is staged in a single
--     session, and the file says so rather than pretending.
--
-- ── KNOWN SIBLING, NOT FIXED HERE ───────────────────────────────────────────────────────────────
--   A manifest takes WHOLE tuns only (E_MANIFEST_LINE otherwise). Measured before this rule: a
--   line of 0.0073 t sold for 1 d. (a rounding gain) and 0.00625 t burned cargo for 0 d.
--   `cmd.parse`'s grammar (0008:281-286) accepts the same fractions through cmd.parse_number; that
--   hole is the grammar's and is named here rather than patched from the side.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   * What a trade CHARGES: `total` is the same `round(Σ round(unit, 2) × n)` (assert (b)).
--   * The gates and their order inside do_buy / do_sell, the daily cap, the bargain being SPENT
--     by the first executed line at (port, good) — which is exactly why a good may appear on only
--     ONE line of a manifest (E_MANIFEST_DUPLICATE): the second line would execute at a different
--     spread than the preview showed, and the daily cap counts both sides against one allowance.
--   * `cmd.issue`, `cmd.parse`, `public.orders`: a manifest writes no order row.
--   * world.market, world.snapshot, the ledger's sentences, prices, stock, drift.
--
-- Depends on: 0008 (cmd.issue's head, cmd.preview's rollback pattern), 0022 (world.quote, world.
-- spread_effective, haggle_daily), 0050 (cmd.refuse / cmd.refusal_caught / cmd.figures), 0069
-- (public.player_progress, level_from_points), 0081 (do_buy / do_sell bodies, cargo basis).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool (its own copy, by necessity — tests/duplication.spec.ts:365-380) ─────────
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
      raise exception '0083 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── 0b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
create temporary table defs_before_0083 as
select format('%s.%s(%s)', n.nspname, p.proname, oidvectortypes(p.proargtypes)) as fn,
       pg_get_functiondef(p.oid)  as def,
       coalesce(p.proacl::text, '') as acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where p.oid in ('world.quote(uuid,uuid,numeric,text,numeric,uuid)'::regprocedure,
                 'world.spread_effective(uuid,uuid,uuid)'::regprocedure,
                 'cmd.do_buy(uuid,jsonb)'::regprocedure,
                 'cmd.do_sell(uuid,jsonb)'::regprocedure,
                 'public.client_rpc_entry_points()'::regprocedure);

-- The economy as it stands: 250 (port, good) pairs, both sides, 30 t, through the OLD quote.
-- Ordered, never `limit` alone, so the sample is the same sample on every apply.
create temporary table quotes_before_0083 as
select s.port_id, s.good_id, side.s as side, q.units, q.total, q.avg_price, q.end_stock
  from (select pg.port_id, pg.good_id from public.port_goods pg order by pg.port_id, pg.good_id limit 250) s
 cross join (values ('buy'), ('sell')) as side(s)
 cross join lateral world.quote(s.port_id, s.good_id, 30, side.s, null, null) q;

-- ── 1. THE SPREAD, WITH OR WITHOUT THE BARGAIN ─────────────────────────────────────────────────
select pg_temp.recut('world.spread_effective(uuid,uuid,uuid)'::regprocedure, true,
  $h$CREATE OR REPLACE FUNCTION world.spread_effective(p_port uuid, p_good uuid, p_fleet uuid DEFAULT NULL::uuid)$h$,
  $h$CREATE OR REPLACE FUNCTION world.spread_effective(p_port uuid, p_good uuid, p_fleet uuid DEFAULT NULL::uuid, p_with_bargain boolean DEFAULT true)$h$,
  $h$    if v_player is not null then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;$h$,
  $h$    -- 0083: asked with p_with_bargain = false this is what the SAME house executes at without
    -- today's bargain — world.quote reads both, so it can say what the bargain saved.
    if v_player is not null and p_with_bargain then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;$h$);

comment on function world.spread_effective(uuid, uuid, uuid, boolean) is
  'THE spread a given house executes a given trade at: the port''s published spread (world.spread, '
  'untouched), less the purser''s shave (0015/0017) and less any open bargain (0022), composed '
  'multiplicatively and floored at haggle_spread_floor_frac of the published figure. 0083: with '
  'p_with_bargain = false the bargain is left out — the one extra reading world.quote needs to '
  'report haggle_saved. Every three-argument call is unchanged to the digit.';
-- The drop took the ACL with it; this is the posture 0022:341 declared, re-declared and then
-- checked in (l). Not a client entry point: world.haggle_state serves the panel.
revoke all on function world.spread_effective(uuid, uuid, uuid, boolean) from public, anon, authenticated;

-- ── 2. THE QUOTE SAYS WHERE THE MONEY WENT ─────────────────────────────────────────────────────
select pg_temp.recut('world.quote(uuid,uuid,numeric,text,numeric,uuid)'::regprocedure, true,
  $h$ RETURNS TABLE(units numeric, total bigint, avg_price numeric, end_stock numeric)$h$,
  $h$ RETURNS TABLE(units numeric, total bigint, avg_price numeric, end_stock numeric, mid_total numeric, tax_total numeric, spread_total numeric, haggle_saved numeric)$h$,
  $h$  v_units  numeric := 0;
  v_total  numeric := 0;
begin$h$,
  $h$  v_units  numeric := 0;
  v_total  numeric := 0;
  -- 0083: the four parts of the money, and the spread this house would pay with no bargain.
  v_nohag  numeric;
  v_mid_t  numeric := 0;
  v_tax_t  numeric := 0;
  v_spr_t  numeric := 0;
  v_hag_t  numeric := 0;
begin$h$,
  $h$  v_spread := world.spread_effective(p_port, p_good, p_fleet);
  v_tax    := world.tax_rate(p_port);$h$,
  $h$  v_spread := world.spread_effective(p_port, p_good, p_fleet);
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  v_nohag  := case when p_fleet is null then v_spread
                   else world.spread_effective(p_port, p_good, p_fleet, false) end;
  v_tax    := world.tax_rate(p_port);$h$,
  $h$      v_total := v_total + v_unit * v_n;
      v_stock := v_stock - v_n;$h$,
  $h$      v_total := v_total + v_unit * v_n;
      -- 0083: the same unit price in its parts, from the same v_mid / v_tax / v_spread; the parts
      -- differ from v_unit only by v_unit's rounding to the hundredth.
      v_mid_t := v_mid_t + v_mid * v_n;
      v_tax_t := v_tax_t + v_mid * v_tax * v_n;
      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;
      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;
      v_stock := v_stock - v_n;$h$,
  $h$      v_total := v_total + v_unit * v_n;
      v_stock := v_stock + v_n;$h$,
  $h$      v_total := v_total + v_unit * v_n;
      v_mid_t := v_mid_t + v_mid * v_n;
      v_tax_t := v_tax_t + v_mid * (1 - v_spread / 2) * v_tax * v_n;
      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;
      v_hag_t := v_hag_t + (v_unit - round(v_mid * (1 - v_nohag / 2) * (1 - v_tax), 2)) * v_n;
      v_stock := v_stock + v_n;$h$,
  $h$  end_stock := v_stock;
  return next;$h$,
  $h$  end_stock := v_stock;
  -- 0083: `total` remains the ONLY figure the purse moves by. These four are exact sums that
  -- differ from it only by the per-unit 2-dp rounding above; a client prints them and never adds
  -- them back together.
  mid_total    := round(v_mid_t, 2);
  tax_total    := round(v_tax_t, 2);
  spread_total := round(v_spr_t, 2);
  haggle_saved := round(v_hag_t, 2);
  return next;$h$);

comment on function world.quote(uuid, uuid, numeric, text, numeric, uuid) is
  'THE stepped execution price, and the only price the money moves at (0017, 0022). 0083: beside '
  '`total` it now says where the money went — mid_total (the goods at mid), tax_total (the port''s '
  'tax), spread_total (the quay''s cut this house actually paid) and haggle_saved (what today''s '
  'bargain took off, against the same house with no bargain) — accumulated per 10-tun step from '
  'the same terms the unit price is built from. `total` is unchanged to the ducat and stays the '
  'only figure the purse moves by; the four parts are printed, never summed back.';
-- The drop took the ACL with it; 0018 §4 revoked this from the client and 0017:90-91 recorded
-- that the client never calls it — every money path reaches it as the definer.
revoke all on function world.quote(uuid, uuid, numeric, text, numeric, uuid) from public, anon, authenticated;

-- ── 3. THE VERBS CARRY THE BREAKDOWN, SLICED ───────────────────────────────────────────────────
select pg_temp.recut('cmd.do_buy(uuid,jsonb)'::regprocedure, false,
  $h$      'haggled', v_conc > 0, 'concession', v_conc)));$h$,
  $h$      'haggled', v_conc > 0, 'concession', v_conc,
      'mid_total', q.mid_total, 'tax_total', q.tax_total, 'spread_total', q.spread_total,
      'haggle_saved', q.haggle_saved)));$h$,
  $h$                            'avg_price', q.avg_price, 'concession_spent', v_conc);$h$,
  $h$                            'avg_price', q.avg_price, 'concession_spent', v_conc,
                            'mid_total', q.mid_total, 'tax_total', q.tax_total,
                            'spread_total', q.spread_total, 'haggle_saved', q.haggle_saved);$h$);

select pg_temp.recut('cmd.do_sell(uuid,jsonb)'::regprocedure, false,
  $h$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit)));$h$,
  $h$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit,
      'mid_total', q.mid_total, 'tax_total', q.tax_total, 'spread_total', q.spread_total,
      'haggle_saved', q.haggle_saved)));$h$,
  $h$                            'basis', v_basis, 'cost', v_cost, 'profit', v_profit);$h$,
  $h$                            'basis', v_basis, 'cost', v_cost, 'profit', v_profit,
                            'mid_total', q.mid_total, 'tax_total', q.tax_total,
                            'spread_total', q.spread_total, 'haggle_saved', q.haggle_saved);$h$);

-- ── 4. THE ONE BODY ────────────────────────────────────────────────────────────────────────────
-- `create`, not `create or replace`: this file claims the four are NEW (0051:252's convention).

-- The inverse of run_manifest's re-raise: the HINT is the refusing line's index and nothing else.
create function cmd.manifest_line_caught(p_hint text)
returns int
language sql
immutable
parallel safe
as $$
  select case when p_hint ~ '^[0-9]+$' then p_hint::int else null end
$$;
comment on function cmd.manifest_line_caught(text) is
  '0083: THE one reader of the HINT cmd.run_manifest re-raises with — the zero-based index of the '
  'line that refused, or null when no line did (an empty manifest). Pass PG_EXCEPTION_HINT.';
revoke all on function cmd.manifest_line_caught(text) from public, anon, authenticated;

-- THE one refusal envelope of a manifest, for both skins. 0050's shape (code, sentence, figures,
-- fixes) plus `line`; a lock collision (deadlock_detected 40P01 / lock_not_available 55P03) is
-- not a refusal the player caused, so it is answered as E_BUSY — retryable, no figures, no line.
create function cmd.manifest_refused(p_fleet uuid, p_sqlstate text, p_message text, p_detail text, p_hint text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_ref  jsonb;
  v_code text;
begin
  if p_sqlstate in ('40P01', '55P03') then
    return jsonb_build_object('ok', false, 'error_code', 'E_BUSY',
      'error_message', 'the quay is busy; try again', 'figures', null,
      'fixes', jsonb_build_array('(try again)'), 'line', null);
  end if;
  v_ref  := cmd.refusal_caught(p_message, p_detail);
  v_code := v_ref->>'code';
  return jsonb_build_object('ok', false, 'error_code', v_code,
    'error_message', v_ref->>'sentence', 'figures', v_ref->'figures',
    'fixes', cmd.fixes(v_code, p_fleet),
    'line', cmd.manifest_line_caught(p_hint));
end $$;
comment on function cmd.manifest_refused(uuid, text, text, text, text) is
  '0083: THE one refusal envelope of a manifest — pass RETURNED_SQLSTATE, SQLERRM, '
  'PG_EXCEPTION_DETAIL and PG_EXCEPTION_HINT from the skin''s handler. 0050''s {code, sentence, '
  'figures, fixes} through cmd.refusal_caught, plus `line` through cmd.manifest_line_caught; a '
  'lock collision (40P01 / 55P03) answers E_BUSY with fixes = try again and no line.';
revoke all on function cmd.manifest_refused(uuid, text, text, text, text) from public, anon, authenticated;

create function cmd.run_manifest(p_fleet uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f           public.fleets%rowtype;
  v_i         int;                 -- the line being worked, zero-based; the HINT on any raise
  v_l         record;
  v_side      text;
  v_qty       numeric;
  v_good      public.goods%rowtype;
  v_seen      text[] := '{}';
  v_ids       uuid[] := '{}';
  v_r         jsonb;
  v_lines     jsonb := '[]'::jsonb;
  v_purse0    bigint;
  v_purse1    bigint;
  v_free0     numeric;
  v_free1     numeric;
  v_prog0     jsonb;
  v_prog1     jsonb;
  v_bought    bigint  := 0;
  v_sold      bigint  := 0;
  v_mid       numeric := 0;
  v_tax       numeric := 0;
  v_spread    numeric := 0;
  v_saved     numeric := 0;
  v_profit    bigint  := 0;
  v_unknown   boolean := false;    -- a sold line whose basis the hold did not know
  v_msg       text;
  v_det       text;
  v_state     text;
begin
  -- The whole body sits in ONE handler whose only job is to re-raise with the line index in HINT.
  -- It swallows nothing and continues nothing (see the header, "which line refused").
  begin
    -- (1) SHAPE ONLY. Legality — room, stock, cap, purse, cargo — is the verbs' to refuse.
    if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 1 then
      perform cmd.refuse('E_MANIFEST_EMPTY', 'the manifest has no lines');
    end if;
    for v_l in select e.value as line, (e.ordinality - 1)::int as idx
                 from jsonb_array_elements(p_lines) with ordinality e
                order by e.ordinality loop
      v_i := v_l.idx;
      v_side := lower(btrim(coalesce(v_l.line->>'side', '')));
      -- (the quantity is cast only once it is known to be a JSON number: SQL does not promise
      --  to short-circuit an OR, and a string where a number should be is a refusal, not 22P02.
      --  WHOLE tuns only: 0.0073 t sold for 1 d. and 0.00625 t burned cargo for 0 d., measured.)
      v_qty := case when jsonb_typeof(v_l.line->'qty') = 'number' then (v_l.line->>'qty')::numeric else 0 end;
      if jsonb_typeof(v_l.line) is distinct from 'object'
         or v_side not in ('buy', 'sell')
         or coalesce(v_l.line->>'good', '') = ''
         or v_qty <= 0 or v_qty <> floor(v_qty) then
        perform cmd.refuse('E_MANIFEST_LINE', format('line %s is not a buy or sell of a quantity', v_i));
      end if;
      -- The exact code, never cmd.resolve_good: a manifest is composed from served rows, so a
      -- prefix that "probably" means a good has no business here.
      select * into v_good from public.goods g where g.code = v_l.line->>'good';
      if v_good.id is null then
        perform cmd.refuse('E_NO_SUCH_GOOD', format('%s is not a good this world trades', v_l.line->>'good'));
      end if;
      -- One line per good, either side: the first executed line at (port, good) SPENDS the
      -- bargain (0022 decision 7) and the daily cap counts both sides against one allowance, so a
      -- second line would execute at figures the preview never showed.
      if v_good.code = any(v_seen) then
        perform cmd.refuse('E_MANIFEST_DUPLICATE', format('%s appears twice; one line per good', v_good.name));
      end if;
      v_seen := v_seen || v_good.code;
      v_ids  := v_ids || v_good.id;
    end loop;
    v_i := null;

    -- (2) BEFORE. Every one of these is READ from a leaf, never computed here.
    select * into f from public.fleets where id = p_fleet;
    -- THE LOCKS, IN ONE FIXED ORDER, before any verb runs: every quay row this manifest will
    -- write, by good_id. Two manifests at one quay then queue instead of cycling, whatever order
    -- their lines were typed in. (Asserted structurally below — the statement is in the body —
    -- not by a race; a single session cannot stage one.)
    perform 1 from public.port_goods pg
      where pg.port_id = f.port_id and pg.good_id = any(v_ids)
      order by pg.good_id
      for update;
    select ducats into v_purse0 from public.players where id = f.player_id;
    v_free0 := public.fleet_free_hold(p_fleet);
    v_prog0 := public.player_progress(f.player_id);

    -- (3) THE LINES: sells first (they fund and make room for the buys), then buys, each in the
    --     order given. Every line is the deployed verb with cmd.parse's own {good, qty} shape —
    --     no qty_mode, no limit — and a refusal from any of them propagates and unwinds them all.
    for v_l in select e.value as line, (e.ordinality - 1)::int as idx
                 from jsonb_array_elements(p_lines) with ordinality e
                order by (lower(btrim(e.value->>'side')) = 'buy'), e.ordinality loop
      v_i    := v_l.idx;
      v_side := lower(btrim(v_l.line->>'side'));
      v_qty  := (v_l.line->>'qty')::numeric;
      select * into v_good from public.goods g where g.code = v_l.line->>'good';
      if v_side = 'sell' then
        v_r := cmd.do_sell(p_fleet, jsonb_build_object('good', v_good.id::text, 'qty', v_qty));
        v_sold := v_sold + (v_r->>'total')::bigint;
        if v_r->'profit' is null or jsonb_typeof(v_r->'profit') = 'null' then
          v_unknown := true;
        else
          v_profit := v_profit + (v_r->>'profit')::bigint;
        end if;
      else
        v_r := cmd.do_buy(p_fleet, jsonb_build_object('good', v_good.id::text, 'qty', v_qty));
        v_bought := v_bought + (v_r->>'total')::bigint;
      end if;
      v_mid    := v_mid    + (v_r->>'mid_total')::numeric;
      v_tax    := v_tax    + (v_r->>'tax_total')::numeric;
      v_spread := v_spread + (v_r->>'spread_total')::numeric;
      v_saved  := v_saved  + (v_r->>'haggle_saved')::numeric;
      v_lines := v_lines || jsonb_build_object(
        'index', v_i, 'side', v_side, 'good', v_r->>'good', 'name', v_good.name,
        'qty', v_r->'qty', 'total', v_r->'total', 'avg_price', v_r->'avg_price',
        'mid_total', v_r->'mid_total', 'tax_total', v_r->'tax_total',
        'spread_total', v_r->'spread_total', 'haggle_saved', v_r->'haggle_saved',
        'concession_spent', v_r->'concession_spent',
        'basis', v_r->'basis', 'cost', v_r->'cost', 'profit', v_r->'profit');
    end loop;
    v_i := null;
  exception when others then
    v_msg := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail, v_state = returned_sqlstate;
    if v_i is null then
      raise exception using message = v_msg, errcode = v_state, detail = coalesce(v_det, '');
    end if;
    raise exception using message = v_msg, errcode = v_state, detail = coalesce(v_det, ''), hint = v_i::text;
  end;

  -- (4) AFTER. Read, not computed: the purse is what the ledger left it at.
  select ducats into v_purse1 from public.players where id = f.player_id;
  v_free1 := public.fleet_free_hold(p_fleet);
  v_prog1 := public.player_progress(f.player_id);

  -- (5) THE RECEIPT.
  return jsonb_build_object(
    'ok', true, 'kind', 'manifest',
    'port', (select p.code from public.ports p where p.id = f.port_id),
    'fleet', p_fleet, 'game_day', world.game_day(), 'at', now(),
    'lines', v_lines,
    'totals', jsonb_build_object(
      'goods_at_mid', round(v_mid, 2), 'tax', round(v_tax, 2), 'spread', round(v_spread, 2),
      'haggle_saved', round(v_saved, 2),
      'profit', case when v_unknown then null else v_profit end,
      'bought', v_bought, 'sold', v_sold, 'net', v_sold - v_bought),
    'purse', jsonb_build_object('before', v_purse0, 'after', v_purse1),
    -- tuns_delta is what the hold took ON: room before less room after (negative when she lightened).
    'hold', jsonb_build_object('free_before', v_free0, 'free_after', v_free1, 'tuns_delta', v_free0 - v_free1),
    'trading', jsonb_build_object(
      'points_before', (v_prog0->'trading'->>'points')::int,
      'points_after',  (v_prog1->'trading'->>'points')::int,
      'delta',         (v_prog1->'trading'->>'points')::int - (v_prog0->'trading'->>'points')::int,
      'level_before',  (v_prog0->'trading'->>'level')::int,
      'level_after',   (v_prog1->'trading'->>'level')::int,
      'turnover_after', (v_prog1->'trading'->>'turnover')::numeric));
end $$;

comment on function cmd.run_manifest(uuid, jsonb) is
  '0083: THE one body of a manifest. Validates the SHAPE of the lines only (array of {side, good, '
  'qty}; exact goods.code; one line per good), then runs every line through the deployed '
  'cmd.do_sell / cmd.do_buy — sells first, then buys, each in the order given — and returns the '
  'receipt from what the verbs returned and what the leaves read back (purse, fleet_free_hold, '
  'player_progress, before and after). Raises on any refusal with the line''s index in HINT; the '
  'skins (cmd.trade_basket, cmd.preview_basket) hold the savepoint that makes it all-or-nothing. '
  'Server-only: it checks no ownership, exactly as do_buy does not.';
revoke all on function cmd.run_manifest(uuid, jsonb) from public, anon, authenticated;

-- ── 5. THE COMMITTING SKIN — cmd.issue's head (0008:470-487), mirrored ─────────────────────────
create function cmd.trade_basket(p_fleet uuid, p_lines jsonb, p_expected_version int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_out    jsonb;
  v_det    text;
  v_hint   text;
  v_state  text;
  v_now    int;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id <> v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;

  -- Bring the fleet up to date BEFORE judging the manifest (DESIGN D.2, as cmd.issue does).
  perform voyage.settle(p_fleet);

  -- THE SAVEPOINT. A refusal from any line has already unwound every earlier line's writes by
  -- the time it is caught here — and the version bump with them: a refused manifest moved
  -- nothing, so nothing has a new version. (cmd.issue bumps before it runs because a failed
  -- order is still a written order row; a manifest writes no row.)
  begin
    -- THE VERSION GUARD, checked and bumped under ONE row lock: a second call carrying the same
    -- expected version waits on this row and then finds the predicate false (DESIGN F.3, "two
    -- devices cannot double-issue" — here, two taps cannot double-trade).
    update public.fleets set version = version + 1
     where id = p_fleet and (p_expected_version is null or version = p_expected_version);
    if not found then
      select version into v_now from public.fleets where id = p_fleet;
      return jsonb_build_object('ok', false, 'error_code', 'E_STALE',
        'error_message', format('This fleet has moved on since you looked (you have version %s, it is at %s).',
                                p_expected_version, v_now),
        'fixes', cmd.fixes('E_STALE', p_fleet), 'version', v_now);
    end if;
    v_out := cmd.run_manifest(p_fleet, p_lines);
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_det = pg_exception_detail, v_hint = pg_exception_hint;
    return cmd.manifest_refused(p_fleet, v_state, sqlerrm, v_det, v_hint)
        || jsonb_build_object('version', (select version from public.fleets where id = p_fleet));
  end;

  return v_out || jsonb_build_object('version', (select version from public.fleets where id = p_fleet));
end $$;

comment on function cmd.trade_basket(uuid, jsonb, int) is
  '0083: a manifest, committed. cmd.issue''s head (ownership -> E_NO_SUCH_FLEET, settle) and then '
  'ONE savepoint in which the version is checked-and-bumped under the fleet row''s lock (E_STALE) '
  'and cmd.run_manifest runs, so every line lands or none does and a double-tap trades once. '
  'Returns the receipt with `version`, or the 0050 refusal envelope with `line` — the zero-based '
  'index of the line that refused — or E_BUSY (retry) on a lock collision. Writes no '
  'public.orders row: the record is the ledger''s BOUGHT / SOLD events, which the receipt equals.';
revoke all on function cmd.trade_basket(uuid, jsonb, int) from public, anon;
grant execute on function cmd.trade_basket(uuid, jsonb, int) to authenticated;

-- ── 6. THE DRY-RUN SKIN — cmd.preview's pattern (0008:424-444), verbatim in shape ──────────────
create function cmd.preview_basket(p_fleet uuid, p_lines jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_out    jsonb;
  v_det    text;
  v_hint   text;
  v_state  text;
begin
  -- The same code as the committing skin for the same condition, so one screen handles one
  -- code. (cmd.preview itself checks no ownership at all — measured: it previews a foreign
  -- fleet — so the code is cmd.issue's, the door the committed order goes through.)
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id is distinct from v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;

  -- RUN THE REAL THING, then throw it away. A preview reports the FIRST refusing line only:
  -- all-or-nothing means the later lines' figures do not exist, so nothing totals the rest.
  begin
    v_out := jsonb_build_object('ok', true, 'estimate', cmd.run_manifest(p_fleet, p_lines));
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    get stacked diagnostics v_state = returned_sqlstate, v_det = pg_exception_detail, v_hint = pg_exception_hint;
    return cmd.manifest_refused(p_fleet, v_state, sqlerrm, v_det, v_hint);
  end;
end $$;

comment on function cmd.preview_basket(uuid, jsonb) is
  '0083: the manifest''s dry run — cmd.run_manifest inside a subtransaction that is always rolled '
  'back (cmd.preview''s pattern). What it reports is what cmd.trade_basket would do, because it '
  'is what it just did. VOLATILE on purpose: it writes and unwrites. No settle, no version.';
revoke all on function cmd.preview_basket(uuid, jsonb) from public, anon;
grant execute on function cmd.preview_basket(uuid, jsonb) to authenticated;

-- ── 7. THE CATALOGUE — re-cut whole (supersedes 0047's), two rows added ────────────────────────
create or replace function public.client_rpc_entry_points()
returns table (schema_name text, function_name text, arg_types text, fn regprocedure)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.s, t.f, t.a,
         to_regprocedure(format('%I.%I(%s)', t.s, t.f, t.a))
    from (values
      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),
      ('world',       'market',              'uuid'),
      ('world',       'fleets',              ''),
      ('world',       'ledger',              'timestamptz, int'),
      ('world',       'buy_capacity',        'uuid, uuid'),
      ('world',       'price_history',       'uuid, int'),
      ('world',       'player',              ''),
      ('world',       'officers',            ''),
      ('world',       'skills',              ''),
      ('world',       'trade_routes',        'uuid, uuid, numeric, int, uuid'),
      ('world',       'haggle_state',        'uuid, uuid'),
      ('world',       'standings',           'int'),
      ('world',       'buffs',               'uuid'),
      ('world',       'provision_presets',   ''),
      -- 0047: the free sea. The raster the client searches, and one place's sailed distances.
      ('world',       'sea_raster',          ''),
      ('world',       'reach',               'uuid'),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int, jsonb'),
      ('cmd',         'preview',             'uuid, text, jsonb'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text'),
      ('cmd',         'haggle',              'uuid, uuid, text'),
      ('cmd',         'provision_preset_save',   'uuid, text, int'),
      ('cmd',         'provision_preset_delete', 'uuid'),
      ('cmd',         'provision_preset_apply',  'uuid, uuid'),
      -- 0047: the helm order at sea - turn where she is, for a port or a bare point of water.
      ('cmd',         'divert',              'uuid, uuid, jsonb, jsonb'),
      -- 0083: the manifest — one order of many lines, and its dry run.
      ('cmd',         'trade_basket',        'uuid, jsonb, int'),
      ('cmd',         'preview_basket',      'uuid, jsonb')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe     uuid := gen_random_uuid();
  v_player    uuid;
  v_fleet     uuid;
  v_port      uuid;
  v_port_code text;
  v_a         uuid;  v_a_code text;  v_a_name text;  v_a_bulk numeric;
  v_b         uuid;  v_b_code text;  v_b_name text;  v_b_bulk numeric;
  v_max_a     numeric;
  v_max_b     numeric;
  v_qb        numeric := 10;
  v_per_point numeric := public.wc_num('fame_ducats_per_point');
  v_lines     jsonb;
  v_pv        jsonb;
  v_pa        jsonb;
  v_pb        jsonb;
  v_res       jsonb;
  v_bad       jsonb;
  v_la        jsonb;
  v_lb        jsonb;
  v_version   int;
  v_n         bigint;
  v_purse0    bigint;
  v_purse1    bigint;
  v_events0   bigint;
  v_ledger0   bigint;
  v_cargo_a0  numeric;
  v_cargo_b0  numeric;
  v_stock_a0  numeric;
  v_stock_b0  numeric;
  v_td0       numeric;
  v_ctrl_a    numeric;
  v_ctrl_seen boolean := false;
  v_over      numeric;
  v_q0        record;
  v_q1        record;
  v_r         record;
  v_def       text;
  v_expect    text;
  v_fn        text;
  v_sold_bal  bigint;
  v_bought_bal bigint;
  v_stock_a_init numeric;
  v_stock_b_init numeric;
  v_busy      jsonb;
  v_body      text;
begin
  -- (a) THE OBJECTS, AND THE SHAPES.
  if to_regprocedure('cmd.run_manifest(uuid, jsonb)') is null
     or to_regprocedure('cmd.trade_basket(uuid, jsonb, int)') is null
     or to_regprocedure('cmd.preview_basket(uuid, jsonb)') is null
     or to_regprocedure('cmd.manifest_line_caught(text)') is null
     or to_regprocedure('cmd.manifest_refused(uuid, text, text, text, text)') is null
     or to_regprocedure('world.spread_effective(uuid, uuid, uuid, boolean)') is null
     or to_regprocedure('world.quote(uuid, uuid, numeric, text, numeric, uuid)') is null then
    raise exception '0083 self-assert FAIL: an object this file declares is missing';
  end if;
  if to_regprocedure('world.spread_effective(uuid, uuid, uuid)') is not null then
    raise exception '0083 self-assert FAIL: the 3-argument world.spread_effective still stands beside the 4-argument one — every 3-argument call is now ambiguous';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'world' and p.proname in ('spread_effective', 'quote')) <> 2 then
    raise exception '0083 self-assert FAIL: % world.spread_effective / world.quote overloads, expected exactly 2',
      (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'world' and p.proname in ('spread_effective', 'quote'));
  end if;
  select count(*) into v_n
    from pg_proc p, unnest(p.proargnames) with ordinality a(nm, i)
   where p.oid = 'world.quote(uuid,uuid,numeric,text,numeric,uuid)'::regprocedure
     and a.nm in ('mid_total', 'tax_total', 'spread_total', 'haggle_saved');
  if v_n <> 4 then
    raise exception '0083 self-assert FAIL: world.quote''s result type carries % of the 4 new columns', v_n;
  end if;

  -- (b) THE NO-OP: the economy did not move. 250 pairs × 2 sides through the new quote read the
  --     same (units, total, avg_price, end_stock) the old one read — and the sample is real.
  select count(*) into v_n from quotes_before_0083;
  if v_n <> 500 then
    raise exception '0083 self-assert FAIL: the pre-image captured % quotes, expected 500 (250 pairs × 2 sides) — the no-op proof would be vacuous', v_n;
  end if;
  select count(*) into v_n
    from quotes_before_0083 b
   cross join lateral world.quote(b.port_id, b.good_id, 30, b.side, null, null) q
   where q.units is distinct from b.units or q.total is distinct from b.total
      or q.avg_price is distinct from b.avg_price or q.end_stock is distinct from b.end_stock;
  if v_n <> 0 then
    raise exception '0083 self-assert FAIL: % of 500 quotes changed on (units, total, avg_price, end_stock) — the recut moved the money', v_n;
  end if;
  --     (p_with_bargain is proven in (i), with a fleet AND an open bargain row; without a fleet
  --      there is no bargain and true/false would be the same number by construction.)

  -- ── THE WORKED EXAMPLE, ON A REAL HOUSE AT A REAL QUAY ───────────────────────────────────────
  v_player := public.new_house(v_probe, 'Casa do Manifesto', 'PRT');
  select id, port_id, version into v_fleet, v_port, v_version from public.fleets where player_id = v_player;
  select code into v_port_code from public.ports where id = v_port;
  perform cmd.assume_identity(v_probe);

  -- (c) TWO SUBJECTS this quay offers and this house can take most of (0081's own query).
  select g.id, g.code, g.name, g.bulk, (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric
    into v_a, v_a_code, v_a_name, v_a_bulk, v_max_a
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_player, v_port, g.id) >= 90
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code
   limit 1;
  if v_a is null or v_max_a < 20 then
    raise exception '0083 self-assert FAIL: at % the good this house can take most of is % (max %) — the worked example needs 20',
      v_port_code, coalesce(v_a_code, '-'), v_max_a;
  end if;
  select stock into v_stock_a_init from public.port_goods where port_id = v_port and good_id = v_a;
  perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_a::text, 'qty', 10));
  if public.fleet_cargo_qty(v_fleet, v_a_code) <> 10 then
    raise exception '0083 self-assert FAIL: the opening buy of 10 t of % left % t aboard', v_a_code, public.fleet_cargo_qty(v_fleet, v_a_code);
  end if;
  -- B is chosen AFTER the opening buy, so its capacity already accounts for the hold A took.
  select g.id, g.code, g.name, g.bulk, (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric
    into v_b, v_b_code, v_b_name, v_b_bulk, v_max_b
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_player, v_port, g.id) >= 90
     and g.id <> v_a
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code
   limit 1;
  if v_b is null or v_max_b < 20 then
    raise exception '0083 self-assert FAIL: at % with 10 t of % aboard the next good this house can take most of is % (max %) — the worked example needs 20',
      v_port_code, v_a_code, coalesce(v_b_code, '-'), v_max_b;
  end if;
  select stock into v_stock_b_init from public.port_goods where port_id = v_port and good_id = v_b;

  -- (g, first half) NON-VACUOUS XP: the executed manifest must turn over at least one point's
  --     worth of ducats, or `delta` proves nothing. Size the buy line from the preview.
  v_lines := jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_code, 'qty', 5),
                               jsonb_build_object('side', 'buy',  'good', v_b_code, 'qty', v_qb));
  v_pv := cmd.preview_basket(v_fleet, v_lines);
  if coalesce((v_pv->>'ok')::boolean, false) is not true then
    raise exception '0083 self-assert FAIL: preview_basket refused the worked example: %', v_pv;
  end if;
  if (v_pv->'estimate'->'totals'->>'bought')::numeric + (v_pv->'estimate'->'totals'->>'sold')::numeric < v_per_point then
    v_qb := least(20, ceil(v_per_point / ((v_pv->'estimate'->'totals'->>'bought')::numeric / v_qb)) + 1);
    v_lines := jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_code, 'qty', 5),
                                 jsonb_build_object('side', 'buy',  'good', v_b_code, 'qty', v_qb));
  end if;

  -- (d) A PREVIEW MOVES NOTHING.
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_events0 from public.events where player_id = v_player;
  v_cargo_a0 := public.fleet_cargo_qty(v_fleet, v_a_code);
  v_cargo_b0 := public.fleet_cargo_qty(v_fleet, v_b_code);
  select stock into v_stock_a0 from public.port_goods where port_id = v_port and good_id = v_a;
  select stock into v_stock_b0 from public.port_goods where port_id = v_port and good_id = v_b;
  select coalesce(sum(qty), 0) into v_td0 from public.trade_daily where player_id = v_player;
  v_pv := cmd.preview_basket(v_fleet, v_lines);
  if coalesce((v_pv->>'ok')::boolean, false) is not true
     or jsonb_array_length(v_pv->'estimate'->'lines') is distinct from 2
     or v_pv->'estimate'->>'kind' is distinct from 'manifest'
     or v_pv->'estimate'->>'port' is distinct from v_port_code then
    raise exception '0083 self-assert FAIL: preview_basket did not answer a 2-line manifest at %: %', v_port_code, v_pv;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse0
     or public.fleet_cargo_qty(v_fleet, v_a_code) <> v_cargo_a0
     or public.fleet_cargo_qty(v_fleet, v_b_code) <> v_cargo_b0
     or (select count(*) from public.events where player_id = v_player) <> v_events0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_a) <> v_stock_a0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_b) <> v_stock_b0
     or (select coalesce(sum(qty), 0) from public.trade_daily where player_id = v_player) <> v_td0 then
    raise exception '0083 self-assert FAIL: the preview moved something — purse % -> %, cargo %/%, events %, stock %/%',
      v_purse0, (select ducats from public.players where id = v_player),
      public.fleet_cargo_qty(v_fleet, v_a_code), public.fleet_cargo_qty(v_fleet, v_b_code),
      (select count(*) from public.events where player_id = v_player),
      (select stock from public.port_goods where port_id = v_port and good_id = v_a),
      (select stock from public.port_goods where port_id = v_port and good_id = v_b);
  end if;

  -- (e) THE LINES ARE THE VERBS: cmd.preview of the same two orders, through the one grammar,
  --     hands back the same figures to the hundredth, because it is the same body.
  v_pa := cmd.preview(v_fleet, 'SELL ' || v_a_code || ' 5', null::jsonb);
  v_pb := cmd.preview(v_fleet, 'BUY ' || v_b_code || ' ' || v_qb::text, null::jsonb);
  if coalesce((v_pa->>'ok')::boolean, false) is not true or coalesce((v_pb->>'ok')::boolean, false) is not true then
    raise exception '0083 self-assert FAIL: cmd.preview refused a line the manifest accepted: % / %', v_pa, v_pb;
  end if;
  select l into v_la from jsonb_array_elements(v_pv->'estimate'->'lines') l where l->>'side' = 'sell';
  select l into v_lb from jsonb_array_elements(v_pv->'estimate'->'lines') l where l->>'side' = 'buy';
  if (v_la->>'total')::numeric        is distinct from (v_pa->'estimate'->>'total')::numeric
     or (v_la->>'avg_price')::numeric is distinct from (v_pa->'estimate'->>'avg_price')::numeric
     or (v_la->>'profit')::numeric    is distinct from (v_pa->'estimate'->>'profit')::numeric
     or (v_la->>'mid_total')::numeric is distinct from (v_pa->'estimate'->>'mid_total')::numeric
     or (v_la->>'tax_total')::numeric is distinct from (v_pa->'estimate'->>'tax_total')::numeric
     or (v_la->>'spread_total')::numeric is distinct from (v_pa->'estimate'->>'spread_total')::numeric
     or (v_la->>'haggle_saved')::numeric is distinct from (v_pa->'estimate'->>'haggle_saved')::numeric
     or (v_la->>'index')::int is distinct from 0 or v_la->>'good' is distinct from v_a_code or v_la->>'name' is distinct from v_a_name then
    raise exception '0083 self-assert FAIL: the manifest''s SELL line % is not cmd.preview''s SELL %', v_la, v_pa->'estimate';
  end if;
  if (v_lb->>'total')::numeric        is distinct from (v_pb->'estimate'->>'total')::numeric
     or (v_lb->>'avg_price')::numeric is distinct from (v_pb->'estimate'->>'avg_price')::numeric
     or (v_lb->>'mid_total')::numeric is distinct from (v_pb->'estimate'->>'mid_total')::numeric
     or (v_lb->>'tax_total')::numeric is distinct from (v_pb->'estimate'->>'tax_total')::numeric
     or (v_lb->>'spread_total')::numeric is distinct from (v_pb->'estimate'->>'spread_total')::numeric
     or (v_lb->>'haggle_saved')::numeric is distinct from (v_pb->'estimate'->>'haggle_saved')::numeric
     or jsonb_typeof(v_lb->'profit') is distinct from 'null' or jsonb_typeof(v_lb->'basis') is distinct from 'null'
     or (v_lb->>'index')::int is distinct from 1 or v_lb->>'good' is distinct from v_b_code then
    raise exception '0083 self-assert FAIL: the manifest''s BUY line % is not cmd.preview''s BUY %', v_lb, v_pb->'estimate';
  end if;

  -- (f) EXECUTE: the receipt IS the ledger.
  select count(*) into v_ledger0 from public.ledger where player_id = v_player;
  v_res := cmd.trade_basket(v_fleet, v_lines, v_version);
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    raise exception '0083 self-assert FAIL: trade_basket refused the worked example: %', v_res;
  end if;
  select ducats into v_purse1 from public.players where id = v_player;
  if (v_res->'purse'->>'before')::bigint is distinct from v_purse0
     or (v_res->'purse'->>'after')::bigint is distinct from v_purse1
     or (v_res->'purse'->>'after')::bigint - (v_res->'purse'->>'before')::bigint is distinct from (v_res->'totals'->>'net')::bigint
     or (v_res->'totals'->>'net')::bigint is distinct from (v_res->'totals'->>'sold')::bigint - (v_res->'totals'->>'bought')::bigint then
    raise exception '0083 self-assert FAIL: the receipt''s purse % / totals % disagree with the purse read back (% -> %)',
      v_res->'purse', v_res->'totals', v_purse0, v_purse1;
  end if;
  select l into v_la from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'sell';
  select l into v_lb from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'buy';
  if (select count(*) from public.events where player_id = v_player) <> v_events0 + 2
     or (select count(*) from public.ledger where player_id = v_player) <> v_ledger0 + 2 then
    raise exception '0083 self-assert FAIL: a 2-line manifest wrote % event(s) and % ledger row(s), expected 2 and 2',
      (select count(*) from public.events where player_id = v_player) - v_events0,
      (select count(*) from public.ledger where player_id = v_player) - v_ledger0;
  end if;
  --     The two new events carry the lines' own figures ...
  select count(*) into v_n from public.events e
   where e.player_id = v_player and e.kind = 'SOLD'
     and (e.payload->>'qty')::numeric = (v_la->>'qty')::numeric
     and (e.payload->>'total')::bigint = (v_la->>'total')::bigint
     and (e.payload->>'profit')::bigint = (v_la->>'profit')::bigint
     and (e.payload->>'mid_total')::numeric = (v_la->>'mid_total')::numeric
     and (e.payload->>'tax_total')::numeric = (v_la->>'tax_total')::numeric
     and (e.payload->>'spread_total')::numeric = (v_la->>'spread_total')::numeric
     and e.payload->>'good' = v_a_name;
  if v_n <> 1 then
    raise exception '0083 self-assert FAIL: % SOLD event(s) match the receipt''s SELL line %', v_n, v_la;
  end if;
  select count(*) into v_n from public.events e
   where e.player_id = v_player and e.kind = 'BOUGHT'
     and (e.payload->>'qty')::numeric = (v_lb->>'qty')::numeric
     and (e.payload->>'total')::bigint = (v_lb->>'total')::bigint
     and (e.payload->>'mid_total')::numeric = (v_lb->>'mid_total')::numeric
     and (e.payload->>'tax_total')::numeric = (v_lb->>'tax_total')::numeric
     and (e.payload->>'spread_total')::numeric = (v_lb->>'spread_total')::numeric
     and e.payload->>'good' = v_b_name;
  if v_n <> 1 then
    raise exception '0083 self-assert FAIL: % BOUGHT event(s) match the receipt''s BUY line %', v_n, v_lb;
  end if;
  --     ... in order — the ledger's running balance says the sale landed before the purchase ...
  --     (every row this transaction wrote shares one now(), so the rows are found by what they
  --      record — the good's name on the event — never by timestamp)
  select l.balance_after into v_sold_bal from public.ledger l join public.events e on e.id = l.ref_event_id
   where l.player_id = v_player and e.kind = 'SOLD' and e.payload->>'good' = v_a_name;
  select l.balance_after into v_bought_bal from public.ledger l join public.events e on e.id = l.ref_event_id
   where l.player_id = v_player and e.kind = 'BOUGHT' and e.payload->>'good' = v_b_name;
  if v_sold_bal is distinct from v_purse0 + (v_la->>'total')::bigint or v_bought_bal is distinct from v_purse1 then
    raise exception '0083 self-assert FAIL: the ledger ran % -> % -> %, so the sale did not land first or the purchase did not land last (purse % -> %)',
      v_purse0, v_sold_bal, v_bought_bal, v_purse0, v_purse1;
  end if;
  --     ... and Σ of the two new ledger rows is the receipt's net.
  if (select sum(l.ducats_delta) from public.ledger l join public.events e on e.id = l.ref_event_id
       where l.player_id = v_player
         and ((e.kind = 'SOLD' and e.payload->>'good' = v_a_name) or (e.kind = 'BOUGHT' and e.payload->>'good' = v_b_name)))
     is distinct from (v_res->'totals'->>'net')::bigint then
    raise exception '0083 self-assert FAIL: the two new ledger rows sum to %, the receipt says net %',
      (select sum(l.ducats_delta) from public.ledger l join public.events e on e.id = l.ref_event_id
        where l.player_id = v_player
          and ((e.kind = 'SOLD' and e.payload->>'good' = v_a_name) or (e.kind = 'BOUGHT' and e.payload->>'good' = v_b_name))),
      v_res->'totals'->>'net';
  end if;
  if public.fleet_cargo_qty(v_fleet, v_a_code) <> 5 or public.fleet_cargo_qty(v_fleet, v_b_code) <> v_qb then
    raise exception '0083 self-assert FAIL: after SELL 5 / BUY % the hold carries % t of % and % t of %',
      v_qb, public.fleet_cargo_qty(v_fleet, v_a_code), v_a_code, public.fleet_cargo_qty(v_fleet, v_b_code), v_b_code;
  end if;
  if (v_res->'hold'->>'free_after')::numeric is distinct from public.fleet_free_hold(v_fleet)
     or (v_res->'hold'->>'tuns_delta')::numeric is distinct from (v_res->'hold'->>'free_before')::numeric - (v_res->'hold'->>'free_after')::numeric then
    raise exception '0083 self-assert FAIL: the receipt''s hold % is not the hold read back (%)', v_res->'hold', public.fleet_free_hold(v_fleet);
  end if;
  if (select version from public.fleets where id = v_fleet) <> v_version + 1
     or (v_res->>'version')::int is distinct from v_version + 1 then
    raise exception '0083 self-assert FAIL: the fleet is at version % after one manifest from %, receipt says %',
      (select version from public.fleets where id = v_fleet), v_version, v_res->>'version';
  end if;
  --     THE DOUBLE-TAP: the same manifest with the same expected version again. The guard is
  --     the locked predicate in the skin's UPDATE; sequentially it must read E_STALE, name the
  --     current version, and move nothing — cargo, purse, events, version.
  v_bad := cmd.trade_basket(v_fleet, v_lines, v_version);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_STALE'
     or (v_bad->>'version')::int is distinct from v_version + 1 then
    raise exception '0083 self-assert FAIL: a manifest with the old version % was not refused E_STALE naming version %: %', v_version, v_version + 1, v_bad;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse1
     or public.fleet_cargo_qty(v_fleet, v_a_code) <> 5 or public.fleet_cargo_qty(v_fleet, v_b_code) <> v_qb
     or (select count(*) from public.events where player_id = v_player) <> v_events0 + 2
     or (select version from public.fleets where id = v_fleet) <> v_version + 1 then
    raise exception '0083 self-assert FAIL: the second tap of the same manifest moved something (purse %, % / % t aboard, % events, version %)',
      (select ducats from public.players where id = v_player), public.fleet_cargo_qty(v_fleet, v_a_code), public.fleet_cargo_qty(v_fleet, v_b_code),
      (select count(*) from public.events where player_id = v_player), (select version from public.fleets where id = v_fleet);
  end if;

  -- (g) XP IS HONEST: the delta is player_progress after less before, the level is the curve's
  --     word for the points, and the example turned over enough to move at least one point.
  if (v_res->'totals'->>'bought')::numeric + (v_res->'totals'->>'sold')::numeric < v_per_point then
    raise exception '0083 self-assert FAIL: the example turned over % d. against % d. per point — delta could be 0 and (g) would prove nothing',
      (v_res->'totals'->>'bought')::numeric + (v_res->'totals'->>'sold')::numeric, v_per_point;
  end if;
  if (v_res->'trading'->>'delta')::int < 1
     or (v_res->'trading'->>'delta')::int is distinct from (v_res->'trading'->>'points_after')::int - (v_res->'trading'->>'points_before')::int
     or (v_res->'trading'->>'points_after')::int is distinct from (public.player_progress(v_player)->'trading'->>'points')::int
     or (v_res->'trading'->>'level_after')::int is distinct from public.level_from_points((v_res->'trading'->>'points_after')::int)
     or (v_res->'trading'->>'turnover_after')::numeric is distinct from (public.player_progress(v_player)->'trading'->>'turnover')::numeric then
    raise exception '0083 self-assert FAIL: the receipt''s trading % is not public.player_progress''s % ', v_res->'trading', public.player_progress(v_player)->'trading';
  end if;

  -- (h) ATOMIC: a refused second line leaves the first unlanded. The buy asks for one tun more
  --     than the hold will take AFTER the sale has made room, so cmd.do_buy's own E_HOLD_FULL
  --     refuses it (0022:709 — hold before stock, cap and purse), and the sale must be gone too.
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_events0 from public.events where player_id = v_player;
  v_cargo_a0 := public.fleet_cargo_qty(v_fleet, v_a_code);
  v_cargo_b0 := public.fleet_cargo_qty(v_fleet, v_b_code);
  select stock into v_stock_a0 from public.port_goods where port_id = v_port and good_id = v_a;
  select stock into v_stock_b0 from public.port_goods where port_id = v_port and good_id = v_b;
  select coalesce(sum(qty), 0) into v_td0 from public.trade_daily where player_id = v_player;
  v_version := (select version from public.fleets where id = v_fleet);
  v_over := floor((public.fleet_free_hold(v_fleet) + 5 * v_a_bulk) / v_b_bulk) + 1;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'sell', 'good', v_a_code, 'qty', 5),
             jsonb_build_object('side', 'buy',  'good', v_b_code, 'qty', v_over)), v_version);
  if coalesce((v_bad->>'ok')::boolean, true)
     or v_bad->>'error_code' is distinct from 'E_HOLD_FULL'
     or (v_bad->>'line')::int is distinct from 1
     or v_bad->'figures'->>'unit' is distinct from 't' then
    raise exception '0083 self-assert FAIL: a manifest whose second line asks for % t of % was not refused E_HOLD_FULL on line 1 with tun figures: %', v_over, v_b_code, v_bad;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse0
     or public.fleet_cargo_qty(v_fleet, v_a_code) <> v_cargo_a0
     or public.fleet_cargo_qty(v_fleet, v_b_code) <> v_cargo_b0
     or (select count(*) from public.events where player_id = v_player) <> v_events0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_a) <> v_stock_a0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_b) <> v_stock_b0
     or (select coalesce(sum(qty), 0) from public.trade_daily where player_id = v_player) <> v_td0
     or (select version from public.fleets where id = v_fleet) <> v_version then
    raise exception '0083 self-assert FAIL: a refused manifest moved something — purse % -> %, % % / % % aboard (was % / %), events % (was %), version % (was %)',
      v_purse0, (select ducats from public.players where id = v_player),
      public.fleet_cargo_qty(v_fleet, v_a_code), v_a_code, public.fleet_cargo_qty(v_fleet, v_b_code), v_b_code, v_cargo_a0, v_cargo_b0,
      (select count(*) from public.events where player_id = v_player), v_events0,
      (select version from public.fleets where id = v_fleet), v_version;
  end if;
  --     THE POSITIVE CONTROL, watched red: the same two verbs WITHOUT the savepoint. The refusal
  --     is swallowed per line — the defect the skin exists to prevent — and the sale STAYS.
  begin
    perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_a::text, 'qty', 5));
    begin
      perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_b::text, 'qty', v_over));
    exception when others then
      v_ctrl_seen := true;
    end;
    v_ctrl_a := public.fleet_cargo_qty(v_fleet, v_a_code);
    raise exception '__0083_CONTROL__';
  exception when others then
    if sqlerrm <> '__0083_CONTROL__' then raise; end if;
  end;
  if not v_ctrl_seen or v_ctrl_a is distinct from v_cargo_a0 - 5 then
    raise exception '0083 self-assert FAIL: the non-atomic control did not show the defect (buy refused: %, % t of % after a swallowed refusal, expected %) — the atomicity assert is not testing anything',
      v_ctrl_seen, v_ctrl_a, v_a_code, v_cargo_a0 - 5;
  end if;
  if public.fleet_cargo_qty(v_fleet, v_a_code) <> v_cargo_a0 then
    raise exception '0083 self-assert FAIL: the control leaked: % t of % aboard, expected %', public.fleet_cargo_qty(v_fleet, v_a_code), v_a_code, v_cargo_a0;
  end if;

  -- (i) THE BREAKDOWN ADDS UP, to the rounding the unit price carries, on the executed lines ...
  if abs((v_lb->>'mid_total')::numeric + (v_lb->>'tax_total')::numeric + (v_lb->>'spread_total')::numeric - (v_lb->>'total')::numeric)
       > 0.005 * (v_lb->>'qty')::numeric + 0.5
     or (v_lb->>'mid_total')::numeric <= 0 or (v_lb->>'tax_total')::numeric < 0 or (v_lb->>'spread_total')::numeric <= 0 then
    raise exception '0083 self-assert FAIL: BUY line mid % + tax % + spread % is not its total % within the unit rounding',
      v_lb->>'mid_total', v_lb->>'tax_total', v_lb->>'spread_total', v_lb->>'total';
  end if;
  if abs((v_la->>'mid_total')::numeric - (v_la->>'tax_total')::numeric - (v_la->>'spread_total')::numeric - (v_la->>'total')::numeric)
       > 0.005 * (v_la->>'qty')::numeric + 0.5
     or (v_la->>'mid_total')::numeric <= 0 or (v_la->>'spread_total')::numeric <= 0 then
    raise exception '0083 self-assert FAIL: SELL line mid % - tax % - spread % is not its total % within the unit rounding',
      v_la->>'mid_total', v_la->>'tax_total', v_la->>'spread_total', v_la->>'total';
  end if;
  if (v_la->>'haggle_saved')::numeric is distinct from 0 or (v_lb->>'haggle_saved')::numeric is distinct from 0 then
    raise exception '0083 self-assert FAIL: a house that struck no bargain was told it saved % / %', v_la->>'haggle_saved', v_lb->>'haggle_saved';
  end if;
  --     ... and haggle_saved is what the bargain took off: the same 10 t of B quoted with and
  --     without an open bargain (a row written directly, as proof 03 does, then removed).
  select * into v_q0 from world.quote(v_port, v_b, 10, 'buy', null, v_fleet);
  insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession)
  values (v_player, v_port, v_b, world.game_day(), 1, 1, 0.5);
  select * into v_q1 from world.quote(v_port, v_b, 10, 'buy', null, v_fleet);
  --     ... and while the bargain row stands, p_with_bargain is the switch: with it the spread
  --     is narrower; without it the same fleet reads the same figure as no fleet at all.
  if world.spread_effective(v_port, v_b, v_fleet, true) >= world.spread_effective(v_port, v_b, v_fleet, false)
     or world.spread_effective(v_port, v_b, v_fleet, false) is distinct from world.spread_effective(v_port, v_b, null)
     or world.spread_effective(v_port, v_b, v_fleet) is distinct from world.spread_effective(v_port, v_b, v_fleet, true) then
    raise exception '0083 self-assert FAIL: with a bargain open world.spread_effective reads % with it, % without it, % with no fleet — p_with_bargain is not the switch',
      world.spread_effective(v_port, v_b, v_fleet, true), world.spread_effective(v_port, v_b, v_fleet, false), world.spread_effective(v_port, v_b, null);
  end if;
  delete from public.haggle_daily where player_id = v_player and port_id = v_port and good_id = v_b;
  if v_q1.haggle_saved <= 0 or v_q1.total >= v_q0.total
     or abs(v_q1.haggle_saved - (v_q0.total - v_q1.total)) > 1
     or v_q1.mid_total <> v_q0.mid_total or v_q1.tax_total <> v_q0.tax_total
     or v_q1.spread_total >= v_q0.spread_total then
    raise exception '0083 self-assert FAIL: with a 0.5 bargain open 10 t of % quoted % (saved %, spread %) against % unbargained (spread %) — haggle_saved is not what the bargain took off',
      v_b_code, v_q1.total, v_q1.haggle_saved, v_q1.spread_total, v_q0.total, v_q0.spread_total;
  end if;

  -- (j) MALFORMED manifests are refused by SHAPE, and each leaves the world alone.
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_events0 from public.events where player_id = v_player;
  v_version := (select version from public.fleets where id = v_fleet);
  v_bad := cmd.trade_basket(v_fleet, '[]'::jsonb, v_version);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_MANIFEST_EMPTY' or v_bad->'line' is distinct from 'null'::jsonb then
    raise exception '0083 self-assert FAIL: an empty manifest was not refused E_MANIFEST_EMPTY: %', v_bad;
  end if;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'buy',  'good', v_a_code, 'qty', 5),
             jsonb_build_object('side', 'sell', 'good', v_a_code, 'qty', 5)), v_version);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_MANIFEST_DUPLICATE' or (v_bad->>'line')::int is distinct from 1 then
    raise exception '0083 self-assert FAIL: % on two lines was not refused E_MANIFEST_DUPLICATE at line 1: %', v_a_code, v_bad;
  end if;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'sell', 'good', v_a_code, 'qty', 5),
             jsonb_build_object('side', 'swap', 'good', v_b_code, 'qty', 5)), v_version);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_MANIFEST_LINE' or (v_bad->>'line')::int is distinct from 1 then
    raise exception '0083 self-assert FAIL: a line with side ''swap'' was not refused E_MANIFEST_LINE at line 1: %', v_bad;
  end if;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'buy', 'good', 'no_such_good_0083', 'qty', 5)), v_version);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_NO_SUCH_GOOD' or (v_bad->>'line')::int is distinct from 0 then
    raise exception '0083 self-assert FAIL: an unknown good was not refused E_NO_SUCH_GOOD at line 0: %', v_bad;
  end if;
  v_bad := cmd.preview_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'buy', 'good', v_b_code, 'qty', 0)));
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_MANIFEST_LINE' then
    raise exception '0083 self-assert FAIL: a quantity of 0 was not refused E_MANIFEST_LINE by the preview: %', v_bad;
  end if;
  v_bad := cmd.preview_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_code, 'qty', 0.5)));
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_MANIFEST_LINE' or (v_bad->>'line')::int is distinct from 0 then
    raise exception '0083 self-assert FAIL: half a tun was not refused E_MANIFEST_LINE at line 0 — a manifest takes whole tuns only: %', v_bad;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse0
     or (select count(*) from public.events where player_id = v_player) <> v_events0
     or (select version from public.fleets where id = v_fleet) <> v_version
     or public.fleet_cargo_qty(v_fleet, v_a_code) <> 5 then
    raise exception '0083 self-assert FAIL: a malformed manifest moved something (purse % -> %, events % -> %, version % -> %)',
      v_purse0, (select ducats from public.players where id = v_player), v_events0,
      (select count(*) from public.events where player_id = v_player), v_version, (select version from public.fleets where id = v_fleet);
  end if;

  -- (j2) THE QUAY ROWS ARE LOCKED FIRST, IN ONE ORDER — asserted STRUCTURALLY: the statement is
  --      in the live body, before the first verb call. A single session cannot stage the race
  --      this prevents, and this file does not pretend to; it checks that the order exists.
  v_body := pg_get_functiondef('cmd.run_manifest(uuid, jsonb)'::regprocedure);
  if position(E'order by pg.good_id\n      for update;' in v_body) = 0
     or position(E'order by pg.good_id\n      for update;' in v_body) > position('cmd.do_sell(p_fleet' in v_body) then
    raise exception '0083 self-assert FAIL: cmd.run_manifest does not lock its quay rows in good_id order before the first verb';
  end if;
  --      ... and a lock collision is answered as E_BUSY, retryable, by the one envelope builder.
  v_busy := cmd.manifest_refused(v_fleet, '40P01', 'deadlock detected', '', null);
  if v_busy->>'error_code' is distinct from 'E_BUSY' or v_busy->'fixes' is distinct from jsonb_build_array('(try again)')
     or (cmd.manifest_refused(v_fleet, '55P03', 'could not obtain lock', '', null))->>'error_code' is distinct from 'E_BUSY'
     or (cmd.manifest_refused(v_fleet, 'P0001', 'E_HOLD_FULL: no room', cmd.figures(1, 2, 't')::text, '3'))->>'error_code' is distinct from 'E_HOLD_FULL'
     or ((cmd.manifest_refused(v_fleet, 'P0001', 'E_HOLD_FULL: no room', cmd.figures(1, 2, 't')::text, '3'))->>'line')::int is distinct from 3 then
    raise exception '0083 self-assert FAIL: cmd.manifest_refused does not answer E_BUSY for 40P01 / 55P03 and the 0050 envelope otherwise: %', v_busy;
  end if;

  -- CLOSE THE EXAMPLE THROUGH THE VERBS (0081:648-652): sell the 5 t of A and the % t of B back,
  -- so the hold is empty and the quay's stock is exactly where this file found it — every buy and
  -- sale above moved it by whole units, and they net to zero.
  perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_a::text, 'qty', 5));
  perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_b::text, 'qty', v_qb));
  if public.fleet_cargo_qty(v_fleet, v_a_code) <> 0 or public.fleet_cargo_qty(v_fleet, v_b_code) <> 0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_a) <> v_stock_a_init
     or (select stock from public.port_goods where port_id = v_port and good_id = v_b) <> v_stock_b_init then
    raise exception '0083 self-assert FAIL: the example did not close — % / % t aboard, stock % / % against % / % before it began',
      public.fleet_cargo_qty(v_fleet, v_a_code), public.fleet_cargo_qty(v_fleet, v_b_code),
      (select stock from public.port_goods where port_id = v_port and good_id = v_a), (select stock from public.port_goods where port_id = v_port and good_id = v_b),
      v_stock_a_init, v_stock_b_init;
  end if;

  -- (k) PARITY: each re-cut body is its pre-image with exactly the declared hunks swapped in.
  for v_r in select fn, def from defs_before_0083 where fn <> 'public.client_rpc_entry_points()' loop
    v_expect := v_r.def;
    if v_r.fn = 'world.spread_effective(uuid, uuid, uuid)' then
      v_expect := replace(v_expect,
        'CREATE OR REPLACE FUNCTION world.spread_effective(p_port uuid, p_good uuid, p_fleet uuid DEFAULT NULL::uuid)',
        'CREATE OR REPLACE FUNCTION world.spread_effective(p_port uuid, p_good uuid, p_fleet uuid DEFAULT NULL::uuid, p_with_bargain boolean DEFAULT true)');
      v_expect := replace(v_expect,
        E'    if v_player is not null then\n      v_hag := public.haggle_concession(v_player, p_port, p_good);\n    end if;',
        E'    -- 0083: asked with p_with_bargain = false this is what the SAME house executes at without\n'
        || E'    -- today\'s bargain — world.quote reads both, so it can say what the bargain saved.\n'
        || E'    if v_player is not null and p_with_bargain then\n      v_hag := public.haggle_concession(v_player, p_port, p_good);\n    end if;');
      select pg_get_functiondef('world.spread_effective(uuid,uuid,uuid,boolean)'::regprocedure) into v_def;
    elsif v_r.fn = 'world.quote(uuid, uuid, numeric, text, numeric, uuid)' then
      v_expect := replace(v_expect,
        ' RETURNS TABLE(units numeric, total bigint, avg_price numeric, end_stock numeric)',
        ' RETURNS TABLE(units numeric, total bigint, avg_price numeric, end_stock numeric, mid_total numeric, tax_total numeric, spread_total numeric, haggle_saved numeric)');
      v_expect := replace(v_expect,
        E'  v_units  numeric := 0;\n  v_total  numeric := 0;\nbegin',
        E'  v_units  numeric := 0;\n  v_total  numeric := 0;\n'
        || E'  -- 0083: the four parts of the money, and the spread this house would pay with no bargain.\n'
        || E'  v_nohag  numeric;\n  v_mid_t  numeric := 0;\n  v_tax_t  numeric := 0;\n  v_spr_t  numeric := 0;\n  v_hag_t  numeric := 0;\nbegin');
      v_expect := replace(v_expect,
        E'  v_spread := world.spread_effective(p_port, p_good, p_fleet);\n  v_tax    := world.tax_rate(p_port);',
        E'  v_spread := world.spread_effective(p_port, p_good, p_fleet);\n'
        || E'  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.\n'
        || E'  v_nohag  := case when p_fleet is null then v_spread\n'
        || E'                   else world.spread_effective(p_port, p_good, p_fleet, false) end;\n'
        || E'  v_tax    := world.tax_rate(p_port);');
      v_expect := replace(v_expect,
        E'      v_total := v_total + v_unit * v_n;\n      v_stock := v_stock - v_n;',
        E'      v_total := v_total + v_unit * v_n;\n'
        || E'      -- 0083: the same unit price in its parts, from the same v_mid / v_tax / v_spread; the parts\n'
        || E'      -- differ from v_unit only by v_unit\'s rounding to the hundredth.\n'
        || E'      v_mid_t := v_mid_t + v_mid * v_n;\n'
        || E'      v_tax_t := v_tax_t + v_mid * v_tax * v_n;\n'
        || E'      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;\n'
        || E'      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;\n'
        || E'      v_stock := v_stock - v_n;');
      v_expect := replace(v_expect,
        E'      v_total := v_total + v_unit * v_n;\n      v_stock := v_stock + v_n;',
        E'      v_total := v_total + v_unit * v_n;\n'
        || E'      v_mid_t := v_mid_t + v_mid * v_n;\n'
        || E'      v_tax_t := v_tax_t + v_mid * (1 - v_spread / 2) * v_tax * v_n;\n'
        || E'      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;\n'
        || E'      v_hag_t := v_hag_t + (v_unit - round(v_mid * (1 - v_nohag / 2) * (1 - v_tax), 2)) * v_n;\n'
        || E'      v_stock := v_stock + v_n;');
      v_expect := replace(v_expect,
        E'  end_stock := v_stock;\n  return next;',
        E'  end_stock := v_stock;\n'
        || E'  -- 0083: `total` remains the ONLY figure the purse moves by. These four are exact sums that\n'
        || E'  -- differ from it only by the per-unit 2-dp rounding above; a client prints them and never adds\n'
        || E'  -- them back together.\n'
        || E'  mid_total    := round(v_mid_t, 2);\n  tax_total    := round(v_tax_t, 2);\n'
        || E'  spread_total := round(v_spr_t, 2);\n  haggle_saved := round(v_hag_t, 2);\n  return next;');
      select pg_get_functiondef('world.quote(uuid,uuid,numeric,text,numeric,uuid)'::regprocedure) into v_def;
    else
      if v_r.fn = 'cmd.do_buy(uuid, jsonb)' then
        v_expect := replace(v_expect,
          E'      \'haggled\', v_conc > 0, \'concession\', v_conc)));',
          E'      \'haggled\', v_conc > 0, \'concession\', v_conc,\n'
          || E'      \'mid_total\', q.mid_total, \'tax_total\', q.tax_total, \'spread_total\', q.spread_total,\n'
          || E'      \'haggle_saved\', q.haggle_saved)));');
        v_expect := replace(v_expect,
          E'                            \'avg_price\', q.avg_price, \'concession_spent\', v_conc);',
          E'                            \'avg_price\', q.avg_price, \'concession_spent\', v_conc,\n'
          || E'                            \'mid_total\', q.mid_total, \'tax_total\', q.tax_total,\n'
          || E'                            \'spread_total\', q.spread_total, \'haggle_saved\', q.haggle_saved);');
      else
        v_expect := replace(v_expect,
          E'      \'basis\', v_basis, \'cost\', v_cost, \'profit\', v_profit)));',
          E'      \'basis\', v_basis, \'cost\', v_cost, \'profit\', v_profit,\n'
          || E'      \'mid_total\', q.mid_total, \'tax_total\', q.tax_total, \'spread_total\', q.spread_total,\n'
          || E'      \'haggle_saved\', q.haggle_saved)));');
        v_expect := replace(v_expect,
          E'                            \'basis\', v_basis, \'cost\', v_cost, \'profit\', v_profit);',
          E'                            \'basis\', v_basis, \'cost\', v_cost, \'profit\', v_profit,\n'
          || E'                            \'mid_total\', q.mid_total, \'tax_total\', q.tax_total,\n'
          || E'                            \'spread_total\', q.spread_total, \'haggle_saved\', q.haggle_saved);');
      end if;
      select pg_get_functiondef(v_r.fn::regprocedure) into v_def;
    end if;
    if v_def <> v_expect then
      raise exception '0083 self-assert FAIL: % is not its pre-image with only the declared hunks swapped in (% chars before, % after, % expected)',
        v_r.fn, length(v_r.def), length(v_def), length(v_expect);
    end if;
    if v_def = v_r.def then
      raise exception '0083 self-assert FAIL: % is byte-identical to its pre-image — the slice did nothing', v_r.fn;
    end if;
  end loop;
  --     ... and the catalogue is 0047's text with exactly two rows added (the rest is not retyped).
  select def into v_def from defs_before_0083 where fn = 'public.client_rpc_entry_points()';
  if pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure) <> replace(v_def,
       E'      (\'cmd\',         \'divert\',              \'uuid, uuid, jsonb, jsonb\')\n',
       E'      (\'cmd\',         \'divert\',              \'uuid, uuid, jsonb, jsonb\'),\n'
       || E'      -- 0083: the manifest — one order of many lines, and its dry run.\n'
       || E'      (\'cmd\',         \'trade_basket\',        \'uuid, jsonb, int\'),\n'
       || E'      (\'cmd\',         \'preview_basket\',      \'uuid, jsonb\')\n') then
    raise exception '0083 self-assert FAIL: public.client_rpc_entry_points is not 0047''s text with the two manifest rows added';
  end if;

  -- (l) THE POSTURE: sliced ACLs byte-identical; the two dropped bodies and the one body off
  --     every client role; the two doors open to authenticated only; both halves read zero.
  for v_r in select fn, acl from defs_before_0083
              where fn in ('cmd.do_buy(uuid, jsonb)', 'cmd.do_sell(uuid, jsonb)', 'public.client_rpc_entry_points()') loop
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_r.fn::regprocedure), '') is distinct from v_r.acl then
      raise exception '0083 self-assert FAIL: the ACL of % moved — was [%], is now [%]', v_r.fn, v_r.acl,
        coalesce((select p.proacl::text from pg_proc p where p.oid = v_r.fn::regprocedure), '');
    end if;
  end loop;
  foreach v_fn in array array[
      'world.quote(uuid, uuid, numeric, text, numeric, uuid)',
      'world.spread_effective(uuid, uuid, uuid, boolean)',
      'cmd.run_manifest(uuid, jsonb)',
      'cmd.manifest_line_caught(text)',
      'cmd.manifest_refused(uuid, text, text, text, text)',
      'cmd.do_buy(uuid, jsonb)', 'cmd.do_sell(uuid, jsonb)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0083 self-assert FAIL: a client role may execute %', v_fn;
    end if;
  end loop;
  foreach v_fn in array array['cmd.trade_basket(uuid, jsonb, int)', 'cmd.preview_basket(uuid, jsonb)'] loop
    if not has_function_privilege('authenticated', v_fn, 'execute') or has_function_privilege('anon', v_fn, 'execute') then
      raise exception '0083 self-assert FAIL: % is not open to authenticated and closed to anon', v_fn;
    end if;
  end loop;
  select count(*) into v_n from public.client_rpc_entry_points() e
   where e.fn is not null and e.function_name in ('trade_basket', 'preview_basket') and e.schema_name = 'cmd';
  if v_n <> 2 then
    raise exception '0083 self-assert FAIL: client_rpc_entry_points names % of the 2 manifest doors with a resolvable fn', v_n;
  end if;
  if (select count(*) from public.client_rpc_entry_points() where fn is null) <> 0 then
    raise exception '0083 self-assert FAIL: client_rpc_entry_points names a function that does not exist';
  end if;
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then
    raise exception '0083 self-assert FAIL: % client write grant(s) after this migration', v_n;
  end if;
  select count(*) into v_n from public.client_executable_writers();
  if v_n <> 0 then
    raise exception '0083 self-assert FAIL: % client-executable writer(s) after this migration: %', v_n,
      (select string_agg(schema_name || '.' || function_name || ' ' || grantee, ', ') from public.client_executable_writers());
  end if;

  -- WHAT IS LEFT: the house (public.events is append-only, 0081:648-652, and the ledger being
  -- immutable is a rule of the game), its ledger rows, and its trade_daily rows for today. Its
  -- hold is empty and the quay's stock reads exactly what it read before the example (asserted).
  raise notice '0083 self-assert ok: A MANIFEST IS ONE ORDER. world.spread_effective takes p_with_bargain (3-arg twin gone) and world.quote says where the money went (mid_total / tax_total / spread_total / haggle_saved) — 500 pre-image quotes unchanged on (units, total, avg_price, end_stock). At % a fresh house held 10 t of %; a preview of [SELL % 5, BUY % %] moved nothing and its two lines equalled cmd.preview''s SELL and BUY to the hundredth; the committed manifest sold % t for % d. (profit % d.) and bought % t for % d., net % d., the purse read % -> % and the ledger''s two new rows ran % -> % -> %, cargo 5 / %, version % -> % and the same tap again is E_STALE and moves nothing; trading +% point(s) (% -> %, level %), read from player_progress; a second manifest whose BUY asked % t was refused E_HOLD_FULL at line 1 with tun figures and moved nothing, while the same two verbs without the savepoint left % of the % t aboard (the defect, thrown away); BUY breakdown % + % + % ~ %, SELL % - % - % ~ %; a 0.5 bargain on 10 t of % saved % d. of a % d. quote; [] / duplicate / ''swap'' / unknown good / qty 0 / qty 0.5 refused E_MANIFEST_EMPTY / _DUPLICATE / _LINE / E_NO_SUCH_GOOD / _LINE / _LINE and moved nothing; the quay rows are locked in good_id order before the first verb and a lock collision answers E_BUSY; the example closed through the verbs with an empty hold and the quay''s stock of % / % exactly where it began; four re-cut bodies are their pre-images with only the declared hunks, the catalogue is 0047''s with two rows; do_buy / do_sell ACLs unmoved, quote / spread_effective / run_manifest / manifest_line_caught / manifest_refused closed to clients, trade_basket / preview_basket open to authenticated only, 0 client write grants, 0 client-executable writers.',
    v_port_code, v_a_code, v_a_code, v_b_code, v_qb,
    v_la->>'qty', v_la->>'total', v_la->>'profit', v_lb->>'qty', v_lb->>'total', v_res->'totals'->>'net',
    v_res->'purse'->>'before', v_res->'purse'->>'after', v_res->'purse'->>'before', v_sold_bal, v_bought_bal,
    v_qb, (v_res->>'version')::int - 1, v_res->>'version',
    v_res->'trading'->>'delta', v_res->'trading'->>'points_before', v_res->'trading'->>'points_after', v_res->'trading'->>'level_after',
    v_over, v_ctrl_a, v_cargo_a0,
    v_lb->>'mid_total', v_lb->>'tax_total', v_lb->>'spread_total', v_lb->>'total',
    v_la->>'mid_total', v_la->>'tax_total', v_la->>'spread_total', v_la->>'total',
    v_b_code, v_q1.haggle_saved, v_q0.total, v_stock_a_init, v_stock_b_init;
end $$;
