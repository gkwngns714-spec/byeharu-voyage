-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0161 — A CAPTAIN READS THE WEATHER, KEEPS THE CASKS AND KNOWS HER GOODS  (K7 "captains IV" — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §4.2, §4.4, §4.9 and §8 row K7. The owner, row 70: *"navigator could be
-- increasing speed, or make wheather more fable"*; row 66: *"trading specialized captains, such as jewelery
-- trader, meat trader"*; 2026-10-17: Origin's captains, languages included. D14 / D15 approved by default.
--
-- ── WHAT THIS FILE DOES — the four new readers, each through public.crew_pct (the one reader) ────
--   PILOT        voyage.storm_hull_lost: a storm's hull loss × (1 − the fleet's `storm`), read AT THE
--                VOYAGE'S DEPARTURE (crew_pct's new p_at), so a settlement is the same whenever it runs.
--   PROVISIONER  voyage.endurance_days: × (1 + the fleet's `supplies`).
--   TRADERS      world.spread_effective: the captains' `spread` + `category_spread` for THIS good — only the
--                traders of the good's category count (public.crew_pct filters by traits.goods), capped per
--                category at crew_effects.cap_pct (20).
--   LANGUAGE     public.haggle_odds gains p_fleet (default null: today's answer; drop + create, the 0139
--                method): if a captain seated in that fleet speaks the port's language, + language_haggle_points
--                (5) to the odds — while crew_bite is on. cmd.haggle and world.haggle_state pass the fleet;
--                world.haggle_state serves `language_line` ("Ana de Sousa speaks Portuguese here: +5% bargain
--                odds"). public.crew_speaker is the one answer to "who in this fleet speaks the port's tongue".
--   THE INSTANT  public.crew_terms and public.crew_pct gain p_at (default now(); drop + create): homesickness
--                is judged at that instant (K6's said edge closed for the storm arm).
-- All of it is 0 while crew_bite is off — storm, supplies and category_spread are not `live` effects, and the
-- language term reads the switch — so every answer below equals its pre-image (asserted).
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) DARK = the pre-image: endurance of every fleet; a storm's loss for every voyage × 3 magnitudes;
--     400 sampled spreads; haggle odds for every player house × 20 goods at its fleet's port; crew_pct of
--     every fleet × the four live effects.
-- (b) THE PROBE (own house, rolled back; crew_bite lit inside it): a Gem trader narrows a gem's spread and
--     leaves a grain's alone; a Provisioner lengthens the supplies; a Pilot shrinks a storm's loss on her
--     fleet's voyage, and the answer is the same asked at the departure whatever the clock; a Spanish-only
--     captain at Lisbon adds nothing to the odds, a Portuguese speaker adds 5 points, and the line says it;
--     dark again, all of it is gone.
-- (c) the re-cuts reverse; ACLs / volatility / definer / config unmoved (the three re-made signatures keep
--     their ACL); the old signatures are gone; no new entry point; 0 client write grants.
--
-- ROLLBACK: a forward slice restoring the bodies from the hunks' OLD text (the three signatures included).
-- VERSION: 0161 (provisional: S13 0158, K6 0160). Written on K6 over production's 0157 bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

create or replace function pg_temp.occurs_0161(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0161 (fn text, fn_after text, def text, acl text, vol "char", secdef boolean, cfg text) on commit drop;
insert into defs_before_0161
select f.fn, f.fn_after,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), ''),
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure),
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure),
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure)
  from (values ('public.crew_terms(uuid)', 'public.crew_terms(uuid, timestamp with time zone)'),
               ('public.crew_pct(uuid, uuid, text, uuid)', 'public.crew_pct(uuid, uuid, text, uuid, timestamp with time zone)'),
               ('public.haggle_odds(uuid, uuid, uuid)', 'public.haggle_odds(uuid, uuid, uuid, uuid)'),
               ('voyage.storm_hull_lost(uuid, numeric, numeric)', 'voyage.storm_hull_lost(uuid, numeric, numeric)'),
               ('voyage.endurance_days(uuid)', 'voyage.endurance_days(uuid)'),
               ('world.spread_effective(uuid, uuid, uuid, boolean)', 'world.spread_effective(uuid, uuid, uuid, boolean)'),
               ('cmd.haggle(uuid, uuid, text)', 'cmd.haggle(uuid, uuid, text)'),
               ('world.haggle_state(uuid, uuid)', 'world.haggle_state(uuid, uuid)')) f(fn, fn_after);

