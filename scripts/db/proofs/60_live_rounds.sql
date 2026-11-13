-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 60 — A BATTLE IS FOUGHT ROUND BY ROUND  (migration 0357, slice C3 of docs/COMBAT_LOG.md sections 3 and 5.2, owner row 315)
--
--   The migration's self-assert reads 0320's matrix under clock bounds and plays one probe battle that it does not close. Here time is free and the game is real: the whole matrix
--   every time; a real company's gunned fleet, a real cargo ship at sea, the REAL attack (public.attack_for), the REAL job (public.tick_battles), the REAL close
--   (public.battle_resolve, public.attack_close), the REAL door (cmd.battle_stance) and read (world.battle), the REAL hold on a real voyage. OLD AGAINST NEW is not taken on
--   trust: the migration's own 23 hunks are held below (written by scripts/ops/harness/live-rounds/gen-checks.mjs --proof-write from the migration's text), each NEW text is found
--   once in the live body and reversed, and the rebuild is judged as a round trip on the live body (no fixed digest: a later file may re-cut these bodies, as proof 56 learned).
--   A battle's seed is its id, so every scene pins the id it opens (the column's default, inside a subtransaction) and is rolled back; the same battle is then played several ways.
--   Everything rolls back with proof.mjs's transaction; every switch this proof needs it writes here.
--
-- @pass ENGINE_PARITY_FULL  0320's whole matrix, 1,120 fights: the old engine (rebuilt from the live one by the hunks) against the new, as text, with no option, the sizing-up, a_order FLEE, a_order PAY and a round limit; and b_order FIGHT with every hull from 1, said aloud, is the old answer
-- @pass PREFIX_FULL         the whole matrix with BOTH sides holding a list of stances: every round limit 1 to 7 on twelve days of it is the first rows of the full run, as text; the side that closes running fires nothing and her chance is the rule's; a called ship fights only from her round
-- @pass DARK_PARITY         attack_enabled false: a merchant's and a company's ordinary voyage (quiet days, a calm, raids), old bodies against new: every day, the report, the ledger, the purse and the hulls byte for byte; the job, the closer, the open and the attack answer as they did; the doors refuse
-- @pass NO_PVP              lit: public.battle_open (both kinds), public.attack_for and cmd.attack refuse a company's fleet as a target, and no battle row is written
-- @pass ROUNDS_TICK_LATE    one battle played tick by tick and by one late call: the same rows, the same result, the same hulls, hands, purse, report and ledger; the log grows one row a tick; each row is the re-run's; with nobody choosing it ends as the one call of the old bodies did
-- @pass STANCE_CHANGE       Flee set before round 3: rounds 1 and 2 are the rows of the battle fought through; from round 3 her guns are silent and each row carries her chance; tick by tick and late agree
-- @pass BREAK_OFF           her Flee gets her away: BROKEN_OFF, the battle ends at that round's instant, no loot and no purse moved, the beaten row of hands, the report says so, both fleets are free, and the target's hold ends with the battle
-- @pass FLEE_CAUGHT         her Flee never gets her away: not a shot of hers in any round, and she is boarded or broken as the fight says; the status is RESOLVED
-- @pass CALLED_FROM         a called ship joins at the first round she is there for (`from`), one that comes up after the last round is there for the boarding, one that never comes is never on the sheet; the rows are the re-run's
-- @pass STANCE_DOOR         cmd.battle_stance advances first, keeps the stance from the next round, writes nothing for the stance she holds; each refusal by its code; a battle that is over stays closed; anon cannot call; both doors registered
-- @pass BATTLE_READ         world.battle: before the first round, between rounds (no ending, no boarding told early), and closed (the end, the loot, the hands); another company reads nothing
-- @pass STANDING_ORDER      a defender's opening stance is her standing order (0353), a ship of the world's is FIGHT, and dark it is FIGHT; on a sheet this proof writes (no door opens one), the rounds are fought under it
-- @pass HOLD_FREE           a held voyage and its unheld twin settle the same days, kinds, stores and wages, and the arrival moves by exactly the hold; under the old bodies the same hold costs about 7 more days; a hold cut short moves the arrival by what was served; a fair wind after a hold
-- @pass CLOSED_ONCE         a retry of the job, the closer and the door closes nothing twice: one report, one ledger row, no new round
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

create temp table hunks_60 (fn text, n int, old text, new text) on commit drop;
insert into hunks_60 (fn, n, old, new) values
-- hunks:begin
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 1, $h$  c_they   numeric := 0;
  v_ratio  numeric;
$h$, $h$  c_they   numeric := 0;
  -- 0357: the stance of the side that closes (p_opts.b_order: FIGHT or FLEE, one word or a list with a word a round whose last stands for the rest), and a hull's `from`: the first round a
  -- called ship of the side set upon is on the sheet (absent: 1). Absent: the fight as it was.
  v_bord   jsonb := p_opts->'b_order';
  v_bo     text;
  v_bfled  boolean := false;
  v_bpf    numeric;
  a_from   int[] := '{}';
  v_late   boolean := false;
  v_ratio  numeric;
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 2, $h$    a_shots[i] := greatest(1, coalesce((x->>'shots')::int, 1));
    v_sa       := greatest(v_sa, coalesce((x->>'sighting')::numeric, 0));
$h$, $h$    a_shots[i] := greatest(1, coalesce((x->>'shots')::int, 1));
    a_from[i]  := greatest(1, coalesce((x->>'from')::int, 1));
    if a_from[i] > 1 then   -- 0357: a called ship: she is not seen, not struck and not counted before her round
      a_hull[i] := 0;
      v_late := true;
      continue;
    end if;
    v_sa       := greatest(v_sa, coalesce((x->>'sighting')::numeric, 0));
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 3, $h$    v_fought := g;
    v_range := v_ranges -> (g - 1) ->> 0;
$h$, $h$    v_fought := g;
    -- 0357: a called ship comes on the sheet at her round, whole; and the stance of the side that closes for this round
    if v_late then
      for i in 1 .. v_na loop
        if a_from[i] > 1 and a_from[i] = g then   -- only a ship that was called: a hull of round 1 is counted where the sides are read
          a_hull[i] := a_hull0[i];
          v_h0a := v_h0a + a_hull0[i];
          v_sa := greatest(v_sa, coalesce((p_a -> (i - 1) ->> 'sighting')::numeric, 0));
          if a_att[i] > 0 and a_acc[i] > 0 then
            v_ba := greatest(v_ba, a_reach[i]);
          end if;
        end if;
      end loop;
    end if;
    v_bo := case jsonb_typeof(v_bord) when 'string' then v_bord #>> '{}'
                                      when 'array' then coalesce(v_bord ->> (g - 1), v_bord ->> -1) end;
    v_range := v_ranges -> (g - 1) ->> 0;
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 4, $h$v_range, v_mult, g = 1 and v_first = 'A', v_k,
$h$, $h$v_range, v_mult, (g = 1 and v_first = 'A') or coalesce(v_bo = 'FLEE', false), v_k,   -- 0357: a side that runs fires nothing
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 5, $h$    if v_h0b - v_lb >= v_break * v_h0b then
$h$, $h$    -- 0357: THE SIDE THAT CLOSES RUNS (docs/WORLD_POWERS.md 5.2, break off). She took this round's fire; now she rolls on her own stream, by the flee rule with the lead turned round.
    -- Away is a break-off said aloud (`b_fled`): no boarding. Not away, the round goes on as it would: her losses may still break her, and the side set upon may still run.
    if v_bo = 'FLEE' then
      v_bpf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sb - v_sa) * public.wc_num('fight_evade_per_sighting')));
      v_rows := jsonb_set(v_rows, array[(g - 1)::text, 'b_flee'], to_jsonb(round(v_bpf, 4)));
      if voyage.rng(p_seed, p_round, format('fight:%s:flee:b', g)) < v_bpf then
        v_bfled := true; v_broke := true;
        v_outcome := case when v_h0a - v_la = 0 then 'EVADED' else 'DRIVEN_OFF' end;
        exit;
      end if;
    end if;
    if v_h0b - v_lb >= v_break * v_h0b then
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 6, $h$    for i in 1 .. v_na loop
      c_you := c_you + a_crew[i];
$h$, $h$    for i in 1 .. v_na loop
      continue when a_from[i] > v_fought + 1;   -- 0357: a called ship that never came up boards nobody
      if a_from[i] > v_fought then a_hull[i] := a_hull0[i]; end if;   -- 0357: one that came up after the last round is there for the boarding, whole
      c_you := c_you + a_crew[i];
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 7, $h$from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k]), '{}'::jsonb),
$h$, $h$from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k] and a_from[k] <= v_fought), '{}'::jsonb),   -- 0357: a ship that never came up lost nothing
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 8, $h$  return jsonb_build_object(
    'outcome', v_outcome,$h$, $h$  return case when v_bfled then '{"b_fled": true}'::jsonb else '{}'::jsonb end ||   -- 0357: said only when true
    jsonb_build_object(
    'outcome', v_outcome,$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1, $h$  v_until := p_now + make_interval(secs => public.wc_num('battle_seconds')::double precision);
$h$, $h$  -- 0357: an ATTACK is fought round by round: battle_round_seconds a round and one more for the boarding, and never longer than battle_seconds. A probe keeps battle_seconds.
  v_until := p_now + make_interval(secs => (case when p_kind = 'ATTACK' then least(public.wc_num('battle_seconds'), public.wc_num('battle_round_seconds') * (jsonb_array_length(public.wc('fight_ranges')) + 1))
                                                 else public.wc_num('battle_seconds') end)::double precision);
$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 2, $h$    perform public.navy_call(v_id, p_defender, v_until, p_now);
$h$, $h$    perform public.navy_call(v_id, p_defender, v_until, p_now);
    perform public.battle_sheet_freeze(v_id, p_now);   -- 0357: both sides as they are, once; the round clock; a probe has no sheet and is one call at its end, as it was
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1, $h$  select * into b from public.battles where id = p_battle for update;
$h$, $h$  select * into b from public.battles where id = p_battle for update;
  if b.sheet is not null and b.status = 'FIGHTING' then   -- 0357: live rounds: every round due is fought and logged first; a fight that ended in a round brings resolves_at in
    perform public.battle_advance(p_battle, p_now);
    select * into b from public.battles where id = p_battle;
  end if;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 2, $h$  v_f := case when jsonb_array_length(v_a) = 0 or jsonb_array_length(v_b) = 0 then jsonb_build_object('outcome', 'NO_FIGHT')
$h$, $h$  v_f := case when b.sheet is not null then public.battle_fight(p_battle, null)   -- 0357: the sheet's own fight under the stances kept: its rounds are the rows already logged
              when jsonb_array_length(v_a) = 0 or jsonb_array_length(v_b) = 0 then jsonb_build_object('outcome', 'NO_FIGHT')
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 3, $h$  update public.battles set status = 'RESOLVED', result = v_f where id = p_battle;
$h$, $h$  -- 0357: BROKEN_OFF has its writer: the side that attacked fled, and got away (docs/WORLD_POWERS.md 5.2)
  update public.battles set status = case when coalesce((v_f->>'b_fled')::boolean, false) then 'BROKEN_OFF' else 'RESOLVED' end, result = v_f where id = p_battle;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 4, $h$     where f.id = s.fleet_id;
    if s.status = 'IN_BATTLE' then
$h$, $h$     where f.id = s.fleet_id;
    if b.sheet is not null and s.status = 'SAILING' then   -- 0357: a battle that ended before its clock ends her hold with it
      perform voyage.hold_cut(s.fleet_id, b.started_at, b.resolves_at);
    end if;
    if s.status = 'IN_BATTLE' then
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 5, $h$      v_rep := public.battle_words(v_f, v_b);
$h$, $h$      v_rep := public.battle_words(v_f || case when b.sheet is not null then jsonb_build_object('sheet', b.sheet) else '{}'::jsonb end, v_b);   -- 0357: with a sheet the report carries the log
$h$),
  ('public.tick_battles(timestamp with time zone)', 1, $h$            where b.status = 'FIGHTING' and b.resolves_at <= p_now
            order by b.resolves_at, b.id limit 50
$h$, $h$            where b.status = 'FIGHTING' and coalesce(b.next_round_at, b.resolves_at) <= p_now   -- 0357: what is due is the next round (battles_round_due); a battle with no sheet is due at its end, as it was
            order by coalesce(b.next_round_at, b.resolves_at), b.id limit 50
$h$),
  ('public.battle_words(jsonb,jsonb)', 1, $h$jsonb_build_object('range', x->'range', 'a', x->'b', 'b', x->'a'), g, v_first, p_ships, v_hull0, 'enemy');
$h$, $h$jsonb_build_object('range', x->'range', 'a', x->'b', 'b', x->'a')
                                                      || case when x ? 'b_flee' then jsonb_build_object('flee', x->'b_flee') else '{}'::jsonb end,   -- 0357: a round she ran
                                                    g, v_first, p_ships, v_hull0, 'enemy');
$h$),
  ('public.battle_words(jsonb,jsonb)', 2, $h$jsonb_build_object('line', 0, 'rounds', to_jsonb(v_rounds))));
$h$, $h$jsonb_build_object('line', 0, 'rounds', to_jsonb(v_rounds))
    -- 0357: a sheet's battle carries its log, from her deck (public.battle_log), as a raid's entry does (0353)
    || case when p_fight ? 'sheet' then jsonb_build_object('log', public.battle_log(p_fight->'sheet', p_fight - 'sheet', 'ATTACKER')) else '{}'::jsonb end));
