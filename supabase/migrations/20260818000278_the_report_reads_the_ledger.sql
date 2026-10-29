-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0278 — THE REPORT READS THE LEDGER  (R4, docs/COMMAND_REDESIGN.md §4: Report replaces Profit,
--        owner row 192 — every earning and loss by section and point, persisted, from the record)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
--   The owner, 2026-10-25: *"the profit tab on command, change it to report, saving all the earnings
--   and losses by sections, points, that is saved."* The record every coin moves through is the
--   append-only public.ledger (0004). 0177's world.books read it by day and kind only — no sections,
--   no points, and the Profit face printed a 7-day window. Report is the one read that answers the
--   whole question: by span ('day' | 'week' | 'all', in game days), by SECTION (the one kind->section
--   mapping of the design §4), and by POINT (the row's voyage, else its port, else "Earlier") — the
--   points 0277 filled at insert, so nothing is guessed at read time.
--
-- ── THE ONE RULE (decided by default; the owner may reverse it) ──────────────────────────────────
--   world.report(p_span text) is DERIVED PER READ and stores nothing (the 0014 rule). The span's day
--   boundaries are world.game_day's (0005) — the one clock; the report's week is the last 7 game days
--   (design §7.7: "Report spans = Day / Week / All, in game days"), NOT world.week_of's real week
--   (0275 — its presence is guarded below because this file's design names the two clock authorities
--   and this chain must carry both). Every row counts in exactly ONE section and ONE place:
--     section = the kind's section by the ONE mapping below; a kind not listed sits under "Other"
--               under its own name (nothing is dropped).
--     place   = the row's voyage when it has one (0277: the SAILING voyage, else the latest ARRIVED
--               one), else its port, else "earlier" (old rows, and event-less rows — WAGES, TAX — that
--               0277's rule leaves nameless). A dangling voyage_id (never for a player: compaction is
--               merchant-only) falls through to the port, so no row can vanish from the places.
--   FOUNDING is capital: excluded, as 0177 did. PROBE_* kinds exist only in rolled-back self-asserts.
--   The shape (design §4): {total, sections:[{id, word, ducats, lines:[{kind, ducats}]}],
--   places:[{kind:'port'|'voyage'|'earlier', …, ducats}], days:[{game_day, net}]}. The client prints
--   the served figures and maps id -> label for display only; the kind->section mapping lives HERE.
--
-- ── WHAT THIS FILE TOUCHES ────────────────────────────────────────────────────────────────────────
--   CREATES ONE function, world.report(text) — stable, security definer, search_path public, pg_temp;
--   registered (authenticated only). RE-CUTS ONE existing function BY HUNK: public.client_rpc_entry_points()
--   — the books row (0177) becomes the report row (one hunk, occurs once, reverses, ACL unmoved).
--   DROPS ONE function: world.books(int) (0177), the read this one replaces — after its registry row
--   is gone and its grants revoked. Its only callers are the desk's Profit face (replaced by
--   features/command/report/Report.tsx) and the Stats tab's Me face (moved to world.report in the
--   same PR), so nothing is left calling it. NO other existing function moves (md5-pinned below).
--   No writer, no knob, no switch, no backfill: the ledger's old rows read "Earlier" untouched.
--
-- ── WHAT IT SELF-ASSERTS (own probe company, rolled back whole; never a DELETE from an append-only
--    table; counts only its own rows) ──────────────────────────────────────────────────────────────
--   (a) the guard's facts hold: 0277's three point columns and its trigger, the two clocks, books
--       present, report absent;
--   (b) nothing else moved: the md5 of every other function in the four schemas (books excluded
--       before, report after), the function count, the registry count;
--   (c) THE PROBE, through the REAL verbs on a company founded at Lisbon: HIRE, PROVISION (FULL),
--       BUY (1 of a good Lisbon offers), SAIL (to the nearest harbour that offers the good and sails
--       — the real do_sail, retried over the three nearest), arrival shaped to the real state
--       (the SAILING voyage becomes the ARRIVED one; the fleet docks at the destination), SELL (1);
--       plus ONE backdated ledger row (kind PROBE_0278, delta 0, no event, created_at 8 game days
--       back — the old row's shape, harmless to the reconcile because its delta is 0):
--       (1) every event-backed row (HIRE, PROVISION, BUY, SELL) carries fleet_id; the trade rows
--           (BUY, SELL) also port_id; the BUY reads the dock (no voyage), the SELL the arrived
--           voyage; the event-less rows (WAGES, TAX, PROBE_0278) stay nameless — 0277's rule;
--       (2) total = the purse minus the FOUNDING (capital excluded, everything else in);
--       (3) the section sums equal the total and the place sums equal the section sums;
--       (4) every kind of the probe sits EXACTLY ONCE under its section with the ledger's own sum,
--           under the section the design's mapping names (Trade: SELL BUY TAX · Crew: WAGES HIRE ·
--           Supplies: PROVISION · Other: PROBE_0278); no FOUNDING line anywhere;
--       (5) the places: port LIS = buy + provision + hire; the voyage LIS->dest = the sell (departure
--           day = today); earlier = wages + tax (the backdated row's zero rides with them);
--       (6) day ⊆ week ⊆ all: days('day') = [today], days('week') = [today-6 .. today] (7),
--           days('all') = [today-8 .. today] (9, the backdated row's day) — and the three totals
--           agree (the backdated row is zero);
--       (7) a bogus span is refused (E_SPAN); the append-only positive control still bites (an UPDATE
--           of a probe row is refused);
--   (d) nothing of the probe survives the rollback (players, events, ledger rows, voyages);
--   (e) the registry: the report row is in, the books row is out, count unchanged, ACL unmoved;
--       world.books is gone (to_regprocedure null); world.report is stable + definer, granted to
--       authenticated and not anon; the three walls read zero.
--
-- ── ROLLBACK (forward; this file adds one read and drops one read) ───────────────────────────────
--   re-create world.books from 0177's body (grant execute to authenticated), re-run the registry
--   hunk reversed (the report row becomes the books row), drop function world.report(text);
--
-- VERSION: 0278 (prod head 0272 at writing; 0273–0277 land before this one, in number order).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.ledger') is null
     or to_regprocedure('public.credit(uuid,text,bigint,uuid)') is null then
    raise exception '0278 refuses: 0004 is not in this world';
  end if;
  if (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'ledger'
         and c.column_name in ('port_id', 'fleet_id', 'voyage_id')
         and c.is_nullable = 'YES' and c.data_type = 'uuid') <> 3 then
    raise exception '0278 refuses: 0277''s point columns are not in this world — the ledger names no points';
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.ledger'::regclass and t.tgname = 'ledger_points') then
    raise exception '0278 refuses: 0277''s ledger_points trigger is not in this world';
  end if;
  if to_regprocedure('world.game_day(timestamptz)') is null then
    raise exception '0278 refuses: the day clock (0005) is not in this world';
  end if;
  if to_regprocedure('world.week_of(timestamptz)') is null then
    raise exception '0278 refuses: 0275''s week clock is not in this world — the chain is behind this file';
  end if;
  if to_regprocedure('world.books(integer)') is null then
    raise exception '0278 refuses: world.books is not here to replace';
  end if;
  if to_regprocedure('world.report(text)') is not null then
    raise exception '0278 refuses: world.report already exists — this has been applied once';
  end if;
end $guard$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table before_0278 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid <> 'world.books(integer)'::regprocedure) as fns_md5,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as reg_def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') as reg_acl;

create or replace function pg_temp.occurs_0278(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.report(p_span text default 'all')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0278: THE REPORT (docs/COMMAND_REDESIGN.md §4, R4; owner row 192) — the caller's ledger, by span,
-- section and place, derived per read; writes nothing. Replaces world.books (0177), dropped here.
-- The span's day boundaries are world.game_day's (0005) — the one clock; the week is the last 7 game
-- days (design §7.7), not world.week_of's real week. The kind->section mapping below is the ONE
-- authority (the client maps id -> label for display only). Every row counts in exactly one section
-- and one place: its voyage when it has one (0277's fill), else its port, else "earlier".
declare
  v_player uuid := public.current_player_id();
  v_today  int  := world.game_day();
  v_lo     int;
  v_secs   bigint := public.wc_num('game_day_seconds')::bigint;
  v_out    jsonb;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  if p_span is null or p_span not in ('day', 'week', 'all') then
    raise exception 'E_SPAN: report takes day, week or all' using errcode = 'P0001';
  end if;
  v_lo := case p_span when 'day'  then v_today
                       when 'week' then v_today - 6
                       else null end;   -- 'all': no bound, no prefilter

  with map(kind, sid, word, ord) as (values
    ('SELL', 'trade', 'Trade', 1), ('BUY', 'trade', 'Trade', 2), ('TAX', 'trade', 'Trade', 3),
    ('WAGES', 'crew', 'Crew', 4), ('HIRE', 'crew', 'Crew', 5),
    ('PROVISION', 'supplies', 'Supplies', 6),
    ('REPAIR', 'repairs', 'Repairs', 7),
    ('INSURANCE', 'insurance', 'Insurance', 8), ('INSURANCE_PAID', 'insurance', 'Insurance', 9),
    ('SHARE', 'invest', 'Invest', 10), ('DIVIDEND', 'invest', 'Invest', 11), ('DONATION', 'invest', 'Invest', 12),
    ('BUILD', 'ships', 'Ships', 13),
    ('TUITION', 'other', 'Other', 14), ('TOW', 'other', 'Other', 15)
  ), rows as (
    -- FOUNDING is capital, not something the company made: excluded, as 0177 did. The coarse time
    -- bound for a bounded span keeps the read on the (player_id, created_at) index (0177's lesson);
    -- the whole-game-day cut is world.game_day's.
    select l.kind, l.ducats_delta as ducats, l.port_id, l.voyage_id,
           world.game_day(l.created_at) as day
      from public.ledger l
     where l.player_id = v_player
       and l.kind <> 'FOUNDING'
       and (v_lo is null
            or (l.created_at > now() - make_interval(secs => ((v_today - v_lo + 1) * v_secs)::double precision)
                and world.game_day(l.created_at) between v_lo and v_today))
  ), pointed as (
    -- the voyage behind each row, when there still is one (a dangling id — never for a player —
    -- reads null and the row falls through to its port, never out of the places)
    select r.*, v.origin_port_id, v.dest_port_id, world.game_day(v.departed_at) as voyage_day
      from rows r
      left join public.voyages v on v.id = r.voyage_id
  ), secs as (
    select coalesce(m.sid, 'other') as sid, coalesce(m.word, 'Other') as word,
           coalesce(m.ord, 99) as ord, sum(r.ducats) as ducats
      from rows r left join map m on m.kind = r.kind
     group by 1, 2, 3
  ), sec_lines as (
    select coalesce(m.sid, 'other') as sid, r.kind, sum(r.ducats) as ducats, min(coalesce(m.ord, 99)) as ord
      from rows r left join map m on m.kind = r.kind
     group by 1, 2
  ), secs_json as (
    select jsonb_agg(jsonb_build_object(
             'id', s.sid, 'word', s.word, 'ducats', s.ducats,
             'lines', coalesce((select jsonb_agg(jsonb_build_object('kind', l.kind, 'ducats', l.ducats)
                                                    order by l.ord, l.kind)
                                  from sec_lines l where l.sid = s.sid), '[]'::jsonb))
           order by s.ord, s.sid) as sections
      from secs s
  ), places_json as (
    select coalesce(
             (select jsonb_agg(t.x order by (t.x->>'ducats')::bigint desc, (t.x->>'kind')::text)
                from (
                  -- the voyage the money belonged to (0277: the sailing voyage, else the latest arrived)
                  select jsonb_build_object('kind', 'voyage', 'from', fp.code, 'to', tp.code,
                                            'game_day', r.voyage_day, 'ducats', sum(r.ducats)) as x
                    from pointed r
                    join public.ports fp on fp.id = r.origin_port_id
                    join public.ports tp on tp.id = r.dest_port_id
                   where r.origin_port_id is not null
                   group by r.voyage_id, r.voyage_day, fp.code, tp.code
                  union all
                  -- money at a port no voyage can call its own (before her first voyage)
                  select jsonb_build_object('kind', 'port', 'code', p.code, 'name', p.name,
                                            'ducats', sum(r.ducats))
                    from pointed r
                    join public.ports p on p.id = r.port_id
                   where r.origin_port_id is null and r.port_id is not null
                   group by p.id, p.code, p.name
                  union all
                  -- old rows and event-less rows (WAGES, TAX): no point names them
                  select jsonb_build_object('kind', 'earlier', 'ducats', sum(r.ducats))
                    from pointed r
                   where r.origin_port_id is null and r.port_id is null
                   having count(*) > 0
                ) t), '[]'::jsonb) as places
  ), span_lo as (
    select case when v_lo is not null then v_lo
                else coalesce((select min(r.day) from rows r), v_today + 1) end as lo
  ), days as (
    select d.day, coalesce(sum(r.ducats), 0) as net
      from span_lo s, generate_series(s.lo, v_today) d(day)
      left join rows r on r.day = d.day
     group by d.day
  ), days_json as (
    select jsonb_agg(jsonb_build_object('game_day', d.day, 'net', d.net) order by d.day) as days
      from days d
  )
  select jsonb_build_object(
           'total', coalesce((select sum(r.ducats) from rows r), 0),
           'sections', coalesce((select sections from secs_json), '[]'::jsonb),
           'places', (select places from places_json),
           'days', coalesce((select days from days_json), '[]'::jsonb))
    into v_out;
  return v_out;
end $$;

comment on function world.report(text) is
  '0278: THE REPORT (docs/COMMAND_REDESIGN.md §4, R4; owner row 192) — the caller''s ledger by span '
  '(''day'' | ''week'' | ''all'', in game days via world.game_day), section (the one kind->section '
  'mapping of the design) and place (the row''s voyage, else its port, else "Earlier"). Derived per '
  'read, stores nothing; FOUNDING excluded (capital). Replaces world.books (0177). Registered.';
revoke all on function world.report(text) from public, anon, authenticated;
grant execute on function world.report(text) to authenticated;

-- ── 2. THE REGISTRY (one hunk: the books row becomes the report row; reverses; ACL unchanged) ───
do $$
declare
  b     record;
  v_old text := $h$      -- 0177: the books — the ledger by game day and kind (docs/COMMAND_DESK.md §3.8, D7).
      ('world',       'books',                 'int')
$h$;
  v_new text := $h$      -- 0278: the report — the ledger by span, section and place (docs/COMMAND_REDESIGN.md §4, R4).
      ('world',       'report',                'text')
$h$;
  v_rev text;
begin
  select * into b from before_0278;
  if pg_temp.occurs_0278(b.reg_def, v_old) <> 1 then
    raise exception '0278 self-assert FAIL: the registry''s books row occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0278(b.reg_def, v_old);
  end if;
  execute replace(b.reg_def, v_old, v_new);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0278(v_rev, v_new) <> 1 or replace(v_rev, v_new, v_old) <> b.reg_def then
    raise exception '0278 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.reg_acl then
    raise exception '0278 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 3. THE OLD READ LEAVES ─────────────────────────────────────────────────────────────────────
-- world.books (0177) is replaced by world.report above; no caller is left (Profit.tsx is replaced
-- and the Stats tab's Me face moves to world.report in the same PR). Grants go with the drop.
revoke all on function world.books(int) from public, anon, authenticated;
drop function world.books(int);

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid   constant uuid := '00000000-0278-4000-8000-000000000001';
  c_nil   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_before record;
  v_p      uuid;
  v_f      uuid;
  v_lis    uuid;
  v_g      uuid;
  v_code   text;
  v_dest   uuid;
  v_dest_code text;
  v_voy    uuid;
  v_dests  record;
  f_sailed boolean := false;
  v_buy_port uuid;
  v_buy_voy  uuid;
  v_sell_port uuid;
  v_sell_voy  uuid;
  v_rday   jsonb;
  v_rweek  jsonb;
  v_rall   jsonb;
  v_purse  bigint;
  v_found  bigint;
  v_sec    bigint;
  v_pla    bigint;
  v_today  int;
  v_n      int;
  v_lines  int;
  v_kinds  int;
  v_buy    bigint := 0;
  v_sell   bigint := 0;
  v_prov   bigint := 0;
  v_hire   bigint := 0;
  v_wages  bigint := 0;
  v_tax    bigint := 0;
  r        record;
  f_append boolean := false;
  f_span   boolean := false;
begin
  select * into v_before from before_0278;

  begin
    v_p := public.new_house(c_uid, 'Casa do Relatório 0278', 'PRT', 'LIS');
    select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_p;

    -- a good Lisbon offers, with stock, the probe's culture accepts (0224's pick, ordered — never a lottery)
    select pg.good_id, g.code into v_g, v_code
      from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
     where p.code = 'LIS' and pg.stock > 0 and not public.culture_refuses(p.culture, g.culture_mask)
       and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
     order by g.code limit 1;
    if v_g is null then
      raise exception '0278 self-assert FAIL: Lisbon offers no good with stock for the probe to trade';
    end if;

    -- THE REAL VERBS, in a player's order: crew (the new barca is laid down uncrewed), stores, buy,
    -- sail, sell. Each money verb books through public.credit — the one mover — and its event names
    -- the fleet, so 0277's trigger fills the points for free.
    perform cmd.do_hire(v_f, jsonb_build_object('count',
      (select c.crew_max from public.ship_classes c join public.ships s on s.class_id = c.id
        where s.fleet_id = v_f order by s.id limit 1)));
    perform cmd.do_provision(v_f, '{"mode": "FULL"}'::jsonb);
    perform cmd.do_buy(v_f, jsonb_build_object('good', v_g, 'qty', 1));

    -- SAIL to the nearest harbour that offers the good and takes its culture; the straight line is
    -- the server's to verify, so a refused candidate is tried against the next (do_sail writes
    -- nothing before it accepts — every refusal is a gate).
    for v_dests in
      select p.id as pid, p.code as pcode
        from public.sea_reaches sr
        join public.ports p on sr.reaches ? p.code
       where sr.port_id = v_lis and p.kind = 'HARBOUR' and p.id <> v_lis
         and exists (select 1 from public.port_goods pg2 where pg2.port_id = p.id and pg2.good_id = v_g)
         and not public.culture_refuses(p.culture, (select g2.culture_mask from public.goods g2 where g2.id = v_g))
         and exists (select 1 from public.port_offered_goods(p.id) o where o.good_id = v_g)
       order by (sr.reaches->>p.code)::numeric asc limit 3
    loop
      begin
        perform cmd.do_sail(v_f, jsonb_build_object('dest', v_dests.pid));
        v_dest := v_dests.pid;
        v_dest_code := v_dests.pcode;
        f_sailed := true;
        exit;
      exception when others then
        null;   -- this candidate refused the sail; the next may pass
      end;
    end loop;
    if not f_sailed then
      raise exception '0278 self-assert FAIL: no near harbour sails from Lisbon for the probe good %', v_code;
    end if;

    -- THE ARRIVAL, shaped to the real state (0277's probe pattern): the sailing voyage she is on
    -- becomes the arrived one, and she lies docked at the destination.
    select v.id into v_voy from public.voyages v
     where v.fleet_id = v_f and v.status = 'SAILING' order by v.departed_at desc limit 1;
    if v_voy is null then
      raise exception '0278 self-assert FAIL: the sail left no voyage';
    end if;
    update public.voyages set status = 'ARRIVED', eta = now() - interval '1 day' where id = v_voy;
    update public.fleets set status = 'DOCKED', port_id = v_dest where id = v_f;

    perform cmd.do_sell(v_f, jsonb_build_object('good', v_g, 'qty', 1));

    -- THE OLD ROW'S SHAPE, 8 game days back: no event, points null (0277's rule leaves it), delta 0
    -- so the purse and the ledger still reconcile. It exists to prove day ⊂ week ⊂ all, and it reads
    -- "Earlier".
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
    values (v_p, 'PROBE_0278', 0, (select pl.ducats from public.players pl where pl.id = v_p),
            null, now() - make_interval(secs => (8 * public.wc_num('game_day_seconds'))::double precision));

    -- (1) THE POINTS, row by row (0277's rule, re-read through the real verbs)
    if exists (select 1 from public.ledger l
                where l.player_id = v_p and l.kind in ('HIRE', 'PROVISION', 'BUY', 'SELL')
                  and l.fleet_id is null) then
      raise exception '0278 self-assert FAIL: an event-backed row lost its fleet';
    end if;
    if exists (select 1 from public.ledger l
                where l.player_id = v_p and l.kind in ('BUY', 'SELL') and l.port_id is null) then
      raise exception '0278 self-assert FAIL: a trade row lost its port';
    end if;
    select l.port_id, l.voyage_id into v_buy_port, v_buy_voy from public.ledger l
     where l.player_id = v_p and l.kind = 'BUY';
    if v_buy_port is distinct from v_lis or v_buy_voy is not null then
      raise exception '0278 self-assert FAIL: the buy reads port % voyage %, not the dock with no voyage', v_buy_port, v_buy_voy;
    end if;
    select l.port_id, l.voyage_id into v_sell_port, v_sell_voy from public.ledger l
     where l.player_id = v_p and l.kind = 'SELL';
    if v_sell_port is distinct from v_dest or v_sell_voy is distinct from v_voy then
      raise exception '0278 self-assert FAIL: the sell reads port % voyage %, not the dock and the arrived voyage %', v_sell_port, v_sell_voy, v_voy;
    end if;
    if exists (select 1 from public.ledger l
                where l.player_id = v_p and l.kind in ('WAGES', 'TAX', 'PROBE_0278')
                  and (l.port_id is not null or l.fleet_id is not null or l.voyage_id is not null)) then
      raise exception '0278 self-assert FAIL: an event-less row was given a point';
    end if;

    -- THE READS, as the probe company
    perform cmd.assume_identity(c_uid);
    v_rday  := world.report('day');
    v_rweek := world.report('week');
    v_rall  := world.report('all');
    perform cmd.assume_identity(c_nil);

    v_today := world.game_day();
    v_purse := (select ducats from public.players where id = v_p);
    v_found := (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'FOUNDING');
    select coalesce(sum(l.ducats_delta) filter (where l.kind = 'BUY'), 0)::bigint,
           coalesce(sum(l.ducats_delta) filter (where l.kind = 'SELL'), 0)::bigint,
           coalesce(sum(l.ducats_delta) filter (where l.kind = 'PROVISION'), 0)::bigint,
           coalesce(sum(l.ducats_delta) filter (where l.kind = 'HIRE'), 0)::bigint,
           coalesce(sum(l.ducats_delta) filter (where l.kind = 'WAGES'), 0)::bigint,
           coalesce(sum(l.ducats_delta) filter (where l.kind = 'TAX'), 0)::bigint
      into v_buy, v_sell, v_prov, v_hire, v_wages, v_tax
      from public.ledger l where l.player_id = v_p;

    -- (2) THE TOTAL IS THE PURSE MINUS THE CAPITAL — FOUNDING excluded, everything else in
    if (v_rall->>'total')::bigint <> v_purse - v_found then
      raise exception '0278 self-assert FAIL: the total reads %, the purse less the founding is %', v_rall->>'total', v_purse - v_found;
    end if;

    -- (3) THE SECTION SUMS EQUAL THE TOTAL, THE PLACE SUMS EQUAL THE SECTION SUMS
    select coalesce(sum((s->>'ducats')::bigint), 0) into v_sec from jsonb_array_elements(v_rall->'sections') s;
    select coalesce(sum((p->>'ducats')::bigint), 0) into v_pla from jsonb_array_elements(v_rall->'places') p;
    if v_sec <> v_purse - v_found then
      raise exception '0278 self-assert FAIL: the section sums read %, the total %', v_sec, v_purse - v_found;
    end if;
    if v_pla <> v_purse - v_found then
      raise exception '0278 self-assert FAIL: the place sums read %, the section sums %', v_pla, v_sec;
    end if;

    -- (4) EVERY KIND SITS EXACTLY ONCE UNDER ITS SECTION, WITH THE LEDGER'S OWN SUM, UNDER THE
    --     SECTION THE DESIGN'S MAPPING NAMES — nothing dropped, nothing doubled, no FOUNDING line
    select count(*) into v_lines from jsonb_array_elements(v_rall->'sections') s, jsonb_array_elements(s->'lines') x;
    select count(*) into v_kinds from (select distinct l.kind from public.ledger l
                                        where l.player_id = v_p and l.kind <> 'FOUNDING') k;
    if v_lines <> v_kinds then
      raise exception '0278 self-assert FAIL: % lines for % kinds', v_lines, v_kinds;
    end if;
    if exists (select 1 from jsonb_array_elements(v_rall->'sections') s, jsonb_array_elements(s->'lines') x
                where x->>'kind' = 'FOUNDING') then
      raise exception '0278 self-assert FAIL: the founding capital reads as a line';
    end if;
    for r in select l.kind, coalesce(sum(l.ducats_delta), 0)::bigint as s
             from public.ledger l where l.player_id = v_p and l.kind <> 'FOUNDING'
             group by l.kind loop
      select count(*) into v_n from jsonb_array_elements(v_rall->'sections') s,
           jsonb_array_elements(s->'lines') x
       where x->>'kind' = r.kind and (x->>'ducats')::bigint = r.s;
      if v_n <> 1 then
        raise exception '0278 self-assert FAIL: kind % is not exactly once under its section with the ledger''s sum %', r.kind, r.s;
      end if;
      if (select s->>'id' from jsonb_array_elements(v_rall->'sections') s,
              jsonb_array_elements(s->'lines') x where x->>'kind' = r.kind)
         <> case r.kind
              when 'SELL' then 'trade' when 'BUY' then 'trade' when 'TAX' then 'trade'
              when 'WAGES' then 'crew' when 'HIRE' then 'crew'
              when 'PROVISION' then 'supplies'
              else 'other' end then
        raise exception '0278 self-assert FAIL: kind % sits under the wrong section', r.kind;
      end if;
    end loop;

    -- (5) THE PLACES, each under its point
    if not exists (select 1 from jsonb_array_elements(v_rall->'places') p
                    where p->>'kind' = 'port' and p->>'code' = 'LIS'
                      and (p->>'ducats')::bigint = v_buy + v_prov + v_hire) then
      raise exception '0278 self-assert FAIL: no port LIS place reads buy % + provision % + hire %', v_buy, v_prov, v_hire;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_rall->'places') p
                    where p->>'kind' = 'voyage' and p->>'from' = 'LIS' and p->>'to' = v_dest_code
                      and (p->>'game_day')::int = v_today and (p->>'ducats')::bigint = v_sell) then
      raise exception '0278 self-assert FAIL: no voyage LIS->% of day % reads the sell''s %', v_dest_code, v_today, v_sell;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_rall->'places') p
                    where p->>'kind' = 'earlier' and (p->>'ducats')::bigint = v_wages + v_tax) then
      raise exception '0278 self-assert FAIL: no earlier place reads wages % + tax %', v_wages, v_tax;
    end if;

    -- (6) day ⊆ week ⊆ all — in the days and in the totals (the backdated row is zero)
    if jsonb_array_length(v_rday->'days') <> 1
       or ((v_rday->'days')->0->>'game_day')::int <> v_today
       or ((v_rday->'days')->0->>'net')::bigint <> (v_rday->>'total')::bigint then
      raise exception '0278 self-assert FAIL: the day span reads %, not today''s one day', v_rday->'days';
    end if;
    if jsonb_array_length(v_rweek->'days') <> 7
       or ((v_rweek->'days')->0->>'game_day')::int <> v_today - 6
       or ((v_rweek->'days')->6->>'game_day')::int <> v_today then
      raise exception '0278 self-assert FAIL: the week span is not the last 7 game days: %', v_rweek->'days';
    end if;
    if jsonb_array_length(v_rall->'days') <> 9
       or ((v_rall->'days')->0->>'game_day')::int <> v_today - 8
       or ((v_rall->'days')->8->>'game_day')::int <> v_today then
      raise exception '0278 self-assert FAIL: the all span does not run from the backdated row''s day: %', v_rall->'days';
    end if;
    if (v_rday->>'total')::bigint <> (v_rweek->>'total')::bigint
       or (v_rweek->>'total')::bigint <> (v_rall->>'total')::bigint then
      raise exception '0278 self-assert FAIL: the spans'' totals disagree: day % / week % / all %',
        v_rday->>'total', v_rweek->>'total', v_rall->>'total';
    end if;

    -- (7) A BOGUS SPAN IS REFUSED; THE APPEND-ONLY BITE STILL BITES (positive controls)
    begin
      perform world.report('bogus');
    exception when others then
      f_span := sqlerrm like 'E_SPAN%';
    end;
    if not f_span then
      raise exception '0278 self-assert FAIL: a bogus span was not refused with E_SPAN';
    end if;
    begin
      update public.ledger set balance_after = balance_after where player_id = v_p and kind = 'BUY';
    exception when others then
      f_append := true;
    end;
    if not f_append then
      raise exception '0278 self-assert FAIL: an UPDATE of a ledger row was accepted — the append-only bite is gone';
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- the subtransaction is gone; the findings survive (plpgsql variables are not transactional)
  if exists (select 1 from public.players where id = v_p)
     or exists (select 1 from public.ledger where kind = 'PROBE_0278')
     or exists (select 1 from public.voyages where id = v_voy) then
    raise exception '0278 self-assert FAIL: the probe left rows behind';
  end if;

  -- (b) NOTHING ELSE MOVED: every other function in the four schemas, by md5, the count, the registry
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> 'world.report(text)'::regprocedure) is distinct from v_before.fns_md5
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_before.fns then
    raise exception '0278 self-assert FAIL: a function moved, or the count is not books-out report-in';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0278 self-assert FAIL: the registry count moved';
  end if;

  -- (e) THE REGISTRY AND THE WALLS: the report row is in, the books row is out; books is dropped;
  --     report is stable + definer, authenticated only; the three walls read zero
  if not exists (select 1 from public.client_rpc_entry_points() e where e.fn = 'world.report(text)'::regprocedure)
     or exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'books') then
    raise exception '0278 self-assert FAIL: the registry does not hold the report and only the report';
  end if;
  if to_regprocedure('world.books(integer)') is not null then
    raise exception '0278 self-assert FAIL: world.books survived its drop';
  end if;
  if not has_function_privilege('authenticated', 'world.report(text)', 'execute')
     or has_function_privilege('anon', 'world.report(text)', 'execute') then
    raise exception '0278 self-assert FAIL: the grant wall moved';
  end if;
  if (select p.provolatile::text from pg_proc p where p.oid = 'world.report(text)'::regprocedure) <> 's'
     or (select p.prosecdef from pg_proc p where p.oid = 'world.report(text)'::regprocedure) is not true then
    raise exception '0278 self-assert FAIL: world.report is not a stable definer read';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0278 self-assert FAIL: the walls moved';
  end if;

  raise notice '0278 self-assert ok: THE REPORT READS THE LEDGER. world.report (registered; authenticated only; stable definer; stores nothing): a probe company at Lisbon hired, provisioned, bought, sailed and sold through the real verbs — every event-backed row carries its fleet, the trade rows their port, the sell the arrived voyage, the event-less rows stay nameless; the total is the purse less the founding (capital excluded); the section sums equal the total, the place sums equal the section sums; every kind sits exactly once under the design''s section with the ledger''s own sum; the places read port LIS = buy % + provision % + hire %, voyage LIS->% day % = sell %, earlier = wages % + tax %; day ⊂ week ⊂ all (1 / 7 / 9 days, totals agree); a bogus span refused; the append-only bite still bites; the backdated row read "Earlier". world.books dropped (no caller left); the registry holds the report in the books'' place, count unchanged; every other function in the four schemas unmoved by md5; the walls read zero; nothing left behind.',
    v_buy, v_prov, v_hire, v_dest_code, v_today, v_sell, v_wages, v_tax;
end $$;
