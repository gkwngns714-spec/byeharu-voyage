-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0016 — A CAPTAIN LEARNS A TRADE: skills are STUDIED at an academy, and seamanship stretches stores
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ────────────────────────────────────────────────────────────────────────
--   "do the migrations - price history, player row, officers, skills"
--
-- ── WHERE THIS WAS ALREADY DECIDED TO LIVE ─────────────────────────────────────────────────────
-- docs/SECTIONS.md: `| skills | its own migration: skills, player_skills | must not become columns
-- on players |`. Obeyed literally — nothing here alters `public.players`, and the self-assert
-- checks the catalogue for a skill-shaped column rather than trusting that it did not.
--
-- ── HOW A SKILL IS GAINED, AND WHY NOT BY XP ───────────────────────────────────────────────────
-- The obvious shape is experience: every verb awards points towards a level. It cannot be built
-- that way here, and the reason is the same one 0014 met with fame — THE VERBS LIVE IN 0007 AND
-- 0007 IS DEPLOYED. Hooking an XP award into each of them means re-cutting an applied migration.
--
-- 0014 solved that by DERIVING fame from the append-only record. That works for fame, which is a
-- measure of what you have done. It is wrong for a skill, which is a CHOICE — a derived skill would
-- level itself, and then it is not a decision, it is a second fame.
--
-- So a skill is STUDIED: `cmd.study_skill()` raises one level, for money, and the money is the
-- cost of the choice. And it may only be studied where teaching happens — a port with an academy.
-- `public.ports.has_academy` has existed since 0002 and, until now, NOTHING IN THE GAME READ IT:
--
--   PortScreen.tsx   printed "Academy: yes / none" and that was the whole of its meaning.
--
-- A flag that nothing reads is scenery. This migration gives it a consequence.
--
-- ── AN INERT SKILL IS DECORATION, SO ONE OF THEM IS WIRED ──────────────────────────────────────
-- As in 0015, this file SUPERSEDES ONE FUNCTION rather than shipping a table of numbers nothing
-- reads: `voyage.endurance_days()` from 0006, plus one term. Four skills are seeded; ONE is read:
--
--   SEAMANSHIP  → voyage.endurance_days()   READ. Superseded below: stores stretch further.
--   NAVIGATION  → speed                     NOT READ. Deliberately: 0015's NAVIGATOR officers own
--                                           speed, and two authorities for one number is the thing
--                                           this project forbids. It attaches to weather when
--                                           weather exists.
--   ACCOUNTING  → the daily trade cap        NOT READ YET. Attaches in world.daily_cap_remaining.
--   HAGGLING    → spread                     NOT READ YET. Attaches in world.quote (0005).
--
-- With no levels studied the multiplier is exactly 1.0, so every figure 0006 published still holds
-- and the proofs — which sail an unskilled captain — are unaffected. Proven below, not asserted.
--
-- Depends ONLY on: 0001-0015 (players/credit/emit_event 0004, ports.has_academy 0002, fleets 0004,
-- endurance_days 0006, current_player_id 0004).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('skill_max_level', to_jsonb(5),
   'The ceiling on every skill. One number for all of them: a skill that levelled higher than another would need its own balancing story, and there is none yet.'),
  ('skill_study_base_cost', to_jsonb(500),
   'What the FIRST level of any skill costs to study, in ducats. Each further level costs this times the level being bought, so level 5 costs five times level 1 — a curve that is a knob rather than a literal.')
on conflict (key) do nothing;

-- ── THE CATALOGUE ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.skills (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code = upper(code) and length(code) between 2 and 16),
  name          text not null,
  effect        text not null check (effect in ('ENDURANCE', 'SPEED', 'TRADE_CAP', 'SPREAD')),
  pct_per_level numeric(5,2) not null check (pct_per_level > 0 and pct_per_level <= 10),
  blurb         text not null
);

comment on table public.skills is
  'WHAT CAN BE LEARNED — authored world data. A house''s levels live in public.player_skills, '
  'never as columns on public.players (docs/SECTIONS.md).';
comment on column public.skills.effect is
  'The ONE thing this skill changes. Exactly one, for the same reason an officer has one specialty: '
  'a skill that moved several numbers would need several rules to read it.';

alter table public.skills enable row level security;
create policy skills_read on public.skills for select to authenticated using (true);
grant select on public.skills to authenticated;

-- ── WHAT A HOUSE HAS LEARNED ───────────────────────────────────────────────────────────────────
create table if not exists public.player_skills (
  player_id  uuid not null references public.players(id) on delete cascade,
  skill_id   uuid not null references public.skills(id) on delete cascade,
  level      int  not null default 1 check (level >= 1),
  studied_at timestamptz not null default now(),
  primary key (player_id, skill_id)
);

