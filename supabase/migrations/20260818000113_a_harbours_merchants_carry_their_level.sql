-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0113 — A HARBOUR'S MERCHANTS CARRY THEIR LEVEL
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-13: *"when i press city, it says how many ships are resting. i want there to be a list,
-- showing the total level, and its current time till the resting finishes."*
--
-- Two of the three things that list needs were already on the wire. `world.port_merchants` (0104)
-- serves every merchant a harbour concerns, what she is DOING there, and `next_lap_at` — the
-- instant her rest ends — so the list and the countdown are a screen's work alone. THE LEVEL WAS
-- NOT SERVED ANYWHERE A LIST COULD READ IT.
--
-- ── WHAT "TOTAL LEVEL" IS, SO IT CANNOT BE INVENTED ─────────────────────────────────────────────
-- docs/WORDS.md, the row for *"the company's four levels (the Academy and the merchant sheet)"*:
-- the word is **Skills**. A merchant company's levels are its rows of `public.player_skills` —
-- SEAMANSHIP, NAVIGATION, ACCOUNTING, HAGGLING, each 0 to `skill_max_level` — written by
-- `public.npc_found` (0097) and printed one bar each on her sheet (`world.npc_fleet_card`'s
-- `skills`). Her TOTAL level is the sum of the four, and the one reading of a single level is
-- `public.skill_level(player, code)` (0107: *"THE reading of a house's level in one skill, 0 where
-- it has never studied it"*). This file sums THAT reading. It does not join `player_skills` by hand
-- (a second reading of the same fact), and it does not reach for `ship_classes.tier` — a hull's
-- tier is a different fact with a different word, and a screen that printed it under the heading
-- "level" would be lying with a number.
--
-- ── WHY THE CARD IS NOT THE ANSWER ──────────────────────────────────────────────────────────────
-- `world.npc_fleet_card(fleet)` already serves the four skills, for ONE fleet, at a tap. A list of
-- the merchants resting in a harbour would have to read a card per row on every beat — N reads to
-- draw one list, against the rule that a screen asks one question (docs/NPC_TRADERS.md §8.1,
-- src/live/useServedRead.ts). The harbour's own read is the one that already answers per row.
--
-- ── WHAT THIS FILE DOES, AND DOES NOT ───────────────────────────────────────────────────────────
-- It SUPERSEDES 0104's `world.port_merchants(p_port)`: the function is restated whole with ONE
-- more key on every row — `level`, the integer sum above — and 0104's body is otherwise carried
-- verbatim. No input is new, so there is no "absent input" case: every row has a company and
-- every company has a level, 0 included. Nothing else about the read moves, and that is not a promise but an assertion below:
-- the pre-image of the function is kept under pg_temp before the replace, and the new read with
-- `level` struck from every row must equal the old read BYTE FOR BYTE over a lit world.
--
-- It does NOT touch `world.sea_traffic` — the beat's read, which 0104's header forbids growing and
-- which has no list to serve. 0104 asserted the harbour row is "sea_traffic's row plus two keys";
-- 0111 made it "minus lane" and this file makes it "plus level". The client type says so in as many
-- words (`PortMerchant` in src/lib/rpc/types.ts), and the key-set assertion below is the contract.
--
-- The switch ships dark (0097). This file lights the world inside a sub-transaction to prove
-- itself and rolls every byte of that back, exactly as 0104 does.
--
-- Depends ONLY on: world.port_merchants (0104), public.skill_level (0107), public.skills (0016),
-- public.npc_found / public.npc_traders_switch (0097).

-- ── 1. THE PRE-IMAGE, KEPT ─────────────────────────────────────────────────────────────────────
-- The live body is copied under a temporary name BEFORE it is replaced, so the self-assert can
-- compare the two reads over the same world rather than trust this file's claim of "one key".
do $$
declare
  v_def text;
begin
  v_def := replace(pg_get_functiondef('world.port_merchants(uuid)'::regprocedure), E'\r', '');
  if position('CREATE OR REPLACE FUNCTION world.port_merchants(p_port uuid)' in v_def) = 0 then
    raise exception '0113: the pre-image of world.port_merchants did not read as expected: %', left(v_def, 120);
  end if;
  execute replace(v_def,
    'CREATE OR REPLACE FUNCTION world.port_merchants(p_port uuid)',
    'CREATE OR REPLACE FUNCTION pg_temp.pm_before_0113(p_port uuid)');
end $$;

-- ── 2. THE READ, PLUS ONE KEY ──────────────────────────────────────────────────────────────────
create or replace function world.port_merchants(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $pm$
  -- 0104: WHICH MERCHANTS THIS HARBOUR CONCERNS, AND WHAT EACH ONE IS DOING (owner row 121). Read
  -- at tap time, like world.npc_fleet_card and unlike world.sea_traffic — the header argues the
  -- choice on the numbers. One row per merchant FLEET whose route calls here, even when she is
  -- nowhere near: `away` is a true answer and a capped traffic read could never give it.
  --
  -- The key set is world.sea_traffic's row (less 0111's `lane`), plus `doing` and `stops` (0104)
  -- and `level` (0113), so the client keeps one type and one writer of the line beside her name.
  -- An `ord` is deliberately NOT served: the screen already knows which harbour it is and marks it
  -- in `stops` by code, which is one fact fewer to disagree about.
  select case when not public.npc_traders_on()
    then jsonb_build_object('enabled', false, 'at', now(),
                            'port', (select code from public.ports where id = p_port),
                            'merchants', '[]'::jsonb)
    else jsonb_build_object('enabled', true, 'at', now(),
      'port', (select code from public.ports where id = p_port),
      'merchants', coalesce((
        select jsonb_agg(r.row order by r.rank, r.roster_ord, r.id)
          from (
            select f.id,
                   nf.roster_ord,
                   -- THE ONES WHO ARE HERE FIRST, then the ones coming, then the rest — the order
                   -- is the server's, so every screen lists them the same way.
                   case d.doing when 'laid_up'  then 1
                                when 'resting'  then 2
                                when 'starting' then 3
                                when 'ending'   then 4
                                when 'passing'  then 5
                                else 6 end as rank,
                   jsonb_build_object(
                     'id', f.id, 'company', p.company_name, 'nation_code', n.code, 'ink', h.ink,
                     'name', f.name, 'status', f.status,
                     'ships', (select count(*) from public.ships s where s.fleet_id = f.id),
                     -- WHAT THOSE HULLS ARE (0102, owner row 120) — `ship_classes.code` per hull,
                     -- flagship first then the order she was built in. Carried because this row IS
                     -- a traffic row plus a few keys, and a shared key that only one of the two
                     -- reads serves is the drift 0104's header promises not to start; the key-set
                     -- self-asserts on both sides are what keep that promise checkable.
                     'hulls', (select coalesce(jsonb_agg(sc.code order by s.is_flagship desc, s.created_at, s.id), '[]'::jsonb)
                                 from public.ships s join public.ship_classes sc on sc.id = s.class_id
                                where s.fleet_id = f.id),
                     'port', po.code,
                     'roadstead', case when f.port_id is not null
                                       then jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon) end,
                     'anchor', case when f.lat is not null then jsonb_build_array(f.lat, f.lon) end,
                     'voyage', (select world.voyage_view(v.id, false) from public.voyages v
                                 where v.fleet_id = f.id and v.status = 'SAILING'),
                     'next_lap_at', case when sr.hold_until > now() then sr.hold_until end,
                     'doing', d.doing,
                     -- HER TOTAL LEVEL (0113, owner 2026-10-13): the company's four skills summed
                     -- through THE one reading of a level, public.skill_level (0107). The absence
                     -- of a row is level 0, by 0016's own ruling, so a company that has studied
                     -- nothing reads 0 and not null.
                     'level', (select coalesce(sum(public.skill_level(p.id, sk.code)), 0)::int
                                 from public.skills sk),
                     -- HER LOOP, as codes in sailing order. The codes alone, never the baked
                     -- courses: those are hundreds of points a leg and they are served on the
                     -- CARD, for the one fleet a player tapped (0099).
                     'stops', (select coalesce(jsonb_agg(po2.code order by s2.ord), '[]'::jsonb)
                                 from public.standing_route_stops s2
                                 join public.ports po2 on po2.id = s2.port_id
                                where s2.route_id = sr.id)) as row
              from public.fleets f
              -- THE ONE PREDICATE. A player's fleet is never a row of a merchant read.
              join public.players p on p.id = f.player_id and p.is_npc
              join public.npc_houses h on h.player_id = p.id
              -- WHOSE ROUTE IS THIS — `npc_fleets.route_id`, the world's own record and the
              -- authority both of 0099's reads use, NOT `standing_routes.fleet_id`: 0097's upkeep
              -- detaches a laid-up route from its fleet, and reading it the other way round drops
              -- exactly the merchants lying at their quay.
              join public.npc_fleets nf on nf.fleet_id = f.id
              join public.standing_routes sr on sr.id = nf.route_id
              left join public.nations n on n.id = p.nation_id
              left join public.ports po on po.id = f.port_id
              left join public.sea_reaches rs on rs.port_id = f.port_id
              cross join lateral (select public.merchant_doing_at(sr.id, f.id, p_port, now()) as doing) d
             where exists (select 1 from public.standing_route_stops st
                            where st.route_id = sr.id and st.port_id = p_port)
          ) r), '[]'::jsonb)) end
