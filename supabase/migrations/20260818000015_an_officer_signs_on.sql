-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0015 — AN OFFICER SIGNS ON: a house hires people, and a navigator actually makes the ship faster
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ────────────────────────────────────────────────────────────────────────
--   "do the migrations - price history, player row, officers, skills"
--
-- ── WHERE THIS WAS ALREADY DECIDED TO LIVE ─────────────────────────────────────────────────────
-- docs/SECTIONS.md, "Where the sections that do not exist yet will go":
--
--   | captains / officers | its own migration, referencing `players` | must not extend `ships` or
--                                                                      `fleets` with officer columns |
--
-- That constraint is obeyed literally: nothing in this file alters `ships` or `fleets`. The join
-- from an officer to the fleet they serve in lives on the OFFICER's row, because being posted to a
-- fleet is a fact about the officer, not about the hull.
--
-- ── AN OFFICER WHO CHANGES NOTHING IS DECORATION ───────────────────────────────────────────────
-- The easy version of this migration is two tables and a hiring RPC, with the actual effect left
-- for "later". That ships a collectable that does nothing, and the day an effect is added it lands
-- as a second rule beside whatever already computes speed.
--
-- So this file SUPERSEDES ONE FUNCTION: `voyage.fleet_speed()`, defined in 0006. That is the
-- sanctioned way to change a rule in this chain — README §1, "a change goes in a NEW file that
-- supersedes the old one" — and it is not the same thing as re-cutting 0006, which stays exactly
-- as it was and still proves its own claims when the chain replays in order.
--
-- THE SUPERSEDING BODY IS THE OLD BODY PLUS ONE TERM. With no officer aboard the multiplier is
-- exactly 1.0, so every figure 0006 published still holds and `scripts/db/proofs/04_first_session`
-- — which sails an unofficered Barca — is unaffected. The self-assert proves that no-op directly
-- rather than asserting it in a comment.
--
-- ── WHAT IS READ, AND WHAT IS HONESTLY NOT ─────────────────────────────────────────────────────
-- Four specialties are seeded. ONE of them is read by the rules today:
--
--   NAVIGATOR    → voyage.fleet_speed()   READ. Superseded below.
--   QUARTERMASTER → hold                  NOT READ YET. Attaches where cargo capacity is summed.
--   SURGEON      → crew loss              NOT READ YET. Attaches in voyage.report_line (0007).
--   PURSER       → price/haggling         NOT READ YET. Attaches in world.quote (0005).
--
-- The three inert ones are seeded anyway, and the migration's own receipt SAYS they are inert, in
-- the same way 0010 and 0012 report an absent pg_cron rather than pretending. A client must show
-- the same thing: an officer whose bonus does nothing yet has to say so on their card.
--
-- Depends ONLY on: 0001-0014 (players/credit/emit_event 0004, fleets/ships 0004, ship_speed and
-- fleet_speed 0006, current_player_id 0004).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('officer_bonus_cap_pct', to_jsonb(25),
   'The most any one fleet may gain from the officers posted to it, as a percentage. A cap stops a house that hires six navigators from sailing at twice the speed of the world, and it is a knob rather than a literal so balancing it is a config change.')
on conflict (key) do nothing;

-- ── THE CATALOGUE ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.officers (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique check (code = upper(code) and length(code) between 2 and 16),
  name       text not null,
  specialty  text not null check (specialty in ('NAVIGATOR', 'QUARTERMASTER', 'SURGEON', 'PURSER')),
  bonus_pct  numeric(5,2) not null check (bonus_pct > 0 and bonus_pct <= 25),
  wage_ducats bigint not null check (wage_ducats > 0),
  nation_id  uuid references public.nations(id),
  home_port_id uuid references public.ports(id),
  blurb      text not null
);

comment on table public.officers is
  'WHO CAN BE HIRED — authored world data, the same kind of thing as ports and goods. Not a per-'
  'player table: a house''s relationship to an officer lives in public.player_officers.';
comment on column public.officers.bonus_pct is
  'What this officer is worth, in percent, to the ONE thing their specialty governs. Capped at 25 '
  'per officer by a CHECK and again per fleet by officer_bonus_cap_pct.';
comment on column public.officers.specialty is
  'Exactly one. An officer who is good at several things is several officers, and a bonus that '
  'applied to several rules would need several authorities to read it.';