comment on table public.player_skills is
  'One row per skill a house has ANY level in. The absence of a row is level 0 — a table with a '
  'row per (player x skill) whether learned or not would make "not studied" and "studied to 0" two '
  'spellings of one state.';

alter table public.player_skills enable row level security;
create policy player_skills_read_own on public.player_skills for select to authenticated
  using (player_id = public.current_player_id());
grant select on public.player_skills to authenticated;

-- ── THE ONE READING ────────────────────────────────────────────────────────────────────────────
create or replace function public.player_skill_bonus(p_player uuid, p_effect text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- A FRACTION (0.10 = +10%), summed across every skill with this effect. There is exactly one
  -- such skill today; the sum is what keeps that from being an assumption baked into the caller.
  select coalesce(sum(s.pct_per_level * ps.level), 0) / 100.0
    from public.player_skills ps
    join public.skills s on s.id = ps.skill_id
   where ps.player_id = p_player
     and s.effect = upper(p_effect);
$$;

comment on function public.player_skill_bonus(uuid, text) is
  'THE ONE answer to "what are this house''s skills worth, for this effect". Every rule that reads '
  'a skill calls this; nothing multiplies pct_per_level by level itself.';

revoke all on function public.player_skill_bonus(uuid, text) from public, anon, authenticated;

-- ── THE RULE THAT ACTUALLY CHANGES ─────────────────────────────────────────────────────────────
-- 0006's body plus one term. Written as plpgsql rather than sql because it now needs the fleet's
-- OWNER, and the owner is a second lookup; the arithmetic is otherwise character-identical.
create or replace function voyage.endurance_days(p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_base   numeric;
  v_player uuid;
  v_skill  numeric := 0;
begin
  -- DESIGN C.5: the SHORTEST-ranged ship sets the fleet's endurance. Stores are pooled per hull.
  select coalesce(min(least(
           case when s.crew = 0 then 9999 else s.water_t / (s.crew * public.wc_num('water_per_crew_day')) end,
           case when s.crew = 0 then 9999 else s.food_t  / (s.crew * public.wc_num('food_per_crew_day'))  end
         )), 0)
    into v_base
    from public.ships s where s.fleet_id = p_fleet;

  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is not null then
    v_skill := public.player_skill_bonus(v_player, 'ENDURANCE');
  end if;

  return v_base * (1 + v_skill);
end $$;

comment on function voyage.endurance_days(uuid) is
  'The shortest-ranged hull sets the range (DESIGN C.5), stretched by the house''s SEAMANSHIP '
  '(0016). Supersedes the 0006 definition; identical to it at skill level 0.';

-- ── STUDYING ───────────────────────────────────────────────────────────────────────────────────
create or replace function cmd.study_skill(p_code text, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_code   text := upper(btrim(coalesce(p_code, '')));
  v_skill  public.skills%rowtype;
  v_fleet  record;
  v_port   record;
  v_level  int;
  v_next   int;
  v_max    int := public.wc_int('skill_max_level');
  v_cost   bigint;
  v_purse  bigint;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no captain to teach.',
      'fixes', jsonb_build_array('(sign in first)'));
  end if;

  select * into v_skill from public.skills where code = v_code;
  if v_skill.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_SKILL',
      'error_message', format('Nothing is taught under the name "%s".', v_code),
      'fixes', (select coalesce(jsonb_agg(format('(study %s — %s)', code, name) order by code), '[]'::jsonb)
                  from public.skills));
  end if;

  select f.id, f.player_id, f.status, f.port_id into v_fleet
    from public.fleets f where f.id = p_fleet;
  if v_fleet.id is null or v_fleet.player_id is distinct from v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
      'error_message', 'That fleet is not yours.',
      'fixes', jsonb_build_array('(name one of your own fleets)'));
  end if;

  -- TEACHING HAPPENS SOMEWHERE. A captain at sea is not in a lecture room, and a port without an
  -- academy has nobody to teach. `has_academy` finally means something.
  if v_fleet.port_id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_AT_SEA',
      'error_message', 'She is at sea. A trade is learned ashore.',
      'fixes', jsonb_build_array('(SAIL to a port with an academy, then study)'));
  end if;

  select p.code, p.name, p.has_academy into v_port from public.ports p where p.id = v_fleet.port_id;
  if not v_port.has_academy then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_ACADEMY',
      'error_message', format('%s keeps no academy.', v_port.name),
      'fixes', (select coalesce(jsonb_agg(format('(sail to %s — %s)', p.code, p.name) order by p.code), '[]'::jsonb)
                  from (select code, name from public.ports where has_academy order by code limit 6) p));
  end if;

  select ps.level into v_level from public.player_skills ps
   where ps.player_id = v_player and ps.skill_id = v_skill.id;
  v_level := coalesce(v_level, 0);
  v_next  := v_level + 1;

  if v_next > v_max then
    return jsonb_build_object('ok', false, 'error_code', 'E_SKILL_MAXED',
      'error_message', format('%s is already at %s, which is as far as it is taught.', v_skill.name, v_max),
      'fixes', jsonb_build_array('(study something else)'));
  end if;

  v_cost := public.wc_int('skill_study_base_cost') * v_next;
  select ducats into v_purse from public.players where id = v_player;
  if v_purse < v_cost then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_ENOUGH_DUCATS',
      'error_message', format('%s to level %s costs %s d. and the house holds %s.', v_skill.name, v_next, v_cost, v_purse),
      'fixes', jsonb_build_array('(sell a parcel first)'));
  end if;

  insert into public.player_skills (player_id, skill_id, level)
  values (v_player, v_skill.id, 1)
  on conflict (player_id, skill_id) do update set level = public.player_skills.level + 1,
                                                  studied_at = now();

  perform public.credit(
    v_player,
    'TUITION',
    -v_cost,
    public.emit_event(v_player, 'STUDIED', jsonb_build_object(
      'skill', v_skill.name, 'code', v_skill.code, 'level', v_next,
      'port', v_port.code, 'cost', v_cost)));

  return jsonb_build_object('ok', true, 'skill', v_skill.code, 'name', v_skill.name,
    'level', v_next, 'max_level', v_max, 'paid', v_cost, 'port', v_port.code,
    'effect', v_skill.effect);