$pm$;
comment on function world.port_merchants(uuid) is
  '0104 (owner row 121) + 0113: one harbour''s merchants — every merchant FLEET whose route calls '
  'here, with what she is doing (public.merchant_doing_at), her loop, and her total level (the '
  'company''s four skills summed through public.skill_level). Read at a tap, not on the beat: '
  'world.sea_traffic serves the whole world every 3 s and must not grow. Dark until '
  'npc_traders_switch(true); authenticated-only; a player''s fleet is never a row.';

-- ── 3. THE WALL, RESTATED ──────────────────────────────────────────────────────────────────────
-- `create or replace` keeps the ACL; it is restated so the grant is read here and not inferred.
revoke all on function world.port_merchants(uuid) from public, anon;
grant execute on function world.port_merchants(uuid) to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_lis    uuid;
  v_fnc    uuid;
  v_leg    jsonb;
  v_back_c jsonb;
  v_m      uuid;
  v_m0     uuid;
  v_fleet  uuid;
  v_fleet0 uuid;
  v_out    jsonb;
  v_old    jsonb;
  v_row    jsonb;
  v_row0   jsonb;
  v_keys   text[];
  v_rows   int;
  v_after  int;
  v_dark   jsonb;
  -- AS FOUND, NOT AS SHIPPED (2026-10-14). Production runs with the merchants LIT (0101-0110 were
  -- pushed with the switch on), and the first push of this file died here on "lit at apply time".
  -- Every claim below holds in either state, and the world is left exactly as it was found.
  v_was_on boolean := public.npc_traders_on();
