-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0337 — A CAPTAIN HAS A SHEET: world.captain_stats(code), a read. NO TABLE, NO KNOB, NO SWITCH, NO ROW. It changes no fight.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05 (row 288): "we also need levels and stats for characters as well as ships ... these factors will be the power and ability of each company / ships. captains should also have stats".
-- docs/WORLD_POWERS.md section 2.4 (W3): a sheet, DERIVED and stored nowhere, "decided by default: no new stored stat, because a stored stat would be a second authority beside trait_effects". Levels are live on prod
-- (levels_bite true since 2026-11-06 19:50 UTC), so a captain's level now bites; this file reads it and lights nothing.
--
-- WHAT THIS FILE ADDS (read only, STABLE, one function, nothing else moved):
--   world.captain_stats(p_code text)   The sheet of YOUR signing of one captain: five stats, each her level in its track and the parts she adds. Granted to authenticated, as its siblings.
-- THE HUNK (once, reversing): public.client_rpc_entry_points gains the one row, at the head of the list as 0310 and 0331 put theirs.
--
-- THE FIVE STATS (docs/WORLD_POWERS.md 2.4; EN / KO are the client's words, src/lib/i18n/dict/books.ts):
--   gunnery     / 포술   her Combat level      + accuracy, reach        what her Gunner traits add to her SHIP
--   boarding    / 백병   her Combat level      + attack                 what her Boarder traits add to her SHIP
--   seamanship  / 항해   her Exploration level + speed, storm, supplies what her Navigator, Pilot and Provisioner traits add to her FLEET
--   trade       / 교역   her Trading level     + hold, spread           what her Quartermaster and Purser traits add to her FLEET
--   care        / 돌봄   (no level)            + crew_saved, homesick_relief, hospitality   what her Surgeon traits add to her FLEET, and the Hospitality her company holds
-- This list is the ONE place the five groups are decided. The client regroups nothing; it prints what is served, in the order served.
--
-- NOTHING IS COMPUTED HERE THAT ANOTHER READER OWNS.
--   level  public.captain_level (0160): her level in force, never above her company's in the same track. Three calls, one per track (combat serves both Gunnery and Boarding).
--   part   HER OWN TERM: what public.crew_terms (0157) gives for her seat, effect by effect, in per cent: greatest(base, her grade's floor once promoted) x the trait's mult x her level x her cabin's rate x homesickness.
--          That is the arithmetic public.crew_pct sums and world.crew_bonuses lists "by source", so the sheet is the lines of world.crew_bonuses that are hers, and no second rule of what a captain is worth exists.
--   line   public.trait_effect_words (0156) over the effect's own words in public.crew_effects: "+9.5% speed", as the trait lines and world.crew_bonuses print them. The server's English, as those are.
--   Hospitality is world.skill_pct(company, null, 'homesick'), the call public.crew_terms makes; it is the COMPANY's, so every seated captain of a company reads the same number.
-- A CAP IS THE CREW'S, NOT HERS. public.crew_pct caps the SUM of the terms of a crew at the effect's cap (25 %) and Command lifts it; the sheet shows what she brings, as world.crew_bonuses lists each source, and the crew's
-- total is crew_bonuses'. Below the cap and without Command the parts of a crew add up to crew_pct x 100 to the digit, and a captain alone in her crew reads crew_pct itself (proof 44 holds both, and holds the cap and the
-- lift: crew_pct x 100 is least(the parts' sum x the lift, the cap)). So the sheet never disagrees with the fight: the fight reads crew_pct, and crew_pct is built from these terms.
--
-- WHY NOT HER SLICE OF crew_pct (built first, priced on prod, read only, 2026-11-07, then DELETED from this file): crew_pct x 100 cut by her share of the terms always adds up to the crew's answer, but it is one crew_pct call
-- for every part she has, and each call reads the whole fleet's terms again: 45 to 134 ms a call on a three-captain fleet, so 150 to 500 ms to open a card, where her own terms are one crew_terms call, 28 to 43 ms.
--
-- DECIDED BY DEFAULT (the owner may reverse any of these afterwards):
--   * A STAT IS A LEVEL AND ITS PARTS, NOT A BLENDED SCORE. docs/WORLD_POWERS.md writes "Combat level + grade floor x seated Gunner share"; added together a level and a per cent are a number nothing in the game reads, and a number
--     nothing reads is the second authority the design refuses. The grade floor and the cabin rate are inside the parts already (public.crew_terms), so the sheet shows their sum, once.
--   * BY CODE, NOT BY UUID. Every captain verb names the officer (cmd.captain_traits_set, cmd.promote_captain, cmd.seat_captain) and finds the caller's own signing; world.captains serves no signing id, and adding one would
--     move a live body for nothing. A caller who keeps no such captain, and a signed-out caller, read null: a blank, never an error, and never another house's captain.
--   * SHE SITS NOWHERE: `seated` false, every part's pct null (there is no crew to bring a term to) and public.crew_terms is not read. Her levels are still hers and are served. SHE SITS, AND A ROLE IS NOT HERS: pct 0, no line.
--   * A SHIP EFFECT (accuracy, reach, attack) WHILE combat_bite IS OFF: pct null. It does nothing yet (the trait card says "Works when combat arrives."), and a sheet must not claim it.
--   * NO XP ROW, NO LEVEL: a signing without public.captain_xp reads level null, not a made-up 1.
--   * TRADE DOES NOT COUNT THE SEVENTEEN CATEGORY TRADERS: category_spread is per good (public.crew_pct takes the good), and the design lists "hold and spread". A Gem trader's Trade stat is her Trading level.
--   * NPC CAPTAINS HAVE NO SHEET: a merchant's captain is nobody's signing, and her hull fights on class, level and gear (docs/WORLD_POWERS.md 2.4).
--
-- NOT TOUCHED: public.crew_pct, public.crew_terms, public.captain_level, public.trait_effects, public.crew_effects, world.captains, world.captain_card, world.crew_bonuses, world.ship_view, voyage.fight, every table, every
-- switch, every knob. The Power line of a ship (docs/WORLD_POWERS.md 2.3) is the client's: attack, accuracy, reach, armour, sighting, served by world.ship_view already.
--
-- COST: one resolve by (player, code); one seat; three public.captain_level calls (each reads public.player_progress, a scan of the company's ledger and events, only above level 1); ONE public.crew_terms call, for her fleet,
-- and only when she sits; one world.skill_pct, only when she sits and skills bite. Read when a card opens, and again on the world's beat while it stays open (the rule of every served read), never by a job.
-- MEASURED on prod, read only, 2026-11-07, on a real three-captain fleet: her terms and Hospitality 41 to 57 ms in five reads of six, 119 in the sixth (median 47), the three levels 4 to 15 ms at level 1 and about 22 ms more for each track above 1: docs/dev-log/2026-11-07-a-captain-has-a-sheet.md.
-- ROLLBACK (forward, owner only): a new migration dropping world.captain_stats(text) and reversing the hunk. Nothing else depends on it.
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows (no money moves, no harbour's purse is touched). The live read is proved in CI: scripts/db/proofs/44_a_captain_has_a_sheet.sql.
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- VERSION: 0337 - prod head 0336 (read 2026-11-07 ~03:00 UTC). 0336 is origins-fence's and hunks public.cargo_origins; this file shares no function with it. The registry row is anchored on a line 0336 did not move (read on prod: once).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_def         text;
  v_pre         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_acl_levels  text;
  v_off         uuid;
  v_code        text;
  v_pl          uuid;
  v_fl          uuid;
  v_sh          uuid;
  v_po          uuid;
  v_r           jsonb;
  v_x           jsonb;
  v_crew        numeric;
  v_lived       boolean := false;
  c_uid  constant uuid := '00000000-0337-4000-8000-000000000001';
  c_old  constant text := $h$      ('world',       'navy_ship_card',        'uuid'),
$h$;
  c_new  constant text := $h$      ('world',       'navy_ship_card',        'uuid'),
      -- 0337: one captain's sheet, read when her card opens. At the head, as above.
      ('world',       'captain_stats',         'text'),
$h$;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('world.captain_stats(text)') is not null then
    raise exception '0337 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.crew_terms(uuid,timestamp with time zone)') is null or to_regprocedure('public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)') is null
     or to_regprocedure('public.captain_level(uuid,text)') is null or to_regprocedure('public.trait_effect_words(text,numeric,text)') is null
     or to_regprocedure('world.skill_pct(uuid,uuid,text)') is null or to_regprocedure('public.combat_bite_on()') is null or to_regprocedure('public.skills_bite_on()') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('world.levels()') is null then
    raise exception '0337 refuses: a reader it composes is not in this world (0157 / 0160 / 0168 / 0325)';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.proname <> 'client_rpc_entry_points';
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  select coalesce(p.proacl::text, '') into v_acl_levels from pg_proc p where p.oid = 'world.levels()'::regprocedure;

  -- ── 1. THE SHEET ──
  execute $f$
create function world.captain_stats(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0337: A CAPTAIN HAS A SHEET (docs/WORLD_POWERS.md 2.4). YOUR signing of the captain named by p_code: {code, seated, stats[]}, each stat {stat, track, level, parts[]}, each part {effect, pct, line}.
-- A level is public.captain_level. A part is HER OWN TERM, what public.crew_terms gives for her seat in per cent: the arithmetic public.crew_pct sums and world.crew_bonuses lists by source. A cap is the crew's, not hers.
-- null: a caller who keeps no such captain (and a signed-out caller). pct null: she sits nowhere, or a ship effect is asked while combat_bite is off. pct 0: she sits and the role is not hers (no line).
declare
  v_player uuid := public.current_player_id();
  v_po     uuid;
  v_code   text;
  v_ship   uuid;
  v_fleet  uuid;
  v_lv     jsonb;
  v_mine   jsonb := '{}'::jsonb;
  v_hosp   numeric;
  v_stats  jsonb;
begin
  select po.id, o.code into v_po, v_code
    from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = v_player and o.code = upper(btrim(coalesce(p_code, '')));
  if v_po is null then
    return null;
  end if;
  select cs.ship_id, s.fleet_id into v_ship, v_fleet
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id
   where cs.player_officer_id = v_po;
  if exists (select 1 from public.captain_xp x where x.player_officer_id = v_po) then
    v_lv := jsonb_build_object('combat', public.captain_level(v_po, 'combat'),
                               'exploration', public.captain_level(v_po, 'exploration'),
                               'trading', public.captain_level(v_po, 'trading'));
  end if;
  if v_ship is not null then
    select coalesce(jsonb_object_agg(x.effect, x.v), '{}'::jsonb) into v_mine
      from (select t.effect, sum(t.value_pct) as v from public.crew_terms(v_fleet) t where t.player_officer_id = v_po group by t.effect) x;
    v_hosp := case when public.skills_bite_on() then coalesce(world.skill_pct(v_player, null, 'homesick'), 0) end;
  end if;
  with
    def(stat_ord, stat, track, part_ord, effect) as (values
      (1, 'gunnery',    'combat',      1, 'accuracy'),
      (1, 'gunnery',    'combat',      2, 'reach'),
      (2, 'boarding',   'combat',      1, 'attack'),
      (3, 'seamanship', 'exploration', 1, 'speed'),
      (3, 'seamanship', 'exploration', 2, 'storm'),
      (3, 'seamanship', 'exploration', 3, 'supplies'),
      (4, 'trade',      'trading',     1, 'hold'),
      (4, 'trade',      'trading',     2, 'spread'),
      (5, 'care',       null,          1, 'crew_saved'),
      (5, 'care',       null,          2, 'homesick_relief')),
    part as (
      select d.stat_ord, d.stat, d.track, d.part_ord, d.effect, ce.words,
             case when v_ship is null then null
                  when ce.scope = 'ship' and not public.combat_bite_on() then null
                  else coalesce((v_mine ->> d.effect)::numeric, 0) end as pct
        from def d join public.crew_effects ce on ce.code = d.effect
      union all
      select 5, 'care', null, 3, 'hospitality', (select ce.words from public.crew_effects ce where ce.code = 'homesick_relief'), v_hosp)
  select jsonb_agg(jsonb_build_object('stat', s.stat, 'track', s.track, 'level', (v_lv ->> s.track)::int, 'parts', s.parts) order by s.stat_ord)
    into v_stats
    from (select p.stat_ord, p.stat, p.track,
                 jsonb_agg(jsonb_build_object('effect', p.effect, 'pct', p.pct,
                                              'line', case when p.pct > 0 then public.trait_effect_words(p.words, p.pct, null) end) order by p.part_ord) as parts
            from part p group by p.stat_ord, p.stat, p.track) s;
  return jsonb_build_object('code', v_code, 'seated', v_ship is not null, 'stats', v_stats);
end
$body$
  $f$;

  revoke all on function world.captain_stats(text) from public, anon;
  grant execute on function world.captain_stats(text) to authenticated;

  -- ── 2. THE HUNK: the registry row (once, and reversing) ──
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  v_pre := v_def;
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0337 self-assert FAIL: the registry hunk occurs % time(s), not once: the deployed body is not what this file was written against', v_n;
  end if;
  execute replace(v_def, c_old, c_new);
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception '0337 self-assert FAIL: the registry hunk is not in the new body once';
  end if;
  if replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0337 self-assert FAIL: public.client_rpc_entry_points does not reverse to its pre-image';
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.proname <> 'client_rpc_entry_points'
         and p.oid::regprocedure::text <> 'world.captain_stats(text)') <> v_fn_before then
    raise exception '0337 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0337 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0337 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.captain_stats(text)'::regprocedure)
     is distinct from (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.levels()'::regprocedure) then
    raise exception '0337 self-assert FAIL: the sheet is not STABLE, definer, with the search path its sibling world.levels() has';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.captain_stats(text)'::regprocedure) <> v_acl_levels
     or has_function_privilege('anon', 'world.captain_stats(text)', 'execute') or not has_function_privilege('authenticated', 'world.captain_stats(text)', 'execute') then
    raise exception '0337 self-assert FAIL: the grants are not its sibling''s: the read to authenticated only';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'captain_stats' and e.arg_types = 'text' and e.fn is not null) then
    raise exception '0337 self-assert FAIL: the read is not in the client registry';
  end if;
  if world.captain_stats('ELCANO') is not null or world.captain_stats(null) is not null then
    raise exception '0337 self-assert FAIL: a caller with no company reads a sheet';
  end if;

  -- ── 4. THE SELF-ASSERT: a probe house of its own rows, every one rolled back. No money moves, no harbour's purse is touched, no knob is written, and nothing is asserted but the probe's own keys. ──
  begin
    select o.id, o.code into v_off, v_code
      from public.officers o join public.captain_job j on j.officer_id = o.id
     where j.job = 'NAVIGATOR'
     order by o.code limit 1;   -- a navigator: speed is a fleet effect the dark arm reads too, so the probe stands in a dark world and a lit one alike
    if v_off is null then
      raise exception '0337 self-assert FAIL: the probe found no navigator to sign';
    end if;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Folha 0337', (select n.id from public.nations n where n.code = 'PRT'), 0, false)
    returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Folha', (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR'));
    v_sh := public.commission_ship(v_pl, v_fl, 'barca', 'Folha', true, true);
    insert into public.player_officers (player_id, officer_id) values (v_pl, v_off) returning id into v_po;
    insert into public.captain_active (player_officer_id, trait)
      select v_po, ct.trait from public.captain_traits ct where ct.officer_id = v_off and ct.ord = 1;
    insert into public.captain_state (player_officer_id, grade, home_seen_at)
      select v_po, cp.grade, now() from public.captain_profile cp where cp.officer_id = v_off;
    insert into public.captain_xp (player_officer_id) values (v_po);
    perform public.captain_seat_put(v_po, v_sh, 1);
    perform cmd.assume_identity(c_uid);

    v_r := world.captain_stats(lower(v_code));   -- the code is read as the verbs read it: upper-cased, trimmed
    if v_r is null or (v_r ->> 'code') <> v_code or (v_r ->> 'seated')::boolean is not true or jsonb_array_length(v_r -> 'stats') <> 5
       or (select string_agg(s ->> 'stat', ',' order by o2) from jsonb_array_elements(v_r -> 'stats') with ordinality x(s, o2)) <> 'gunnery,boarding,seamanship,trade,care'
       or (select string_agg(coalesce(s ->> 'track', '-'), ',' order by o2) from jsonb_array_elements(v_r -> 'stats') with ordinality x(s, o2)) <> 'combat,combat,exploration,trading,-' then
      raise exception '0337 self-assert FAIL: the sheet is not five stats in order for a seated probe captain: %', v_r;
    end if;
    v_crew := public.crew_pct(v_fl, v_sh, 'speed') * 100;
    v_x := v_r -> 'stats' -> 2 -> 'parts' -> 0;
    if (v_x ->> 'effect') <> 'speed' or (v_x ->> 'pct')::numeric <> v_crew or v_crew <= 0 or (v_x ->> 'line') is distinct from public.trait_effect_words('+{pct}% speed', v_crew, null) then
      raise exception '0337 self-assert FAIL: a captain alone in her crew does not read crew_pct itself: sheet %, crew_pct x 100 = %', v_x, v_crew;
    end if;
    if (select count(*) from jsonb_array_elements(v_r -> 'stats') s, jsonb_array_elements(s -> 'parts') p where (p ->> 'pct')::numeric > 0) <> 1 then
      raise exception '0337 self-assert FAIL: a navigator with her job alone active adds more than one part: %', v_r;
    end if;
    if (v_r -> 'stats' -> 2 ->> 'level')::int <> 1 or (v_r -> 'stats' -> 4 -> 'parts' -> 0 ->> 'pct')::numeric <> 0 then
      raise exception '0337 self-assert FAIL: a fresh signing is not level 1 with no Surgeon part: %', v_r;
    end if;
    perform public.captain_seat_put(v_po, null, null);
    v_r := world.captain_stats(v_code);
    if (v_r ->> 'seated')::boolean is not false or (v_r -> 'stats' -> 2 -> 'parts' -> 0 ->> 'pct') is not null or (v_r -> 'stats' -> 2 ->> 'level')::int <> 1 then
      raise exception '0337 self-assert FAIL: ashore, a captain does not read blank parts and her own level: %', v_r;
    end if;
    raise exception using errcode = 'ZX337', message = 'PROBE_ROLLBACK_0337';
  exception when sqlstate 'ZX337' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0337 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Folha 0337' or p.auth_uid = c_uid) then
    raise exception '0337 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0337 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0337 self-assert FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0337 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0337 self-assert ok: A CAPTAIN HAS A SHEET. One function, STABLE, to authenticated only, as world.levels(); one hunk, once and reversing; no other function, knob, table or row moved. A probe captain alone in her crew reads crew_pct x 100 (% points) and blank ashore; nothing of the probe survives. (proof 44 runs the rest in CI.) % ms.',
    round(v_crew, 4), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
