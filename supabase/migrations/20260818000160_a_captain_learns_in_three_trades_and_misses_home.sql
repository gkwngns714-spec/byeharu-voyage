-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0160 — A CAPTAIN LEARNS IN THREE TRADES AND MISSES HOME  (K6 "captains III": levels, homesickness — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §4.5, §4.7 and §8 row K6 (research: docs/research/UWO_SKILLS_AND_CAPTAINS.md
-- §3.3, §3.10). The owner, row 62: *"3 kinds of levels - exploration, trading, combat"*; row 70: *"surgeon
-- could be a healer where captains may be homesick"*; O8: a captain's level is per signing and the grind is
-- long. D11 and D13 were approved by default — the owner may reverse either; every number is a knob.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   THREE TRACKS   public.captain_xp (signing → exploration, trading, combat points), a PLAYER's signing only
--       (merchants' captains never level, O8). Seeded from officer_xp: all of a signing's points go to
--       Exploration (miles were the bulk of voyage_xp, and 0127 never kept fights apart — said, not guessed).
--       officer_xp.xp is written by nothing from here and read by nothing (K9 drops it; officer_xp keeps
--       `aboard_since`, which the seat core writes).
--   THE ONE WRITER public.captain_xp_credit(fleet, exploration, trading, combat, since): every captain seated in
--       the fleet earns each track at her cabin's rate for it (100 % in a cabin of that focus or the Captain's
--       cabin, cabin_off_focus_pct elsewhere — the same 50 % a trait gets) × (1 + Leadership %) while skills
--       bite. Called by voyage.settle's arrival arm (a voyage's miles → Exploration, the pirates seen off →
--       Combat: public.voyage_xp_tracks, which voyage_xp now sums — the same number, asserted) and by
--       cmd.do_buy / cmd.do_sell (the trade's coin → Trading, fame_ducats_per_point: 0069's 100 = 1 point).
--       A merchant's signing has no row, so the update touches nothing for her.
--   THE LEVEL IN FORCE public.captain_level(signing, focus) = her level in that track, but never above YOUR
--       company's level in the same track (public.player_progress) — read only when her own is above 1, so a
--       level-1 captain (every merchant) costs no progress scan. public.captain_level_mult(signing, focus)
--       replaces 0127's one-number multiplier: still exactly 1 while levels_bite is off.
--   HOMESICK (D13) captain_state.home_seen_at is set at hiring (0157) and by the arrival arm when her fleet
--       makes port in her home region (at the voyage's arrival instant). Homesick = more than
--       homesick_after_hours (72) since. Lit (crew_bite), her terms × (1 − max(0, homesick_penalty_pct 20 −
--       the fleet's care) / 100); care = the fleet's Surgeon homesick_relief (capped, crew_effects) + Hospitality
--       (while skills bite). One query: public.crew_terms computes the raw terms once, care from them, then
--       the factor — never a second copy of the term arithmetic.
--   THE ROSTER     world.captains() (registered): your captains — grade now, job, the traits she knows and the
--       ones she uses, her seat, three level bars with the cap said in words, and the homesick line.
--       cmd.captain_traits_set(code, traits) (registered; deferred here from K5 with the screen that shows
--       traits): choose up to her grade's slots among the traits she knows — only ashore or in port.
--   THE RE-CUTS (hunks sliced from PRODUCTION's live bodies at head 0158, LF-normalised, each occurring once,
--       each reversing, ACLs unchanged): public.voyage_xp, public.crew_terms, voyage.settle, cmd.do_buy,
--       cmd.do_sell, public.sign_officer (a player's hire gets her captain_xp row), world.officers (`level` is
--       the level in force in her job's track), public.client_rpc_entry_points (+2). The old
--       public.captain_level_mult(uuid) is then dropped — no body names it (asserted).
--
-- ── DARK: WHAT IT DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────────
-- Change any number while levels_bite and crew_bite are off: every fleet × the four live effects, every
-- ship's experience and every reader answer equal their pre-images. No promotion (K8), languages in
-- bargaining, Pilot / Provisioner / goods traders (K7). Crew homesickness is not in this plan (D13).
-- KNOWN EDGE, said: homesickness is read at the moment a lit term is read (now()), so a settlement run late
-- under crew_bite could see a captain one day more homesick than at the event; dark today, it is K7's to
-- pass the event's instant if the owner lights crew_bite before then.
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) seed: one captain_xp row per player signing, Σ exploration = Σ old officer_xp.xp; none for a merchant.
-- (b) DARK = the pre-image: crew_pct every fleet × 4 effects; voyage_xp of every voyage; fleet_speed /
--     cargo space / raid losses on every fleet / ship; world.officers for the captains of today.
-- (c) THE PROBE (own houses, rolled back): an S navigator hired into a docked fleet gets a captain_xp row;
--     credit by the one writer: Exploration cabin → miles 100 %, trading 50 %, combat 50 %; Captain's cabin →
--     all 100 %; her level is capped at the company's (a level-10 Trading captain of a level-1 company reads
--     1), and uncapped once the company out-levels her; lit levels × 1.02 per level; homesick 73 h → her lit
--     speed × 0.80, with a 9 % Surgeon aboard × 0.89; docking in her home region clears it; the traits verb
--     refuses six on an S (E_TOO_MANY_TRAITS), a trait she does not know (E_TRAIT_NOT_KNOWN), at sea
--     (E_NOT_IN_PORT), and takes five she knows; world.captains says it all in words.
-- (e) the re-cuts reverse; ACL / volatility / definer / config unmoved; no body names the old multiplier or
--     officer_xp.xp; entry points +2; 0 client write grants.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- New table and functions only; the re-cuts replace bodies. Deploy with the clock unwound (DEPLOY_RUNBOOK).
-- ROLLBACK: a forward slice restoring the bodies from the hunks' OLD text and captain_level_mult(uuid) from its
-- pre-image, and dropping captain_xp (officer_xp.xp was never cleared, so 0127's levels are where they were
-- plus nothing: credits after 0160 would be lost — say so before rolling back a live game).
-- VERSION: 0160 (provisional: S13 holds 0158). Written on production's 0158.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

create or replace function pg_temp.occurs_0160(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0160 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.voyage_xp(uuid)'), ('public.crew_terms(uuid)'), ('voyage.settle(uuid, timestamp with time zone)'),
               ('cmd.do_buy(uuid, jsonb)'), ('cmd.do_sell(uuid, jsonb)'), ('public.sign_officer(uuid, text, uuid)'),
               ('world.officers()'), ('public.client_rpc_entry_points()')) f(fn);

create temp table untouched_before_0160 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.crew_pct(uuid, uuid, text, uuid)'), ('world.crew_bonuses(uuid)'), ('world.ship_seats(uuid)'),
               ('public.seat_captain_for(uuid, text, uuid, integer)'), ('public.captain_seat_put(uuid, uuid, integer, boolean)'),
               ('public.player_progress(uuid)'), ('world.captain_card(uuid)'), ('public.post_officer_to(uuid, text, uuid)')) f(fn);

create temp table hunks_0160 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0160 (fn, n, old, new) values
  ('public.voyage_xp(uuid)', 1, $o0$  select v.total_nm / public.wc_num('ship_xp_nm_per_point')
         + coalesce((select sum(public.fight_points(ve.payload->>'outcome'))
                       from public.voyage_events ve
                      where ve.voyage_id = v.id and ve.kind = 'PIRATES'), 0)
    from public.voyages v where v.id = p_voyage$o0$, $n0$  -- 0160: the sum of its two tracks (public.voyage_xp_tracks) — the same number, asserted.
  select x.exploration + x.combat from public.voyage_xp_tracks(p_voyage) x$n0$),
  ('public.crew_terms(uuid)', 1, $o1$-- stands above her birth grade (K8).
declare
  v_off numeric;
begin$o1$, $n1$-- stands above her birth grade (K8).
-- 0160 (K6): the level multiplier is her level IN THE TRAIT'S TRACK (her job's, dark); lit, a homesick
-- captain's terms × (1 − max(0, homesick_penalty_pct − the fleet's care) / 100) — care being the fleet's
-- Surgeon homesick_relief (capped) + Hospitality while skills bite, taken from the SAME raw terms.
declare
  v_off   numeric;
  v_care  numeric := 0;
  v_pen   numeric;
  v_hours numeric;