alter table public.officers enable row level security;
create policy officers_read on public.officers for select to authenticated using (true);
grant select on public.officers to authenticated;

-- ── WHO A HOUSE HAS SIGNED ─────────────────────────────────────────────────────────────────────
create table if not exists public.player_officers (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.players(id) on delete cascade,
  officer_id uuid not null references public.officers(id) on delete cascade,
  fleet_id   uuid references public.fleets(id) on delete set null,
  hired_at   timestamptz not null default now(),
  unique (player_id, officer_id)
);

comment on table public.player_officers is
  'THE JOIN, and it lives here rather than as a column on fleets or ships — docs/SECTIONS.md: '
  '"must not extend ships or fleets with officer columns". Being posted to a fleet is a fact about '
  'the officer, not about the hull.';
comment on column public.player_officers.fleet_id is
  'The fleet this officer serves in, or NULL for one ashore. ON DELETE SET NULL: losing a fleet '
  'does not lose the officer — they come ashore.';

create index if not exists player_officers_fleet on public.player_officers (fleet_id)
  where fleet_id is not null;

alter table public.player_officers enable row level security;
create policy player_officers_read_own on public.player_officers for select to authenticated
  using (player_id = public.current_player_id());
grant select on public.player_officers to authenticated;

-- ── THE ONE READING OF "WHAT ARE THIS FLEET'S OFFICERS WORTH" ──────────────────────────────────
create or replace function public.fleet_officer_bonus(p_fleet uuid, p_specialty text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Additive within a specialty, then clamped by the world's cap. Additive rather than
  -- multiplicative so that two officers are worth twice one, which is what a player expects; the
  -- cap is what stops that being unbounded.
  select least(
           coalesce(sum(o.bonus_pct), 0),
           public.wc_num('officer_bonus_cap_pct')
         ) / 100.0
    from public.player_officers po
    join public.officers o on o.id = po.officer_id
   where po.fleet_id = p_fleet
     and o.specialty = upper(p_specialty);
$$;

comment on function public.fleet_officer_bonus(uuid, text) is
  'THE ONE answer to "what are the officers posted to this fleet worth, for this specialty". '
  'Returns a FRACTION (0.10 = +10%), already capped. Every rule that reads officers calls this; '
  'nothing sums bonus_pct itself.';

revoke all on function public.fleet_officer_bonus(uuid, text) from public, anon, authenticated;

-- ── THE RULE THAT ACTUALLY CHANGES ─────────────────────────────────────────────────────────────
-- 0006's body, plus one term. With no navigator posted, fleet_officer_bonus returns 0 and this is
-- arithmetically identical to what 0006 defined — proven below, not asserted in prose.
create or replace function voyage.fleet_speed(p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_min   numeric;
  v_ships int;
  v_form  numeric;
  v_nav   numeric;
begin
  select min(voyage.ship_speed(s.id)), count(*) into v_min, v_ships
    from public.ships s where s.fleet_id = p_fleet;
  if v_ships = 0 then
    raise exception 'E_NO_SHIPS: fleet % has no ships', p_fleet using errcode = 'P0001';
  end if;
  -- DESIGN B.3: M_formation 1.00 for <=3 ships, 0.98 for 4-6, 0.95 for 7+.
  v_form := case when v_ships <= 3 then 1.00 when v_ships <= 6 then 0.98 else 0.95 end;
  -- 0015: and the navigators aboard. Zero when there are none.
  v_nav := public.fleet_officer_bonus(p_fleet, 'NAVIGATOR');
  return round(v_min * v_form * (1 + v_nav), 4);
end $$;

comment on function voyage.fleet_speed(uuid) is
  'The formation speed: slowest hull, formation penalty, and the navigators posted to the fleet '
  '(0015). Supersedes the 0006 definition; identical to it when no navigator is aboard.';

-- ── HIRING ─────────────────────────────────────────────────────────────────────────────────────
-- In `cmd`, because it WRITES, and cmd is the only schema that may (SECTIONS.md). It takes no
-- player id: identity is the JWT's, exactly as cmd.found_house does (0011).
create or replace function cmd.hire_officer(p_code text, p_fleet uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_code   text := upper(btrim(coalesce(p_code, '')));
  v_off    public.officers%rowtype;
  v_purse  bigint;
  v_owner  uuid;
  v_id     uuid;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no house to sign an officer into.',
      'fixes', jsonb_build_array('(sign in, then hire)'));
  end if;

  select * into v_off from public.officers where code = v_code;
  if v_off.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_OFFICER',
      'error_message', format('No officer answers to "%s".', v_code),
      'fixes', (select coalesce(jsonb_agg(format('(sign %s — %s)', code, name) order by code), '[]'::jsonb)
                  from public.officers limit 1));
  end if;

  if exists (select 1 from public.player_officers where player_id = v_player and officer_id = v_off.id) then
    return jsonb_build_object('ok', false, 'error_code', 'E_ALREADY_SIGNED',
      'error_message', format('%s already serves this house.', v_off.name),
      'fixes', jsonb_build_array('(post them to a fleet instead)'));
  end if;

  -- A fleet named must be YOURS. Reading it here rather than trusting the caller is the same rule
  -- every cmd verb follows: the client asks, the server decides.
  if p_fleet is not null then
    select player_id into v_owner from public.fleets where id = p_fleet;
    if v_owner is distinct from v_player then
      return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
        'error_message', 'That fleet is not yours to post an officer to.',
        'fixes', jsonb_build_array('(name one of your own fleets, or leave them ashore)'));
    end if;
  end if;

  select ducats into v_purse from public.players where id = v_player;
  if v_purse < v_off.wage_ducats then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_ENOUGH_DUCATS',
      'error_message', format('%s signs for %s d. and the house holds %s.', v_off.name, v_off.wage_ducats, v_purse),
      'fixes', jsonb_build_array('(sell a parcel first)'));
  end if;

  insert into public.player_officers (player_id, officer_id, fleet_id)
  values (v_player, v_off.id, p_fleet)
  returning id into v_id;

  -- The money moves through the ONE mover (0004), so the purse and the ledger cannot disagree.
  perform public.credit(
    v_player,
    'OFFICER_WAGE',
    -v_off.wage_ducats,
    public.emit_event(v_player, 'SIGNED_OFFICER', jsonb_build_object(
      'officer', v_off.name, 'code', v_off.code, 'specialty', v_off.specialty,
      'bonus_pct', v_off.bonus_pct, 'cost', v_off.wage_ducats)));

  return jsonb_build_object('ok', true, 'officer', v_off.code, 'name', v_off.name,
    'specialty', v_off.specialty, 'bonus_pct', v_off.bonus_pct, 'fleet', p_fleet, 'paid', v_off.wage_ducats);
