-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0011 — A CAPTAIN SIGNS THE BOOK: the one way a signed-in player gets a house
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE HOLE THIS FILLS ────────────────────────────────────────────────────────────────────────
-- The game has only ever been played in LOCAL mode, and that hid a gap big enough to make cloud
-- mode unplayable: THERE WAS NO WAY FOR A SIGNED-IN PLAYER TO EVER GET A HOUSE.
--
--   public.new_house(p_auth_uid, name, nation)   founds everything — the house, the 8,000 ducats,
--                                                the Barca at Lisboa, the opening ledger entry.
--   0004, line 342                               `revoke all ... from public, anon, authenticated`
--
-- and that revoke is CORRECT and permanent: new_house takes a uid as an argument, so a client that
-- could call it could found a house for somebody else's account. The only caller was
-- src/lib/db/localDb.ts, seeding the single local captain on first boot. Sign in to a real project
-- and you would land on an empty world: no fleet, no purse, no ledger, and nothing you could press
-- to fix it.
--
-- ── WHAT THIS ADDS, AND WHY IT IS SHAPED THIS WAY ──────────────────────────────────────────────
-- `cmd.found_house(name, nation)` — and note what is NOT in that signature. IT TAKES NO UID. It
-- reads `auth.uid()` itself, so the identity is the JWT's and cannot be passed in, spoofed, or
-- mistyped. That is the whole security property, and it is structural rather than checked.
--
-- IT RESTATES NO RULE THAT ALREADY EXISTS. `public.players` already carries:
--
--   auth_uid     uuid unique                                        -> one house per account
--   company_name text not null unique
--                check (length(btrim(company_name)) between 3 and 24)
--
-- so this function does not re-implement "is the name taken", "is it too short", or "does this
-- account already have a house". It lets the table's own constraints bite and TRANSLATES the
-- SQLSTATE into the refusal vocabulary the client already speaks (DESIGN F.5: a code, a sentence,
-- and at least one fix). Two authorities for "is this name legal" would drift; there is one, and
-- it is the constraint.
--
-- The pre-check for an existing house is not a second authority either — it is the FRIENDLY path,
-- and `current_player_id()` (0004, "THE ONE translation from the JWT subject to a player id") is
-- what answers it. The unique index behind it is still what makes the rule true under a race.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function cmd.found_house(
  p_company_name text,
  p_nation_code  text default 'PRT'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_name   text := btrim(coalesce(p_company_name, ''));
  v_nation text := upper(btrim(coalesce(p_nation_code, 'PRT')));
  v_player uuid;
begin
  if v_uid is null then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no captain to give a house to.',
      'fixes', jsonb_build_array('(sign in, then name your house)'));
  end if;

  v_player := public.current_player_id();
  if v_player is not null then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_ALREADY_FOUNDED',
      'error_message', 'This account already keeps a house. A captain signs the book once.',
      'fixes', jsonb_build_array('(open the game — your fleet is already at sea or alongside)'));
  end if;

  if not exists (select 1 from public.nations where code = v_nation) then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_NO_SUCH_NATION',
      'error_message', format('No nation answers to "%s".', v_nation),
      'fixes', (select jsonb_agg(format('(sail under %s — %s)', code, name) order by code)
                  from public.nations));
  end if;

  -- The constraints on public.players are the authority. Let them bite, and say what they meant.
  begin
    v_player := public.new_house(v_uid, v_name, v_nation);
  exception
    when unique_violation then
      -- Which unique index? auth_uid means a second house raced this one in; company_name means
      -- the name is spoken for. Naming the constraint keeps the two answers from being confused.
      if position('players_auth_uid_key' in sqlerrm) > 0 then
        return jsonb_build_object(
          'ok', false, 'error_code', 'E_ALREADY_FOUNDED',
          'error_message', 'This account already keeps a house. A captain signs the book once.',
          'fixes', jsonb_build_array('(open the game — your fleet is already alongside)'));
      end if;
      return jsonb_build_object(
        'ok', false, 'error_code', 'E_NAME_TAKEN',
        'error_message', format('Another house already trades as "%s".', v_name),
        'fixes', jsonb_build_array('(choose another name)'));
    when check_violation then
      return jsonb_build_object(
        'ok', false, 'error_code', 'E_BAD_NAME',
        'error_message', 'A house name is 3 to 24 letters, and cannot be blank.',
        'fixes', jsonb_build_array('(try something between 3 and 24 characters)'));
  end;

  return jsonb_build_object(
    'ok', true,
    'player_id', v_player,
    'company_name', v_name,
    'nation', v_nation);
end $$;

comment on function cmd.found_house(text, text) is
  'THE ONE way a signed-in player gets a house. Takes NO uid — it reads auth.uid(), so a caller '
  'can only ever found their own. Composes the constraints already on public.players rather than '
  'restating them, and translates their SQLSTATE into a DESIGN F.5 refusal.';

