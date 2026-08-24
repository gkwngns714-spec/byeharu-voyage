-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 1 — OFFLINE EQUIVALENCE  (DESIGN Appendix 2, CI apply-proof requirement 1)
--
--   "A voyage settled LAZILY after a simulated 9-hour gap produces BYTE-IDENTICAL voyage_events to
--    one settled tick-by-tick."
--
-- WHY THIS IS THE PROOF THE GAME STANDS ON
--   Law 8 says a fleet keeps sailing while the player is offline. That is either true to the byte
--   or it is a promise the player will eventually catch you breaking — a storm that "would have"
--   happened, a purse that differs by the wages of one day. §D.2 makes the claim; this file is
--   where the claim is tested.
--
-- HOW IT IS MADE A FAIR TEST
--   The two settlements must be of THE SAME VOYAGE, because voyage.rng() is seeded by voyage_id:
--   two different voyages are ENTITLED to differ, so comparing two fleets would prove nothing.
--   So the same voyage is settled day by day, the result is captured into a plpgsql variable, and
--   the whole settlement is then thrown away by rolling back a subtransaction — plpgsql variables
--   are not transactional, so the captured text survives while the rows do not. The identical
--   voyage row is then settled once, lazily, nine hours late, and the two texts are compared.
--
--   And the voyage is PRE-SCREENED for a hazard before it is used. voyage.hazard_roll() writes
--   nothing, so the proof can look ahead and reject a quiet crossing. A comparison of two runs in
--   which nothing ever happened would pass while proving nothing at all.
--
-- @pass OFFLINE_EQUIV_HAZARD_PRESENT   the voyage under test really contains at least one hazard day
-- @pass OFFLINE_EQUIV_SAME_ROW_COUNT   both settlements resolved the same number of checkpoints
-- @pass OFFLINE_EQUIV_IDENTICAL_BYTES  day_index, kind, payload and resolved_at match exactly
-- @pass OFFLINE_EQUIV_SAME_PURSE       wages and hazard costs came to the same ducat
-- @pass OFFLINE_EQUIV_SAME_ETA         the delays moved the arrival to the same instant
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth   constant uuid := '00000000-0f01-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_voyage uuid;
  v_days   int;
  v_haz    int;
  v_try    int := 0;
  v_found  boolean := false;
  v_retry  boolean;
  d        int;
  -- captured from the step-by-step run and read after it has been rolled away
  v_step_text  text;
  v_step_rows  int;
  v_step_purse bigint;
  v_step_eta   timestamptz;
  v_lazy_text  text;
  v_lazy_rows  int;
  v_lazy_purse bigint;
  v_lazy_eta   timestamptz;
  v_depart timestamptz;
