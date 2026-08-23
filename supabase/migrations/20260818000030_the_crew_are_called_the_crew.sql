-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0030 — THE CREW ARE CALLED THE CREW
--        The owner, verbatim: "and hands? seriously? change it like crew or something."
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY THIS IS A MIGRATION AND NOT A CLIENT GLOSS ─────────────────────────────────────────────
-- Every one of these sentences is SERVED: refusal messages a player reads on the Command tab,
-- after-action prose on the Ledger, the HIRE card's help line, an officer's blurb on the roster.
-- The server authors this copy (cmd.verb_schema is THE one grammar, 0008; voyage.report_line THE
-- one prose author, 0007/0027), so a client that re-spelled a served string would be a second
-- authority for the game's own words — the exact fork those "one place" rules exist to prevent.
-- 0020 already established that a served word a player should not read changes ON THE SERVER.
--
-- ── WHAT THIS SUPERSEDES, AND WHY THE PIECES MOVE TOGETHER ─────────────────────────────────────
--   cmd.do_hire(uuid, jsonb)              0007:632 — three refusals say "hands" (0007:662, 671,
--                                         677), and one body comment beside them keeps the cant.
--   voyage.report_line(int, text, jsonb)  0007:868, re-cut 0027:196 — the two burial lines
--                                         (0027:215, 218) and SHORT_RATIONS (0027:224).
--   cmd.verb_schema()                     0008:160, re-cut 0020:52, re-cut 0021:249 — the HIRE
--                                         help (0021:292).
--   public.officers.blurb                 DATA, not a function: ZAHRA's blurb (0015:350). One
--                                         UPDATE, asserted to touch exactly one row.
-- They move together because they are one wording decision about one word; landing the refusals
-- without the report would rename the crew at the quay and bury "hands" at sea.
--
-- ── SLICED, NOT RETYPED (0027's method, and the 0305 discipline behind it) ─────────────────────
-- Each function's LIVE definition is read back from pg_get_functiondef, each hunk is asserted to
-- occur EXACTLY ONCE before it is replaced, and the re-created definition is proven to be the old
-- one plus only these words: reverse-substituting the new strings back yields the pre-image to
-- the character. The arithmetic around them — the hire pricing proof 06 exercises, the report
-- lines proof 01 matches character-for-character — is unchanged BY CONSTRUCTION, not by care.
--
-- ── WHAT IS DELIBERATELY LEFT ALONE ────────────────────────────────────────────────────────────
--   * cmd.haggle's "Hands are shaken." (0022:575) — the HANDSHAKE idiom, served on purpose. A
--     blind sweep would print "Crew are shaken", which is worse than the problem.
--   * voyage.settle's declare-block comment "…how many hands he lost…" (0027:266) and
--     public.raid_crew_lost's "HANDS, not a fraction" (0027:246) — developer prose inside prosrc;
--     no player is ever served a function's source. The second was FOUND BY THE SWEEP on this
--     file's first apply, which is the sweep proving it can see.
--   * "a ship changes hands" (0021:234) and 0027's own COMMENT ON texts — pg_description, English
--     idiom, never served.
--   * Every historical migration file. They are history; the chain replays them and each still
--     proves its own claims (0027's assert even greps its OWN report for '%hands%' — against its
--     own definition, at its own point in the chain, which stays true forever).
--
-- ── GRANTS: NOTHING MOVES ──────────────────────────────────────────────────────────────────────
-- create-or-replace preserves each ACL and that is ASSERTED, not assumed: each re-cut function's
-- proacl must be byte-identical to its pre-image. verb_schema stays an authenticated entry point
-- and do_hire server-only; report_line's reach is deliberately asserted only as UNCHANGED,
-- because "executable by PUBLIC" is the built-in default and a rebuilt persisted world (where
-- 0018's schema-less default ACL survives demolition) legitimately rebuilds it owner-only.
--
-- Depends ONLY on: 0007 (do_hire), 0027 (report_line), 0021 (verb_schema), 0015 (officers),
--                  0018/0023 (the grant authorities it re-asserts).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGES, and the positive control that the probe can SEE the word at all: a search that
-- found nothing before the fix would prove nothing after it.
create temporary table defs_before_0030 as
  select 'cmd.do_hire'::text as fn,
         pg_get_functiondef('cmd.do_hire(uuid, jsonb)'::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = 'cmd.do_hire(uuid, jsonb)'::regprocedure) as acl
  union all
  select 'voyage.report_line',
         pg_get_functiondef('voyage.report_line(int, text, jsonb)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure)
  union all
  select 'cmd.verb_schema',
         pg_get_functiondef('cmd.verb_schema()'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'cmd.verb_schema()'::regprocedure);

do $$
declare
  r        record;
  v_def    text;
  v_new    text;
  v_n      int;
  v_pre    int;
  -- The hunks. OLD text must occur exactly once in its function; NEW is the owner's word.
  -- Dollar-quoted so an apostrophe in a sentence can never truncate a hunk.
  hunks constant jsonb := jsonb_build_array(
    jsonb_build_object('fn', 'cmd.do_hire',
      'old', $h1$E_CREW_MAX: the fleet has berths for % more hands$h1$,
      'new', $h2$E_CREW_MAX: the fleet has berths for % more crew$h2$),
    jsonb_build_object('fn', 'cmd.do_hire',
      'old', $h3$E_CREW_POOL: there are no hands to be had in this port$h3$,
      'new', $h4$E_CREW_POOL: there is no crew to be had in this port$h4$),
    jsonb_build_object('fn', 'cmd.do_hire',
      'old', $h5$E_INSUFFICIENT_FUNDS: % hands cost % d. and you hold %$h5$,
      'new', $h6$E_INSUFFICIENT_FUNDS: % crew cost % d. and you hold %$h6$),
    jsonb_build_object('fn', 'cmd.do_hire',
      'old', $h7$E_CREW_POOL is reserved for a port with no hands at all$h7$,
      'new', $h8$E_CREW_POOL is reserved for a port with no crew at all$h8$),
    jsonb_build_object('fn', 'voyage.report_line',
      'old', $h9$ We buried %s of the hands; the surgeon kept the rest.$h9$,
      'new', $h10$ We buried %s of the crew; the surgeon kept the rest.$h10$),
    jsonb_build_object('fn', 'voyage.report_line',
      'old', $h11$ We buried %s of the hands.$h11$,
      'new', $h12$ We buried %s of the crew.$h12$),
    jsonb_build_object('fn', 'voyage.report_line',
      'old', $h13$The hands are on short rations and their wages are up.$h13$,
      'new', $h14$The crew are on short rations and their wages are up.$h14$),
    jsonb_build_object('fn', 'cmd.verb_schema',
      'old', $h15$Sign on hands from the idle men in port.$h15$,
      'new', $h16$Sign on crew from the idle men in port.$h16$));
  h jsonb;
begin
  -- POSITIVE CONTROL, before anything is replaced: the catalogue sweep the self-assert relies on
  -- must FIND the cant now, in exactly the functions this file names — a probe that cannot see
  -- the word would wave the fix through unexamined.
  select count(*) into v_pre
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.prosrc ~* '\mhands\M'
     and (n.nspname || '.' || p.proname) in ('cmd.do_hire', 'voyage.report_line', 'cmd.verb_schema');
  if v_pre <> 3 then
    raise exception '0030: the pre-slice sweep sees the word in % of the 3 functions this file supersedes — the probe is blind, or the chain has already changed underneath this file', v_pre;
  end if;

  for r in select fn, def from defs_before_0030 loop
    v_def := r.def;
    v_new := v_def;
    for h in select * from jsonb_array_elements(hunks) loop
      continue when h->>'fn' <> r.fn;
      -- EXACTLY ONCE, or this migration was generated against a different deployment and must
      -- not guess (the 0305/0306 slice rule: this assert is what stands between a slice and a
      -- corrupted function body).
      v_n := (length(v_new) - length(replace(v_new, h->>'old', ''))) / length(h->>'old');
      if v_n <> 1 then
        raise exception '0030: hunk "%" occurs % time(s) in the deployed % — expected exactly 1; the deployed body is not what this migration was written against', h->>'old', v_n, r.fn;
      end if;
      v_new := replace(v_new, h->>'old', h->>'new');
    end loop;
    execute v_new;
  end loop;
end $$;

-- The one DATA occurrence: an officer's served blurb (0015:350). A row, so an UPDATE — sliced
-- function surgery is for function bodies, not for a column value.
update public.officers
   set blurb = 'Keeps more of the crew alive across a bad crossing than the ship''s prayers do.'
 where code = 'ZAHRA';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_old       text;
  v_new       text;
  v_back      text;
  v_sweep     text;
  v_sweep_n   int;
  v_schema    text;
  v_help      text;
  v_line_surg text;
  v_line_none text;
  v_line_rat  text;
  v_off       text;
  v_skills    text;
  v_blurbs    int;
  v_zahra     text;
  c_probe     constant uuid := '00000000-0030-4000-8000-000000000030';
  v_player    uuid;
  v_fleet     uuid;
  v_port      uuid;
  v_room      int;
  v_msg_max   text;
  v_msg_pool  text;
  v_msg_funds text;
  f_parity    boolean := true;
  f_sweep     boolean := false;
  f_verbs     boolean := false;
  f_prose     boolean := false;
  f_roster    boolean := false;
  f_refusals  boolean := false;
  f_grant     boolean := false;
begin
  -- (a) BYTE PARITY BY CONSTRUCTION, verified: substituting the owner's words back OUT of each
  --     live definition must reproduce the pre-image to the character — so nothing moved but the
  --     word, in any of the three bodies.
  select def into v_old from defs_before_0030 where fn = 'cmd.do_hire';
  v_new  := pg_get_functiondef('cmd.do_hire(uuid, jsonb)'::regprocedure);
  v_back := replace(v_new, 'E_CREW_MAX: the fleet has berths for % more crew',
                           'E_CREW_MAX: the fleet has berths for % more hands');
  v_back := replace(v_back, 'E_CREW_POOL: there is no crew to be had in this port',
                            'E_CREW_POOL: there are no hands to be had in this port');
  v_back := replace(v_back, 'E_INSUFFICIENT_FUNDS: % crew cost % d. and you hold %',
                            'E_INSUFFICIENT_FUNDS: % hands cost % d. and you hold %');
  v_back := replace(v_back, 'E_CREW_POOL is reserved for a port with no crew at all',
                            'E_CREW_POOL is reserved for a port with no hands at all');
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0030 where fn = 'voyage.report_line';
  v_new  := pg_get_functiondef('voyage.report_line(int, text, jsonb)'::regprocedure);
  v_back := replace(v_new, ' We buried %s of the crew; the surgeon kept the rest.',
                           ' We buried %s of the hands; the surgeon kept the rest.');
  v_back := replace(v_back, ' We buried %s of the crew.', ' We buried %s of the hands.');
  v_back := replace(v_back, 'The crew are on short rations and their wages are up.',
                            'The hands are on short rations and their wages are up.');
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0030 where fn = 'cmd.verb_schema';
  v_new  := pg_get_functiondef('cmd.verb_schema()'::regprocedure);
  v_back := replace(v_new, 'Sign on crew from the idle men in port.',
                           'Sign on hands from the idle men in port.');
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  -- (b) THE SWEEP: after the slice, the word survives in this catalogue's function bodies in
  --     EXACTLY three places, each named and each deliberate — cmd.haggle serves the handshake
  --     idiom ("Hands are shaken."), while voyage.settle and public.raid_crew_lost carry it only
  --     in source comments no player is ever served (the latter found BY this sweep on first
  --     apply). Anything else appearing here is a new leak, and this names it.
  select count(*), string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
    into v_sweep_n, v_sweep
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.prosrc ~* '\mhands\M';
  if v_sweep_n = 3 and v_sweep = 'cmd.haggle, public.raid_crew_lost, voyage.settle' then f_sweep := true; end if;

  -- (c) THE GRAMMAR SPEAKS OF CREW. The served schema carries the exact new sentence and no
  --     crew-cant "hands" anywhere in any verb's help or note.
  v_schema := cmd.verb_schema()::text;
  select v->>'help' into v_help
    from jsonb_array_elements(cmd.verb_schema()) v where v->>'verb' = 'HIRE';
  if v_help = 'Sign on crew from the idle men in port.'
     and v_schema !~* '\mhands\M' then
    f_verbs := true;
  end if;

  -- (d) THE PROSE SPEAKS OF CREW, read off the author itself in all three moods.
  v_line_surg := voyage.report_line(2, 'PIRATES',
    '{"prose":"They took everything but the ship itself.","crew_lost":"3","surgeon_pct":"7"}'::jsonb);
  v_line_none := voyage.report_line(2, 'PIRATES',
    '{"prose":"They took everything but the ship itself.","crew_lost":"3"}'::jsonb);
  v_line_rat  := voyage.report_line(4, 'SHORT_RATIONS', '{}'::jsonb);
  if position(' We buried 3 of the crew; the surgeon kept the rest.' in v_line_surg) > 0
     and position(' We buried 3 of the crew.' in v_line_none) > 0
     and position('The crew are on short rations and their wages are up.' in v_line_rat) > 0
     and v_line_surg !~* '\mhands\M' and v_line_none !~* '\mhands\M' and v_line_rat !~* '\mhands\M' then
    f_prose := true;
  end if;

  -- (e) THE ROSTER AND THE SCHOOL SPEAK OF CREW — asserted on the SERVED payloads, with ZAHRA's
  --     new sentence required present so "no hands in the payload" cannot pass because blurbs
  --     quietly stopped being served at all. The authored tables are swept beside them.
  select count(*) into v_blurbs from (
    select blurb from public.officers where blurb ~* '\mhands\M'
    union all select blurb from public.skills where blurb ~* '\mhands\M'
    union all select blurb from public.buff_kinds where blurb ~* '\mhands\M') s;
  select blurb into v_zahra from public.officers where code = 'ZAHRA';

  begin
    v_player := public.new_house(c_probe, 'Casa da Tripulacao', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;

    v_off    := world.officers()::text;
    v_skills := world.skills()::text;
    if v_blurbs = 0
       and v_zahra = 'Keeps more of the crew alive across a bad crossing than the ship''s prayers do.'
       and position('Keeps more of the crew alive' in v_off) > 0
       and v_off !~* '\mhands\M'
       and v_skills !~* '\mhands\M' then
      f_roster := true;
    end if;

    -- (f) THE REFUSALS A PLAYER ACTUALLY READS, provoked one by one off the live verb. Each
    --     precondition is set here, deterministically, and rolled away with the probe.
    select coalesce(sum(c.crew_max - s.crew), 0)::int into v_room
      from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_fleet;
    begin
      perform cmd.do_hire(v_fleet, jsonb_build_object('count', v_room + 1));
    exception when others then v_msg_max := sqlerrm; end;

    update public.ports set crew_pool = 0 where id = v_port;
    begin
      perform cmd.do_hire(v_fleet, jsonb_build_object('count', greatest(v_room, 1)));
    exception when others then v_msg_pool := sqlerrm; end;

    update public.ports set crew_pool = 50 where id = v_port;
    perform public.credit(v_player, 'WAGES', -(select ducats from public.players where id = v_player));
    begin
      perform cmd.do_hire(v_fleet, jsonb_build_object('count', greatest(least(v_room, 5), 1)));
    exception when others then v_msg_funds := sqlerrm; end;

    if v_msg_max  like 'E_CREW_MAX:%'           and position('more crew' in v_msg_max) > 0   and v_msg_max  !~* '\mhands\M'
       and v_msg_pool like 'E_CREW_POOL:%'      and position('no crew to be had' in v_msg_pool) > 0 and v_msg_pool !~* '\mhands\M'
       and v_msg_funds like 'E_INSUFFICIENT_FUNDS:%' and position('crew cost' in v_msg_funds) > 0 and v_msg_funds !~* '\mhands\M' then
      f_refusals := true;
    end if;

    raise exception '__PROBE_ROLLBACK_0030__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0030__' then raise; end if;
  end;

  if not f_parity then
    raise exception '0030 self-assert FAIL: substituting the old words back into a re-cut body does not reproduce its pre-image — something besides the word moved, or nothing moved at all';
  end if;
  if not f_sweep then
    raise exception '0030 self-assert FAIL: after the slice the word survives in % function bod(ies) [%] — expected exactly [cmd.haggle, public.raid_crew_lost, voyage.settle] — the served handshake idiom and two source comments; anything else is a leak this file missed or a keeper it broke', v_sweep_n, coalesce(v_sweep, '(none)');
  end if;
  if not f_verbs then
    raise exception '0030 self-assert FAIL: the served HIRE help reads "%" or the grammar still says hands somewhere a player taps', v_help;
  end if;
  if not f_prose then
    raise exception '0030 self-assert FAIL: the after-action prose still speaks of hands — surgeon: "%", plain: "%", rations: "%"', v_line_surg, v_line_none, v_line_rat;
  end if;
  if not f_roster then
    raise exception '0030 self-assert FAIL: % authored blurb(s) still say hands, ZAHRA reads "%", or the served roster/school payloads still carry the word (or stopped carrying blurbs at all)', v_blurbs, v_zahra;
  end if;
  if not f_refusals then
    raise exception '0030 self-assert FAIL: a hire refusal a player reads still says hands or lost its shape — E_CREW_MAX: "%", E_CREW_POOL: "%", E_INSUFFICIENT_FUNDS: "%"', coalesce(v_msg_max, '(none)'), coalesce(v_msg_pool, '(none)'), coalesce(v_msg_funds, '(none)');
  end if;

  -- The probe rolled back.
  if (select count(*) from public.players where auth_uid = c_probe) <> 0 then
    raise exception '0030 self-assert FAIL: the probe house survived its subtransaction';
  end if;

  -- POSTURE. The deterministic half: verb_schema stays an authenticated entry point and
  -- do_hire stays server-only — true in every environment this chain runs. The report_line half
  -- is NOT asserted as "anon may execute it": that executability is the built-in function
  -- default, and on a REBUILT persisted world (localDb demolish-and-retry) 0018's surviving
  -- schema-less default ACL means it is reborn owner-only — an AMBIENT state this file does not
  -- own (docs/NO_SPAGHETTI.md §4; the rebuild spec went red on the first draft of this assert,
  -- which asserted it anyway). What this file DOES own is that the slice moved no ACL at all:
  -- every re-cut function's proacl is byte-identical to its pre-image, whatever it was.
  if has_function_privilege('authenticated', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('anon', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('authenticated', 'cmd.do_hire(uuid, jsonb)', 'execute')
     and not has_function_privilege('anon', 'cmd.do_hire(uuid, jsonb)', 'execute')
     and (select d.acl from defs_before_0030 d where d.fn = 'cmd.do_hire')
         is not distinct from (select p.proacl::text from pg_proc p where p.oid = 'cmd.do_hire(uuid, jsonb)'::regprocedure)
     and (select d.acl from defs_before_0030 d where d.fn = 'voyage.report_line')
         is not distinct from (select p.proacl::text from pg_proc p where p.oid = 'voyage.report_line(int, text, jsonb)'::regprocedure)
     and (select d.acl from defs_before_0030 d where d.fn = 'cmd.verb_schema')
         is not distinct from (select p.proacl::text from pg_proc p where p.oid = 'cmd.verb_schema()'::regprocedure)
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0030 self-assert FAIL: a grant moved under the slice — verb_schema must stay an authenticated entry point, do_hire server-only, every re-cut function''s ACL byte-identical to its pre-image, and the whole grant family at zero';
  end if;

  raise notice '0030 self-assert ok: THE CREW ARE CALLED THE CREW. Three functions were sliced, not retyped — substituting the old words back reproduces each pre-image to the character — and the word now survives in exactly 3 named places [%] — the served handshake idiom and two source comments; the grammar''s HIRE card reads "%", the after-action prose buries crew and rations crew in all three moods, 0 authored blurbs say hands with ZAHRA''s new sentence proven SERVED on the roster payload; all three hire refusals were provoked off the live verb and each speaks of crew ("%" · "%" · "%"); grants unmoved, 0 client write grants',
    v_sweep, v_help, v_msg_max, v_msg_pool, v_msg_funds;
end $$;

drop table defs_before_0030;