-- Signing the book is something an AUTHENTICATED captain does. `anon` may read the world; it may
-- not open a house, or a crawler would found thousands.
revoke all on function cmd.found_house(text, text) from public, anon;
grant execute on function cmd.found_house(text, text) to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe   constant uuid := '00000000-0011-4000-8000-000000000001';
  v_probe2  constant uuid := '00000000-0011-4000-8000-000000000002';
  v_ok      jsonb;
  v_again   jsonb;
  v_taken   jsonb;
  v_short   jsonb;
  v_nation  jsonb;
  v_anon    jsonb;
  v_purse   bigint;
  v_ships   int;
  v_port    text;
  v_grants  int;
  v_anon_x  boolean;
  v_auth_x  boolean;
  v_players int;
begin
  -- Grants are a property of the FUNCTION, not of the probe, so they are read outside the
  -- rolled-back block: a revoke that never happened must fail this migration, not vanish with it.
  v_anon_x := has_function_privilege('anon', 'cmd.found_house(text, text)', 'execute');
  v_auth_x := has_function_privilege('authenticated', 'cmd.found_house(text, text)', 'execute');
  if v_anon_x then raise exception '0011 self-assert FAIL: anon may execute cmd.found_house — a crawler could found houses'; end if;
  if not v_auth_x then raise exception '0011 self-assert FAIL: authenticated may NOT execute cmd.found_house — no player could ever sign the book'; end if;

  begin
    -- (a) with nobody signed in, it refuses rather than founding an ownerless house.
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    v_anon := cmd.found_house('Casa Anonima', 'PRT');
    if (v_anon->>'error_code') is distinct from 'E_NOT_SIGNED_IN' then
      raise exception '0011 self-assert FAIL: an unsigned caller was not refused E_NOT_SIGNED_IN: %', v_anon;
    end if;

    -- (b) a captain signs the book, and gets exactly what DESIGN K.1 opens with.
    perform cmd.assume_identity(v_probe);
    v_ok := cmd.found_house('Casa do Livro', 'PRT');
    if not (v_ok->>'ok')::boolean then
      raise exception '0011 self-assert FAIL: founding refused: %', v_ok;
    end if;

    select p.ducats into v_purse from public.players p where p.id = (v_ok->>'player_id')::uuid;
    select count(*) into v_ships from public.ships s
      join public.fleets f on f.id = s.fleet_id
     where f.player_id = (v_ok->>'player_id')::uuid;
    select po.code into v_port from public.fleets f
      join public.ports po on po.id = f.port_id
     where f.player_id = (v_ok->>'player_id')::uuid;
    if v_purse <> public.wc_int('starting_ducats') then
      raise exception '0011 self-assert FAIL: opened with % ducats, expected %', v_purse, public.wc_int('starting_ducats');
    end if;
    if v_ships <> 1 or v_port <> 'LIS' then
      raise exception '0011 self-assert FAIL: opened with % ship(s) at %, expected 1 at LIS', v_ships, v_port;
    end if;

    -- (c) THE POSITIVE CONTROLS. Each of these must BITE, or the function is not enforcing it.
    v_again := cmd.found_house('Casa Segunda', 'PRT');
    if (v_again->>'error_code') is distinct from 'E_ALREADY_FOUNDED' then
      raise exception '0011 self-assert FAIL: a second house on one account was not refused: %', v_again;
    end if;

    perform cmd.assume_identity(v_probe2);
    v_taken := cmd.found_house('Casa do Livro', 'PRT');
    if (v_taken->>'error_code') is distinct from 'E_NAME_TAKEN' then
      raise exception '0011 self-assert FAIL: a duplicate house name was not refused: %', v_taken;
    end if;

    v_short := cmd.found_house('  x  ', 'PRT');
    if (v_short->>'error_code') is distinct from 'E_BAD_NAME' then
      raise exception '0011 self-assert FAIL: a 1-character house name was not refused: %', v_short;
    end if;

    v_nation := cmd.found_house('Casa Sem Bandeira', 'ZZZ');
    if (v_nation->>'error_code') is distinct from 'E_NO_SUCH_NATION' then
      raise exception '0011 self-assert FAIL: an unknown nation was not refused: %', v_nation;
    end if;
    if jsonb_array_length(v_nation->'fixes') < 1 then
      raise exception '0011 self-assert FAIL: E_NO_SUCH_NATION carried no fix (DESIGN F.5)';
    end if;

    -- ...and after all four refusals, the second captain still has no house. A refusal that
    -- half-founded one would leave a purse with no ledger behind it.
    perform cmd.assume_identity(v_probe2);
    if public.current_player_id() is not null then
      raise exception '0011 self-assert FAIL: a refused founding still left a house standing';
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_players from public.players;
  if v_players <> 0 then
    raise exception '0011 self-assert FAIL: the probe left % player(s) behind', v_players;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0011 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0011 self-assert ok: cmd.found_house() takes NO uid and reads auth.uid(); anon may not execute it and authenticated may; an unsigned caller is refused E_NOT_SIGNED_IN; a captain opened Casa do Livro with % d. and 1 ship at LIS; and four positive controls all BIT — a second house on one account (E_ALREADY_FOUNDED), a name already trading (E_NAME_TAKEN), a 1-character name (E_BAD_NAME) and an unknown nation (E_NO_SUCH_NATION, carrying % fix(es)) — leaving the refused captain with no house; probe rolled back leaving 0 players; 0 client write grants',
    public.wc_int('starting_ducats'), jsonb_array_length(v_nation->'fixes');
end $$;
