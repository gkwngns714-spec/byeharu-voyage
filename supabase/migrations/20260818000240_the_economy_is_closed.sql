-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0240 — THE ECONOMY IS CLOSED
--        (slice E7 of docs/CLOSED_ECONOMY.md §6, §7, §8: THE GUARD at the two money writers and THE SWITCH.
--         This file does NOT light it. Lit later by one `select public.economy_close_switch(true)`, with the deploy note.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (docs/OWNER_REQUESTS.md row 212, 2026-10-26) ──────────────────────────────────────
--   "i want the gold to be stopped here, meaning no more excess gold produced - so that the economy circulates like
--   real world." … "lets try this model and see the stats after few days."
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   NEW, server-only:
--     public.mint_guard(kind, delta)      THE one judge of "is this new gold?": closed (economy_closed() and the purses
--                                         lit), a POSITIVE delta of a MINTED kind (stats_flow_words.side = 'minted':
--                                         EARNINGS, FOUNDING, GRANT, IMPORT_DEMAND, NPC_REFOUND, SEED) is refused —
--                                         E_NO_NEW_GOLD. Open: nothing.
--     public.economy_close_switch(on)     THE switch (§6). true: refused while the purses are dark (E_PURSES_DARK);
--                                         seeds port_treasury.invested = Σ city_shares.paid where it is null (§3);
--                                         records economy_closed_at + economy_closed_total (the world total at that
--                                         second, world.stats_now()'s `total`); flips economy_closed; writes ONE
--                                         events row ECONOMY_SWITCH (player null) for the news (docs/NEWS_AND_MARKERS.md).
--                                         false: economy_closed false, the two records back to null, one ECONOMY_SWITCH
--                                         row. Asked for what already is: {changed: false}, nothing written.
--   KNOBS: economy_closed_at, economy_closed_total (both null).
--   HUNKS (one each):
--     public.credit          a positive minted kind goes through mint_guard unless byeharu.paid_by_city = 'on'.
--     public.treasury_post   a positive minted kind goes through mint_guard (a city is never paid new gold).
--     public.city_pays       when the city's purse really paid (treasury_post wrote its row), its credit runs with
--                            byeharu.paid_by_city = 'on' (set_config local) and the setting is put back after — so a
--                            capital-paid FOUNDING (0234 capital_pays → city_pays) passes, and nothing else does.
--
-- ── DECIDED BY DEFAULT (the owner reverses) ─────────────────────────────────────────────────────
--   * The drift knobs of §6 (600 s, 0.932, 0.0166) are NOT set by this switch: they are §4's noise and ride with E6.
--     drift_slot_seconds has 16 readers, and port_goods.drift_slot is stored in slot units: 900 → 600 → 900 would leave
--     every row's slot ahead of the clock and freeze the drift for months after a switch-back.
--   * `invested` is seeded here (only where null, so a re-light keeps E5's decayed figure) and left as it is on OFF:
--     it is a figure read by nothing until E5, not a knob.
--   * "Lit" for the guard = economy_closed() AND the purses lit — the same test 0234's founding_credit makes, so a
--     closed economy with dark purses never blocks a sign-up (and the switch refuses to close with dark purses).
--   * A negative minted kind (none exists) is not judged: it is not new gold.
--
-- ── WHAT STILL MINTS, AND WHAT IT DOES LIT (docs/dev-log/2026-10-26-econ-e7.md has the table) ─────
--   EARNINGS (city_day) and IMPORT_DEMAND (cmd.do_sell): not posted lit (0233). SEED (city_treasury_switch, new-harbour
--   migrations): REFUSED lit. FOUNDING (new_house, npc_fix_hull_skills via founding_credit): paid by the capital
--   (0234 capital_pays → city_pays); its last fallback (no harbour in the world can pay) is REFUSED lit. GRANT,
--   NPC_REFOUND: no writer exists; REFUSED lit.
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0237, LF-normalised; each asserted to occur exactly once and to
--    reverse to its pre-image; ACL / volatility / definer / config unchanged) ─────────────────────────────────────
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe a rolled-back sub-transaction, asserted) ───
--   (a) the hunks reverse; ACL / volatility / definer / config unmoved; the two new functions server-only; registry
--       unchanged; walls 0.
--   (b) DARK, BYTE FOR BYTE: a Dutch probe company founded at Lisbon sails 40 t to Funchal, docks, sells; then a bare
--       credit(FOUNDING) and a treasury_post(EARNINGS +) — run BEFORE the re-cut and AFTER it, from the same state
--       (the probe's (port, good) row locked for this transaction): flows, purse, ledger, fleet, orders, events, debts
--       and the sale's answer equal.
--   (c) LIT, THE GUARD: every minted kind refused at both writers (E_NO_NEW_GOLD); a negative minted post passes; a
--       non-minted kind passes; city_pays(FOUNDING) passes and puts byeharu.paid_by_city back (a bare credit after it is
--       refused again).
--   (d) LIT, NOTHING A PLAYER DOES IS REFUSED: a sign-up (cmd.found_house, Dutch: Amsterdam pays); a buy and a sell at
--       Amsterdam; a sail to Funchal docked by AN ARRIVALS RUN (tick_arrivals over a voyage moved to 2001, where no real
--       voyage, repair, hold, port time or waiting merchant is due) paying its dock fee, then a sale there, then the
--       next arrivals run waking her queued SAIL; a merchant founded (Lisbon pays) and gifted by the capital's pass,
--       and her donation; city_day three hours ahead over every harbour. No E_NO_NEW_GOLD, no error, no minted flow
--       but the capital-paid FOUNDING (−).
--   (e) THE SWITCH: refused with dark purses; on → flag, at = now(), total, one event, invested = Σ shares.paid on every
--       harbour (between the register's sums before and after the switch: nothing is locked); on again → nothing; off → the three knobs back exactly as
--       they were, a second event; no money moved by either.
--   No table that grows on production is counted or summed against a remembered figure; nothing is DELETEd from an
--   append-only table; no `set role`; tick_arrivals runs only over the year 2001; npc_tend_houses / tick_city are never
--   run; nothing reads the hour of day.
-- ROLLBACK (forward): restore the three OLD hunks below verbatim; drop the two functions and the two knobs.
-- VERSION: 0240 (0238 / 0239 are in flight elsewhere; the deploy renumbers).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.economy_closed()') is null
     or to_regprocedure('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)') is null
     or to_regprocedure('public.founding_credit(uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.port_call(uuid,uuid,uuid,timestamptz,timestamptz,uuid)') is null
     or to_regprocedure('public.port_time_wake(timestamptz,timestamptz,uuid)') is null then
    raise exception '0240 refuses: E1–E4b (0228, 0234, 0237) are not all in this world';
  end if;
  if public.economy_closed() then
    raise exception '0240 refuses: the economy is already closed — this file ships the switch, it does not light it';
  end if;
  if to_regprocedure('public.economy_close_switch(boolean)') is not null or to_regprocedure('public.mint_guard(text,bigint)') is not null then
    raise exception '0240 refuses: the switch or the guard already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0240(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0240 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.credit(uuid,text,bigint,uuid)'),
               ('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'),
               ('public.city_pays(uuid,uuid,text,bigint,uuid)')) f(fn);

create temp table before_0240 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select coalesce(max(f.id), 0) from public.treasury_flows f) as mark,
       (select count(*) from public.port_treasury t where t.invested is not null) as invested_rows,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis,
       (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR') as fnc,
       (select p.id from public.ports p where p.code = 'AMS' and p.kind = 'HARBOUR') as ams,
       (select g.id from public.goods g join public.ports p on p.code = 'FNC' and p.kind = 'HARBOUR'
         where g.bulk = 1 and not public.culture_refuses(p.culture, g.culture_mask) order by g.code limit 1) as good;

-- The dark probe's (port, good) row is held still for this transaction, so the two dark runs price the same market.
do $$
begin
  if exists (select 1 from before_0240 b where b.lis is null or b.fnc is null or b.ams is null or b.good is null) then
    raise exception '0240 self-assert FAIL: no Lisbon, Funchal, Amsterdam or probe good';
  end if;
  perform 1 from public.port_goods pg, before_0240 b where pg.port_id = b.fnc and pg.good_id = b.good for update;
end $$;

-- ── 1. THE PROBE'S TOOLS ────────────────────────────────────────────────────────────────────────
-- What a probe wrote since the mark: flows (port code, kind, ducats; probe kinds left out), and a company's purse,
-- ledger, fleet, orders, events (voyage ids left out) and debts.
create or replace function pg_temp.seen_0240(p_p uuid, p_f uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'flows', coalesce((select jsonb_agg(jsonb_build_array(p.code, f.kind, f.ducats) order by f.id)
                         from public.treasury_flows f join public.ports p on p.id = f.port_id
                        where f.id > (select b.mark from before_0240 b) and f.created_at = now() and f.kind <> 'PROBE_0240'), '[]'::jsonb),
    'purse', (select pl.ducats from public.players pl where pl.id = p_p),
    'ledger', coalesce((select jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.kind, l.ducats_delta, l.balance_after)
                          from public.ledger l where l.player_id = p_p and l.kind <> 'PROBE_0240'), '[]'::jsonb),
    'fleet', (select jsonb_build_array(f.status, p.code, f.ready_at, f.version)
                from public.fleets f left join public.ports p on p.id = f.port_id where f.id = p_f),
    'orders', coalesce((select jsonb_agg(jsonb_build_array(o.verb, o.status, o.error_code) order by o.seq)
                          from public.orders o where o.fleet_id = p_f), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_array(e.kind, e.payload - 'voyage_id' - 'eta') order by e.created_at, e.kind, e.payload::text)
                          from public.events e where e.player_id = p_p), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(jsonb_build_array(p.code, d.ducats) order by p.code)
                         from public.port_fee_debts d join public.ports p on p.id = d.port_id where d.player_id = p_p), '[]'::jsonb))