create temp table hunks_0161 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0161 (fn, n, old, new) values
  ('public.crew_terms(uuid)', 1, $o0$CREATE OR REPLACE FUNCTION public.crew_terms(p_fleet uuid)$o0$, $n0$CREATE OR REPLACE FUNCTION public.crew_terms(p_fleet uuid, p_at timestamp with time zone DEFAULT now())$n0$),
  ('public.crew_terms(uuid)', 2, $o1$coalesce(now() - st.home_seen_at > make_interval$o1$, $n1$coalesce(p_at - st.home_seen_at > make_interval$n1$),
  ('public.crew_pct(uuid, uuid, text, uuid)', 1, $o2$CREATE OR REPLACE FUNCTION public.crew_pct(p_fleet uuid, p_ship uuid, p_effect text, p_good uuid DEFAULT NULL::uuid)$o2$, $n2$CREATE OR REPLACE FUNCTION public.crew_pct(p_fleet uuid, p_ship uuid, p_effect text, p_good uuid DEFAULT NULL::uuid, p_at timestamp with time zone DEFAULT now())$n2$),
  ('public.crew_pct(uuid, uuid, text, uuid)', 2, $o3$  select coalesce(sum(t.value_pct), 0) into v_sum from public.crew_terms(p_fleet) t where t.effect = p_effect;$o3$, $n3$  -- 0161 (K7): at the instant asked (p_at: homesickness is judged then), and for a goods trader's effect
  -- only the traders of THIS good's category (traits.goods) — capped per category at cap_pct.
  select coalesce(sum(t.value_pct), 0) into v_sum from public.crew_terms(p_fleet, p_at) t
   where t.effect = p_effect
     and (p_effect <> 'category_spread'
          or exists (select 1 from public.traits tr join public.goods g on g.category = tr.goods
                      where tr.code = t.trait and g.id = p_good));$n3$),
  ('voyage.storm_hull_lost(uuid, numeric, numeric)', 1, $o4$  v_pct numeric := voyage.skill_pct_at_departure(p_voyage, 'storm_damage');
begin$o4$, $n4$  v_pct numeric := voyage.skill_pct_at_departure(p_voyage, 'storm_damage');
  -- 0161 (K7): the Pilots seated in her fleet, read AT THE DEPARTURE (crew_pct's p_at), so a settlement
  -- is the same whenever it runs. 0 while crew_bite is off (storm is not a live effect).
  v_crew numeric := (select public.crew_pct(v.fleet_id, null, 'storm', null, v.departed_at) from public.voyages v where v.id = p_voyage);
begin$n4$),
  ('voyage.storm_hull_lost(uuid, numeric, numeric)', 2, $o5$  if v_pct = 0 then
$o5$, $n5$  if v_pct = 0 and coalesce(v_crew, 0) = 0 then
$n5$),
  ('voyage.storm_hull_lost(uuid, numeric, numeric)', 3, $o6$  return round(p_maxd * (0.08 + 0.17 * p_magnitude) * (1 - least(v_pct, 100) / 100.0), 2);$o6$, $n6$  return round(p_maxd * (0.08 + 0.17 * p_magnitude) * (1 - least(v_pct, 100) / 100.0) * (1 - coalesce(v_crew, 0)), 2);$n6$),
  ('voyage.endurance_days(uuid)', 1, $o7$  return v_base * (1 + v_skill);$o7$, $n7$  -- 0161 (K7): the Provisioners seated in her fleet (0 while crew_bite is off — and then nothing is multiplied).
  v_crew := public.crew_pct(p_fleet, null, 'supplies');
  if v_crew <> 0 then
    return v_base * (1 + v_skill) * (1 + v_crew);
  end if;
  return v_base * (1 + v_skill);$n7$),
  ('voyage.endurance_days(uuid)', 2, $o8$  v_skill  numeric := 0;
begin$o8$, $n8$  v_skill  numeric := 0;
  v_crew   numeric;   -- 0161
begin$n8$),
  ('world.spread_effective(uuid, uuid, uuid, boolean)', 1, $o9$    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);   -- 0157: the captains, through the one reader
$o9$, $n9$    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);   -- 0157: the captains, through the one reader
    -- 0161 (K7): and the traders of THIS good's category (0 while crew_bite is off — then nothing is added)
    v_trader := public.crew_pct(p_fleet, null, 'category_spread', p_good);
    if v_trader <> 0 then
      v_purser := v_purser + v_trader;
    end if;
$n9$),
  ('world.spread_effective(uuid, uuid, uuid, boolean)', 2, $o10$  v_hag    numeric := 0;
$o10$, $n10$  v_hag    numeric := 0;
  v_trader numeric;   -- 0161
$n10$),
  ('public.haggle_odds(uuid, uuid, uuid)', 1, $o11$CREATE OR REPLACE FUNCTION public.haggle_odds(p_player uuid, p_port uuid, p_good uuid)$o11$, $n11$CREATE OR REPLACE FUNCTION public.haggle_odds(p_player uuid, p_port uuid, p_good uuid, p_fleet uuid DEFAULT NULL::uuid)$n11$),
  ('public.haggle_odds(uuid, uuid, uuid)', 2, $o12$             + public.player_skill_bonus(p_player, 'SPREAD'))$o12$, $n12$             + public.player_skill_bonus(p_player, 'SPREAD')
             -- 0161 (K7, D14): a captain of this fleet who speaks the port's language (public.crew_speaker,
             -- read only while crew_bite is on); no fleet named, nothing — today's answer
             + case when p_fleet is not null and exists (select 1 from public.crew_speaker(p_fleet, p_port))
                    then public.wc_num('language_haggle_points') / 100.0 else 0 end)$n12$),
  ('cmd.haggle(uuid, uuid, text)', 1, $o13$  v_odds   := public.haggle_odds(v_player, f.port_id, g.id);$o13$, $n13$  v_odds   := public.haggle_odds(v_player, f.port_id, g.id, p_fleet);   -- 0161: her captains' languages$n13$),
  ('world.haggle_state(uuid, uuid)', 1, $o14$    'next_odds',     public.haggle_odds(v_player, f.port_id, p_good),
    'next_odds_pct', round(public.haggle_odds(v_player, f.port_id, p_good) * 100, 1),
$o14$, $n14$    'next_odds',     public.haggle_odds(v_player, f.port_id, p_good, p_fleet),
    'next_odds_pct', round(public.haggle_odds(v_player, f.port_id, p_good, p_fleet) * 100, 1),
    -- 0161 (K7, D14): who of her captains speaks this port's language, in words (null: nobody, or dark)
    'language_line', (select format('%s speaks %s here: +%s%% bargain odds', s.captain, s.language,
                                    public.wc_num('language_haggle_points'))
                        from public.crew_speaker(p_fleet, f.port_id) s),
$n14$);

create temp table before_0161 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

create temp table readers_before_0161 on commit drop as
select 'endure'::text as what, f.id::text as k, voyage.endurance_days(f.id)::text as v from public.fleets f
union all
select 'storm', v.id::text || '/' || m.m::text, voyage.storm_hull_lost(v.id, 100, m.m)::text
  from public.voyages v cross join (values (0.0), (0.5), (1.0)) m(m)
union all
select 'spread', q.port_id::text || '/' || q.good_id::text || '/' || q.fleet_id::text,
       world.spread_effective(q.port_id, q.good_id, q.fleet_id, false)::text
  from (select f.id as fleet_id, p.id as port_id, g.id as good_id
          from (select id from public.fleets order by md5(id::text || '0161f') limit 100) f
         cross join (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || '0161p') limit 2) p
         cross join (select id from public.goods order by md5(id::text || '0161g') limit 2) g) q
