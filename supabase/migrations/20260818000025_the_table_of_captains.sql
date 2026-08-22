-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0025 — THE TABLE OF CAPTAINS
--        A standing, computed from the ledger, that a house may read about OTHER houses — and the
--        exact four things it is allowed to say about them.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ────────────────────────────────────────────────────────────────────────────────────
-- DESIGN I.4: "the Ledger is not a UI convenience — it is the source of truth from which rank is
-- computed." I.5: "Top 10 shown on RANK; full list paginated."
--
-- RANK currently tells the player, on screen, that no table of captains exists. It is telling the
-- truth. `src/features/rank/RankScreen.tsx:19-25` states the defect precisely:
--
--     "There is no standings RPC and no player row a client may read. world.snapshot() carries the
--      WORLD ... world.ledger() carries this house's own events and its purse. So the client can
--      say what YOU are worth. It cannot say what that is worth RELATIVE to anyone, because no
--      other house's figures cross the wire and nothing in the chain computes a table."
--
-- Both halves are fixed here, and neither is fixed by widening a policy.
--
-- ── THE BLOCKING QUESTION, DECIDED: WHO MAY SEE WHOSE FIGURES ──────────────────────────────────
-- Every player-owned table in this chain is READ-OWN (`player_id = public.current_player_id()`),
-- and 0023 spent a whole migration proving that wall stands — "house A saw EXACTLY the rows it
-- owns and ZERO of house B's". A leaderboard is a deliberate hole in that wall, so the hole is cut
-- once, to a stated size, in ONE function, and the wall itself is not touched.
--
--   THE DECISION: a board row carries a NAME, a NATION, a STANDING, and the FAMES the standing is
--   computed from. It carries NOTHING ELSE. In particular it never carries the purse, the cargo,
--   the fleets, the ships, the port a fleet lies in, or any ledger line.
--
-- The reason is the game's own shape, not squeamishness. DESIGN J.1: markets are shared, and
-- "when a player buys out Calicut's pepper, the next player finds it dear" is the ONLY direct
-- pressure players put on each other. In a game whose whole PvP surface is the order book, another
-- house's purse and the port her fleet lies in are not colour — they are ACTIONABLE: they say what
-- she can afford to corner and where she will try. A name and a standing say where you sit, which
-- is the entire purpose of a leaderboard, and they cost the person above you nothing.
--
-- Fame is the right figure to expose for the same reason: DESIGN I.1 defines it as a measure of
-- DEEDS — margin realised, ports called at — and 0014 already derives it from the append-only
-- record rather than storing it. A deed is a public thing. A balance is not.
--
--   HOW IT IS ENFORCED: `world.standings()` is the ONE place another house's figures cross the
--   wire. `public.standings` itself has RLS on, NO policy and NO grant to any client role, so the
--   table is unreachable by a browser however the API is pointed at it. Widening
--   `players_read_own` to achieve this was rejected outright: a policy is row-shaped, so opening
--   it would open the WHOLE row — `ducats`, `company_level`, `auth_uid` — to satisfy a screen that
--   wants four columns. The self-assert below proves the negative BEHAVIOURALLY: it searches the
--   serialised board for another house's purse and requires it absent, and it requires every board
--   row's key set to equal the sanctioned list exactly, so a future field cannot be added here by
--   accident.
--
-- ── COMPUTED FROM THE LEDGER, BY COMPOSING THE THING THAT ALREADY DOES IT ──────────────────────
-- `public.player_fame(player)` (0014) reads turnover off `public.ledger` joined to `public.events`
-- and counts distinct arrivals off `VOYAGE_REPORT` events. It is DERIVED on every call and never
-- stored, "so it cannot drift from the ledger it is computed from" (0014:104-106).
--
-- This file does not recompute one term of it. `public.settle_standings()` calls
-- `public.player_fame(p.id)` once per house and records what it said. That is the difference
-- between a second CALLER and a second AUTHOR (docs/NO_SPAGHETTI.md §1): if the fame weights
-- change tomorrow, exactly one function changes and this board follows it on the next slot.
--
-- ── WHAT BOUNDS IT — THE READ DOES NOT SCAN THE WORLD ──────────────────────────────────────────
-- Naive shape: `world.standings()` calls `player_fame()` for every house on every open. That is
-- O(houses × ledger) per tab open, on a screen a player leaves sitting there.
--
-- So the board is a RECORD, exactly as `public.price_history` is (0013): derivation stays the only
-- way a standing is COMPUTED, and this only records what it said, keyed on a SLOT so a retried
-- write is a no-op by construction.
--
--     public.standings_slot_of(at)   the named slot authority (0013's drift_slot_of, same shape)
--     public.settle_standings(at)    O(houses) — writes one row per house for the current slot,
--                                    ON CONFLICT DO NOTHING, and prunes past the retention window
--     world.standings(limit)         O(board_size) — a primary-key range scan of ONE slot, plus
--                                    ONE primary-key lookup for the reader's own row
--
-- WHO CALLS THE SETTLE: the read does, and only if the current slot is missing. That is this
-- chain's own idiom, not a new one — 0009: "Every fleet read calls voyage.settle() first: THE READ
-- IS THE CATCH-UP." So the first captain to open RANK in a five-minute slot pays the O(houses)
-- pass and every other captain in that slot pays two index lookups. There is no cron dependency,
-- which matters because `pg_cron` is absent under PGlite (0012) and a board that only exists where
-- a scheduler does would be empty on half the platforms this chain runs on.
--
-- ── HONEST ABOUT TIES, AND ABOUT WHEN IT WAS SETTLED ───────────────────────────────────────────
-- TIES: `rank()`, not `row_number()` and not `dense_rank()`. Two houses on 1,200 fame are BOTH
-- second and the next house is fourth. Every row also carries `tied`, so the screen can say "=2"
-- rather than inventing an order between two equal captains. `row_number()` would have picked a
-- winner out of heap order, which is the lottery docs/NO_SPAGHETTI.md §4 forbids; `dense_rank()`
-- would have hidden how many people are level with you.
--
-- SETTLED: every payload carries `settled_at` (the wall clock of the pass that wrote it),
-- `board_slot`, `slot_seconds` and `age_seconds`. A board is a photograph and it says so. Your OWN
-- figures are live on the same screen already — `world.player()` derives them on every call
-- (0014) — so the client can show a live self against a settled field, which is exactly what
-- DESIGN I.4 asks for: "Refreshed every 5 minutes for leaderboards; computed live on the RANK tab."
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────
--   * NO SEASONS. DESIGN I.5 wants a per-season board; nothing in this chain records a season
--     boundary, so this board is of ALL TIME and the payload says `season: null` rather than
--     implying one. Inventing a season here would have put a second definition of "when did the
--     year turn" in the chain before the first one exists.
--   * NO PER-NATION BOARD. Same reason: it is a filter over this same record and it can be added
--     without a schema change, so it is not guessed at now.
--   * NO ADVENTURE/NAVAL AXES. DESIGN I.1 names three; `public.player_fame` derives TWO (trade and
--     exploration) and this board serves exactly what that authority produces. Serving a `naval: 0`
--     column would be printing a number no rule computes.
--   * NO TITLES. DESIGN I.3's eleven title levels need all three fames; two exist.
--   * IT MOVES NO MONEY AND NO PRICE. Proven below against a pre-image of real quotes rather than
--     asserted, because "this changes nothing" is a sentence and a comparison is evidence.
--
-- ── GRANTS: THIS FILE GRANTS. IT REVOKES NOTHING. ──────────────────────────────────────────────
-- ONE new client entry point takes `grant execute ... to authenticated`: `world.standings(int)`.
-- No table grant is issued at all — `public.standings` is deliberately unreachable by every client
-- role. `public.standings_slot_of` and `public.settle_standings` are revoked from public/anon/
-- authenticated. `supabase db push` connects as `postgres.<ref>` through the pooler and cannot do
-- this on these schemas; apply through the Management API as `postgres`, the way 0018 and 0022
-- were applied.
--
-- ── WHAT IT SUPERSEDES ─────────────────────────────────────────────────────────────────────────
--   public.client_rpc_entry_points (0018, re-cut 0019, re-cut 0022) — one row added. 0018's grant
--                                   loop reads THIS list, so granted and sanctioned cannot drift.
--
-- Depends ONLY on: 0004 (players, ledger, events, current_player_id), 0014 (player_fame),
--                  0013 (drift_slot_of — the shape copied, not the code), 0018/0022
--                  (client_rpc_entry_points), 0001 (world_config, wc_int, client_write_grants).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGE. Real quotes on real (port, good) pairs, taken through the CURRENT pricing path
-- before a line of this file runs, so "the economy did not move" is a comparison and not a
-- sentence. Scaffolding for one assert; dropped at the foot of this file.
create temporary table quote_before_0025 as
  select pg.port_id, pg.good_id, s.side, s.qty,
         q.units, q.total, q.avg_price, q.end_stock
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 40) pg
   cross join (values ('buy'::text, 10::numeric), ('buy', 130), ('sell', 25)) as s(side, qty)
   cross join lateral world.quote(pg.port_id, pg.good_id, s.qty, s.side) q;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('standings_slot_seconds', to_jsonb(300),
   'DESIGN I.4 (0025): how often the table of captains is settled, in real seconds. 300 is I.4''s own "refreshed every 5 minutes". A board is a photograph; this is the shutter. The read settles the current slot if nobody has yet, so this is also the most work any one RANK open can cost.'),
  ('standings_board_size', to_jsonb(10),
   'DESIGN I.5 (0025): how many captains the board shows. The reader''s own standing is always served beside it, even when she is nowhere near the top, so a small board does not mean an unreadable one.'),
  ('standings_slots_kept', to_jsonb(12),
   'How many settled boards are kept before the oldest is pruned. 12 slots at 300 seconds is one hour. The record exists so a read is two index lookups; it is not an archive, and an unpruned one would grow by (houses) rows every five minutes for ever.')