$$;

-- A company founded at Lisbon (p_nation), 1,000,000 of probe money, 40 t of the probe good at 25 aboard, on passage to
-- Funchal; Lisbon and Funchal with no reserve and Funchal 10,000,000 richer (its bid is whole). Answers {p, f, voyage}.
create or replace function pg_temp.voyager_0240(p_uid uuid, p_name text, p_nation text)
returns jsonb
language plpgsql
as $$
declare
  b       record;
  v_p     uuid;
  v_f     uuid;
  v_n     numeric;
  v_voy   uuid;
  v_course jsonb;
begin
  select * into b from before_0240;
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  v_p := public.new_house(p_uid, p_name, p_nation, 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p;
  perform public.credit(v_p, 'PROBE_0240', 1000000);
  v_n := public.fleet_load(v_f, (select g.code from public.goods g where g.id = b.good), 40, 25);
  if v_n <> 40 or public.fleet_stock_at_cost(v_f) <> 1000 then
    raise exception '0240 self-assert FAIL: the probe''s 40 t did not load (% loaded, worth %)', v_n, public.fleet_stock_at_cost(v_f);
  end if;
  update public.port_treasury set reserve = 0 where port_id in (b.lis, b.fnc);
  perform public.treasury_post(b.fnc, 'PROBE_0240', 10000000, null, null, true);
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(c.roadstead_lat, c.roadstead_lon))
    into v_course
    from public.sea_reaches a, public.sea_reaches c where a.port_id = b.lis and c.port_id = b.fnc;
  v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', b.fnc, 'path', v_course))->>'voyage_id')::uuid;
  if v_voy is null then
    raise exception '0240 self-assert FAIL: the probe did not sail for Funchal';
  end if;
  return jsonb_build_object('p', v_p, 'f', v_f, 'voyage', v_voy);
