-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0372 — CROWN AND PIRATE HULLS FIGHT AT LEVEL FIVE: world_config `npc_ship_level_enabled` false -> true, and the one writer of 0344 run once. One knob row, the level rows of the
--   crown hulls (public.ship_xp, through public.crown_hull_level_fix alone) and one news row. No function, no table, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. Owner row 288 and docs/WORLD_POWERS.md 2.3: "Crown and pirate hulls take a fixed level by knob, npc_ship_level 5." 0344 built it dark behind this one switch.
--   Owner, 2026-11-13 (row 324): "do all, make everything work. open them if everything is built and is workable." This file is that one light (the form of 0178 and 0179).
-- WHAT THE SWITCH TURNS ON (every reader is live already, 0344; none is touched here): every hull of a public.crown_house (a crown cargo ship, a navy ship, a pirate ship) carries
--   public.level_points(npc_ship_level): level 5. Through world.ship_stats that is +4 handling, +6 accuracy and +0.6 sighting (ship_level_*_per_level 1, 1.5, 0.15), where levels_bite is
--   on. The job byeharu-voyage:crown-hull-level keeps new hulls and refits at it every ten minutes; this file runs the same writer once, so the level stands at the deploy, not ten
--   minutes later, and so a world with no job runner (the local world) has it too.
-- WHAT IT DOES TO A FIGHT, MEASURED (scripts/ops/harness/crown-level/raids-scene.sql; the tables are in docs/dev-log/2026-11-13-light-npc-levels.md):
--   * A RAID ON A VOYAGE DOES NOT CHANGE. The raiders of a raid are a figure (the sea's danger, or voyage.pirate_strength of a named pirate ship: her class's attack, crew and tier by
--     the hull she has left) that voyage.raider_hulls turns into class hulls. No level is read. A barca, an armed trader and a nau against 1, 2 and 5 raider hulls: the same outcomes at
--     level 1 and at level 5, to the fight.
--   * A FIGHT THAT READS THE CROWN HULL ITSELF (voyage.fleet_hulls) does: a battle where a company attacks a cargo, navy or pirate ship (dark behind attack_enabled), the navy coming
--     to such a battle, the navy against a pirate ship, and a crown cargo ship set upon by a raid (she shoots a little straighter).
-- GUARD (the file refuses, and nothing is written, when any of these is not so):
--   * 0344's writer and 0347's news exist;
--   * the switch row exists and reads exactly false; npc_ship_level reads 5 (the level the tables were measured at);
--   * dark posture: no hull of a crown house holds a ship_xp row (0344's own after-check).
-- SELF-ASSERT: every crown hull that stood before the write is level 5 after it. No level row of a merchant or a company is compared whole: those rows grow under live play (a
--   voyage, the merchants' own job), so the probe holds that rule instead. On a probe navy hull and a probe merchant of this file's own, rolled back: the probe hull takes level 5 and her stats move by
--   exactly four levels of the knobs; the merchant is never written; THE ROLLBACK PLAYED inside the probe (the switch set false, the writer run) takes the row away and her stats are as
--   before. The catalog: no function moved; exactly one world_config row moved; the news row is one row.
-- ALTERS LIVE PLAY: its own window, a 30-minute after-check (scripts/ops/harness/crown-level/after-light.sql, and scripts/ops/harness/raid/after-check.sh <start> <end>: the paired
--   raid check must read as before, since a raid reads no level).
-- ROLLBACK (forward; a draft is scripts/ops/harness/crown-level/rollback-0372.sql): the switch set back to false and the writer run once (or left to the job: within ten minutes it
--   deletes every such row and the hulls are level 1). The one-line form (owner only): update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled';
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0372', 'Navy and pirate ships: level 5', '해군·해적선: 레벨 5') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0372 - deploys after 0371 (raid_orders_enabled), in its own window. It names no function of 0364 to 0371.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

create temp table crown_before_0372 on commit drop as
select s.id as ship_id, s.player_id from public.ships s where public.crown_house(s.player_id);

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_m           int;
  v_again       int;
  v_hulls       int;
  v_written     int;
  v_fn_before   text;
  v_cfg_before  text;
  v_lived       boolean := false;
  v_nat         uuid;
  v_port        uuid;
  v_pl          uuid;
  v_fl          uuid;
  v_sh          uuid;
  v_mpl         uuid;
  v_msh         uuid;
  v_dark        jsonb;
  v_lit         jsonb;
  v_ms_write    numeric;
  v_ms_probe    numeric;
  c_key         constant text := 'npc_ship_level_enabled';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['public.crown_hull_level_fix(uuid)', 'public.crown_house(uuid)', 'public.level_points(integer)', 'public.level_from_points(numeric)',
                                        'world.ship_stats(uuid)', 'public.news_update(text,text,text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.ship_xp') is null then
    raise exception '0372 refuses: the crown hulls'' level (0344) or the news (0347) are not in this world';
  end if;
  if (select c.value from public.world_config c where c.key = c_key) is distinct from 'false'::jsonb then
    raise exception '0372 refuses: % is not false in this world (it reads %): this file lights it once, from dark', c_key, (select c.value from public.world_config c where c.key = c_key);
  end if;
  if public.wc_num('npc_ship_level') is distinct from 5 then
    raise exception '0372 refuses: npc_ship_level reads %, not the 5 its tables were measured at (scripts/ops/harness/crown-level/raids-scene.sql)', public.wc_num('npc_ship_level');
  end if;
  if exists (select 1 from public.ship_xp x join crown_before_0372 b on b.ship_id = x.ship_id) then
    raise exception '0372 refuses: dark, % crown or pirate hull(s) already hold a level row', (select count(*) from public.ship_xp x join crown_before_0372 b on b.ship_id = x.ship_id);
  end if;
  select count(*) into v_hulls from crown_before_0372;

  -- ── 1. BEFORE: the catalog and every OTHER knob ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c where c.key <> c_key;

  -- ── 2. THE LIGHT ──
  update public.world_config
     set value = 'true'::jsonb, updated_at = now(), description = description || ' LIT by 0372 (owner row 324, 2026-11-13).'
   where key = c_key and value = 'false'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.wc(c_key) is distinct from 'true'::jsonb then
    raise exception '0372 self-assert FAIL: % row(s) written, and the switch reads %', v_n, public.wc(c_key);
  end if;

  -- ── 3. THE WRITER, ONCE, for the houses that stood before the write (the job takes every later hull within ten minutes) ──
  v_t := clock_timestamp();
  v_written := 0;
  for v_pl in select distinct b.player_id from crown_before_0372 b loop
    v_n := public.crown_hull_level_fix(v_pl);   -- its own statement: a volatile writer (0344's note)
    v_written := v_written + v_n;
  end loop;
  if exists (select 1 from crown_before_0372 b join public.ships s on s.id = b.ship_id
              where public.level_from_points(coalesce((select x.xp from public.ship_xp x where x.ship_id = b.ship_id), 0)) is distinct from 5) then
    raise exception '0372 self-assert FAIL: lit, a crown or pirate hull that stood before the write is not level 5 (% written of % hulls)', v_written, v_hulls;
  end if;
  v_ms_write := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 4. THE SELF-ASSERT: a probe navy hull and a probe merchant of this file's own, rolled back ──
  v_t := clock_timestamp();
  begin
    v_nat  := (select n.id from public.nations n where n.code = 'PRT');
    v_port := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Crown Navy 0372', v_nat, 0, true) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Navy ship 0372', v_port);
    v_sh := public.commission_ship(v_pl, v_fl, public.wc_text('navy_ship_class'), 'Navy ship 0372', true, false);
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port)
    values (v_fl, v_pl, v_nat, 1 + coalesce((select max(x.ord) from public.navy_ships x where x.nation_id = v_nat), 0), v_port, v_port);
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa 0372', v_nat, 0, true) returning id into v_mpl;
    v_msh := public.commission_ship(v_mpl, public.form_fleet(v_mpl, 'Casa 0372', v_port), public.wc_text('navy_ship_class'), 'Casa 0372', true, false);
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';   -- the stats read the level in force

    v_dark := world.ship_stats(v_sh);   -- a hull just laid: no row yet, level 1
    v_n := public.crown_hull_level_fix(v_pl);
    v_m := public.crown_hull_level_fix(v_mpl);
    v_again := public.crown_hull_level_fix(v_pl);
    if v_n <> 1 or v_m <> 0 or v_again <> 0
       or (select public.level_from_points(x.xp) from public.ship_xp x where x.ship_id = v_sh) is distinct from 5 or exists (select 1 from public.ship_xp x where x.ship_id = v_msh) then
      raise exception '0372 self-assert FAIL: lit, a new navy hull is not written once to level 5, or a merchant is written (% / % / %)', v_n, v_m, v_again;
    end if;
    v_lit := world.ship_stats(v_sh);
    if (v_lit ->> 'handling')::numeric - (v_dark ->> 'handling')::numeric <> 4 * public.wc_num('ship_level_handling_per_level')
       or (v_lit ->> 'accuracy')::numeric - (v_dark ->> 'accuracy')::numeric <> 4 * public.wc_num('ship_level_accuracy_per_level')
       or (v_lit ->> 'sighting')::numeric - (v_dark ->> 'sighting')::numeric <> 4 * public.wc_num('ship_level_sighting_per_level')
       or (v_lit - 'handling' - 'accuracy' - 'sighting') <> (v_dark - 'handling' - 'accuracy' - 'sighting') then
      raise exception '0372 self-assert FAIL: level 5 does not move handling, accuracy and sighting by exactly four levels of their knobs, and nothing else: level 1 %, level 5 %', v_dark, v_lit;
    end if;
    -- THE ROLLBACK, PLAYED: the switch set back and the writer run: the row goes and she reads as before
    update public.world_config set value = 'false'::jsonb where key = c_key;
    v_n := public.crown_hull_level_fix(v_pl);
    if v_n <> 1 or exists (select 1 from public.ship_xp x where x.ship_id = v_sh) or world.ship_stats(v_sh) <> v_dark then
      raise exception '0372 self-assert FAIL: with the switch set back the row is not gone or the hull does not read as before (% deleted)', v_n;
    end if;
    raise exception using errcode = 'ZX372', message = 'PROBE_ROLLBACK_0372';
  exception when sqlstate 'ZX372' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0372 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name in ('Crown Navy 0372', 'Casa 0372')) then
    raise exception '0372 self-assert FAIL: a probe house outlived the probe';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 5. AFTER: lit, and nothing else moved ──
  if public.wc(c_key) is distinct from 'true'::jsonb then
    raise exception '0372 self-assert FAIL: the switch is not lit after the probe';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0372 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c where c.key <> c_key) <> v_cfg_before then
    raise exception '0372 self-assert FAIL: another world_config row moved: this file writes one';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0372', 'Navy and pirate ships: level 5', '해군·해적선: 레벨 5');
  if (select count(*) from public.world_news w where w.key = 'update:0372') <> 1 then
    raise exception '0372 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0372 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0372 timings: the writer over % crown or pirate hull(s) (% row(s) written) % ms; the probe % ms', v_hulls, v_written, v_ms_write, v_ms_probe;
  raise notice '0372 self-assert ok: CROWN AND PIRATE HULLS FIGHT AT LEVEL FIVE. npc_ship_level_enabled was false and is true; npc_ship_level is 5. % crown or pirate hull(s) stood before the write, none held a level row, and each is level 5 now (% row(s) written by public.crown_hull_level_fix). A probe navy hull took level 5 in one write and her handling, accuracy and sighting moved by exactly four levels of their knobs; a probe merchant was never written; with the switch set back and the writer run (the rollback, played and rolled back) her row is gone and she reads as before. No function moved, no other knob moved, its UPDATE row is one row. % ms.',
    v_hulls, v_written, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