$h$),
  ('voyage.hold(uuid,timestamp with time zone,timestamp with time zone)', 1, $h$'held_from', p_now, 'held_until', p_until), p_now
$h$, $h$'held_from', p_now, 'held_until', p_until, 'free', true), p_now   -- 0357: a battle's hold burns nothing (voyage.hold_free_hours)
$h$),
  ('voyage.total_days(uuid)', 1, $h$                       + (select delay_hours from public.voyages where id = p_voyage)) / 24)::int)
$h$, $h$                       + greatest(0, (select delay_hours from public.voyages where id = p_voyage) - voyage.hold_free_hours(p_voyage))) / 24)::int)   -- 0357: a free hold is no day
$h$),
  ('voyage.days_complete(uuid,timestamp with time zone)', 1, $h$                             + (select delay_hours from public.voyages where id = p_voyage)) / 24)::int) + 1;
$h$, $h$                             + greatest(0, (select delay_hours from public.voyages where id = p_voyage) - voyage.hold_free_hours(p_voyage))) / 24)::int) + 1;   -- 0357: a free hold is no day
$h$),
  ('voyage.arrival_at(uuid,timestamp with time zone)', 1, $h$    exit when d > greatest(1, ceil((v_sim + v_delay) / 24)::int);
$h$, $h$    exit when d > greatest(1, ceil((v_sim + greatest(0, v_delay - voyage.hold_free_hours(v.id))) / 24)::int);   -- 0357: a free hold is no day, as voyage.total_days counts
$h$),
  ('public.client_rpc_entry_points()', 1, $h$      ('cmd',         'preview_attack',        'uuid, uuid'),
$h$, $h$      ('cmd',         'preview_attack',        'uuid, uuid'),
      -- 0357: a battle fought round by round: her stance (Fight, Flee), and the read the battle card polls.
      ('cmd',         'battle_stance',         'uuid, text'),
      ('world',       'battle',                'uuid'),
$h$)
-- hunks:end
;

-- the bodies as they are now, by digest: what a rolled-back rebuild must come back to
create temp table live_60 on commit drop as
select f.fn, md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5
  from (select distinct x.fn from hunks_60 x where x.fn <> 'public.client_rpc_entry_points()') f;

-- THE OLD BODIES, rebuilt from the live ones, whatever a later migration has made of them: each hunk's NEW text occurs exactly once in the live body and is reversed; each OLD text then
-- occurs exactly once; putting the NEW texts back gives the live body again, to the character. The registry is not rebuilt (no battle reads it; every later slice adds rows to it).
-- Called only inside a subtransaction that is rolled back.
create function pg_temp.to_old_60() returns void language plpgsql as $b$
declare
  f      record;
  h      record;
  v_live text;
  v_def  text;
  v_back text;
begin
  for f in select l.fn from live_60 l order by l.fn loop
    v_live := replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '');
    v_def := v_live;
    for h in select * from hunks_60 x where x.fn = f.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'PROOF 60 FAIL: hunk % of % is not in the live body exactly once: a later migration re-cut the very text 0357 added, and must amend this proof''s copy of the hunk', h.n, f.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    v_back := v_def;
    for h in select * from hunks_60 x where x.fn = f.fn order by x.n loop
      if (length(v_back) - length(replace(v_back, h.old, ''))) / length(h.old) <> 1 then
        raise exception 'PROOF 60 FAIL: hunk % of %: its OLD text is not in the rebuilt body exactly once', h.n, f.fn;
      end if;
      v_back := replace(v_back, h.old, h.new);
    end loop;
    if v_back is distinct from v_live or v_def = v_live then
      raise exception 'PROOF 60 FAIL: the rebuilt % does not come back to the live body when 0357''s hunks are put back (or nothing was reversed)', f.fn;
    end if;
    execute v_def;
  end loop;
  if exists (select 1 from live_60 l where md5(replace(pg_get_functiondef(l.fn::regprocedure), E'\r', '')) = l.md5) then
    raise exception 'PROOF 60 FAIL: the old bodies were not rebuilt';
  end if;
end
$b$;

create function pg_temp.live_60_ok() returns boolean language sql as $b$
  select not exists (select 1 from live_60 l where md5(replace(pg_get_functiondef(l.fn::regprocedure), E'\r', '')) is distinct from l.md5)
$b$;

-- ══ THE WHOLE MATRIX, EVERY TIME (ENGINE_PARITY_FULL, PREFIX_FULL): pure fights on 0320's probe hulls; no row of the game is read or written ══
do $p$
declare
  c_seed constant uuid := '00000000-0357-4000-8000-0000000000ff';
  v_carlat jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a1', 'name', 'Probe Carlat',
                      'tier', 1, 'hull', 550, 'maxd', 550, 'crew', 12, 'attack', 55, 'accuracy', 40, 'reach', 25, 'armour', 12,
                      'sighting', 10, 'gear', jsonb_build_array('Boarding Gear')));
  v_barca  jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a2', 'name', 'Probe Barca',
                      'tier', 1, 'hull', 400, 'maxd', 400, 'crew', 8, 'attack', 35, 'accuracy', 0, 'reach', 0, 'armour', 5,
                      'sighting', 8));
  v_three  jsonb := jsonb_build_array(
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a3', 'name', 'Probe Nau', 'tier', 3, 'hull', 1500, 'maxd', 1800, 'crew', 90, 'attack', 180,
                        'accuracy', 55, 'reach', 60, 'armour', 30, 'sighting', 40, 'boarder_pct', 0.12, 'boarder', 'Probe Boarder', 'gunner', 'Probe Gunner', 'gear', jsonb_build_array('Swivel Guns', 'Boarding Gear')),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a4', 'name', 'Probe Galion', 'tier', 4, 'hull', 2400, 'maxd', 2400, 'crew', 140, 'attack', 260,
                        'accuracy', 48, 'reach', 40, 'armour', 44, 'sighting', 22),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a5', 'name', 'Probe Wreck', 'tier', 1, 'hull', 0, 'maxd', 500, 'crew', 6, 'attack', 40,
                        'accuracy', 40, 'reach', 90, 'armour', 0, 'sighting', 5));
  v_two    jsonb := jsonb_build_array(
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000b1', 'name', 'Probe One', 'tier', 2, 'hull', 9000, 'maxd', 9000, 'crew', 40, 'attack', 120,
                        'accuracy', 60, 'reach', 50, 'armour', 20, 'sighting', 22),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000b2', 'name', 'Probe Two', 'tier', 2, 'hull', 9000, 'maxd', 9000, 'crew', 40, 'attack', 120,
                        'accuracy', 60, 'reach', 50, 'armour', 20, 'sighting', 22));
  v_x     record;
  v_o     jsonb;
  v_b     jsonb;
  v_g     jsonb;
  v_f     jsonb;
  v_full  jsonb;
  v_cut   jsonb;
  v_w     int;
  v_m     int;
  v_pairs int := 0;
  v_bad   int := 0;
  v_ex    text;
  v_kinds jsonb := '{}'::jsonb;
  v_neutral int := 0;
  v_pf    numeric;
  v_bfled int := 0;
  v_bcaught int := 0;
  v_same  int := 0;
  v_pre   int := 0;
  v_open  int := 0;
  v_from  int := 0;
  v_board int := 0;
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
begin
  create temp table mx_60 on commit drop as
  with rh as materialized (select r.r, voyage.raider_hulls(r.r) as b from (values (6.0), (12.0), (18.0), (24.0), (10.0), (60.0), (120.0)) r(r))
  select row_number() over (order by m.d, m.k)::int as i, m.*
    from (select s.k * 10 + r.k as k, s.ships as a, (select rh.b from rh where rh.r = r.r) as b, s.esc, r.r, d
            from (values (1, v_carlat, 11.74::numeric), (2, v_barca, 6.66::numeric)) s(k, ships, esc)
           cross join (values (1, 6.0), (2, 12.0), (3, 18.0), (4, 24.0)) r(k, r)
           cross join generate_series(1, 120) d
          union all
          select 30 + r.k, v_three, (select rh.b from rh where rh.r = r.r), 30.5::numeric, r.r, d
            from (values (1, 10.0), (2, 24.0), (3, 60.0), (4, 120.0)) r(k, r)
           cross join generate_series(1, 30) d
          union all
          select 40, v_three, v_two, null::numeric, null::numeric, d from generate_series(1, 40) d) m;
  if (select count(*) from mx_60) is distinct from 1120 then
    raise exception 'PROOF 60 FAIL: the matrix is % fights, not 1120', (select count(*) from mx_60);
  end if;

  -- the new engine's answers, kept as text: five ways a fight (w 1 no option, 2 the sizing-up, 3 a_order FLEE, 4 a_order PAY, 5 a round limit that turns with the fight)
  create temp table new_60 (i int, w int, o jsonb, t text, primary key (i, w)) on commit drop;
  for v_x in select * from mx_60 m order by m.i loop
    v_b := case when v_x.r is null then '{}'::jsonb else jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r) end;
    v_w := 0;
    foreach v_o in array array['{}'::jsonb, v_b, v_b || '{"a_order": "FLEE"}'::jsonb, v_b || '{"a_order": "PAY"}'::jsonb, v_b || jsonb_build_object('rounds', 1 + (v_x.i % 6))] loop
      v_w := v_w + 1;
      v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_o);
      insert into new_60 values (v_x.i, v_w, v_o, v_f::text);
      if v_w = 2 then
        v_kinds := jsonb_set(v_kinds, array[v_f ->> 'outcome'], 'true'::jsonb);
        -- the new options, said aloud and neutral, are the same answer (and so the old one, below)
        v_g := public.fight_sides(c_seed, v_x.d, (select jsonb_agg(e.h || '{"from": 1}'::jsonb order by e.o) from jsonb_array_elements(v_x.a) with ordinality e(h, o)), v_x.b, v_o || '{"b_order": "FIGHT"}'::jsonb);
        v_neutral := v_neutral + 1;
        if v_g::text is distinct from v_f::text then
          raise exception 'PROOF 60 FAIL: b_order FIGHT and from 1, said aloud, changed a fight (fight %): % against %', v_x.i, v_f, v_g;
        end if;
      end if;
    end loop;
  end loop;

  -- the old engine, rebuilt, against every one of them
  begin
    perform pg_temp.to_old_60();
    for v_x in select m.*, n.w, n.o, n.t from mx_60 m join new_60 n on n.i = m.i order by m.i, n.w loop
      v_pairs := v_pairs + 1;
      v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_x.o);
      if v_f::text is distinct from v_x.t then
        v_bad := v_bad + 1;
        v_ex := coalesce(v_ex, format('fight %s way %s: %s against %s', v_x.i, v_x.w, v_f, v_x.t));
      end if;
    end loop;
    raise exception using errcode = 'ZX360', message = 'OLD_ROLLBACK_60';
  exception when sqlstate 'ZX360' then
    null;
  end;
  if v_pairs is distinct from 5600 or v_bad is distinct from 0 or v_neutral is distinct from 1120 or not coalesce(v_kinds ?& array['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED'], false)
     or not pg_temp.live_60_ok() then
    raise exception 'PROOF 60 FAIL: ENGINE PARITY on the whole matrix: % pair(s) of 5600, % changed, % neutral of 1120, endings %, the old engine outlived its rollback: %; first: %',
      v_pairs, v_bad, v_neutral, v_kinds, not pg_temp.live_60_ok(), v_ex;
  end if;
  raise notice 'PASS: ENGINE_PARITY_FULL — 0320''s whole matrix, 1,120 fights: 5,600 pairs (no option, the sizing-up, a_order FLEE, a_order PAY, a round limit), the old engine (rebuilt from the live one by the hunks) against the new, all equal as text; every ending met; b_order FIGHT with every hull from 1, said aloud, is the same answer on all 1,120';

  -- THE STANCES, on the whole matrix (the new engine)
  for v_x in select * from mx_60 m order by m.i loop
    v_b := case when v_x.r is null then '{}'::jsonb else jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r) end;
    v_full := (select n.t::jsonb from new_60 n where n.i = v_x.i and n.w = 2);
    -- the side that closes runs from the first round
    v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_b || '{"b_order": "FLEE"}'::jsonb);
    if (v_full ->> 'stood_off')::boolean or (v_full ->> 'slipped')::boolean then
      v_same := v_same + 1;
      if v_f::text is distinct from v_full::text then
        raise exception 'PROOF 60 FAIL: b_order FLEE changed a day that never came to a round (fight %): %', v_x.i, v_f;
      end if;
    else
      v_pf := round(public.fight_flee_chance((select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_x.b) e)
                                             - (select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_x.a) e)), 4);
      if v_f -> 'hull_lost' -> 'a' is distinct from '{}'::jsonb or (v_f -> 'hits' ->> 'b')::int is distinct from 0 or jsonb_array_length(v_f -> 'rounds') is distinct from (v_f ->> 'rounds_fought')::int
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e where (e -> 'b' ->> 'fired')::int is distinct from 0 or (e ->> 'b_flee')::numeric is distinct from v_pf) then
        raise exception 'PROOF 60 FAIL: a side that closes and runs fired, or a round''s b_flee is not the rule''s % (fight %): %', v_pf, v_x.i, v_f;
      end if;
      if coalesce((v_f ->> 'b_fled')::boolean, false) then
        v_bfled := v_bfled + 1;
        if (v_f ->> 'broke_off')::boolean is not true or v_f -> 'board' is distinct from 'null'::jsonb or coalesce(v_f ->> 'outcome', '') not in ('EVADED', 'DRIVEN_OFF') then
          raise exception 'PROOF 60 FAIL: a break-off that got away is not broke_off with no boarding (fight %): %', v_x.i, v_f;
        end if;
      else
        v_bcaught := v_bcaught + 1;
        if v_f ? 'b_fled' or (not (v_f ->> 'broke_off')::boolean and (jsonb_typeof(v_f -> 'board') is distinct from 'object' or (v_f ->> 'rounds_fought')::int is distinct from v_n)) then
          raise exception 'PROOF 60 FAIL: a side that ran and never got away was neither broken nor boarded after every round (fight %): %', v_x.i, v_f;
        end if;
      end if;
    end if;
    -- the prefix: both sides hold a list a round, and every limit 1 to 7 is the first rows of the full run (twelve days of the matrix)
    if v_x.d <= 12 then
      v_g := v_b || jsonb_build_object('a_order', case v_x.i % 3 when 0 then '["FIGHT", "FLEE", "FLEE", "FIGHT"]'::jsonb when 1 then '["FLEE", "FIGHT"]'::jsonb else '["FIGHT"]'::jsonb end,
                                       'b_order', case v_x.i % 4 when 0 then '["FIGHT", "FIGHT", "FLEE"]'::jsonb when 1 then '["FLEE", "FIGHT", "FIGHT", "FLEE"]'::jsonb when 2 then '["FIGHT"]'::jsonb else '["FIGHT", "FLEE"]'::jsonb end);
      v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_g);
      for v_m in 1 .. 7 loop
        v_pre := v_pre + 1;
        v_cut := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_g || jsonb_build_object('rounds', v_m));
        if (v_f ->> 'rounds_fought')::int > v_m then
          v_open := v_open + 1;
          if (v_cut ->> 'open')::boolean is not true or v_cut -> 'outcome' is distinct from 'null'::jsonb or v_cut -> 'board' is distinct from 'null'::jsonb or (v_cut ->> 'rounds_fought')::int is distinct from v_m
             or (v_cut -> 'rounds')::text is distinct from (select jsonb_agg(e order by o) from jsonb_array_elements(v_f -> 'rounds') with ordinality q(e, o) where o <= v_m)::text then
            raise exception 'PROOF 60 FAIL: THE PREFIX: a run to round % is not the first rows of the full run, left open (fight %): % against %', v_m, v_x.i, v_cut, v_f;
          end if;
        elsif v_cut::text is distinct from v_f::text then
          raise exception 'PROOF 60 FAIL: THE PREFIX: a round limit the fight never reached changed it (limit %, fight %): % against %', v_m, v_x.i, v_cut, v_f;
        end if;
      end loop;
    end if;
    -- a called ship, on the fights of real hulls: from round 3; from the boarding (the rounds + 1); never
    if v_x.r is null then
      v_from := v_from + 1;
      v_f := public.fight_sides(c_seed, v_x.d, jsonb_set(v_x.a, '{1,from}', '3'::jsonb), v_x.b, '{}'::jsonb);
      if exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e, jsonb_array_elements(e -> 'a' -> 'struck') st where (e ->> 'round')::int < 3 and (st ->> 0)::int = 2)
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e where (e ->> 'round')::int < 3 and (e -> 'a' ->> 'can')::int > 1)
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e where (e ->> 'round')::int = 3 and (e -> 'a' ->> 'left')::numeric + (e -> 'b' ->> 'dealt')::numeric < (v_x.a -> 1 ->> 'hull')::numeric - 0.01) then
        raise exception 'PROOF 60 FAIL: a called ship fought before her round, or not from it (fight %): %', v_x.i, v_f;
      end if;
      -- the side's starting hull is each hull once: those there from round 1, and she from round 3 if the fight came to it (it counted round 1's hulls twice once)
      if (v_f -> 'hull' ->> 'a_start')::numeric is distinct from
           (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_x.a) with ordinality q(e, o) where o <> 2 or (v_f ->> 'rounds_fought')::int >= 3) then
        raise exception 'PROOF 60 FAIL: with a called ship the side''s starting hull is not each hull once (fight %): %', v_x.i, v_f -> 'hull';
      end if;
      v_g := public.fight_sides(c_seed, v_x.d, jsonb_set(v_x.a, '{1,from}', to_jsonb(v_n + 1)), v_x.b, '{}'::jsonb);
      v_cut := public.fight_sides(c_seed, v_x.d, jsonb_set(v_x.a, '{1,from}', '99'::jsonb), v_x.b, '{}'::jsonb);
      if v_cut -> 'hull_lost' -> 'a' ? (v_x.a -> 1 ->> 'id') or v_g -> 'hull_lost' -> 'a' ? (v_x.a -> 1 ->> 'id')
         or (v_g -> 'rounds')::text is distinct from (v_cut -> 'rounds')::text then
        raise exception 'PROOF 60 FAIL: a ship that came up for the boarding, or never, was struck or changed a round (fight %)', v_x.i;
      end if;
      if jsonb_typeof(v_cut -> 'board') = 'object' then
        v_board := v_board + 1;
        if (v_cut -> 'board' ->> 'a_crew')::numeric is distinct from (v_x.a -> 0 ->> 'crew')::numeric + (v_x.a -> 2 ->> 'crew')::numeric
           or (v_g -> 'board' ->> 'a_crew')::numeric is distinct from (v_cut -> 'board' ->> 'a_crew')::numeric + (v_x.a -> 1 ->> 'crew')::numeric
           or (v_g -> 'board' ->> 'a_power')::numeric <= (v_cut -> 'board' ->> 'a_power')::numeric then
          raise exception 'PROOF 60 FAIL: at the boarding a ship that never came counted, or one that came up for it did not (fight %): % against %', v_x.i, v_g -> 'board', v_cut -> 'board';
        end if;
      end if;
    end if;
  end loop;
  if v_bfled + v_bcaught + v_same is distinct from 1120 or v_bfled = 0 or v_bcaught = 0 or v_same = 0 or v_pre = 0 or v_open = 0 or v_open = v_pre or v_from is distinct from 40 or v_board = 0 then
    raise exception 'PROOF 60 FAIL: the stances on the whole matrix: % away, % never away, % unchanged, % round limits, % open, % called, % boarded', v_bfled, v_bcaught, v_same, v_pre, v_open, v_from, v_board;
  end if;
  raise notice 'PASS: PREFIX_FULL — the side that closes running on all 1,120 fights (% away with no boarding, % never away, % that never came to a round unchanged; not a shot of hers, every round''s chance the rule''s); % round limits under both stance lists, % left open, each the first rows of the full run, the rest the full run; a called ship on 40 fights of real hulls: from round 3, at the boarding (% boardings), never',
    v_bfled, v_bcaught, v_same, v_pre, v_open, v_board;