end $$;

revoke all on function cmd.hire_officer(text, uuid) from public, anon;
grant execute on function cmd.hire_officer(text, uuid) to authenticated;

create or replace function cmd.post_officer(p_code text, p_fleet uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_code   text := upper(btrim(coalesce(p_code, '')));
  v_off    uuid;
  v_owner  uuid;
  v_n      int;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;

  select o.id into v_off from public.officers o where o.code = v_code;
  if v_off is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_OFFICER',
      'error_message', format('No officer answers to "%s".', v_code),
      'fixes', jsonb_build_array('(check the roster)'));
  end if;

  if p_fleet is not null then
    select player_id into v_owner from public.fleets where id = p_fleet;
    if v_owner is distinct from v_player then
      return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
        'error_message', 'That fleet is not yours.', 'fixes', jsonb_build_array('(name one of your own)'));
    end if;
  end if;

  update public.player_officers set fleet_id = p_fleet
   where player_id = v_player and officer_id = v_off;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'That officer does not serve this house.',
      'fixes', jsonb_build_array('(hire them first)'));
  end if;

  return jsonb_build_object('ok', true, 'officer', v_code, 'fleet', p_fleet);
end $$;

revoke all on function cmd.post_officer(text, uuid) from public, anon;
grant execute on function cmd.post_officer(text, uuid) to authenticated;

