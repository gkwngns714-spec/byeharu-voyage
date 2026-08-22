-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 6 — THE BARGAIN  (migration 0022)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0022 proves, in the transaction that applies it, that its own arithmetic is right and that the
--   unhaggled economy did not move. It cannot prove three things, and those three are this file:
--
--     1. THE MECHANIC WORKS THROUGH THE DOOR THE BROWSER USES. The self-assert runs as the owner,
--        who bypasses RLS and holds every grant. A player is `authenticated`, sees only his own
--        rows, and may call exactly two of these functions. If the grants or the policies are
--        wrong the game is broken for everyone and every self-assert in the chain is still green.
--     2. THE RANDOMNESS IS NOT SKEWED. One migration takes three draws. Three draws say nothing
--        about whether a 45 per cent chance is a 45 per cent chance. This file takes two thousand,
--        over FIXED keys so the answer is the same on every run and on every machine.
--     3. THE CAPS HOLD UNDER ABUSE, not merely at their boundary. Win over and over; the
--        concession must stop, and the executed spread must stop, and the day's attempts must stop.
--
-- ── EVERY NUMBER HERE IS DERIVED OR MEASURED, NONE IS A SEED ────────────────────────────────────
-- The knobs are read from world_config, never written as literals — a proof that hard-codes 0.45
-- goes red the day somebody tunes the mechanic and was never testing the rule. The subject good is
-- FOUND by query with an `order by`, never picked by an unordered `limit 1` (0014:248-258, the
-- lottery that lost). Where a precondition is needed it is SET here and rolled back with the rest,
-- never borrowed from the seed (docs/NO_SPAGHETTI.md §4).
--
-- @pass HAGGLE_OPT_IN_IS_INERT       a house that never bargains is quoted DESIGN G.1 exactly, recomputed independently of 0022's code path
-- @pass HAGGLE_MOVES_THE_ASK         a won bargain moves ask and bid by exactly concession x spread/2, and moves the mid by nothing
-- @pass HAGGLE_CAP_BITES             winning over and over stops dead at haggle_concession_max
-- @pass HAGGLE_FLOOR_BITES           with a purser at the officer cap AND a bargain at its cap, the executed spread lands ON the floor
-- @pass HAGGLE_ATTEMPTS_ARE_FINITE   the day's attempts run out, and a refusal hardens the odds by exactly the knob
-- @pass HAGGLE_NO_RETRY_REROLLS      every outcome of the day is reproducible from voyage.rng, and no two attempts share a draw
-- @pass HAGGLE_ODDS_ARE_HONEST       2,000 fixed-key draws land within 4.5 sigma of the advertised chance
-- @pass HAGGLE_IS_WORTH_DOING       a fully bargained round trip is worth a stated slice of a voyage's margin, and every attempt of the day can improve it
-- @pass HAGGLE_CLIENT_PATH           as `authenticated`: the two entry points work, the internal folds are refused 42501, and RLS shows the house exactly its own bargain
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth    constant uuid := '00000000-0f06-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_port    uuid;
  v_good    uuid;
  v_good_c  text;
  v_day     int;
  -- knobs, read not written
  k_step    numeric := public.wc_num('haggle_concession_step');
  k_cap     numeric := public.wc_num('haggle_concession_max');
  k_floor   numeric := public.wc_num('haggle_spread_floor_frac');
  k_harden  numeric := public.wc_num('haggle_hardening_per_fail');
  k_base    numeric := public.wc_num('haggle_base_success');
  k_tries   int     := public.wc_int('haggle_attempts_per_day');
  k_offcap  numeric := public.wc_num('officer_bonus_cap_pct');
  -- measurements
  v_pub     numeric;
  v_mid0    numeric; v_ask0 numeric; v_bid0 numeric;
  v_mid1    numeric; v_ask1 numeric; v_bid1 numeric;
  v_eff     numeric;
  v_conc    numeric;
  v_res     jsonb;
  v_state   jsonb;
  v_odds    numeric;
  v_odds_fresh numeric;
  v_roll    numeric;
  v_officer uuid;
  v_i       int;
  v_n       int;
  v_bad     int;
  v_wins    int;
  v_pred    int;
  v_draws   int;
  v_hits    int;
  v_rate    numeric;
  v_sigma   numeric;
  v_expect  numeric;
  v_err     text;
  v_streams text[];
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 1. OPT-IN MEANS INERT. Recompute DESIGN G.1's ask and bid from the PUBLISHED spread, the tax
  --    and the mid — none of it through world.spread_effective — and require world.price() to
  --    agree on a broad sample. If 0022 leaked a shave into the default path, this is where a
  --    player who has never heard of haggling finds out, and it is where we find out first.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select count(*) into v_n
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 250) s;
  if v_n < 250 then
    raise exception 'PROOF 6 FAILED: only % (port, good) pair(s) to sample; the sweep below would be nearly vacuous', v_n;
  end if;

  select count(*) into v_bad
    from (select port_id, good_id, stock from public.port_goods order by port_id, good_id limit 250) s
   cross join lateral world.price(s.port_id, s.good_id) p
   where p.ask is distinct from round(world.mid_price(s.port_id, s.good_id, s.stock)
                                      * (1 + world.tax_rate(s.port_id) + world.spread(s.port_id) / 2), 2)
      or p.bid is distinct from round(world.mid_price(s.port_id, s.good_id, s.stock)
                                      * (1 - world.spread(s.port_id) / 2)
                                      * (1 - world.tax_rate(s.port_id)), 2)
      -- and the executed spread for a house with no fleet named IS the published spread
      or world.spread_effective(s.port_id, s.good_id, null) is distinct from world.spread(s.port_id);
  if v_bad <> 0 then
    raise exception 'PROOF 6 FAILED: % of % sampled (port, good) pair(s) are no longer priced by DESIGN G.1 with the published spread. Haggling is opt-in and it has leaked', v_bad, v_n;
  end if;
  raise notice 'PASS: HAGGLE_OPT_IN_IS_INERT — % (port, good) pairs priced by mid x (1 + tax + spread/2) and mid x (1 - spread/2) x (1 - tax), recomputed from world.spread/tax/mid_price without touching 0022''s path, and world.spread_effective(port, good, NULL) equals world.spread on every one', v_n;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 2. A HOUSE, AND A SUBJECT FOUND BY QUERY
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_player := public.new_house(c_auth, 'Casa do Regateio', 'PRT');
  perform cmd.assume_identity(c_auth);
  select f.id, f.port_id into v_fleet, v_port from public.fleets f where f.player_id = v_player;
  v_day := world.game_day();
  v_pub := world.spread(v_port);

  select pg.good_id, g.code into v_good, v_good_c
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where pg.port_id = v_port and pg.stock > 50 and not (p.culture = any(g.culture_mask))
   order by g.code limit 1;
  if v_good is null then
    raise exception 'PROOF 6 FAILED: the starting port trades nothing with stock, so every check below would be vacuous';
  end if;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 3. A WON BARGAIN MOVES THE PRICE THE HOUSE PAYS, BY EXACTLY THE STATED AMOUNT — AND MOVES THE
  --    WORLD'S PRICE BY NOTHING. The precondition (certainty) is SET here, so the measurement is
  --    about the size of the effect rather than about luck.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  update public.world_config set value = to_jsonb(1.0) where key = 'haggle_base_success';
  update public.world_config set value = to_jsonb(1.0) where key = 'haggle_success_max';

  select mid, ask, bid into v_mid0, v_ask0, v_bid0 from world.price(v_port, v_good);
  v_res  := cmd.haggle(v_fleet, v_good, 'buy');
  v_conc := (v_res->>'concession')::numeric;
  select mid, ask, bid into v_mid1, v_ask1, v_bid1 from world.price(v_port, v_good);
  v_eff  := world.spread_effective(v_port, v_good, v_fleet);

  if (v_res->>'won')::boolean is not true or v_conc <> k_step then
    raise exception 'PROOF 6 FAILED: a certain bargain did not win exactly one step — won %, concession % against a step of %',
      v_res->>'won', v_conc, k_step;
  end if;
  -- The executed spread is the published one less the concession, to the digit.
  if v_eff <> v_pub * (1 - v_conc) then
    raise exception 'PROOF 6 FAILED: executed spread % is not the published % less % of it', v_eff, v_pub, v_conc;
  end if;
  -- And the WORLD's published price did not move: world.price takes no fleet and never will.
  if (v_mid1, v_ask1, v_bid1) is distinct from (v_mid0, v_ask0, v_bid0) then
    raise exception 'PROOF 6 FAILED: haggling moved the published price — mid % -> %, ask % -> %, bid % -> %',
      v_mid0, v_mid1, v_ask0, v_ask1, v_bid0, v_bid1;
  end if;
  raise notice 'PASS: HAGGLE_MOVES_THE_ASK — one won bargain on % took the executed spread from % to % (a cut of % per cent of the port''s cut, worth % per cent off the ask), while world.price() still publishes mid %, ask %, bid % to everyone — the port''s cut moved and the world''s price did not',
    v_good_c, v_pub, v_eff, round(v_conc * 100, 1), round(v_conc * v_pub / 2 * 100, 4),
    v_mid1, v_ask1, v_bid1;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 4. THE CONCESSION CAP BITES UNDER ABUSE. Win far more times than the day allows — the attempt
  --    budget is lifted for this block, deliberately, because the thing under test is the CAP and
  --    not the budget — and the concession must stop dead at haggle_concession_max.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  update public.world_config set value = to_jsonb(999) where key = 'haggle_attempts_per_day';
  for v_i in 1 .. 20 loop
    v_res := cmd.haggle(v_fleet, v_good, 'buy');
    if (v_res->>'ok')::boolean is not true then
      raise exception 'PROOF 6 FAILED: attempt % was refused (%) while the budget was lifted', v_i, v_res->>'error_code';
    end if;
    if (v_res->>'concession')::numeric > k_cap then
      raise exception 'PROOF 6 FAILED: the concession reached % after % certain wins, above the cap of %',
        v_res->>'concession', v_i, k_cap;
    end if;
  end loop;
  v_conc := public.haggle_concession(v_player, v_port, v_good);
  if v_conc <> k_cap then
    raise exception 'PROOF 6 FAILED: 21 certain wins left the concession at % and the cap is %; if it never reached the cap this check never tested it', v_conc, k_cap;
  end if;
  raise notice 'PASS: HAGGLE_CAP_BITES — 21 consecutive certain wins (a step of % each, which would have summed to %) stopped dead at the cap of %, and the executed spread with it',
    k_step, round(k_step * 21, 4), k_cap;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 5. AND THE FLOOR BITES UNDER THE WORST STACK THE KNOBS PERMIT. Today's seeded roster reaches
  --    only a 10 per cent purser (0015:354-358), which is not enough — so this proof authors a
  --    purser at the cap `officers.bonus_pct` already allows and rolls it back with everything
  --    else. That is a precondition it OWNS, not one it borrows.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  insert into public.officers (code, name, specialty, bonus_pct, wage_ducats, blurb)
  values ('PROOF6', 'A purser at the cap', 'PURSER', k_offcap, 1,
          'Exists for the length of one rolled-back proof, to drive the stack onto the floor.')
  returning id into v_officer;
  insert into public.player_officers (player_id, officer_id, fleet_id)
  values (v_player, v_officer, v_fleet);

  v_eff := world.spread_effective(v_port, v_good, v_fleet);
  if v_eff <> v_pub * k_floor then
    raise exception 'PROOF 6 FAILED: with a % per cent purser and a % concession the executed spread is % and the floor is %; the floor did not hold',
      k_offcap, k_cap, v_eff, v_pub * k_floor;
  end if;
  if v_eff <= v_pub * (1 - public.fleet_officer_bonus(v_fleet, 'PURSER')) * (1 - k_cap) then
    raise exception 'PROOF 6 FAILED: the floor is at or below the naive product, so it can never fire and this check proves nothing';
  end if;
  raise notice 'PASS: HAGGLE_FLOOR_BITES — a purser at the % per cent cap and a bargain at its % cap would have multiplied the port''s spread down to %, and the floor held it at % (% of the published %) — the quay keeps more than half its living whatever stacks',
    k_offcap, k_cap,
    v_pub * (1 - public.fleet_officer_bonus(v_fleet, 'PURSER')) * (1 - k_cap),
    v_eff, k_floor, v_pub;

  -- Put the world back the way it was before the timing checks: this block owned those knobs, and
  -- a proof that leaves a precondition standing has contaminated everything after it.
  delete from public.player_officers where player_id = v_player and officer_id = v_officer;
  delete from public.officers where code = 'PROOF6';
  update public.world_config set value = to_jsonb(k_base)  where key = 'haggle_base_success';
  update public.world_config set value = to_jsonb(0.85)    where key = 'haggle_success_max';
  update public.world_config set value = to_jsonb(k_tries) where key = 'haggle_attempts_per_day';
  delete from public.haggle_daily where player_id = v_player;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 6. THE ATTEMPTS ARE FINITE, EVERY OUTCOME IS REPRODUCIBLE FROM THE KEY, AND NO TWO ATTEMPTS
  --    SHARE A DRAW. Predict each attempt BEFORE playing it; count the predictions that matched.
  --    Exact, not statistical — the roll is a pure function and this is what that means.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_odds_fresh := public.haggle_odds(v_player, v_port, v_good);
  v_pred := 0; v_wins := 0;
  v_streams := array[]::text[];
  for v_i in 0 .. k_tries - 1 loop
    v_odds := public.haggle_odds(v_player, v_port, v_good);
    v_roll := voyage.rng(v_player, v_day, format('haggle:%s:%s:%s', v_port, v_good, v_i));
    v_streams := v_streams || v_roll::text;
    v_res  := cmd.haggle(v_fleet, v_good, 'buy');
    if (v_res->>'ok')::boolean is not true then
      raise exception 'PROOF 6 FAILED: attempt % of % was refused: %', v_i + 1, k_tries, v_res->>'error_code';
    end if;
    if (v_res->>'won')::boolean = (v_roll < v_odds) and (v_res->>'attempt')::int = v_i + 1 then
      v_pred := v_pred + 1;
    end if;
    if (v_res->>'won')::boolean then v_wins := v_wins + 1; end if;
  end loop;
  if v_pred <> k_tries then
    raise exception 'PROOF 6 FAILED: only % of % outcome(s) matched the draw voyage.rng predicts for their key', v_pred, k_tries;
  end if;
  -- No two attempts of the day drew the same number: that is what "a retry costs a chance" means.
  if (select count(distinct s) from unnest(v_streams) s) <> k_tries then
    raise exception 'PROOF 6 FAILED: the % attempt(s) of the day did not take % distinct draws; a retry can re-roll', k_tries, k_tries;
  end if;

  v_res := cmd.haggle(v_fleet, v_good, 'buy');
  if (v_res->>'ok')::boolean is not false or v_res->>'error_code' <> 'E_HAGGLE_SPENT' then
    raise exception 'PROOF 6 FAILED: the % + 1 th attempt was not refused E_HAGGLE_SPENT (got %)', k_tries, v_res;
  end if;
  raise notice 'PASS: HAGGLE_ATTEMPTS_ARE_FINITE — % attempts, % won, and the % + 1 th refused E_HAGGLE_SPENT with % fix(es); the counter advanced on refusals as well as wins',
    k_tries, v_wins, k_tries, jsonb_array_length(v_res->'fixes');
  raise notice 'PASS: HAGGLE_NO_RETRY_REROLLS — all % outcome(s) were PREDICTED from voyage.rng before they were played and every one matched, on % distinct draws; the attempt index is written before the draw is taken, so there is no ordering of calls that re-rolls one',
    k_tries, k_tries;

  -- The hardening, when there was anything to harden.
  if v_wins < k_tries then
    if public.haggle_odds(v_player, v_port, v_good)
       <> round(least(public.wc_num('haggle_success_max'),
                (k_base + public.player_skill_bonus(v_player, 'SPREAD'))
                * greatest(0, 1 - k_harden * (k_tries - v_wins))), 4) then
      raise exception 'PROOF 6 FAILED: % refusal(s) did not harden the odds by exactly % each — fresh %, now %',
        k_tries - v_wins, k_harden, v_odds_fresh, public.haggle_odds(v_player, v_port, v_good);
    end if;
  end if;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 7. THE COIN IS NOT WEIGHTED. Two thousand draws over FIXED keys — a fixed subject uuid and
  --    a counter — so this is deterministic on every run and on every machine and can never flake
  --    on a correct system. The band is 4.5 sigma wide, which is stated rather than guessed:
  --    sigma = sqrt(n p (1-p)); at n = 2000 and p = base that is about 22 draws, so the band is
  --    about +/- 100 out of 2000. Only a genuinely skewed generator can leave it.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_draws := 2000;
  select count(*) into v_hits
    from generate_series(1, v_draws) i
   where voyage.rng('00000000-0f06-4000-8000-0000000000ff'::uuid, 0, 'haggle:uniformity:' || i) < k_base;
  v_rate   := v_hits::numeric / v_draws;
  v_expect := k_base * v_draws;
  v_sigma  := sqrt(v_draws * k_base * (1 - k_base));
  if abs(v_hits - v_expect) > 4.5 * v_sigma then
    raise exception 'PROOF 6 FAILED: % of % fixed-key draws fell under a chance of %, expected % +/- % (4.5 sigma). The generator behind the bargain is skewed',
      v_hits, v_draws, k_base, round(v_expect, 1), round(4.5 * v_sigma, 1);
  end if;
  raise notice 'PASS: HAGGLE_ODDS_ARE_HONEST — % of % fixed-key draws landed under an advertised chance of % (a measured rate of %), against an expectation of % +/- % at 4.5 sigma; the keys are fixed, so this figure is the same on every run and a red here is a real skew and never a bad night',
    v_hits, v_draws, k_base, round(v_rate, 4), round(v_expect, 1), round(4.5 * v_sigma, 1);

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 7b. IT IS WORTH DOING AT ALL. This is the marker migration 0024 exists because nobody had:
  --     0022 shipped a mechanic that was arithmetically correct and worth 0.36 per cent of a
  --     trade, which reads as broken rather than as subtle. A correct mechanic nobody can feel is
  --     a failed feature, so the MAGNITUDE is guarded here and not only the behaviour.
  --
  --     A round trip pays half the spread on each leg, so a bargain worth `c` of the spread saves
  --     `c x spread` of the stake. Both ends of the band are stated: below 2 per cent it is the
  --     rounding error 0024 was written to fix, and above 3.5 per cent an optional three-tap
  --     mechanic starts rivalling the 12-14 per cent that choosing the right cargo is worth.
  --     Every figure is READ from world_config, so retuning the mechanic retunes this check with
  --     it and only a change that leaves the band goes red.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select avg(world.spread(id)) into v_rate from public.ports;
  v_expect := (v_rate - greatest(v_rate * k_floor, v_rate * (1 - k_cap))) * 100;
  if v_expect < 2.0 or v_expect > 3.5 then
    raise exception 'PROOF 6 FAILED: a fully bargained round trip is worth % per cent of the stake, outside the 2.0-3.5 band. Below it the mechanic is a rounding error; above it an optional three-tap action rivals choosing the cargo',
      round(v_expect, 3);
  end if;
  -- And every attempt of the day must be able to improve the bargain: `attempts x step` must reach
  -- the cap exactly. If it overshot, the last tap would be a tap the game invited you to waste.
  if k_step * k_tries <> k_cap then
    raise exception 'PROOF 6 FAILED: % attempt(s) x a step of % is %, and the cap is %; an attempt that cannot improve the bargain is a wasted tap',
      k_tries, k_step, k_step * k_tries, k_cap;
  end if;
  -- The floor must clip the STACK and not the mechanic alone, or the cap above is a lie.
  if (1 - k_cap) <= k_floor
     or (1 - k_offcap / 100.0) * (1 - k_cap) >= k_floor then
    raise exception 'PROOF 6 FAILED: the floor of % either clips haggling on its own (executed %) or no longer clips a fully officered stack (%)',
      k_floor, 1 - k_cap, (1 - k_offcap / 100.0) * (1 - k_cap);
  end if;
  raise notice 'PASS: HAGGLE_IS_WORTH_DOING — a bargain at the cap is worth % per cent of the stake over a round trip, measured across all % ports (average published spread %), which is % per cent of a median 13 per cent voyage and inside the 2.0-3.5 band; % attempts x a step of % lands EXACTLY on the cap of % so no tap is wasted; and the floor of % clips a fully officered stack (%) while leaving the mechanic alone unclipped at %',
    round(v_expect, 3), (select count(*) from public.ports), round(v_rate, 4),
    round(v_expect / 13 * 100, 0), k_tries, k_step, k_cap,
    k_floor, round((1 - k_offcap / 100.0) * (1 - k_cap), 4), 1 - k_cap;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 8. AND IT ALL WORKS THROUGH THE DOOR A BROWSER USES. As `authenticated`: RLS on, and only the
  --    two declared entry points reachable. This is the half no self-assert can see, because a
  --    migration runs as the owner.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  delete from public.haggle_daily where player_id = v_player;
  begin
    set local role authenticated;

    v_state := world.haggle_state(v_fleet, v_good);
    if (v_state->>'docked')::boolean is not true
       or (v_state->>'attempts_left')::int <> k_tries
       or (v_state->>'attempts_max')::int <> k_tries
       or (v_state->>'concession')::numeric <> 0
       or (v_state->>'concession_max')::numeric <> k_cap then
      raise exception 'PROOF 6 FAILED: world.haggle_state read wrong through the client door: %', v_state;
    end if;

    v_res := cmd.haggle(v_fleet, v_good, 'buy');
    if (v_res->>'ok')::boolean is not true then
      raise exception 'PROOF 6 FAILED: cmd.haggle refused a legal bargain through the client door: %', v_res;
    end if;
    v_state := world.haggle_state(v_fleet, v_good);
    if (v_state->>'attempts_left')::int <> k_tries - 1 then
      raise exception 'PROOF 6 FAILED: the read did not see the attempt the verb just spent: %', v_state;
    end if;

    -- ANTI-PROOF: the internal readings are NOT the client's, and neither is the spread fold.
    v_err := null;
    begin
      perform public.haggle_odds(v_player, v_port, v_good);
    exception when insufficient_privilege then v_err := 'refused';
    end;
    if v_err is null then
      raise exception 'PROOF 6 FAILED: authenticated executed public.haggle_odds, which is not a client entry point';
    end if;
    v_err := null;
    begin
      perform world.spread_effective(v_port, v_good, v_fleet);
    exception when insufficient_privilege then v_err := 'refused';
    end;
    if v_err is null then
      raise exception 'PROOF 6 FAILED: authenticated executed world.spread_effective, which is not a client entry point';
    end if;

    -- AND A BARGAIN IS A PRIVATE FACT: RLS SHOWS THIS HOUSE ITS OWN ROW AND NO OTHER.
    --
    -- WRITTEN 2026-08-22 AS THE OPPOSITE ASSERTION, AND THAT IS THE POINT OF THIS NOTE. When this
    -- file was first written the check had to accept a REFUSAL, because migration 0018 had swept
    -- EXECUTE off `public.current_player_id()` and every RLS policy that calls it — eleven of them
    -- — raised 42501. This proof is where that was found. Migration 0023 repaired it by sweeping
    -- the catalogue for the whole class, so the property this file wanted all along is now the
    -- property the database has, and the assertion says so plainly instead of tolerating both.
    -- scripts/db/proofs/03_grant_lockdown.sql carries the general form: every private table, and
    -- the isolation between two houses.
    select count(*) into v_n from public.haggle_daily;
    if v_n <> 1 then
      raise exception 'PROOF 6 FAILED: authenticated sees % row(s) of haggle_daily and should see exactly its own 1', v_n;
    end if;

    set local role none;
  exception when others then
    set local role none;
    raise;
  end;
  raise notice 'PASS: HAGGLE_CLIENT_PATH — as `authenticated`, world.haggle_state read % attempts and cmd.haggle spent one and the read saw it; public.haggle_odds and world.spread_effective were both REFUSED with 42501, so the folds stayed on the server; and RLS showed the house EXACTLY its own 1 bargain row and none of anybody else''s — an assertion this file could not make until 0023 repaired the policy grant that 0018 had swept away, a defect this proof is where it was found',
    k_tries;
end $$;
