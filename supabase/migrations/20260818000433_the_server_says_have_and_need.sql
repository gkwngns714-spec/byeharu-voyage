-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0433 - THE SERVER SAYS HAVE AND NEED  (a refusal is "Money 5,000 / 9,000"; the news, the battle and voyage reports in short lines; a best sale
--        she cannot pay for in full is offered at the most she can, with what it would need; a room ladder serves her level)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "too much word should be shorter. for example wave 24. just tell me what i have, and what is required." (row 350). The
--   client was cut to HAVE / NEED words by #708-#716 (`Waves 12 / 30`, `Money 5,000 / 9,000`, `Crew 8 / 8`, `Title 1 / 2`). The server still wrote
--   sentences: "Macaronesia and the Canary Current asks title 2 and wave resistance 10 — you are title 1 and your fleet holds 12".
--
-- WHAT THIS FILE DOES (no table, no knob, no switch, no job):
--   1. A REFUSAL SAYS WHAT SHE HAS AND WHAT IS NEEDED. New cmd.refusal_line(code, figures) (IMMUTABLE, server-only) and cmd.refusal_figure(numeric):
--      figures {have, need, unit} -> "<Label> have / need[ unit]": `Money 5,000 / 9,000`, `Supplies 2.9 / 33 days`, `Hold 120 / 150 t`, `Crew 6 / 8`,
--      `Range 300 / 450 miles`, `Reputation 60 / 300`; the label by code (E_ENDURANCE Supplies, E_HOLD_FULL Hold, E_CITY_BROKE City money, ...), else
--      by unit (ducats Money, crew Crew, ...). A closed sea's figures (public.sea_refusal, 0215/0396) -> `<Sea> closed. Title 1 / 2. Waves 12 / 30.`
--      (the asks she is short of, as the client's seaWallWords prints them). ONE HUNK in cmd.refusal, THE one maker of a refusal value (cmd.refuse
--      raises it, cmd.refusal_caught rebuilds it, voyage.sail_refusal, voyage.leg_refusal and public.sea_refusal return it): its sentence is
--      cmd.refusal_line's when the figures say it, else the sentence it was given. Codes, figures and every other key are unmoved; a refusal with no
--      figures keeps its sentence. Korean is the client's (src/components/ui/refusalWords.ts: the same label and figures).
--   2. THE NEWS IN SHORT HEADLINES. public.news_kinds' eight templates (0347, 0362) re-worded, the same {words} in each: UPDATE `{title}` (was
--      `Update: {title}`), NEW_HARBOUR `New port: {city}`, RELATIONS `{a}–{b}: {stance}`, BIG_SALE/BIG_BUY `{company} sold/bought {qty} {good}:
--      {n} · {city}`, PRICE_SPIKE `{good} {p} · {city}`, PIRATES `{company} raided: {n}`, CAPITAL_GIFT `{capital} → {company}: {n}`. The six
--      update titles longer than 40 letters (0375, 0413, 0422, 0423, 0425, 0426) are shortened in their own rows (world_news, key 'update:<n>',
--      matched on their exact old title; the append-only trigger is lifted for that one statement and put back, asserted).
--   3. THE BATTLE AND VOYAGE REPORTS IN SHORT LINES. Words only; every figure, outcome, key and the log are unmoved:
--      public.battle_words (one hunk: its five outcome lines; `We broke off.` and `We boarded her.` stand), voyage.fight_round_line (12 hunks:
--      `Round 2 · close · we hit 3 of 5; they hit Gaivota −17%. Raiders −40%.`), voyage.raid_report (31 hunks: `Raiders: ~2 × Şebek, 81 crew.`,
--      `They saw us first.`, `Boarded: crew 40 vs 55. Thrown back.`), voyage.report_line (3 hunks: ` Crew −3.`), and the 14 rows of
--      public.voyage_event_kinds (`Gale: hull −40.`, `Becalmed: 6 hours lost.`, `Quiet day.`; each matched on its exact old prose).
--      public.reputation_arrival and public.reputation_lap write no words (keys and amounts only): not touched. public.battle_resolve is not touched
--      (0427 and 0432 cut it); public.battle_log writes numbers only.
--   4. A BEST SALE AT THE MOST HER PURSE PAYS FOR (world.best_sales, 3 hunks). Before: "No money" while she held 40,000 and the full load cost
--      87,000. Now, when no sale is within her purse: the best full load (the same order: gains first, best per day) says what it NEEDS (its buy,
--      and her stores unless they may be owed); a good bought here is re-priced for the most units her purse less those stores pays for (world.quote
--      at this city, at most three narrowing steps), and the best of those rows within her purse is the answer. New keys `have` (her purse) and
--      `need` (the full load's buy + stores) whenever the full load was beyond her purse, so the card prints `Money 40,000 / 87,000` and opens the
--      trip at the units served. `short` keeps 0351's meaning: no sale is named (her purse buys not one unit, or no row fits).
--   5. A ROOM LADDER SAYS HER LEVEL (world.house_room, 2 hunks): `fleets.level` is her Trading level (the p_level public.room_steps is given),
--      `ships.level` the greater of her Seamanship and Command levels, so the Fleets room card prints `Trading 2 / 3`.
--
-- NOT DONE: a skill's refusal (E_NEEDS_SKILL, E_SKILL_PREREQ, E_SKILL_ORDER) keeps its sentence: it names the skill, which the figures do not.
--   cmd.captain_skill_next and public.augment_fitting_for build their own envelopes (not through cmd.refusal): their sentences stand.
--   voyage.settle's own fallback words (a fight with no sentence) are not cut: raid_report always gives one. Update titles posted by 0427-0432 are
--   their own files'.
-- budget: no table, no job, no knob, no autovacuum or fillfactor; six world_news rows updated once; world.best_sales asks one more board_sell and
--   at most three world.quote calls for a good whose full load is beyond her purse, inside its own 2.5 s budget.
-- LOCKS: CREATE FUNCTION x2; CREATE OR REPLACE x8 (by hunks); ALTER TABLE world_news DISABLE/ENABLE TRIGGER (SHARE ROW EXCLUSIVE, milliseconds);
--   UPDATE of 14 voyage_event_kinds rows, 8 news_kinds rows, 6 world_news rows.
-- TIME: milliseconds; the probe calls pure functions. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/short-server/rollback-0433.sql (a draft): reverses every hunk, puts the old templates and prose
--   back. The six shortened news titles stay short.
-- SELF-ASSERT: each hunk once in its body and reversing to the pre-image; grants, volatility, definer, search path and owner of each body unmoved;
--   no other function moved; then a probe of pure calls (no row written) on the new words.
-- VERSION: 0433 = the queue 0427..0432 + 1. 0427 and 0432 cut public.battle_resolve and add public.raid_close; this file touches neither.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_hunks     jsonb;
  v_fns       text[];
  v_fn        text;
  v_pre       text;
  v_def       text;
  v_back      text;
  v_meta      text;
  v_fn_before text;
  h           jsonb;
  v_n         int;
  v_cnt       int := 0;
  v_rows      int;
  v_kept      text := '';
  v_r         jsonb;
  v_s         text;
  z           record;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('cmd.refusal(text,text,jsonb)') is null or to_regprocedure('world.best_sales(uuid,uuid)') is null
     or to_regprocedure('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)') is null or to_regprocedure('world.house_room()') is null
     or to_regclass('public.news_kinds') is null or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0433 refuses: the refusal (0050), the best sale (0351), the raid report (0353), the room (0354) or the news (0347) is not in this world';
  end if;
  if to_regprocedure('cmd.refusal_line(text,jsonb)') is not null then
    raise exception '0433 refuses: it has been applied once';
  end if;

  -- ── 1. THE HUNKS: [function, old, new], applied in order, each once ──
  v_hunks := jsonb_build_array(
    -- cmd.refusal: THE one maker of a refusal value
    jsonb_build_array('cmd.refusal(text,text,jsonb)',
$h$           'code', p_code, 'sentence', btrim(p_sentence), 'figures', p_figures))
$h$,
$h$           'code', p_code, 'sentence', coalesce(cmd.refusal_line(p_code, p_figures), btrim(p_sentence)), 'figures', p_figures))
  -- 0433: what she has and what is needed (cmd.refusal_line), when the figures say it; else the sentence given