end $$;

-- THE DARK PROBE (economy open, purses lit): dock at Funchal 30 s ago, sell, then a bare FOUNDING credit and an EARNINGS
-- post. Rolled back; answers what it saw.
create or replace function pg_temp.dark_0240()
returns jsonb
language plpgsql
as $$
declare
  b     record;
  v     jsonb;
  v_p   uuid; v_f uuid;
  v_res jsonb;
begin
  select * into b from before_0240;
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';   -- a quiet passage: no lottery
    v := pg_temp.voyager_0240('00000000-0240-4000-8000-000000000001', 'Huis van de Proef 0240', 'NLD');
    v_p := (v->>'p')::uuid; v_f := (v->>'f')::uuid;
    update public.voyages vo
       set departed_at = vo.departed_at - (vo.eta - (now() - interval '30 seconds')), eta = now() - interval '30 seconds'
     where vo.id = (v->>'voyage')::uuid;
    perform voyage.settle(v_f, now());
    v_res := cmd.do_sell(v_f, jsonb_build_object('good', b.good));
    v_res := jsonb_build_object('sale', v_res,
                                'founding', public.credit(v_p, 'FOUNDING', 500),
                                'earnings_written', public.treasury_post(b.fnc, 'EARNINGS', 700, null, null) is not null);
    raise exception using errcode = 'ZY240', message = (v_res || jsonb_build_object('seen', pg_temp.seen_0240(v_p, v_f)))::text;
  exception when sqlstate 'ZY240' then
    return sqlerrm::jsonb;
  end;
end $$;

-- (b), the first half: the dark probe through the PRE-IMAGES
create temp table dark_old_0240 on commit drop as select pg_temp.dark_0240() as seen;

-- ── 2. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('economy_closed_at', 'null'::jsonb,
   '0240 (docs/CLOSED_ECONOMY.md §6): the instant public.economy_close_switch(true) closed the economy; null while open. One writer: the switch.'),
  ('economy_closed_total', 'null'::jsonb,
   '0240 (§6, §7): the world total (world.stats_now() total: players + merchants + cities + set aside) at that instant — the figure "world total flat" is judged against; null while open. One writer: the switch.');

-- ── 3. THE GUARD ────────────────────────────────────────────────────────────────────────────────
create function public.mint_guard(p_kind text, p_delta bigint)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0240 (docs/CLOSED_ECONOMY.md §0.2, §8 E7): NO NEW GOLD. THE one judge, asked by the two money writers (public.credit,
-- public.treasury_post) for a positive delta: while the economy is closed (and the purses lit — 0234's founding_credit
-- test), a MINTED kind (public.stats_flow_words.side = 'minted') is refused, E_NO_NEW_GOLD. Open: nothing, ever.
-- A city that pays (public.city_pays) is not asked: its credit is money moved, not made.
begin
  if coalesce(p_delta, 0) > 0
     and public.economy_closed()
     and public.city_treasury_on()
     and exists (select 1 from public.stats_flow_words w where w.kind = p_kind and w.side = 'minted') then
    perform cmd.refuse('E_NO_NEW_GOLD',
      format('the economy is closed: no %s is made from nothing (%s d.) — a city must pay it', p_kind, p_delta),
      cmd.figures(0, p_delta, 'ducats'));
  end if;
end $$;
comment on function public.mint_guard(text, bigint) is
  '0240: the closed economy''s guard — refuses a positive minted kind (stats_flow_words) while economy_closed. Asked by credit and treasury_post. Server-only.';
revoke all on function public.mint_guard(text, bigint) from public, anon, authenticated;

