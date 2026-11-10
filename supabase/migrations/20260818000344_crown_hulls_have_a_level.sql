-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0344 — CROWN AND PIRATE HULLS HAVE A LEVEL: a cargo ship's, a navy ship's and a pirate ship's hull carry the fixed level npc_ship_level (5). DARK
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05 (docs/OWNER_REQUESTS.md row 288): "we also need levels and stats for characters as well as ships ... these factors will be the power and ability of each company / ships".
-- docs/WORLD_POWERS.md 2.3 (Part 1): "NPC hulls: merchants already have constant levels (npc_fix_level). Crown and pirate hulls take a fixed level by knob, npc_ship_level 5." Nothing built it:
-- MEASURED ON PROD, read only, 2026-11-10, head 0343 (levels_bite, navy_enabled, pirates_bite, convoys_enabled all true): 372 cargo, 6 navy and 3 pirate hulls, NONE with a public.ship_xp row, so every one
-- of them is level 1 and fights on her class alone, while a merchant's hull is level 1 to 4 (npc_fix_level) and a player's grows by the mile. voyage.settle writes no experience for any is_npc house (0127).
--
-- WHAT THIS FILE ADDS (one function, two knobs, one job; no table, no hunk of a live body):
--   public.crown_hull_level_fix(p_player uuid default null)   THE ONE WRITER of a crown or pirate hull's experience. A crown or pirate house is public.crown_house (0331, 0339: a cargo ship's, a navy
--       ship's or a pirate ship's house; never a merchant, a pirate merchant or a player, even one who built a crown class), read here and nowhere copied. It makes public.ship_xp of every hull of every
--       such house EXACTLY what the switch says: lit, public.level_points(npc_ship_level), the points that level begins at (as npc_fix_level writes a merchant's); dark, no row, which is level 1, the world
--       before this file. A reconcile, not a step: it writes only a row that differs and answers how many it wrote, so a second run answers 0. p_player narrows it to one house (the self-assert's probe).
--   npc_ship_level_enabled  false   THE switch (owner only). npc_ship_level  5   the level (docs/WORLD_POWERS.md 2.3).
--   pg_cron byeharu-voyage:crown-hull-level, every ten minutes: select public.crown_hull_level_fix(). A hull laid since, a refit (0322), the switch or the knob turned: within ten minutes, every hull reads it.
-- WHAT THE LEVEL BUYS: nothing new. Every effect reads public.ship_xp already, through the level in force (0127: world.ship_stats adds handling 1, accuracy 1.5, sighting 0.15 a level above 1, while levels_bite
-- is on; world.ship_slots). Lit at 5: +4 handling, +6 accuracy, +0.6 sighting on every such hull, in a battle (0323 reads world.ship_stats per hull), a raid, a hunt and on her card.
-- DARK PARITY BY CONSTRUCTION: dark the writer deletes only rows that do not exist (prod and CI: 0 such rows, asserted below), so every read is byte for byte the world before this file.
-- NOT TOUCHED: voyage.settle (a crown house is is_npc: no experience accrues, so nothing fights the fixed level), npc_fix_level, every reader of ship_xp, every table, every other knob and job.
-- DECIDED BY DEFAULT: dark, although 2.3 names no switch: lit, it moves every navy, pirate and armed cargo fight on prod, and a balance change is the owner's (the knob row is the design's number).
-- SELF-ASSERT (the catalog, then a probe house of its own rolled-back rows; no real hull is written, no real game step runs, docs/OPS_HEALTH.md section 4): the function is VOLATILE, definer, server-only;
-- no other function, knob, table, trigger or job moved; the posture reads zero; no crown hull has a row; on the probe navy hull and a probe merchant: lit level 5 and the stats by exactly the knobs, the
-- merchant untouched, a second run 0; dark again, the row gone. THE REAL PATHS ARE PROVED IN CI: proof 51, scripts/db/proofs/51_crown_hulls_have_a_level.sql. Mutation controls:
-- scripts/ops/harness/crown-level/proof-0344.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s. Reads: the catalog, ship_xp joined to crown houses (about 400 hulls).
-- ROLLBACK (forward, owner only): lit, update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled'; the next run (ten minutes) deletes every such row and the hulls are level 1.
--   To remove: a new migration unscheduling the job, dropping the function and the two knobs, after the switch is off and a run has passed.
-- VERSION: 0344 - prod head 0343 (read 2026-11-10). 0345 is another agent's; this file shares no body with anything (it re-cuts nothing).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_n           int;
  v_m           int;
  v_again       int;
  v_fn_before   text;
  v_meta_before text;
  v_cfg_before  text;
  v_rel_before  text;
  v_trig_before text;
  v_cron_before text;
  v_cron_after  text;
  v_entry       int;
  v_nat         uuid;
  v_port        uuid;
  v_pl          uuid;
  v_fl          uuid;
  v_sh          uuid;
  v_mpl         uuid;
  v_msh         uuid;
  v_dark        jsonb;
  v_lit         jsonb;
  v_lived       boolean := false;
  c_keys    constant text[] := array['npc_ship_level_enabled', 'npc_ship_level'];
  c_fn      constant text   := 'public.crown_hull_level_fix(uuid)';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and the readers it composes do ──
  if exists (select 1 from public.world_config c where c.key = any (c_keys)) or to_regprocedure(c_fn) is not null then
    raise exception '0344 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.crown_house(uuid)') is null or to_regprocedure('public.level_points(integer)') is null or to_regprocedure('public.level_from_points(numeric)') is null
     or to_regprocedure('world.ship_stats(uuid)') is null or to_regclass('public.ship_xp') is null or to_regclass('public.navy_ships') is null or to_regclass('public.pirate_ships') is null
     or to_regclass('public.cargo_ships') is null then
    raise exception '0344 refuses: 0127 / 0308 / 0331 / 0339 (the experience table, the crown and pirate kinds) are not all in this world';
  end if;
  -- the premise: no crown or pirate hull has experience today (nothing writes it: voyage.settle skips is_npc), so dark is the world as it stands
  if exists (select 1 from public.ship_xp x join public.ships s on s.id = x.ship_id where public.crown_house(s.player_id)) then
    raise exception '0344 refuses: a crown or pirate hull already has a public.ship_xp row; a writer this file does not know exists';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text)),
         md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before, v_meta_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('npc_ship_level_enabled', 'false'::jsonb,
     '0344: THE switch of the crown and pirate hulls'' fixed level (docs/WORLD_POWERS.md 2.3). False: they carry no experience and are level 1. True: every hull of a public.crown_house (cargo, navy, pirate ship) carries npc_ship_level, written by public.crown_hull_level_fix within ten minutes. Owner only.'),
    ('npc_ship_level', to_jsonb(5),
     '0344: the level every crown and pirate hull carries while npc_ship_level_enabled is on (docs/WORLD_POWERS.md 2.3), on public.level_from_points''s curve (1 to 20). A merchant''s is npc_fix_level''s, a player''s is earned. Read through public.crown_hull_level_fix alone.');

  -- ── 3. THE WRITER ──
  execute $f$
