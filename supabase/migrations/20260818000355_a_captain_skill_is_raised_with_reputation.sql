-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0355 - A CAPTAIN'S SKILL IS RAISED WITH REPUTATION  (slice R2 of docs/REPUTATION.md, sections 1.4, 1.6, 3 and 6; owner row 317)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 317: Reputation from every success, "spent on captain skills". 0352 (R1) is the earning half. This
-- file is the spending half: a step per captain per skill, bought with Reputation, worth +4 % of that skill's own value.
--
-- WHAT THIS FILE MAKES
--   THE TABLE     public.captain_trait_rank (signing, trait, rank >= 1). A row exists only for a skill a PLAYER has
--                 raised: a merchant's captain never has one. No client reads or writes it.
--   THE CEILING   public.captain_grades.max_rank: C 3, B 5, A 7, S 10 (data/captains.json, held by the world guard).
--   THE ONE ARITHMETIC  public.captain_rank_mult(rank) = 1 + rank x captain_skill_rank_pct / 100. public.crew_terms and
--                 the read both call it; nothing else multiplies by a rank.
--   THE TERM      four hunks on public.crew_terms (two in the dark arm, two in the lit arm), sliced from the live body
--                 (pg_get_functiondef, LF), each once and reversing: a left join on the table's primary key and one factor,
--                 `case when tr.rank is null then 1 else public.captain_rank_mult(tr.rank) end`, so a captain with no row
--                 reads no knob. Dark, only her JOB's row is joined (the dark arm reads nothing else of her). Every reader
--                 takes it through public.crew_terms: public.crew_pct (speed, hold, prices, crew saved, storm, supplies,
--                 goods traders), public.ship_crew_terms (fight stats), world.crew_bonuses, world.captain_stats.
--                 THE 25 % CAP DOES NOT MOVE: it is the crew's, in public.crew_pct. The factor stands after the grade's
--                 floor, so a promoted captain's steps are worth more.
--   THE READING   public.captain_skill_next(player, code, trait): the ONE reading the door refuses by and the sheet prints
--                 (as public.promotion_next is for a promotion): her step, her grade's ceiling, the next step's cost
--                 (rep_skill_base x r x (r + 1) / 2: 50, 150, 300, 500, 750, 1,050, 1,400, 1,800, 2,250, 2,750), the
--                 company's Reputation, and the refusal if there is one.
--   THE DOOR      cmd.captain_skill_up(code, trait) -> public.captain_skill_up_for(player, code, trait). It spends through
--                 public.reputation_credit(player, 'skill', -cost, ...), THE ONE PLACE THE BALANCE FALLS, writes the row,
--                 and emits CAPTAIN_SKILL {officer, name, trait, word, rank, cost}. No refund, no way back.
--                 Refusals, in this order: E_NOT_SIGNED_IN (nobody is signed in), E_NOT_SIGNED (not her captain),
--                 E_TRAIT_NOT_KNOWN (not among her grade's known skills), E_TRAIT_IDLE (nothing reads it today),
--                 E_NOT_IN_PORT (seated in a fleet that is not docked; ashore is allowed), E_TOP_RANK (at her grade's
--                 ceiling), E_NOT_IN_USE (reputation_on is false: nothing can be spent), E_NOT_ENOUGH_REPUTATION (with figures).
--   THE READ      world.captain_skills(code), STABLE, to authenticated only, as world.levels():
--                 {code, reputation, skills: [{trait, word, rank, max, pct_now, cost, in_use, can, why, why_code, figures}]}.
--   THE KNOBS     rep_skill_base 50, captain_skill_rank_pct 4.
--   THE REGISTRY  one hunk on public.client_rpc_entry_points(), +2 rows, anchored on 0162's own line
--                 `('cmd', 'promote_captain', 'text'),`: 0353 anchors on the pirate_ship_card line and 0354 on the
--                 ship_moves line, so this hunk reads the same whether or not either has been applied.
--
-- NEWS: this file posts its own UPDATE row, 'Captain skills' / '선장 스킬' (0347's law, tests/news.lint.spec.ts): raising a captain's skill with
-- Reputation is live for a player at this deploy.
--
-- SUPERSEDES (re-cut): public.crew_terms (created 0157; 0160, 0161 and 0166 cut it too, on other lines) and
-- public.client_rpc_entry_points (0162's line; many files cut it on other lines). By hunks, not whole bodies. The re-cut of
-- public.crew_terms is a no-op when the new input is absent: with no row in public.captain_trait_rank every term is what it was.
--
-- NOTHING MOVES AT THE DEPLOY: no captain has a row, so public.crew_terms answers what it answered (asserted below: OLD
-- against NEW at one instant for every fleet with a seated captain). Play moves only when a player spends.
--
-- WHERE THIS FILE LEAVES docs/REPUTATION.md (the code was followed; each is in docs/dev-log/2026-11-11-captain-skills.md):
--   * one more function than the design names, public.captain_skill_next: the door and the read must refuse by one rule.
--   * "nothing reads it today" is read from the code, not from public.trait_in_use alone: crew_effects.live is the DARK
--     arm's filter (four effects), and lit every fleet effect is read and a ship effect is read while combat_bite is on.
--     So lit, a skill is idle only when all its effects are ship effects and combat is off; dark, when it is not her job
--     or her job's effect is not live.
--   * one more refusal, E_NOT_IN_USE, when reputation_on is false: public.reputation_credit books nothing then, and a
--     step must not be given for nothing.
--   * the read serves three more fields (code, why_code, figures) so the client can print the refusal in Korean, and the
--     event carries one more (word, the skill's served word beside its code) so History needs no second read.
--   * the parity runs over every fleet that has a seated captain, not every fleet: both arms inner-join captain_seats, so
--     a fleet with none has no term in either body, and each such call would still cost three knob reads on prod.
--   * the cap probe seats three navigators, not two: two S navigators at step 10 reach 24.5 %, under the cap.
--
-- COST: public.crew_terms gains one left join on a primary key into a table that holds only players' rows; a captain with
-- no row reads no knob. The self-assert prints, and never raises on, the hot-path bound: merchant speed and hold, and
-- world.spread_effective quotes, OLD against NEW, the faster of two passes each, NEW <= OLD x 1.05 + 10 ms.
-- AFTER-CHECK: 30 minutes (it alters live play once a player spends): scripts/ops/harness/captain-skills/.
-- ROLLBACK (forward, owner only): a migration reversing the four hunks. Rank rows stay and read as nothing.
-- SELF-ASSERT: the catalog, the parity, then a probe house of this file's own rows, rolled back by a raised sentinel. No
-- table is counted or summed. The switches the probe sets (crew_bite, reputation_on) are put back by that rollback.
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Fails above 45 s.
-- LOCKS: captain_grades gains a column (ACCESS EXCLUSIVE for an instant, retried 5 times under lock_timeout); the new
-- table references public.player_officers and public.traits (a brief SHARE ROW EXCLUSIVE on each).
-- VERSION: 0355. 0353 (the fight) and 0354 (fleet room) share no function with this file but the registry, on other lines.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz := now();
  v_fn_before   text;
  v_cfg_before  text;
  v_entry       int;
  v_def         text;
  d             record;
  h             record;
  v_p           record;
  v_n           int;
  v_bad         int;
  v_fleets      int;
  v_try         int := 0;
  v_msg         text;
  v_state       text;
  v_lived       boolean := false;
  v_ok          boolean;
  v_r           jsonb;
  v_x           jsonb;
  v_old_a       jsonb;
  v_old_b       jsonb;
  v_new_a       jsonb;
  v_new_b       jsonb;
  v_old_ms      numeric;
  v_new_ms      numeric;
  v_olds_ms     numeric;
  v_news_ms     numeric;
  v_cost_note   text;
  v_pl          uuid;
  v_npc         uuid;
  v_fl          uuid;
  v_fl2         uuid;
  v_sh          uuid;
  v_sh2         uuid;
  v_lis         uuid;
  v_off         uuid;
  v_code        text;
  v_name        text;
  v_po          uuid;
  v_po2         uuid;
  v_second      text;
  v_unknown     text;
  v_word        text;
  v_lit0        numeric;
  v_dark0       numeric;
  v_rest_lit    text;
  v_rest_dark   text;
  v_lit         numeric;
  v_dark        numeric;
  v_sum         numeric;
  v_crew        jsonb;
  c_uid   constant uuid := '00000000-0355-4000-8000-000000000001';
  c_terms constant text := 'public.crew_terms(uuid,timestamp with time zone)';
  c_reg   constant text := 'public.client_rpc_entry_points()';
  c_new_fns constant text[] := array[
    'public.captain_rank_mult(integer)', 'public.captain_skill_next(uuid,text,text)',
    'public.captain_skill_up_for(uuid,text,text)', 'cmd.captain_skill_up(text,text)', 'world.captain_skills(text)'];
  c_cut_fns constant text[] := array['public.crew_terms(uuid,timestamp with time zone)', 'public.client_rpc_entry_points()'];
  c_knobs constant text[] := array['rep_skill_base', 'captain_skill_rank_pct'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);

  -- ── 0. GUARD ──
  if to_regclass('public.captain_trait_rank') is not null or to_regprocedure('public.captain_rank_mult(integer)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_knobs))
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'captain_grades' and column_name = 'max_rank') then
    raise exception '0355 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is null or to_regclass('public.reputation_balance') is null
     or not exists (select 1 from public.reputation_kinds k where k.code = 'skill' and k.sign = -1)
     or not exists (select 1 from public.world_config c where c.key = 'reputation_on') then
    raise exception '0355 refuses: the Reputation book is not in this world (0352)';
  end if;
  if to_regprocedure('public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)') is null or to_regprocedure('public.trait_in_use(text)') is null
     or to_regprocedure('public.crew_bite_on()') is null or to_regprocedure('public.combat_bite_on()') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('public.emit_event(uuid,text,jsonb)') is null
     or to_regprocedure('cmd.figures(numeric,numeric,text)') is null or to_regprocedure('public.wc_num(text)') is null
     or to_regprocedure('public.wc_int(text)') is null or to_regprocedure('world.levels()') is null
     or to_regprocedure('cmd.promote_captain(text)') is null or to_regprocedure('public.client_write_grants()') is null
     or to_regprocedure('voyage.fleet_speed_at(uuid,numeric)') is null or to_regprocedure('public.ship_hold_capacity(uuid)') is null
     or to_regprocedure('world.spread_effective(uuid,uuid,uuid,boolean)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null
     or exists (select 1 from unnest(c_cut_fns) f where to_regprocedure(f) is null) then
    raise exception '0355 refuses: a function it calls or cuts is not in this world (0157 / 0160 / 0162 / 0168 / 0325 / 0347)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table defs_0355 on commit drop as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
         (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
         (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
         (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
    from unnest(c_cut_fns) f(fn);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns) f);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- ── 2. THE HUNKS (each OLD text once in its live body; NEW is OLD and one line, or three, more) ──
  create temp table hunks_0355 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0355 (fn, n, old, new) values
    -- the DARK arm: her job's step
    (c_terms, 1,
$o$             j.job_pct * public.captain_level_mult(po.id, jt.focus)
$o$,
$n$             j.job_pct * public.captain_level_mult(po.id, jt.focus)
             * case when tr.rank is null then 1 else public.captain_rank_mult(tr.rank) end   -- 0355 (R2): her job's step; no row reads no knob
$n$),
    (c_terms, 2,
$o$        join public.trait_effects te on te.trait = j.job
$o$,
$n$        join public.trait_effects te on te.trait = j.job
        left join public.captain_trait_rank tr on tr.player_officer_id = po.id and tr.trait = j.job   -- 0355 (R2): a merchant's captain never has a row
$n$),
    -- the LIT arm: the step of each skill she uses, after her grade's floor
    (c_terms, 3,
$o$             * te.mult * public.captain_level_mult(po.id, t.focus)
$o$,
$n$             * te.mult * public.captain_level_mult(po.id, t.focus)
             * case when tr.rank is null then 1 else public.captain_rank_mult(tr.rank) end   -- 0355 (R2): the skill's step; no row reads no knob
$n$),
    (c_terms, 4,
$o$        join public.trait_effects te on te.trait = ca.trait
$o$,
$n$        join public.trait_effects te on te.trait = ca.trait
        left join public.captain_trait_rank tr on tr.player_officer_id = po.id and tr.trait = ca.trait   -- 0355 (R2): a merchant's captain never has a row
$n$),
    -- THE REGISTRY, anchored on 0162's own line (0353 and 0354 cut other lines)
    (c_reg, 1,
$o$      ('cmd',         'promote_captain',       'text'),
$o$,
$n$      ('cmd',         'promote_captain',       'text'),
      -- 0355 (R2): one captain's skills with what the next step costs, and the step bought with Reputation.
      ('world',       'captain_skills',        'text'),
      ('cmd',         'captain_skill_up',      'text, text'),
$n$);
  for d in select * from defs_0355 order by fn loop
    for h in select * from hunks_0355 x where x.fn = d.fn order by x.n loop
      v_n := (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0355 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, d.fn, v_n;
      end if;
    end loop;
  end loop;

  -- ── 3. OLD, KEPT UNDER A pg_temp NAME (0166's method), AND THE COST OF OLD, BEFORE ANYTHING MOVES ──
  execute replace((select x.def from defs_0355 x where x.fn = c_terms),
                  'CREATE OR REPLACE FUNCTION public.crew_terms(', 'CREATE FUNCTION pg_temp.crew_terms_old_0355(');
  if to_regprocedure('pg_temp.crew_terms_old_0355(uuid,timestamp with time zone)') is null then
    raise exception '0355: could not name the old copy of public.crew_terms';
  end if;
  execute $f$
create function pg_temp.pass_0355(p_what text) returns jsonb language plpgsql as $body$
-- 0355: ONE PASS of the hot path, on merchant fleets that have a seated captain (a fixed sample, by id), stopped at 1 s.
-- 'ships': the fleet's speed and her flagship's hold. 'quotes': world.spread_effective for goods at her port, 200 at most.
-- Every function called is STABLE. Returns {ms, n}.
declare
  r    record;
  x    numeric;
  t0   timestamptz := clock_timestamp();
  v_n  int := 0;
begin
  if p_what = 'ships' then
    for r in select f.id as fleet, (select s.id from public.ships s where s.fleet_id = f.id order by s.is_flagship desc, s.id limit 1) as ship
               from public.fleets f join public.players pl on pl.id = f.player_id and pl.is_npc
              where exists (select 1 from public.ships s join public.captain_seats cs on cs.ship_id = s.id where s.fleet_id = f.id)
              order by f.id limit 60 loop
      exit when clock_timestamp() - t0 > interval '1 second';
      x := voyage.fleet_speed_at(r.fleet, null);
      x := public.ship_hold_capacity(r.ship);
      v_n := v_n + 1;
    end loop;
  else
    for r in select q.fleet, q.port, q.good
               from (select f.id as fleet, f.port_id as port, pg.good_id as good, row_number() over (partition by f.id order by pg.good_id) as k
                       from public.fleets f join public.players pl on pl.id = f.player_id and pl.is_npc
                       join public.port_goods pg on pg.port_id = f.port_id
                      where exists (select 1 from public.ships s join public.captain_seats cs on cs.ship_id = s.id where s.fleet_id = f.id)) q
              where q.k <= 4 order by q.fleet, q.good limit 200 loop
      exit when clock_timestamp() - t0 > interval '1 second';
      x := world.spread_effective(r.port, r.good, r.fleet, false);
      v_n := v_n + 1;
    end loop;
  end if;
  return jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - t0) * 1000, 3), 'n', v_n);
end
$body$
  $f$;
  begin   -- a measurement, never a gate: whatever stops it is printed
    v_old_a := pg_temp.pass_0355('ships');  v_old_b := pg_temp.pass_0355('ships');
    v_x     := pg_temp.pass_0355('quotes'); v_r     := pg_temp.pass_0355('quotes');
    v_old_ms  := least((v_old_a ->> 'ms')::numeric / nullif((v_old_a ->> 'n')::int, 0), (v_old_b ->> 'ms')::numeric / nullif((v_old_b ->> 'n')::int, 0));
    v_olds_ms := least((v_x ->> 'ms')::numeric / nullif((v_x ->> 'n')::int, 0), (v_r ->> 'ms')::numeric / nullif((v_r ->> 'n')::int, 0));
    v_cost_note := format('%s fleets, %s quotes', v_old_a ->> 'n', v_x ->> 'n');
  exception when others then
    v_cost_note := 'OLD not measured (' || left(sqlerrm, 90) || ')';
  end;

  -- ── 4. THE CEILING: captain_grades.max_rank (0162's lock-retry) ──
  loop
    v_try := v_try + 1;
    begin
      alter table public.captain_grades add column max_rank int check (max_rank >= 1);
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0355 self-assert FAIL: LOCK CONTENTION, not a result: captain_grades could not be altered in 5 tries (%: %). Re-run the push.', v_state, v_msg;
      end if;
      perform pg_sleep(0.5);
    end;
  end loop;
  update public.captain_grades g set max_rank = w.max_rank
    from (values ('C', 3), ('B', 5), ('A', 7), ('S', 10)) w(code, max_rank) where w.code = g.code;
  comment on column public.captain_grades.max_rank is
    '0355 (R2): the most steps a captain of this grade holds in one skill (public.captain_trait_rank). A promotion keeps every step and raises the ceiling. data/captains.json.';

  -- ── 5. THE TABLE ──
  create table public.captain_trait_rank (
    player_officer_id uuid not null references public.player_officers(id) on delete cascade,
    trait             text not null references public.traits(code),
    rank              int  not null check (rank >= 1),
    primary key (player_officer_id, trait)
  );
  comment on table public.captain_trait_rank is
    '0355 (R2): the steps a PLAYER has bought for one skill of one signing, with Reputation. A row exists only once a step is bought: a merchant''s captain never has one. Not a value: the value stays public.crew_terms, and the multiplier is public.captain_rank_mult alone. Written by public.captain_skill_up_for alone.';
  alter table public.captain_trait_rank enable row level security;
  revoke all on table public.captain_trait_rank from public, anon, authenticated;

  -- ── 6. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('rep_skill_base', to_jsonb(50),
     '0355: the Reputation the first step of a captain''s skill costs. Step r costs this x r x (r + 1) / 2: 50, 150, 300, 500, 750, 1050, 1400, 1800, 2250, 2750. Read by public.captain_skill_next.'),
    ('captain_skill_rank_pct', to_jsonb(4),
     '0355: per cent of a skill''s own value one step adds (public.captain_rank_mult: 1 + steps x this / 100). Read only for a captain who has a step: a merchant''s captain reads none.');

  -- ── 7. THE ONE ARITHMETIC ──
  execute $f$
create function public.captain_rank_mult(p_rank int)
returns numeric
language sql
stable
set search_path = public, pg_temp
as $body$
  -- 0355 (R2): THE ONE ARITHMETIC of a skill's steps: its value x (1 + steps x captain_skill_rank_pct / 100).
  -- public.crew_terms calls it only for a captain who has a row; world.captain_skills prints the same figure.
  select 1 + p_rank * public.wc_num('captain_skill_rank_pct') / 100
$body$
  $f$;

  -- ── 8. THE ONE READING ──
  execute $f$
create function public.captain_skill_next(p_player uuid, p_code text, p_trait text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0355 (R2): WHAT THE NEXT STEP OF ONE SKILL OF ONE CAPTAIN NEEDS: the one reading the door refuses by and the sheet
-- prints. {ok, officer, name, signing, trait, word, rank, max, cost, reputation, in_use} and, refused,
-- {error_code, error_message, fixes, figures}. Server-only.
declare
  v_code  text := upper(btrim(coalesce(p_code, '')));
  v_trait text := upper(btrim(coalesce(p_trait, '')));
  v_po    uuid;
  v_off   uuid;
  v_name  text;
  g       record;
  v_word  text;
  v_rank  int;
  v_max   int;
  v_cost  int;
  v_bal   int;
  v_live  boolean;
  v_at    record;
  v_up    record;
  v_out   jsonb;
begin
  select po.id, o.id, o.name into v_po, v_off, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id
    join public.players pl on pl.id = po.player_id and not pl.is_npc
   where po.player_id = p_player and o.code = v_code;
  if v_po is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'You do not keep that captain.', 'fixes', jsonb_build_array('(hire her at an inn first)'));
  end if;
  select gr.code, gr.ord, gr.known, gr.max_rank into g
    from public.captain_profile cp
    left join public.captain_state st on st.player_officer_id = v_po
    join public.captain_grades gr on gr.code = coalesce(st.grade, cp.grade)
   where cp.officer_id = v_off;
  select t.word into v_word
    from public.captain_traits ct join public.traits t on t.code = ct.trait
   where ct.officer_id = v_off and ct.trait = v_trait and ct.ord <= g.known;
  if v_word is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_TRAIT_NOT_KNOWN',
      'error_message', format('%s does not know %s.', v_name, coalesce(nullif(v_trait, ''), 'that skill')), 'fixes', '[]'::jsonb);
  end if;
  v_rank := coalesce((select r.rank from public.captain_trait_rank r where r.player_officer_id = v_po and r.trait = v_trait), 0);
  v_max  := coalesce(g.max_rank, 0);
  v_cost := case when v_rank < v_max then public.wc_int('rep_skill_base') * (v_rank + 1) * (v_rank + 2) / 2 end;
  v_bal  := coalesce((select b.balance from public.reputation_balance b where b.player_id = p_player), 0);
  -- DOES A RULE READ IT TODAY (public.crew_terms' own two arms). Dark: her job alone, for a live effect. Lit: every skill
  -- she uses; a fleet effect always has its reader, a ship effect is read while combat_bite is on (public.crew_pct).
  v_live := case when not public.crew_bite_on()
                 then public.trait_in_use(v_trait) and exists (select 1 from public.captain_job j where j.officer_id = v_off and j.job = v_trait)
                 else exists (select 1 from public.trait_effects te join public.crew_effects ce on ce.code = te.effect
                               where te.trait = v_trait and (ce.scope = 'fleet' or public.combat_bite_on())) end;
  v_out := jsonb_build_object('ok', true, 'officer', v_code, 'name', v_name, 'signing', v_po, 'trait', v_trait, 'word', v_word,
                              'rank', v_rank, 'max', v_max, 'cost', v_cost, 'reputation', v_bal, 'in_use', v_live);
  if not v_live then
    return v_out || jsonb_build_object('ok', false, 'error_code', 'E_TRAIT_IDLE',
      'error_message', format('%s does nothing yet.', v_word), 'fixes', '[]'::jsonb);
  end if;
  select s.name as ship, f.status into v_at
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id join public.fleets f on f.id = s.fleet_id
   where cs.player_officer_id = v_po;
  if v_at.ship is not null and v_at.status <> 'DOCKED' then
    return v_out || jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_PORT',
      'error_message', format('%s is at sea aboard %s. A skill is raised in port.', v_name, v_at.ship),
      'fixes', jsonb_build_array('(wait until her ship is docked)'));
  end if;
  if v_rank >= v_max then
    select gr.code, gr.max_rank into v_up from public.captain_grades gr where gr.ord > g.ord and gr.max_rank > v_max order by gr.ord limit 1;
    return v_out || jsonb_build_object('ok', false, 'error_code', 'E_TOP_RANK',
      'error_message', case when v_up.code is null then format('%s is %s of %s.', v_word, v_rank, v_max)
                            else format('%s is %s of %s: %s %s captain reaches %s.', v_word, v_rank, v_max,
                                        case when left(v_up.code, 1) in ('A', 'E', 'F', 'H', 'I', 'L', 'M', 'N', 'O', 'R', 'S', 'X') then 'an' else 'a' end,
                                        v_up.code, v_up.max_rank) end,
      'fixes', case when v_up.code is null then '[]'::jsonb else jsonb_build_array('(promote her)') end);
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return v_out || jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_USE',
      'error_message', 'Reputation is not in use.', 'fixes', '[]'::jsonb);
  end if;
  if v_bal < v_cost then
    return v_out || jsonb_build_object('ok', false, 'error_code', 'E_NOT_ENOUGH_REPUTATION',
      'error_message', format('Needs %s Reputation: you have %s.', v_cost, v_bal),
      'fixes', jsonb_build_array('(earn more Reputation)'), 'figures', cmd.figures(v_bal, v_cost, 'reputation'));
  end if;
  return v_out;
end
$body$
  $f$;

  -- ── 9. THE DOOR ──
  execute $f$
create function public.captain_skill_up_for(p_player uuid, p_code text, p_trait text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0355 (R2): CORE of cmd.captain_skill_up. One step of one skill of one captain, for Reputation. The rule is
-- public.captain_skill_next's; the spend is public.reputation_credit's (the one place the balance falls); the row is
-- written here and nowhere else. No refund. Server-only.
declare
  v_code  text := upper(btrim(coalesce(p_code, '')));
  v_n     jsonb;
  v_po    uuid;
  v_cost  int;
  v_rank  int;
  v_paid  int := 0;
begin
  -- one step at a time for a company: her signing and the company's balance are held, then the rule is read
  perform 1 from public.player_officers po join public.officers o on o.id = po.officer_id
    where po.player_id = p_player and o.code = v_code for update of po;
  perform 1 from public.reputation_balance b where b.player_id = p_player for update;
  v_n := public.captain_skill_next(p_player, p_code, p_trait);
  if not (v_n ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'error_code', v_n -> 'error_code', 'error_message', v_n -> 'error_message', 'fixes', v_n -> 'fixes')
           || case when v_n ? 'figures' then jsonb_build_object('figures', v_n -> 'figures') else '{}'::jsonb end;
  end if;
  v_po   := (v_n ->> 'signing')::uuid;
  v_cost := (v_n ->> 'cost')::int;
  v_rank := (v_n ->> 'rank')::int + 1;
  if v_cost > 0 then
    v_paid := public.reputation_credit(p_player, 'skill', -v_cost, null,
                jsonb_build_object('officer', v_n -> 'officer', 'trait', v_n -> 'trait', 'rank', v_rank));
    if v_paid is distinct from -v_cost then
      raise exception 'captain_skill_up_for: the spend booked % and not %: no step is given for nothing', v_paid, -v_cost using errcode = 'P0001';
    end if;
  end if;
  insert into public.captain_trait_rank (player_officer_id, trait, rank) values (v_po, v_n ->> 'trait', v_rank)
  on conflict (player_officer_id, trait) do update set rank = excluded.rank;
  perform public.emit_event(p_player, 'CAPTAIN_SKILL',
    jsonb_build_object('officer', v_n -> 'officer', 'name', v_n -> 'name', 'trait', v_n -> 'trait', 'word', v_n -> 'word', 'rank', v_rank, 'cost', v_cost));
  return jsonb_build_object('ok', true, 'officer', v_n -> 'officer', 'trait', v_n -> 'trait', 'rank', v_rank, 'max', v_n -> 'max',
    'cost', v_cost, 'reputation', (v_n ->> 'reputation')::int - v_cost,
    'sentence', format('%s: %s is now %s of %s.', v_n ->> 'name', v_n ->> 'word', v_rank, v_n ->> 'max'));
end
$body$
  $f$;
  execute $f$
create function cmd.captain_skill_up(p_code text, p_trait text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  -- 0355: the step is public.captain_skill_up_for's.
  return public.captain_skill_up_for(v_player, p_code, p_trait);
end
$body$
  $f$;

  -- ── 10. THE READ ──
  execute $f$
create function world.captain_skills(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0355 (R2): THE SKILLS OF YOUR SIGNING OF ONE CAPTAIN, each with its step, her grade's ceiling, what the steps add
-- (pct_now: public.captain_rank_mult, in per cent of the skill's own value), what the next step costs, and whether the
-- door would take it now (can) or why not (why, in the server's words; why_code; figures). Every row is
-- public.captain_skill_next's answer: the door refuses by the same reading. null: a caller who keeps no such captain.
declare
  v_player uuid := public.current_player_id();
  v_code   text := upper(btrim(coalesce(p_code, '')));
  v_po     uuid;
  v_off    uuid;
  v_known  int;
begin
  select po.id, po.officer_id into v_po, v_off
    from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = v_player and o.code = v_code;
  if v_po is null then
    return null;
  end if;
  select gr.known into v_known
    from public.captain_profile cp
    left join public.captain_state st on st.player_officer_id = v_po
    join public.captain_grades gr on gr.code = coalesce(st.grade, cp.grade)
   where cp.officer_id = v_off;
  return jsonb_build_object(
    'code', v_code,
    'reputation', coalesce((select b.balance from public.reputation_balance b where b.player_id = v_player), 0),
    'skills', (select coalesce(jsonb_agg(jsonb_build_object(
                   'trait', ct.trait, 'word', x.n -> 'word', 'rank', x.n -> 'rank', 'max', x.n -> 'max',
                   'pct_now', case when (x.n ->> 'rank')::int = 0 then 0
                                   else round((public.captain_rank_mult((x.n ->> 'rank')::int) - 1) * 100, 2) end,
                   'cost', x.n -> 'cost', 'in_use', x.n -> 'in_use', 'can', x.n -> 'ok',
                   'why', x.n -> 'error_message', 'why_code', x.n -> 'error_code', 'figures', x.n -> 'figures') order by ct.ord), '[]'::jsonb)
                 from public.captain_traits ct
                cross join lateral (select public.captain_skill_next(v_player, v_code, ct.trait) as n) x
                where ct.officer_id = v_off and ct.ord <= v_known));
end
$body$
  $f$;

  revoke all on function public.captain_rank_mult(int) from public, anon, authenticated;
  revoke all on function public.captain_skill_next(uuid, text, text) from public, anon, authenticated;
  revoke all on function public.captain_skill_up_for(uuid, text, text) from public, anon, authenticated;
  revoke all on function cmd.captain_skill_up(text, text) from public, anon;
  grant execute on function cmd.captain_skill_up(text, text) to authenticated;
  revoke all on function world.captain_skills(text) from public, anon;
  grant execute on function world.captain_skills(text) to authenticated;

  -- ── 11. THE RE-CUTS (each hunk once) ──
  for d in select * from defs_0355 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0355 x where x.fn = d.fn order by x.n loop
      v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0355 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;

  -- ── 12. THE SELF-ASSERT: the catalog ──
  for d in select * from defs_0355 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0355 x where x.fn = d.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0355 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0355 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0355 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_new_fns) f)) <> v_fn_before then
    raise exception '0355 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before
     or (select count(*) from public.world_config c where c.key = any (c_knobs)) <> array_length(c_knobs, 1) then
    raise exception '0355 self-assert FAIL: an existing world_config row moved, or a knob of this file is missing';
  end if;
  if (select string_agg(g.code || ':' || coalesce(g.max_rank::text, '-'), ',' order by g.ord) from public.captain_grades g) <> 'C:3,B:5,A:7,S:10' then
    raise exception '0355 self-assert FAIL: the ceilings are not C 3, B 5, A 7, S 10: %',
      (select string_agg(g.code || ':' || coalesce(g.max_rank::text, '-'), ',' order by g.ord) from public.captain_grades g);
  end if;
  if exists (select 1 from unnest(array['public.captain_rank_mult(integer)', 'public.captain_skill_next(uuid,text,text)', 'public.captain_skill_up_for(uuid,text,text)']) f
              cross join unnest(array['anon', 'authenticated']) r(role) where has_function_privilege(r.role, f, 'execute')) then
    raise exception '0355 self-assert FAIL: a client may call a server-only function of this file';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.captain_skills(text)'::regprocedure)
       <> (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.levels()'::regprocedure)
     or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.captain_skills(text)'::regprocedure)
       is distinct from (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.levels()'::regprocedure)
     or has_function_privilege('anon', 'world.captain_skills(text)', 'execute') then
    raise exception '0355 self-assert FAIL: the read is not STABLE, definer and granted as its sibling world.levels()';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'cmd.captain_skill_up(text,text)'::regprocedure)
       <> (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'cmd.promote_captain(text)'::regprocedure)
     or has_function_privilege('anon', 'cmd.captain_skill_up(text,text)', 'execute') then
    raise exception '0355 self-assert FAIL: the door is not granted as its sibling cmd.promote_captain';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.captain_rank_mult(integer)'::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = 'public.captain_skill_next(uuid,text,text)'::regprocedure) <> 's' then
    raise exception '0355 self-assert FAIL: the arithmetic or the reading is not STABLE';
  end if;
  if has_table_privilege('anon', 'public.captain_trait_rank', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.captain_trait_rank', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.captain_trait_rank'::regclass) then
    raise exception '0355 self-assert FAIL: a client can read or write public.captain_trait_rank, or it has no row level security';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0355 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry + 2
     or (select count(*) from public.client_rpc_entry_points() e
          where e.fn = any (array['world.captain_skills(text)'::regprocedure, 'cmd.captain_skill_up(text,text)'::regprocedure])) <> 2 then
    raise exception '0355 self-assert FAIL: the registry is not the old rows and these two';
  end if;
  -- one writer, one arithmetic: only the door writes the table; only crew_terms and the read multiply by a step; only the door spends
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'captain_trait_rank'
                and p.oid <> all (array['public.captain_skill_next(uuid,text,text)'::regprocedure, 'public.captain_skill_up_for(uuid,text,text)'::regprocedure, c_terms::regprocedure]::oid[]))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'captain_rank_mult'
                   and p.oid <> all (array[c_terms::regprocedure, 'world.captain_skills(text)'::regprocedure]::oid[]))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~* '(insert into|update|delete from) public\.captain_trait_rank'
                   and p.oid <> 'public.captain_skill_up_for(uuid,text,text)'::regprocedure)
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'reputation_credit\(' and p.prosrc ~ '''skill''') <> 1 then
    raise exception '0355 self-assert FAIL: the table has more than one writer, or the multiplier more than its two readers';
  end if;
  if world.captain_skills('ELCANO') is not null or world.captain_skills(null) is not null
     or (cmd.captain_skill_up('ELCANO', 'NAVIGATOR') ->> 'error_code') is distinct from 'E_NOT_SIGNED_IN' then
    raise exception '0355 self-assert FAIL: a caller with no company reads a sheet, or the door did not refuse E_NOT_SIGNED_IN';
  end if;

  -- ── 13. THE SELF-ASSERT: OLD = NEW public.crew_terms at one instant, for every fleet that has a seated captain ──
  select count(*), count(*) filter (where c.o is distinct from c.n) into v_fleets, v_bad
    from (select (select coalesce(string_agg(x::text, '|' order by x::text), '') from pg_temp.crew_terms_old_0355(f.fleet_id, v_t) x) as o,
                 (select coalesce(string_agg(x::text, '|' order by x::text), '') from public.crew_terms(f.fleet_id, v_t) x) as n
            from (select distinct s.fleet_id from public.captain_seats cs join public.ships s on s.id = cs.ship_id) f) c;
  if v_bad <> 0 then
    raise exception '0355 self-assert FAIL: public.crew_terms moved for % fleet(s) with no step bought', v_bad;
  end if;

  -- ── 14. THE COST OF NEW (printed; never raised) ──
  begin
    v_new_a := pg_temp.pass_0355('ships');  v_new_b := pg_temp.pass_0355('ships');
    v_x     := pg_temp.pass_0355('quotes'); v_r     := pg_temp.pass_0355('quotes');
    v_new_ms  := least((v_new_a ->> 'ms')::numeric / nullif((v_new_a ->> 'n')::int, 0), (v_new_b ->> 'ms')::numeric / nullif((v_new_b ->> 'n')::int, 0));
    v_news_ms := least((v_x ->> 'ms')::numeric / nullif((v_x ->> 'n')::int, 0), (v_r ->> 'ms')::numeric / nullif((v_r ->> 'n')::int, 0));
    v_n := (v_old_a ->> 'n')::int;
    v_cost_note := format('merchant speed + hold on %s: OLD %s ms, NEW %s ms (%s); %s world.spread_effective quotes: OLD %s ms, NEW %s ms (%s). The faster of two passes each; the bound is NEW <= OLD x 1.05 + 10 ms.',
      v_cost_note, round(v_old_ms * v_n, 2), round(v_new_ms * v_n, 2),
      case when v_new_ms * v_n <= v_old_ms * v_n * 1.05 + 10 then 'within the bound' else 'OVER THE BOUND' end,
      v_x ->> 'n', round(v_olds_ms * (v_x ->> 'n')::int, 2), round(v_news_ms * (v_x ->> 'n')::int, 2),
      case when v_news_ms * (v_x ->> 'n')::int <= v_olds_ms * (v_x ->> 'n')::int * 1.05 + 10 then 'within the bound' else 'OVER THE BOUND' end);
  exception when others then
    v_cost_note := coalesce(v_cost_note, '') || ' NEW not measured (' || left(sqlerrm, 90) || ')';
  end;

  -- ── 15. THE SELF-ASSERT: a probe house of this file's own rows, every one rolled back ──
  v_crew := (select c.value from public.world_config c where c.key = 'crew_bite');
  begin
    execute $f$
create function pg_temp.term_0355(p_fleet uuid, p_po uuid, p_trait text) returns numeric language sql as $body$
  select sum(t.value_pct) from public.crew_terms(p_fleet) t where t.player_officer_id = p_po and t.trait = p_trait
$body$
    $f$;
    execute $f$
create function pg_temp.rest_0355(p_fleet uuid, p_po uuid, p_trait text) returns text language sql as $body$
  select coalesce(string_agg(t::text, '|' order by t::text), '') from public.crew_terms(p_fleet) t
   where not (t.player_officer_id = p_po and t.trait = p_trait)
$body$
    $f$;
    update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Pericia 0355', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0355', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Pericia', v_lis);
    v_sh := public.commission_ship(v_pl, v_fl, 'barca', 'Pericia', true, true);
    -- HER: a C navigator, in the Captain's cabin, using her job and her second skill. BESIDE HER: a purser, in the trading cabin.
    select o.id, o.code, o.name into v_off, v_code, v_name
      from public.officers o join public.captain_job j on j.officer_id = o.id join public.captain_profile cp on cp.officer_id = o.id
     where j.job = 'NAVIGATOR' and cp.grade = 'C' order by o.code limit 1;
    if v_off is null then
      raise exception '0355 self-assert FAIL: the probe found no C navigator to sign';
    end if;
    select ct.trait into v_second from public.captain_traits ct where ct.officer_id = v_off and ct.ord = 2;
    select ct.trait into v_unknown from public.captain_traits ct where ct.officer_id = v_off and ct.ord = 5;   -- a C captain knows her first four
    insert into public.player_officers (player_id, officer_id) values (v_pl, v_off) returning id into v_po;
    insert into public.captain_active (player_officer_id, trait)
      select v_po, ct.trait from public.captain_traits ct where ct.officer_id = v_off and ct.ord <= 2;
    insert into public.captain_state (player_officer_id, grade, home_seen_at) values (v_po, 'C', now());
    insert into public.captain_xp (player_officer_id) values (v_po);
    perform public.captain_seat_put(v_po, v_sh, 1);
    insert into public.player_officers (player_id, officer_id)
      select v_pl, o.id from public.officers o join public.captain_job j on j.officer_id = o.id where j.job = 'PURSER' order by o.code limit 1
    returning id into v_po2;
    insert into public.captain_active (player_officer_id, trait) values (v_po2, 'PURSER');
    insert into public.captain_state (player_officer_id, grade, home_seen_at)
      select v_po2, cp.grade, now() from public.captain_profile cp join public.player_officers po on po.officer_id = cp.officer_id where po.id = v_po2;
    insert into public.captain_xp (player_officer_id) values (v_po2);
    perform public.captain_seat_put(v_po2, v_sh, 2);

    -- (a) BEFORE ANY STEP: her speed term and everything else of the fleet, lit and dark
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    v_lit0 := pg_temp.term_0355(v_fl, v_po, 'NAVIGATOR');
    v_rest_lit := pg_temp.rest_0355(v_fl, v_po, 'NAVIGATOR');
    update public.world_config set value = 'false'::jsonb where key = 'crew_bite';
    v_dark0 := pg_temp.term_0355(v_fl, v_po, 'NAVIGATOR');
    v_rest_dark := pg_temp.rest_0355(v_fl, v_po, 'NAVIGATOR');
    if v_lit0 is null or v_lit0 <= 0 or v_dark0 is null or v_dark0 <= 0 or v_rest_lit = '' or v_rest_dark = '' then
      raise exception '0355 self-assert FAIL: the probe crew has no speed term, or nothing beside it (lit %, dark %)', v_lit0, v_dark0;
    end if;

    -- (b) THE REFUSALS, each with its words (dark first: a skill that is not her job does nothing)
    v_r := public.captain_skill_up_for(v_pl, v_code, v_second);
    select t.word into v_word from public.traits t where t.code = v_second;
    if (v_r ->> 'error_code') is distinct from 'E_TRAIT_IDLE' or (v_r ->> 'error_message') is distinct from v_word || ' does nothing yet.' then
      raise exception '0355 self-assert FAIL: dark, a skill that is not her job was not refused E_TRAIT_IDLE: %', v_r;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    v_r := public.captain_skill_up_for(v_pl, 'NOBODY0355', 'NAVIGATOR');
    if (v_r ->> 'error_code') is distinct from 'E_NOT_SIGNED' or (v_r ->> 'error_message') is distinct from 'You do not keep that captain.' then
      raise exception '0355 self-assert FAIL: a captain she does not keep was not refused E_NOT_SIGNED: %', v_r;
    end if;
    v_r := public.captain_skill_up_for(v_pl, v_code, v_unknown);
    if (v_r ->> 'error_code') is distinct from 'E_TRAIT_NOT_KNOWN' or (v_r ->> 'error_message') is distinct from format('%s does not know %s.', v_name, v_unknown) then
      raise exception '0355 self-assert FAIL: a skill past her grade''s known was not refused E_TRAIT_NOT_KNOWN: %', v_r;
    end if;
    v_n := public.reputation_credit(v_pl, 'built', 40, 'probe:a');
    v_r := public.captain_skill_up_for(v_pl, lower(v_code), ' navigator ');   -- read as the verbs read it: upper-cased, trimmed
    if v_n <> 40 or (v_r ->> 'error_code') is distinct from 'E_NOT_ENOUGH_REPUTATION'
       or (v_r ->> 'error_message') is distinct from 'Needs 50 Reputation: you have 40.'
       or (v_r -> 'figures') is distinct from jsonb_build_object('have', 40, 'need', 50, 'unit', 'reputation') then
      raise exception '0355 self-assert FAIL: 40 Reputation against a step of 50 was not refused with its figures: %', v_r;
    end if;
    v_n := public.reputation_credit(v_pl, 'built', 1010, 'probe:b');
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -12.0 where id = v_fl;
    v_r := public.captain_skill_up_for(v_pl, v_code, 'NAVIGATOR');
    if (v_r ->> 'error_code') is distinct from 'E_NOT_IN_PORT'
       or (v_r ->> 'error_message') is distinct from format('%s is at sea aboard Pericia. A skill is raised in port.', v_name) then
      raise exception '0355 self-assert FAIL: a captain at sea was not refused E_NOT_IN_PORT: %', v_r;
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fl;
    update public.world_config set value = 'false'::jsonb where key = 'reputation_on';
    v_r := public.captain_skill_up_for(v_pl, v_code, 'NAVIGATOR');
    if (v_r ->> 'error_code') is distinct from 'E_NOT_IN_USE' then
      raise exception '0355 self-assert FAIL: with reputation_on false the door did not refuse E_NOT_IN_USE: %', v_r;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
    if exists (select 1 from public.captain_trait_rank r where r.player_officer_id in (v_po, v_po2))
       or exists (select 1 from public.events e where e.player_id = v_pl and e.kind = 'CAPTAIN_SKILL')
       or (select b.balance from public.reputation_balance b where b.player_id = v_pl) <> 1050 then
      raise exception '0355 self-assert FAIL: a refusal wrote a step, an event or a spend';
    end if;

    -- (c) STEP 1 THEN STEP 2: 50 then 150, the book chained, her speed term x 1.08 exactly, everything else unmoved, lit and dark
    v_r := public.captain_skill_up_for(v_pl, v_code, 'NAVIGATOR');
    v_x := public.captain_skill_up_for(v_pl, v_code, 'NAVIGATOR');
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'rank')::int <> 1 or (v_r ->> 'cost')::int <> 50 or (v_r ->> 'reputation')::int <> 1000
       or (v_x ->> 'ok')::boolean is not true or (v_x ->> 'rank')::int <> 2 or (v_x ->> 'cost')::int <> 150 or (v_x ->> 'reputation')::int <> 850
       or (v_x ->> 'sentence') is distinct from format('%s: Navigator is now 2 of 3.', v_name) then
      raise exception '0355 self-assert FAIL: steps 1 and 2 did not cost 50 then 150: % then %', v_r, v_x;
    end if;
    if (select string_agg(k.seq || ':' || k.kind || ':' || k.delta || ':' || k.balance_after, ',' order by k.seq) from public.reputation_book k where k.player_id = v_pl)
         is distinct from '1:built:40:40,2:built:1010:1050,3:skill:-50:1000,4:skill:-150:850'
       or (select b.balance || ':' || b.seq from public.reputation_balance b where b.player_id = v_pl) <> '850:4'
       or (select k.note from public.reputation_book k where k.player_id = v_pl and k.seq = 4)
            is distinct from jsonb_build_object('officer', v_code, 'trait', 'NAVIGATOR', 'rank', 2) then
      raise exception '0355 self-assert FAIL: the book is not chained 40, 1050, 1000, 850 with the step in its note';
    end if;
    set constraints public.reputation_reconciles immediate;   -- the spends reconcile
    set constraints public.reputation_reconciles deferred;
    if (select r.rank from public.captain_trait_rank r where r.player_officer_id = v_po and r.trait = 'NAVIGATOR') <> 2
       or (select string_agg((e.payload ->> 'officer') || ':' || (e.payload ->> 'name') || ':' || (e.payload ->> 'trait') || ':' || (e.payload ->> 'word') || ':' || (e.payload ->> 'rank') || ':' || (e.payload ->> 'cost'), ','
                             order by (e.payload ->> 'rank')::int)
             from public.events e where e.player_id = v_pl and e.kind = 'CAPTAIN_SKILL')
            is distinct from format('%s:%s:NAVIGATOR:Navigator:1:50,%s:%s:NAVIGATOR:Navigator:2:150', v_code, v_name, v_code, v_name) then
      raise exception '0355 self-assert FAIL: the row is not step 2, or the two CAPTAIN_SKILL events are not {officer, name, trait, word, rank, cost}';
    end if;
    v_lit := pg_temp.term_0355(v_fl, v_po, 'NAVIGATOR');
    if v_lit <> v_lit0 * 1.08 or pg_temp.rest_0355(v_fl, v_po, 'NAVIGATOR') <> v_rest_lit then
      raise exception '0355 self-assert FAIL: lit, step 2 did not make her speed term x 1.08 exactly (% from %), or another term moved', v_lit, v_lit0;
    end if;
    if public.crew_pct(v_fl, null, 'speed') * 100 <> v_lit then
      raise exception '0355 self-assert FAIL: public.crew_pct does not read her raised term: % against %', public.crew_pct(v_fl, null, 'speed') * 100, v_lit;
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'crew_bite';
    v_dark := pg_temp.term_0355(v_fl, v_po, 'NAVIGATOR');
    if v_dark <> v_dark0 * 1.08 or pg_temp.rest_0355(v_fl, v_po, 'NAVIGATOR') <> v_rest_dark then
      raise exception '0355 self-assert FAIL: dark, step 2 did not make her speed term x 1.08 exactly (% from %), or another term moved', v_dark, v_dark0;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';

    -- (d) THE READ, as she reads it
    perform cmd.assume_identity(c_uid);
    v_r := world.captain_skills(lower(v_code));
    v_x := v_r -> 'skills' -> 0;
    if (v_r ->> 'reputation')::int <> 850 or jsonb_array_length(v_r -> 'skills') <> 4
       or (v_x ->> 'trait') <> 'NAVIGATOR' or (v_x ->> 'word') <> 'Navigator' or (v_x ->> 'rank')::int <> 2 or (v_x ->> 'max')::int <> 3
       or (v_x ->> 'pct_now')::numeric <> 8 or (v_x ->> 'cost')::int <> 300 or (v_x ->> 'can')::boolean is not true or (v_x ->> 'why') is not null
       or (v_r -> 'skills' -> 1 ->> 'rank')::int <> 0 or (v_r -> 'skills' -> 1 ->> 'pct_now')::numeric <> 0 or (v_r -> 'skills' -> 1 ->> 'cost')::int <> 50 then
      raise exception '0355 self-assert FAIL: the read is not Navigator 2 / 3, +8 %%, next 300, with 850 Reputation: %', v_r;
    end if;
    v_r := cmd.captain_skill_up(v_code, 'NAVIGATOR');   -- step 3, through the door: 300
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'rank')::int <> 3 or (v_r ->> 'reputation')::int <> 550 then
      raise exception '0355 self-assert FAIL: step 3 through cmd.captain_skill_up did not cost 300: %', v_r;
    end if;

    -- (e) HER GRADE'S CEILING, AND A PROMOTION KEEPS HER STEPS AND RAISES IT
    v_r := public.captain_skill_up_for(v_pl, v_code, 'NAVIGATOR');
    if (v_r ->> 'error_code') is distinct from 'E_TOP_RANK' or (v_r ->> 'error_message') is distinct from 'Navigator is 3 of 3: a B captain reaches 5.' then
      raise exception '0355 self-assert FAIL: step 4 of a C captain was not refused E_TOP_RANK with its figures: %', v_r;
    end if;
    v_x := world.captain_skills(v_code) -> 'skills' -> 0;
    if (v_x ->> 'can')::boolean is not false or (v_x ->> 'why_code') <> 'E_TOP_RANK' or (v_x ->> 'cost') is not null then
      raise exception '0355 self-assert FAIL: the read does not say why the ceiling holds her: %', v_x;
    end if;
    update public.captain_state set grade = 'B' where player_officer_id = v_po;
    if (select r.rank from public.captain_trait_rank r where r.player_officer_id = v_po and r.trait = 'NAVIGATOR') <> 3
       or pg_temp.term_0355(v_fl, v_po, 'NAVIGATOR')
          <> greatest((select ct.base_pct from public.captain_traits ct where ct.officer_id = v_off and ct.trait = 'NAVIGATOR'),
                      (select g.floor_pct from public.captain_grades g where g.code = 'B')) * public.captain_rank_mult(3) then
      raise exception '0355 self-assert FAIL: a promoted captain did not keep her 3 steps over her new grade''s floor: %', pg_temp.term_0355(v_fl, v_po, 'NAVIGATOR');
    end if;
    v_r := public.captain_skill_up_for(v_pl, v_code, 'NAVIGATOR');
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'rank')::int <> 4 or (v_r ->> 'cost')::int <> 500 or (v_r ->> 'max')::int <> 5 or (v_r ->> 'reputation')::int <> 50 then
      raise exception '0355 self-assert FAIL: a promoted captain could not go past her old ceiling for 500: %', v_r;
    end if;

    -- (f) THE CAP IS THE CREW'S: three navigators, each at her grade's ceiling, add up past the cap and public.crew_pct still reads it
    v_fl2 := public.form_fleet(v_pl, 'Tecto', v_lis);
    v_sh2 := public.commission_ship(v_pl, v_fl2, 'barca', 'Tecto', true, true);
    for d in select o.id as officer_id, row_number() over (order by j.job_pct desc, o.code) as k
               from public.officers o join public.captain_job j on j.officer_id = o.id
              where j.job = 'NAVIGATOR' and o.id <> v_off order by j.job_pct desc, o.code limit 3 loop
      insert into public.player_officers (player_id, officer_id) values (v_pl, d.officer_id) returning id into v_po2;
      insert into public.captain_active (player_officer_id, trait) values (v_po2, 'NAVIGATOR');
      insert into public.captain_state (player_officer_id, grade, home_seen_at)
        select v_po2, cp.grade, now() from public.captain_profile cp where cp.officer_id = d.officer_id;
      insert into public.captain_xp (player_officer_id) values (v_po2);
      perform public.captain_seat_put(v_po2, v_sh2, case d.k when 1 then 1 when 2 then 3 else 2 end);   -- the Captain's cabin, the exploration cabin, then the trading cabin
      insert into public.captain_trait_rank (player_officer_id, trait, rank)   -- by hand: the probe's own rows, at each grade's ceiling
        select v_po2, 'NAVIGATOR', g.max_rank from public.captain_profile cp join public.captain_grades g on g.code = cp.grade where cp.officer_id = d.officer_id;
    end loop;
    select sum(t.value_pct) into v_sum from public.crew_terms(v_fl2) t where t.effect = 'speed';
    if v_sum is null or v_sum <= 25 or public.crew_pct(v_fl2, null, 'speed') <> 0.25 then
      raise exception '0355 self-assert FAIL: lit, three navigators at their ceilings (% %% in terms) do not read the cap from public.crew_pct: %', v_sum, public.crew_pct(v_fl2, null, 'speed');
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'crew_bite';
    select sum(t.value_pct) into v_sum from public.crew_terms(v_fl2) t where t.effect = 'speed';
    if v_sum is null or v_sum <= 25 or public.crew_pct(v_fl2, null, 'speed') <> 0.25 then
      raise exception '0355 self-assert FAIL: dark, three navigators at their ceilings (% %% in terms) do not read the cap from public.crew_pct: %', v_sum, public.crew_pct(v_fl2, null, 'speed');
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';

    -- (g) A MERCHANT'S COMPANY: refused, nothing written
    insert into public.player_officers (player_id, officer_id) values (v_npc, v_off);
    v_r := public.captain_skill_up_for(v_npc, v_code, 'NAVIGATOR');
    if (v_r ->> 'error_code') is distinct from 'E_NOT_SIGNED'
       or exists (select 1 from public.captain_trait_rank r join public.player_officers po on po.id = r.player_officer_id where po.player_id = v_npc) then
      raise exception '0355 self-assert FAIL: a merchant''s company was given a step: %', v_r;
    end if;
    set constraints public.reputation_reconciles immediate;   -- every probe row of this transaction reconciles
    set constraints public.reputation_reconciles deferred;
    raise exception using errcode = 'ZX355', message = 'PROBE_ROLLBACK_0355';
  exception when sqlstate 'ZX355' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0355 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0355' or p.auth_uid = c_uid)
     or (select c.value from public.world_config c where c.key = 'crew_bite') is distinct from v_crew
     or to_regprocedure('pg_temp.term_0355(uuid,uuid,text)') is not null then
    raise exception '0355 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0355 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0355 self-assert FAIL: a world_config row moved (the probe''s switches were not put back)';
  end if;
  -- THE NEWS (0347's law): one UPDATE row, outside the probe, idempotent by its number. What is live at this deploy.
  perform public.news_update('0355', 'Captain skills', '선장 스킬');
  drop function pg_temp.crew_terms_old_0355(uuid, timestamp with time zone);
  drop function pg_temp.pass_0355(text);
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0355 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0355 cost: %', v_cost_note;
  raise notice '0355 self-assert ok: A CAPTAIN''S SKILL IS RAISED WITH REPUTATION (R2). One table no client reads or writes, the ceilings C 3, B 5, A 7, S 10, 2 knobs, 5 functions (the door and the read to authenticated, as their siblings); 4 hunks on public.crew_terms and 1 on the registry (+2 rows), each once and reversing, ACL, volatility, definer and config unmoved; no other function and no existing knob moved; 0 client write grants. PARITY: OLD = NEW public.crew_terms at one instant for all % fleet(s) with a seated captain (crew_bite % here). The probe (rolled back): refused E_TRAIT_IDLE (dark, not her job), E_NOT_SIGNED, E_TRAIT_NOT_KNOWN, E_NOT_ENOUGH_REPUTATION (Needs 50: you have 40, with figures), E_NOT_IN_PORT, E_NOT_IN_USE (reputation_on false), E_TOP_RANK (3 of 3: a B captain reaches 5), and no refusal wrote anything; steps 1 and 2 cost 50 then 150 and the book stayed chained (1050, 1000, 850); her speed term was x 1.08 exactly, lit (% to %) and dark (% to %), and nothing else of the fleet moved; the read said Navigator 2 / 3, +8 %%, next 300; step 3 through the door cost 300; promoted to B she kept 3 steps over the new floor and bought step 4 for 500; three navigators at their ceilings added up past 25 %% and public.crew_pct read 25 %%, lit and dark; a merchant''s company was refused. % ms.',
    v_fleets, v_crew, v_lit0, v_lit, v_dark0, v_dark, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