begin$n1$),
  ('public.crew_terms(uuid)', 2, $o2$             o.bonus_pct * public.captain_level_mult(po.id)
$o2$, $n2$             o.bonus_pct * public.captain_level_mult(po.id, jt.focus)
$n2$),
  ('public.crew_terms(uuid)', 3, $o3$        join public.trait_effects te on te.trait = o.specialty
$o3$, $n3$        join public.traits jt on jt.code = o.specialty   -- 0160: her job's track
        join public.trait_effects te on te.trait = o.specialty
$n3$),
  ('public.crew_terms(uuid)', 4, $o4$  v_off := public.wc_num('cabin_off_focus_pct') / 100.0;
  return query
    select po.id, po.officer_id, cs.ship_id, cs.seat, ca.trait, te.effect,
           greatest(ct.base_pct, case when gs.ord > gb.ord then gs.floor_pct else 0 end)
           * te.mult * public.captain_level_mult(po.id)
           * case when x.cabin in ('captain', t.focus) then 1 else v_off end
      from public.ships s
      join public.captain_seats cs on cs.ship_id = s.id
      join public.ship_classes c on c.id = s.class_id
      cross join lateral (select public.cabin_focus(c.code, cs.seat) as cabin) x
      join public.player_officers po on po.id = cs.player_officer_id
      join public.captain_active ca on ca.player_officer_id = po.id
      join public.captain_traits ct on ct.officer_id = po.officer_id and ct.trait = ca.trait
      join public.traits t on t.code = ca.trait
      join public.trait_effects te on te.trait = ca.trait
      join public.captain_profile cp on cp.officer_id = po.officer_id
      join public.captain_grades gb on gb.code = cp.grade
      left join public.captain_state st on st.player_officer_id = po.id
      -- a merchant's captain has no state row: she stands at her birth grade for ever (O8), said here
      join public.captain_grades gs on gs.code = coalesce(st.grade, cp.grade)
     where s.fleet_id = p_fleet;
end$o4$, $n4$  v_off   := public.wc_num('cabin_off_focus_pct') / 100.0;
  v_pen   := public.wc_num('homesick_penalty_pct');
  v_hours := public.wc_num('homesick_after_hours');
  return query
    with raw as (
      select po.id as player_officer_id, po.officer_id, cs.ship_id, cs.seat, ca.trait, te.effect,
             greatest(ct.base_pct, case when gs.ord > gb.ord then gs.floor_pct else 0 end)
             * te.mult * public.captain_level_mult(po.id, t.focus)
             * case when x.cabin in ('captain', t.focus) then 1 else v_off end as value_pct,
             coalesce(now() - st.home_seen_at > make_interval(hours => v_hours::int), false) as homesick
        from public.ships s
        join public.captain_seats cs on cs.ship_id = s.id
        join public.ship_classes c on c.id = s.class_id
        cross join lateral (select public.cabin_focus(c.code, cs.seat) as cabin) x
        join public.player_officers po on po.id = cs.player_officer_id
        join public.captain_active ca on ca.player_officer_id = po.id
        join public.captain_traits ct on ct.officer_id = po.officer_id and ct.trait = ca.trait
        join public.traits t on t.code = ca.trait
        join public.trait_effects te on te.trait = ca.trait
        join public.captain_profile cp on cp.officer_id = po.officer_id
        join public.captain_grades gb on gb.code = cp.grade
        left join public.captain_state st on st.player_officer_id = po.id
        -- a merchant's captain has no state row: she stands at her birth grade for ever (O8), said here,
        -- and is never homesick (no home clock — O8, D13)
        join public.captain_grades gs on gs.code = coalesce(st.grade, cp.grade)
       where s.fleet_id = p_fleet),
    care as (
      -- the fleet's care for its homesick: the Surgeons' homesick_relief (capped) + Hospitality while skills
      -- bite — read only when somebody is homesick
      select case when not coalesce(bool_or(r.homesick), false) then 0
                  else least(coalesce(sum(r.value_pct) filter (where r.effect = 'homesick_relief'), 0),
                             (select ce.cap_pct from public.crew_effects ce where ce.code = 'homesick_relief'))
                       + case when public.skills_bite_on()
                              then coalesce(world.skill_pct((select f.player_id from public.fleets f where f.id = p_fleet), null, 'homesick'), 0)
                              else 0 end end as pts
        from raw r)
    select r.player_officer_id, r.officer_id, r.ship_id, r.seat, r.trait, r.effect,
           r.value_pct * case when r.homesick then 1 - greatest(0, v_pen - care.pts) / 100.0 else 1 end
      from raw r cross join care;
end$n4$),
  ('voyage.settle(uuid, timestamp with time zone)', 1, $o5$      insert into public.officer_xp (player_officer_id, xp)
      select po.id, public.voyage_xp(v.id) from public.player_officers po
       -- 0157: the captains SEATED in her ships (seats change only in port, so these sailed with her)
       join public.captain_seats cs on cs.player_officer_id = po.id
       join public.ships sh2 on sh2.id = cs.ship_id
       where sh2.fleet_id = p_fleet
         and coalesce((select ox.aboard_since from public.officer_xp ox where ox.player_officer_id = po.id),
                       po.hired_at) <= v.departed_at
      on conflict (player_officer_id) do update set xp = public.officer_xp.xp + excluded.xp;
$o5$, $n5$      -- 0160 (K6): HER THREE TRACKS — the voyage's miles to Exploration and the pirates seen off to Combat
      -- (public.voyage_xp_tracks), through the one writer (her cabin's rate per track; Leadership while skills
      -- bite; only captains aboard when she departed; a merchant's have no row). And HOME: a captain whose fleet
      -- makes port in her home region is no longer homesick (her clock is the voyage's arrival instant).
      perform public.captain_xp_credit(p_fleet, x.exploration, 0, x.combat, v.departed_at)
         from public.voyage_xp_tracks(v.id) x;
      update public.captain_state st set home_seen_at = v.eta
        from public.captain_seats cs
        join public.ships sh2 on sh2.id = cs.ship_id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.officers o on o.id = po.officer_id
        join public.ports hp on hp.id = o.home_port_id
       where st.player_officer_id = cs.player_officer_id and sh2.fleet_id = p_fleet
         and hp.region_id = (select ap.region_id from public.ports ap where ap.id = v.dest_port_id);
$n5$),
  ('cmd.do_buy(uuid, jsonb)', 1, $o6$      'haggle_saved', q.haggle_saved)));

  return jsonb_build_object('good', g.code, 'qty', v_loaded$o6$, $n6$      'haggle_saved', q.haggle_saved)));
  -- 0160 (K6): the captains seated in the fleet learn Trading from the coin that moved (0069's rate).
  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);

  return jsonb_build_object('good', g.code, 'qty', v_loaded$n6$),
  ('cmd.do_sell(uuid, jsonb)', 1, $o7$  -- 0122: the profit tax is its own ledger row and its own flow, paid to the city of the sale.
$o7$, $n7$  -- 0160 (K6): the captains seated in the fleet learn Trading from the coin that moved (0069's rate).
  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
  -- 0122: the profit tax is its own ledger row and its own flow, paid to the city of the sale.
$n7$),
  ('public.sign_officer(uuid, text, uuid)', 1, $o8$    select v_id, cp.grade, now() from public.captain_profile cp where cp.officer_id = v_off.id;
$o8$, $n8$    select v_id, cp.grade, now() from public.captain_profile cp where cp.officer_id = v_off.id;
    insert into public.captain_xp (player_officer_id) values (v_id);   -- 0160: her three tracks, from nothing
$n8$),
  ('world.officers()', 1, $o9$               'level', case when po.id is not null then public.level_from_points(coalesce(
                          (select ox.xp from public.officer_xp ox where ox.player_officer_id = po.id), 0)) end
$o9$, $n9$               -- 0160: the level in force in her JOB's track (public.captain_level; capped at your company's)
               'level', case when po.id is not null then public.captain_level(po.id,
                          (select jt.focus from public.traits jt where jt.code = o.specialty)) end
$n9$),
  ('public.client_rpc_entry_points()', 1, $o10$      ('cmd',         'seat_captain',          'text, uuid, int')
$o10$, $n10$      ('cmd',         'seat_captain',          'text, uuid, int'),
      -- 0160: your captains (levels, homesickness, traits) and choosing the traits she uses (K6).
      ('world',       'captains',              ''),
      ('cmd',         'captain_traits_set',    'text, text[]')
$n10$);