create function public.crown_hull_level_fix(p_player uuid default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0344: THE ONE WRITER of a crown or pirate hull's experience (docs/WORLD_POWERS.md 2.3). A crown or pirate house is public.crown_house. Lit (npc_ship_level_enabled): every hull of every such house holds
-- public.level_points(npc_ship_level), the points her fixed level begins at. Dark: none holds a row, which is level 1. Writes only a row that differs; answers how many it wrote, so a second run answers 0.
-- p_player null: every such house (the job, every ten minutes); else that house alone, and only if it is one.
declare
  v_n int;
begin
  if public.wc('npc_ship_level_enabled') = 'true'::jsonb then
    insert into public.ship_xp (ship_id, xp)
    select s.id, public.level_points(round(public.wc_num('npc_ship_level'))::int)
      from public.ships s
     where (p_player is null or s.player_id = p_player) and public.crown_house(s.player_id)
    on conflict (ship_id) do update set xp = excluded.xp where public.ship_xp.xp is distinct from excluded.xp;
  else
    delete from public.ship_xp x
     using public.ships s
     where s.id = x.ship_id and (p_player is null or s.player_id = p_player) and public.crown_house(s.player_id);
  end if;
  get diagnostics v_n = row_count;
  return v_n;
end
$body$
  $f$;
  comment on function public.crown_hull_level_fix(uuid) is
    '0344: THE one writer of a crown or pirate hull''s experience: lit, level_points(npc_ship_level) on every hull of a public.crown_house; dark, no row. Rows written. Job byeharu-voyage:crown-hull-level. Server-only.';
  revoke all on function public.crown_hull_level_fix(uuid) from public, anon, authenticated;

  comment on table public.ship_xp is
    '0127: a hull''s experience in points (0069''s curve: public.level_from_points). A player''s: written only by voyage.settle''s arrival arm (public.voyage_xp). A merchant''s: fixed once by '
    'public.npc_fix_level. 0344: a crown or pirate hull''s (public.crown_house): public.crown_hull_level_fix alone, while npc_ship_level_enabled is on. No row = 0.';

  -- ── 4. THE JOB: scheduled where cron exists (prod); the local chain has no cron and runs the writer from the proofs ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:crown-hull-level', '*/10 * * * *', 'select public.crown_hull_level_fix()')$q$;
  end if;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before
     or (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_meta_before then
    raise exception '0344 self-assert FAIL: another function moved: this file re-cuts nothing';
  end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = c_fn::regprocedure)
        is distinct from (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.npc_fix_level(uuid)'::regprocedure)
     or (select p.provolatile from pg_proc p where p.oid = c_fn::regprocedure) <> 'v'
     or has_function_privilege('anon', c_fn, 'execute') or has_function_privilege('authenticated', c_fn, 'execute') then
    raise exception '0344 self-assert FAIL: the writer is not VOLATILE, definer, with the search path its sibling public.npc_fix_level has, server-only';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before
     or public.wc('npc_ship_level_enabled') <> 'false'::jsonb or public.wc_num('npc_ship_level') <> 5 then
    raise exception '0344 self-assert FAIL: a knob moved, or the two new ones are not false and 5';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before
     or (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0344 self-assert FAIL: a table, view, index or trigger appeared or went: this file makes none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0344 self-assert FAIL: the registry or a wall moved (no new door; the posture must read zero)';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:crown-hull-level' and j.schedule = '*/10 * * * *' and j.command = 'select public.crown_hull_level_fix()' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0344 self-assert FAIL: the cron job byeharu-voyage:crown-hull-level is not scheduled every ten minutes';
    end if;
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:crown-hull-level'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0344 self-assert FAIL: another cron job moved';
    end if;
  end if;
  if exists (select 1 from public.ship_xp x join public.ships s on s.id = x.ship_id where public.crown_house(s.player_id)) then
    raise exception '0344 self-assert FAIL: dark, a crown or pirate hull has a row';
  end if;

  -- ── 6. THE SELF-ASSERT: a probe navy ship and a probe merchant of their own, every row rolled back. No money moves, no real hull or house is written, and the writer runs narrowed to the probe. ──
  begin
    v_nat  := (select n.id from public.nations n where n.code = 'PRT');
    v_port := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Crown Navy 0344', v_nat, 0, true) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Navy ship 0344', v_port);
    v_sh := public.commission_ship(v_pl, v_fl, public.wc_text('navy_ship_class'), 'Navy ship 0344', true, false);
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port)
    values (v_fl, v_pl, v_nat, 1 + coalesce((select max(x.ord) from public.navy_ships x where x.nation_id = v_nat), 0), v_port, v_port);
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa 0344', v_nat, 0, true) returning id into v_mpl;
    v_msh := public.commission_ship(v_mpl, public.form_fleet(v_mpl, 'Casa 0344', v_port), public.wc_text('navy_ship_class'), 'Casa 0344', true, false);
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';   -- the stats read the level in force

    v_dark := world.ship_stats(v_sh);
    -- every call of the writer is its own statement: the operands of an OR have no order, and a STABLE read beside it may run first
    v_n := public.crown_hull_level_fix(v_pl);
    v_m := public.crown_hull_level_fix(v_mpl);
    if v_n <> 0 or v_m <> 0 or exists (select 1 from public.ship_xp x where x.ship_id in (v_sh, v_msh)) then
      raise exception '0344 self-assert FAIL: dark, the writer wrote a row';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'npc_ship_level_enabled';
    v_n := public.crown_hull_level_fix(v_pl);
    v_m := public.crown_hull_level_fix(v_mpl);
    v_again := public.crown_hull_level_fix(v_pl);
    if v_n <> 1 or v_m <> 0 or v_again <> 0 then
      raise exception '0344 self-assert FAIL: lit, the navy hull is not written once, or the merchant is written, or a second run writes';
    end if;
    if (select public.level_from_points(x.xp) from public.ship_xp x where x.ship_id = v_sh) is distinct from 5 or exists (select 1 from public.ship_xp x where x.ship_id = v_msh) then
      raise exception '0344 self-assert FAIL: lit, the navy hull is not level 5, or the merchant has a row';
    end if;
    v_lit := world.ship_stats(v_sh);
    if (v_lit ->> 'handling')::numeric - (v_dark ->> 'handling')::numeric <> 4 * public.wc_num('ship_level_handling_per_level')
       or (v_lit ->> 'accuracy')::numeric - (v_dark ->> 'accuracy')::numeric <> 4 * public.wc_num('ship_level_accuracy_per_level')
       or (v_lit ->> 'sighting')::numeric - (v_dark ->> 'sighting')::numeric <> 4 * public.wc_num('ship_level_sighting_per_level')
       or (v_lit - 'handling' - 'accuracy' - 'sighting') <> (v_dark - 'handling' - 'accuracy' - 'sighting') then
      raise exception '0344 self-assert FAIL: level 5 does not move handling, accuracy and sighting by exactly four levels of their knobs, and nothing else: dark %, lit %', v_dark, v_lit;
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled';
    v_n := public.crown_hull_level_fix(v_pl);
    if v_n <> 1 or exists (select 1 from public.ship_xp x where x.ship_id = v_sh) or world.ship_stats(v_sh) <> v_dark then
      raise exception '0344 self-assert FAIL: dark again, the row is not gone or the hull does not read as before: % deleted, stats % against %', v_n, world.ship_stats(v_sh), v_dark;
    end if;
    raise exception using errcode = 'ZX344', message = 'PROBE_ROLLBACK_0344';
  exception when sqlstate 'ZX344' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0344 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name in ('Crown Navy 0344', 'Casa 0344'))
     or public.wc('npc_ship_level_enabled') <> 'false'::jsonb then
    raise exception '0344 self-assert FAIL: the probe left rows behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0344 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0344 self-assert ok: CROWN AND PIRATE HULLS HAVE A LEVEL. One writer, VOLATILE, server-only; two knobs (npc_ship_level_enabled false, npc_ship_level 5); the job where cron exists; no other function, knob, table, trigger or job moved; no crown hull has a row. A probe navy hull: dark nothing, lit level 5 and +4 levels of handling, accuracy, sighting, a second run 0, dark again as before; a probe merchant never written. (proof 51 runs the rest in CI.) % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
