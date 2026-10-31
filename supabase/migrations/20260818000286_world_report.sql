-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0286 — THE REPORT  (R4: Report replaces Profit; owner rows 192 and 244 — "do 2, the report")
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
--   docs/COMMAND_REDESIGN.md §4 (written by the owner's order) and §5 (its screens): the Profit
--   face becomes Report — every earning and loss, by SECTION (trade, crew, supplies, repairs,
--   insurance, invest, ships, other) and by POINT (port, voyage), over a span of game days. The
--   design is the brief; this file is its server half.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   world.report(p_span text) — NEW, the client's one read (registered; authenticated only).
--   p_span is 'day' | 'week' | 'all', measured in GAME DAYS on the one clock world.game_day:
--     day  = today's game day;
--     week = the last SEVEN game days, today − 6 .. today (§7 item 7: "in game days" — NOT 0275's
--            real-time week key world.week_of, which is a different clock and stays the city book's);
--     all  = every row the company has.
--   It is DERIVED from the append-only public.ledger per read (the 0014 rule) and stores nothing.
--
--   SECTIONS, by ledger kind, exactly §4's table (id → client words; the line words ship beside
--   each kind so an unknown kind is never dropped):
--     trade      SELL, BUY, TAX (the profit tax), PORT_FEE (the city-visit fee — see below)
--     crew       WAGES, HIRE
--     supplies   PROVISION
--     repairs    REPAIR
--     insurance  INSURANCE (paid), INSURANCE_PAID (received)
--     invest     SHARE, DIVIDEND, DONATION
--     ships      BUILD
--     other      TUITION, TOW, and EVERY other kind under its own name (initcap fallback)
--   FOUNDING is a company's starting CAPITAL, not something it made: left out, as 0177 does.
--   PROBE_% kinds exist only in rolled-back self-asserts: never served.
--   PORT FEES: the design (§4, §7 item 8) said the ledger had no fee kind and fees sat inside SELL's
--   proceeds. At head 0285 that is stale: the city-visit fee writes a real PORT_FEE kind (35,870 rows
--   on prod when this file was written). Report keeps fees INSIDE Trade, where the design puts them —
--   PORT_FEE is part of Trade's figure, never a section or a place of its own; its line keeps the kind
--   so nothing is dropped and Trade stays the sum of its lines. No figure is invented.
--
--   POINTS, using 0284's three columns (port_id, fleet_id, voyage_id), form a PARTITION so the
--   place sums equal the section sums:
--     · a PORT when the row names one (she was docked — 0284 fills the port from the fleet's own
--       dock, so even a just-arrived voyage reads its port here);
--     · else a VOYAGE when the row names one (she was at sea): the voyage's from/to codes and its
--       departure game day;
--     · else EARLIER — every row with no point: the pre-0284 history (append-only; no backfill),
--       and the new rows whose event names no fleet (TAX, WAGES, DONATION, SHARE, DIVIDEND,
--       TUITION) or has no event at all. Earlier is always LAST.
--   A row that names BOTH a port and a voyage is counted once, under the PORT (where she was).
--   A voyage id whose row is gone (the compactor deletes NPC history) reads Earlier — never a guess.
--
--   DAYS: one bar per game day, zero-filled — day: 1 entry; week: 7, oldest first; all: every day
--   from the earliest included row to today. A day with no money moved is a true zero, not invented.
--
-- ── WHAT MOVED (0177's world.books RETIRED) ─────────────────────────────────────────────────────
--   world.report REPLACES world.books (0177) as the desk's ledger read. This file:
--     · removes 0177's registry row and appends world.report's (the registry count is unchanged);
--     · REVOKES the authenticated grant on world.books — the client door is retired;
--     · KEEPS the world.books body. It has one remaining caller: frozen 0232's self-assert, which
--       times world.books(7) as the migration OWNER during a from-zero apply (0232:1236). Dropping
--       the function would make the chain un-appliable from zero, and an applied file is history
--       (never edited). The owner-run call is not a client door: authenticated holds no grant.
--   The client's only callers were the desk's Profit face (replaced by Report) and Stats › Me's
--   week bars (re-pointed to world.report('week') in the same change).
--
-- ── THE GUARD AND THE PROOF ─────────────────────────────────────────────────────────────────────
--   The self-assert runs on its OWN rolled-back probe, as 0177's did: a throwaway house and fleet,
--   a planted ledger history spanning two ports and a voyage, and rows at the exact game-day
--   boundaries. It asserts:
--     (a) the read's shape: jsonb, STABLE, SECURITY DEFINER, search_path public/pg_temp; the
--         registry row present and books' row gone; authenticated can execute report and cannot
--         execute books; anon can execute neither;
--     (b) nothing else moved: every other function in public/cmd/world/voyage, by md5; the registry
--         count unchanged; the registry's ACL unmoved; the two hunks reverse to the pre-image;
--     (c) the locked walls: 0 client write grants, 0 client executable writers, 0 caller-evaluated;
--     (d) the report, on the probe's own rows only:
--         · every section's sum and each line's sum (Trade 200, Crew −50, Supplies −70,
--           Repairs −40, Insurance +210, Invest −360, Ships −1000, Other −50 → total −1,160),
--           with the city-visit PORT_FEE line inside Trade (never a section or place of its own);
--         · the places partition (LIS −760, FNC −190, the voyage +300 with codes and departure
--           day, Earlier −510 last) and places sum = sections sum;
--         · the span boundary on the game-day clock (a row 1 s before today is outside Day; a row
--           at the exact start of today−6 is inside Week; at the exact start of today−7 is outside
--           Week but inside All) and the day/week/all totals (−1,160 / −827 / −50) and day axes
--           (1 / 7 / 31 zero-filled entries, each axis summing to its total);
--         · FOUNDING and PROBE_0286 never appear; an unlisted kind appears under its own name in
--           Other; a row with both a port and a voyage counts once, under the port;
--         · an EMPTY report: total 0, eight empty sections, no places, day axis [today 0],
--           week axis 7 zeros, all axis empty; an unknown span is refused;
--     (e) the probe rolls back whole: no player, voyage or ledger row survives.
--   The selections count nothing live: every row read is the probe's own (player id, its voyage
--   id, its PROBE_0286 kind). Clean-up is by rollback — this file never DELETEs from the ledger.
--
-- ── ROLLBACK (forward; this file is additive apart from the registry and one grant) ─────────────
--   grant execute on function world.books(int) to authenticated;
--   drop function world.report(text);
--   reverse the registry's two hunks (books back in, report out).
--
-- VERSION: 0286 — prod head 20260818000285 when written (2026-10-31).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.report(text)') is not null then
    raise exception '0286 refuses: world.report(text) already exists — this has been applied once';
  end if;
  if to_regprocedure('world.books(int)') is null then
    raise exception '0286 refuses: world.books(integer) is not in this world — 0177 is not the shape this file retires';
  end if;
  if to_regprocedure('public.client_rpc_entry_points()') is null then
    raise exception '0286 refuses: the client entry-point registry is not in this world';
  end if;
  if (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'ledger'
         and c.column_name in ('port_id', 'fleet_id', 'voyage_id') and c.is_nullable = 'YES'
         and c.data_type = 'uuid') <> 3 then
    raise exception '0286 refuses: 0284''s three nullable ledger point columns are not here';
  end if;
end $guard$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table before_0286 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid <> 'public.client_rpc_entry_points()'::regprocedure) as fns_md5,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure) as acl;