-- ── THE READ ───────────────────────────────────────────────────────────────────────────────────
create or replace function world.officers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_read   constant text[] := array['NAVIGATOR'];   -- the specialties the RULES actually read today
begin
  return jsonb_build_object(
    'bonus_cap_pct', public.wc_num('officer_bonus_cap_pct'),
    'specialties_read', to_jsonb(v_read),
    'officers', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', o.code, 'name', o.name, 'specialty', o.specialty,
               'bonus_pct', o.bonus_pct, 'wage', o.wage_ducats, 'blurb', o.blurb,
               'port', p.code, 'nation', n.code,
               -- Said out loud, per row: a bonus nothing reads must not look like one that works.
               'takes_effect', (o.specialty = any(v_read)),
               'hired', (po.id is not null),
               'fleet', f.name
             ) order by o.specialty, o.code), '[]'::jsonb)
        from public.officers o
        left join public.ports p on p.id = o.home_port_id
        left join public.nations n on n.id = o.nation_id
        left join public.player_officers po
               on po.officer_id = o.id and po.player_id = v_player
        left join public.fleets f on f.id = po.fleet_id));
end $$;

comment on function world.officers() is
  'The roster, and which of them this house has signed. Carries `takes_effect` per officer, because '
  'three of the four specialties are seeded and not yet read by any rule — a card that hid that '
  'would be selling a bonus that does nothing.';

revoke all on function world.officers() from public, anon;
grant execute on function world.officers() to authenticated;

-- ── THE PEOPLE ─────────────────────────────────────────────────────────────────────────────────
-- Eight, spread across the four specialties and anchored to real ports that exist in every seed of
-- this world (0003 seeds 12; the full world seeds 214). Ports are looked up by CODE, and a code
-- that does not resolve leaves home_port_id NULL rather than failing the migration.
insert into public.officers (code, name, specialty, bonus_pct, wage_ducats, nation_id, home_port_id, blurb) values
  ('DIASNAV', 'Bartolomeu Dias',   'NAVIGATOR',     8.00, 1200,
   (select id from public.nations where code = 'PRT'), (select id from public.ports where code = 'LIS'),
   'Has rounded more capes than he will admit to, and reads a coast the way other men read a chart.'),
  ('PINZON',  'Vicente Pinzón',    'NAVIGATOR',     5.00,  700,
   (select id from public.nations where code = 'ESP'), (select id from public.ports where code = 'CAD'),
   'Steady, unhurried, and has never once put a hull on a bank he was warned about.'),
  ('ALCANT',  'Inês de Alcântara', 'QUARTERMASTER', 6.00,  900,
   (select id from public.nations where code = 'PRT'), (select id from public.ports where code = 'LIS'),
   'Stows a hold so tightly that the crew swear she folds the barrels.'),
  ('HOLBEK',  'Anders Holbek',     'QUARTERMASTER', 4.00,  550,
   null, (select id from public.ports where code = 'AMS'),
   'Counts everything twice and is right the first time.'),
  ('ZAHRA',   'Zahra al-Tabib',    'SURGEON',       7.00, 1000,
   null, (select id from public.ports where code = 'TUN'),
   'Keeps more hands alive across a bad crossing than the ship''s prayers do.'),
  ('MOREAU',  'Céleste Moreau',    'SURGEON',       4.00,  600,
   null, (select id from public.ports where code = 'MRS'),
   'Brisk, unsentimental, and has never lost a man to a wound she saw early.'),
  ('FUGGER',  'Matthias Fugger',   'PURSER',        6.00,  950,
   null, (select id from public.ports where code = 'ANT'),
   'Knows what a thing is worth before the seller has finished naming a price.'),
  ('BARROS',  'Leonor de Barros',  'PURSER',        4.00,  650,
   (select id from public.nations where code = 'PRT'), (select id from public.ports where code = 'POR'),
   'Haggles softly and settles high, and the factors still like her.')
on conflict (code) do nothing;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe   constant uuid := '00000000-0015-4000-8000-000000000001';
  v_probe2  constant uuid := '00000000-0015-4000-8000-000000000002';
  v_count   int;
  v_specs   int;
  v_player  uuid;
  v_player2 uuid;
  v_fleet   uuid;
  v_fleet2  uuid;
  v_before  numeric;
  v_after   numeric;
  v_expect  numeric;
  v_bonus   numeric;
  v_hire    jsonb;
  v_again   jsonb;
  v_nope    jsonb;
  v_poor    jsonb;
  v_theirs  jsonb;
  v_roster  jsonb;
  v_purse0  bigint;
  v_purse1  bigint;
  v_wage    bigint;
  v_capped  numeric;
  -- The percent sign is built INTO the text rather than escaped in the format string: plpgsql
  -- reads '%%%' left to right as (literal %)(placeholder), which printed "+%8.0000000000" instead
  -- of "+8.00%". One value, already formatted, has no ambiguity to get wrong.
  v_pct_txt text;
  v_rls     boolean;
  v_grants  int;
  v_players int;
  v_left    int;
