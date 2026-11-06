-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0330 — DANGER IS ONE NUMBER: voyage.sea_danger, frozen into each segment at departure. No answer changes
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Slice W15 of docs/WORLD_POWERS.md (section 7.7), which is Z1 of docs/PIRATES_AND_HAVENS.md (sections 2.2, 2.3, 2.5, 7.2).
-- W17 and later make a sea more or less dangerous than it was authored. They can only do that if two things hold first: danger has ONE reader of the authored figure, and a voyage rolls the danger she departed into,
-- never today's, or the same day settled late rolls a different fight (DESIGN D.2). This file lays both. Nothing writes public.sea_pressure, so every sea's danger is its piracy_index to the digit and no roll moves.
--
-- WHAT THIS FILE ADDS:
--   public.sea_pressure    One row per sea with pressure on it: wins, decaying. EMPTY, and no body writes it. W17 is its first writer (docs/PIRATES_AND_HAVENS.md section 3.3).
--   voyage.sea_danger      THE authority: piracy_index x (1 + pressure), clamped to 0..1, four places like the column. The ONE reader of seas.piracy_index. A null p_at asks for the sea as authored, no pressure.
--   voyage.freeze_danger   Writes the figure into each segment beside its sea_id. Read by voyage.depart, the one writer of a voyage.
--   voyage.leg_danger      Reads a segment's frozen figure. THE one reading: the roll, the raid, the quote and the panel all go through it.
--   voyage.sea_band        Which band of sea_danger_bands a figure is in.
--   voyage.sea_mix(uuid, numeric)  What a sea breeds, at a figure passed in. SUPERSEDES voyage.sea_mix(uuid), dropped here: its body read piracy_index.
--   world.sea_danger       Every sea's level and reason. NOT open to a client yet: Z2 opens it with the map.
--   Two knobs: sea_pressure_decay 0.9, sea_danger_bands [0.1, 0.25, 0.4, 0.6].
--
-- THE RE-CUTS (hunks of the live bodies), each occurs once and reverses to its pre-image:
--   voyage.depart (1):       the segments are frozen as the voyage is written.
--   voyage.hazard_roll (1):  the mix is read at the leg's frozen figure.
--   voyage.settle (1):       the PIRATES arm's raiders are the leg's frozen figure x 40 x (0.5 + magnitude). Was piracy_index.
--   voyage.risk_quote (3):   each day's PIRATES share at that day's frozen figure, as the comment 0213 left there promised.
--   voyage.waters_ahead (3): the panel's mix at the run's frozen figure.
-- cmd.divert is not cut: it keeps her sailed segments whole (`e || ...`, their figure with them) and the onward water is a new voyage through voyage.depart. Proof 38 checks that.
--
-- THE VOYAGES AT SEA ARE NOT WRITTEN. A segment frozen before this file has no figure, and voyage.leg_danger reads it as the sea as authored. That is not a guess: there was no pressure before this file, so the
-- authored figure IS what she departed into. Both branches give the true answer. It also keeps 652 SAILING rows (prod, 2026-11-06) and every ARRIVED row out of this deploy, with no lock on public.voyages.
--
-- WHY THIS CHANGES NOTHING: with no row in public.sea_pressure the pressure is 0, and round(piracy_index x 1, 4) is piracy_index in value and in scale, so the frozen figure prints the same digits and every sum on it
-- has the same operands. voyage.fight and the mix's shares are fed the same numeric. Proved below for all 51 seas, the new mix byte for byte against the old body before it is dropped, and in proof 38 on real passages.
--
-- GOLD. None moves. No knob of the game moves. No switch: nothing to light, as docs/PIRATES_AND_HAVENS.md section 8 says of Z1.
--
-- DECIDED BY DEFAULT (owner may reverse): docs/dev-log/2026-11-06-danger-is-one-number.md lists them.
--
-- SELF-ASSERT: the catalog, stable reads, and one rolled-back probe (a row of the empty public.sea_pressure, gone by a raised error before the block ends). Hunks once and reversing; ACL, volatility and config unmoved;
-- no other function, no other knob, no job; one reader of piracy_index, with a positive control. THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4).
-- THE LIVE PATHS ARE PROVED IN CI: proof 38, scripts/db/proofs/38_sea_danger.sql. Red first and mutation controls: scripts/ops/harness/sea-danger/proof-0330.mjs.
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): nothing to switch off. To remove: swap this file's old and new, restore voyage.sea_mix(uuid) from 0059's head, drop what it created. Frozen `danger` keys left in
-- voyages.path are read by nothing after that.
-- VERSION: 0330 - prod head 0328 (2026-11-06). 0329 (W12, its own PR) deploys first; if it cuts any line of these hunks, this file refuses at "occurs 0 time(s)" and is rebased.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_sea  uuid;
  v_p    numeric;
  v_lvl  int;
  v_bad  text;
  v_fn_before   text;
  v_cfg_before  text;
  v_meta_before text;
  v_cron_before text;
  v_cron_after  text;
  c_keys constant text[] := array['sea_pressure_decay', 'sea_danger_bands'];
  c_new_fns constant text[] := array[
    'voyage.sea_danger(uuid,timestamp with time zone)', 'voyage.freeze_danger(jsonb,timestamp with time zone)', 'voyage.leg_danger(jsonb)', 'voyage.sea_band(numeric)',
    'voyage.sea_mix(uuid,numeric)', 'world.sea_danger()'];
  c_hunked constant text[] := array[
    'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'voyage.hazard_roll(uuid,integer)', 'voyage.settle(uuid,timestamp with time zone)', 'voyage.risk_quote(uuid)', 'voyage.waters_ahead(uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.sea_pressure') is not null or to_regprocedure('voyage.sea_danger(uuid,timestamp with time zone)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys)) then
    raise exception '0330 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('voyage.sea_mix(uuid)') is null or to_regprocedure('voyage.risk_quote(uuid)') is null then
    raise exception '0330 refuses: 0059 / 0213 (the mix, the quote) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
     and p.oid <> 'voyage.sea_mix(uuid)'::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE KNOBS AND THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('sea_pressure_decay', to_jsonb(0.9), '0330: what is left of a sea''s pressure after one hour (public.sea_pressure.value x this ^ hours since updated_at). Read by voyage.sea_danger only. Moves nothing while the table is empty.'),
    ('sea_danger_bands', '[0.1, 0.25, 0.4, 0.6]'::jsonb, '0330: the four figures of voyage.sea_danger where a sea moves one level, ascending. Read by voyage.sea_band only. The authored level stands until pressure carries the figure over one.');

  create table public.sea_pressure (
    sea_id     uuid primary key references public.seas (id),
    value      numeric not null,
    updated_at timestamptz not null default now()
  );
  comment on table public.sea_pressure is
    '0330: pressure on a sea from raids won there, decaying (docs/PIRATES_AND_HAVENS.md section 2.2). Read by voyage.sea_danger only. Empty: W17 is its first and only writer. No row means no pressure.';
  alter table public.sea_pressure enable row level security;
  revoke all on table public.sea_pressure from public, anon, authenticated;

  -- ── 2. THE AUTHORITY AND ITS LEAVES ──
  create function voyage.sea_danger(p_sea uuid, p_at timestamptz)
  returns numeric
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
    -- 0330: HOW DANGEROUS A SEA IS. THE ONE READER OF seas.piracy_index (docs/PIRATES_AND_HAVENS.md section 2.2; no second scale, 0055). In [0, 1], four places as the column, so with no pressure it IS the column,
    -- digit for digit. W17 adds its presence to the pressure here and nowhere else. A null p_at is the sea as authored: no moment, so no pressure. A voyage never rolls this: she rolls what voyage.depart froze.
    select coalesce(round(least(1, greatest(0, s.piracy_index * (1 + coalesce(
             (select sp.value * power(public.wc_num('sea_pressure_decay'), greatest(0, extract(epoch from p_at - sp.updated_at) / 3600))
                from public.sea_pressure sp where sp.sea_id = p_sea and p_at is not null), 0)))), 4), 0)
      from (select 1) one
      left join public.seas s on s.id = p_sea
  $f$;
  comment on function voyage.sea_danger(uuid, timestamptz) is
    '0330: piracy_index x (1 + pressure), clamped to 0..1, four places. The one reader of seas.piracy_index. An unknown sea is 0, as the PIRATES arm read one. p_at null: as authored.';

  create function voyage.freeze_danger(p_segments jsonb, p_at timestamptz)
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
    -- 0330: each segment carries the danger of its sea at the moment she left (docs/PIRATES_AND_HAVENS.md section 2.3), beside the speed she froze there. Order and every other key as they came.
    select coalesce(jsonb_agg(e.seg || jsonb_build_object('danger', voyage.sea_danger((e.seg->>'sea_id')::uuid, p_at)) order by e.n), '[]'::jsonb)
      from jsonb_array_elements(p_segments) with ordinality e(seg, n)
  $f$;
  comment on function voyage.freeze_danger(jsonb, timestamptz) is
    '0330: the segments with each one''s voyage.sea_danger at p_at written beside its sea_id. Read by voyage.depart only.';

  create function voyage.leg_danger(p_leg jsonb)
  returns numeric
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
    -- 0330: THE DANGER A LEG WAS FROZEN AT. A leg frozen before 0330 has no figure. There was no pressure then, so the sea as authored IS what she departed into: both branches are the truth, not a fallback.
    select coalesce((p_leg->>'danger')::numeric, voyage.sea_danger((p_leg->>'sea_id')::uuid, null))
  $f$;
  comment on function voyage.leg_danger(jsonb) is
    '0330: the one reading of a segment''s frozen danger. Read by voyage.hazard_roll, voyage.settle, voyage.risk_quote and voyage.waters_ahead.';

  create function voyage.sea_band(p_danger numeric)
  returns int
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
    select count(*)::int from jsonb_array_elements_text(public.wc('sea_danger_bands')) b(x) where b.x::numeric <= p_danger
  $f$;
  comment on function voyage.sea_band(numeric) is
    '0330: how many of sea_danger_bands a figure has reached, 0 to 4. Read by world.sea_danger only.';

  create function voyage.sea_mix(p_sea uuid, p_danger numeric)
  returns table (kind_code text, share numeric, cum_share numeric)
  language plpgsql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