create or replace function pg_temp.occurs_0286(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE READ ─────────────────────────────────────────────────────────────────────────────────
create or replace function world.report(p_span text default 'week')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0286: THE REPORT (docs/COMMAND_REDESIGN.md §4; owner rows 192, 244) — the caller's ledger, cut by
-- span (game days), by the design's fixed sections and by point (port, else voyage, else Earlier).
-- Derived per read; writes nothing. FOUNDING is capital and PROBE_% never appears. The points form
-- a partition, so the place sums equal the section sums. The client never computes a span or a day.
declare
  v_player uuid := public.current_player_id();
  v_today  int := world.game_day();
  v_gds    numeric := public.wc_num('game_day_seconds');
  v_span   int;
  v_from   timestamptz;
  v_out    jsonb;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  if p_span is null or p_span not in ('day', 'week', 'all') then
    raise exception 'E_SPAN: % is not day, week or all', coalesce(p_span, '(null)') using errcode = 'P0001';
  end if;
  v_span := case p_span when 'day' then 1 when 'week' then 7 else null end;
  if v_span is not null then
    -- the EXACT game-day boundary: world.game_day(t) = floor(epoch(t) / game_day_seconds)
    v_from := to_timestamp(((v_today - v_span + 1) * v_gds)::double precision);
  end if;

  with kept as (
    select l.kind, l.ducats_delta, l.port_id, l.voyage_id, l.created_at,
           world.game_day(l.created_at) as day
      from public.ledger l
     where l.player_id = v_player
       and l.kind <> 'FOUNDING'                 -- capital, not something the company made
       and left(l.kind, 6) <> 'PROBE_'          -- rolled-back self-asserts are never served
       and (v_from is null or l.created_at >= v_from)
  ),
  wordmap(kind, word, ord) as (values
    ('SELL', 'Sold', 1), ('BUY', 'Bought', 2), ('TAX', 'Profit tax', 3), ('PORT_FEE', 'Port fee', 3),
    ('WAGES', 'Wages', 4), ('HIRE', 'Hired', 5), ('PROVISION', 'Supplies', 6),
    ('REPAIR', 'Repairs', 7), ('INSURANCE', 'Insurance', 8), ('INSURANCE_PAID', 'Insurance paid', 9),
    ('SHARE', 'Invested', 10), ('DIVIDEND', 'Dividends', 11), ('DONATION', 'Donations', 12),
    ('BUILD', 'Build', 13), ('TUITION', 'Tuition', 14), ('TOW', 'Tows', 15)
  ),
  mapped as (
    select k.kind, k.ducats_delta, k.port_id, k.voyage_id, k.created_at, k.day,
           case when k.kind in ('SELL', 'BUY', 'TAX', 'PORT_FEE') then 'trade'
                when k.kind in ('WAGES', 'HIRE') then 'crew'
                when k.kind = 'PROVISION' then 'supplies'
                when k.kind = 'REPAIR' then 'repairs'
                when k.kind in ('INSURANCE', 'INSURANCE_PAID') then 'insurance'
                when k.kind in ('SHARE', 'DIVIDEND', 'DONATION') then 'invest'
                when k.kind = 'BUILD' then 'ships'
                else 'other' end as section
      from kept k
  ),
  lines as (
    select m.section, m.kind, sum(m.ducats_delta) as ducats
      from mapped m
     group by m.section, m.kind
  ),
  sects(id, ord) as (values
    ('trade', 1), ('crew', 2), ('supplies', 3), ('repairs', 4),
    ('insurance', 5), ('invest', 6), ('ships', 7), ('other', 8)
  ),
  section_json as (
    select s.id, s.ord,
           coalesce(sum(l.ducats), 0) as ducats,
           coalesce(jsonb_agg(jsonb_build_object(
                      'kind', l.kind,
                      'word', coalesce(w.word, initcap(lower(l.kind))),
                      'ducats', l.ducats)
                    order by coalesce(w.ord, 99), l.kind) filter (where l.kind is not null), '[]'::jsonb) as lines
      from sects s
      left join lines l on l.section = s.id
      left join wordmap w on w.kind = l.kind
     group by s.id, s.ord
  ),
  -- THE POINT: the port when docked; else the voyage; else Earlier. A partition, never a double count.
  pointed as (
    select m.*,
           case when m.port_id is not null then 'port'
                when v.id is not null then 'voyage'
                else 'earlier' end as pkind,
           v.id as v_id, v.origin_port_id, v.dest_port_id, v.departed_at
      from mapped m
      left join public.voyages v on m.port_id is null and v.id = m.voyage_id
  ),
  place_lines as (
    select p.pkind, p.port_id, p.v_id, p.origin_port_id, p.dest_port_id, p.departed_at,
           p.kind, sum(p.ducats_delta) as ducats
      from pointed p
     group by p.pkind, p.port_id, p.v_id, p.origin_port_id, p.dest_port_id, p.departed_at, p.kind
  ),
  place_json as (
    select p.pkind, p.port_id, p.v_id, p.origin_port_id, p.dest_port_id, p.departed_at,
           sum(p.ducats) as ducats,
           jsonb_agg(jsonb_build_object(
             'kind', p.kind,
             'word', coalesce(w.word, initcap(lower(p.kind))),
             'ducats', p.ducats)
             order by coalesce(w.ord, 99), p.kind) as lines
      from place_lines p
      left join wordmap w on w.kind = p.kind
     group by p.pkind, p.port_id, p.v_id, p.origin_port_id, p.dest_port_id, p.departed_at
  ),
  day_rows as (
    select m.day, sum(m.ducats_delta) as net from mapped m group by m.day
  ),
  day_axis as (
    select d as game_day,
           coalesce((select r.net from day_rows r where r.day = d), 0) as net
      from generate_series(
             case when v_span is not null then v_today - v_span + 1
                  else coalesce((select min(r.day) from day_rows r), v_today + 1) end,
             v_today) d
  )
  select jsonb_build_object(
           'span', p_span,
           'game_day', v_today,
           'total', coalesce((select sum(s.ducats) from section_json s), 0),
           'sections', coalesce(
             (select jsonb_agg(jsonb_build_object('id', s.id, 'ducats', s.ducats, 'lines', s.lines) order by s.ord)
                from section_json s), '[]'::jsonb),
           'places', coalesce(
             (select jsonb_agg(
                       case when p.pkind = 'port' then
                              jsonb_build_object('kind', 'port', 'id', p.port_id, 'code', pc.code, 'name', pc.name,
                                                 'ducats', p.ducats, 'lines', p.lines)
                            when p.pkind = 'voyage' then
                              jsonb_build_object('kind', 'voyage', 'id', p.v_id,
                                                 'from', oc.code, 'to', dc.code,
                                                 'from_name', oc.name, 'to_name', dc.name,
                                                 'day', world.game_day(p.departed_at),
                                                 'ducats', p.ducats, 'lines', p.lines)
                            else jsonb_build_object('kind', 'earlier', 'ducats', p.ducats, 'lines', p.lines) end
                       order by case p.pkind when 'port' then 1 when 'voyage' then 2 else 3 end,
                                case when p.pkind = 'port' then pc.code
                                     when p.pkind = 'voyage' then oc.code end nulls last,
                                p.departed_at nulls last)
                from place_json p
                left join public.ports pc on pc.id = p.port_id
                left join public.ports oc on oc.id = p.origin_port_id
                left join public.ports dc on dc.id = p.dest_port_id), '[]'::jsonb),
           'days', coalesce(
             (select jsonb_agg(jsonb_build_object('game_day', a.game_day, 'net', a.net) order by a.game_day)
                from day_axis a), '[]'::jsonb))
    into v_out;
  return v_out;
end $$;

comment on function world.report(text) is
  '0286: THE REPORT (docs/COMMAND_REDESIGN.md §4) — the caller''s ledger by the design''s sections and by '
  'point (port, else voyage, else Earlier), over a day / week (7 game days) / all span. Derived per read; '
  'FOUNDING and PROBE_% are never served. The points partition, so places sum to the total.';
revoke all on function world.report(text) from public, anon, authenticated;
grant execute on function world.report(text) to authenticated;

-- 0177's client door is retired: the body stays for frozen 0232's owner-run timing probe (header).
revoke execute on function world.books(int) from authenticated;

-- ── 2. THE REGISTRY (two hunks, sliced from the live body; each reverses; ACL unchanged) ────────
do $$
declare
  b      record;
  v_old1 text := $h$      -- 0177: the books — the ledger by game day and kind (docs/COMMAND_DESK.md §3.8, D7).
      ('world',       'books',                 'int'),
$h$;
  v_new1 text := $h$      -- 0286: world.books retired — the Report face reads world.report (docs/COMMAND_REDESIGN.md §4).
$h$;
  v_old2 text := $h$      ('cmd',         'forge_good',            'uuid, uuid, int')
$h$;
  v_new2 text := $h$      ('cmd',         'forge_good',            'uuid, uuid, int'),
      -- 0286 (R4, Report): the ledger by section and point, any span — replaces 0177's world.books
      -- (its client grant is retired above; its body stays for frozen 0232's owner-run timing probe).
      ('world',       'report',                'text')
$h$;
  v_rev  text;
begin
  select * into b from before_0286;
  if pg_temp.occurs_0286(b.def, v_old1) <> 1 or pg_temp.occurs_0286(b.def, v_old2) <> 1 then
    raise exception '0286 self-assert FAIL: a registry hunk occurs % / % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0286(b.def, v_old1), pg_temp.occurs_0286(b.def, v_old2);
  end if;
  execute replace(replace(b.def, v_old1, v_new1), v_old2, v_new2);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0286(v_rev, v_new1) <> 1 or pg_temp.occurs_0286(v_rev, v_new2) <> 1
     or replace(replace(v_rev, v_new1, v_old1), v_new2, v_old2) <> b.def then
    raise exception '0286 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.acl then
    raise exception '0286 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid   constant uuid := '00000000-0286-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0286-4000-8000-000000000002';
  c_nil   constant uuid := '00000000-0000-0000-0000-000000000000';
  b       record;
  v_p     uuid;
  v_p2    uuid;
  v_f     uuid;
  v_lis   uuid;
  v_fnc   uuid;
  v_voy   uuid;
  v_today int;
  v_gds   numeric;
  v_start timestamptz;
  v_d0    bigint;
  v_voy_day int;
  v_day   jsonb;
  v_week  jsonb;
  v_all   jsonb;
  v_empty jsonb;
  v_empty_week jsonb;
  v_empty_all jsonb;
  v_sec   jsonb;
  v_sum   bigint;
  v_vol   text;
  v_def   boolean;
  v_cfg   text;
  v_bad_span boolean := false;
  v_bad_read boolean := false;
begin
  select * into b from before_0286;

  -- (a) THE READ'S SHAPE, ITS GRANTS AND THE REGISTRY
  select p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '')
    into v_vol, v_def, v_cfg
    from pg_proc p where p.oid = to_regprocedure('world.report(text)');
  if v_vol is distinct from 's' or v_def is not true or v_cfg not like '%search_path=public, pg_temp%' then
    raise exception '0286 self-assert FAIL: world.report is not STABLE SECURITY DEFINER with search_path public, pg_temp (% / % / %)', v_vol, v_def, v_cfg;
  end if;
  if not has_function_privilege('authenticated', 'world.report(text)', 'execute')
     or has_function_privilege('anon', 'world.report(text)', 'execute')
     or has_function_privilege('authenticated', 'world.books(int)', 'execute')
     or has_function_privilege('anon', 'world.books(int)', 'execute') then
    raise exception '0286 self-assert FAIL: the read''s grant wall moved (report must be authenticated-only; books'' client grant is retired)';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'world' and e.function_name = 'report' and e.arg_types = 'text' and e.fn is not null)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.schema_name = 'world' and e.function_name = 'books')
     or (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0286 self-assert FAIL: the registry is not report-in / books-out at the same count';
  end if;

  -- (b) NOTHING ELSE MOVED: every other function in the four schemas, by md5; the registry's body is
  --     the only existing body this file re-cuts, and its reversal was proven in §2.
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('world.report(text)'), 'public.client_rpc_entry_points()'::regprocedure)) is distinct from b.fns_md5
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> b.fns + 1 then
    raise exception '0286 self-assert FAIL: a function moved, or more than the one new function was minted';
  end if;

  -- (c) THE LOCKED WALLS
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0286 self-assert FAIL: the grant wall or the read wall moved';
  end if;

  -- (d) THE REPORT, on the probe's own rows only — rolled back whole
  begin
    v_p  := public.new_house(c_uid,  'Casa do Relatorio 0286', 'PRT', 'LIS');
    v_p2 := public.new_house(c_uid2, 'Casa Vazia 0286',       'PRT', 'LIS');
    select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_p;
    select p.id into v_fnc from public.ports p where p.code = 'FNC';
    if v_f is null or v_lis is null or v_fnc is null or v_fnc = v_lis then
      raise exception '0286 self-assert FAIL: no probe fleet, or no second harbour';
    end if;
    select ducats into v_d0 from public.players where id = v_p;
    v_today := world.game_day();
    v_gds   := public.wc_num('game_day_seconds');
    v_start := to_timestamp((v_today * v_gds)::double precision);
    perform cmd.assume_identity(c_uid);

    -- AN EMPTY REPORT FIRST: FOUNDING is capital, so a new house has made nothing yet.
    v_empty      := world.report('day');
    v_empty_week := world.report('week');
    v_empty_all  := world.report('all');
    if (v_empty->>'total')::bigint <> 0
       or (v_empty->>'game_day')::int <> v_today
       or jsonb_array_length(v_empty->'sections') <> 8
       or exists (select 1 from jsonb_array_elements(v_empty->'sections') s
                   where (s->>'ducats')::bigint <> 0 or jsonb_array_length(s->'lines') <> 0)
       or jsonb_array_length(v_empty->'places') <> 0
       or jsonb_array_length(v_empty->'days') <> 1
       or (v_empty->'days'->0->>'game_day')::int <> v_today
       or (v_empty->'days'->0->>'net')::bigint <> 0 then
      raise exception '0286 self-assert FAIL: a new company''s Day report is not the empty shape: %', v_empty;
    end if;
    if jsonb_array_length(v_empty_week->'days') <> 7
       or exists (select 1 from jsonb_array_elements(v_empty_week->'days') d where (d->>'net')::bigint <> 0)
       or (v_empty_week->>'total')::bigint <> 0 then
      raise exception '0286 self-assert FAIL: a new company''s Week axis is not 7 zeros: %', v_empty_week;
    end if;
    if (v_empty_all->>'total')::bigint <> 0
       or jsonb_array_length(v_empty_all->'days') <> 0
       or jsonb_array_length(v_empty_all->'places') <> 0 then
      raise exception '0286 self-assert FAIL: a new company''s All report is not empty: %', v_empty_all;
    end if;
    -- the second house exists so the first house's rows can never be read through it (same shape).
    if (select count(*) from public.players where id in (v_p, v_p2)) <> 2 then
      raise exception '0286 self-assert FAIL: the two probe houses did not both open';
    end if;

    -- A VOYAGE the probe owns: Lisbon → Funchal, arrived two days ago (its departure game day is read back).
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                origin_port_id, dest_port_id, created_at)
    values (v_voy, v_f, v_p, '[]', 100, '{}', now() - interval '2 days', now() - interval '1 day', 'ARRIVED',
            v_lis, v_fnc, now() - interval '2 days');
    v_voy_day := world.game_day(now() - interval '2 days');

    -- THE PLANTED HISTORY, all today: the eight sections, an unlisted kind, a PROBE row that must
    -- never appear, and one row naming BOTH a port and the voyage (the port wins, once).
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, port_id, fleet_id, voyage_id, created_at) values
      (v_p, 'SELL',            500, v_d0, v_lis, v_f, null,   v_start + interval '1 second'),
      (v_p, 'BUY',            -200, v_d0, v_fnc, v_f, null,   v_start + interval '1 second'),
      (v_p, 'TAX',             -50, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'PORT_FEE',        -60, v_d0, v_lis, v_f, null,   v_start + interval '1 second'),
      (v_p, 'WAGES',           -30, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'HIRE',            -20, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'PROVISION',       -70, v_d0, v_lis, v_f, null,   v_start + interval '1 second'),
      (v_p, 'REPAIR',          -40, v_d0, v_lis, v_f, null,   v_start + interval '1 second'),
      (v_p, 'INSURANCE',       -90, v_d0, v_lis, v_f, null,   v_start + interval '1 second'),
      (v_p, 'INSURANCE_PAID',  300, v_d0, null,  v_f, v_voy,  v_start + interval '1 second'),
      (v_p, 'SHARE',          -400, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'DIVIDEND',        100, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'DONATION',        -60, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'BUILD',         -1000, v_d0, v_lis, v_f, null,   v_start + interval '1 second'),
      (v_p, 'TUITION',         -80, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'TOW',             -25, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'GRANT',            55, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'PROBE_0286',      999, v_d0, null,  null, null,  v_start + interval '1 second'),
      (v_p, 'SELL',             10, v_d0, v_fnc, v_f, v_voy,  v_start + interval '1 second'),
      -- THE SPAN BOUNDARIES, on the exact game-day clock:
      -- 1 s before today is outside Day (inside Week);
      -- the exact start of today−6 is inside Week; the exact start of today−7 is outside Week;
      -- 30 game days ago is outside Week but inside All.
      (v_p, 'TOW',             111, v_d0, null,  null, null,  v_start - interval '1 second'),
      (v_p, 'TUITION',         222, v_d0, v_lis, v_f, null,   to_timestamp(((v_today - 6) * v_gds)::double precision)),
      (v_p, 'GRANT',           333, v_d0, v_fnc, v_f, null,   to_timestamp(((v_today - 7) * v_gds)::double precision)),
      (v_p, 'TOW',             444, v_d0, null,  null, null,  v_start - make_interval(secs => (30 * v_gds)::double precision));

    v_day  := world.report('day');
    v_week := world.report('week');
    v_all  := world.report('all');

    -- THE TOTALS: Day −1,160 / Week −827 / All −50 (the boundary rows prove the filter).
    if (v_day->>'total')::bigint <> -1160 or (v_week->>'total')::bigint <> -827 or (v_all->>'total')::bigint <> -50 then
      raise exception '0286 self-assert FAIL: the span totals are % / % / %, not −1,160 / −827 / −50',
        v_day->>'total', v_week->>'total', v_all->>'total';
    end if;
    if (v_day->>'span') <> 'day' or (v_week->>'span') <> 'week' or (v_all->>'span') <> 'all'
       or (v_day->>'game_day')::int <> v_today then
      raise exception '0286 self-assert FAIL: the served span or game day is wrong';
    end if;

    -- EVERY SECTION'S SUM, on the Day span.
    select jsonb_object_agg(s->>'id', (s->>'ducats')::bigint) into v_sec
      from jsonb_array_elements(v_day->'sections') s;
    if (v_sec->>'trade')::bigint <> 200 or (v_sec->>'crew')::bigint <> -50
       or (v_sec->>'supplies')::bigint <> -70 or (v_sec->>'repairs')::bigint <> -40
       or (v_sec->>'insurance')::bigint <> 210 or (v_sec->>'invest')::bigint <> -360
       or (v_sec->>'ships')::bigint <> -1000 or (v_sec->>'other')::bigint <> -50 then
      raise exception '0286 self-assert FAIL: a section''s Day sum is wrong: %', v_sec;
    end if;
    -- every section's lines sum to the section; the sections sum to the total; lines are exact.
    if exists (select 1 from jsonb_array_elements(v_day->'sections') s
                where coalesce((select sum((l->>'ducats')::bigint) from jsonb_array_elements(s->'lines') l), 0) <> (s->>'ducats')::bigint) then
      raise exception '0286 self-assert FAIL: a section is not the sum of its lines: %', v_day->'sections';
    end if;
    select coalesce(sum((s->>'ducats')::bigint), 0) into v_sum from jsonb_array_elements(v_day->'sections') s;
    if v_sum <> (v_day->>'total')::bigint then
      raise exception '0286 self-assert FAIL: the Day total is not the sections'' sum';
    end if;
    if not exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                    where s->>'id' = 'trade' and l->>'kind' = 'SELL' and (l->>'ducats')::bigint = 510)
       or not exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                    where s->>'id' = 'trade' and l->>'kind' = 'BUY' and (l->>'ducats')::bigint = -200)
       or not exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                    where s->>'id' = 'other' and l->>'kind' = 'GRANT' and (l->>'ducats')::bigint = 55 and l->>'word' = 'Grant')
       or not exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                    where s->>'id' = 'trade' and l->>'kind' = 'PORT_FEE' and (l->>'ducats')::bigint = -60 and l->>'word' = 'Port fee') then
      raise exception '0286 self-assert FAIL: the kind lines are not exact (SELL 510, BUY −200, PORT_FEE −60 inside Trade, the unlisted GRANT under its own name)';
    end if;

    -- THE PLACES: ports (alphabetical), the voyage, Earlier last; a partition summing to the total.
    if not exists (select 1 from jsonb_array_elements(v_day->'places') p
                    where p->>'kind' = 'port' and p->>'code' = 'LIS' and (p->>'ducats')::bigint = -760)
       or not exists (select 1 from jsonb_array_elements(v_day->'places') p
                    where p->>'kind' = 'port' and p->>'code' = 'FNC' and (p->>'ducats')::bigint = -190) then
      raise exception '0286 self-assert FAIL: the port points are not LIS −760 / FNC −190: %', v_day->'places';
    end if;
    if not exists (select 1 from jsonb_array_elements(v_day->'places') p
                    where p->>'kind' = 'voyage' and (p->>'id')::uuid = v_voy
                      and p->>'from' = 'LIS' and p->>'to' = 'FNC'
                      and (p->>'day')::int = v_voy_day and (p->>'ducats')::bigint = 300) then
      raise exception '0286 self-assert FAIL: the voyage point is not LIS→FNC d% at +300: %', v_voy_day, v_day->'places';
    end if;
    if v_day->'places'->-1->>'kind' <> 'earlier'
       or (v_day->'places'->-1->>'ducats')::bigint <> -510
       or (select count(*) from jsonb_array_elements(v_day->'places') p where p->>'kind' = 'earlier') <> 1 then
      raise exception '0286 self-assert FAIL: Earlier is not LAST at −510: %', v_day->'places';
    end if;
    select coalesce(sum((p->>'ducats')::bigint), 0) into v_sum from jsonb_array_elements(v_day->'places') p;
    if v_sum <> (v_day->>'total')::bigint then
      raise exception '0286 self-assert FAIL: the place sums are not the section sums (the points are not a partition)';
    end if;
    -- the both-points row (SELL +10 port FNC + voyage v) is counted ONCE, under the port.
    if (select sum((p->>'ducats')::bigint) from jsonb_array_elements(v_week->'places') p where p->>'kind' = 'voyage') <> 300 then
      raise exception '0286 self-assert FAIL: a row with both a port and a voyage was counted in the voyage too';
    end if;

    -- THE SPAN FILTER, through the sections it must move: Other is −50 on Day, +283 on Week, +1,060 on All.
    if ((select (s->>'ducats')::bigint from jsonb_array_elements(v_week->'sections') s where s->>'id' = 'other') <> 283)
       or ((select (s->>'ducats')::bigint from jsonb_array_elements(v_all->'sections') s where s->>'id' = 'other') <> 1060) then
      raise exception '0286 self-assert FAIL: the game-day boundary filter is wrong (Other should be −50 / 283 / 1060)';
    end if;

    -- THE DAY AXES: Day 1, Week 7, All 31, zero-filled, each summing to its total; the edge days exact.
    if jsonb_array_length(v_day->'days') <> 1
       or (v_day->'days'->0->>'net')::bigint <> -1160
       or jsonb_array_length(v_week->'days') <> 7
       or (v_week->'days'->0->>'game_day')::int <> v_today - 6
       or (v_week->'days'->0->>'net')::bigint <> 222
       or (v_week->'days'->6->>'game_day')::int <> v_today
       or (v_week->'days'->6->>'net')::bigint <> -1160
       or jsonb_array_length(v_all->'days') <> 31
       or (v_all->'days'->0->>'game_day')::int <> v_today - 30
       or (v_all->'days'->0->>'net')::bigint <> 444
       or (v_all->'days'->-1->>'game_day')::int <> v_today
       or (v_all->'days'->-1->>'net')::bigint <> -1160 then
      raise exception '0286 self-assert FAIL: a day axis is not 1 / 7 / 31 zero-filled entries at the right edges: % / % / %',
        jsonb_array_length(v_day->'days'), jsonb_array_length(v_week->'days'), jsonb_array_length(v_all->'days');
    end if;
    if (select sum((d->>'net')::bigint) from jsonb_array_elements(v_week->'days') d) <> (v_week->>'total')::bigint
       or (select sum((d->>'net')::bigint) from jsonb_array_elements(v_all->'days') d) <> (v_all->>'total')::bigint then
      raise exception '0286 self-assert FAIL: a day axis does not sum to its span''s total';
    end if;

    -- FOUNDING and PROBE_% NEVER appear; nothing is dropped (every line is in a section).
    if exists (select 1 from jsonb_array_elements(v_all->'sections') s, jsonb_array_elements(s->'lines') l
                where l->>'kind' in ('FOUNDING', 'PROBE_0286')) then
      raise exception '0286 self-assert FAIL: FOUNDING or a PROBE row was served';
    end if;

    -- AN UNKNOWN SPAN IS REFUSED, not defaulted.
    begin
      perform world.report('month');
    exception when others then v_bad_span := true;
    end;
    if not v_bad_span then
      raise exception '0286 self-assert FAIL: an unknown span was served instead of refused';
    end if;

    -- THE READING AS A CLIENT ROLE: the granted door answers, and the retired books door does not.
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_uid)::text, true);
    begin
      set local role authenticated;
      if (select (world.report('day'))->>'total')::bigint <> -1160 then
        raise exception '0286 self-assert FAIL: the authenticated door served a different total';
      end if;
      begin
        perform world.books(7);
      exception when insufficient_privilege then v_bad_read := true;
      end;
      reset role;
    exception when others then
      reset role;
      raise;
    end;
    if not v_bad_read then
      raise exception '0286 self-assert FAIL: world.books still answered a client role — its door is not retired';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- (e) the subtransaction is gone; the findings survive (plpgsql variables are not transactional)
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where company_name in ('Casa do Relatorio 0286', 'Casa Vazia 0286'))
     or exists (select 1 from public.ledger where kind = 'PROBE_0286')
     or exists (select 1 from public.voyages where id = v_voy) then
    raise exception '0286 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0286 self-assert ok: THE REPORT. world.report(text) (STABLE, SECURITY DEFINER, authenticated only) serves the ledger by the design''s eight sections and by point (port, else voyage, else Earlier last); PORT_FEE stays INSIDE Trade (never its own section or place); the registry has report in and books out at the same count, books'' client grant is retired (its body stays for frozen 0232), every other function unmoved by md5. Probe, rolled back: Day −1,160 / Week −827 / All −50; Trade 200 · Crew −50 · Supplies −70 · Repairs −40 · Insurance +210 · Invest −360 · Ships −1000 · Other −50; LIS −760 · FNC −190 · voyage LIS→FNC d% +300 · Earlier −510 last; the exact game-day boundary splits Day/Week/All; 1 / 7 / 31 zero-filled days each sum to its total; FOUNDING and PROBE_0286 hidden; an unlisted GRANT under its own name; the empty report is eight zero sections, no places, [today 0] / 7 zeros / no days; an unknown span refused; no probe rows survive.',
    v_voy_day;
end $$;
