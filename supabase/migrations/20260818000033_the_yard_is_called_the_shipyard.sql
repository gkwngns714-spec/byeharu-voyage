-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0033 — THE YARD IS CALLED THE SHIPYARD
--        The owner, verbatim: "what is yard?" — a player had to ask what a served word meant,
--        and jargon a player must ask about is a defect in the copy, not in the player.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY THIS IS A MIGRATION AND NOT A CLIENT GLOSS (0030's reason, same word-shaped defect) ────
-- The sentences are SERVED: two refusals a player reads on the Command tab and the REPAIR card's
-- help line in the one grammar. The server authors this copy, so a client that re-spelled a
-- served string would be a second authority for the game's own words. The client screens that
-- said "yard" in their OWN labels were fixed client-side in the same effort; the strings below
-- are the server's half, and both halves land together.
--
-- ── WHAT THIS SUPERSEDES, AND WHY THE PIECES MOVE TOGETHER ─────────────────────────────────────
--   cmd.do_repair(uuid, jsonb)  0007:697 — both refusals say "yard" (0007:717 "cannot enter a
--                               yard", 0007:721 "no repair yard"). Never re-cut since; the live
--                               body is 0007's.
--   cmd.verb_schema()           0008:160, re-cut 0020:52, re-cut 0021:249, SLICED by 0030 — the
--                               REPAIR help (0021:297, "Put her in the yard and mend the hull.").
--                               The live body is 0021's text carrying 0030's word edits, which is
--                               why this file slices pg_get_functiondef and never retypes a file.
-- They move together because they are one wording decision about one word: landing the card
-- without the refusals would rename the place on the menu and keep the old name on the door.
--
-- ── SLICED, NOT RETYPED (0030's method, and the 0305 discipline behind it) ─────────────────────
-- Each function's LIVE definition is read back from pg_get_functiondef, each hunk is asserted to
-- occur EXACTLY ONCE before it is replaced, and the re-created definition is proven to be the old
-- one plus only these words: reverse-substituting the new strings back yields the pre-image to
-- the character. The repair pricing and yard-time arithmetic around them is unchanged BY
-- CONSTRUCTION, not by care.
--
-- ── WHAT IS DELIBERATELY LEFT ALONE ────────────────────────────────────────────────────────────
--   * The refusal CODE `E_NO_YARD`, and the columns `has_yard` / `yard_tier` — contract
--     identifiers, not copy. A client keys behaviour off a code the way it keys off a column
--     name; renaming one is an API change, not a wording fix. (The regex sweep below cannot even
--     see them: `\myard\M` refuses a word glued to an underscore, deliberately.)
--   * cmd.advance's "-- still in the yard" and public.tick_arrivals' "A fleet whose yard time
--     has elapsed…" — developer prose inside prosrc; no player is ever served a function's
--     source. They are the two named survivors the sweep pins, 0030's own convention.
--   * world_config's `repair_sim_hours_per_pct` description ("sim-hours of yard time…") —
--     world_config is server-only (0001) and snapshot serves an allow-list of VALUES (0009), so
--     a description never crosses the wire. Same class as 0030's COMMENT ON texts.
--   * "yard" the SPAR — the legitimate nautical sense. Checked: it appears nowhere in served
--     copy, authored blurbs or port names; only in client-side icon comments, which stay.
--   * Every historical migration file. They are history; the chain replays them and each still
--     proves its own claims at its own point in the chain.
--
-- ── GRANTS: NOTHING MOVES ──────────────────────────────────────────────────────────────────────
-- create-or-replace preserves each ACL and that is ASSERTED, not assumed: each re-cut function's
-- proacl must be byte-identical to its pre-image. verb_schema stays an authenticated entry point
-- and do_repair server-only.
--
-- Depends ONLY on: 0007 (do_repair), 0021/0030 (verb_schema's live body),
--                  0018/0023 (the grant authorities it re-asserts).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGES, and the ACLs beside them, before anything is replaced.
create temporary table defs_before_0033 as
  select 'cmd.do_repair'::text as fn,
         pg_get_functiondef('cmd.do_repair(uuid, jsonb)'::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = 'cmd.do_repair(uuid, jsonb)'::regprocedure) as acl
  union all
  select 'cmd.verb_schema',
         pg_get_functiondef('cmd.verb_schema()'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'cmd.verb_schema()'::regprocedure);

do $$
declare
  r       record;
  v_def   text;
  v_new   text;
  v_n     int;
  v_pre   text;
  -- The hunks. OLD text must occur exactly once in its function; NEW is the plain word.
  -- Dollar-quoted so an apostrophe in a sentence can never truncate a hunk.
  hunks constant jsonb := jsonb_build_array(
    jsonb_build_object('fn', 'cmd.do_repair',
      'old', $h1$E_NOT_DOCKED: % is % and cannot enter a yard$h1$,
      'new', $h2$E_NOT_DOCKED: % is % and cannot enter a shipyard$h2$),
    jsonb_build_object('fn', 'cmd.do_repair',
      'old', $h3$E_NO_YARD: this port has no repair yard$h3$,
      'new', $h4$E_NO_YARD: this port has no shipyard$h4$),
    jsonb_build_object('fn', 'cmd.verb_schema',
      'old', $h5$Put her in the yard and mend the hull.$h5$,
      'new', $h6$Put her in the shipyard and mend the hull.$h6$));
  h jsonb;
begin
  -- POSITIVE CONTROL, before anything is replaced: the catalogue sweep the self-assert relies on
  -- must FIND the word now, in exactly the four functions this header names — the two being
  -- sliced and the two comment carriers being kept. A probe that cannot see the word would wave
  -- the fix through unexamined, and a fifth carrier appearing here is a leak found before the
  -- slice rather than after it.
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
    into v_pre
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.prosrc ~* '\myard\M';
  if v_pre is distinct from 'cmd.advance, cmd.do_repair, cmd.verb_schema, public.tick_arrivals' then
    raise exception '0033: the pre-slice sweep sees the word in [%] — expected exactly [cmd.advance, cmd.do_repair, cmd.verb_schema, public.tick_arrivals]; the probe is blind, a carrier is missing, or the chain has changed underneath this file', coalesce(v_pre, '(none)');
  end if;

  for r in select fn, def from defs_before_0033 loop
    v_def := r.def;
    v_new := v_def;
    for h in select * from jsonb_array_elements(hunks) loop
      continue when h->>'fn' <> r.fn;
      -- EXACTLY ONCE, or this migration was generated against a different deployment and must
      -- not guess (the 0305/0306 slice rule: this assert is what stands between a slice and a
      -- corrupted function body).
      v_n := (length(v_new) - length(replace(v_new, h->>'old', ''))) / length(h->>'old');
      if v_n <> 1 then
        raise exception '0033: hunk "%" occurs % time(s) in the deployed % — expected exactly 1; the deployed body is not what this migration was written against', h->>'old', v_n, r.fn;
      end if;
      v_new := replace(v_new, h->>'old', h->>'new');
    end loop;
    execute v_new;
  end loop;
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_old       text;
  v_new       text;
  v_back      text;
  v_sweep     text;
  v_help      text;
  v_schema    text;
  c_probe     constant uuid := '00000000-0033-4000-8000-000000000033';
  v_player    uuid;
  v_fleet     uuid;
  v_port      uuid;
  v_msg_dock  text;
  v_msg_yard  text;
  f_parity    boolean := true;
  f_sweep     boolean := false;
  f_verbs     boolean := false;
  f_refusals  boolean := false;
  f_grant     boolean := false;
begin
  -- (a) BYTE PARITY BY CONSTRUCTION, verified: substituting the old words back OUT of each live
  --     definition must reproduce the pre-image to the character — so nothing moved but the word.
  select def into v_old from defs_before_0033 where fn = 'cmd.do_repair';
  v_new  := pg_get_functiondef('cmd.do_repair(uuid, jsonb)'::regprocedure);
  v_back := replace(v_new, 'E_NOT_DOCKED: % is % and cannot enter a shipyard',
                           'E_NOT_DOCKED: % is % and cannot enter a yard');
  v_back := replace(v_back, 'E_NO_YARD: this port has no shipyard',
                            'E_NO_YARD: this port has no repair yard');
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0033 where fn = 'cmd.verb_schema';
  v_new  := pg_get_functiondef('cmd.verb_schema()'::regprocedure);
  v_back := replace(v_new, 'Put her in the shipyard and mend the hull.',
                           'Put her in the yard and mend the hull.');
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  -- (b) THE SWEEP: after the slice, the standalone word survives in EXACTLY the two named source
  --     comments no player is ever served — cmd.advance ("still in the yard") and
  --     public.tick_arrivals ("A fleet whose yard time has elapsed"). Anything else is a leak
  --     this file missed, and this names it. (`\myard\M` deliberately cannot match `shipyard`,
  --     `E_NO_YARD`, `has_yard`, `yard_tier` or `v_yard`: no word boundary.)
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
    into v_sweep
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.prosrc ~* '\myard\M';
  if v_sweep = 'cmd.advance, public.tick_arrivals' then f_sweep := true; end if;

  -- (c) THE GRAMMAR SPEAKS OF THE SHIPYARD. The served card carries the exact new sentence and
  --     no standalone "yard" survives anywhere in any verb's help or note.
  v_schema := cmd.verb_schema()::text;
  select v->>'help' into v_help
    from jsonb_array_elements(cmd.verb_schema()) v where v->>'verb' = 'REPAIR';
  if v_help = 'Put her in the shipyard and mend the hull.'
     and v_schema !~* '\myard\M' then
    f_verbs := true;
  end if;

  -- (d) THE REFUSALS A PLAYER ACTUALLY READS, provoked one by one off the live verb. Each
  --     precondition is set here, deterministically, and rolled away with the probe.
  begin
    v_player := public.new_house(c_probe, 'Casa do Estaleiro', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;

    update public.fleets set status = 'ANCHORED' where id = v_fleet;
    begin
      perform cmd.do_repair(v_fleet, '{}'::jsonb);
    exception when others then v_msg_dock := sqlerrm; end;

    update public.fleets set status = 'DOCKED' where id = v_fleet;
    -- ports_yard_tier_agrees (0002:103): a port with no yard has tier 0 — both move together.
    update public.ports set has_yard = false, yard_tier = 0 where id = v_port;
    begin
      perform cmd.do_repair(v_fleet, '{}'::jsonb);
    exception when others then v_msg_yard := sqlerrm; end;

    if v_msg_dock like 'E_NOT_DOCKED:%' and position('cannot enter a shipyard' in v_msg_dock) > 0
       and v_msg_dock !~* '\myard\M'
       and v_msg_yard like 'E_NO_YARD:%' and position('this port has no shipyard' in v_msg_yard) > 0
       and v_msg_yard !~* '\myard\M' then
      f_refusals := true;
    end if;

    raise exception '__PROBE_ROLLBACK_0033__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0033__' then raise; end if;
  end;

  if not f_parity then
    raise exception '0033 self-assert FAIL: substituting the old words back into a re-cut body does not reproduce its pre-image — something besides the word moved, or nothing moved at all';
  end if;
  if not f_sweep then
    raise exception '0033 self-assert FAIL: after the slice the standalone word survives in [%] — expected exactly [cmd.advance, public.tick_arrivals], the two source comments no player is served; anything else is a leak this file missed or a keeper it broke', coalesce(v_sweep, '(none)');
  end if;
  if not f_verbs then
    raise exception '0033 self-assert FAIL: the served REPAIR help reads "%" or the grammar still says yard somewhere a player taps', v_help;
  end if;
  if not f_refusals then
    raise exception '0033 self-assert FAIL: a repair refusal a player reads still says yard or lost its shape — E_NOT_DOCKED: "%", E_NO_YARD: "%"', coalesce(v_msg_dock, '(none)'), coalesce(v_msg_yard, '(none)');
  end if;

  -- The probe rolled back.
  if (select count(*) from public.players where auth_uid = c_probe) <> 0 then
    raise exception '0033 self-assert FAIL: the probe house survived its subtransaction';
  end if;

  -- POSTURE: the slice moved no ACL — every re-cut function's proacl byte-identical to its
  -- pre-image, verb_schema still an authenticated entry point, do_repair still server-only, and
  -- the whole grant family at zero (0018/0023's authorities, re-asserted as every migration does).
  if has_function_privilege('authenticated', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('anon', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('authenticated', 'cmd.do_repair(uuid, jsonb)', 'execute')
     and not has_function_privilege('anon', 'cmd.do_repair(uuid, jsonb)', 'execute')
     and (select d.acl from defs_before_0033 d where d.fn = 'cmd.do_repair')
         is not distinct from (select p.proacl::text from pg_proc p where p.oid = 'cmd.do_repair(uuid, jsonb)'::regprocedure)
     and (select d.acl from defs_before_0033 d where d.fn = 'cmd.verb_schema')
         is not distinct from (select p.proacl::text from pg_proc p where p.oid = 'cmd.verb_schema()'::regprocedure)
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0033 self-assert FAIL: a grant moved under the slice — verb_schema must stay an authenticated entry point, do_repair server-only, every re-cut function''s ACL byte-identical to its pre-image, and the whole grant family at zero';
  end if;

  raise notice '0033 self-assert ok: THE YARD IS CALLED THE SHIPYARD. Two functions were sliced, not retyped — substituting the old words back reproduces each pre-image to the character — and the standalone word now survives in exactly 2 named places [%], both source comments no player is served; the grammar''s REPAIR card reads "%"; both repair refusals were provoked off the live verb and each speaks of the shipyard ("%" · "%"); grants unmoved, 0 client write grants',
    v_sweep, v_help, v_msg_dock, v_msg_yard;
end $$;

drop table defs_before_0033;