create temp table clm_before_0160 on commit drop as
select replace(pg_get_functiondef('public.captain_level_mult(uuid)'::regprocedure), E'\r', '') as def;

create temp table before_0160 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select coalesce(sum(ox.xp), 0) from public.officer_xp ox join public.player_officers po on po.id = ox.player_officer_id
          join public.players pl on pl.id = po.player_id and not pl.is_npc) as xp_sum,
       (select count(*) from public.player_officers po join public.players pl on pl.id = po.player_id and not pl.is_npc) as player_signings;

create temp table bonus_before_0160 on commit drop as
select f.id as fleet_id, e.effect, public.crew_pct(f.id, null, e.effect) as v
  from public.fleets f cross join (values ('speed'), ('hold'), ('spread'), ('crew_saved')) e(effect);
create temp table readers_before_0160 on commit drop as
select 'vxp'::text as what, v.id::text as k, public.voyage_xp(v.id)::text as v from public.voyages v
union all
select 'speed', f.id::text, voyage.fleet_speed(f.id)::text from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id)
union all
select 'hold', s.id::text, public.ship_hold_capacity(s.id)::text from public.ships s
union all
select 'raid', f.id::text, public.raid_crew_lost(f.id, 120, 0.15)::text from public.fleets f;
create temp table officers_before_0160 on commit drop as select world.officers() as j;