-- THE one reading of "what does this water breed". Pure in (sea, figure, catalogue): no clock, no voyage,
-- no player. The bands are cumulative in `ordinal` order, exactly as 0035's flat draw is, so the
-- same rng stream keeps answering in the same direction.
-- 0330: SUPERSEDES voyage.sea_mix(uuid). The piracy figure comes in, frozen with the leg, so a raid rolls the
-- danger she departed into (docs/PIRATES_AND_HAVENS.md section 2.3). Otherwise the same body, to the character.
declare
  v_d   numeric;
  v_p   numeric := p_danger;
  v_tot numeric;
begin
  select s.danger_level::numeric / 5 into v_d
    from public.seas s where s.id = p_sea;
  -- NO_SPAGHETTI §7C: the alternative is an empty mix, and an empty mix is a draw with no answer
  -- three frames later. If the else is unacceptable it is not a branch.
  if v_d is null then
    raise exception 'E_NO_SEA_MIX: % names no sea, so what its water breeds has no answer',
      coalesce(p_sea::text, '(null)') using errcode = 'P0001';
  end if;

  select sum(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p))
    into v_tot from public.voyage_event_kinds k where k.in_sea_mix;
  if v_tot is null or v_tot <= 0 then
    raise exception 'E_NO_SEA_MIX: no kind is in the sea mix, so every hazard roll would fall off the end of the bands'
      using errcode = 'P0001';
  end if;

  return query
    select k.code,
           round(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p) / v_tot, 6),
           round(sum(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p))
                   over (order by k.ordinal rows between unbounded preceding and current row)
                 / v_tot, 6)
      from public.voyage_event_kinds k
     where k.in_sea_mix
     order by k.ordinal;