end
$p$;

-- ══ THE GAME ══
do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled', 'npc_refits_enabled', 'navy_enabled', 'pirates_bite', 'raid_orders_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;

  -- THE SEA ON ONE SETTING (proofs 37, 38, 46 and 56 stub it so): '' quiet, else that kind at magnitude 0.5
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_60;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s   text := coalesce(current_setting('byeharu.proof_sea', true), '');
  v_min int := 0;
begin
  -- 'STORM>10': a storm on every day after the tenth, and none before
  if position('>' in v_s) > 0 then
    v_min := split_part(v_s, '>', 2)::int;
    v_s := split_part(v_s, '>', 1);
  end if;
  return query select v_s <> '' and p_day > v_min, case when v_s <> '' and p_day > v_min then v_s end, 0.5::numeric, 1::numeric;
end
$b$
  $f$;

  -- a human company of Portugal, her one fleet in Lisbon, 100 hands, the best guns there are, her hold empty (proof 34's house)
  execute $f$
create function pg_temp.house_60(p_n int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0357-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Ronda ' || p_n, 'PRT', 'LIS', 'Ronda ' || p_n,
                                 (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Ronda ' || p_n, null, false);
  v_f   uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set crew = 100, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 100000, food_t = 100000 where fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- the next cargo ship at sea, not of Portugal, with p_ducats aboard, sailed at p_at and slowed so she is still at sea when the proof looks (proof 34's ship)
  execute $f$
create function pg_temp.ship_60(p_ducats bigint, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
  v_st text;
begin
  select x.* into c
    from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and x.out_load is null and n.code <> 'PRT'
     and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
   order by n.code, x.ord limit 1;
  if c.fleet_id is null then
    raise exception 'PROOF 60 FAIL: no cargo ship left to sail';
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  v_st := public.cargo_ship_step(c.fleet_id, p_at);
  if v_st <> 'SAILED' then
    raise exception 'PROOF 60 FAIL: the cargo ship did not sail: %', v_st;
  end if;
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
  return c.fleet_id;
end
$b$
  $f$;

  -- lay a fleet at anchor at the very point of her target
  execute $f$
create function pg_temp.lie_by(p_fleet uuid, p_target uuid, p_at timestamptz)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;

  -- every great power's ships and circuits
  declare
    v_nat uuid;
    v_n   int;
  begin
    for v_nat in select g.nation_id from public.great_powers g loop
      for v_n in 1 .. 3 loop
        perform public.tick_cargo_ships(now(), v_nat);
      end loop;
    end loop;
  end;
end
$$;

-- a path of p_days voyage-days in one sea (proof 46's and 56's: a day is her speed x 24 to the digit)
create function pg_temp.through_60(p_fleet uuid, p_sea uuid, p_days int) returns jsonb language sql stable as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', voyage.fleet_speed(p_fleet) * 24, 'sea_id', p_sea, 'hazard_mult', 1000))
    from generate_series(1, p_days)
$b$;

-- AN ORDINARY PASSAGE, in a subtransaction that is rolled back: under the old bodies or the new, the voyage id pinned (a raid's seed), the sea said day by day (p_sea: one word a
-- day; '' quiet), settled day by day or once at the eta. p_hold: hold her for that many seconds at the end of day 3 (voyage.hold, as a battle holds her), and p_cut: end that hold
-- after so many seconds (voyage.hold_cut). Answers everything it left.
create function pg_temp.passage_60(p_fleet uuid, p_sea uuid, p_seas text[], p_at timestamptz, p_by_day boolean, p_old boolean, p_hold int default null, p_cut int default null)
returns jsonb language plpgsql as $b$
declare
  c_voy  constant uuid := '00000000-0357-4000-8000-0000000000aa';
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_port uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_ev   uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_led  uuid[] := array(select l.id from public.ledger l where l.player_id = v_pl);
  v_days int := array_length(p_seas, 1);
  v_voy  uuid;
  v_out  jsonb;
  v_t3   timestamptz;
  v_mid  jsonb := '{}'::jsonb;
  d      int;
begin
  begin
    if p_old then
      perform pg_temp.to_old_60();
    end if;
    v_voy := voyage.depart(p_fleet, pg_temp.through_60(p_fleet, p_sea, v_days), v_port, v_port, p_at);
    update public.voyages set id = c_voy where id = v_voy;
    for d in 1 .. 60 loop
      exit when (select o.status from public.voyages o where o.id = c_voy) <> 'SAILING' or d > voyage.total_days(c_voy);
      perform set_config('byeharu.proof_sea', coalesce(p_seas[d], ''), true);
      if p_by_day or p_hold is not null or d < v_days then
        perform voyage.settle(p_fleet, voyage.day_ends_at(c_voy, d));
      end if;
      if d = 3 and p_hold is not null then
        v_t3 := voyage.day_ends_at(c_voy, 3);
        v_mid := jsonb_build_object('nm_at_hold', voyage.progress_nm(c_voy, v_t3));
        perform voyage.hold(p_fleet, v_t3 + make_interval(secs => p_hold), v_t3);
        v_mid := v_mid || jsonb_build_object('nm_mid_hold', voyage.progress_nm(c_voy, v_t3 + make_interval(secs => least(p_hold, coalesce(p_cut, p_hold)) / 2)),
                                             'days_mid_hold', voyage.days_complete(c_voy, v_t3 + make_interval(secs => least(p_hold, coalesce(p_cut, p_hold)) / 2)));
        if p_cut is not null then
          perform voyage.hold_cut(p_fleet, v_t3, v_t3 + make_interval(secs => p_cut));
        end if;
        v_mid := v_mid || jsonb_build_object('nm_end_hold', voyage.progress_nm(c_voy, v_t3 + make_interval(secs => coalesce(p_cut, p_hold))),
                                             'nm_60s_after', voyage.progress_nm(c_voy, v_t3 + make_interval(secs => coalesce(p_cut, p_hold) + 60)),
                                             'total_days', voyage.total_days(c_voy), 'eta', (select o.eta from public.voyages o where o.id = c_voy),
                                             'arrival_at', voyage.arrival_at(c_voy, (select o.eta from public.voyages o where o.id = c_voy) + interval '30 days'));
        update public.fleets set busy_until = null where id = p_fleet;
      end if;
    end loop;
    perform set_config('byeharu.proof_sea', '', true);
    perform voyage.settle(p_fleet, (select o.eta from public.voyages o where o.id = c_voy) + interval '1 second');
    if (select o.status from public.voyages o where o.id = c_voy) <> 'ARRIVED' then
      raise exception 'PROOF 60 FAIL: the passage did not arrive: %', (select to_jsonb(o) - 'path' from public.voyages o where o.id = c_voy);
    end if;
    v_out := v_mid || jsonb_build_object(
      'eta', (select o.eta from public.voyages o where o.id = c_voy),
      'delay', (select o.delay_hours from public.voyages o where o.id = c_voy),
      'n_days', (select count(*) from public.voyage_events e where e.voyage_id = c_voy and e.day_index < voyage.hold_floor() and e.kind <> 'LANDFALL'),
      'days', (select jsonb_agg(jsonb_build_object('d', e.day_index, 'kind', e.kind, 'payload', e.payload, 'at', e.resolved_at) order by e.day_index)
                 from public.voyage_events e where e.voyage_id = c_voy),
      'kinds', (select jsonb_agg(jsonb_build_array(e.day_index, e.kind, e.payload - 'delay_hours' - 'hours_gained') order by e.day_index)
                  from public.voyage_events e where e.voyage_id = c_voy and e.day_index < voyage.hold_floor()),
      'events', (select coalesce(jsonb_agg(jsonb_build_object('kind', e.kind, 'payload', e.payload) order by e.kind, e.payload::text), '[]'::jsonb)
                   from public.events e where e.player_id = v_pl and e.id <> all (v_ev)),
      'ledger', (select coalesce(jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.balance_after desc, l.kind), '[]'::jsonb)
                   from public.ledger l where l.player_id = v_pl and l.id <> all (v_led)),
      'purse', (select p.ducats from public.players p where p.id = v_pl),
      'wages', (select coalesce(sum(w.owed), 0) from public.fleet_wages w where w.fleet_id = p_fleet),
      'fleet', (select to_jsonb(f) - 'version' - 'updated_at' - 'ready_at' from public.fleets f where f.id = p_fleet),
      'ships', (select jsonb_agg(to_jsonb(s) - 'updated_at' order by s.name) from public.ships s where s.fleet_id = p_fleet));
    raise exception using errcode = 'ZX360', message = 'PASSAGE_ROLLBACK_60';
  exception when sqlstate 'ZX360' then
    null;
  end;
  perform set_config('byeharu.proof_sea', '', true);
  return v_out;
end
$b$;

-- WHAT A SHIP CALLED FOR ROUND 3 ADDS, judged on a play's own rows so it holds under any dice: null when it holds, else the figures. L2 and L3 are the side's hull left after rounds
-- 2 and 3, H hers on the sheet, D3 what the other side's guns dealt in round 3 (a shot can deal more than the hull it sinks, so the loss is at most D3):
--   L3 <= L2 + H (she is whole when she comes up) and L3 >= L2 + H - D3 (the round took no more than was fired);
--   and she is THERE: either the round struck her (her place on the sheet is in the row's `struck`), or it did not and her whole hull stands in what is left (L3 >= H).
create function pg_temp.called_60(p_play jsonb, p_fleet uuid) returns jsonb language sql stable as $b$
  with s as (select e, o from jsonb_array_elements(p_play -> 'battle' -> 'sheet' -> 'a') with ordinality q(e, o)),
       f as (select (p_play -> 'rounds' -> 1 -> 'row' -> 'a' ->> 'left')::numeric as l2, (p_play -> 'rounds' -> 2 -> 'row' -> 'a' ->> 'left')::numeric as l3,
                    (p_play -> 'rounds' -> 2 -> 'row' -> 'b' ->> 'dealt')::numeric as d3,
                    (select sum((s.e ->> 'hull')::numeric) from s where s.e ->> 'fleet' = p_fleet::text) as h,
                    exists (select 1 from jsonb_array_elements(p_play -> 'rounds' -> 2 -> 'row' -> 'a' -> 'struck') st join s on s.o = (st ->> 0)::int where s.e ->> 'fleet' = p_fleet::text) as struck)
  select case when f.l2 is not null and f.l3 is not null and f.h > 0 and f.l3 <= f.l2 + f.h + 0.01 and f.l3 >= f.l2 + f.h - f.d3 - 0.01 and (f.struck or f.l3 >= f.h - 0.01)
              then null else to_jsonb(f) end
    from f
$b$;

-- ONE BATTLE, PLAYED ONE WAY, in a subtransaction that is rolled back. The battle's id is pinned (it is the fight's seed), the attack is the real one at p_t, the stances are rows
-- at instants of the scene's choosing ([[seconds after the open, stance], ...]: what the door writes at that instant), and it is played by the real job: 'TICK' at every round's
-- instant and the clock's end, 'LATE' by one call an hour after, 'OLD' under the rebuilt old bodies (one call at the old clock's end), 'OPEN' not at all. p_called: fleets written
-- on the list as called ships [[fleet, seconds after the open or null for never]]. Answers everything it left.
create function pg_temp.play_60(p_id uuid, p_a uuid, p_d uuid, p_t timestamptz, p_mode text, p_stances jsonb default '[]'::jsonb, p_called jsonb default '[]'::jsonb)
returns jsonb language plpgsql as $b$
declare
  v_pl    uuid := (select f.player_id from public.fleets f where f.id = p_a);
  v_ev    uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_led   uuid[] := array(select l.id from public.ledger l where l.player_id = v_pl);
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
  v_b     uuid;
  v_x     jsonb;
  v_grow  int[] := '{}';
  v_closed int := 0;
  v_k     int;
  v_rs    int;
  v_out   jsonb;
  v_open  jsonb;
  v_reads jsonb := '[]'::jsonb;
  v_rd    jsonb;
  g       int;
begin
  begin
    if p_mode = 'OLD' then
      perform pg_temp.to_old_60();
    end if;
    execute format('alter table public.battles alter column id set default %L::uuid', p_id);
    v_x := public.attack_for(v_pl, p_a, p_d, null, p_t);
    v_b := (v_x ->> 'battle_id')::uuid;
    if v_b is distinct from p_id then
      raise exception 'PROOF 60 FAIL: the battle''s id was not pinned';
    end if;
    v_open := (select to_jsonb(b) from public.battles b where b.id = v_b);
    if p_mode <> 'OLD' then
      v_rs := (select b.round_seconds from public.battles b where b.id = v_b);
      insert into public.battle_stances (battle_id, fleet_id, set_at, stance)
      select v_b, p_a, p_t + make_interval(secs => (e ->> 0)::int), e ->> 1 from jsonb_array_elements(p_stances) e;
      insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how)
      select v_b, (e ->> 0)::uuid, 'DEFENDER', p_t, coalesce(p_t + make_interval(secs => (e ->> 1)::int), 'infinity'), 'CALLED' from jsonb_array_elements(p_called) e;
    end if;
    if p_mode = 'TICK' then
      for g in 1 .. v_n + 1 loop
        v_k := public.tick_battles(p_t + make_interval(secs => g * v_rs));
        v_closed := v_closed + v_k;
        v_grow := v_grow || (select count(*)::int from public.battle_rounds r where r.battle_id = v_b);
        -- what she reads after this tick (the read is the caller's own: her identity for the call)
        perform cmd.assume_identity((select pl.auth_uid from public.players pl where pl.id = v_pl));
        v_rd := world.battle(p_a);
        v_reads := v_reads || jsonb_build_array(jsonb_build_object('status', v_rd -> 'status', 'rows', jsonb_array_length(v_rd -> 'log' -> 'r'), 'done', v_rd -> 'rounds_done',
                     'told', (v_rd -> 'log' ? 'end') or (v_rd -> 'log' ? 'board') or v_rd ? 'outcome' or v_rd ? 'loot', 'next_range', v_rd -> 'next_range'));
      end loop;
    elsif p_mode = 'LATE' then
      v_closed := public.tick_battles(p_t + interval '1 hour');
    elsif p_mode = 'OLD' then
      v_closed := public.tick_battles(p_t + interval '1 hour');
    end if;
    v_out := jsonb_build_object(
      'attack', v_x - 'resolves_at' - 'navy_minutes',
      'open', v_open,
      'battle', (select to_jsonb(b) - 'next_round_at' from public.battles b where b.id = v_b),
      'rounds', (select coalesce(jsonb_agg(jsonb_build_object('g', r.g, 'at', r.at, 'row', r."row") order by r.g), '[]'::jsonb) from public.battle_rounds r where r.battle_id = v_b),
      'stances', (select coalesce(jsonb_agg(jsonb_build_array(s.set_at, s.stance) order by s.set_at), '[]'::jsonb) from public.battle_stances s where s.battle_id = v_b),
      'closed', v_closed, 'grow', to_jsonb(v_grow), 'reads', v_reads,
      'fleets', (select jsonb_agg(jsonb_build_object('id', f.id, 'status', f.status, 'busy', f.busy_until) order by f.id) from public.fleets f where f.id in (p_a, p_d)),
      'ships', (select jsonb_agg(jsonb_build_array(s.id, s.durability, s.crew) order by s.id) from public.ships s where s.fleet_id in (p_a, p_d)),
      'purse', (select p.ducats from public.players p where p.id = v_pl),
      'aboard', (select x.aboard from public.cargo_ship_aboard(p_d) x),
      'events', (select coalesce(jsonb_agg(jsonb_build_object('kind', e.kind, 'payload', e.payload) order by e.kind, e.payload::text), '[]'::jsonb)
                   from public.events e where e.player_id = v_pl and e.id <> all (v_ev) and e.kind = 'BATTLE_REPORT'),
      -- any other event of hers (a WANTED notice carries the instant the close ran at), by kind
      'other_events', (select coalesce(jsonb_agg(e.kind order by e.kind), '[]'::jsonb) from public.events e where e.player_id = v_pl and e.id <> all (v_ev) and e.kind <> 'BATTLE_REPORT'),
      'ledger', (select coalesce(jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.balance_after desc, l.kind), '[]'::jsonb)
                   from public.ledger l where l.player_id = v_pl and l.id <> all (v_led)),
      'voyage', (select jsonb_build_object('eta', o.eta, 'delay', o.delay_hours, 'days', voyage.total_days(o.id), 'status', o.status,
                                           'hold', (select jsonb_agg(e.payload order by e.day_index) from public.voyage_events e where e.voyage_id = o.id and e.day_index >= voyage.hold_floor()))
                   from public.voyages o where o.fleet_id = p_d and o.status = 'SAILING'),
      'rerun', case when p_mode <> 'OLD' then public.battle_fight(v_b, null) end);
    raise exception using errcode = 'ZX360', message = 'PLAY_ROLLBACK_60';
  exception when sqlstate 'ZX360' then
    null;
  end;
  return v_out;
end
$b$;

do $p$
declare
  c_uid   constant uuid := '00000000-0357-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0357-4000-8000-000000000002';
  v_t     timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' + interval '2 hours';
  v_k     numeric := public.wc_num('time_compression');
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
  v_lis   uuid;
  v_sea   uuid;
  a       uuid;     -- her gunned fleet
  a2      uuid;     -- another company's
  p       uuid;
  d       uuid;     -- a cargo ship at sea
  d2      uuid;
  d3      uuid;
  v_npc   uuid;
  v_nfl   uuid;
  v_hfl   uuid;     -- a company's trader, for the ordinary voyage
  v_hum   uuid;
  v_new   jsonb;
  v_old   jsonb;
  v_u     jsonb;
  v_h     jsonb;
  v_o     jsonb;
  v_c     jsonb;
  v_w     jsonb;
  v_tick  jsonb;
  v_late  jsonb;
  v_oldp  jsonb;
  v_st    jsonb;
  v_stl   jsonb;
  v_r     jsonb;
  v_x     jsonb;
  v_id    uuid;
  v_i     int;
  v_m     int;
  v_m3    int;
  v_e1    text;
  v_e2    text;
  v_e3    text;
  v_seas  text[];
  v_bat   uuid;
  v_eta0  timestamptz;
  v_days0 int;
  v_was   bigint;
  v_secs  numeric;
  v_hold_h numeric;
begin
  select pt.id into v_lis from public.ports pt where pt.code = 'LIS';
  v_sea := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  a := pg_temp.house_60(1);
  p := (select f.player_id from public.fleets f where f.id = a);
  a2 := pg_temp.house_60(2);
  d := pg_temp.ship_60(100000, v_t);
  d2 := pg_temp.ship_60(100000, v_t);
  d3 := pg_temp.ship_60(100000, v_t);
  v_npc := public.new_house(null, 'Proof 60 merchant', 'PRT', p_ducats => 20000, p_is_npc => true);
  select f.id into v_nfl from public.fleets f where f.player_id = v_npc;
  insert into public.players (auth_uid, company_name, nation_id, ducats) values ('00000000-0357-4000-8000-000000000009', 'Proof 60 trader', (select n.id from public.nations n where n.code = 'PRT'), 300000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Proof 60 trader fleet', v_lis);
  perform public.commission_ship(v_hum, v_hfl, 'jacht', 'Proof 60 jacht', true, true);
  update public.ships s set water_t = 100000, food_t = 100000 where s.fleet_id in (v_hfl, v_nfl);

  -- ══ DARK_PARITY: attack_enabled false. An ordinary voyage of a merchant and of a company, old bodies against new ══
  v_seas := array['', 'CALM', 'PIRATES', '', 'PIRATES', 'FAIR_WIND', '', 'STORM', 'PIRATES', ''];
  foreach v_id in array array[v_nfl, v_hfl] loop
    for v_i in 0 .. 1 loop
      v_new := pg_temp.passage_60(v_id, v_sea, v_seas, v_t, v_i = 0, false);
      v_old := pg_temp.passage_60(v_id, v_sea, v_seas, v_t, v_i = 0, true);
      if v_new is null or v_new::text is distinct from v_old::text then
        raise exception 'PROOF 60 FAIL: DARK PARITY: an ordinary voyage changed (fleet %, by day %): % against %', v_id, v_i = 0, v_new, v_old;
      end if;
      if (v_new ->> 'n_days')::int < 10 or not (v_new -> 'days')::text like '%"PIRATES"%' or not (v_new -> 'days')::text like '%"CALM"%' or (v_new ->> 'delay')::numeric <= 0
         or not exists (select 1 from jsonb_array_elements(v_new -> 'events') e where e ->> 'kind' = 'VOYAGE_REPORT') then
        raise exception 'PROOF 60 FAIL: the ordinary voyage was not one: % days, delay %', v_new ->> 'n_days', v_new ->> 'delay';
      end if;
    end loop;
  end loop;
  v_m := length(v_new::text);
  -- the job, the closer, the open, the attack and the doors, dark, old against new
  perform pg_temp.lie_by(a, d, v_t);
  begin
    v_x := jsonb_build_object('tick', public.tick_battles(v_t + interval '1 day'), 'resolve', public.battle_resolve(gen_random_uuid(), v_t));
    begin perform public.battle_open('ATTACK', a, d, v_t); v_e1 := 'opened'; exception when others then v_e1 := sqlerrm; end;
    begin perform public.attack_for(p, a, d, null, v_t); v_e2 := 'attacked'; exception when others then v_e2 := sqlerrm; end;
    perform pg_temp.to_old_60();
    v_r := jsonb_build_object('tick', public.tick_battles(v_t + interval '1 day'), 'resolve', public.battle_resolve(gen_random_uuid(), v_t));
    begin perform public.battle_open('ATTACK', a, d, v_t); v_e3 := 'opened'; exception when others then v_e3 := sqlerrm; end;
    if v_x is distinct from v_r or v_x is distinct from '{"tick": 0, "resolve": false}'::jsonb or v_e1 is distinct from v_e3 or v_e1 not like 'E_NOT_YET:%' or v_e2 not like 'E_NOT_IN_USE:%' then
      raise exception 'PROOF 60 FAIL: DARK PARITY: the job, the closer, the open or the attack: % against %; % against %; %', v_x, v_r, v_e1, v_e3, v_e2;
    end if;
    begin perform public.attack_for(p, a, d, null, v_t); v_e3 := 'attacked'; exception when others then v_e3 := sqlerrm; end;
    if v_e3 is distinct from v_e2 then
      raise exception 'PROOF 60 FAIL: DARK PARITY: the attack under the old bodies answered %', v_e3;
    end if;
    raise exception using errcode = 'ZX360', message = 'DARK_ROLLBACK_60';
  exception when sqlstate 'ZX360' then
    null;
  end;
  perform cmd.assume_identity(c_uid);
  if cmd.battle_stance(gen_random_uuid(), 'FLEE') ->> 'error_code' is distinct from 'E_NOT_IN_USE' or world.battle(a) is distinct from '{"on": false}'::jsonb
     or cmd.attack(a, d) ->> 'error_code' is distinct from 'E_NOT_IN_USE'
     or exists (select 1 from public.battles) or exists (select 1 from public.battle_rounds) or exists (select 1 from public.battle_stances)
     or exists (select 1 from public.voyage_events e where e.kind = 'BATTLE') or not pg_temp.live_60_ok() then
    raise exception 'PROOF 60 FAIL: DARK: a door did something, a battle or a hold was written, or the old bodies stayed';
  end if;
  raise notice 'PASS: DARK_PARITY — attack_enabled false: a merchant''s and a company''s voyage of ten sea days (quiet, a calm, a storm, a fair wind, three raids), settled day by day and once, the old bodies (rebuilt from the live ones) against the new: every day, the report, the ledger, the purse, the fleet and the hulls byte for byte (% bytes a passage); the job, the closer, the open and the attack answer as they did; the stance door and cmd.attack refuse E_NOT_IN_USE and the read says off; no battle, round, stance or hold exists', v_m;

  -- ══ LIT, in this transaction only ══
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';

  -- ══ NO_PVP ══
  perform pg_temp.lie_by(a2, d, v_t);
  begin perform public.battle_open('ATTACK', a, a2, v_t); v_e1 := 'opened'; exception when others then v_e1 := sqlerrm; end;
  begin perform public.battle_open('PROBE', a, a2, v_t); v_e2 := 'opened'; exception when others then v_e2 := sqlerrm; end;
  begin perform public.attack_for(p, a, a2, null, v_t); v_e3 := 'attacked'; exception when others then v_e3 := sqlerrm; end;
  v_x := cmd.attack(a, a2);
  v_r := cmd.preview_attack(a, a2);
  if v_e1 not like 'E_HUMAN_TARGET:%' or v_e2 not like 'E_HUMAN_TARGET:%' or v_e3 not like 'E_HUMAN_TARGET:%'
     or v_x ->> 'error_code' is distinct from 'E_HUMAN_TARGET' or v_r ->> 'error_code' is distinct from 'E_HUMAN_TARGET'
     or public.fleet_kind(a2) is distinct from 'COMPANY' or exists (select 1 from public.battles) or exists (select 1 from public.battle_sides) then
    raise exception 'PROOF 60 FAIL: A PLAYER COULD FIGHT A PLAYER: battle_open % / %, attack_for %, cmd.attack %, the preview %', v_e1, v_e2, v_e3, v_x, v_r;
  end if;
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where f.id = a2;
  raise notice 'PASS: NO_PVP — lit: public.battle_open (ATTACK and PROBE), public.attack_for, cmd.attack and its preview each refuse a company''s fleet as a target (E_HUMAN_TARGET); no battle and no side was written';

  -- ══ ROUNDS_TICK_LATE: one battle, the id found that is fought through every round (the stance scenes need the rounds) ══
  for v_i in 1 .. 40 loop
    v_id := ('00000000-0357-4000-8000-0000000b' || lpad(v_i::text, 4, '0'))::uuid;
    v_late := pg_temp.play_60(v_id, a, d, v_t, 'LATE');
    exit when jsonb_array_length(v_late -> 'rounds') = v_n;
    v_id := null;
  end loop;
  if v_id is null then
    raise exception 'PROOF 60 FAIL: no battle of 40 was fought through every round: the last %', v_late -> 'battle' -> 'result';
  end if;
  v_tick := pg_temp.play_60(v_id, a, d, v_t, 'TICK');
  v_oldp := pg_temp.play_60(v_id, a, d, v_t, 'OLD');
  if (v_tick - 'grow' - 'closed' - 'reads')::text is distinct from (v_late - 'grow' - 'closed' - 'reads')::text then
    raise exception 'PROOF 60 FAIL: tick by tick and one late call are not the same battle: %',
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_late -> k.key)) from jsonb_each(v_tick - 'grow' - 'closed' - 'reads') k where k.value::text is distinct from (v_late -> k.key)::text);
  end if;
  if (v_tick ->> 'closed')::int is distinct from 1 or (v_late ->> 'closed')::int is distinct from 1
     or v_tick -> 'grow' is distinct from (select jsonb_agg(least(g, v_n) order by g) from generate_series(1, v_n + 1) g)
     or v_tick -> 'battle' ->> 'status' is distinct from 'RESOLVED' or (v_tick -> 'battle' ->> 'rounds_done')::int is distinct from v_n
     or (v_tick -> 'battle' ->> 'resolves_at')::timestamptz is distinct from v_t + make_interval(secs => 60 * (v_n + 1))
     or (v_tick -> 'open' ->> 'round_seconds')::int is distinct from 60 or (v_tick -> 'open' ->> 'next_round_at')::timestamptz is distinct from v_t + interval '60 seconds'
     or jsonb_array_length(v_tick -> 'open' -> 'sheet' -> 'a') < 1 or jsonb_array_length(v_tick -> 'open' -> 'sheet' -> 'b') < 1
     or exists (select 1 from jsonb_array_elements(v_tick -> 'rounds') r
                 where (r -> 'row')::text is distinct from (v_tick -> 'rerun' -> 'rounds' -> ((r ->> 'g')::int - 1))::text
                    or (r ->> 'at')::timestamptz is distinct from v_t + make_interval(secs => 60 * (r ->> 'g')::int))
     or (v_tick -> 'battle' -> 'result' -> 'rounds')::text is distinct from (select jsonb_agg(r -> 'row' order by (r ->> 'g')::int) from jsonb_array_elements(v_tick -> 'rounds') r)::text
     or jsonb_typeof(v_tick -> 'battle' -> 'result' -> 'board') is distinct from 'object'
     or exists (select 1 from jsonb_array_elements(v_tick -> 'fleets') f where f ->> 'busy' is not null or f ->> 'status' = 'IN_BATTLE')
     or jsonb_array_length(v_tick -> 'events') is distinct from 1 or v_tick -> 'events' -> 0 ->> 'kind' is distinct from 'BATTLE_REPORT' then
    raise exception 'PROOF 60 FAIL: the battle fought through: closed % / %, grew %, %', v_tick ->> 'closed', v_late ->> 'closed', v_tick -> 'grow', v_tick -> 'battle';
  end if;
  -- with nobody choosing it ends as the one call of the old bodies did: the same fight, the same loot, hulls, hands and purse (the old clock is longer; the old battle keeps no sheet and no row)
  if ((v_oldp -> 'battle' -> 'result') - 'navy')::text is distinct from ((v_tick -> 'battle' -> 'result') - 'navy')::text
     or v_oldp -> 'ships' is distinct from v_tick -> 'ships' or v_oldp -> 'purse' is distinct from v_tick -> 'purse' or v_oldp -> 'aboard' is distinct from v_tick -> 'aboard'
     or v_oldp -> 'ledger' is distinct from v_tick -> 'ledger' or v_oldp -> 'rounds' is distinct from '[]'::jsonb or v_oldp -> 'open' -> 'sheet' is distinct from 'null'::jsonb
     or (v_oldp -> 'battle' ->> 'resolves_at')::timestamptz is distinct from v_t + make_interval(secs => public.wc_num('battle_seconds')::double precision)
     or ((v_oldp -> 'events' -> 0 -> 'payload') #- '{fights,0,log}')::text is distinct from ((v_tick -> 'events' -> 0 -> 'payload') #- '{fights,0,log}')::text then
    raise exception 'PROOF 60 FAIL: with nobody choosing, the battle did not end as the old one call did: result %; ships % %; purse % %; ledger % %; rounds %; clock %; report %',
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_tick -> 'battle' -> 'result' -> k.key)) from jsonb_each(v_oldp -> 'battle' -> 'result') k where k.value::text is distinct from (v_tick -> 'battle' -> 'result' -> k.key)::text),
      v_oldp -> 'ships', v_tick -> 'ships', v_oldp -> 'purse', v_tick -> 'purse', v_oldp -> 'ledger', v_tick -> 'ledger', v_oldp -> 'rounds', v_oldp -> 'battle' ->> 'resolves_at',
      ((v_oldp -> 'events' -> 0 -> 'payload') #- '{fights,0,log}')::text is distinct from ((v_tick -> 'events' -> 0 -> 'payload') #- '{fights,0,log}')::text;
  end if;
  -- the read while it is fought: after tick g it shows g rows and tells nothing ahead: no ending, no boarding, no loot; after the last round the boarding is still to come
  if exists (select 1 from jsonb_array_elements(v_tick -> 'reads') with ordinality q(e, g)
              where g <= v_n and (e ->> 'status' is distinct from 'FIGHTING' or (e ->> 'rows')::int is distinct from g::int or (e ->> 'told')::boolean
                                  or (g < v_n and e ->> 'next_range' is null) or (g = v_n and e ->> 'next_range' is not null)))
     or v_tick -> 'reads' -> v_n ->> 'status' is distinct from 'RESOLVED' or (v_tick -> 'reads' -> v_n ->> 'told')::boolean is not true then
    raise exception 'PROOF 60 FAIL: the read while it is fought told something early, or not at the close: %', v_tick -> 'reads';
  end if;
  v_x := v_tick -> 'events' -> 0 -> 'payload' -> 'fights' -> 0 -> 'log';
  if (v_x ->> 'v')::int is distinct from 1 or jsonb_array_length(v_x -> 'r') is distinct from v_n or coalesce(v_x ->> 'end', '') not in ('A_THROWN', 'A_TERMS', 'A_TOOK')
     or exists (select 1 from jsonb_array_elements(v_x -> 'r') e where jsonb_array_length(e) is distinct from 14)
     or jsonb_array_length(v_x -> 'you') is distinct from jsonb_array_length(v_tick -> 'open' -> 'sheet' -> 'b') or jsonb_array_length(v_x -> 'board') is distinct from 3
     or jsonb_array_length(v_tick -> 'events' -> 0 -> 'payload' -> 'fights' -> 0 -> 'rounds') is distinct from v_n then
    raise exception 'PROOF 60 FAIL: the report''s log is not the fight from her deck: %', v_x;
  end if;
  raise notice 'PASS: ROUNDS_TICK_LATE — battle %: tick by tick (the log grew %; closed once, at the clock''s end, % s) and by one late call: the same % rows, result (%), hulls, hands, purse (loot %), report and ledger, as text; each row is the re-run''s row at its own instant; with nobody choosing it ends as the old bodies'' one call did; the report carries the log from her deck (%)',
    v_id, v_tick -> 'grow', 60 * (v_n + 1), jsonb_array_length(v_tick -> 'rounds'), v_tick -> 'battle' -> 'result' ->> 'outcome', v_tick -> 'battle' -> 'result' ->> 'loot', v_x ->> 'end';

  -- ══ STANCE_CHANGE: Flee set between round 2 and round 3. The knobs keep her from getting away here, so every round is fought ══
  update public.world_config set value = '0'::jsonb where key in ('fight_flee_floor', 'fight_evade_max', 'fight_flee_base');
  v_st := pg_temp.play_60(v_id, a, d, v_t, 'TICK', '[[150, "FLEE"]]'::jsonb);
  v_stl := pg_temp.play_60(v_id, a, d, v_t, 'LATE', '[[150, "FLEE"]]'::jsonb);
  if (v_st - 'grow' - 'closed' - 'reads')::text is distinct from (v_stl - 'grow' - 'closed' - 'reads')::text then
    raise exception 'PROOF 60 FAIL: with a stance change, tick by tick and late are not the same battle';
  end if;
  if (v_st -> 'rounds' -> 0)::text is distinct from (v_tick -> 'rounds' -> 0)::text or (v_st -> 'rounds' -> 1)::text is distinct from (v_tick -> 'rounds' -> 1)::text
     or (v_st -> 'rounds' -> 2)::text is not distinct from (v_tick -> 'rounds' -> 2)::text
     or exists (select 1 from jsonb_array_elements(v_st -> 'rounds') r where (r ->> 'g')::int <= 2 and r -> 'row' ? 'b_flee')
     or exists (select 1 from jsonb_array_elements(v_st -> 'rounds') r where (r ->> 'g')::int >= 3 and (not r -> 'row' ? 'b_flee' or (r -> 'row' -> 'b' ->> 'fired')::int is distinct from 0))
     or jsonb_array_length(v_st -> 'rounds') < 3
     or exists (select 1 from jsonb_array_elements(v_st -> 'rounds') r where (r -> 'row')::text is distinct from (v_st -> 'rerun' -> 'rounds' -> ((r ->> 'g')::int - 1))::text)
     or v_st -> 'battle' ->> 'status' is distinct from 'RESOLVED' or v_st -> 'battle' -> 'result' ? 'b_fled' then
    raise exception 'PROOF 60 FAIL: Flee from round 3: rows %, result %', v_st -> 'rounds', v_st -> 'battle' -> 'result';
  end if;
  raise notice 'PASS: STANCE_CHANGE — Flee set 150 s in (after round 2, before round 3): rounds 1 and 2 are the rows of the battle fought through, as text; rounds 3 to % are fought with her guns silent, each with her chance on the row; tick by tick and one late call agree; every row is the re-run''s', jsonb_array_length(v_st -> 'rounds');

  -- ══ FLEE_CAUGHT: Flee from the first round, never away ══
  v_c := pg_temp.play_60(v_id, a, d, v_t, 'TICK', '[[1, "FLEE"]]'::jsonb);
  if exists (select 1 from jsonb_array_elements(v_c -> 'rounds') r where (r -> 'row' -> 'b' ->> 'fired')::int is distinct from 0 or (r -> 'row' ->> 'b_flee')::numeric is distinct from 0)
     or v_c -> 'battle' ->> 'status' is distinct from 'RESOLVED' or v_c -> 'battle' -> 'result' ? 'b_fled' or (v_c -> 'battle' -> 'result' -> 'hits' ->> 'b')::int is distinct from 0
     or not ((v_c -> 'battle' -> 'result' ->> 'broke_off')::boolean or jsonb_typeof(v_c -> 'battle' -> 'result' -> 'board') = 'object') then
    raise exception 'PROOF 60 FAIL: a Flee that never got away: %', v_c -> 'battle' -> 'result';
  end if;
  raise notice 'PASS: FLEE_CAUGHT — Flee from the first round with no chance to slip: % rounds, not a shot of hers, and the fight ends as it says (%, broke off %); the status is RESOLVED, never BROKEN_OFF',
    jsonb_array_length(v_c -> 'rounds'), v_c -> 'battle' -> 'result' ->> 'outcome', v_c -> 'battle' -> 'result' ->> 'broke_off';

  -- ══ BREAK_OFF: the knobs make her Flee certain (the floor AND the ceiling at 1: the rule is least(max, greatest(floor, ...))) ══
  update public.world_config set value = '1'::jsonb where key in ('fight_flee_floor', 'fight_evade_max');
  select o.eta, voyage.total_days(o.id) into v_eta0, v_days0 from public.voyages o where o.fleet_id = d and o.status = 'SAILING';
  v_was := (select pl.ducats from public.players pl where pl.id = p);
  v_w := pg_temp.play_60(v_id, a, d, v_t, 'TICK', '[[70, "FLEE"]]'::jsonb);
  v_x := pg_temp.play_60(v_id, a, d, v_t, 'LATE', '[[70, "FLEE"]]'::jsonb);
  if (v_w - 'grow' - 'closed' - 'reads')::text is distinct from (v_x - 'grow' - 'closed' - 'reads')::text then
    raise exception 'PROOF 60 FAIL: a break-off, tick by tick and late, is not the same battle: % against %', v_w -> 'battle', v_x -> 'battle';
  end if;
  v_r := v_w -> 'battle' -> 'result';
  if v_w -> 'battle' ->> 'status' is distinct from 'BROKEN_OFF' or (v_r ->> 'b_fled')::boolean is not true or (v_r ->> 'broke_off')::boolean is not true
     or jsonb_array_length(v_w -> 'rounds') is distinct from 2 or (v_w -> 'battle' ->> 'resolves_at')::timestamptz is distinct from v_t + interval '120 seconds'
     or (v_w -> 'rounds' -> 0)::text is distinct from (v_tick -> 'rounds' -> 0)::text or (v_w -> 'rounds' -> 1 -> 'row' ->> 'b_flee')::numeric is distinct from 1
     or (v_w ->> 'closed')::int is distinct from 1 or v_w -> 'grow' is distinct from (select jsonb_agg(least(g, 2) order by g) from generate_series(1, v_n + 1) g)
     or (v_r ->> 'loot')::bigint is distinct from 0 or (v_w ->> 'purse')::bigint is distinct from v_was or (v_w ->> 'aboard')::bigint is distinct from 100000 or v_w -> 'ledger' is distinct from '[]'::jsonb
     or jsonb_typeof(v_r -> 'board') is distinct from 'null'
     or exists (select 1 from jsonb_array_elements(v_w -> 'fleets') f where f ->> 'busy' is not null or f ->> 'status' = 'IN_BATTLE')
     or v_w -> 'events' -> 0 -> 'payload' -> 'lines' ->> 0 is distinct from 'We broke off.' or v_w -> 'events' -> 0 -> 'payload' -> 'fights' -> 0 -> 'log' ->> 'end' is distinct from 'FLED'
     or v_w -> 'events' -> 0 -> 'payload' -> 'fights' -> 0 -> 'rounds' ->> 1 not like '%you run before them%'
     or v_w -> 'events' -> 0 -> 'payload' ->> 'outcome' is distinct from v_r ->> 'outcome' then
    raise exception 'PROOF 60 FAIL: a break-off: battle %, events %', v_w -> 'battle', v_w -> 'events';
  end if;
  -- the hands: the beaten row of attack_crew_lost, as public.attack_close charges a break-off
  if (v_r ->> 'crew_lost')::int is distinct from (select sum(public.raid_crew_lost(a, s.crew, (public.wc('attack_crew_lost') ->> 'beaten')::numeric))::int from public.ships s where s.fleet_id = a) then
    raise exception 'PROOF 60 FAIL: a break-off cost % hands, not the beaten row', v_r ->> 'crew_lost';
  end if;
  -- the target's hold ended with the battle: her arrival moved by the 120 s she stood, not by the clock's 420, and her days are the days she had
  if (v_w -> 'voyage' ->> 'eta')::timestamptz is distinct from v_eta0 + interval '120 seconds' or (v_w -> 'voyage' ->> 'days')::int is distinct from v_days0
     or (v_w -> 'voyage' -> 'hold' -> 0 ->> 'held_until')::timestamptz is distinct from v_t + interval '120 seconds' or (v_w -> 'voyage' -> 'hold' -> 0 ->> 'free')::boolean is not true
     or (v_tick -> 'voyage' ->> 'eta')::timestamptz is distinct from v_eta0 + make_interval(secs => 60 * (v_n + 1)) or (v_tick -> 'voyage' ->> 'days')::int is distinct from v_days0 then
    raise exception 'PROOF 60 FAIL: the target''s hold: eta % (before %), days % (before %), hold %; fought through: eta %', v_w -> 'voyage' ->> 'eta', v_eta0, v_w -> 'voyage' ->> 'days', v_days0, v_w -> 'voyage' -> 'hold', v_tick -> 'voyage' ->> 'eta';
  end if;
  raise notice 'PASS: BREAK_OFF — Flee set 70 s in, certain: round 1 is the fought-through row, round 2 she runs and is away: BROKEN_OFF, closed at 120 s (not 420), no loot, purse and the ship''s funds unmoved, % hands (the beaten row), "We broke off.", the log ends FLED, both fleets free; tick by tick and late agree; the target''s arrival moved by the 120 s she stood and her days are unchanged (%); fought through, by 420 s and the same days',
    v_r ->> 'crew_lost', v_days0;
  update public.world_config set value = to_jsonb(0.05) where key = 'fight_flee_floor';
  update public.world_config set value = to_jsonb(0.30) where key = 'fight_evade_max';
  update public.world_config set value = to_jsonb(0.15) where key = 'fight_flee_base';

  -- ══ CALLED_FROM: three called ships written on the list: one comes up 150 s in (round 3), one 400 s in (after the last round: the boarding), one never ══
  v_c := pg_temp.play_60(v_id, a, d, v_t, 'TICK', '[]'::jsonb, jsonb_build_array(jsonb_build_array(d2, 150), jsonb_build_array(d3, 400), jsonb_build_array(v_nfl, null)));
  v_x := pg_temp.play_60(v_id, a, d, v_t, 'LATE', '[]'::jsonb, jsonb_build_array(jsonb_build_array(d2, 150), jsonb_build_array(d3, 400), jsonb_build_array(v_nfl, null)));
  if (v_c - 'grow' - 'closed' - 'reads')::text is distinct from (v_x - 'grow' - 'closed' - 'reads')::text then
    raise exception 'PROOF 60 FAIL: with called ships, tick by tick and late are not the same battle: % against %', v_c -> 'battle' -> 'sheet' -> 'a', v_x -> 'battle' -> 'sheet' -> 'a';
  end if;
  v_r := v_c -> 'battle' -> 'sheet' -> 'a';
  if (select count(*) from jsonb_array_elements(v_r) e where e ->> 'fleet' = d2::text and (e ->> 'from')::int = 3) < 1
     or exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'fleet' = d2::text and (e ->> 'from')::int is distinct from 3)
     or (jsonb_array_length(v_c -> 'rounds') = v_n and not exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'fleet' = d3::text and (e ->> 'from')::int = v_n + 1))
     or exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'fleet' = v_nfl::text)
     or (v_c -> 'rounds' -> 0)::text is distinct from (v_tick -> 'rounds' -> 0)::text or (v_c -> 'rounds' -> 1)::text is distinct from (v_tick -> 'rounds' -> 1)::text
     -- ROUND 3 HAS HER HULL TOO, whatever the dice did (the world's secret is its own: a shot may have sunk the target before her round, and round 3's may sink her):
     -- the side's hull after round 3 is its hull after round 2 plus hers, less what round 3 took, and round 3 took no more than was fired at the side;
     or pg_temp.called_60(v_c, d2) is not null
     -- and the side's starting hull is each hull once: the target's, and hers if the fight came to her round (a ship there only for the boarding is not in it)
     or (v_c -> 'battle' -> 'result' -> 'hull' ->> 'a_start')::numeric is distinct from
          (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_r) e where coalesce((e ->> 'from')::int, 1) <= jsonb_array_length(v_c -> 'rounds'))
     or exists (select 1 from jsonb_array_elements(v_c -> 'rounds') r where (r -> 'row')::text is distinct from (v_c -> 'rerun' -> 'rounds' -> ((r ->> 'g')::int - 1))::text)
     or (v_c -> 'battle' -> 'result' -> 'navy' ->> 'came')::int < 1 then
    -- the message says WHICH line failed and with what figures: a red on CI must be readable there (the dice are the world's own, and CI's world is not this desk's)
    raise exception 'PROOF 60 FAIL: the called ships: % | sheet % | navy % | with her [hull left, fired at her side] % | without her %',
      jsonb_build_object('round_3', pg_temp.called_60(v_c, d2),
        'round_1_same', (v_c -> 'rounds' -> 0)::text is not distinct from (v_tick -> 'rounds' -> 0)::text,
        'round_2_same', (v_c -> 'rounds' -> 1)::text is not distinct from (v_tick -> 'rounds' -> 1)::text,
        'rows_not_the_rerun', (select jsonb_agg(r -> 'g') from jsonb_array_elements(v_c -> 'rounds') r where (r -> 'row')::text is distinct from (v_c -> 'rerun' -> 'rounds' -> ((r ->> 'g')::int - 1))::text),
        'hull', v_c -> 'battle' -> 'result' -> 'hull', 'seed', v_id),
      (select jsonb_agg(jsonb_build_array(e -> 'name', e -> 'fleet', e -> 'from', e -> 'hull')) from jsonb_array_elements(v_r) e), v_c -> 'battle' -> 'result' -> 'navy',
      (select jsonb_agg(jsonb_build_array(r -> 'row' -> 'a' -> 'left', r -> 'row' -> 'b' -> 'dealt') order by (r ->> 'g')::int) from jsonb_array_elements(v_c -> 'rounds') r),
      (select jsonb_agg(jsonb_build_array(r -> 'row' -> 'a' -> 'left', r -> 'row' -> 'b' -> 'dealt') order by (r ->> 'g')::int) from jsonb_array_elements(v_tick -> 'rounds') r);
  end if;
  raise notice 'PASS: CALLED_FROM — a ship that came up 150 s in is on the sheet from round 3 (rounds 1 and 2 are the rows of the battle without her, as text; from round 3 the side set upon has her hull too: its hull after round 3 is its hull after round 2 plus hers less what the round took, whatever the dice; the side''s starting hull is each hull once); one that came up 400 s in is there for the boarding (from %); one that never came is never on the sheet; every row is the re-run''s; tick by tick and late agree; the report says %',
    v_n + 1, v_c -> 'battle' -> 'result' -> 'navy' ->> 'line';

  -- ══ STANCE_DOOR, BATTLE_READ, CLOSED_ONCE: one battle kept (not rolled back), opened 130 s ago by the real clock, so the door's own clock finds two rounds due ══
  execute format('alter table public.battles alter column id set default %L::uuid', v_id);
  -- the attack door reads now(): a cargo ship that sails now, and her fleet laid by it
  d := pg_temp.ship_60(100000, now());
  perform pg_temp.lie_by(a, d, now());
  perform cmd.assume_identity(c_uid);
  v_x := cmd.attack(a, d);
  alter table public.battles alter column id set default gen_random_uuid();
  v_t := clock_timestamp() - interval '130 seconds';
  v_bat := (v_x ->> 'battle_id')::uuid;
  if (v_x ->> 'ok')::boolean is not true or v_bat is null then
    raise exception 'PROOF 60 FAIL: cmd.attack did not open the battle: %', v_x;
  end if;
  -- the battle is moved back 130 s (its own rows: the clock columns and the hold), as if she had pressed Attack then: the door below reads the real clock
  select b.started_at into v_eta0 from public.battles b where b.id = v_bat;
  update public.battles b set started_at = v_t, resolves_at = v_t + make_interval(secs => 60 * (v_n + 1)), next_round_at = v_t + interval '60 seconds' where b.id = v_bat;

  v_r := world.battle(a);
  if (v_r ->> 'on')::boolean is not true or v_r ->> 'battle' is distinct from v_bat::text or v_r ->> 'status' is distinct from 'FIGHTING' or v_r ->> 'side' is distinct from 'ATTACKER'
     or v_r ->> 'stance' is distinct from 'FIGHT' or v_r -> 'may' is distinct from '["FIGHT", "FLEE"]'::jsonb or (v_r ->> 'rounds')::int is distinct from v_n or (v_r ->> 'rounds_done')::int is distinct from 0
     or v_r -> 'log' ? 'end' or v_r -> 'log' ? 'board' or v_r -> 'log' -> 'r' is distinct from '[]'::jsonb or (v_r -> 'log' ->> 'v')::int is distinct from 1
     or v_r ->> 'next_range' is distinct from 'LONG' or (v_r ->> 'next_at')::timestamptz is distinct from v_t + interval '60 seconds'
     or coalesce(v_r ->> 'word', '') not in ('weaker', 'even', 'stronger', 'far_stronger') or v_r ->> 'foe' is distinct from (select f.name from public.fleets f where f.id = d)
     or v_r ? 'outcome' or v_r ? 'loot' then
    raise exception 'PROOF 60 FAIL: the read before the first round: %', v_r;
  end if;
  perform cmd.assume_identity(c_uid2);
  if world.battle(a) is distinct from '{"on": false}'::jsonb or world.battle(a2) is distinct from '{"on": false}'::jsonb
     or cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' then
    raise exception 'PROOF 60 FAIL: another company read her battle or set a stance in it';
  end if;
  perform cmd.assume_identity(c_uid);
  if cmd.battle_stance(v_bat, 'RUN') ->> 'error_code' is distinct from 'E_BAD_STANCE' or cmd.battle_stance(v_bat, null) ->> 'error_code' is distinct from 'E_BAD_STANCE'
     or cmd.battle_stance(v_bat, 'PAY') ->> 'error_code' is distinct from 'E_BAD_STANCE' or cmd.battle_stance(gen_random_uuid(), 'FLEE') ->> 'error_code' is distinct from 'E_NO_BATTLE'
     or exists (select 1 from public.battle_stances) or exists (select 1 from public.battle_rounds) then
    raise exception 'PROOF 60 FAIL: a refused stance wrote a row or fought a round';
  end if;
  -- FIGHT, the stance she holds: it advances (two rounds are due by the real clock) and writes no row
  v_x := cmd.battle_stance(v_bat, 'FIGHT');
  if (v_x ->> 'ok')::boolean is not true or (v_x ->> 'round_next')::int is distinct from 3 or (v_x ->> 'next_at')::timestamptz is distinct from v_t + interval '180 seconds'
     or (select count(*) from public.battle_rounds r where r.battle_id = v_bat) is distinct from 2 or exists (select 1 from public.battle_stances) then
    raise exception 'PROOF 60 FAIL: the door with the stance she holds: %, % rounds, % stance rows', v_x, (select count(*) from public.battle_rounds r where r.battle_id = v_bat), (select count(*) from public.battle_stances);
  end if;
  -- FLEE: kept, from round 3; again: nothing more
  v_x := cmd.battle_stance(v_bat, 'FLEE');
  v_r := cmd.battle_stance(v_bat, 'FLEE');
  if (v_x ->> 'ok')::boolean is not true or v_x ->> 'stance' is distinct from 'FLEE' or (v_r ->> 'ok')::boolean is not true
     or (select count(*) from public.battle_stances s where s.battle_id = v_bat and s.fleet_id = a and s.stance = 'FLEE' and s.set_at > v_t + interval '120 seconds' and s.set_at < v_t + interval '180 seconds') is distinct from 1
     or (select count(*) from public.battle_stances) is distinct from 1 or (select count(*) from public.battle_rounds r where r.battle_id = v_bat) is distinct from 2 then
    raise exception 'PROOF 60 FAIL: Flee through the door: % then %, stances %', v_x, v_r, (select jsonb_agg(to_jsonb(s)) from public.battle_stances s);
  end if;
  v_r := world.battle(a);
  if v_r ->> 'stance' is distinct from 'FLEE' or (v_r ->> 'rounds_done')::int is distinct from 2 or jsonb_array_length(v_r -> 'log' -> 'r') is distinct from 2 or v_r -> 'log' ? 'end' or v_r -> 'log' ? 'board'
     or v_r ->> 'next_range' is distinct from (public.wc('fight_ranges') -> 2 ->> 0) or v_r ->> 'status' is distinct from 'FIGHTING'
     or exists (select 1 from jsonb_array_elements(v_r -> 'log' -> 'r') e where jsonb_array_length(e) is distinct from 14 or jsonb_typeof(e -> 13) is distinct from 'null')
     -- her deck: her shots are the side that closed's, her hull is hers
     or (v_r -> 'log' -> 'r' -> 0 ->> 3)::int is distinct from (select (r."row" -> 'b' ->> 'fired')::int from public.battle_rounds r where r.battle_id = v_bat and r.g = 1)
     or (v_r -> 'log' -> 'r' -> 1 ->> 10)::numeric is distinct from (select round((r."row" -> 'b' ->> 'left')::numeric, 1) from public.battle_rounds r where r.battle_id = v_bat and r.g = 2) then
    raise exception 'PROOF 60 FAIL: the read between rounds: %', v_r;
  end if;
  -- the job fights on under her last stance (she is gone: the offline case): round 3 at its instant, her guns silent
  v_m3 := public.tick_battles(v_t + interval '180 seconds');
  if not exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r.g = 3 and r."row" ? 'b_flee' and (r."row" -> 'b' ->> 'fired')::int = 0)
     or exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r.g <= 2 and r."row" ? 'b_flee') then
    raise exception 'PROOF 60 FAIL: the job did not fight round 3 under the stance the door kept: %', (select jsonb_agg(r."row" order by r.g) from public.battle_rounds r where r.battle_id = v_bat);
  end if;
  raise notice 'PASS: STANCE_DOOR — the door advances first (two rounds were due by the real clock: both logged under FIGHT), keeps FLEE from round 3 (one row, set between the two instants), writes nothing for the stance she holds; the job then fights round 3 with her guns silent (the offline case: her last stance stands); E_BAD_STANCE (a bad word, none, PAY by the side that attacked), E_NO_BATTLE, E_NOT_YOUR_BATTLE';

  -- to its end by the job, an hour on; then nothing closes twice. HER FLEE MAY HAVE GOT HER AWAY IN ROUND 3 ITSELF (the roll is the world's own dice): then the job's round-3 call
  -- above is the one that closed it, and the call an hour on closes nothing. Either way it is closed by exactly one of the two.
  v_m := v_m3 + public.tick_battles(v_t + interval '1 hour');
  select count(*) into v_i from public.events e where e.player_id = p and e.kind = 'BATTLE_REPORT' and (e.payload ->> 'battle_id')::uuid = v_bat;
  v_x := cmd.battle_stance(v_bat, 'FIGHT');
  if v_m is distinct from 1 or v_i is distinct from 1 or v_x ->> 'error_code' is distinct from 'E_BATTLE_OVER'
     or (select b.status from public.battles b where b.id = v_bat) not in ('RESOLVED', 'BROKEN_OFF')
     or public.tick_battles(v_t + interval '2 hours') is distinct from 0 or public.battle_resolve(v_bat, v_t + interval '2 hours') is not false or public.battle_advance(v_bat, v_t + interval '2 hours') is distinct from 0
     or (select count(*) from public.events e where e.player_id = p and e.kind = 'BATTLE_REPORT' and (e.payload ->> 'battle_id')::uuid = v_bat) is distinct from 1
     or (select count(*) from public.ledger l where l.player_id = p and l.kind = 'LOOT') > 1
     or (select count(*) from public.battle_rounds r where r.battle_id = v_bat) is distinct from (select (b.result ->> 'rounds_fought')::int from public.battles b where b.id = v_bat)
     or exists (select 1 from public.fleets f where f.id in (a, d) and (f.busy_until is not null or f.status = 'IN_BATTLE')) then
    raise exception 'PROOF 60 FAIL: the close, or a retry: closed %, reports %, the door after %, battle %', v_m, v_i, v_x, (select to_jsonb(b) - 'sheet' from public.battles b where b.id = v_bat);
  end if;
  raise notice 'PASS: CLOSED_ONCE — the job closes it once; a retry of the job, the closer, the advance and the door (E_BATTLE_OVER, and the battle stays closed) writes nothing: one report, at most one LOOT row, % rounds, both fleets free',
    (select count(*) from public.battle_rounds r where r.battle_id = v_bat);

  v_r := world.battle(a);
  if v_r ->> 'status' not in ('RESOLVED', 'BROKEN_OFF') or coalesce(v_r -> 'log' ->> 'end', '') not in ('A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK')
     or not v_r ? 'outcome' or not v_r ? 'loot' or not v_r ? 'crew_lost' or v_r -> 'next_at' is distinct from 'null'::jsonb
     or jsonb_array_length(v_r -> 'log' -> 'r') is distinct from (select count(*)::int from public.battle_rounds r where r.battle_id = v_bat)
     or (v_r ->> 'loot')::bigint is distinct from (select (b.result ->> 'loot')::bigint from public.battles b where b.id = v_bat)
     or jsonb_array_length(v_r -> 'log' -> 'after') is distinct from jsonb_array_length(v_r -> 'log' -> 'you')
     -- her hull after is the hull her ships have
     or (select sum((e ->> 1)::numeric) from jsonb_array_elements(v_r -> 'log' -> 'after') e) is distinct from (select sum(round(s.durability, 2)) from public.ships s where s.fleet_id = a) then
    raise exception 'PROOF 60 FAIL: the read of a closed battle: %', v_r;
  end if;
  if has_function_privilege('anon', 'cmd.battle_stance(uuid,text)', 'execute') or has_function_privilege('anon', 'world.battle(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.battle_stance(uuid,text)', 'execute') or not has_function_privilege('authenticated', 'world.battle(uuid)', 'execute')
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array['cmd.battle_stance(uuid,text)'::regprocedure, 'world.battle(uuid)'::regprocedure])) is distinct from 2 then
    raise exception 'PROOF 60 FAIL: the doors'' grants or registry rows';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  if cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_IN_USE' or (world.battle(a) ->> 'on')::boolean is not true then
    raise exception 'PROOF 60 FAIL: with the switch off again the door did not refuse, or her closed battle could not be read';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NO_HOUSE' or world.battle(a) is distinct from '{"on": false}'::jsonb then
    raise exception 'PROOF 60 FAIL: a caller with no house set a stance or read a battle';
  end if;
  raise notice 'PASS: BATTLE_READ — before the first round (the word, the next range, no round, no ending), between rounds (two rows of 14 cells from her deck, her stance FLEE, no ending and no boarding told early), closed (% : the end, the loot %, the hands, her hull after is the hull her ships have); another company and a caller with no house read nothing; the doors are authenticated-only and registered once each',
    v_r -> 'log' ->> 'end', v_r ->> 'loot';

  -- ══ STANDING_ORDER: a defender's opening stance. No door opens a battle on a company (NO_PVP above), so the sheet is this proof's own rows ══
  perform cmd.assume_identity(c_uid2);
  if public.battle_opening_stance(a2) is distinct from 'FIGHT' or public.battle_opening_stance(d2) is distinct from 'FIGHT' then
    raise exception 'PROOF 60 FAIL: with no standing order the opening stance is not FIGHT';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';
  v_x := cmd.raid_order(a2, 'FLEE');
  insert into public.fleet_raid_orders (fleet_id, raid_order) values (d2, 'FLEE');   -- a row no door would write: a ship of the world still fights
  if (v_x ->> 'ok')::boolean is not true or public.battle_opening_stance(a2) is distinct from 'FLEE' or public.battle_opening_stance(d2) is distinct from 'FIGHT' then
    raise exception 'PROOF 60 FAIL: lit, the opening stance is not her standing order, or a ship of the world took one: %', v_x;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';
  if public.battle_opening_stance(a2) is distinct from 'FIGHT' then
    raise exception 'PROOF 60 FAIL: with standing orders dark a standing order opened a battle';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';
  v_t := date_trunc('second', clock_timestamp()) - interval '1 day';
  -- the fight's seed is the battle's id: the first of 40 in which she does not slip at first sight, so a round is fought
  for v_i in 1 .. 40 loop
    v_bat := ('00000000-0357-4000-8000-0000000c' || lpad(v_i::text, 4, '0'))::uuid;
    insert into public.battles (id, kind, site, started_at, resolves_at) values (v_bat, 'ATTACK', '{"lat": 0, "lon": 0}'::jsonb, v_t, v_t + make_interval(secs => 60 * (v_n + 1)));
    insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_bat, a, 'ATTACKER', v_t, v_t), (v_bat, a2, 'DEFENDER', v_t, v_t);
    perform public.battle_sheet_freeze(v_bat, v_t);
    v_m := public.battle_advance(v_bat, v_t + interval '125 seconds');
    exit when v_m >= 1;
    delete from public.battles b where b.id = v_bat;
  end loop;
  v_r := world.battle(a2);
  if (select jsonb_agg(jsonb_build_array(s.fleet_id, s.set_at, s.stance)) from public.battle_stances s where s.battle_id = v_bat) is distinct from jsonb_build_array(jsonb_build_array(a2, v_t, 'FLEE'))
     or exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and (not r."row" ? 'flee' or (r."row" -> 'a' ->> 'fired')::int is distinct from 0))
     or v_m < 1
     or v_r ->> 'side' is distinct from 'DEFENDER' or v_r ->> 'stance' is distinct from 'FLEE' or v_r -> 'may' is distinct from '["FIGHT", "FLEE", "PAY"]'::jsonb
     or jsonb_array_length(v_r -> 'log' -> 'r') is distinct from v_m or v_r -> 'log' ? 'end' then
    raise exception 'PROOF 60 FAIL: a sheet under her standing order: % rounds, stances %, read %', v_m, (select jsonb_agg(to_jsonb(s)) from public.battle_stances s where s.battle_id = v_bat), v_r;
  end if;
  raise notice 'PASS: STANDING_ORDER — a company''s FLEE (0353) is her opening stance while standing orders are lit, FIGHT while they are dark; a ship of the world fights whatever row stands; on a sheet this proof wrote (no door opens a battle on a company) the stance is kept at the open and % round(s) are fought under it: not a shot of hers, her chance on each row; her read says side DEFENDER, stance FLEE, and may PAY', v_m;
  delete from public.battles b where b.id = v_bat;
  update public.world_config set value = 'false'::jsonb where key in ('raid_orders_enabled', 'attack_enabled');

  -- ══ HOLD_FREE: a company's voyage of ten quiet days, held for 600 s at the end of day 3 (voyage.hold, as a battle holds her) ══
  v_seas := array['', '', '', '', '', '', '', '', '', ''];
  v_t := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' + interval '2 hours';
  v_hold_h := 600 * v_k / 3600;
  v_u := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, false);                 -- the twin never held
  v_h := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, false, 600);            -- held
  v_o := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, true, 600);             -- held, under the old bodies
  v_c := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, false, 600, 200);       -- held, and the hold cut at 200 s
  if (v_h ->> 'n_days')::int is distinct from (v_u ->> 'n_days')::int or v_h -> 'kinds' is distinct from v_u -> 'kinds' or v_h -> 'ships' is distinct from v_u -> 'ships'
     or (v_h -> 'fleet') - 'busy_until' is distinct from (v_u -> 'fleet') - 'busy_until' or v_h -> 'purse' is distinct from v_u -> 'purse' or v_h -> 'ledger' is distinct from v_u -> 'ledger' or v_h -> 'wages' is distinct from v_u -> 'wages'
     or (v_h ->> 'eta')::timestamptz is distinct from (v_u ->> 'eta')::timestamptz + interval '600 seconds' or (v_h ->> 'total_days')::int is distinct from (v_u ->> 'n_days')::int
     or (v_h ->> 'arrival_at')::timestamptz is distinct from (v_h ->> 'eta')::timestamptz or (v_h ->> 'delay')::numeric is distinct from v_hold_h
     or (v_h ->> 'nm_mid_hold')::numeric is distinct from (v_h ->> 'nm_at_hold')::numeric or (v_h ->> 'nm_end_hold')::numeric is distinct from (v_h ->> 'nm_at_hold')::numeric
     or (v_h ->> 'nm_60s_after')::numeric <= (v_h ->> 'nm_at_hold')::numeric or (v_h ->> 'days_mid_hold')::int is distinct from 3
     -- every day from the held one on ends 600 s later; the days before do not move
     or exists (select 1 from jsonb_array_elements(v_h -> 'days') x join jsonb_array_elements(v_u -> 'days') y on (y ->> 'd')::int = (x ->> 'd')::int
                 where (x ->> 'd')::int < voyage.hold_floor() and x ->> 'kind' <> 'LANDFALL'
                   and (x ->> 'at')::timestamptz is distinct from (y ->> 'at')::timestamptz + case when (x ->> 'd')::int >= 4 then interval '600 seconds' else interval '0' end) then
    raise exception 'PROOF 60 FAIL: A HOLD THAT BURNS NOTHING: held % days (unheld %), eta % (unheld %), delay %, total_days %, miles % % % %', v_h ->> 'n_days', v_u ->> 'n_days', v_h ->> 'eta', v_u ->> 'eta',
      v_h ->> 'delay', v_h ->> 'total_days', v_h ->> 'nm_at_hold', v_h ->> 'nm_mid_hold', v_h ->> 'nm_end_hold', v_h ->> 'nm_60s_after';
  end if;
  -- BEFORE THIS FILE the same hold cost days: the old bodies settle more days, drink more and owe more
  if (v_o ->> 'n_days')::int is distinct from (v_u ->> 'n_days')::int + ceil(((v_u ->> 'n_days')::int * 24 + v_hold_h) / 24)::int - (v_u ->> 'n_days')::int
     or (v_o ->> 'n_days')::int <= (v_u ->> 'n_days')::int or (v_o ->> 'eta')::timestamptz is distinct from (v_h ->> 'eta')::timestamptz
     or (select sum((s ->> 'water_t')::numeric) from jsonb_array_elements(v_o -> 'ships') s) >= (select sum((s ->> 'water_t')::numeric) from jsonb_array_elements(v_h -> 'ships') s)
     or (v_o ->> 'wages')::numeric <= (v_h ->> 'wages')::numeric then
    raise exception 'PROOF 60 FAIL: under the old bodies the hold did not cost days: % days (unheld %), water % against %', v_o ->> 'n_days', v_u ->> 'n_days',
      (select sum((s ->> 'water_t')::numeric) from jsonb_array_elements(v_o -> 'ships') s), (select sum((s ->> 'water_t')::numeric) from jsonb_array_elements(v_h -> 'ships') s);
  end if;
  -- a hold cut at 200 s: she stood 200 s, sails on from the same mile, lands 200 s late, the same days
  if (v_c ->> 'n_days')::int is distinct from (v_u ->> 'n_days')::int or v_c -> 'kinds' is distinct from v_u -> 'kinds' or v_c -> 'ships' is distinct from v_u -> 'ships' or v_c -> 'wages' is distinct from v_u -> 'wages'
     or (v_c ->> 'eta')::timestamptz is distinct from (v_u ->> 'eta')::timestamptz + interval '200 seconds'
     or (v_c ->> 'nm_mid_hold')::numeric is distinct from (v_c ->> 'nm_at_hold')::numeric or (v_c ->> 'nm_end_hold')::numeric is distinct from (v_c ->> 'nm_at_hold')::numeric
     or (v_c ->> 'nm_60s_after')::numeric is distinct from (v_h ->> 'nm_60s_after')::numeric then
    raise exception 'PROOF 60 FAIL: a hold cut at 200 s: % days, eta % (unheld %), miles % % % % (uncut 60 s after: %)', v_c ->> 'n_days', v_c ->> 'eta', v_u ->> 'eta',
      v_c ->> 'nm_at_hold', v_c ->> 'nm_mid_hold', v_c ->> 'nm_end_hold', v_c ->> 'nm_60s_after', v_h ->> 'nm_60s_after';
  end if;
  -- a fair wind on day 5, after the hold: the days, the kinds, the stores and the wages are the unheld twin's (the wind finds nothing to give back there); held, it may give the
  -- hold's own hours back (voyage.settle is not cut), and she lands earlier by exactly that gain
  v_seas[5] := 'FAIR_WIND';
  v_w := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, false);
  v_x := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, false, 600);
  v_secs := (select coalesce(sum((e -> 'payload' ->> 'hours_gained')::numeric), 0) from jsonb_array_elements(v_x -> 'days') e where e ->> 'kind' = 'FAIR_WIND') * 3600 / v_k;
  if (v_x ->> 'n_days')::int is distinct from (v_w ->> 'n_days')::int or v_x -> 'kinds' is distinct from v_w -> 'kinds' or v_x -> 'ships' is distinct from v_w -> 'ships' or v_x -> 'wages' is distinct from v_w -> 'wages'
     or (v_x -> 'fleet') - 'busy_until' is distinct from (v_w -> 'fleet') - 'busy_until' or v_secs <= 0
     or (v_x ->> 'eta')::timestamptz is distinct from (v_w ->> 'eta')::timestamptz + make_interval(secs => (600 - v_secs)::double precision) then
    raise exception 'PROOF 60 FAIL: a fair wind after a hold: % days (unheld %), gained % s, eta % (unheld %)', v_x ->> 'n_days', v_w ->> 'n_days', v_secs, v_x ->> 'eta', v_w ->> 'eta';
  end if;
  -- the arrival the game predicts (voyage.arrival_at) counts the days voyage.settle settles: with a storm on every day after the tenth, a held voyage of ten days meets none
  v_seas := array['STORM>10', 'STORM>10', 'STORM>10', 'STORM>10', 'STORM>10', 'STORM>10', 'STORM>10', 'STORM>10', 'STORM>10', 'STORM>10'];
  v_x := pg_temp.passage_60(v_hfl, v_sea, v_seas, v_t, true, false, 600);
  if (v_x ->> 'arrival_at')::timestamptz is distinct from (v_x ->> 'eta')::timestamptz or (v_x ->> 'eta')::timestamptz is distinct from (v_h ->> 'eta')::timestamptz
     or (v_x ->> 'n_days')::int is distinct from (v_u ->> 'n_days')::int then
    raise exception 'PROOF 60 FAIL: the predicted arrival of a held voyage counted days it does not have: predicted %, landed %, % days', v_x ->> 'arrival_at', v_x ->> 'eta', v_x ->> 'n_days';
  end if;
  if not pg_temp.live_60_ok() or exists (select 1 from public.voyages o where o.fleet_id = v_hfl) then
    raise exception 'PROOF 60 FAIL: a passage outlived its rollback, or the old bodies stayed';
  end if;
  raise notice 'PASS: HOLD_FREE — a 600 s hold (% sim-hours at compression %) at the end of day 3: the held voyage and its unheld twin settle the same % days, kinds, stores, wages and purse, every day from the held one on ends 600 s later, the arrival moves by exactly 600 s, and she stands on the same mile through it. UNDER THE OLD BODIES the same hold settled % days (% more): water % t against % t, food % t against % t, wages owed % d. against % d. Cut at 200 s: the same days, 200 s late, the same mile. A fair wind after a hold: the same days, stores and wages; it gave back % s of the hold, and she lands earlier by that',
    v_hold_h, v_k, v_u ->> 'n_days', v_o ->> 'n_days', (v_o ->> 'n_days')::int - (v_u ->> 'n_days')::int,
    (select round(sum((s ->> 'water_t')::numeric), 2) from jsonb_array_elements(v_o -> 'ships') s), (select round(sum((s ->> 'water_t')::numeric), 2) from jsonb_array_elements(v_h -> 'ships') s),
    (select round(sum((s ->> 'food_t')::numeric), 2) from jsonb_array_elements(v_o -> 'ships') s), (select round(sum((s ->> 'food_t')::numeric), 2) from jsonb_array_elements(v_h -> 'ships') s),
    v_o ->> 'wages', v_h ->> 'wages', round(v_secs);
end
$p$;