begin
  v_player := public.new_house(c_auth, 'Casa Ausente', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.assume_identity(c_auth);

  -- Stores enough for the Barbary run, so E_ENDURANCE is not what this proof measures.
  perform cmd.issue(v_fleet, 'PROVISION FULL');

  -- ── Find a voyage that actually meets weather. hazard_roll() is pure, so looking ahead costs
  --    nothing and changes nothing.
  --    THE CAP IS 120, AND IT IS A MEASUREMENT. 2026-08-22, PGlite 0.5.5: of 120 Lisboa-Tunis
  --    voyages, 20 carried at least one hazard — 17 per cent, over 11 voyage-days. At the old cap
  --    of 25 the chance of finding none was 0.83^25, ONE RUN IN NINETY, and this file duly went red
  --    on a correct system, which is a proof that gates nothing. At 120 it is 1 in 70 million. An
  --    attempt costs ~17 ms and the median run needs about six of them.
  while v_try < 120 and not v_found loop
    v_try := v_try + 1;
    v_retry := false;
    begin
      -- 0039: a proof sails like a player — it PROPOSES the course (proof.sail attaches the
      -- fixture's proposal) and the server verifies and measures it.
      perform proof.sail(v_fleet, 'TUN');
      select id into v_voyage from public.voyages where fleet_id = v_fleet and status = 'SAILING';
      if v_voyage is null then
        raise exception 'PROOF 1 SETUP FAILED: the fleet did not depart for Tunis on attempt %', v_try;
      end if;
      v_days := voyage.total_days(v_voyage);
      select count(*) into v_haz
        from generate_series(1, v_days) g
       cross join lateral voyage.hazard_roll(v_voyage, g) h
       where h.occurred;
      if v_haz > 0 then
        v_found  := true;
        v_depart := (select departed_at from public.voyages where id = v_voyage);
      else
        v_retry := true;
        raise exception '__NEXT_VOYAGE__' using errcode = 'P0001';
      end if;
    exception when others then
      if not v_retry then raise; end if;
    end;
  end loop;

  if not v_found then
    raise exception 'PROOF 1 FAILED: no voyage in % attempts carried a hazard; the comparison would have been vacuous. At the measured rate of ~17%% that is a 1-in-70-million run, so suspect the hazard rule rather than the dice', v_try;
  end if;
  raise notice 'PASS: OFFLINE_EQUIV_HAZARD_PRESENT — voyage % over % voyage-days carries % hazard day(s) (found on attempt %)',
    v_voyage, v_days, v_haz, v_try;

  -- Backdate the whole voyage by nine hours: it is long since due, and nothing ticked.
  update public.voyages
     set departed_at = departed_at - interval '9 hours', eta = eta - interval '9 hours'
   where id = v_voyage;
  v_depart := (select departed_at from public.voyages where id = v_voyage);

  -- ── RUN A: tick-by-tick. Settle at each day boundary, as a cron running on time would.
  begin
    for d in 1 .. v_days + 4 loop
      perform voyage.settle(v_fleet, voyage.day_ends_at(v_voyage, d));
      exit when (select status from public.voyages where id = v_voyage) <> 'SAILING';
    end loop;
    perform voyage.settle(v_fleet, now());

    select count(*),
           jsonb_agg(jsonb_build_object('d', ve.day_index, 'k', ve.kind,
                                        'p', ve.payload, 'r', ve.resolved_at)
                     order by ve.day_index)::text
      into v_step_rows, v_step_text
      from public.voyage_events ve where ve.voyage_id = v_voyage;
    select ducats into v_step_purse from public.players where id = v_player;
    select eta    into v_step_eta   from public.voyages where id = v_voyage;

    -- Throw the entire settlement away. The voyage row itself was created BEFORE this
    -- subtransaction, so its id — and therefore every rng seed — is unchanged.
    raise exception '__DISCARD_RUN_A__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__DISCARD_RUN_A__' then raise; end if;
  end;

  if (select last_settled_day from public.voyages where id = v_voyage) <> 0
     or (select count(*) from public.voyage_events where voyage_id = v_voyage) <> 0 then
    raise exception 'PROOF 1 FAILED: run A did not roll away; the lazy run would start from a settled voyage';
  end if;

  -- ── RUN B: the offline player. One call, nine hours late.
  perform voyage.settle(v_fleet, now());

  select count(*),
         jsonb_agg(jsonb_build_object('d', ve.day_index, 'k', ve.kind,
                                      'p', ve.payload, 'r', ve.resolved_at)
                   order by ve.day_index)::text
    into v_lazy_rows, v_lazy_text
    from public.voyage_events ve where ve.voyage_id = v_voyage;
  select ducats into v_lazy_purse from public.players where id = v_player;
  select eta    into v_lazy_eta   from public.voyages where id = v_voyage;

  if v_step_rows <> v_lazy_rows or v_step_rows = 0 then
    raise exception 'PROOF 1 FAILED: tick-by-tick resolved % checkpoint(s), lazy resolved %',
      v_step_rows, v_lazy_rows;
  end if;
  raise notice 'PASS: OFFLINE_EQUIV_SAME_ROW_COUNT — both settlements resolved % checkpoint(s)', v_lazy_rows;

  if v_step_text is distinct from v_lazy_text then
    raise exception E'PROOF 1 FAILED: voyage_events differ.\n  tick-by-tick: %\n  lazy:         %',
      v_step_text, v_lazy_text;
  end if;
  raise notice 'PASS: OFFLINE_EQUIV_IDENTICAL_BYTES — % characters of (day_index, kind, payload, resolved_at) match exactly',
    length(v_lazy_text);

  if v_step_purse <> v_lazy_purse then
    raise exception 'PROOF 1 FAILED: purse differs — tick-by-tick % d., lazy % d.', v_step_purse, v_lazy_purse;
  end if;
  raise notice 'PASS: OFFLINE_EQUIV_SAME_PURSE — both runs ended on % ducats after wages and hazards', v_lazy_purse;

  if v_step_eta is distinct from v_lazy_eta then
    raise exception 'PROOF 1 FAILED: ETA differs — tick-by-tick %, lazy %', v_step_eta, v_lazy_eta;
  end if;
  raise notice 'PASS: OFFLINE_EQUIV_SAME_ETA — both runs put the arrival at % (departed %)', v_lazy_eta, v_depart;
end $$;