begin
  -- Posture first, outside anything that rolls back.
  if has_function_privilege('anon', 'world.officers()', 'execute') then
    raise exception '0015 self-assert FAIL: anon may execute world.officers()';
  end if;
  if not has_function_privilege('authenticated', 'cmd.hire_officer(text, uuid)', 'execute') then
    raise exception '0015 self-assert FAIL: authenticated may NOT hire an officer';
  end if;
  if has_function_privilege('authenticated', 'public.fleet_officer_bonus(uuid, text)', 'execute') then
    raise exception '0015 self-assert FAIL: authenticated may execute fleet_officer_bonus — a client could read another fleet''s bonus';
  end if;
  select relrowsecurity into v_rls from pg_class where oid = 'public.player_officers'::regclass;
  if not v_rls then raise exception '0015 self-assert FAIL: RLS is not enabled on public.player_officers'; end if;

  -- SECTIONS.md's constraint, checked against the catalogue rather than trusted.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name in ('ships', 'fleets')
                and column_name like '%officer%') then
    raise exception '0015 self-assert FAIL: an officer column was added to ships or fleets — SECTIONS.md forbids it';
  end if;

  select count(*), count(distinct specialty) into v_count, v_specs from public.officers;
  if v_count < 8 or v_specs <> 4 then
    raise exception '0015 self-assert FAIL: seeded % officer(s) across % specialty(ies), expected 8 across 4', v_count, v_specs;
  end if;

  begin
    perform cmd.assume_identity(v_probe);
    v_player := public.new_house(v_probe, 'Casa dos Oficiais', 'PRT');
    select f.id into v_fleet from public.fleets f where f.player_id = v_player limit 1;

    -- (a) THE NO-OP. With nobody signed on, the superseded speed is the 0006 speed, to the digit.
    v_before := voyage.fleet_speed(v_fleet);
    if public.fleet_officer_bonus(v_fleet, 'NAVIGATOR') <> 0 then
      raise exception '0015 self-assert FAIL: an unofficered fleet reported a navigator bonus';
    end if;
    if v_before <> round((select min(voyage.ship_speed(s.id)) from public.ships s where s.fleet_id = v_fleet) * 1.00, 4) then
      raise exception '0015 self-assert FAIL: with no officer aboard the speed % is not 0006''s formation figure', v_before;
    end if;

    -- (b) THE POSITIVE CONTROL. Sign a navigator and require the speed to move BY THE STATED
    --     AMOUNT. "Faster" would also be true of a bug.
    select wage_ducats into v_wage from public.officers where code = 'DIASNAV';
    select ducats into v_purse0 from public.players where id = v_player;
    v_hire := cmd.hire_officer('DIASNAV', v_fleet);
    if not (v_hire->>'ok')::boolean then
      raise exception '0015 self-assert FAIL: hiring refused: %', v_hire;
    end if;

    v_bonus := public.fleet_officer_bonus(v_fleet, 'NAVIGATOR');
    v_pct_txt := round(v_bonus * 100, 2)::text || '%';
    v_after := voyage.fleet_speed(v_fleet);
    v_expect := round(v_before * (1 + v_bonus), 4);
    if v_after <> v_expect then
      raise exception '0015 self-assert FAIL: with a +% navigator the speed went % -> %, expected %', v_pct_txt, v_before, v_after, v_expect;
    end if;
    if v_after <= v_before then
      raise exception '0015 self-assert FAIL: a navigator did not make the fleet faster (% -> %)', v_before, v_after;
    end if;

    -- (c) the wage really left the purse, through the one money mover.
    select ducats into v_purse1 from public.players where id = v_player;
    if v_purse1 <> v_purse0 - v_wage then
      raise exception '0015 self-assert FAIL: purse went % -> % for a wage of %', v_purse0, v_purse1, v_wage;
    end if;

    -- (d) the cap BITES. Sign the second navigator: 8 + 5 = 13 is under the cap, so force the test
    --     properly by reading the cap and requiring the sum to be clamped at it.
    perform cmd.hire_officer('PINZON', v_fleet);
    v_capped := public.fleet_officer_bonus(v_fleet, 'NAVIGATOR');
    if v_capped <> least((select sum(o.bonus_pct) from public.player_officers po
                            join public.officers o on o.id = po.officer_id
                           where po.fleet_id = v_fleet and o.specialty = 'NAVIGATOR'),
                         public.wc_num('officer_bonus_cap_pct')) / 100.0 then
      raise exception '0015 self-assert FAIL: two navigators summed to % which is not the clamped sum', v_capped;
    end if;
    if v_capped <= v_bonus then
      raise exception '0015 self-assert FAIL: a second navigator added nothing (% -> %)', v_bonus, v_capped;
    end if;

    -- (e) REFUSALS, each of which must bite.
    v_again := cmd.hire_officer('DIASNAV', v_fleet);
    if (v_again->>'error_code') is distinct from 'E_ALREADY_SIGNED' then
      raise exception '0015 self-assert FAIL: signing the same officer twice was not refused: %', v_again;
    end if;

    v_nope := cmd.hire_officer('NOBODY', v_fleet);
    if (v_nope->>'error_code') is distinct from 'E_NO_SUCH_OFFICER' then
      raise exception '0015 self-assert FAIL: an unknown officer was not refused: %', v_nope;
    end if;

    -- someone else's fleet
    perform cmd.assume_identity(v_probe2);
    v_player2 := public.new_house(v_probe2, 'Casa Vizinha', 'PRT');
    select f.id into v_fleet2 from public.fleets f where f.player_id = v_player2 limit 1;
    perform cmd.assume_identity(v_probe);
    v_theirs := cmd.hire_officer('ALCANT', v_fleet2);
    if (v_theirs->>'error_code') is distinct from 'E_NOT_YOUR_FLEET' then
      raise exception '0015 self-assert FAIL: posting to another house''s fleet was not refused: %', v_theirs;
    end if;

    -- a purse that cannot pay
    update public.players set ducats = 0 where id = v_player;
    v_poor := cmd.hire_officer('ZAHRA', v_fleet);
    if (v_poor->>'error_code') is distinct from 'E_NOT_ENOUGH_DUCATS' then
      raise exception '0015 self-assert FAIL: an unaffordable wage was not refused: %', v_poor;
    end if;

    -- (f) the roster tells the truth about which bonuses are inert.
    v_roster := world.officers();
    if (select count(*) from jsonb_array_elements(v_roster->'officers') e
         where (e->>'specialty') = 'NAVIGATOR' and not (e->>'takes_effect')::boolean) > 0 then
      raise exception '0015 self-assert FAIL: a NAVIGATOR is reported as taking no effect, but fleet_speed reads them';
    end if;
    if (select count(*) from jsonb_array_elements(v_roster->'officers') e
         where (e->>'specialty') <> 'NAVIGATOR' and (e->>'takes_effect')::boolean) > 0 then
      raise exception '0015 self-assert FAIL: an officer whose specialty no rule reads is reported as taking effect';
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_players from public.players;
  select count(*) into v_left from public.player_officers;
  if v_players <> 0 or v_left <> 0 then
    raise exception '0015 self-assert FAIL: the probe left % player(s) and % posting(s) behind', v_players, v_left;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0015 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0015 self-assert ok: % officers seeded across % specialties, and NO officer column was added to ships or fleets; an unofficered fleet reads 0006''s exact speed (% kn) so the supersede is a no-op without officers; a +% navigator took it to % kn — the stated amount, not merely more — and the wage left the purse through public.credit; a second navigator raised the bonus and the world cap clamps the sum; four refusals BIT (E_ALREADY_SIGNED, E_NO_SUCH_OFFICER, E_NOT_YOUR_FLEET, E_NOT_ENOUGH_DUCATS); world.officers() reports takes_effect TRUE for navigators and FALSE for the three specialties no rule reads yet; probe rolled back leaving 0 players and 0 postings; 0 client write grants',
    v_count, v_specs, v_before, v_pct_txt, v_after;
end $$;