begin
  -- (a) THE WALL DID NOT MOVE: authenticated reads, anon does not.
  if not has_function_privilege('authenticated', 'world.port_merchants(uuid)', 'execute')
     or has_function_privilege('anon', 'world.port_merchants(uuid)', 'execute') then
    raise exception '0113 self-assert FAIL: world.port_merchants is not exactly authenticated-only';
  end if;

  -- (b) THE PRE-IMAGE IS REALLY THERE TO COMPARE AGAINST — a vacuous comparison would be worse
  --     than none.
  if to_regprocedure('pg_temp.pm_before_0113(uuid)') is null then
    raise exception '0113 self-assert FAIL: the pre-image was not kept';
  end if;

  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  if v_lis is null or v_fnc is null then
    raise exception '0113 self-assert FAIL: LIS or FNC is not a port';
  end if;

  -- (c) DARK, THE READ IS UNCHANGED: the same four top-level keys, no rows, no level to be read.
  --     Dark by the flag inside a rolled-back block, so a lit world is asked too.
  begin
    update public.world_config set value = 'false'::jsonb where key = 'npc_traders_enabled';
    v_dark := world.port_merchants(v_lis);
    if v_dark is distinct from pg_temp.pm_before_0113(v_lis)
       or (v_dark->>'enabled')::boolean or jsonb_array_length(v_dark->'merchants') <> 0 then
      raise exception '0113 self-assert FAIL: dark, the read differs from its pre-image or serves rows: %',
        left(v_dark::text, 200);
    end if;
    raise exception 'ROLLBACK_0113_DARK';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0113_DARK' then raise; end if;
  end;

  -- (d) LIT, OVER THE REAL ROSTER PUT TO SEA BY THE ONE SWITCH, with two probe companies whose
  --     levels are KNOWN. Rolled back to the byte.
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    -- Lit already (production), the roster is at sea and the switch is not run again.
    if not v_was_on then perform public.npc_traders_switch(true); end if;
    if not public.npc_traders_on() then
      raise exception '0113 self-assert FAIL: the probe could not switch the merchants on';
    end if;

    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches b
     where a.port_id = v_lis and b.port_id = v_fnc;
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);

    -- A company that has studied two skills: 2 + 3 = 5, and nothing else counts.
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa da Escola', 'alt_company', 'Casa do Estudo', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Letrado',
      'blurb', 'A probe company founded so a harbour can be asked what her level is.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9113,
      'skills', jsonb_build_object('SEAMANSHIP', 2, 'NAVIGATION', 3),
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Letrada', 'roster_ord', 9113, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Letrada')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select fleet_id into v_fleet from public.npc_fleets where player_id = v_m;
    -- A company that has studied NOTHING: the absence of a row is the level, and it is 0, not null.
    v_m0 := public.npc_found(jsonb_build_object(
      'company', 'Casa Iletrada', 'alt_company', 'Casa Rude', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Rude',
      'blurb', 'A probe company that never went to the academy, so the read must say nought.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9114,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Rude', 'roster_ord', 9114, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Rude')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select fleet_id into v_fleet0 from public.npc_fleets where player_id = v_m0;
    if v_fleet is null or v_fleet0 is null then
      raise exception '0113 self-assert FAIL: a probe merchant was founded without a fleet';
    end if;
    -- Both lie at Lisbon, where the list the owner asked for would show them.
    update public.fleets set port_id = v_lis, status = 'DOCKED', lat = null, lon = null
     where id in (v_fleet, v_fleet0);

    v_out := world.port_merchants(v_lis);
    v_old := pg_temp.pm_before_0113(v_lis);
    v_rows := jsonb_array_length(v_out->'merchants');
    if not (v_out->>'enabled')::boolean or v_rows < 2 then
      raise exception '0113 self-assert FAIL: lit, LIS served % row(s) — nothing below would mean anything', v_rows;
    end if;

    -- (e) THE PRE-IMAGE PLUS ONE KEY, BYTE FOR BYTE. Strike `level` from every row and the two
    --     reads must agree — the order, every other key, the top level. Within one transaction
    --     now() is one instant, so `at` agrees too.
    if (select jsonb_agg(x - 'level') from jsonb_array_elements(v_out->'merchants') x)
         is distinct from v_old->'merchants'
       or (v_out - 'merchants') is distinct from (v_old - 'merchants') then
      raise exception '0113 self-assert FAIL: with level struck out the read is not its pre-image';
    end if;

    -- (f) EVERY ROW'S LEVEL IS THE SUM OF public.skill_level OVER THE FOUR SKILLS, read back
    --     independently per company — not only the probes', every merchant the switch put to sea.
    if exists (select 1
                 from jsonb_array_elements(v_out->'merchants') x
                 join public.fleets f on f.id = (x->>'id')::uuid
                where jsonb_typeof(x->'level') <> 'number'
                   or (x->>'level')::int is distinct from
                      (select coalesce(sum(public.skill_level(f.player_id, sk.code)), 0)::int
                         from public.skills sk)) then
      raise exception '0113 self-assert FAIL: a row''s level is not the sum of its company''s skill levels';
    end if;
    if (select count(*) from public.skills) <> 4 then
      raise exception '0113 self-assert FAIL: the world keeps % skills, not the four the header names',
        (select count(*) from public.skills);
    end if;

    -- (g) THE TWO PROBES READ WHAT WAS PLANTED: 5, and 0 (a number, never null).
    select x into v_row  from jsonb_array_elements(v_out->'merchants') x where (x->>'id')::uuid = v_fleet;
    select x into v_row0 from jsonb_array_elements(v_out->'merchants') x where (x->>'id')::uuid = v_fleet0;
    if v_row is null or v_row0 is null then
      raise exception '0113 self-assert FAIL: a probe lying at LIS is not a row of LIS';
    end if;
    if (v_row->>'level')::int <> 5 then
      raise exception '0113 self-assert FAIL: SEAMANSHIP 2 + NAVIGATION 3 was served as level %', v_row->>'level';
    end if;
    if jsonb_typeof(v_row0->'level') <> 'number' or (v_row0->>'level')::int <> 0 then
      raise exception '0113 self-assert FAIL: a company that studied nothing was served level %', v_row0->'level';
    end if;

    -- (h) POSITIVE CONTROL: raise one skill by one and the read moves by exactly one.
    update public.player_skills ps set level = 3
      from public.skills sk
     where sk.id = ps.skill_id and ps.player_id = v_m and sk.code = 'SEAMANSHIP';
    select (x->>'level')::int into v_after
      from jsonb_array_elements(world.port_merchants(v_lis)->'merchants') x
     where (x->>'id')::uuid = v_fleet;
    if v_after <> 6 then
      raise exception '0113 self-assert FAIL: one level raised by one, the read moved 5 -> %', v_after;
    end if;

    -- (i) THE KEY SET IS THE CONTRACT: 0104's row plus `level`, and the top level untouched.
    v_keys := array(select k from jsonb_object_keys(v_row) k order by k collate "C");
    if v_keys <> array['anchor', 'company', 'doing', 'hulls', 'id', 'ink', 'level', 'name', 'nation_code',
                       'next_lap_at', 'port', 'roadstead', 'ships', 'status', 'stops', 'voyage'] then
      raise exception '0113 self-assert FAIL: a merchant row''s keys are %', v_keys;
    end if;
    if array(select k from jsonb_object_keys(v_out) k order by k collate "C")
       <> array['at', 'enabled', 'merchants', 'port'] then
      raise exception '0113 self-assert FAIL: the read''s top-level keys moved';
    end if;

    -- (j) DARK AGAIN, `level` is not a side door onto a company's skills.
    update public.world_config set value = 'false'::jsonb where key = 'npc_traders_enabled';
    if (world.port_merchants(v_lis)->>'enabled')::boolean
       or jsonb_array_length(world.port_merchants(v_lis)->'merchants') <> 0 then
      raise exception '0113 self-assert FAIL: dark, the harbour still serves rows';
    end if;

    raise exception 'ROLLBACK_0113';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0113' then raise; end if;
  end;

  -- EVERYTHING ABOVE WAS UNDONE: the switch is as it was found, and the probes are gone.
  if public.npc_traders_on() is distinct from v_was_on
     or exists (select 1 from public.players where company_name in ('Casa da Escola', 'Casa Iletrada')) then
    raise exception '0113 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0113 self-assert ok: A HARBOUR''S MERCHANTS CARRY THEIR LEVEL. Dark, the read is '
    'its pre-image to the byte. Lit over the real roster plus two probes at LIS (% rows), with '
    '`level` struck from every row the read IS its pre-image; every row''s level is the sum of '
    'public.skill_level over the four skills; 2 + 3 read 5, nothing read 0 (a number), one level '
    'raised by one moved the read 5 -> 6; the row''s keys are 0104''s plus level and the top level '
    'is unchanged; dark again, no rows. Authenticated-only. Rolled back; the switch is as found.',
    v_rows;
end $$;