-- ── 2. THE KNOBS, THE TABLE ────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('homesick_after_hours', to_jsonb(72),
   '0160 (D13): REAL hours since a captain''s fleet last made port in her home region after which she is homesick. '
   'Read by public.crew_terms (lit) and world.captains.'),
  ('homesick_penalty_pct', to_jsonb(20),
   '0160 (D13): what homesickness costs a captain''s traits, in per cent, before the fleet''s care (Surgeon, '
   'Hospitality). Read by public.crew_terms while crew_bite is on.')
on conflict (key) do nothing;

create table if not exists public.captain_xp (
  player_officer_id uuid primary key references public.player_officers(id) on delete cascade,
  exploration       numeric not null default 0 check (exploration >= 0),
  trading           numeric not null default 0 check (trading >= 0),
  combat            numeric not null default 0 check (combat >= 0)
);
comment on table public.captain_xp is
  '0160 (K6, D11): a PLAYER''s signing''s points in the three tracks (per signing, O8: dismissed, she starts over). '
  'Written only by public.captain_xp_credit; read by public.captain_level. A merchant''s captain has no row. Server-only.';
alter table public.captain_xp enable row level security;
revoke all on table public.captain_xp from public, anon, authenticated;

insert into public.captain_xp (player_officer_id, exploration)
select po.id, coalesce((select ox.xp from public.officer_xp ox where ox.player_officer_id = po.id), 0)
  from public.player_officers po join public.players pl on pl.id = po.player_id and not pl.is_npc
on conflict (player_officer_id) do nothing;