union all
select 'odds', pl.id::text || '/' || f.port_id::text || '/' || g.id::text, public.haggle_odds(pl.id, f.port_id, g.id)::text
  from public.players pl
  join public.fleets f on f.player_id = pl.id and f.port_id is not null
  cross join (select id from public.goods order by md5(id::text || '0161h') limit 20) g
 where not pl.is_npc
union all
select 'crew', f.id::text || '/' || e.e, public.crew_pct(f.id, null, e.e)::text
  from public.fleets f cross join (values ('speed'), ('hold'), ('spread'), ('crew_saved')) e(e);

-- ── 2. THE KNOB AND THE ONE SPEAKER ─────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('language_haggle_points', to_jsonb(5),
   '0161 (D14): bargain odds, in points, when a captain seated in the haggling fleet speaks the port''s language. '
   'Read by public.haggle_odds while crew_bite is on. A language is never a gate.')
on conflict (key) do nothing;

create or replace function public.crew_speaker(p_fleet uuid, p_port uuid)
returns table (captain text, language text)
language sql
stable
security definer
set search_path = public, pg_temp
as $cs$
  -- 0161 (D14): THE ONE ANSWER to "who in this fleet speaks this port's language" — the first such
  -- captain seated in her ships (by name) and the language, or no row. Read only while crew_bite is on.
  select o.name, l.name
    from public.ships s
    join public.captain_seats cs on cs.ship_id = s.id
    join public.player_officers po on po.id = cs.player_officer_id
    join public.officers o on o.id = po.officer_id
    join public.captain_languages cl on cl.officer_id = o.id
    join public.port_language pl on pl.port_id = p_port and pl.language = cl.language
    join public.languages l on l.code = cl.language
   where s.fleet_id = p_fleet and public.crew_bite_on()
   order by o.name
   limit 1