on conflict (key) do nothing;

-- ── 2. THE SLOT ────────────────────────────────────────────────────────────────────────────────
-- A named authority for "which board does this instant belong to", exactly as public.drift_slot_of
-- (0013:64) is the named authority for the market's drift slot. Two callers — the settle and the
-- read — must agree on the answer, and the only way to guarantee that is for there to be one
-- answer.
create or replace function public.standings_slot_of(p_at timestamptz default now())
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select floor(extract(epoch from p_at) / public.wc_num('standings_slot_seconds'))::int $$;

comment on function public.standings_slot_of(timestamptz) is
  'THE slot a settled board belongs to. public.settle_standings writes it and world.standings '
  'reads it; a second spelling of this arithmetic would let the writer and the reader disagree '
  'about which photograph is the current one.';

revoke all on function public.standings_slot_of(timestamptz) from public, anon, authenticated;

-- ── 3. THE RECORD ──────────────────────────────────────────────────────────────────────────────
-- Keyed (board_slot, player_id): a retried settle is a no-op BY CONSTRUCTION rather than by a
-- guard somebody has to remember to write. This is public.price_history's shape (0013:100) and it
-- is here for the same reason.
--
-- THE COLUMN LIST IS THE PRIVACY DECISION, WRITTEN DOWN. Everything in this table is served by
-- world.standings() and everything world.standings() serves is in this table. There is no column
-- recorded "in case" — a purse stored here and merely not selected would be one careless jsonb
-- key away from being disclosed, and nobody would notice.
create table if not exists public.standings (
  board_slot       int  not null,
  player_id        uuid not null references public.players(id) on delete cascade,
  -- `rank_position`, not `position`: POSITION is a SQL function name and a column called that has
  -- to be qualified everywhere it is read. The jsonb key the client sees is still "position",
  -- because that is the player's word for it.
  rank_position    int  not null check (rank_position >= 1),
  tied             boolean not null,
  trade_fame       int  not null check (trade_fame >= 0),
  exploration_fame int  not null check (exploration_fame >= 0),
  total_fame       int  not null check (total_fame >= 0),
  ports_reached    int  not null check (ports_reached >= 0),
  settled_at       timestamptz not null,
  primary key (board_slot, player_id)
);