-- ── 4. THE HUNKS (each occurs exactly once in the live body) ─────────────────────────────────────
create temp table hunks_0240 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0240 values
('public.credit(uuid,text,bigint,uuid)', 1,
$h$  v_after := v_before + p_delta;
  if v_after < 0 then
$h$,
$h$  -- 0240 (E7, docs/CLOSED_ECONOMY.md §0.2): NO NEW GOLD — closed, a minted kind is refused here (public.mint_guard)
  -- unless a city paid it in this same act (public.city_pays sets byeharu.paid_by_city for its own credit only).
  if p_delta > 0 and coalesce(current_setting('byeharu.paid_by_city', true), '') <> 'on' then
    perform public.mint_guard(p_kind, p_delta);
  end if;
  v_after := v_before + p_delta;
  if v_after < 0 then
$h$),
('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)', 1,
$h$  insert into public.treasury_flows (port_id, kind, ducats, player_id, ref_event)
$h$,
$h$  -- 0240 (E7): NO NEW GOLD — closed, a city is never paid a minted kind (EARNINGS, SEED, …) from nothing.
  if p_delta > 0 then
    perform public.mint_guard(p_kind, p_delta);
  end if;
  insert into public.treasury_flows (port_id, kind, ducats, player_id, ref_event)
$h$),
('public.city_pays(uuid,uuid,text,bigint,uuid)', 1,
$h$begin
  if public.city_treasury_on() then
    perform 1 from public.players where id = p_player for update;
  end if;
  perform public.treasury_post(p_port, p_kind, -p_amount, p_player, p_event);
  return public.credit(p_player, p_kind, p_amount, p_event);
end $function$
$h$,
$h$declare
  v_prev  text;
  v_after bigint;
begin
  if public.city_treasury_on() then
    perform 1 from public.players where id = p_player for update;
  end if;
  -- 0240 (E7): when the city's purse really paid (treasury_post wrote its row), the house's credit is PAID BY A CITY —
  -- byeharu.paid_by_city 'on' for that one credit, then put back — so public.credit's guard lets a capital-paid
  -- FOUNDING through (0234 capital_pays) and nothing else. Nothing written by the city: the plain credit, as before.
  if public.treasury_post(p_port, p_kind, -p_amount, p_player, p_event) is null then
    return public.credit(p_player, p_kind, p_amount, p_event);
  end if;
  v_prev := current_setting('byeharu.paid_by_city', true);
  perform set_config('byeharu.paid_by_city', 'on', true);
  v_after := public.credit(p_player, p_kind, p_amount, p_event);
  perform set_config('byeharu.paid_by_city', coalesce(v_prev, ''), true);
  return v_after;
end $function$
$h$);