-- ── 3. THE ONE ANSWERS ─────────────────────────────────────────────────────────────────────────
create or replace function public.voyage_xp_tracks(p_voyage uuid)
returns table (exploration numeric, combat numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $vt$
  -- 0160: WHAT A VOYAGE TEACHES, by track — her miles (Exploration) and the pirates she saw off (Combat).
  -- public.voyage_xp is their sum (the ship's one number, 0127).
  select v.total_nm / public.wc_num('ship_xp_nm_per_point'),
         coalesce((select sum(public.fight_points(ve.payload->>'outcome'))
                     from public.voyage_events ve
                    where ve.voyage_id = v.id and ve.kind = 'PIRATES'), 0)
    from public.voyages v where v.id = p_voyage
$vt$;

create or replace function public.captain_level(p_signing uuid, p_focus text)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $cl$
-- 0160 (D11): the level IN FORCE of a signing in one track — her own, never above your company's in the
-- same track (public.player_progress, read only when her own is above 1). No row (a merchant's): 1.
declare
  v_pts numeric;
  v_lvl int;
  v_co  int;
begin
  select case p_focus when 'exploration' then x.exploration when 'trading' then x.trading when 'combat' then x.combat end
    into v_pts from public.captain_xp x where x.player_officer_id = p_signing;
  v_lvl := public.level_from_points(coalesce(v_pts, 0));
  if v_lvl <= 1 then
    return 1;
  end if;
  select (public.player_progress(po.player_id)->p_focus->>'level')::int into v_co
    from public.player_officers po where po.id = p_signing;
  return least(v_lvl, coalesce(v_co, 1));
end $cl$;

create or replace function public.captain_level_mult(p_signing uuid, p_focus text)
returns numeric
language sql
stable
set search_path = public, pg_temp
as $cm$
  -- 0160: a captain's value × (1 + pct × (level − 1)) in the TRACK of the trait counted — exactly 1 at
  -- level 1, and while levels_bite is off (nothing is read but the switch). 0127's rule, per track.
  select case when not public.levels_bite_on() then 1
              else 1 + public.wc_num('captain_level_pct_per_level') / 100 * (public.captain_level(p_signing, p_focus) - 1) end
$cm$;

create or replace function public.captain_xp_credit(p_fleet uuid, p_exploration numeric, p_trading numeric, p_combat numeric,
                                                    p_since timestamptz default null)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $cx$
-- 0160: THE ONE WRITER of a captain's experience. Every signing seated in the fleet (and aboard since
-- p_since, when given — 0127's rule) earns each track at her cabin's rate for it — 100 % in a cabin of
-- that focus or the Captain's cabin, cabin_off_focus_pct elsewhere — × (1 + Leadership %) while skills
-- bite. Only rows that exist are touched: a merchant's captain has none. Returns how many earned.
declare
  v_off  numeric := public.wc_num('cabin_off_focus_pct') / 100.0;
  v_lead numeric := 1;
  v_n    int;
begin
  if public.skills_bite_on() then
    v_lead := 1 + coalesce(world.skill_pct((select f.player_id from public.fleets f where f.id = p_fleet), null, 'captain_xp'), 0) / 100.0;
  end if;
  update public.captain_xp cx
     set exploration = cx.exploration + p_exploration * v_lead * case when z.cabin in ('captain', 'exploration') then 1 else v_off end,
         trading     = cx.trading     + p_trading     * v_lead * case when z.cabin in ('captain', 'trading')     then 1 else v_off end,
         combat      = cx.combat      + p_combat      * v_lead * case when z.cabin in ('captain', 'combat')      then 1 else v_off end
    from (select cs.player_officer_id, public.cabin_focus(c.code, cs.seat) as cabin, po.hired_at
            from public.ships s
            join public.captain_seats cs on cs.ship_id = s.id
            join public.ship_classes c on c.id = s.class_id
            join public.player_officers po on po.id = cs.player_officer_id
           where s.fleet_id = p_fleet) z
   where cx.player_officer_id = z.player_officer_id
     and (p_since is null
          or coalesce((select ox.aboard_since from public.officer_xp ox where ox.player_officer_id = z.player_officer_id),
                      z.hired_at) <= p_since);
  get diagnostics v_n = row_count;
  return v_n;
end $cx$;

create or replace function public.captain_traits_set_for(p_player uuid, p_code text, p_traits text[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $ts$
-- 0160: CORE of cmd.captain_traits_set — the traits a captain USES: at least one, at most her grade's
-- slots, each one she knows (her grade's `known` first of her ten), none twice. Only ashore or while her
-- ship is docked (D9). Server-only.
declare
  v_code  text := upper(btrim(coalesce(p_code, '')));
  v_po    uuid;
  v_off   uuid;
  v_name  text;
  v_slots int;
  v_known int;
  v_at    text;
  v_bad   text;
  v_set   text[] := (select array_agg(distinct upper(btrim(t))) from unnest(coalesce(p_traits, '{}'::text[])) t where btrim(t) <> '');
begin
  select po.id, o.id, o.name into v_po, v_off, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = p_player and o.code = v_code;
  if v_po is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'You do not keep that captain.', 'fixes', jsonb_build_array('(hire her at an inn first)'));
  end if;
  select s.name into v_at
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id join public.fleets f on f.id = s.fleet_id
   where cs.player_officer_id = v_po and f.status <> 'DOCKED';
  if v_at is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_PORT',
      'error_message', format('%s is at sea aboard %s. A captain changes her traits only in port.', v_name, v_at),
      'fixes', jsonb_build_array('(wait until her ship is docked)'));
  end if;
  select g.slots, g.known into v_slots, v_known
    from public.captain_profile cp
    left join public.captain_state st on st.player_officer_id = v_po
    join public.captain_grades g on g.code = coalesce(st.grade, cp.grade)
   where cp.officer_id = v_off;
  if coalesce(array_length(v_set, 1), 0) = 0 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_TRAITS',
      'error_message', format('%s must use at least one trait.', v_name), 'fixes', '[]'::jsonb);
  end if;
  if array_length(v_set, 1) > v_slots then
    return jsonb_build_object('ok', false, 'error_code', 'E_TOO_MANY_TRAITS',
      'error_message', format('%s uses %s traits at most; %s were chosen.', v_name, v_slots, array_length(v_set, 1)),
      'fixes', jsonb_build_array('(choose fewer)'));
  end if;
  select string_agg(t, ', ') into v_bad from unnest(v_set) t
   where not exists (select 1 from public.captain_traits ct where ct.officer_id = v_off and ct.trait = t and ct.ord <= v_known);
  if v_bad is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_TRAIT_NOT_KNOWN',
      'error_message', format('%s does not know %s.', v_name, v_bad), 'fixes', '[]'::jsonb);
  end if;
  delete from public.captain_active where player_officer_id = v_po;
  insert into public.captain_active (player_officer_id, trait) select v_po, t from unnest(v_set) t;
  return jsonb_build_object('ok', true, 'officer', v_code, 'traits', to_jsonb(v_set),
    'sentence', format('%s now uses %s of %s traits.', v_name, array_length(v_set, 1), v_slots));
end $ts$;

create or replace function cmd.captain_traits_set(p_code text, p_traits text[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $ct$
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  -- 0160: the choosing is public.captain_traits_set_for's.
  return public.captain_traits_set_for(v_player, p_code, p_traits);
end $ct$;

create or replace function world.captains()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $wc$
-- 0160: YOUR CAPTAINS — every signing of yours: her card (world.captain_card) with her grade NOW, the
-- traits she uses, where she sits, her three levels (the level in force, her points, the next level's,
-- and when the cap holds her, the sentence that says so), and whether she is homesick, in words.
declare
  v_player uuid := public.current_player_id();
  v_hours  numeric := public.wc_num('homesick_after_hours');
begin
  return jsonb_build_object('captains', (
    select coalesce(jsonb_agg(world.captain_card(o.id) || jsonb_build_object(
      'code', o.code, 'name', o.name,
      'grade', coalesce(st.grade, cp.grade),
      'active', (select coalesce(jsonb_agg(a.trait order by ct.ord), '[]'::jsonb)
                   from public.captain_active a join public.captain_traits ct on ct.officer_id = o.id and ct.trait = a.trait
                  where a.player_officer_id = po.id),
      'ship', sh.name, 'fleet', fl.name,
      'cabin_word', (select k.word from public.cabin_kinds k where k.code = public.cabin_focus(c.code, cs.seat)),
      'can_change', (cs.player_officer_id is null or fl.status = 'DOCKED'),
      'levels', (select jsonb_agg(jsonb_build_object(
                    'track', tf.code, 'word', tf.word,
                    'level', public.captain_level(po.id, tf.code),
                    'own', public.level_from_points(x.pts),
                    'points', floor(x.pts),
                    'next_at', public.level_points(public.level_from_points(x.pts) + 1),
                    'cap_line', case when public.level_from_points(x.pts) > public.captain_level(po.id, tf.code)
                                     then format('capped at your %s level %s', tf.word, public.captain_level(po.id, tf.code)) end)
                    order by tf.ord)
                   from public.trait_foci tf
                  cross join lateral (select coalesce(case tf.code when 'exploration' then cx.exploration
                                                                   when 'trading' then cx.trading else cx.combat end, 0) as pts) x),
      'homesick', case when st.home_seen_at is not null and now() - st.home_seen_at > make_interval(hours => v_hours::int)
                       then jsonb_build_object('days', floor(extract(epoch from now() - st.home_seen_at) / 86400),
                              'line', format('Homesick: %s days from %s', floor(extract(epoch from now() - st.home_seen_at) / 86400),
                                             (select r.name from public.regions r where r.id = hp.region_id))) end
    ) order by o.name), '[]'::jsonb)
      from public.player_officers po
      join public.officers o on o.id = po.officer_id
      join public.captain_profile cp on cp.officer_id = o.id
      left join public.captain_state st on st.player_officer_id = po.id
      left join public.captain_xp cx on cx.player_officer_id = po.id
      left join public.ports hp on hp.id = o.home_port_id
      left join public.captain_seats cs on cs.player_officer_id = po.id
      left join public.ships sh on sh.id = cs.ship_id
      left join public.ship_classes c on c.id = sh.class_id
      left join public.fleets fl on fl.id = sh.fleet_id
     where po.player_id = v_player));
end $wc$;

revoke all on function public.voyage_xp_tracks(uuid) from public, anon, authenticated;
revoke all on function public.captain_level(uuid, text) from public, anon, authenticated;
revoke all on function public.captain_level_mult(uuid, text) from public, anon, authenticated;
revoke all on function public.captain_xp_credit(uuid, numeric, numeric, numeric, timestamptz) from public, anon, authenticated;
revoke all on function public.captain_traits_set_for(uuid, text, text[]) from public, anon, authenticated;
revoke all on function cmd.captain_traits_set(text, text[]) from public, anon;
grant execute on function cmd.captain_traits_set(text, text[]) to authenticated;
revoke all on function world.captains() from public, anon;
grant execute on function world.captains() to authenticated;

-- ── 4. THE RE-CUTS, then the old multiplier goes ─────────────────────────────────────────────────
do $recut$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0160 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0160 where fn = d.fn order by n loop
      if pg_temp.occurs_0160(v_def, h.old) <> 1 then
        raise exception '0160 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against',
          h.n, d.fn, pg_temp.occurs_0160(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $recut$;

drop function public.captain_level_mult(uuid);

-- ── 5. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  b        record;
  d        record;
  h        record;
  v_p      record;
  v_def    text;
  v_bad    int;
  v_r      jsonb;
  v_player uuid;
  v_fleet  uuid;
  v_ship   uuid;
  v_cls    text;
  v_po     uuid;
  v_sp     uuid;
  v_home   uuid;
  v_n      int;
  v_lvl    int;
  v_val    numeric;
  v_spd    numeric;
  v_crew   jsonb := (select value from public.world_config where key = 'crew_bite');
  c_uid constant uuid := '00000000-0160-4000-8000-000000000001';
  c_off constant text := 'ELCANO';       -- an S navigator, 9 %, home Cadiz (data/officers.json)
  c_srg constant text := 'GARCIAORTA';   -- an S surgeon, 9 %
begin
  select * into b from before_0160;

  -- (a) THE SEED
  if (select count(*) from public.captain_xp) <> b.player_signings
     or (select coalesce(sum(exploration), 0) from public.captain_xp) <> b.xp_sum
     or (select coalesce(sum(trading + combat), 0) from public.captain_xp) <> 0
     or exists (select 1 from public.captain_xp cx join public.player_officers po on po.id = cx.player_officer_id
                  join public.players pl on pl.id = po.player_id where pl.is_npc) then
    raise exception '0160 self-assert FAIL: the seed is not one row per player signing with the old experience in Exploration';
  end if;

  -- (b) DARK = the pre-image
  select count(*) into v_bad from bonus_before_0160 x where public.crew_pct(x.fleet_id, null, x.effect) is distinct from x.v;
  if v_bad <> 0 then
    raise exception '0160 self-assert FAIL: % fleet × effect(s) moved', v_bad;
  end if;
  select count(*) into v_bad from readers_before_0160 r
   where r.v is distinct from case r.what
           when 'vxp'   then public.voyage_xp(r.k::uuid)::text
           when 'speed' then voyage.fleet_speed(r.k::uuid)::text
           when 'hold'  then public.ship_hold_capacity(r.k::uuid)::text
           when 'raid'  then public.raid_crew_lost(r.k::uuid, 120, 0.15)::text end;
  if v_bad <> 0 then
    raise exception '0160 self-assert FAIL: % reader answer(s) moved (voyage experience / speed / cargo space / raid losses)', v_bad;
  end if;
  if world.officers() <> (select j from officers_before_0160) then
    raise exception '0160 self-assert FAIL: world.officers moved for the captains of today';
  end if;

  -- (c) THE PROBE — own houses, rolled back
  begin
    v_player := public.new_house(c_uid, 'Casa das Saudades', 'PRT');
    select id, port_id into v_fleet, v_home from public.fleets where player_id = v_player;
    select s.id, c.code into v_ship, v_cls from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_fleet order by s.is_flagship desc limit 1;
    perform public.credit(v_player, 'PROBE_HOMESICK', 50000,
      public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0160 self-assert')));
    v_r := public.sign_officer(v_player, c_off, v_fleet);
    select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id
     where po.player_id = v_player and o.code = c_off;
    if not coalesce((v_r->>'ok')::boolean, false) or not exists (select 1 from public.captain_xp where player_officer_id = v_po) then
      raise exception '0160 self-assert FAIL: a player''s hire has no captain_xp row: %', v_r;
    end if;
    -- the one writer, in her Exploration cabin: 100 / 50 / 50
    v_n := public.captain_xp_credit(v_fleet, 100, 100, 100);
    if v_n <> 1
       or (select (exploration, trading, combat) <> (100::numeric, 50::numeric, 50::numeric) from public.captain_xp where player_officer_id = v_po) then
      raise exception '0160 self-assert FAIL: an Exploration-cabin credit of 100 each (% earned) landed as %', v_n,
        (select row(exploration, trading, combat)::text from public.captain_xp where player_officer_id = v_po);
    end if;
    -- in the Captain's cabin: 100 % of everything
    v_r := public.seat_captain_for(v_player, c_off, v_ship, 1);
    perform public.captain_xp_credit(v_fleet, 10, 10, 10);
    if (select (exploration, trading, combat) <> (110::numeric, 60::numeric, 60::numeric) from public.captain_xp where player_officer_id = v_po) then
      raise exception '0160 self-assert FAIL: a Captain''s-cabin credit was not 100 %% of each track';
    end if;
    -- a voyage that departed before she came aboard teaches her nothing
    if public.captain_xp_credit(v_fleet, 10, 0, 0, now() - interval '1 day') <> 0 then
      raise exception '0160 self-assert FAIL: a captain earned from a voyage that sailed before she came aboard';
    end if;
    -- the cap: level 10 in Trading, a level-1 company → 1; out-levelled → her own
    update public.captain_xp set trading = public.level_points(10) where player_officer_id = v_po;
    if public.captain_level(v_po, 'trading') <> 1 then
      raise exception '0160 self-assert FAIL: a level-10 Trading captain of a level-1 company reads %', public.captain_level(v_po, 'trading');
    end if;
    perform public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', 'LIS', 'total_nm', 50000000));
    update public.captain_xp set exploration = public.level_points(4) where player_officer_id = v_po;
    v_lvl := public.captain_level(v_po, 'exploration');
    if v_lvl <> 4 then
      raise exception '0160 self-assert FAIL: an Exploration level-4 captain of a far better company reads %', v_lvl;
    end if;
    -- dark the level is not read; lit, × 1.06 at level 4 (2 % a level)
    if public.captain_level_mult(v_po, 'exploration') <> 1 then
      raise exception '0160 self-assert FAIL: dark, a level multiplier was not 1';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
    if public.captain_level_mult(v_po, 'exploration') <> 1 + public.wc_num('captain_level_pct_per_level') / 100 * 3 then
      raise exception '0160 self-assert FAIL: lit, level 4 gave × %', public.captain_level_mult(v_po, 'exploration');
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
    update public.captain_xp set exploration = 0 where player_officer_id = v_po;
    -- HOMESICK (lit): 73 h from home → × 0.80 (she uses her job alone, so no care of her own); with a
    -- Surgeon aboard, more; home again → whole
    v_r := public.captain_traits_set_for(v_player, c_off, array['NAVIGATOR']);
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    v_val := public.crew_pct(v_fleet, null, 'speed');
    update public.captain_state set home_seen_at = now() - interval '73 hours' where player_officer_id = v_po;
    if public.crew_pct(v_fleet, null, 'speed') <> round(v_val * (1 - public.wc_num('homesick_penalty_pct') / 100), 8) then
      raise exception '0160 self-assert FAIL: homesick, her speed is % (expected % × 0.80)', public.crew_pct(v_fleet, null, 'speed'), v_val;
    end if;
    v_r := public.sign_officer(v_player, c_srg, v_fleet);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0160 self-assert FAIL: could not hire the surgeon into the probe fleet: %', v_r;
    end if;
    v_spd := (select sum(x.value_pct) from public.crew_terms(v_fleet) x where x.effect = 'speed' and x.player_officer_id = v_po) / 100.0;
    if not (v_spd > round(v_val * (1 - public.wc_num('homesick_penalty_pct') / 100), 8) and v_spd < v_val) then
      raise exception '0160 self-assert FAIL: with a Surgeon aboard her homesick speed is % (between % and % expected)',
        v_spd, v_val * 0.8, v_val;
    end if;
    -- docking in her home region (Cadiz: Iberia) clears it — the arrival arm's own update, run as settle runs it
    update public.captain_state st set home_seen_at = now()
      from public.officers o, public.player_officers po, public.ports hp, public.ports ap
     where st.player_officer_id = po.id and po.id = v_po and o.id = po.officer_id and hp.id = o.home_port_id
       and ap.id = v_home and hp.region_id = ap.region_id;
    if (select now() - home_seen_at from public.captain_state where player_officer_id = v_po) > interval '1 hour' then
      raise exception '0160 self-assert FAIL: a fleet docked in her home region (Lisbon, Iberia) did not clear her homesickness';
    end if;
    if (select sum(x.value_pct) from public.crew_terms(v_fleet) x where x.effect = 'speed' and x.player_officer_id = v_po) / 100.0 <> v_val then
      raise exception '0160 self-assert FAIL: home again, her speed is not her whole value %', v_val;
    end if;
    update public.world_config set value = v_crew where key = 'crew_bite';
    -- the traits verb
    v_r := public.captain_traits_set_for(v_player, c_off,
             (select array_agg(ct.trait order by ct.ord) from public.captain_traits ct join public.officers o on o.id = ct.officer_id
               where o.code = c_off and ct.ord <= 6));
    if v_r->>'error_code' is distinct from 'E_TOO_MANY_TRAITS' then
      raise exception '0160 self-assert FAIL: six traits on an S captain: %', v_r;
    end if;
    v_r := public.captain_traits_set_for(v_player, c_off,
             array[(select t.code from public.traits t join public.officers o on o.code = c_off
                     where not exists (select 1 from public.captain_traits ct where ct.officer_id = o.id and ct.trait = t.code)
                     order by t.ord limit 1)]);
    if v_r->>'error_code' is distinct from 'E_TRAIT_NOT_KNOWN' then
      raise exception '0160 self-assert FAIL: a trait she does not know: %', v_r;
    end if;
    v_r := public.captain_traits_set_for(v_player, c_off,
             (select array_agg(ct.trait order by ct.ord) from public.captain_traits ct join public.officers o on o.id = ct.officer_id
               where o.code = c_off and ct.ord in (1, 3, 5, 7, 9)));
    if not coalesce((v_r->>'ok')::boolean, false) or (select count(*) from public.captain_active where player_officer_id = v_po) <> 5 then
      raise exception '0160 self-assert FAIL: five known traits on an S captain were refused: %', v_r;
    end if;
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -12.0 where id = v_fleet;
    v_r := public.captain_traits_set_for(v_player, c_off, array['NAVIGATOR']);
    if v_r->>'error_code' is distinct from 'E_NOT_IN_PORT' then
      raise exception '0160 self-assert FAIL: traits changed at sea: %', v_r;
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_home, lat = null, lon = null where id = v_fleet;
    -- the roster, in words
    perform cmd.assume_identity(c_uid);
    v_r := world.captains();
    if jsonb_array_length(v_r->'captains') <> 2
       or (select count(*) from jsonb_array_elements(v_r->'captains') c, jsonb_array_elements(c->'levels') l) <> 6
       or not exists (select 1 from jsonb_array_elements(v_r->'captains') c where c->>'code' = c_off and c->>'cabin_word' is not null) then
      raise exception '0160 self-assert FAIL: world.captains reads %', v_r;
    end if;
    update public.captain_xp set trading = public.level_points(10) where player_officer_id = v_po;
    if not exists (select 1 from jsonb_array_elements(world.captains()->'captains') c, jsonb_array_elements(c->'levels') l
                    where c->>'code' = c_off and l->>'track' = 'trading' and l->>'cap_line' like 'capped at your Trading level %') then
      raise exception '0160 self-assert FAIL: a capped level is not said in words';
    end if;
    raise exception 'PROBE_ROLLBACK_0160';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0160' then raise; end if;
  end;
  if exists (select 1 from public.players where company_name = 'Casa das Saudades')
     or (select value from public.world_config where key = 'crew_bite') <> v_crew then
    raise exception '0160 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (e) THE RE-CUTS reverse; the old multiplier and officer_xp.xp are named by no body
  for d in select * from defs_before_0160 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0160 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0160(v_def, h.new) <> 1 then
        raise exception '0160 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0160 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0160 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0160 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0160 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;
  if to_regprocedure('public.captain_level_mult(uuid)') is not null
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'world', 'cmd', 'voyage') and p.prosrc like '%ox.xp%') then
    raise exception '0160 self-assert FAIL: the old multiplier or officer_xp.xp is still named by a body';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points + 2 then
    raise exception '0160 self-assert FAIL: the entry points are not the old ones + world.captains + cmd.captain_traits_set';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
              where has_table_privilege(r.role, 'public.captain_xp', 'select,insert,update,delete')) then
    raise exception '0160 self-assert FAIL: a client can read or write captain_xp';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0160 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;

  raise notice '0160 self-assert ok: A CAPTAIN LEARNS IN THREE TRADES AND MISSES HOME (K6, DARK). % player signing(s) carry three tracks, their % old point(s) in Exploration; merchants none. DARK: every fleet × the four live effects, % reader answer(s) (voyage experience, speed, cargo space, raid losses) and world.officers equal their pre-images. The probe: the one writer paid an Exploration-cabin captain 100 / 50 / 50 and a Captain''s-cabin one 100 each, nothing from a voyage before she came aboard; a level-10 Trading captain of a level-1 company read 1, an Exploration level-4 one of a far better company 4 (× 1.06 lit, × 1 dark); homesick 73 h she gave 80 %% of her speed, more with a Surgeon aboard, all of it once home; the traits verb refused six on an S, a trait she does not know and a change at sea, and took five; world.captains said the cap in words. The old multiplier is gone; +2 entry points; 0 client write grants.',
    b.player_signings, b.xp_sum, (select count(*) from readers_before_0160);
end $$;