end
  $f$;
  comment on function voyage.sea_mix(uuid, numeric) is
    '0330 (supersedes voyage.sea_mix(uuid), 0055): what a sea breeds at a frozen danger figure. Read by voyage.hazard_roll, voyage.risk_quote and voyage.waters_ahead.';

  create function world.sea_danger()
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
    -- 0330: EVERY SEA'S LEVEL, one read, for the map (Z2). The number is never served. The level is the same 1 to 5 as seas.danger_level, the one src/components/ui/dangerTiers.ts words and voyage.waters_ahead serves:
    -- the authored level, moved one step each time the live figure crosses a band the authored figure is not over. `reason` is W17's: no cause exists yet.
    select coalesce(jsonb_agg(jsonb_build_object(
             'sea_code', s.code,
             'level', least(5, greatest(1, s.danger_level + voyage.sea_band(voyage.sea_danger(s.id, now())) - voyage.sea_band(voyage.sea_danger(s.id, null)))),
             'reason', null::text) order by s.code), '[]'::jsonb)
      from public.seas s
  $f$;
  comment on function world.sea_danger() is
    '0330: [{sea_code, level, reason}] for every sea. Server only until Z2 adds it to public.client_rpc_entry_points and grants it, with the screen that reads it.';

  revoke all on function voyage.sea_danger(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function voyage.freeze_danger(jsonb, timestamptz) from public, anon, authenticated;
  revoke all on function voyage.leg_danger(jsonb) from public, anon, authenticated;
  revoke all on function voyage.sea_band(numeric) from public, anon, authenticated;
  revoke all on function voyage.sea_mix(uuid, numeric) from public, anon, authenticated;
  revoke all on function world.sea_danger() from public, anon, authenticated;

  -- ── 3. PARITY FOR ALL 51 SEAS, the old body still standing: every figure and every mix, byte for byte ──
  if (select count(*) from public.seas) <> 51 then
    raise exception '0330 self-assert FAIL: this file was written for 51 seas';
  end if;
  select string_agg(s.code, ', ') into v_bad from public.seas s
   where voyage.sea_danger(s.id, now())::text <> s.piracy_index::text
      or voyage.sea_danger(s.id, null)::text <> s.piracy_index::text
      or (voyage.freeze_danger(jsonb_build_array(jsonb_build_object('sea_id', s.id)), now())->0->>'danger') <> s.piracy_index::text;
  if v_bad is not null then
    raise exception '0330 self-assert FAIL: the danger of % is not its piracy_index to the digit', v_bad;
  end if;
  select string_agg(s.code, ', ') into v_bad from public.seas s
   where (select jsonb_agg(to_jsonb(m) order by m.cum_share) from voyage.sea_mix(s.id) m)::text
         <> (select jsonb_agg(to_jsonb(m) order by m.cum_share) from voyage.sea_mix(s.id, voyage.sea_danger(s.id, now())) m)::text;
  if v_bad is not null then
    raise exception '0330 self-assert FAIL: the mix of % moved', v_bad;
  end if;
  if exists (select 1 from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int, reason text) join public.seas s on s.code = x.sea_code where x.level <> s.danger_level or x.reason is not null)
     or jsonb_array_length(world.sea_danger()) <> 51 then
    raise exception '0330 self-assert FAIL: world.sea_danger does not read as the authored levels';
  end if;

  -- ── 4. THE PROBE: a row of an empty table, rolled back by the raise at its end ──
  select s.id, s.piracy_index, s.danger_level into v_sea, v_p, v_lvl from public.seas s where s.piracy_index = (select max(x.piracy_index) from public.seas x) order by s.code limit 1;
  begin
    insert into public.sea_pressure (sea_id, value, updated_at) values (v_sea, 0.5, now());
    if voyage.sea_danger(v_sea, now()) <> round(least(1, v_p * 1.5), 4) then
      raise exception '0330 self-assert FAIL: pressure does not raise the figure';
    end if;
    if voyage.sea_danger(v_sea, now() + interval '10 hours') <> round(least(1, v_p * (1 + 0.5 * power(0.9::numeric, 10))), 4) then
      raise exception '0330 self-assert FAIL: pressure does not decay by the hour';
    end if;
    if voyage.sea_danger(v_sea, now() - interval '10 hours') <> round(least(1, v_p * 1.5), 4) then
      raise exception '0330 self-assert FAIL: pressure grows into the past';
    end if;
    if voyage.sea_danger(v_sea, null)::text <> v_p::text then
      raise exception '0330 self-assert FAIL: a null moment is not the sea as authored';
    end if;
    update public.sea_pressure set value = -3 where sea_id = v_sea;
    if voyage.sea_danger(v_sea, now()) <> 0 then
      raise exception '0330 self-assert FAIL: the figure goes below 0';
    end if;
    update public.sea_pressure set value = 100 where sea_id = v_sea;
    if voyage.sea_danger(v_sea, now()) <> 1 then
      raise exception '0330 self-assert FAIL: the figure goes above 1';
    end if;
    raise exception using errcode = 'ZY330';
  exception when sqlstate 'ZY330' then
    null;
  end;
  if exists (select 1 from public.sea_pressure) then
    raise exception '0330 self-assert FAIL: the probe row is still there';
  end if;

  -- ── 5. THE HUNKS ──
  create temp table hunks_0330 (fn text, ord int, old text, new text);
  insert into hunks_0330 values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$h$  values (p_fleet, v_player, p_segments, v_total, v_profile, p_at,
$h$,
$h$  values (p_fleet, v_player, voyage.freeze_danger(p_segments, p_at), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left
$h$),
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$    from voyage.sea_mix(v_sea) m
$h$,
$h$    from voyage.sea_mix(v_sea, voyage.leg_danger(v_leg)) m   -- 0330: the danger she departed into, frozen on the leg
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$      select coalesce(s2.piracy_index, 0) * 40 * (0.5 + h.magnitude) into v_raider
        from public.seas s2 where s2.id = (voyage.leg_at_day(v.id, d)->>'sea_id')::uuid;
$h$,
$h$      v_raider := voyage.leg_danger(voyage.leg_at_day(v.id, d)) * 40 * (0.5 + h.magnitude);   -- 0330: the danger she departed into, frozen on the leg
$h$),
  ('voyage.risk_quote(uuid)', 1,
$h$    select (voyage.leg_at_day(p_voyage, g.d)->>'sea_id')::uuid as sea, h.p_hazard as p
      from generate_series(1, voyage.total_days(p_voyage)) g(d)
$h$,
$h$    select (l.leg->>'sea_id')::uuid as sea, voyage.leg_danger(l.leg) as danger, h.p_hazard as p   -- 0330: each day at the danger frozen on its leg
      from generate_series(1, voyage.total_days(p_voyage)) g(d)
     cross join lateral voyage.leg_at_day(p_voyage, g.d) l(leg)
$h$),
  ('voyage.risk_quote(uuid)', 2,
$h$    select x.sea, coalesce((select m.share from voyage.sea_mix(x.sea) m where m.kind_code = 'PIRATES'), 0) as share
      from (select distinct d.sea from d) x
$h$,
$h$    select x.sea, x.danger, coalesce((select m.share from voyage.sea_mix(x.sea, x.danger) m where m.kind_code = 'PIRATES'), 0) as share
      from (select distinct d.sea, d.danger from d) x
$h$),
  ('voyage.risk_quote(uuid)', 3,
$h$    from d join s on s.sea = d.sea
$h$,
$h$    from d join s on s.sea = d.sea and s.danger = d.danger
$h$),
  ('voyage.waters_ahead(uuid)', 1,
$h$  v_to     numeric[] := '{}';
$h$,
$h$  v_to     numeric[] := '{}';
  v_dang   numeric[] := '{}';   -- 0330: each run's frozen danger. One voyage froze one figure per sea, so a run's first segment speaks for it
$h$),
  ('voyage.waters_ahead(uuid)', 2,
$h$      v_to   := v_to   || v_acc;
$h$,
$h$      v_to   := v_to   || v_acc;
      v_dang := v_dang || voyage.leg_danger(e);
$h$),
  ('voyage.waters_ahead(uuid)', 3,
$h$      'mix',    (select jsonb_object_agg(m.kind_code, m.share) from voyage.sea_mix(s.id) m),
$h$,
$h$      'mix',    (select jsonb_object_agg(m.kind_code, m.share) from voyage.sea_mix(s.id, v_dang[i]) m),
$h$);

  for v_h in select h.fn from hunks_0330 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0330 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0330 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0330 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0330 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0330 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  drop function voyage.sea_mix(uuid);

  -- ── 6. THE SELF-ASSERT: the catalog and stable reads. No game step. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0330 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0330 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0330 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0330 self-assert FAIL: a cron job moved';
    end if;
  end if;
  -- ONE READER (the 0184 method, with its positive control): a scan that finds nothing proves nothing, so it must find the one body that may read it.
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%piracy_index%' and p.oid <> 'voyage.sea_danger(uuid,timestamp with time zone)'::regprocedure;
  if v_bad is not null then
    raise exception '0330 self-assert FAIL: a second reader of piracy_index: %', v_bad;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'voyage.sea_danger(uuid,timestamp with time zone)'::regprocedure and p.prosrc like '%piracy_index%') then
    raise exception '0330 self-assert FAIL: the scan for piracy_index cannot see the one reader';
  end if;
  if exists (select 1 from pg_views v where v.schemaname in ('public', 'cmd', 'world', 'voyage') and v.definition like '%piracy_index%') then
    raise exception '0330 self-assert FAIL: a view reads piracy_index';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or has_table_privilege('anon', 'public.sea_pressure', 'select') or has_table_privilege('authenticated', 'public.sea_pressure', 'select') then
    raise exception '0330 self-assert FAIL: a client can reach what is new';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array(select x::regprocedure from unnest(c_new_fns) x)::oid[])) <> 'ssssss' then
    raise exception '0330 self-assert FAIL: a read is not stable';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0330 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0330 self-assert ok: DANGER IS ONE NUMBER, and it is every sea''s piracy_index to the digit. 51 seas, every mix byte for byte; % hunks once each and reversing; one reader of piracy_index; no other function, knob or job; no game step ran (proof 38 runs them). % ms',
    (select count(*) from hunks_0330), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0330;
end
$m$;