comment on table public.standings is
  'THE TABLE OF CAPTAINS, settled once per standings_slot_seconds. Every figure here is what '
  'public.player_fame() said at that instant — this table RECORDS a standing, it never COMPUTES '
  'one, exactly as public.price_history records a price it does not derive. There is deliberately '
  'no purse, no cargo, no fleet and no port column: this is the one place another house''s figures '
  'exist in a shape a client could ever reach, so the shape IS the privacy decision.';
comment on column public.standings.rank_position is
  'rank() over (order by total_fame desc) — COMPETITION ranking. Two houses level on fame are both '
  '2nd and the next is 4th. row_number() would have invented an order between equals out of heap '
  'order; dense_rank() would have hidden how many people are level with you.';
comment on column public.standings.tied is
  'True when another house settled on the same total_fame in this slot. Served so a screen can '
  'print "=2" instead of pretending the tie was broken.';

alter table public.standings enable row level security;

-- NO POLICY AND NO GRANT, ON PURPOSE. The definer read below is the only door. A `select` grant
-- with a read-own policy would have been strictly WORSE than nothing here: it would let a browser
-- read its own row twice (once through the RPC, once through PostgREST) and give the privacy
-- decision two places to be stated.

create index if not exists standings_slot_position
  on public.standings (board_slot, rank_position);