$cs$;
revoke all on function public.crew_speaker(uuid, uuid) from public, anon, authenticated;

-- ── 3. THE RE-CUTS (three re-made signatures: create the new, drop the old, keep the ACL) ───────────
do $recut$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0161 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0161 where fn = d.fn order by n loop
      if pg_temp.occurs_0161(v_def, h.old) <> 1 then
        raise exception '0161 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against',
          h.n, d.fn, pg_temp.occurs_0161(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $recut$;
drop function public.crew_pct(uuid, uuid, text, uuid);
drop function public.crew_terms(uuid);
drop function public.haggle_odds(uuid, uuid, uuid);
revoke all on function public.crew_pct(uuid, uuid, text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.crew_terms(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.haggle_odds(uuid, uuid, uuid, uuid) from public, anon, authenticated;
do $acl$
declare d record;
begin
  -- the re-made signatures carry the ACL the old ones had (asserted below); restore any grant the old one held
  for d in select * from defs_before_0161 where fn <> fn_after loop
    if d.acl like '%authenticated=X%' then
      execute format('grant execute on function %s to authenticated', d.fn_after);
    end if;
  end loop;
end $acl$;

-- ── 4. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
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
  v_lis    uuid;
  v_cad    uuid;
  v_leg    jsonb;
  v_voy    uuid;
  v_gem    uuid;
  v_grain  uuid;
  v_a      numeric;
  v_b      numeric;
  v_crew   jsonb := (select value from public.world_config where key = 'crew_bite');
  c_uid constant uuid := '00000000-0161-4000-8000-000000000001';
begin
  select * into b from before_0161;

  -- (a) DARK = the pre-image
  select count(*) into v_bad from readers_before_0161 r
   where r.v is distinct from case r.what
           when 'endure' then voyage.endurance_days(r.k::uuid)::text
           when 'storm'  then voyage.storm_hull_lost(split_part(r.k, '/', 1)::uuid, 100, split_part(r.k, '/', 2)::numeric)::text
           when 'spread' then world.spread_effective(split_part(r.k, '/', 1)::uuid, split_part(r.k, '/', 2)::uuid,
                                                     split_part(r.k, '/', 3)::uuid, false)::text
           when 'odds'   then public.haggle_odds(split_part(r.k, '/', 1)::uuid, split_part(r.k, '/', 2)::uuid, split_part(r.k, '/', 3)::uuid)::text
           when 'crew'   then public.crew_pct(split_part(r.k, '/', 1)::uuid, null, split_part(r.k, '/', 2))::text end;
  if v_bad <> 0 then
    raise exception '0161 self-assert FAIL: % reader answer(s) moved (endurance / storm / spread / odds / crew)', v_bad;
  end if;

  -- (b) THE PROBE — own house, rolled back
  begin
    v_player := public.new_house(c_uid, 'Casa das Linguas', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_cad from public.ports where code = 'CAD';
    perform public.credit(v_player, 'PROBE_TRAITS', 60000,
      public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0161 self-assert')));
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    -- TRADERS: a Gem trader narrows a gem's spread, not a grain's
    select id into v_gem from public.goods where category = 'gems' order by code limit 1;
    select id into v_grain from public.goods where category = 'grain' order by code limit 1;
    v_a := world.spread_effective(v_lis, v_gem, v_fleet, false);
    v_b := world.spread_effective(v_lis, v_grain, v_fleet, false);
    v_r := public.sign_officer(v_player, 'DECOUTRE', v_fleet);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0161 self-assert FAIL: could not hire the Gem trader: %', v_r;
    end if;
    perform public.captain_traits_set_for(v_player, 'DECOUTRE', array['GEM_TRADER']);
    if not (world.spread_effective(v_lis, v_gem, v_fleet, false) < v_a) then
      raise exception '0161 self-assert FAIL: a Gem trader did not narrow a gem''s spread (% → %)', v_a, world.spread_effective(v_lis, v_gem, v_fleet, false);
    end if;
    if world.spread_effective(v_lis, v_grain, v_fleet, false) <> v_b then
      raise exception '0161 self-assert FAIL: a Gem trader moved a grain''s spread';
    end if;
    -- LANGUAGE: she speaks Spanish only; Lisbon speaks Portuguese — nothing
    if public.haggle_odds(v_player, v_lis, v_gem, v_fleet) <> public.haggle_odds(v_player, v_lis, v_gem) then
      raise exception '0161 self-assert FAIL: a captain who does not speak Portuguese changed the odds at Lisbon';
    end if;
    -- PROVISIONER: the supplies last longer
    v_a := voyage.endurance_days(v_fleet);
    v_r := public.sign_officer(v_player, 'DARELL', v_fleet);
    perform public.captain_traits_set_for(v_player, 'DARELL', array['PROVISIONER']);
    if not coalesce((v_r->>'ok')::boolean, false) or not (voyage.endurance_days(v_fleet) > v_a) then
      raise exception '0161 self-assert FAIL: a Provisioner did not lengthen the supplies (% → %): %', v_a, voyage.endurance_days(v_fleet), v_r;
    end if;
    -- LANGUAGE again: a Portuguese speaker (ELCANO) adds the points, and the line says so
    v_a := public.haggle_odds(v_player, v_lis, v_gem, v_fleet);
    v_r := public.sign_officer(v_player, 'ELCANO', v_fleet);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0161 self-assert FAIL: could not hire the speaker: %', v_r;
    end if;
    if public.haggle_odds(v_player, v_lis, v_gem, v_fleet)
       <> least(public.wc_num('haggle_success_max'), round(v_a + public.wc_num('language_haggle_points') / 100.0, 4)) then
      raise exception '0161 self-assert FAIL: a Portuguese speaker at Lisbon gave odds % (expected % + % points)',
        public.haggle_odds(v_player, v_lis, v_gem, v_fleet), v_a, public.wc_num('language_haggle_points');
    end if;
    if (select count(*) from public.crew_speaker(v_fleet, v_lis)) <> 1 then
      raise exception '0161 self-assert FAIL: the speaker is not found';
    end if;
    -- PILOT: a storm's loss on her fleet's voyage, read at the departure
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(c.roadstead_lat, c.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches c where a.port_id = v_lis and c.port_id = v_cad;
    v_voy := voyage.depart(v_fleet, voyage.segments_from_course(v_leg), v_lis, v_cad, now() - interval '1 hour');
    v_a := voyage.storm_hull_lost(v_voy, 100, 0.5);
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fleet;
    v_r := public.seat_captain_for(v_player, 'DECOUTRE', null);   -- a barca has three cabins: the Gem trader goes ashore
    v_r := public.sign_officer(v_player, 'URDANETA', v_fleet);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0161 self-assert FAIL: could not hire the Pilot: %', v_r;
    end if;
    perform public.captain_traits_set_for(v_player, 'URDANETA', array['PILOT']);
    if not (voyage.storm_hull_lost(v_voy, 100, 0.5) < v_a) then
      raise exception '0161 self-assert FAIL: a Pilot did not shrink a storm''s loss (% → %)', v_a, voyage.storm_hull_lost(v_voy, 100, 0.5);
    end if;
    -- the same whenever it is read: homesick NOW but not at the departure, and the storm does not move
    v_b := voyage.storm_hull_lost(v_voy, 100, 0.5);
    update public.captain_state set home_seen_at = now() - interval '72 hours 30 minutes'
     where player_officer_id in (select po.id from public.player_officers po where po.player_id = v_player);
    if voyage.storm_hull_lost(v_voy, 100, 0.5) <> v_b then
      raise exception '0161 self-assert FAIL: a storm read at the departure moved with the clock (% → %)', v_b, voyage.storm_hull_lost(v_voy, 100, 0.5);
    end if;
    if public.crew_pct(v_fleet, null, 'storm') = public.crew_pct(v_fleet, null, 'storm', null, (select departed_at from public.voyages where id = v_voy)) then
      raise exception '0161 self-assert FAIL: the probe proves nothing — homesickness now and at the departure read the same';
    end if;
    -- DARK again: every one of them gone
    update public.world_config set value = 'false'::jsonb where key = 'crew_bite';
    if voyage.storm_hull_lost(v_voy, 100, 0.5) <> round(100 * (0.08 + 0.17 * 0.5), 2)
       or public.haggle_odds(v_player, v_lis, v_gem, v_fleet) <> public.haggle_odds(v_player, v_lis, v_gem)
       or public.crew_pct(v_fleet, null, 'supplies') <> 0 or public.crew_pct(v_fleet, null, 'category_spread', v_gem) <> 0 then
      raise exception '0161 self-assert FAIL: dark, a K7 effect still bites';
    end if;
    raise exception 'PROBE_ROLLBACK_0161';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0161' then raise; end if;
  end;
  if exists (select 1 from public.players where company_name = 'Casa das Linguas')
     or (select value from public.world_config where key = 'crew_bite') <> v_crew then
    raise exception '0161 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (c) THE RE-CUTS reverse; the re-made signatures keep their ACL; the old ones are gone
  for d in select * from defs_before_0161 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn_after::regprocedure), E'\r', '');
    for h in select * from hunks_0161 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0161(v_def, h.new) <> 1 then
        raise exception '0161 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0161 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn_after::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0161 self-assert FAIL: % changed its ACL (% → %), volatility, definer or config', d.fn_after, d.acl, v_p.acl;
    end if;
    if d.fn <> d.fn_after and to_regprocedure(d.fn) is not null then
      raise exception '0161 self-assert FAIL: the old signature % is still there', d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0161 self-assert FAIL: the client entry points moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0161 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;

  raise notice '0161 self-assert ok: A CAPTAIN READS THE WEATHER, KEEPS THE CASKS AND KNOWS HER GOODS (K7, DARK). DARK: % reader answer(s) — endurance, a storm''s loss on every voyage, spreads, bargain odds, the four live effects — equal their pre-images. The probe (crew_bite lit, rolled back): a Gem trader narrowed a gem''s spread and left a grain''s; a Provisioner lengthened the supplies; a Pilot shrank a storm''s loss, read at the departure; a Spanish-only captain at Lisbon added nothing to the odds and a Portuguese speaker added % points; dark again, all gone. Three signatures re-made with their ACLs; no new entry point; 0 client write grants.',
    (select count(*) from readers_before_0161), public.wc_num('language_haggle_points');
end $$;