end $$;

revoke all on function cmd.study_skill(text, uuid) from public, anon;
grant execute on function cmd.study_skill(text, uuid) to authenticated;

-- ── THE READ ───────────────────────────────────────────────────────────────────────────────────
create or replace function world.skills()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_read   constant text[] := array['ENDURANCE'];   -- the effects the RULES actually read today
begin
  return jsonb_build_object(
    'max_level', public.wc_int('skill_max_level'),
    'base_cost', public.wc_int('skill_study_base_cost'),
    'effects_read', to_jsonb(v_read),
    'skills', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name, 'effect', s.effect,
               'pct_per_level', s.pct_per_level, 'blurb', s.blurb,
               'level', coalesce(ps.level, 0),
               'next_cost', case when coalesce(ps.level, 0) >= public.wc_int('skill_max_level')
                                 then null
                                 else public.wc_int('skill_study_base_cost') * (coalesce(ps.level, 0) + 1) end,
               'takes_effect', (s.effect = any(v_read))
             ) order by s.code), '[]'::jsonb)
        from public.skills s
        left join public.player_skills ps on ps.skill_id = s.id and ps.player_id = v_player));
end $$;

comment on function world.skills() is
  'What can be learned, and how far this house has learned it. Carries `takes_effect` per skill '
  'because three of the four are seeded and not yet read by any rule.';

revoke all on function world.skills() from public, anon;
grant execute on function world.skills() to authenticated;

insert into public.skills (code, name, effect, pct_per_level, blurb) values
  ('SEAMANSHIP', 'Seamanship', 'ENDURANCE', 6.00,
   'A crew that knows its business wastes less. Stores stretch further at every level.'),
  ('NAVIGATION', 'Navigation', 'SPEED', 4.00,
   'Reading the sky and the set of a current. Not yet read by any rule — a navigator officer is what makes a hull faster today.'),
  ('ACCOUNTING', 'Accounting', 'TRADE_CAP', 5.00,
   'Books kept well enough that a factor will let you move more in a day. Not yet read by any rule.'),
  ('HAGGLING',   'Haggling',   'SPREAD',    5.00,
   'The difference between what a thing is worth and what you pay for it. Not yet read by any rule.')
on conflict (code) do nothing;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe   constant uuid := '00000000-0016-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_acad    uuid;
  v_noacad  uuid;
  v_n       int;
  v_effects int;
  v_base    numeric;
  v_after   numeric;
  v_expect  numeric;
  v_bonus   numeric;
  v_ok      jsonb;
  v_sea     jsonb;
  v_max     jsonb;
  v_none    jsonb;
  v_poor    jsonb;
  v_nosuch  jsonb;
  v_list    jsonb;
  v_purse0  bigint;
  v_purse1  bigint;
  v_cost    bigint;
  v_lvl     int;
  v_rls     boolean;
  v_grants  int;
  v_players int;
  v_left    int;
  v_pct     text;