$h$),
    -- public.battle_words: the attacker's outcome line
    jsonb_build_array('public.battle_words(jsonb,jsonb)',
$h$  v_line := case when p_fight->>'outcome' = 'NO_FIGHT' then 'There was no one left to fight.'
                 when (p_fight->>'stood_off')::boolean then 'We had nothing left to fight with.'
                 when (p_fight->>'slipped')::boolean then 'She saw us first and slipped away.'
                 when (p_fight->>'broke_off')::boolean then 'We broke off.'
                 when p_fight->>'outcome' = 'DRIVEN_OFF' then 'We came alongside and were thrown back.'
                 when p_fight->>'outcome' = 'RANSOM' then 'We came alongside and she offered terms.'
$h$,
$h$  v_line := case when p_fight->>'outcome' = 'NO_FIGHT' then 'No fight.'   -- 0433: short lines
                 when (p_fight->>'stood_off')::boolean then 'Nothing to fight with.'
                 when (p_fight->>'slipped')::boolean then 'She slipped away.'
                 when (p_fight->>'broke_off')::boolean then 'We broke off.'
                 when p_fight->>'outcome' = 'DRIVEN_OFF' then 'Thrown back.'
                 when p_fight->>'outcome' = 'RANSOM' then 'She paid terms.'
$h$),
    -- voyage.fight_round_line: one round
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                || format('%s for %s%% damage', coalesce(p_ships->((h->>0)::int - 1)->>'name', 'Your ship'), h->>1);
$h$,
$h$                || format('%s −%s%%', coalesce(p_ships->((h->>0)::int - 1)->>'name', 'Your ship'), h->>1);   -- 0433: short words
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$  v_you := case when p_round ? 'flee' then 'you run before them'   -- 0353$h$,
$h$  v_you := case when p_round ? 'flee' then 'we run'   -- 0353$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                when p_g = 1 and p_first = 'THEY' then 'you are caught unready'
$h$,
$h$                when p_g = 1 and p_first = 'THEY' then 'caught unready'
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                when v_can = 0 then 'you have no guns to answer with'
$h$,
$h$                when v_can = 0 then 'no guns'
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                when v_fired = 0 then 'your guns cannot reach them'
$h$,
$h$                when v_fired = 0 then 'out of range'
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                when v_hits = 0 then format('you miss with %s shot%s', v_fired, case when v_fired = 1 then '' else 's' end)
$h$,
$h$                when v_hits = 0 then format('we miss ×%s', v_fired)
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                else format('you hit with %s of %s shot%s', v_hits, v_fired, case when v_fired = 1 then '' else 's' end) end;
$h$,
$h$                else format('we hit %s of %s', v_hits, v_fired) end;
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$  v_they := case when p_g = 1 and p_first = 'YOU' then 'they are caught unready'
$h$,
$h$  v_they := case when p_g = 1 and p_first = 'YOU' then 'they caught unready'
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                 when (v_b->>'fired')::int = 0 then 'their guns cannot reach you'
$h$,
$h$                 when (v_b->>'fired')::int = 0 then 'they out of range'
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$                              then format(' (armour turned %s%%)', $h$,
$h$                              then format(' (armour −%s%%)', $h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$  return format('Round %s · %s range — %s; %s.', p_g, lower(p_round->>'range'), v_you, v_they)
$h$,
$h$  return format('Round %s · %s · %s; %s.', p_g, lower(p_round->>'range'), v_you, v_they)
$h$),
    jsonb_build_array('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
$h$         || case when v_hits > 0 then format(' The %s are %s%% damaged.', p_foe, $h$,
$h$         || case when v_hits > 0 then format(' %s −%s%%.', initcap(p_foe), $h$),
    -- voyage.raid_report: a raid, in short lines
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'They stood off and did not close.',
$h$,
$h$    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'They stood off.',   -- 0433: short lines
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$then 'The sail stood off and never closed.'
$h$,
$h$then 'A sail stood off.'
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$else format('Raiders: about %s × %s, %s crew. They looked you over and stood off.',
$h$,
$h$else format('Raiders: ~%s × %s, %s crew. Stood off.',
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$then format('Raiders: one small %s, %s crew.', v_name, round(r_crew))
$h$,
$h$then format('Raiders: 1 small %s, %s crew.', v_name, round(r_crew))
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$else format('Raiders: about %s × %s, %s crew.', round(r_n), v_name, round(r_crew)) end;
$h$,
$h$else format('Raiders: ~%s × %s, %s crew.', round(r_n), v_name, round(r_crew)) end;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || ('Ready for them: ' || v_txt || '.');
$h$,
$h$    v_lines := v_lines || ('Ready: ' || v_txt || '.');
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$  select string_agg(format('%s lays the guns on %s.', e->>'gunner', e->>'name'), ' ' order by o)
$h$,
$h$  select string_agg(format('Gunner %s on %s.', e->>'gunner', e->>'name'), ' ' order by o)
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'Your lookout saw them first, and you slipped away before they could close.'::text;
$h$,
$h$    v_lines := v_lines || 'Seen first; slipped away.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'We saw them first and slipped away.',
$h$,
$h$    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'Slipped away.',
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'Your lookout saw them first.'::text;
$h$,
$h$    v_lines := v_lines || 'We saw them first.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'They saw you before your lookout saw them.'::text;
$h$,
$h$    v_lines := v_lines || 'They saw us first.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'Both sides saw each other at the same moment.'::text;
$h$,
$h$    v_lines := v_lines || 'Both saw at once.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'You have nothing aboard to pay them with.'::text;
$h$,
$h$    v_lines := v_lines || 'Nothing aboard to pay.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'They will take no ransom.'::text;
$h$,
$h$    v_lines := v_lines || 'No ransom taken.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'You turn and run.'::text;
$h$,
$h$    v_lines := v_lines || 'We run.'::text;
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'You pay their price, and they let you pass.'::text;
    v_sentence := 'We paid their price and they let us pass.';
$h$,
$h$    v_lines := v_lines || 'Paid; let pass.'::text;
    v_sentence := 'Paid; let pass.';
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'You get clear of them.'::text;
    v_sentence := 'We ran, and got clear of them.';
$h$,
$h$    v_lines := v_lines || 'Got clear.'::text;
    v_sentence := 'Ran; got clear.';
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || 'They break off and run.'::text;
    v_sentence := 'They broke off and ran.';
$h$,
$h$    v_lines := v_lines || 'They broke off.'::text;
    v_sentence := 'They broke off.';
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    select string_agg(format('%s leads the crew on %s (+%s%%).', e->>'boarder', e->>'name',
$h$,
$h$    select string_agg(format('%s boards from %s (+%s%%).', e->>'boarder', e->>'name',
$h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$    v_lines := v_lines || (format('Close quarters: they come alongside — your %s crew against their %s.', $h$,
$h$    v_lines := v_lines || (format('Boarded: crew %s vs %s.', $h$),
    jsonb_build_array('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
$h$                           || case when v_surrender then ' You surrender; they board and take what they can carry.'
                                   else case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                                       when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                                       else ' They board and take what they can carry.' end end);
    v_sentence := case when v_surrender then 'We surrendered, and they took what they could carry.'
                       else case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                           when 'RANSOM'     then 'They came alongside and we paid them off.'
                                           else 'They came aboard and took what they could carry.' end end;
$h$,
$h$                           || case when v_surrender then ' Surrendered; plundered.'
                                   else case v_outcome when 'DRIVEN_OFF' then ' Thrown back.'
                                                       when 'RANSOM'     then ' Paid off.'
                                                       else ' Plundered.' end end);
    v_sentence := case when v_surrender then 'Surrendered; plundered.'
                       else case v_outcome when 'DRIVEN_OFF' then 'Thrown back.'
                                           when 'RANSOM'     then 'Paid off.'
                                           else 'Plundered.' end end;
$h$),
    -- voyage.report_line: the crew's line under a day
    jsonb_build_array('voyage.report_line(integer,text,jsonb)',
$h$             then format(' We buried %s of the crew; the surgeon kept the rest.',
$h$,
$h$             then format(' Crew −%s (surgeon).',   -- 0433: short lines
$h$),
    jsonb_build_array('voyage.report_line(integer,text,jsonb)',
$h$             then format(' We buried %s of the crew.', p_payload->>'crew_lost')
$h$,
$h$             then format(' Crew −%s.', p_payload->>'crew_lost')
$h$),
    jsonb_build_array('voyage.report_line(integer,text,jsonb)',
$h$             then ' The surgeon brought every man through it.'
$h$,
$h$             then ' No crew lost (surgeon).'
$h$),
    -- world.best_sales: at the most her purse pays for
    jsonb_build_array('world.best_sales(uuid,uuid)',
$h$  v_short   boolean;                -- 0351: sales are priced, none within her purse
$h$,
$h$  v_short   boolean;                -- 0351: sales are priced, none within her purse
  v_full    record;                 -- 0433: the best full load, when none is within her purse: what it needs
  v_need    numeric;                -- 0433: that load's buy and stores (null: the full load is within her purse)
  v_n       numeric;                -- 0433: the most units her purse less those stores pays for
  v_qt      numeric;                -- 0433: world.quote's total for v_n
  v_qu      numeric;
  v_i       int;
$h$),
    jsonb_build_array('world.best_sales(uuid,uuid)',
$h$           v_short or (exists (select 1 from pool) and not exists (select 1 from c))
      into v_best, v_far, v_short;
$h$,
$h$           v_short or (exists (select 1 from pool) and not exists (select 1 from c))
      into v_best, v_far, v_short;
    -- 0433: NONE WITHIN HER PURSE: the best full load (the same order) says what it needs, and a good bought here is priced for the most units her
    -- purse less those stores pays for (world.quote here, at most three narrowing steps); the best of those rows within her purse is the answer.
    v_need := null;
    if v_short and v_best is null then
      select x.e, case when a.basis <> 'on_board' then coalesce((x.e->>'cost')::numeric, 0) else 0 end as buy,
             case when v_credit then 0 else coalesce((x.e->'supplies'->>'cost')::numeric, 0) end as stores
        into v_full
        from jsonb_array_elements(v_rows) x(e)
       where (x.e->>'sailable')::boolean and jsonb_typeof(x.e->'profit') = 'number' and x.e->>'port' is distinct from v_port.code
         and (a.basis = 'on_board' or (x.e->>'units')::numeric <= (x.e->'supplies'->>'units_fit')::numeric)
       order by ((x.e->>'profit')::numeric > 0) desc,
                case when (x.e->>'profit')::numeric > 0
                     then (x.e->>'profit')::numeric / greatest(extract(epoch from ((x.e->>'arrive_at')::timestamptz - now())), 1) end desc nulls last,
                (x.e->>'profit')::numeric desc, (x.e->>'days')::numeric nulls last, x.e->>'port'
       limit 1;
      if v_full.e is not null then
        v_need := round(v_full.buy + v_full.stores);
        if a.basis <> 'on_board' and v_full.buy > 0 and coalesce((v_full.e->>'units')::numeric, 0) > 1 and v_purse > v_full.stores then
          v_n := least(floor((v_purse - v_full.stores) * (v_full.e->>'units')::numeric / v_full.buy), (v_full.e->>'units')::numeric - 1);
          v_i := 0;
          loop
            exit when v_n < 1 or v_i >= 3;
            select q.units, q.total into v_qu, v_qt from world.quote(p_port, gd.id, v_n, 'buy', null, p_fleet) q;
            exit when v_qt is not null and v_qt + v_full.stores <= v_purse;
            v_n := least(v_n - 1, floor(v_n * (v_purse - v_full.stores) / greatest(coalesce(v_qt, 0), 1)));
            v_i := v_i + 1;
          end loop;
          if v_n >= 1 and v_qt is not null and v_qt + v_full.stores <= v_purse then
            select x.e into v_best
              from jsonb_array_elements(world.board_sell(gd.id, p_fleet, v_ctx || jsonb_build_object(
                     'units', v_n, 'basis', 'asked', 'fit', false,
                     'src', jsonb_build_object('code', v_port.code, 'units', v_qu, 'cost', v_qt)))) x(e)
             where (x.e->>'sailable')::boolean and jsonb_typeof(x.e->'profit') = 'number' and x.e->>'port' is distinct from v_port.code
               and (x.e->>'units')::numeric <= (x.e->'supplies'->>'units_fit')::numeric
               and coalesce((x.e->>'cost')::numeric, 0) + case when v_credit then 0 else coalesce((x.e->'supplies'->>'cost')::numeric, 0) end <= v_purse
             order by ((x.e->>'profit')::numeric > 0) desc,
                      case when (x.e->>'profit')::numeric > 0
                           then (x.e->>'profit')::numeric / greatest(extract(epoch from ((x.e->>'arrive_at')::timestamptz - now())), 1) end desc nulls last,
                      (x.e->>'profit')::numeric desc, (x.e->>'days')::numeric nulls last, x.e->>'port'
             limit 1;
            v_short := v_best is null;
          end if;
        end if;
      end if;
    end if;
$h$),
    jsonb_build_array('world.best_sales(uuid,uuid)',
$h$               'short', v_short and v_best is null,
$h$,
$h$               'short', v_short and v_best is null,
               'have', case when v_need is not null then round(v_purse) end, 'need', v_need,   -- 0433: Money have / need, when the full load is beyond her purse
$h$),
    -- world.house_room: each ladder's level
    jsonb_build_array('world.house_room()',
$h$      'bought', v_fb, 'full', v_ffull,
$h$,
$h$      'bought', v_fb, 'full', v_ffull,
      'level', (public.player_progress(v_id) -> 'trading' ->> 'level')::int,   -- 0433: her level on this ladder (room_steps' p_level): `Trading 2 / 3`
$h$),
    jsonb_build_array('world.house_room()',
$h$      'bought', v_sb, 'full', v_sfull,
$h$,
$h$      'bought', v_sb, 'full', v_sfull,
      'level', greatest(public.skill_level(v_id, 'SEAMANSHIP'), public.skill_level(v_id, 'COMMAND')),   -- 0433: as room_steps is given it
$h$));

  select array_agg(distinct x->>0) into v_fns from jsonb_array_elements(v_hunks) x;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not (p.oid::regprocedure::text = any(
           array(select f::regprocedure::text from unnest(v_fns) f)));

  -- ── 2. THE NEW FUNCTIONS (before the hunk that calls them) ──
  execute $f$
create function cmd.refusal_figure(p_n numeric)
 returns text
 language sql
 immutable
as $fn$
  -- 0433: a refusal's figure as the client prints it: a whole number with thousands commas (5,000), else one decimal (2.9).
  select case when round(p_n, 1) = trunc(round(p_n, 1)) then regexp_replace(trunc(round(p_n, 1))::text, '(\d)(?=(\d{3})+$)', '\1,', 'g')
              else regexp_replace(trunc(round(p_n, 1))::text, '(\d)(?=(\d{3})+$)', '\1,', 'g') || '.' || right(round(abs(p_n), 1)::text, 1) end
$fn$
$f$;
  execute $f$
create function cmd.refusal_line(p_code text, p_figures jsonb)
 returns text
 language plpgsql
 immutable
as $fn$
-- 0433: WHAT SHE HAS AND WHAT IS NEEDED (owner 2026-11-15: "just tell me what i have, and what is required"). The sentence of a refusal whose figures
-- say it: {have, need, unit} -> "<Label> have / need[ unit]"; a closed sea's (public.sea_refusal) -> "<Sea> closed. Title 1 / 2. Waves 12 / 30."
-- (the asks she is short of). Null for any other shape: the sentence given stands. Read by cmd.refusal alone. The Korean is the client's
-- (src/components/ui/refusalWords.ts), the same labels.
declare
  v_unit  text;
  v_label text;
  v_st    boolean;
  v_sw    boolean;
begin
  if p_figures is null or jsonb_typeof(p_figures) <> 'object' then
    return null;
  end if;
  if jsonb_typeof(p_figures->'zone_name') = 'string' and jsonb_typeof(p_figures->'needs_title') = 'number' and jsonb_typeof(p_figures->'needs_wave') = 'number' then
    v_st := coalesce(jsonb_typeof(p_figures->'title') = 'number' and (p_figures->>'title')::numeric < (p_figures->>'needs_title')::numeric, false);
    v_sw := coalesce(jsonb_typeof(p_figures->'wave') = 'number' and (p_figures->>'wave')::numeric < (p_figures->>'needs_wave')::numeric, false);
    if not v_st and not v_sw then   -- neither is short by her figures: both she has
      v_st := jsonb_typeof(p_figures->'title') is not distinct from 'number';
      v_sw := jsonb_typeof(p_figures->'wave') is not distinct from 'number';
    end if;
    return concat_ws(' ', format('%s closed.', p_figures->>'zone_name'),
                     case when v_st then format('Title %s / %s.', cmd.refusal_figure((p_figures->>'title')::numeric), cmd.refusal_figure((p_figures->>'needs_title')::numeric)) end,
                     case when v_sw then format('Waves %s / %s.', cmd.refusal_figure((p_figures->>'wave')::numeric), cmd.refusal_figure((p_figures->>'needs_wave')::numeric)) end);
  end if;
  if jsonb_typeof(p_figures->'have') is distinct from 'number' or jsonb_typeof(p_figures->'need') is distinct from 'number'
     or jsonb_typeof(p_figures->'unit') is distinct from 'string' then
    return null;
  end if;
  if p_code in ('E_NEEDS_SKILL', 'E_SKILL_PREREQ', 'E_SKILL_ORDER') then
    return null;   -- the skill's own name is the sentence's (public.requirements_refusal): "Skill 2 / 3" would not say which
  end if;
  v_unit := p_figures->>'unit';
  v_label := case
    when p_code = 'E_ENDURANCE' then 'Supplies'
    when p_code in ('E_LEG_TOO_FAR', 'E_OUT_OF_REACH') then 'Range'
    when p_code = 'E_HOLD_FULL' and v_unit = 't' then 'Hold'
    when p_code = 'E_CITY_BROKE' then 'City money'
    when p_code = 'E_WORLD_BROKE' then 'World money'
    when p_code in ('E_DAILY_CAP', 'E_DAY_CAP') then 'Day limit'
    when p_code = 'E_INVEST_MIN' then 'Investment'
    when p_code in ('E_SHIP_LEVEL', 'E_SLOT_LOCKED') then 'Ship level'
    when p_code = 'E_DRAFT' then 'Depth'
    when p_code = 'E_ATTACK_COOLDOWN' then 'Wait'
    when p_code in ('E_CONTRACT_SHORT', 'E_CONTRACT_EXPIRED') then 'Delivered'
    when p_code = 'E_OVER_DECK' then 'Deck'
    when p_code = 'E_OVER_HANDS' then 'Hands'
    when p_code = 'E_PREPARING' then 'Ready'
    else case v_unit when 'ducats' then 'Money' when 'crew' then 'Crew' when 'days' then 'Days' when 't' then 'Cargo'
                     when 'miles' then 'Range' when 'minutes' then 'Wait' when 'seconds' then 'Wait' when 'reputation' then 'Reputation'
                     when 'level' then 'Level' when 'levels' then 'Level' when 'depth' then 'Depth' else initcap(v_unit) end
  end;
  return format('%s %s / %s', v_label, cmd.refusal_figure((p_figures->>'have')::numeric), cmd.refusal_figure((p_figures->>'need')::numeric))
         || case v_unit when 'days' then ' days' when 't' then ' t' when 'miles' then ' miles' when 'minutes' then ' min' when 'seconds' then ' s' else '' end;
end
$fn$
$f$;
  revoke all on function cmd.refusal_figure(numeric) from public, anon, authenticated;
  revoke all on function cmd.refusal_line(text, jsonb) from public, anon, authenticated;

  -- ── 3. THE HUNKS, function by function: each once in the pre-image, applied, then once in the new body and reversing ──
  foreach v_fn in array v_fns loop
    v_pre := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
      into v_meta from pg_proc p where p.oid = v_fn::regprocedure;
    v_def := v_pre;
    for h in select x from jsonb_array_elements(v_hunks) x where x->>0 = v_fn loop
      v_n := (length(v_def) - length(replace(v_def, h->>1, ''))) / length(h->>1);
      if v_n <> 1 or (length(v_pre) - length(replace(v_pre, h->>1, ''))) / length(h->>1) <> 1 then
        raise exception '0433 self-assert FAIL: a hunk occurs % time(s) in %, not once: the deployed body is not what this file was written against: %', v_n, v_fn, left(h->>1, 120);
      end if;
      v_def := replace(v_def, h->>1, h->>2);
      v_cnt := v_cnt + 1;
    end loop;
    execute v_def;
    v_back := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    for h in select x from jsonb_array_elements(v_hunks) with ordinality t(x, i) where x->>0 = v_fn order by i desc loop
      if (length(v_back) - length(replace(v_back, h->>2, ''))) / length(h->>2) <> 1 then
        raise exception '0433 self-assert FAIL: a new hunk is not in % once: %', v_fn, left(h->>2, 120);
      end if;
      v_back := replace(v_back, h->>2, h->>1);
    end loop;
    if v_back <> v_pre then
      raise exception '0433 self-assert FAIL: % does not reverse to its pre-image', v_fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = v_fn::regprocedure) <> v_meta then
      raise exception '0433 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', v_fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not (p.oid::regprocedure::text = any(array(select f::regprocedure::text from unnest(v_fns) f)))
         and p.oid not in ('cmd.refusal_figure(numeric)'::regprocedure, 'cmd.refusal_line(text,jsonb)'::regprocedure)) <> v_fn_before then
    raise exception '0433 self-assert FAIL: another function moved';
  end if;

  -- ── 4. THE WORDS IN ROWS: each matched on its exact old words; an owner's own wording is left and named ──
  update public.news_kinds k set en = v.en, ko = v.ko
    from (values
      ('UPDATE',       'Update: {title}', '{title}', '{title}'),
      ('NEW_HARBOUR',  'New harbour: {city}', 'New port: {city}', '새 항구: {city}'),
      ('RELATIONS',    '{a} and {b}: now {stance}', '{a}–{b}: {stance}', '{a}–{b}: {stance}'),
      ('BIG_SALE',     '{company} sold {qty} {good} at {city}: {n}', '{company} sold {qty} {good}: {n} · {city}', '{company} {good} {qty} 판매: {n} · {city}'),
      ('BIG_BUY',      '{company} bought {qty} {good} at {city}: {n}', '{company} bought {qty} {good}: {n} · {city}', '{company} {good} {qty} 구매: {n} · {city}'),
      ('PRICE_SPIKE',  '{good} at {city} {p} in an hour', '{good} {p} · {city}', '{good} {p} · {city}'),
      ('PIRATES',      'Pirates took {n} from {company}', '{company} raided: {n}', '{company} 약탈당함: {n}'),
      ('CAPITAL_GIFT', '{capital} gave {company} {n}', '{capital} → {company}: {n}', '{capital} → {company}: {n}')) v(kind, was, en, ko)
   where k.kind = v.kind and k.en = v.was;
  get diagnostics v_rows = row_count;
  if v_rows <> 8 then
    v_kept := v_kept || format('news_kinds %s of 8 re-worded; ', v_rows);
  end if;

  update public.voyage_event_kinds k set prose = v.prose, prose_fallbacks = coalesce(v.fb, k.prose_fallbacks)
    from (values
      ('BATTLE',        'We hove to and fought, and lost %s hours.', 'Fought: %s hours lost.', null::text[]),
      ('CALM',          'The wind died away. We lay becalmed and lost %s hours.', 'Becalmed: %s hours lost.', null),
      ('CLEAR',         'A quiet watch; nothing to report.', 'Quiet day.', null),
      ('CONSORT',       'We spoke a sail on the other tack and swapped what news we had.', 'Spoke a ship; swapped news.', null),
      ('DERELICT',      'A hull lay low in the water, abandoned. We took what we could off her: %s.', 'Salvaged a wreck: %s.', null),
      ('FAIR_WIND',     'A soldier''s wind all day, and she ran her easting down. We made up %s hours.', 'Fair wind: %s hours gained.', null),
      ('FORCED_HOME',   'The water and the food are gone. We bore up for %s and came in with the hold empty and the hulls hurt.', 'Out of stores: back to %s, hold empty, hulls hurt.', null),
      ('FOUL_WATER',    'The casks were broached and the water in them had turned. We started %s tuns over the side.', 'Water spoiled: %s tuns lost.', null),
      ('LANDFALL',      'We raised %s and hove to. %s', 'Sighted %s. %s', array['the mark', 'Empty sea.']),
      ('NAVY',          '%s', '%s', array['Navy stopped us.']),
      ('PIRATES',       'Sail sighted to windward. %s', 'Pirates. %s', array['They closed.']),
      ('SHOAL_WATER',   'She touched on ground that was on no chart, and came off with %s points off her hull.', 'Aground: hull −%s.', null),
      ('SHORT_RATIONS', 'Stores are low. The crew are on short rations and their wages are up.', 'Stores low: short rations, wages up.', null),
      ('STORM',         'A gale took us on the beam. We ran under bare poles and lost %s points of hull.', 'Gale: hull −%s.', null)) v(code, was, prose, fb)
   where k.code = v.code and k.prose = v.was;
  get diagnostics v_rows = row_count;
  if v_rows <> 14 then
    v_kept := v_kept || format('voyage_event_kinds %s of 14 re-worded; ', v_rows);
  end if;

  -- the six long update titles, in their own rows (append-only: its trigger lifted for this one statement, then put back)
  alter table public.world_news disable trigger world_news_append_only;
  update public.world_news w
     set detail = jsonb_set(jsonb_set(w.detail, '{words,title,en}', to_jsonb(v.en)), '{words,title,ko}', to_jsonb(v.ko))
    from (values
      ('update:0375', 'Attack ships at sea: it costs standing, and the navy answers', 'Attack ships at sea', '해상 선박 공격'),
      ('update:0413', 'A game day now lasts one hour: ships and markets run five times slower', 'A day is one hour', '하루는 한 시간'),
      ('update:0422', 'Navy and pirate ships now sail three times as fast as merchants', 'Navy and pirates 3× faster', '해군·해적선 3배 속도'),
      ('update:0423', 'Busier seas: merchants rest less, more cargo ships sail, the navy patrols', 'Busier seas', '더 붐비는 바다'),
      ('update:0425', 'The navy leaves port; cargo ships carry smaller loads on more ships', 'Navy at sea', '해군 출항'),
      ('update:0426', 'Merchants leave poor harbours; cargo ships carry smaller loads on more ships', 'Merchants leave poor ports', '상선이 가난한 항구를 떠남')) v(key, was, en, ko)
   where w.key = v.key and w.kind = 'UPDATE' and w.detail->'words'->'title'->>'en' = v.was;
  get diagnostics v_rows = row_count;
  alter table public.world_news enable trigger world_news_append_only;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.world_news'::regclass and t.tgname = 'world_news_append_only' and t.tgenabled = 'O') then
    raise exception '0433 self-assert FAIL: the append-only trigger of world_news is not back on';
  end if;
  v_kept := v_kept || format('%s update title(s) shortened', v_rows);

  -- ── 5. THE NEWS (0347's law) ──
  perform public.news_update('0433', 'Shorter words', '더 짧은 문구');

  -- ── 6. THE PROBE: pure calls, no row written ──
  if cmd.refusal('E_INSUFFICIENT_FUNDS', 'a long sentence', cmd.figures(5000, 9000, 'ducats'))->>'sentence' <> 'Money 5,000 / 9,000'
     or cmd.refusal('E_ENDURANCE', 'a long sentence', cmd.figures(2.9, 33, 'days'))->>'sentence' <> 'Supplies 2.9 / 33 days'
     or cmd.refusal('E_HOLD_FULL', 'more Pepper than the hold will take', cmd.figures(120, 150, 't'))->>'sentence' <> 'Hold 120 / 150 t'
     or cmd.refusal('E_CREW_SHORT', 'a long sentence', cmd.figures(6, 8, 'crew'))->>'sentence' <> 'Crew 6 / 8'
     or cmd.refusal('E_OUT_OF_REACH', 'a long sentence', cmd.figures(300, 1450, 'miles'))->>'sentence' <> 'Range 300 / 1,450 miles'
     or cmd.refusal('E_NOT_DOCKED', '  Gaivota is not in port ')->>'sentence' <> 'Gaivota is not in port'
     or cmd.refusal('E_NOT_DOCKED', 'Gaivota is not in port', cmd.figures(1, 2, 'ducats'))->>'code' <> 'E_NOT_DOCKED'
     or cmd.refusal('E_X', 'x', cmd.figures(1, 2, 'ducats'))->'figures' <> cmd.figures(1, 2, 'ducats') then
    raise exception '0433 self-assert FAIL: a refusal does not say have / need: %', cmd.refusal('E_INSUFFICIENT_FUNDS', 'x', cmd.figures(5000, 9000, 'ducats'));
  end if;
  begin
    perform cmd.refuse('E_HOLD_FULL', 'more Pepper than the hold will take', cmd.figures(1.5, 20000, 't'));
  exception when others then
    v_s := sqlerrm;
    v_r := cmd.refusal_caught(sqlerrm, '{"have": 1.5, "need": 20000, "unit": "t"}');
  end;
  if v_s is distinct from 'E_HOLD_FULL: Hold 1.5 / 20,000 t' or v_r->>'sentence' <> 'Hold 1.5 / 20,000 t' or v_r->>'code' <> 'E_HOLD_FULL' then
    raise exception '0433 self-assert FAIL: a raised refusal is not have / need: % / %', v_s, v_r;
  end if;
  select zz.code, zz.name, zz.title_min, zz.wave_min into z from public.sea_zones zz where zz.title_min > 1 order by zz.ord limit 1;
  if z.code is not null then
    v_r := public.sea_refusal(1, greatest(z.wave_min, 0) + 1, array[z.code]);
    if v_r->>'sentence' <> format('%s closed. Title 1 / %s.', z.name, z.title_min) or v_r->>'code' <> 'E_SEA_CLOSED' or v_r->'figures'->>'zone' <> z.code then
      raise exception '0433 self-assert FAIL: a closed sea is not have / need: %', v_r;
    end if;
  end if;
  v_s := voyage.fight_round_line('{"range": "CLOSE", "a": {"can": 2, "fired": 5, "hits": 3, "struck": []}, "b": {"fired": 2, "hits": 1, "raw": 10, "dealt": 10, "left": 60}}'::jsonb
                                 || jsonb_build_object('a', jsonb_build_object('can', 2, 'fired', 5, 'hits', 3, 'struck', '[]'::jsonb),
                                                       'b', jsonb_build_object('fired', 2, 'hits', 1, 'raw', 10, 'dealt', 10, 'left', 60)),
                                 2, 'YOU', '[]'::jsonb, 100, 'raiders');
  if v_s is distinct from 'Round 2 · close · we hit 3 of 5; they hit . Raiders −40%.' and v_s not like 'Round 2 · close · we hit 3 of 5; they hit%Raiders −40%.' then
    raise exception '0433 self-assert FAIL: a round is not told short: %', v_s;
  end if;
  if public.battle_words('{"outcome": "DRIVEN_OFF", "rounds_fought": 0}'::jsonb, '[]'::jsonb)->'lines'->>0 <> 'Thrown back.'
     or voyage.report_line(3, 'STORM', '{"hull_lost": 12}'::jsonb) <> 'Day 3. Gale: hull −12.'
     or (v_kept not like '%voyage_event_kinds%' and voyage.report_line(4, 'CLEAR', '{"crew_lost": 2}'::jsonb) <> 'Day 4. Quiet day. Crew −2.') then
    raise exception '0433 self-assert FAIL: a report is not told short';
  end if;
  if position('''level'', (public.player_progress(v_id)' in pg_get_functiondef('world.house_room()'::regprocedure)) = 0 then
    raise exception '0433 self-assert FAIL: the room does not serve its level';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0433 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0433 self-assert ok: THE SERVER SAYS HAVE AND NEED. % hunks over % bodies (cmd.refusal, battle_words, fight_round_line, raid_report, report_line, best_sales, house_room), each once and reversing; grants and volatility unmoved; no other function moved; cmd.refusal_line + cmd.refusal_figure (server-only). Probe: Money 5,000 / 9,000; Supplies 2.9 / 33 days; Hold 1.5 / 20,000 t raised and caught; a sea closed with Title 1 / n; a round, a battle and a day told short. Rows: %. % ms.',
    v_cnt, array_length(v_fns, 1), v_kept, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