create or replace function pg_temp.recut_0240(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0240 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0240 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0240(v_def, h.old);
    if v_n <> 1 then
      raise exception '0240 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0240(fn) from defs_before_0240 order by fn;

-- ── 5. THE SWITCH ───────────────────────────────────────────────────────────────────────────────
create function public.economy_close_switch(p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0240 (docs/CLOSED_ECONOMY.md §6): THE one switch of the closed economy. Owner / service role only.
--   true:  refused while the city purses are dark (E_PURSES_DARK). Seeds port_treasury.invested = Σ city_shares.paid
--          where it is null (§3; a re-light keeps what E5 has rolled since). Records economy_closed_at = now() and
--          economy_closed_total = the world total this second (world.stats_now() `total`), flips economy_closed, and
--          writes ONE events row ECONOMY_SWITCH (no player: the world's own news).
--   false: economy_closed false, economy_closed_at / economy_closed_total null, ONE events row ECONOMY_SWITCH.
--          Money already moved stays where it is; `invested` stays (read by nothing while open).
--   Asked for what already is: {changed: false}, nothing written. No money moves either way.
-- The drift knobs of §6 are not this switch's: they ride with E6 (0240's header says why).
declare
  v_was    boolean := public.economy_closed();
  v_total  bigint;
  v_n      int := 0;
  v_inv    bigint;
  v_ev     uuid;
  v_at     jsonb;
  v_atotal jsonb;
begin
  if p_on is null then
    raise exception 'economy_close_switch(): say true (close) or false (open)';
  end if;
  if p_on = v_was then
    return jsonb_build_object('closed', v_was, 'changed', false);
  end if;
  v_total := (world.stats_now()->>'total')::bigint;
  if p_on then
    if not public.city_treasury_on() then
      perform cmd.refuse('E_PURSES_DARK',
        'the city purses are dark — light them (public.city_treasury_switch) before the economy is closed');
    end if;
    update public.port_treasury t
       set invested = coalesce((select sum(s.paid) from public.city_shares s where s.port_id = t.port_id), 0)
     where t.invested is null;
    get diagnostics v_n = row_count;
    select coalesce(sum(t.invested), 0) into v_inv from public.port_treasury t;
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    update public.world_config set value = to_jsonb(now()) where key = 'economy_closed_at';
    update public.world_config set value = coalesce(to_jsonb(v_total), 'null'::jsonb) where key = 'economy_closed_total';
    v_ev := public.emit_event(null, 'ECONOMY_SWITCH', jsonb_build_object(
              'closed', true, 'at', now(), 'world_total', v_total, 'invested_seeded', v_n, 'invested', v_inv));
  else
    v_at := public.wc('economy_closed_at');
    v_atotal := public.wc('economy_closed_total');
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    update public.world_config set value = 'null'::jsonb where key in ('economy_closed_at', 'economy_closed_total');
    v_ev := public.emit_event(null, 'ECONOMY_SWITCH', jsonb_build_object(
              'closed', false, 'at', now(), 'world_total', v_total, 'closed_at', v_at, 'total_at_close', v_atotal,
              'total_moved', case when jsonb_typeof(v_atotal) = 'number' and v_total is not null
                                  then v_total - (v_atotal #>> '{}')::bigint end));
  end if;
  return jsonb_build_object('closed', public.economy_closed(), 'changed', true, 'world_total', v_total,
                            'invested_seeded', v_n, 'event', v_ev);
end $$;
comment on function public.economy_close_switch(boolean) is
  '0240 (docs/CLOSED_ECONOMY.md §6): closes (true) or re-opens (false) the economy. Owner / service role only, by one select with the deploy note. Never granted to a client.';
revoke all on function public.economy_close_switch(boolean) from public, anon, authenticated;

-- ── 6. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0240-4000-8000-000000000002';
  c_t      constant timestamptz := '2001-01-01 00:00:00+00';   -- the probe voyage's year: nothing real is due then
  b        record;
  v_d record; v_h record; v_pp record; v_def text;
  v_new    jsonb;
  v_old    jsonb;
  v_kind   text;
  v_g      jsonb := '{}'::jsonb;
  v_l      jsonb := '{}'::jsonb;
  v_w      jsonb;
  v_err    jsonb := '[]'::jsonb;
  v_p      uuid; v_f uuid; v_m uuid;
  v_v      jsonb;
  v_res    jsonb;
  v_buy    uuid;
  v_back   jsonb;
  v_r1 jsonb; v_r2 jsonb; v_r3 jsonb;
  v_knobs  jsonb;
  v_minted text[] := array(select w.kind from public.stats_flow_words w where w.side = 'minted' order by w.kind);
begin
  select * into b from before_0240;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0240 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0240 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0240(v_def, v_h.new) <> 1 then
        raise exception '0240 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0240 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0240 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.mint_guard(text,bigint)'), ('public.economy_close_switch(boolean)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0240 self-assert FAIL: a client role can execute the guard or the switch';
  end if;
  if exists (select 1 from public.client_rpc_entry_points() e where e.function_name in ('economy_close_switch', 'mint_guard'))
     or (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0240 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0240 self-assert FAIL: a wall moved';
  end if;
  if v_minted <> array['EARNINGS', 'FOUNDING', 'GRANT', 'IMPORT_DEMAND', 'NPC_REFOUND', 'SEED'] then
    raise exception '0240 self-assert FAIL: the minted kinds are not E1''s six: %', v_minted;
  end if;

  -- (b) DARK, BYTE FOR BYTE: the same probe through the new bodies
  v_old := (select d.seen from dark_old_0240 d);
  v_new := pg_temp.dark_0240();
  if v_old is null or v_new is distinct from v_old
     or v_new->'seen'->'fleet'->>0 <> 'DOCKED' or v_new->'seen'->'fleet'->>1 <> 'FNC'
     or (v_new->'sale'->'sale'->>'qty')::numeric <> 40 or not (v_new->>'earnings_written')::boolean
     or not (v_new->'seen'->'flows' @> '[["FNC", "EARNINGS", 700]]'::jsonb)
     or not (v_new->'seen'->'ledger' @> jsonb_build_array(jsonb_build_array('FOUNDING', 500, (v_new->>'founding')::bigint))) then
    raise exception '0240 self-assert FAIL: dark, the docking, the sale, the bare FOUNDING and the EARNINGS post are not the pre-image''s byte for byte: new % old %', v_new, v_old;
  end if;

  -- (c) LIT, THE GUARD at both writers
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    update public.port_treasury set reserve = 0 where port_id in (b.lis, b.ams);
    perform public.treasury_post(b.lis, 'PROBE_0240', 1000000, null, null, true);
    perform public.treasury_post(b.ams, 'PROBE_0240', 1000000, null, null, true);
    v_p := public.new_house(null, 'Casa da Guarda 0240', 'PRT', 'LIS');
    foreach v_kind in array v_minted loop
      begin
        perform public.credit(v_p, v_kind, 1);
        v_g := v_g || jsonb_build_object('credit_' || v_kind, 'passed');
      exception when others then
        v_g := v_g || jsonb_build_object('credit_' || v_kind, split_part(sqlerrm, ':', 1));
      end;
      begin
        perform public.treasury_post(b.lis, v_kind, 1, null, null);
        v_g := v_g || jsonb_build_object('post_' || v_kind, 'passed');
      exception when others then
        v_g := v_g || jsonb_build_object('post_' || v_kind, split_part(sqlerrm, ':', 1));
      end;
      begin
        perform public.treasury_post(b.lis, v_kind, -1, null, null);
        perform public.credit(v_p, v_kind, -1);
        v_g := v_g || jsonb_build_object('minus_' || v_kind, 'passed');
      exception when others then
        v_g := v_g || jsonb_build_object('minus_' || v_kind, sqlerrm);
      end;
    end loop;
    begin
      perform public.credit(v_p, 'PROBE_0240', 1);
      perform public.treasury_post(b.lis, 'BUY', 1, v_p, null);
      v_g := v_g || jsonb_build_object('moved', 'passed');
    exception when others then
      v_g := v_g || jsonb_build_object('moved', sqlerrm);
    end;
    begin
      perform public.city_pays(b.lis, v_p, 'FOUNDING', 500, null);
      v_g := v_g || jsonb_build_object('city_pays', 'passed', 'after', coalesce(current_setting('byeharu.paid_by_city', true), ''));
    exception when others then
      v_g := v_g || jsonb_build_object('city_pays', sqlerrm);
    end;
    begin
      perform public.credit(v_p, 'FOUNDING', 1);
      v_g := v_g || jsonb_build_object('bare_after', 'passed');
    exception when others then
      v_g := v_g || jsonb_build_object('bare_after', split_part(sqlerrm, ':', 1));
    end;
    raise exception using errcode = 'ZX240', message = v_g::text;
  exception when sqlstate 'ZX240' then
    v_g := sqlerrm::jsonb;
  end;
  foreach v_kind in array v_minted loop
    if v_g->>('credit_' || v_kind) <> 'E_NO_NEW_GOLD' or v_g->>('post_' || v_kind) <> 'E_NO_NEW_GOLD'
       or v_g->>('minus_' || v_kind) <> 'passed' then
      raise exception '0240 self-assert FAIL: lit, the guard did not refuse new % at both writers (or refused a negative one): %', v_kind, v_g;
    end if;
  end loop;
  if v_g->>'moved' <> 'passed' or v_g->>'city_pays' <> 'passed' or v_g->>'after' <> '' or v_g->>'bare_after' <> 'E_NO_NEW_GOLD' then
    raise exception '0240 self-assert FAIL: lit, a moved kind or a city-paid FOUNDING was refused, or the setting was not put back: %', v_g;
  end if;

  -- (d) LIT, NOTHING A PLAYER DOES IS REFUSED
  begin
    update public.world_config set value = 'true'::jsonb
     where key in ('city_treasury_enabled', 'economy_closed', 'influence_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
    update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';
    update public.port_treasury set reserve = 0 where port_id in (b.lis, b.ams);
    perform public.treasury_post(b.lis, 'PROBE_0240', 1000000, null, null, true);
    perform public.treasury_post(b.ams, 'PROBE_0240', 1000000, null, null, true);

    -- d1 A SIGN-UP: a Dutch house, Amsterdam pays her starting money
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    begin
      v_res := cmd.found_house('Huis van het Slot 0240', 'NLD');
      v_l := v_l || jsonb_build_object('signup', v_res);
    exception when others then
      v_err := v_err || jsonb_build_array(jsonb_build_object('signup', sqlerrm));
    end;
    select pl.id into v_p from public.players pl where pl.auth_uid = c_uid;
    select f.id into v_f from public.fleets f where f.player_id = v_p;
    v_l := v_l || jsonb_build_object('signed', pg_temp.seen_0240(v_p, v_f));

    -- d2 A BUY AND A SELL at Amsterdam
    select g.id into v_buy from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = b.ams
      join public.ports p on p.id = b.ams
     where g.bulk <= 1 and pg.stock >= 10 and public.port_offers(b.ams, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
     order by g.code limit 1;
    begin
      v_l := v_l || jsonb_build_object('buy', cmd.do_buy(v_f, jsonb_build_object('good', v_buy, 'qty', 2)));
      v_l := v_l || jsonb_build_object('sell', cmd.do_sell(v_f, jsonb_build_object('good', v_buy)));
    exception when others then
      v_err := v_err || jsonb_build_array(jsonb_build_object('trade', sqlerrm));
    end;
    v_l := v_l || jsonb_build_object('traded', pg_temp.seen_0240(v_p, v_f));

    -- d3 A SAIL, DOCKED BY AN ARRIVALS RUN with its dock fee, a sale there, and the next run waking her queued SAIL
    begin
      v_v := pg_temp.voyager_0240('00000000-0240-4000-8000-000000000003', 'Huis van de Reis 0240', 'NLD');
      update public.voyages vo set departed_at = c_t - (vo.eta - vo.departed_at), eta = c_t where vo.id = (v_v->>'voyage')::uuid;
      select jsonb_build_array(jsonb_build_array(c.roadstead_lat, c.roadstead_lon), jsonb_build_array(a.roadstead_lat, a.roadstead_lon))
        into v_back from public.sea_reaches a, public.sea_reaches c where a.port_id = b.lis and c.port_id = b.fnc;
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args)
      values ((v_v->>'f')::uuid, (v_v->>'p')::uuid, 1, 'SAIL TO LIS', 'SAIL', jsonb_build_object('dest', b.lis, 'path', v_back));
      v_r1 := public.tick_arrivals(c_t + interval '30 seconds');
      v_l := v_l || jsonb_build_object('run1', v_r1, 'docked', pg_temp.seen_0240((v_v->>'p')::uuid, (v_v->>'f')::uuid));
      v_l := v_l || jsonb_build_object('sale_fnc', cmd.do_sell((v_v->>'f')::uuid, jsonb_build_object('good', b.good)));
      v_r2 := public.tick_arrivals(c_t + interval '61 seconds');
      v_l := v_l || jsonb_build_object('run2', v_r2, 'woken', pg_temp.seen_0240((v_v->>'p')::uuid, (v_v->>'f')::uuid));
    exception when others then
      v_err := v_err || jsonb_build_array(jsonb_build_object('voyage', sqlerrm));
    end;

    -- d4 A MERCHANT FOUNDED (Lisbon pays), GIFTED BY HER CAPITAL'S PASS, and her donation
    begin
      v_m := public.new_house(null, 'Casa do Dom 0240', 'PRT', 'LIS', p_ducats => 500, p_is_npc => true);
      insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
      values (v_m, (select coalesce(max(h.roster_ord), 0) + 1 from public.npc_houses h), 'prt',
              'A probe house of 0240, rolled back.', 'Mestre da Prova', b.lis, 5000, 0.1, '{}');
      insert into public.npc_fleets (fleet_id, player_id, roster_ord)
      select f.id, v_m, (select coalesce(max(n.roster_ord), 0) + 1 from public.npc_fleets n)
        from public.fleets f where f.player_id = v_m order by f.id limit 1;
      v_l := v_l || jsonb_build_object('gift', public.capital_gift_pass(now(), v_m));
      perform public.pay_city(v_m, b.lis, 'DONATION', 100);
      v_l := v_l || jsonb_build_object('merchant', pg_temp.seen_0240(v_m, null));
    exception when others then
      v_err := v_err || jsonb_build_array(jsonb_build_object('merchant', sqlerrm));
    end;

    -- d5 THE CITY DAY, three hours ahead, over every harbour
    begin
      perform public.city_day(now() + interval '3 hours');
      v_l := v_l || jsonb_build_object('city_day', 'ran',
                     'minted_in', (select coalesce(jsonb_agg(jsonb_build_array(p.code, f.kind, f.ducats) order by f.id), '[]'::jsonb)
                                     from public.treasury_flows f join public.ports p on p.id = f.port_id
                                    where f.id > b.mark and f.created_at = now() and f.ducats > 0
                                      and f.kind in (select w.kind from public.stats_flow_words w where w.side = 'minted')));
    exception when others then
      v_err := v_err || jsonb_build_array(jsonb_build_object('city_day', sqlerrm));
    end;
    raise exception using errcode = 'ZX240', message = jsonb_build_object('l', v_l, 'err', v_err)::text;
  exception when sqlstate 'ZX240' then
    v_res := sqlerrm::jsonb;
    v_l := v_res->'l'; v_err := v_res->'err';
  end;
  if v_err <> '[]'::jsonb then
    raise exception '0240 self-assert FAIL: lit, a player''s act was refused: %', v_err;
  end if;
  if not coalesce((v_l->'signup'->>'ok')::boolean, false)
     or (v_l->'signed'->>'purse')::bigint <> public.wc_int('starting_ducats')
     or (select count(*) from jsonb_array_elements(v_l->'signed'->'flows') e where e->>1 = 'FOUNDING' and (e->>2)::bigint = -public.wc_int('starting_ducats')) <> 1 then
    raise exception '0240 self-assert FAIL: lit, the sign-up was not paid by a city: % %', v_l->'signup', v_l->'signed';
  end if;
  if (v_l->'buy'->>'qty')::numeric <> 2 or (v_l->'sell'->>'qty')::numeric <> 2
     or exists (select 1 from jsonb_array_elements(v_l->'traded'->'flows') e
                 where e->>1 = any (v_minted) and (e->>2)::bigint > 0) then
    raise exception '0240 self-assert FAIL: lit, the buy and the sell at Amsterdam did not run clean: % % %', v_l->'buy', v_l->'sell', v_l->'traded';
  end if;
  if (v_l->'run1'->>'fleets_touched')::int < 1
     or v_l->'docked'->'fleet'->>0 <> 'DOCKED' or v_l->'docked'->'fleet'->>1 <> 'FNC'
     or (v_l->'docked'->'fleet'->>2)::timestamptz <> c_t + interval '60 seconds'
     or (select count(*) from jsonb_array_elements(v_l->'docked'->'flows') e where e->>0 = 'FNC' and e->>1 = 'PORT_FEE' and (e->>2)::bigint > 0) <> 1
     or v_l->'docked'->'orders' <> '[["SAIL", "pending", null]]'::jsonb
     or (v_l->'sale_fnc'->>'qty')::numeric <> 40
     or (v_l->'run2'->>'fleets_touched')::int < 1
     or v_l->'woken'->'orders' <> '[["SAIL", "done", null]]'::jsonb or v_l->'woken'->'fleet'->>0 <> 'SAILING' then
    raise exception '0240 self-assert FAIL: lit, the arrivals run did not dock her with her fee and wake her queued SAIL: %',
      jsonb_build_object('run1', v_l->'run1', 'docked', v_l->'docked', 'sale', v_l->'sale_fnc', 'run2', v_l->'run2', 'woken', v_l->'woken');
  end if;
  if (v_l->'gift'->>'gifted')::int <> 1 or (v_l->'gift'->>'gift_ducats')::bigint <> 5000
     or not (v_l->'merchant'->'flows' @> '[["LIS", "FOUNDING", -500], ["LIS", "CAPITAL_GIFT", -5000], ["LIS", "DONATION", 100]]'::jsonb)
     or (v_l->'merchant'->>'purse')::bigint <> 5400 then
    raise exception '0240 self-assert FAIL: lit, the merchant''s founding, gift or donation did not run through Lisbon: % %', v_l->'gift', v_l->'merchant';
  end if;
  if v_l->>'city_day' <> 'ran' or v_l->'minted_in' <> '[]'::jsonb then
    raise exception '0240 self-assert FAIL: lit, the city day minted: %', v_l->'minted_in';
  end if;

  -- (e) THE SWITCH
  v_knobs := (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'economy_closed_at', 'economy_closed_total'));
  begin
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    begin
      perform public.economy_close_switch(true);
      v_w := jsonb_build_object('dark_purses', 'passed');
    exception when others then
      v_w := jsonb_build_object('dark_purses', split_part(sqlerrm, ':', 1));
    end;
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    -- a probe holder of 12,345 paid in Funchal's docks, so the seed is seen to read the register
    v_m := public.new_house(null, 'Casa das Acções 0240', 'PRT', 'LIS');
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
    values (b.fnc, 'docks', v_m, 1, 12345, 0, 0);
    -- the register before and after the switch (a merchant may invest between two statements; nothing is locked):
    -- each harbour's seed must lie between the two sums
    v_knobs := v_knobs || jsonb_build_object('paid_before', (select jsonb_object_agg(t.port_id, coalesce((select sum(s.paid) from public.city_shares s where s.port_id = t.port_id), 0)) from public.port_treasury t));
    v_r1 := public.economy_close_switch(true);
    v_w := v_w || jsonb_build_object('on', v_r1,
      'flag', public.economy_closed(),
      'at_is_now', (public.wc('economy_closed_at') #>> '{}')::timestamptz = now(),
      'total', public.wc('economy_closed_total'),
      'event', (select jsonb_build_array(e.kind, e.player_id, e.payload->'closed', e.payload->'world_total')
                  from public.events e where e.id = (v_r1->>'event')::uuid),
      'fnc_seed', (select t.invested - coalesce((select sum(s.paid) from public.city_shares s where s.port_id = t.port_id and s.player_id <> v_m), 0)
                     from public.port_treasury t where t.port_id = b.fnc),
      'invested_off', (select count(*) from public.port_treasury t
                        cross join lateral (select (v_knobs->'paid_before'->>t.port_id::text)::numeric as a,
                                                   coalesce((select sum(s.paid) from public.city_shares s where s.port_id = t.port_id), 0) as z) x
                        where t.invested is null or t.invested not between least(x.a, x.z) and greatest(x.a, x.z)));
    begin
      perform public.credit((select pl.id from public.players pl order by pl.id limit 1), 'GRANT', 1);
      v_w := v_w || jsonb_build_object('guard_lit', 'passed');
    exception when others then
      v_w := v_w || jsonb_build_object('guard_lit', split_part(sqlerrm, ':', 1));
    end;
    v_r2 := public.economy_close_switch(true);
    v_r3 := public.economy_close_switch(false);
    v_w := v_w || jsonb_build_object('again', v_r2, 'off', v_r3,
      'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'economy_closed_at', 'economy_closed_total')),
      'event_off', (select jsonb_build_array(e.kind, e.player_id, e.payload->'closed', e.payload->'total_at_close')
                      from public.events e where e.id = (v_r3->>'event')::uuid),
      'flows', (select count(*) from public.treasury_flows f where f.id > b.mark and f.created_at = now() and f.kind <> 'PROBE_0240'));
    raise exception using errcode = 'ZX240', message = v_w::text;
  exception when sqlstate 'ZX240' then
    v_w := sqlerrm::jsonb;
  end;
  if v_w->>'dark_purses' <> 'E_PURSES_DARK'
     or not (v_w->'on'->>'changed')::boolean or not (v_w->'on'->>'closed')::boolean or not (v_w->>'flag')::boolean
     or not (v_w->>'at_is_now')::boolean or jsonb_typeof(v_w->'total') <> 'number'
     or v_w->'event'->>0 <> 'ECONOMY_SWITCH' or v_w->'event'->1 <> 'null'::jsonb or v_w->'event'->2 <> 'true'::jsonb
     or v_w->'event'->3 <> v_w->'total'
     or (v_w->>'invested_off')::int <> 0 or (v_w->>'fnc_seed')::bigint <> 12345 or (v_w->'on'->>'invested_seeded')::int <> (select count(*) from public.port_treasury)
     or v_w->>'guard_lit' <> 'E_NO_NEW_GOLD'
     or (v_w->'again'->>'changed')::boolean or v_w->'again'->'event' is not null
     or (v_w->'off'->>'closed')::boolean or not (v_w->'off'->>'changed')::boolean
     or v_w->'knobs' <> v_knobs - 'paid_before'
     or v_w->'event_off'->>0 <> 'ECONOMY_SWITCH' or v_w->'event_off'->2 <> 'false'::jsonb or v_w->'event_off'->3 <> v_w->'total'
     or (v_w->>'flows')::int <> 0 then
    raise exception '0240 self-assert FAIL: the switch did not close and re-open the economy as §6 says: % (knobs before %)', v_w, v_knobs - 'paid_before';
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.company_name like '% 0240')
     or exists (select 1 from public.treasury_flows f where f.id > b.mark and f.created_at = now())
     or exists (select 1 from public.events e where e.id in ((v_w->'on'->>'event')::uuid, (v_w->'off'->>'event')::uuid))
     or (select count(*) from public.port_treasury t where t.invested is not null) <> b.invested_rows
     or public.economy_closed() or public.wc('economy_closed_at') <> 'null'::jsonb
     or coalesce(current_setting('byeharu.paid_by_city', true), '') <> ''
     or coalesce(current_setting('request.jwt.claim.sub', true), '') <> '' then
    raise exception '0240 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0240 self-assert ok: THE ECONOMY IS CLOSED (not lit). credit, treasury_post, city_pays re-cut by one hunk each, each reversed, ACL unmoved; mint_guard and economy_close_switch server-only; registry unchanged; walls 0. DARK: a Dutch company docking at Funchal and selling 40 t, then a bare FOUNDING 500 and an EARNINGS 700 — new bodies = old bodies byte for byte (flows %). LIT, THE GUARD: % refused at credit and at treasury_post (E_NO_NEW_GOLD), negative posts and moved kinds pass, city_pays(FOUNDING) passes and the setting is put back. LIT, NOTHING REFUSED: sign-up (flows %), buy 2 and sell 2 at Amsterdam, an arrivals run in 2001 docked her at Funchal with her dock fee (flows %) and the next woke her SAIL, a merchant founded 500 + gifted 5,000 by Lisbon + donated 100, city_day over every harbour minted nothing. THE SWITCH: refused with dark purses; on — flag, at, total %, one ECONOMY_SWITCH event, invested = Σ shares.paid on % harbours; on again — nothing; off — knobs back, a second event; no money moved. Rolled back.',
    v_new->'seen'->'flows', v_minted, v_l->'signed'->'flows', v_l->'docked'->'flows', v_w->'total', v_w->'on'->'invested_seeded';
end $$;