begin
  if has_function_privilege('anon', 'world.skills()', 'execute') then
    raise exception '0016 self-assert FAIL: anon may execute world.skills()';
  end if;
  if not has_function_privilege('authenticated', 'cmd.study_skill(text, uuid)', 'execute') then
    raise exception '0016 self-assert FAIL: authenticated may NOT study a skill';
  end if;
  if has_function_privilege('authenticated', 'public.player_skill_bonus(uuid, text)', 'execute') then
    raise exception '0016 self-assert FAIL: authenticated may execute player_skill_bonus — a client could read another house''s skills';
  end if;
  select relrowsecurity into v_rls from pg_class where oid = 'public.player_skills'::regclass;
  if not v_rls then raise exception '0016 self-assert FAIL: RLS is not enabled on public.player_skills'; end if;

  -- SECTIONS.md's constraint, checked rather than trusted.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'players'
                and column_name like '%skill%') then
    raise exception '0016 self-assert FAIL: a skill column was added to public.players — SECTIONS.md forbids it';
  end if;

  select count(*), count(distinct effect) into v_n, v_effects from public.skills;
  if v_n < 4 or v_effects <> 4 then
    raise exception '0016 self-assert FAIL: seeded % skill(s) across % effect(s), expected 4 and 4', v_n, v_effects;
  end if;

  -- The world must actually contain somewhere to study, or every check below is vacuous.
  select count(*) into v_n from public.ports where has_academy;
  if v_n = 0 then
    raise exception '0016 self-assert FAIL: no port in the world keeps an academy, so studying could never be proven';
  end if;

  begin
    perform cmd.assume_identity(v_probe);
    v_player := public.new_house(v_probe, 'Casa da Escola', 'PRT');
    select f.id into v_fleet from public.fleets f where f.player_id = v_player limit 1;

    -- (a) THE NO-OP. At level 0 the superseded endurance is 0006's own figure, to the digit.
    v_base := voyage.endurance_days(v_fleet);
    if public.player_skill_bonus(v_player, 'ENDURANCE') <> 0 then
      raise exception '0016 self-assert FAIL: an unstudied house reported an endurance bonus';
    end if;
    if v_base <> (select coalesce(min(least(
                    case when s.crew = 0 then 9999 else s.water_t / (s.crew * public.wc_num('water_per_crew_day')) end,
                    case when s.crew = 0 then 9999 else s.food_t  / (s.crew * public.wc_num('food_per_crew_day'))  end)), 0)
                   from public.ships s where s.fleet_id = v_fleet) then
      raise exception '0016 self-assert FAIL: at level 0 the endurance % is not 0006''s figure', v_base;
    end if;

    -- (b) THE POSITIVE CONTROLS FOR PLACE. At sea, and at a port with no academy, both refuse.
    select p.id into v_noacad from public.ports p where not p.has_academy order by p.code limit 1;
    if v_noacad is not null then
      update public.fleets set status = 'DOCKED', port_id = v_noacad where id = v_fleet;
      v_none := cmd.study_skill('SEAMANSHIP', v_fleet);
      if (v_none->>'error_code') is distinct from 'E_NO_ACADEMY' then
        raise exception '0016 self-assert FAIL: studying at a port with no academy was not refused: %', v_none;
      end if;
    end if;

    -- At sea means SAILING with no port: `fleets_position_is_unambiguous` (0004) makes the two
    -- inseparable, which is the constraint doing its job — a fleet cannot be nowhere.
    update public.fleets set status = 'SAILING', port_id = null where id = v_fleet;
    v_sea := cmd.study_skill('SEAMANSHIP', v_fleet);
    if (v_sea->>'error_code') is distinct from 'E_AT_SEA' then
      raise exception '0016 self-assert FAIL: studying at sea was not refused: %', v_sea;
    end if;

    -- (c) at an academy it works, and the endurance moves BY THE STATED AMOUNT.
    select p.id into v_acad from public.ports p where p.has_academy order by p.code limit 1;
    update public.fleets set status = 'DOCKED', port_id = v_acad where id = v_fleet;

    select ducats into v_purse0 from public.players where id = v_player;
    v_ok := cmd.study_skill('SEAMANSHIP', v_fleet);
    if not (v_ok->>'ok')::boolean then
      raise exception '0016 self-assert FAIL: studying at an academy was refused: %', v_ok;
    end if;
    if (v_ok->>'level')::int <> 1 then
      raise exception '0016 self-assert FAIL: a first study gave level %', v_ok->>'level';
    end if;

    v_cost := (v_ok->>'paid')::bigint;
    select ducats into v_purse1 from public.players where id = v_player;
    if v_purse1 <> v_purse0 - v_cost then
      raise exception '0016 self-assert FAIL: purse went % -> % for tuition of %', v_purse0, v_purse1, v_cost;
    end if;

    v_bonus := public.player_skill_bonus(v_player, 'ENDURANCE');
    v_pct   := round(v_bonus * 100, 2)::text || '%';
    v_after := voyage.endurance_days(v_fleet);
    v_expect := v_base * (1 + v_bonus);
    if abs(v_after - v_expect) > 0.000001 then
      raise exception '0016 self-assert FAIL: with % seamanship the endurance went % -> %, expected %', v_pct, v_base, v_after, v_expect;
    end if;
    if v_after <= v_base then
      raise exception '0016 self-assert FAIL: seamanship did not stretch the stores (% -> %)', v_base, v_after;
    end if;

    -- (d) the ceiling BITES. Study to the cap, then require the next attempt to be refused.
    for v_lvl in 2..public.wc_int('skill_max_level') loop
      update public.players set ducats = 1000000 where id = v_player;
      perform cmd.study_skill('SEAMANSHIP', v_fleet);
    end loop;
    select ps.level into v_lvl from public.player_skills ps
      join public.skills s on s.id = ps.skill_id
     where ps.player_id = v_player and s.code = 'SEAMANSHIP';
    if v_lvl <> public.wc_int('skill_max_level') then
      raise exception '0016 self-assert FAIL: studying to the ceiling reached level % of %', v_lvl, public.wc_int('skill_max_level');
    end if;
    v_max := cmd.study_skill('SEAMANSHIP', v_fleet);
    if (v_max->>'error_code') is distinct from 'E_SKILL_MAXED' then
      raise exception '0016 self-assert FAIL: studying past the ceiling was not refused: %', v_max;
    end if;

    -- (e) an unknown skill, and a purse that cannot pay.
    v_nosuch := cmd.study_skill('ALCHEMY', v_fleet);
    if (v_nosuch->>'error_code') is distinct from 'E_NO_SUCH_SKILL' then
      raise exception '0016 self-assert FAIL: an unknown skill was not refused: %', v_nosuch;
    end if;

    update public.players set ducats = 0 where id = v_player;
    v_poor := cmd.study_skill('NAVIGATION', v_fleet);
    if (v_poor->>'error_code') is distinct from 'E_NOT_ENOUGH_DUCATS' then
      raise exception '0016 self-assert FAIL: unaffordable tuition was not refused: %', v_poor;
    end if;

    -- (f) the roster tells the truth about which skills are inert.
    v_list := world.skills();
    if (select count(*) from jsonb_array_elements(v_list->'skills') e
         where (e->>'effect') = 'ENDURANCE' and not (e->>'takes_effect')::boolean) > 0 then
      raise exception '0016 self-assert FAIL: SEAMANSHIP is reported inert, but endurance_days reads it';
    end if;
    if (select count(*) from jsonb_array_elements(v_list->'skills') e
         where (e->>'effect') <> 'ENDURANCE' and (e->>'takes_effect')::boolean) > 0 then
      raise exception '0016 self-assert FAIL: a skill no rule reads is reported as taking effect';
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_players from public.players;
  select count(*) into v_left from public.player_skills;
  if v_players <> 0 or v_left <> 0 then
    raise exception '0016 self-assert FAIL: the probe left % player(s) and % studied skill(s) behind', v_players, v_left;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0016 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0016 self-assert ok: 4 skills across 4 effects, and NO skill column was added to public.players; at level 0 the endurance is 0006''s exact figure (% d) so the supersede is a no-op unstudied; studying was REFUSED at sea (E_AT_SEA) and at a port with no academy (E_NO_ACADEMY) — has_academy finally means something — and allowed at one that keeps one, taking endurance to % d at % seamanship, the stated amount; tuition left the purse through public.credit; the ceiling of % BIT (E_SKILL_MAXED) after studying to it, and E_NO_SUCH_SKILL and E_NOT_ENOUGH_DUCATS both bit; world.skills() reports takes_effect TRUE only for the one effect a rule reads; probe rolled back leaving 0 players and 0 studied skills; 0 client write grants',
    round(v_base, 3), round(v_after, 3), v_pct, public.wc_int('skill_max_level');
end $$;