-- ── 4. THE SETTLE ──────────────────────────────────────────────────────────────────────────────
create or replace function public.settle_standings(p_at timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot int := public.standings_slot_of(p_at);
  v_n    int;
begin
  -- Cheap exit first: if this slot is already photographed, do nothing at all. This is what makes
  -- the read O(board_size) for every caller but the first one in a slot.
  if exists (select 1 from public.standings where board_slot = v_slot) then
    return 0;
  end if;

  -- ONE pass over the houses, calling the ONE definition of fame (0014) ONCE each — the lateral is
  -- what keeps it to once — and nothing here re-derives a term of it.
  insert into public.standings (board_slot, player_id, rank_position, tied,
                                trade_fame, exploration_fame, total_fame, ports_reached, settled_at)
  select v_slot, r.player_id,
         rank() over (order by r.total desc)              as rank_position,
         (count(*) over (partition by r.total)) > 1       as tied,
         r.trade, r.exploration, r.total, r.ports, p_at
    from (
      select p.id as player_id,
             (fm.j->>'trade')::int         as trade,
             (fm.j->>'exploration')::int   as exploration,
             (fm.j->>'total')::int         as total,
             (fm.j->>'ports_reached')::int as ports
        from public.players p
       cross join lateral (select public.player_fame(p.id) as j) fm
    ) r
  on conflict (board_slot, player_id) do nothing;
  get diagnostics v_n = row_count;

  -- The record is a working set, not an archive. Prune outside the retention window.
  delete from public.standings
   where board_slot <= v_slot - public.wc_int('standings_slots_kept');

  return v_n;
end $$;

comment on function public.settle_standings(timestamptz) is
  'Photographs the table of captains for the current slot, if nobody has yet. O(houses), once per '
  'standings_slot_seconds, paid by whichever read arrives first — the read-is-the-catch-up idiom '
  'voyage.settle established (0009). Idempotent within a slot in both directions: the second call '
  'writes 0 rows and changes nothing.';

revoke all on function public.settle_standings(timestamptz) from public, anon, authenticated;
grant execute on function public.settle_standings(timestamptz) to service_role;

-- ── 5. THE ONE PLACE ANOTHER HOUSE'S FIGURES CROSS THE WIRE ────────────────────────────────────
create or replace function world.standings(p_limit int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me    uuid := public.current_player_id();
  v_slot  int;
  v_size  int  := greatest(1, least(coalesce(p_limit, public.wc_int('standings_board_size')),
                                    public.wc_int('standings_board_size')));
  v_at    timestamptz;
  v_count int;
  v_mine  public.standings%rowtype;
begin
  -- THE READ IS THE CATCH-UP (0009). At most one caller per slot pays for this.
  perform public.settle_standings(now());
  v_slot := public.standings_slot_of(now());

  select min(s.settled_at), count(*) into v_at, v_count
    from public.standings s where s.board_slot = v_slot;

  if v_count = 0 then
    -- A STATE, not a refusal — 0014's precedent for "signed in with no house". A world with no
    -- houses in it has an empty board, and that is not a fault.
    return jsonb_build_object('board', '[]'::jsonb, 'you', null, 'houses', 0,
                              'settled_at', null, 'board_slot', v_slot,
                              'slot_seconds', public.wc_int('standings_slot_seconds'),
                              'board_size', v_size, 'season', null,
                              'why', 'No house has yet sailed under a flag anyone is counting.');
  end if;

  select * into v_mine from public.standings s
   where s.board_slot = v_slot and s.player_id = v_me;

  return jsonb_build_object(
    -- WHEN it was settled, said plainly. A board is a photograph and the payload never pretends
    -- otherwise; your own figures on the same screen are live (world.player(), 0014).
    'settled_at',   v_at,
    'age_seconds',  round(extract(epoch from (now() - v_at)))::int,
    'board_slot',   v_slot,
    'slot_seconds', public.wc_int('standings_slot_seconds'),
    'houses',       v_count,
    'board_size',   v_size,
    -- Stated rather than implied: this board is of ALL TIME, because nothing in this chain records
    -- a season boundary (DESIGN I.5 wants one).
    'season',       null,
    'board', (
      select coalesce(jsonb_agg(b.card order by b.rank_position, b.company_name), '[]'::jsonb)
        from (
          select s.rank_position, pl.company_name,
                 jsonb_build_object(
                   -- ── THE ONLY THINGS A CAPTAIN MAY LEARN ABOUT ANOTHER CAPTAIN ──────────────
                   'position',         s.rank_position,
                   'tied',             s.tied,
                   'company_name',     pl.company_name,
                   'nation',           n.code,
                   'trade_fame',       s.trade_fame,
                   'exploration_fame', s.exploration_fame,
                   'total_fame',       s.total_fame,
                   'ports_reached',    s.ports_reached,
                   'is_you',           (s.player_id = v_me)
                   -- ── AND NOTHING ELSE. No ducats, no fleets, no ships, no port, no ledger. ──
                 ) as card
            from public.standings s
            join public.players pl on pl.id = s.player_id
            left join public.nations n on n.id = pl.nation_id
           where s.board_slot = v_slot
           order by s.rank_position, pl.company_name
           limit v_size) b),
    -- Where YOU stand, whether or not you are on the board. Without this a ten-row board is a
    -- screen that says nothing at all to the 190th captain.
    'you', case when v_mine.player_id is null then null else jsonb_build_object(
             'position',         v_mine.rank_position,
             'tied',             v_mine.tied,
             'trade_fame',       v_mine.trade_fame,
             'exploration_fame', v_mine.exploration_fame,
             'total_fame',       v_mine.total_fame,
             'ports_reached',    v_mine.ports_reached,
             'on_board',         (v_mine.rank_position <= v_size)) end);
end $$;

comment on function world.standings(int) is
  'THE table of captains, and the ONE place another house''s figures cross the wire. Serves a '
  'name, a nation, a standing and the fames the standing is computed from — never a purse, a '
  'cargo, a fleet, a port or a ledger line. Settles the current slot if it is missing and then '
  'reads it, so it is O(board_size) for every caller but the first in each five-minute slot.';

revoke all on function world.standings(int) from public, anon;
grant execute on function world.standings(int) to authenticated;

-- ── 6. THE CLIENT ENTRY POINTS — SUPERSEDES 0022's LIST ───────────────────────────────────────
-- One row added. 0018's rule stands: this list and src/lib/rpc/catalog.ts are one statement of
-- what a browser may call, and client_executable_writers() subtracts it, so granted and sanctioned
-- cannot drift.
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
      ('world',       'trade_routes',        'uuid, uuid, int, int, uuid'),
      ('world',       'haggle_state',        'uuid, uuid'),
      -- 0025: the table of captains. src/lib/rpc/catalog.ts names it `worldStandings`.
      ('world',       'standings',           'int'),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int'),
      ('cmd',         'preview',             'uuid, text'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text'),
      ('cmd',         'haggle',              'uuid, uuid, text')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_a constant uuid := '00000000-0025-4000-8000-00000000000a';
  c_b constant uuid := '00000000-0025-4000-8000-00000000000b';
  c_c constant uuid := '00000000-0025-4000-8000-00000000000c';
  c_none constant uuid := '00000000-0025-4000-8000-00000000000f';   -- signed in, no house
  -- The sanctioned key set of a board row, stated ONCE, here. If a future edit adds a key to
  -- world.standings() this assert goes red, which is exactly why it is written down.
  c_keys constant text[] := array['company_name', 'exploration_fame', 'is_you', 'nation',
                                  'ports_reached', 'position', 'tied', 'total_fame', 'trade_fame'];
  c_bounty constant bigint := 123457;   -- a purse nothing else in this world would produce
  v_a uuid; v_b uuid; v_c uuid;
  v_fa uuid; v_fb uuid; v_fc uuid;
  v_pre_rows int;
  v_drift    int;
  v_slot     int;
  v_wrote    int;
  v_again    int;
  v_board    jsonb;
  v_row      jsonb;
  v_txt      text;
  v_purse_b  bigint;
  v_pos_a    int;  v_pos_b int;  v_pos_c int;
  v_tied_a   boolean; v_tied_c boolean;
  v_state    text;
  v_left     int;
  v_n        int;
  v_houses   int;
  v_rls      boolean;
  v_good     uuid;
  v_port     uuid;
  -- findings recorded inside the throwaway subtransaction and read after it is gone
  f_noop      boolean := false;
  f_board     boolean := false;
  f_ties      boolean := false;
  f_bounded   boolean := false;
  f_private   boolean := false;
  f_keys      boolean := false;
  f_you       boolean := false;
  f_houseless boolean := false;
  f_composed  boolean := false;
  f_pruned    boolean := false;
  f_grant     boolean := false;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) THE ECONOMY DID NOT MOVE. This file touches no pricing function, and that claim is a
  --     COMPARISON rather than a sentence: real quotes taken before any of it ran, re-taken now,
  --     in the same transaction and therefore against the same clock and the same drift.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select count(*) into v_pre_rows from quote_before_0025;
  if v_pre_rows < 60 then
    raise exception '0025 self-assert FAIL: the quote pre-image holds only % row(s); the no-op comparison below would be nearly vacuous', v_pre_rows;
  end if;
  select count(*) into v_drift
    from quote_before_0025 b
    cross join lateral world.quote(b.port_id, b.good_id, b.qty, b.side) a
   where (a.units, a.total, a.avg_price, a.end_stock)
         is distinct from (b.units, b.total, b.avg_price, b.end_stock);
  if v_drift = 0 then f_noop := true; end if;

  -- Posture that needs no probe: the record is RLS-protected and belongs to nobody.
  select relrowsecurity into v_rls from pg_class where oid = 'public.standings'::regclass;
  if not v_rls then
    raise exception '0025 self-assert FAIL: RLS is not enabled on public.standings';
  end if;
  if (select count(*) from pg_policy where polrelid = 'public.standings'::regclass) <> 0 then
    raise exception '0025 self-assert FAIL: public.standings carries a policy; the definer read is meant to be the only door';
  end if;

  select count(*) into v_houses from public.players;

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────

    -- THREE HOUSES, and their fame EARNED rather than borrowed: this probe owns its preconditions.
    v_a := public.new_house(c_a, 'Casa Primeira 0025', 'PRT');
    v_b := public.new_house(c_b, 'Casa Segunda 0025',  'PRT');
    v_c := public.new_house(c_c, 'Casa Terceira 0025', 'PRT');
    select f.id, f.port_id into v_fa, v_port from public.fleets f where f.player_id = v_a;
    select f.id into v_fb from public.fleets f where f.player_id = v_b;
    select f.id into v_fc from public.fleets f where f.player_id = v_c;

    -- Fame is DERIVED from the ledger, so the only honest way to give a house fame is to make her
    -- trade. FIND the subject deterministically — a good this port actually holds and trades —
    -- rather than picking one out of heap order (0014:248-258).
    select pg.good_id into v_good
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports p on p.id = pg.port_id
     where pg.port_id = v_port and pg.stock > 200 and not (p.culture = any(g.culture_mask))
     order by g.code limit 1;
    if v_good is null then
      raise exception '0025 self-assert FAIL: the starting port holds no tradeable good with stock, so every probe below would be vacuous';
    end if;

    -- A buys twice, C once, B never: a STRICT order, produced by playing the game rather than by
    -- writing fame into a table.
    perform cmd.do_buy(v_fa, jsonb_build_object('good', v_good::text, 'qty', 20));
    perform cmd.do_buy(v_fa, jsonb_build_object('good', v_good::text, 'qty', 20));
    perform cmd.do_buy(v_fc, jsonb_build_object('good', v_good::text, 'qty', 20));

    -- (b) THE BOARD RECORDS THE LEDGER'S ANSWER, IT DOES NOT COMPUTE A SECOND ONE. Every settled
    --     figure must equal public.player_fame() recomputed right now, for every house on the
    --     board — that is what makes this a CALLER of 0014 and not a second author of fame.
    delete from public.standings;
    perform cmd.assume_identity(c_a);
    v_board := world.standings(null);
    v_slot  := (v_board->>'board_slot')::int;
    select count(*) into v_n from public.standings s
     where s.board_slot = v_slot
       and (s.trade_fame, s.exploration_fame, s.total_fame, s.ports_reached)
           is distinct from ((public.player_fame(s.player_id)->>'trade')::int,
                             (public.player_fame(s.player_id)->>'exploration')::int,
                             (public.player_fame(s.player_id)->>'total')::int,
                             (public.player_fame(s.player_id)->>'ports_reached')::int);
    if v_n = 0 then f_composed := true; end if;

    select s.rank_position into v_pos_a from public.standings s where s.board_slot = v_slot and s.player_id = v_a;
    select s.rank_position into v_pos_b from public.standings s where s.board_slot = v_slot and s.player_id = v_b;
    select s.rank_position into v_pos_c from public.standings s where s.board_slot = v_slot and s.player_id = v_c;
    if (v_board->>'houses')::int = v_houses + 3
       and v_pos_a < v_pos_c and v_pos_c < v_pos_b
       and (v_board->>'settled_at') is not null
       and (v_board->>'age_seconds') is not null
       and (v_board->'season') = 'null'::jsonb
       and (v_board->>'slot_seconds')::int = public.wc_int('standings_slot_seconds') then
      f_board := true;
    end if;

    -- (c) YOUR OWN STANDING IS SERVED EVEN WHEN THE BOARD IS TOO SHORT TO HOLD YOU — the case a
    --     ten-row board has for the 190th captain, asked here with a board of ONE.
    perform cmd.assume_identity(c_b);
    v_board := world.standings(1);
    if jsonb_array_length(v_board->'board') = 1
       and (v_board->'you'->>'position')::int = v_pos_b
       and (v_board->'you'->>'total_fame')::int = (public.player_fame(v_b)->>'total')::int
       and (v_board->'you'->>'on_board')::boolean is false
       and not ((v_board->'board'->0->>'is_you')::boolean) then
      f_you := true;
    end if;

    -- (d) AND A SIGNED-IN ACCOUNT WITH NO HOUSE READS A STATE, NOT A REFUSAL (0014's rule). This
    --     is the branch a live world can actually reach; the houses = 0 branch cannot be reached
    --     at all once anybody has founded a house, and is reported separately below.
    perform cmd.assume_identity(c_none);
    v_board := world.standings(null);
    if (v_board->'you') = 'null'::jsonb
       and jsonb_array_length(v_board->'board') >= 1
       and (v_board->>'houses')::int = v_houses + 3 then
      f_houseless := true;
    end if;

    -- (e) TIES ARE HONEST, and made honest by CONSTRUCTION rather than by hoping two houses come
    --     out level: settle a board whose totals are equal and require COMPETITION ranking — two
    --     firsts, and the next captain THIRD, not second.
    delete from public.standings;
    insert into public.standings (board_slot, player_id, rank_position, tied, trade_fame,
                                  exploration_fame, total_fame, ports_reached, settled_at)
    select public.standings_slot_of(now()), r.player_id,
           rank() over (order by r.total desc),
           (count(*) over (partition by r.total)) > 1,
           r.total, 0, r.total, 0, now()
      from (values (v_a, 500), (v_c, 500), (v_b, 100)) r(player_id, total);
    perform cmd.assume_identity(c_a);
    v_board := world.standings(null);
    select s.rank_position, s.tied into v_pos_a, v_tied_a from public.standings s
     where s.player_id = v_a and s.board_slot = public.standings_slot_of(now());
    select s.rank_position, s.tied into v_pos_c, v_tied_c from public.standings s
     where s.player_id = v_c and s.board_slot = public.standings_slot_of(now());
    select s.rank_position into v_pos_b from public.standings s
     where s.player_id = v_b and s.board_slot = public.standings_slot_of(now());
    if v_pos_a = 1 and v_pos_c = 1 and v_tied_a and v_tied_c and v_pos_b = 3
       and (v_board->'board'->0->>'tied')::boolean then
      f_ties := true;
    end if;

    -- (f) THE READ DOES NOT RE-PHOTOGRAPH THE WORLD. Idempotence claimed in one direction is half
    --     a claim (0010's standard): the first settle in a fresh slot writes one row per house and
    --     the second call in the same slot writes ZERO.
    delete from public.standings;
    v_wrote := public.settle_standings(now());
    v_again := public.settle_standings(now());
    if v_wrote = v_houses + 3 and v_again = 0 then f_bounded := true; end if;

    -- (g) AND THE RECORD IS PRUNED, proven by ageing a board on purpose rather than by waiting.
    delete from public.standings;
    insert into public.standings (board_slot, player_id, rank_position, tied, trade_fame,
                                  exploration_fame, total_fame, ports_reached, settled_at)
    values (public.standings_slot_of(now()) - public.wc_int('standings_slots_kept') - 1,
            v_a, 1, false, 0, 0, 0, 0, now());
    perform public.settle_standings(now());
    if not exists (select 1 from public.standings s
                    where s.board_slot <= public.standings_slot_of(now())
                                          - public.wc_int('standings_slots_kept')) then
      f_pruned := true;
    end if;

    -- (h) THE PRIVACY DECISION HOLDS, BEHAVIOURALLY AND STRUCTURALLY.
    --     Behaviourally: give B a purse nothing else in this world would produce and require its
    --     digits ABSENT from the whole serialised board A reads — the technique 0009 used for the
    --     world secret, which searches for the VALUE rather than trusting a list of key names.
    --     Structurally: every row's key set must equal the sanctioned list.
    perform public.credit(v_b, 'PROBE_0025', c_bounty,
                          public.emit_event(v_b, 'PROBE_0025', '{}'::jsonb));
    select pl.ducats into v_purse_b from public.players pl where pl.id = v_b;
    perform cmd.assume_identity(c_a);
    delete from public.standings;
    v_board := world.standings(null);
    v_txt   := v_board::text;
    if strpos(v_txt, v_purse_b::text) = 0
       and strpos(v_txt, 'ducats') = 0
       and strpos(v_txt, 'auth_uid') = 0
       and strpos(v_txt, 'fleet') = 0
       and strpos(v_txt, 'company_level') = 0 then
      f_private := true;
    end if;

    f_keys := (jsonb_array_length(v_board->'board') >= 3);
    for v_row in select value from jsonb_array_elements(v_board->'board') loop
      if (select array_agg(k order by k) from jsonb_object_keys(v_row) k) is distinct from c_keys then
        f_keys := false;
      end if;
    end loop;

    -- ... and the table itself is unreachable by either client role. Not a catalogue read: BE the
    -- role and try, requiring SQLSTATE 42501 specifically (proof 03's standard).
    begin
      execute 'set local role authenticated';
      begin
        perform 1 from public.standings;
        f_private := false;   -- it answered. The wall is not there.
      exception when others then
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then f_private := false; end if;
      end;
      execute 'set local role none';
    exception when others then
      execute 'set local role none'; raise;
    end;

    raise exception '__PROBE_ROLLBACK_0025__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0025__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survived it, because plpgsql variables are not
  --    transactional. Assert on them now. ────────────────────────────────────────────────────────

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if not f_noop then
    raise exception '0025 self-assert FAIL: % of % pre-image quote(s) moved. This file adds a READ and was not allowed to touch the economy at all', v_drift, v_pre_rows;
  end if;
  if not f_composed then
    raise exception '0025 self-assert FAIL: % settled row(s) disagree with public.player_fame() recomputed at read time — the board is COMPUTING fame instead of recording what the one authority said', v_n;
  end if;
  if not f_board then
    raise exception '0025 self-assert FAIL: three houses with a strict fame order did not settle in that order (% then % then %), or the payload did not carry settled_at, age_seconds, a null season and the slot length', v_pos_a, v_pos_c, v_pos_b;
  end if;
  if not f_you then
    raise exception '0025 self-assert FAIL: a captain off the end of a one-row board was not told her own standing, or that standing disagreed with public.player_fame, or the board''s only row claimed to be her';
  end if;
  if not f_houseless then
    raise exception '0025 self-assert FAIL: a signed-in account with no house did not read back a board with you = null; a refusal there would make a normal state look like a fault';
  end if;
  if not f_ties then
    raise exception '0025 self-assert FAIL: two houses level on fame did not both settle 1st with tied = true and the third at position 3 — the board is inventing an order between equals';
  end if;
  if not f_bounded then
    raise exception '0025 self-assert FAIL: the settle wrote % row(s) then % on a repeat call in the same slot; a read that re-photographs the world on every open is O(houses) per tab open', v_wrote, v_again;
  end if;
  if not f_pruned then
    raise exception '0025 self-assert FAIL: a board older than standings_slots_kept survived a settle; the record would grow by (houses) rows every slot for ever';
  end if;
  if not f_private then
    raise exception '0025 self-assert FAIL: another house''s purse of % d., or a forbidden key, was reachable through the board — or public.standings answered a client role that should have been refused 42501', v_purse_b;
  end if;
  if not f_keys then
    raise exception '0025 self-assert FAIL: a board row''s keys are not exactly %, or fewer than three rows were examined; the hole cut in the read-own wall is only as small as this list', c_keys;
  end if;

  -- The empty-world branch. It CANNOT be reached once anybody has founded a house, so it is
  -- REPORTED rather than asserted where houses exist — 0010/0012's posture for an absent pg_cron,
  -- and the opposite of an assert that passes vacuously.
  if v_houses = 0 then
    v_board := world.standings(null);
    if jsonb_array_length(v_board->'board') <> 0 or (v_board->>'houses')::int <> 0
       or (v_board->'you') <> 'null'::jsonb or not (v_board ? 'why') then
      raise exception '0025 self-assert FAIL: a world with no houses did not read back an empty board as a STATE carrying its own explanation';
    end if;
    delete from public.standings;
    raise notice '0025: the world holds 0 house(s), so the empty-board branch WAS reachable and was asserted here.';
  else
    raise notice '0025: the world already holds % house(s), so the empty-board branch of world.standings() cannot be reached and was NOT asserted. It is asserted on every fresh chain.', v_houses;
  end if;

  -- The rollback really rolled back. NOT "the table is empty" — this chain deploys onto a live
  -- world with real houses in it — but "this probe left nothing of its own behind".
  select count(*) into v_left from public.players pl where pl.auth_uid in (c_a, c_b, c_c);
  if v_left <> 0 then
    raise exception '0025 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  select count(*) into v_left from public.standings;
  if v_left <> 0 then
    raise exception '0025 self-assert FAIL: % settled row(s) were left committed by the probe', v_left;
  end if;
  if public.wc_int('standings_slot_seconds') <> 300 or public.wc_int('standings_board_size') <> 10 then
    raise exception '0025 self-assert FAIL: the probe left a knob moved — slot %, board %',
      public.wc_int('standings_slot_seconds'), public.wc_int('standings_board_size');
  end if;

  -- POSTURE. Exactly one new client entry point, and the machinery behind it unreachable.
  if has_function_privilege('authenticated', 'world.standings(int)', 'execute')
     and not has_function_privilege('anon', 'world.standings(int)', 'execute')
     and not has_function_privilege('authenticated', 'public.settle_standings(timestamptz)', 'execute')
     and not has_function_privilege('anon', 'public.settle_standings(timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public.standings_slot_of(timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public.player_fame(uuid)', 'execute')
     and not has_table_privilege('authenticated', 'public.standings', 'select')
     and not has_table_privilege('anon', 'public.standings', 'select')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0025 self-assert FAIL: world.standings is not exactly granted to authenticated and denied to anon, or the settle/slot/fame machinery leaked to a client, or public.standings became client-readable, or a catalogued entry point does not resolve, or a write/execute grant or a read-wall gap appeared';
  end if;

  raise notice '0025 self-assert ok: there is a table of captains, and it says a NAME, a NATION and a STANDING and nothing else — every board row''s keys are exactly %, a probe house''s purse of % d. is ABSENT from the whole serialised payload (searched for the VALUE, not trusted from a list of key names), and public.standings itself refuses both client roles with SQLSTATE 42501 and carries no policy at all, so the read-own wall 0023 rebuilt was not widened by one row; the standing is RECORDED, never computed — every settled row equals public.player_fame() recomputed at read time, so 0014 is still the ONE definition of fame; three houses with a strict order settled in that order, a captain off the end of a one-row board was still told exactly where she stands, and a signed-in account with no house read back a board with you = null rather than a refusal; ties are COMPETITION-ranked, proven by two houses level on fame settling BOTH first with tied = true and the third at position 3, not 2; the read is BOUNDED — the first call in a slot wrote % row(s) and the second wrote %, so opening RANK costs two index lookups for every captain but the first in each % second slot, and a board older than % slot(s) is pruned; the economy is BYTE-IDENTICAL across % real quotes taken before this file ran, of which % moved; and the 1 new entry point is granted to authenticated, denied to anon, with the settle, the slot authority and player_fame unreachable by any client, 0 client write grants, 0 client-executable writers and 0 read-wall gaps',
    c_keys, v_purse_b, v_wrote, v_again,
    public.wc_int('standings_slot_seconds'), public.wc_int('standings_slots_kept'),
    v_pre_rows, v_drift;
end $$;

drop table quote_before_0025;
