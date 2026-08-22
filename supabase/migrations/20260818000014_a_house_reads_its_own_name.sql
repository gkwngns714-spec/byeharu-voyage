-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0014 — A HOUSE READS ITS OWN NAME: the player row crosses the wire, and fame is DERIVED
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ────────────────────────────────────────────────────────────────────────
--   "do the migrations - price history, player row, officers, skills"
--
-- ── THE HOLE THIS FILLS ────────────────────────────────────────────────────────────────────────
-- `public.players` has existed since 0004 with the house's name, nation, purse, company_level and
-- title_level. NOTHING HAS EVER SERVED IT. The read surface (0009) is snapshot / market / fleets /
-- ledger, and the only player fact any of them carries is `ledger().ducats`.
--
--   src/lib/db/README.md §4    "A PROFILE/RANK screen cannot be driven by V0 RPCs."
--   docs/UI_DIRECTION.md §5    names "no player row" as the biggest of the server gaps.
--   RankScreen.tsx (D12c)      says so on screen: the client can say what you are worth, and
--                              cannot say what that is worth relative to anyone.
--
-- This closes the first half — a house can read itself. It does NOT close the second half: there is
-- still no standings table, because a table of captains needs a rule about who may see whose
-- figures, and that is a design decision rather than a missing SELECT (see §K.1 / I.4).
--
-- ── FAME IS DERIVED, NOT COUNTED ───────────────────────────────────────────────────────────────
-- The obvious shape is a `fame` column that every verb increments. It is the wrong one, twice over:
--
--   1. The verbs live in 0007 and 0007 IS DEPLOYED. Adding an increment to each of them means
--      re-cutting a migration that has run, which this chain does not do.
--   2. A counter is a second authority for something the ledger already knows. `events` is
--      append-only and is, in I.4's words, "the source of truth from which rank is computed".
--      A stored total can drift from it; a derived one cannot, and it is retroactively correct for
--      every voyage already sailed.
--
-- So fame is a READING of the record, in the same spirit as 0005's "every price is derived, never
-- stored". The weights are knobs, not literals, so tuning fame is a config change and not a
-- migration.
--
--   trade fame       — ducats TURNED OVER on BOUGHT/SOLD, divided by fame_ducats_per_point.
--                      Turnover, not profit: profit is already the purse, and rewarding it twice
--                      would make fame a second scoreboard for the same thing. Turnover says how
--                      much of the world's business went through your hands.
--   exploration fame — distinct ports arrived at, times fame_per_port. A port is reached once;
--                      sailing back and forth between two of them is trade, not exploration.
--
-- ── WHAT IS DELIBERATELY NOT HERE ──────────────────────────────────────────────────────────────
-- No title ladder. `players.title_level` exists and nothing in the chain moves it; inventing a
-- mapping from fame to a title here would be an authored rule with no design behind it yet. The
-- number is served; naming its bands is a later decision.
--
-- Depends ONLY on: 0001-0013 (players/events 0004, current_player_id 0004, nations 0002-0003).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('fame_ducats_per_point', to_jsonb(100),
   'How many ducats of TURNOVER (the absolute value moved on a BOUGHT or SOLD event) make one point of trade fame. Turnover rather than profit: profit is the purse, and paying fame for it too would score one thing twice.'),
  ('fame_per_port', to_jsonb(25),
   'Exploration fame for each DISTINCT port a house has arrived at. A port is reached once; sailing between two of them for ever is trade, not exploration.')
on conflict (key) do nothing;

-- ── FAME, THE ONE READING ──────────────────────────────────────────────────────────────────────
create or replace function public.player_fame(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_per_ducat numeric := public.wc_num('fame_ducats_per_point');
  v_per_port  numeric := public.wc_num('fame_per_port');
  v_turnover  numeric := 0;
  v_ports     int     := 0;
  v_trade     int;
  v_explore   int;
begin
  if p_player is null then
    return jsonb_build_object('trade', 0, 'exploration', 0, 'total', 0, 'ports_reached', 0, 'turnover', 0);
  end if;

  -- Turnover is read off the LEDGER's own movements, not off a payload field, so a verb that one
  -- day writes a differently-shaped payload still counts correctly.
  select coalesce(sum(abs(l.ducats_delta)), 0) into v_turnover
    from public.ledger l
    join public.events e on e.id = l.ref_event_id
   where l.player_id = p_player
     and e.kind in ('BOUGHT', 'SOLD');

  select count(distinct e.payload->>'to') into v_ports
    from public.events e
   where e.player_id = p_player
     and e.kind = 'VOYAGE_REPORT'
     and e.payload ? 'to';

  v_trade   := floor(v_turnover / nullif(v_per_ducat, 0))::int;
  v_explore := (v_ports * v_per_port)::int;

  return jsonb_build_object(
    'trade', v_trade,
    'exploration', v_explore,
    'total', v_trade + v_explore,
    'ports_reached', v_ports,
    'turnover', v_turnover);
end $$;

comment on function public.player_fame(uuid) is
  'THE ONE definition of fame. Derived from the append-only record every time it is asked, never '
  'stored — so it cannot drift from the ledger it is computed from, and it is retroactively right '
  'for voyages sailed before this migration existed.';

revoke all on function public.player_fame(uuid) from public, anon, authenticated;

-- ── THE READ ───────────────────────────────────────────────────────────────────────────────────
-- It takes NO id, for the same reason cmd.found_house() takes no uid (0011): identity comes from
-- the JWT, so a caller can only ever read their own house. That is structural, not checked.
create or replace function world.player()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_id     uuid := public.current_player_id();
  v_row    public.players%rowtype;
  v_nation record;
  v_fleets int;
  v_ships  int;
  v_port   text;
begin
  if v_id is null then
    -- NOT an error. "Signed in with no house" is a real and expected state — it is exactly what
    -- the register screen exists for (0011) — and a refusal here would make a normal state look
    -- like a fault.
    return jsonb_build_object('player', null);
  end if;

  select * into v_row from public.players where id = v_id;

  select n.code as code, n.name as name into v_nation
    from public.nations n where n.id = v_row.nation_id;

  select count(*) into v_fleets from public.fleets f where f.player_id = v_id;
  select count(*) into v_ships  from public.ships  s where s.player_id = v_id;

  -- Where the house keeps its books: the port its FIRST fleet lies in, or null while every fleet
  -- is at sea. There is no "home port" in this game (a port is a place, not a base), so this is
  -- reported as what it is — where she is lying — and named accordingly.
  select p.code into v_port
    from public.fleets f
    join public.ports p on p.id = f.port_id
   where f.player_id = v_id and f.port_id is not null
   order by f.created_at
   limit 1;

  return jsonb_build_object(
    'player', jsonb_build_object(
      'id',            v_row.id,
      'company_name',  v_row.company_name,
      'nation',        v_nation.code,
      'nation_name',   v_nation.name,
      'ducats',        v_row.ducats,
      'company_level', v_row.company_level,
      'title_level',   v_row.title_level,
      'founded_at',    v_row.created_at,
      'fleets',        v_fleets,
      'ships',         v_ships,
      'lying_at',      v_port,
      'fame',          public.player_fame(v_id)));
end $$;

comment on function world.player() is
  'The signed-in house, reading itself. Takes no id — identity is the JWT''s (see cmd.found_house, '
  '0011) — and returns {"player": null} for a signed-in account that has not signed the book yet, '
  'because that is a state and not a fault.';

revoke all on function world.player() from public, anon;
grant execute on function world.player() to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe   constant uuid := '00000000-0014-4000-8000-000000000001';
  v_none    jsonb;
  v_out     jsonb;
  v_p       jsonb;
  v_fame0   jsonb;
  v_fame1   jsonb;
  v_player  uuid;
  v_fleet   uuid;
  v_good    uuid;
  v_port    uuid;
  v_anon_x  boolean;
  v_auth_x  boolean;
  v_players int;
  v_grants  int;
  v_turn    numeric;
  v_buy     jsonb;
  v_expect  int;
begin
  v_anon_x := has_function_privilege('anon', 'world.player()', 'execute');
  v_auth_x := has_function_privilege('authenticated', 'world.player()', 'execute');
  if v_anon_x then raise exception '0014 self-assert FAIL: anon may execute world.player() — a house is not public'; end if;
  if not v_auth_x then raise exception '0014 self-assert FAIL: authenticated may NOT execute world.player() — no captain could read their own house'; end if;
  if has_function_privilege('authenticated', 'public.player_fame(uuid)', 'execute') then
    raise exception '0014 self-assert FAIL: authenticated may execute player_fame(uuid) — it takes an id, so a client could read another house''s fame';
  end if;

  begin
    -- (a) signed in, no house: a STATE, not a refusal.
    perform cmd.assume_identity(v_probe);
    v_none := world.player();
    if v_none->'player' <> 'null'::jsonb then
      raise exception '0014 self-assert FAIL: an account with no house did not read back {"player": null}: %', v_none;
    end if;

    -- (b) a house reads itself, and every field is the row's own.
    v_player := public.new_house(v_probe, 'Casa do Espelho', 'PRT');
    v_out := world.player();
    v_p := v_out->'player';
    if v_p is null or v_p = 'null'::jsonb then
      raise exception '0014 self-assert FAIL: a founded house read back no player';
    end if;
    if (v_p->>'company_name') <> 'Casa do Espelho' then
      raise exception '0014 self-assert FAIL: read back the name "%"', v_p->>'company_name';
    end if;
    if (v_p->>'nation') <> 'PRT' then
      raise exception '0014 self-assert FAIL: read back nation "%" for a house founded under PRT', v_p->>'nation';
    end if;
    if (v_p->>'ducats')::bigint <> public.wc_int('starting_ducats') then
      raise exception '0014 self-assert FAIL: read back % ducats against a starting purse of %', v_p->>'ducats', public.wc_int('starting_ducats');
    end if;
    if (v_p->>'ships')::int <> 1 or (v_p->>'fleets')::int <> 1 then
      raise exception '0014 self-assert FAIL: read back % fleet(s) and % ship(s), expected 1 and 1', v_p->>'fleets', v_p->>'ships';
    end if;
    if (v_p->>'lying_at') is null then
      raise exception '0014 self-assert FAIL: a house whose only fleet is docked read back no port';
    end if;

    -- (c) fame opens at ZERO. Without this the next step could not prove anything moved.
    v_fame0 := v_p->'fame';
    if (v_fame0->>'total')::int <> 0 then
      raise exception '0014 self-assert FAIL: a house that has traded nothing opened with % fame', v_fame0->>'total';
    end if;

    -- (d) THE POSITIVE CONTROL. Trade once, and require fame to move BY THE DEFINED AMOUNT — not
    --     merely to be non-zero. A weight read from the wrong knob would still be "non-zero".
    select f.id into v_fleet from public.fleets f where f.player_id = v_player limit 1;
    select p.id into v_port from public.ports p join public.fleets f on f.port_id = p.id
      where f.id = v_fleet;
    -- THIS PICK WAS A LOTTERY, AND IT LOST. It read `... where pg.stock > 50 limit 1` with NO
    -- ORDER BY, so which good the probe bought depended on heap order — which varies between runs
    -- because the seed writes rows keyed by gen_random_uuid(). Draw a good this port's culture
    -- refuses, or one whose 10 tuns the opening purse cannot cover, and the BUY does nothing, and
    -- the assert below fires on a control that was never given a chance to work. It passed twice on
    -- 2026-08-22 and failed on the third run, on an unchanged chain.
    --
    -- Same defect class as D11h's drift assert: "the assert was a lottery on one row". The fix is
    -- the same one — make the probe DETERMINISTIC and make it satisfy its own preconditions:
    -- ordered by code so every run picks the same good, `available` so the culture will trade it,
    -- and cheap enough that 10 tuns fit the opening purse with room to spare.
    select pg.good_id into v_good
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
     where pg.port_id = v_port
       and pg.stock > 50
       and not ((select p.culture from public.ports p where p.id = v_port) = any(g.culture_mask))
       and (select ask from world.price(v_port, pg.good_id)) * 10 < public.wc_int('starting_ducats') / 2
     order by g.code
     limit 1;
    if v_good is null then
      raise exception '0014 self-assert FAIL: the starting port stocks no good this house could both trade and afford, so the fame control could not run';
    end if;

    -- AND THE BUY MUST BE SEEN TO WORK. `perform` discarded the result, so a refusal arrived as the
    -- silent "no ducats moved" failure below instead of as the reason. Read the answer and say it.
    v_buy := cmd.issue(v_fleet, format('BUY %s 10', (select code from public.goods where id = v_good)));
    if (v_buy->>'ok') is distinct from 'true' then
      raise exception '0014 self-assert FAIL: the probe BUY was refused, so the fame control could not run: %', v_buy;
    end if;

    select coalesce(sum(abs(l.ducats_delta)), 0) into v_turn
      from public.ledger l join public.events e on e.id = l.ref_event_id
     where l.player_id = v_player and e.kind in ('BOUGHT', 'SOLD');
    if v_turn <= 0 then
      raise exception '0014 self-assert FAIL: a BUY moved no ducats, so the fame control is vacuous';
    end if;

    v_fame1 := public.player_fame(v_player);
    v_expect := floor(v_turn / public.wc_num('fame_ducats_per_point'))::int;
    if (v_fame1->>'trade')::int <> v_expect then
      raise exception '0014 self-assert FAIL: turnover of % d. at % d./point gave % trade fame, expected %',
        v_turn, public.wc_num('fame_ducats_per_point'), v_fame1->>'trade', v_expect;
    end if;
    if (v_fame1->>'trade')::int = 0 then
      raise exception '0014 self-assert FAIL: the trade after a real purchase still scored 0 fame — the control cannot bite';
    end if;

    -- (e) exploration fame is 0 until a voyage is REPORTED. A house that has never arrived
    --     anywhere has reached nowhere, and this proves the two fames are independent.
    if (v_fame1->>'exploration')::int <> 0 then
      raise exception '0014 self-assert FAIL: a house that has never completed a voyage has % exploration fame', v_fame1->>'exploration';
    end if;
    if (v_fame1->>'total')::int <> (v_fame1->>'trade')::int + (v_fame1->>'exploration')::int then
      raise exception '0014 self-assert FAIL: total fame is not the sum of its parts: %', v_fame1;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_players from public.players;
  if v_players <> 0 then
    raise exception '0014 self-assert FAIL: the probe left % player(s) behind', v_players;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0014 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0014 self-assert ok: world.player() takes no id and reads auth.uid(); anon may not execute it and authenticated may, while player_fame(uuid) is server-only; a signed-in account with no house reads back {"player": null} rather than a refusal; a founded house read back its own name, nation, purse (% d.), 1 fleet and 1 ship, and the port she lies in; fame opened at 0 and a real purchase of turnover % d. scored EXACTLY % trade fame at % d./point, with exploration still 0 because nothing has arrived anywhere; probe rolled back leaving 0 players; 0 client write grants',
    public.wc_int('starting_ducats'), v_turn, v_expect, public.wc_num('fame_ducats_per_point');
end $$;
