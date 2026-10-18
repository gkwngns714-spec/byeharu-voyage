-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0156 — A CAPTAIN HAS A GRADE, A KIT AND A TONGUE  (K4 "captains I": who they are — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §4.1, §4.2, §4.9, §6.2 and §8 row K4 (research:
-- docs/research/UWO_SKILLS_AND_CAPTAINS.md §3, §4.4, §4.6). The owner, 2026-10-17: *"the captains of
-- 대항해시대 오리진 … apply it to the game as well. this is very important."* — and row 61 (*"S rank the
-- best, A, B C … The S ranked captain will have 5 skill slots, with 10 skills. A 4 skill slots, with
-- 8 skills, you get the pattern"*), row 66 (*"trading specialized captains, such as jewelery trader,
-- meat trader etc. make one captain for each role. combat close, long range"*), row 70 (*"navigator
-- could be increasing speed, or make wheather more fable … surgeon could be a healer"*) and row 113
-- (*"captain traits"*). D10, D14 and D15 were approved by default (no answer in 2 minutes = yes) —
-- decided by default; the owner may reverse any of them, and each one is data.
--
-- ── WHAT THIS FILE DOES (data/officers.json + data/captains.json are the one authority,
--    scripts/build-captains.mjs generates data/captains.generated.json from them, and
--    scripts/db/world-guard.mjs holds the database to all three on every apply) ──────────────────
--   THE CATALOGUE  public.trait_foci (3), public.captain_grades (C/B/A/S: 2/4 · 3/6 · 4/8 · 5/10 trait
--       slots / traits known; floors 4 / 5.5 / 7 / 8.5 %), public.crew_effects (11 effects, the four
--       LIVE ones flagged — the four public.fleet_officer_bonus has always served), public.traits (25:
--       the four live jobs, Pilot, Provisioner, 17 goods traders, Gunner, Boarder) + public.trait_effects,
--       public.languages (20), public.port_language (every harbour, by the rule in data/captains.json).
--   THE PEOPLE     42 new captains (63 → 105: every job is held by at least two, one C or B and one A or
--       S, D15); public.captain_profile (grade at birth — the highest floor her job value reaches, D10 —
--       and job), public.captain_traits (her kit of ten: the job at her value, nine more at 60 %),
--       public.captain_languages (her home's, plus one for A and two for S, D14).
--   THE MIRROR     officers.specialty = captain_profile.job_trait = captain_traits ord 1, and
--       officers.bonus_pct = ord 1's value, for every captain (asserted here, held by the guard; the two
--       columns are retired in K9). The specialty CHECK of four values becomes a FOREIGN KEY to
--       public.traits (NOT VALID, then VALIDATE).
--   THE READS      world.captain_card(officer) — ONE builder of what a captain is (grade, slots, job,
--       focus, the traits she knows with their lines and whether each works today, the languages she
--       speaks and the sentence for them), composed by world.inn (every guest) and world.officers
--       (every captain in the Codex). public.trait_in_use(trait) is the ONE answer to "does this trait
--       work today", and world.officers' `specialties_read` is now derived from it (the same four, in
--       the same order — asserted). public.trait_effect_words is the one line-builder.
--   THE HUNKS (sliced from the bodies live after 0153, LF-normalised, each occurring once, each body
--       reversing to its pre-image, ACLs unchanged):
--       world.inn        every guest object is `world.captain_card(o.id) || <the 0119 object>`
--       world.officers   the same, per captain; and `v_read` (its own "ONE place the game states which
--                        of them work") is derived from public.trait_in_use instead of typed
--
-- ── DARK: WHAT IT DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────────
-- Change any number the game computes today. Nothing reads a trait beyond the job (ord 1), and the job
-- is read exactly as before, through officers.specialty / bonus_pct by public.fleet_officer_bonus — a
-- new captain's job is none of its four, so hiring her adds nothing to any fleet until K5's
-- public.crew_pct and crew_bite. Who is in an inn is world.inn_present per captain, untouched, so every
-- captain of today is in exactly the rooms she was in (asserted over every harbour); the 42 new ones
-- join rooms beside them. No cabin, seat, level, homesickness, promotion or language effect (K5-K8).
-- No crew_effects cap: the cap per effect arrives with its one reader, public.crew_pct, in K5 (a number
-- nothing reads would be a second source of truth beside officer_bonus_cap_pct). No gate of any kind
-- (§12): a language, a grade or a trait never refuses anything.
--
-- ── THE PROOF (one rolled-back statement or loop each) ──────────────────────────────────────────
-- (a) the catalogue and the roster: 105 captains, 63 of them unmoved column for column, the counts of
--     every table derived from the data's own sizes (pasted by the generator), the mirror for all 105,
--     every grade by D10's floors (the 63 of today fall 18 / 17 / 20 / 8, the plan's count), every kit
--     ten distinct traits with the job first, every job held by ≥ 2 captains (one C/B, one A/S), every
--     focus a captain of every grade; every harbour one language, every language spoken somewhere.
-- (b) DARK: fleet_officer_bonus for every fleet × the four live jobs = its pre-image; inn_present for
--     every one of the 63 × every harbour at this quarter hour = its pre-image.
-- (c) the reads: world.inn for 60 harbours (fixed sample) serves, restricted to the 63, exactly its
--     pre-image objects key for key and in order, plus the card keys; world.officers serves the same
--     cap, the same `specialties_read`, and for the 63 the pre-image objects plus the card keys;
--     every card's grade, job and traits are the tables' own; a new captain's job does not take effect.
-- (d) every new captain is in some inn within the next 24 hours (96 quarter hours), derived; the
--     average and fullest room printed (0073's receipt).
-- (e) the re-cuts reverse to their pre-images; ACL / volatility / definer / config unmoved; no new
--     client entry point; 0 client write grants; the new tables are server-only.
-- (f) timing (notice only): world.inn over the sample and world.officers, before and after.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Pre-images first (ACCESS SHARE). The catalogue tables are new. Then ONE `alter table public.officers`
-- (drop the four-value CHECK, add the FOREIGN KEY NOT VALID): ACCESS EXCLUSIVE on public.officers,
-- retried on lock_timeout / deadlock (5 tries), held to commit — after it come only the 42 inserts, the
-- validate and the proof (seconds). public.fleet_officer_bonus (speed, cargo space, spread, raid losses)
-- and the Inn wait that long. Deploy with the clock unwound (DEPLOY_RUNBOOK): unwind_the_clock() →
-- db push → wind_the_clock().
--
-- ROLLBACK: a forward slice restoring the two bodies (their hunks' OLD text), the four-value CHECK in
-- place of the FOREIGN KEY, and deleting the 42 captains (only after asserting no signing references
-- one — `player_officers` keeps a captain a company hired) and dropping the ten new tables and three
-- functions. Nothing a company holds is touched by this file.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once,
-- ACLs unchanged: world.inn (0119), world.officers (0127).
-- VERSION: 0156 (K2 = 0154, K3 = 0155 apply first; the coordinator's numbering, 2026-10-18). Written on 0153.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0156(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before anything is locked) ───────────────
create temp table defs_before_0156 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.inn(uuid)'), ('world.officers()')) f(fn);

create temp table untouched_before_0156 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.fleet_officer_bonus(uuid, text)'), ('world.inn_present(uuid, uuid, integer)'),
               ('world.inn_chance(uuid, uuid)'), ('world.officer_scarcity(numeric)'), ('world.inn_shift(timestamp with time zone)'),
               ('cmd.hire_officer(text, uuid)'), ('public.sign_officer(uuid, text, uuid)'),
               ('public.post_officer_to(uuid, text, uuid)'), ('world.npc_fleet_card(uuid)')) f(fn);

create temp table hunks_0156 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0156 (fn, n, old, new) values
  ('world.inn(uuid)', 1, $o1$    'present', (select coalesce(jsonb_agg(jsonb_build_object($o1$, $n1$    -- 0156: every guest carries her card (world.captain_card): grade, job, traits, languages.
    'present', (select coalesce(jsonb_agg(world.captain_card(o.id) || jsonb_build_object($n1$),
  ('world.officers()', 1, $o2$      select coalesce(jsonb_agg(jsonb_build_object(
               'code', o.code$o2$, $n2$      -- 0156: every captain carries her card (world.captain_card): grade, job, traits, languages.
      select coalesce(jsonb_agg(world.captain_card(o.id) || jsonb_build_object(
               'code', o.code$n2$),
  ('world.officers()', 2, $o3$  -- 0027: SURGEON joins them. ALL FOUR specialties are read by a rule now — NAVIGATOR by
  -- voyage.fleet_speed (0015), QUARTERMASTER by public.ship_hold_capacity and PURSER by
  -- world.spread_effective (0017/0022), SURGEON by public.raid_crew_lost (this file). This array is
  -- the ONE place the game states which of them work, and it is no longer a list of exceptions.
  v_read   constant text[] := array['NAVIGATOR', 'QUARTERMASTER', 'PURSER', 'SURGEON'];$o3$, $n3$  -- 0027: SURGEON joins them, and all four jobs are read by a rule — NAVIGATOR by voyage.fleet_speed
  -- (0015), QUARTERMASTER by public.ship_hold_capacity and PURSER by world.spread_effective
  -- (0017/0022), SURGEON by public.raid_crew_lost (0027). 0156: the list is DERIVED from the trait
  -- catalogue (public.trait_in_use: an effect of the trait is live), the ONE place the game states
  -- which traits work today; it gives exactly these four, in this order, until K5 lights more.
  v_read   constant text[] := array(select t.code from public.traits t where public.trait_in_use(t.code) order by t.ord);$n3$);

create temp table before_0156 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.officers) as officers,
       world.inn_shift() as shift,
       (select md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s|%s', o.code, o.name, o.specialty, o.bonus_pct, o.wage_ducats,
                                     o.nation_id, o.home_port_id, o.blurb), '/' order by o.code))
          from public.officers o) as roster_hash;

create temp table old_officers_0156 on commit drop as select id, code from public.officers;

-- what a company's captains are worth today, every fleet × the four live jobs (the DARK claim)
create temp table bonus_before_0156 on commit drop as
select f.id as fleet_id, s.sp, public.fleet_officer_bonus(f.id, s.sp) as v
  from public.fleets f cross join (values ('NAVIGATOR'), ('QUARTERMASTER'), ('PURSER'), ('SURGEON')) s(sp);

-- who is in which room this quarter hour, every captain of today × every harbour
create temp table rooms_before_0156 on commit drop as
select o.id as officer_id, p.id as port_id, world.inn_present(o.id, p.id, (select shift from before_0156)) as here
  from public.officers o cross join public.ports p where p.kind = 'HARBOUR';

-- the two reads, as a player would get them (no player here: signed = false, fleet/level null)
create temp table inn_before_0156 on commit drop as
select p.id as port_id, world.inn(p.id) as j
  from (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || '0156') limit 60) p;
create temp table officers_before_0156 on commit drop as select world.officers() as j;

do $time$
declare t0 timestamptz; v_inn numeric; v_off numeric;
begin
  t0 := clock_timestamp();
  perform world.inn(port_id) from inn_before_0156;
  v_inn := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp();
  perform world.officers();
  v_off := extract(epoch from clock_timestamp() - t0) * 1000;
  create temp table time_before_0156 on commit drop as select v_inn as inn_ms, v_off as officers_ms;
end $time$;

-- ── 2. THE CATALOGUE (new tables; server-only — served through world.inn / world.officers) ───────
create table if not exists public.trait_foci (
  code text primary key check (code in ('exploration', 'trading', 'combat')),
  word text not null,
  ord  int  not null unique
);
comment on table public.trait_foci is
  '0156: Origin''s three foci [UWO §3.2] and the word the player reads (data/captains.json). Server-only.';
alter table public.trait_foci enable row level security;
revoke all on table public.trait_foci from public, anon, authenticated;

create table if not exists public.captain_grades (
  code      text primary key check (code ~ '^[A-Z]+$'),
  ord       int  not null unique check (ord >= 1),
  slots     int  not null check (slots >= 1),
  known     int  not null check (known >= slots),
  floor_pct numeric not null check (floor_pct > 0)
);
comment on table public.captain_grades is
  '0156: the grade ladder, as data (OWNER O3 "for now": a grade above S costs a row). slots = traits in use at '
  'once, known = traits she knows; floor_pct = the least job value of the grade (D10) and, from K8, the value a '
  'promotion lifts every trait to (D12). Authored in data/captains.json. Server-only.';
alter table public.captain_grades enable row level security;
revoke all on table public.captain_grades from public, anon, authenticated;

create table if not exists public.crew_effects (
  code   text primary key check (code ~ '^[a-z_]+$'),
  ord    int  not null unique,
  scope  text not null check (scope in ('fleet', 'ship')),
  live   boolean not null,
  words  text not null check (words like '%{pct}%'),
  waits  text not null,
  reader text not null
);
comment on table public.crew_effects is
  '0156: what a trait can do. live = a rule reads it TODAY (crew_bite off): the four public.fleet_officer_bonus '
  'serves, and only for a captain''s job. words = the trait card''s line ({pct}, {goods}); waits = the sentence '
  'when it does not work for her yet; reader = the ONE rule that reads it. The per-effect cap arrives with '
  'public.crew_pct (K5). Authored in data/captains.json. Server-only.';
alter table public.crew_effects enable row level security;
revoke all on table public.crew_effects from public, anon, authenticated;

create table if not exists public.traits (
  code       text primary key check (code ~ '^[A-Z_]+$'),
  ord        int  not null unique check (ord >= 1),
  word       text not null,
  focus      text not null references public.trait_foci(code),
  goods      text,
  goods_word text,
  check ((goods is null) = (goods_word is null))
);
comment on table public.traits is
  '0156: the 25 traits — a captain''s job is her first (OWNER O5, O6; D15). goods = the goods category a trader '
  'works on (data/goods.json), goods_word how the card names it. Authored in data/captains.json. Server-only.';
alter table public.traits enable row level security;
revoke all on table public.traits from public, anon, authenticated;

create table if not exists public.trait_effects (
  trait  text not null references public.traits(code) on delete cascade,
  effect text not null references public.crew_effects(code),
  ord    int  not null check (ord >= 1),
  mult   numeric not null check (mult > 0),
  primary key (trait, effect),
  unique (trait, ord)
);
comment on table public.trait_effects is
  '0156: what each trait does, effect by effect (the surgeon carries two). Authored in data/captains.json. Server-only.';
alter table public.trait_effects enable row level security;
revoke all on table public.trait_effects from public, anon, authenticated;

create table if not exists public.languages (
  code text primary key check (code ~ '^[A-Z]+$'),
  ord  int  not null unique,
  name text not null
);
comment on table public.languages is
  '0156: the twenty languages (D14). A language is never a gate. Authored in data/captains.json. Server-only.';
alter table public.languages enable row level security;
revoke all on table public.languages from public, anon, authenticated;

create table if not exists public.port_language (
  port_id  uuid primary key references public.ports(id) on delete cascade,
  language text not null references public.languages(code)
);
comment on table public.port_language is
  '0156: the one language of every harbour (D14): its founding nation''s, else its culture''s, else (Latin, no '
  'nation) its country''s — scripts/build-captains.mjs, held by the world guard. Not the flag: a city won by '
  'influence keeps its language. Server-only.';
alter table public.port_language enable row level security;
revoke all on table public.port_language from public, anon, authenticated;

create table if not exists public.captain_profile (
  officer_id uuid primary key references public.officers(id) on delete cascade,
  grade      text not null references public.captain_grades(code),
  job_trait  text not null references public.traits(code)
);
comment on table public.captain_profile is
  '0156: who a captain IS at birth — her grade (D10) and job (her first trait). A company''s copy of her (grade '
  'after promotion, traits in use) is the signing''s, from K5. Generated by scripts/build-captains.mjs. Server-only.';
alter table public.captain_profile enable row level security;
revoke all on table public.captain_profile from public, anon, authenticated;

create table if not exists public.captain_traits (
  officer_id uuid not null references public.officers(id) on delete cascade,
  ord        int  not null check (ord >= 1),
  trait      text not null references public.traits(code),
  base_pct   numeric not null check (base_pct > 0),
  primary key (officer_id, ord),
  unique (officer_id, trait)
);
comment on table public.captain_traits is
  '0156: every captain''s kit of ten ordered traits (D15): ord 1 = her job at her value (= officers.bonus_pct), '
  'the rest at 60 %. She knows the first captain_grades.known of them. Generated by scripts/build-captains.mjs. '
  'Server-only.';
alter table public.captain_traits enable row level security;
revoke all on table public.captain_traits from public, anon, authenticated;

create table if not exists public.captain_languages (
  officer_id uuid not null references public.officers(id) on delete cascade,
  ord        int  not null check (ord >= 1),
  language   text not null references public.languages(code),
  primary key (officer_id, ord),
  unique (officer_id, language)
);
comment on table public.captain_languages is
  '0156: the languages a captain speaks, her home harbour''s first (D14). Generated by scripts/build-captains.mjs. '
  'Server-only.';
alter table public.captain_languages enable row level security;
revoke all on table public.captain_languages from public, anon, authenticated;

insert into public.trait_foci (code, word, ord) values
  ('exploration', 'Exploration', 1),
  ('trading', 'Trading', 2),
  ('combat', 'Combat', 3);
insert into public.captain_grades (code, ord, slots, known, floor_pct) values
  ('C', 1, 2, 4, 4),
  ('B', 2, 3, 6, 5.5),
  ('A', 3, 4, 8, 7),
  ('S', 4, 5, 10, 8.5);
insert into public.crew_effects (code, ord, scope, live, words, waits, reader) values
  ('speed', 1, 'fleet', true, '+{pct}% speed', 'Not in use yet.', 'voyage.fleet_speed'),
  ('hold', 2, 'fleet', true, '+{pct}% cargo space', 'Not in use yet.', 'public.ship_hold_capacity'),
  ('spread', 3, 'fleet', true, '+{pct}% better prices', 'Not in use yet.', 'world.spread_effective'),
  ('crew_saved', 4, 'fleet', true, '−{pct}% crew lost to pirates', 'Not in use yet.', 'public.raid_crew_lost'),
  ('homesick_relief', 5, 'fleet', false, '−{pct} points of homesickness', 'Not in use yet.', 'public.crew_pct'),
  ('storm', 6, 'fleet', false, '−{pct}% storm damage', 'Not in use yet.', 'voyage.settle'),
  ('supplies', 7, 'fleet', false, '+{pct}% days of supplies', 'Not in use yet.', 'voyage.endurance_days'),
  ('category_spread', 8, 'fleet', false, '+{pct}% better prices on {goods}', 'Not in use yet.', 'world.spread_effective'),
  ('accuracy', 9, 'ship', false, '+{pct}% accuracy', 'Works when combat arrives.', 'world.ship_stats'),
  ('reach', 10, 'ship', false, '+{pct}% reach', 'Works when combat arrives.', 'world.ship_stats'),
  ('attack', 11, 'ship', false, '+{pct}% attack', 'Works when combat arrives.', 'world.ship_stats');
insert into public.traits (code, ord, word, focus, goods, goods_word) values
  ('NAVIGATOR', 1, 'Navigator', 'exploration', null, null),
  ('QUARTERMASTER', 2, 'Quartermaster', 'trading', null, null),
  ('PURSER', 3, 'Purser', 'trading', null, null),
  ('SURGEON', 4, 'Surgeon', 'exploration', null, null),
  ('PILOT', 5, 'Pilot', 'exploration', null, null),
  ('PROVISIONER', 6, 'Provisioner', 'exploration', null, null),
  ('GRAIN_TRADER', 7, 'Grain trader', 'trading', 'grain', 'grain'),
  ('FOOD_TRADER', 8, 'Food trader', 'trading', 'food', 'food'),
  ('DRINK_TRADER', 9, 'Drink trader', 'trading', 'drink', 'drink'),
  ('TOBACCO_TRADER', 10, 'Tobacco trader', 'trading', 'tobacco', 'tobacco'),
  ('SPICE_TRADER', 11, 'Spice trader', 'trading', 'spice', 'spice'),
  ('MEDICINE_TRADER', 12, 'Medicine trader', 'trading', 'medicine', 'medicine'),
  ('DYE_TRADER', 13, 'Dye trader', 'trading', 'dye', 'dye'),
  ('CLOTH_TRADER', 14, 'Cloth trader', 'trading', 'cloth', 'cloth'),
  ('METAL_TRADER', 15, 'Metal trader', 'trading', 'metal', 'metal'),
  ('GEM_TRADER', 16, 'Gem trader', 'trading', 'gems', 'gems'),
  ('CRAFTS_TRADER', 17, 'Crafts trader', 'trading', 'crafts', 'crafts'),
  ('WEAPONS_TRADER', 18, 'Weapons trader', 'trading', 'weapons', 'weapons'),
  ('GUNS_TRADER', 19, 'Guns trader', 'trading', 'guns', 'guns'),
  ('SHIP_SUPPLIES_TRADER', 20, 'Ship-supplies trader', 'trading', 'ship-supplies', 'ship supplies'),
  ('ART_TRADER', 21, 'Art trader', 'trading', 'art', 'art'),
  ('BOOK_TRADER', 22, 'Book trader', 'trading', 'books', 'books'),
  ('ANIMAL_TRADER', 23, 'Animal trader', 'trading', 'animals', 'animals'),
  ('GUNNER', 24, 'Gunner', 'combat', null, null),
  ('BOARDER', 25, 'Boarder', 'combat', null, null);
insert into public.trait_effects (trait, effect, ord, mult) values
  ('NAVIGATOR', 'speed', 1, 1),
  ('QUARTERMASTER', 'hold', 1, 1),
  ('PURSER', 'spread', 1, 1),
  ('SURGEON', 'crew_saved', 1, 1),
  ('SURGEON', 'homesick_relief', 2, 1),
  ('PILOT', 'storm', 1, 1),
  ('PROVISIONER', 'supplies', 1, 1),
  ('GRAIN_TRADER', 'category_spread', 1, 1),
  ('FOOD_TRADER', 'category_spread', 1, 1),
  ('DRINK_TRADER', 'category_spread', 1, 1),
  ('TOBACCO_TRADER', 'category_spread', 1, 1),
  ('SPICE_TRADER', 'category_spread', 1, 1),
  ('MEDICINE_TRADER', 'category_spread', 1, 1),
  ('DYE_TRADER', 'category_spread', 1, 1),
  ('CLOTH_TRADER', 'category_spread', 1, 1),
  ('METAL_TRADER', 'category_spread', 1, 1),
  ('GEM_TRADER', 'category_spread', 1, 1),
  ('CRAFTS_TRADER', 'category_spread', 1, 1),
  ('WEAPONS_TRADER', 'category_spread', 1, 1),
  ('GUNS_TRADER', 'category_spread', 1, 1),
  ('SHIP_SUPPLIES_TRADER', 'category_spread', 1, 1),
  ('ART_TRADER', 'category_spread', 1, 1),
  ('BOOK_TRADER', 'category_spread', 1, 1),
  ('ANIMAL_TRADER', 'category_spread', 1, 1),
  ('GUNNER', 'accuracy', 1, 1),
  ('GUNNER', 'reach', 2, 1),
  ('BOARDER', 'attack', 1, 1);
insert into public.languages (code, ord, name) values
  ('PORTUGUESE', 1, 'Portuguese'),
  ('SPANISH', 2, 'Spanish'),
  ('FRENCH', 3, 'French'),
  ('ITALIAN', 4, 'Italian'),
  ('ENGLISH', 5, 'English'),
  ('DUTCH', 6, 'Dutch'),
  ('GERMAN', 7, 'German'),
  ('NORDIC', 8, 'Nordic'),
  ('SLAVIC', 9, 'Slavic'),
  ('TURKISH', 10, 'Turkish'),
  ('ARABIC', 11, 'Arabic'),
  ('PERSIAN', 12, 'Persian'),
  ('INDIC', 13, 'Indic'),
  ('MALAY', 14, 'Malay'),
  ('THAI', 15, 'Thai'),
  ('CHINESE', 16, 'Chinese'),
  ('JAPANESE', 17, 'Japanese'),
  ('KOREAN', 18, 'Korean'),
  ('SWAHILI', 19, 'Swahili'),
  ('GUINEAN', 20, 'Guinean');
insert into public.port_language (port_id, language)
select p.id, w.language
  from (values
  ('ACA', 'SPANISH'),
  ('ACC', 'PORTUGUESE'),
  ('ADE', 'TURKISH'),
  ('AGA', 'ARABIC'),
  ('ALE', 'TURKISH'),
  ('ALG', 'TURKISH'),
  ('AMB', 'MALAY'),
  ('AMS', 'DUTCH'),
  ('ANC', 'ITALIAN'),
  ('ANG', 'PORTUGUESE'),
  ('ANT', 'TURKISH'),
  ('ARI', 'SPANISH'),
  ('ARK', 'SLAVIC'),
  ('ARP', 'SPANISH'),
  ('AYU', 'THAI'),
  ('BAN', 'MALAY'),
  ('BAR', 'SPANISH'),
  ('BAS', 'PERSIAN'),
  ('BEI', 'TURKISH'),
  ('BEL', 'PORTUGUESE'),
  ('BER', 'NORDIC'),
  ('BIL', 'SPANISH'),
  ('BND', 'MALAY'),
  ('BNT', 'MALAY'),
  ('BOR', 'FRENCH'),
  ('BOS', 'ENGLISH'),
  ('BRI', 'ENGLISH'),
  ('BRS', 'ENGLISH'),
  ('BRU', 'SPANISH'),
  ('BSR', 'TURKISH'),
  ('BUE', 'SPANISH'),
  ('BUS', 'KOREAN'),
  ('BUV', 'SPANISH'),
  ('CAD', 'SPANISH'),
  ('CAG', 'SPANISH'),
  ('CAL', 'GUINEAN'),
  ('CAP', 'PORTUGUESE'),
  ('CAR', 'SPANISH'),
  ('CEB', 'SPANISH'),
  ('CEU', 'SPANISH'),
  ('CHE', 'INDIC'),
  ('CHI', 'INDIC'),
  ('CHS', 'ITALIAN'),
  ('CID', 'PORTUGUESE'),
  ('CLL', 'SPANISH'),
  ('CLS', 'FRENCH'),
  ('COL', 'PORTUGUESE'),
  ('CON', 'SPANISH'),
  ('COP', 'NORDIC'),
  ('COQ', 'SPANISH'),
  ('COR', 'ITALIAN'),
  ('CPT', 'GUINEAN'),
  ('CRK', 'ENGLISH'),
  ('CUM', 'SPANISH'),
  ('DBR', 'ITALIAN'),
  ('DIL', 'MALAY'),
  ('DIU', 'PORTUGUESE'),
  ('DUB', 'ENGLISH'),
  ('ELM', 'PORTUGUESE'),
  ('FAM', 'ITALIAN'),
  ('FEO', 'TURKISH'),
  ('FNC', 'PORTUGUESE'),
  ('FUK', 'JAPANESE'),
  ('FUZ', 'CHINESE'),
  ('GAL', 'INDIC'),
  ('GDA', 'SLAVIC'),
  ('GIB', 'SPANISH'),
  ('GOA', 'ITALIAN'),
  ('GOR', 'GUINEAN'),
  ('GUA', 'CHINESE'),
  ('GYE', 'SPANISH'),
  ('HAD', 'ARABIC'),
  ('HAG', 'MALAY'),
  ('HAM', 'GERMAN'),
  ('HAN', 'MALAY'),
  ('HAV', 'SPANISH'),
  ('HER', 'ITALIAN'),
  ('HIR', 'JAPANESE'),
  ('HNL', 'MALAY'),
  ('HOB', 'MALAY'),
  ('HOI', 'MALAY'),
  ('HON', 'CHINESE'),
  ('HOO', 'INDIC'),
  ('HOR', 'PORTUGUESE'),
  ('HRN', 'DUTCH'),
  ('HUA', 'SPANISH'),
  ('INC', 'KOREAN'),
  ('ISL', 'PORTUGUESE'),
  ('IST', 'TURKISH'),
  ('IZM', 'TURKISH'),
  ('JAF', 'INDIC'),
  ('JAK', 'MALAY'),
  ('JAM', 'ENGLISH'),
  ('JED', 'TURKISH'),
  ('JEJ', 'KOREAN'),
  ('KAG', 'JAPANESE'),
  ('KAL', 'SLAVIC'),
  ('KAN', 'INDIC'),
  ('KAR', 'INDIC'),
  ('KHA', 'INDIC'),
  ('KIL', 'SWAHILI'),
  ('KIN', 'ENGLISH'),
  ('KOC', 'INDIC'),
  ('KOL', 'INDIC'),
  ('KOZ', 'INDIC'),
  ('KUP', 'MALAY'),
  ('LAG', 'GUINEAN'),
  ('LAR', 'FRENCH'),
  ('LEH', 'FRENCH'),
  ('LEI', 'ENGLISH'),
  ('LIS', 'PORTUGUESE'),
  ('LIV', 'ITALIAN'),
  ('LNG', 'NORDIC'),
  ('LON', 'ENGLISH'),
  ('LPA', 'SPANISH'),
  ('LUA', 'PORTUGUESE'),
  ('LUB', 'GERMAN'),
  ('MAC', 'PORTUGUESE'),
  ('MAK', 'MALAY'),
  ('MAL', 'PORTUGUESE'),
  ('MAN', 'ARABIC'),
  ('MAS', 'SWAHILI'),
  ('MAT', 'JAPANESE'),
  ('MCH', 'INDIC'),
  ('MES', 'SPANISH'),
  ('MID', 'DUTCH'),
  ('MLE', 'ARABIC'),
  ('MLG', 'SPANISH'),
  ('MLN', 'SWAHILI'),
  ('MNG', 'INDIC'),
  ('MNL', 'SPANISH'),
  ('MOC', 'TURKISH'),
  ('MOG', 'SWAHILI'),
  ('MOK', 'KOREAN'),
  ('MOM', 'SWAHILI'),
  ('MRS', 'FRENCH'),
  ('MTY', 'SPANISH'),
  ('MUM', 'INDIC'),
  ('MUS', 'ARABIC'),
  ('MYE', 'INDIC'),
  ('MZT', 'SPANISH'),
  ('NAG', 'JAPANESE'),
  ('NAH', 'JAPANESE'),
  ('NAM', 'KOREAN'),
  ('NAN', 'FRENCH'),
  ('NAP', 'SPANISH'),
  ('NAV', 'SPANISH'),
  ('NEW', 'ENGLISH'),
  ('NIN', 'CHINESE'),
  ('NUU', 'NORDIC'),
  ('OLD', 'PORTUGUESE'),
  ('OPO', 'PORTUGUESE'),
  ('ORA', 'TURKISH'),
  ('OSA', 'JAPANESE'),
  ('OUI', 'GUINEAN'),
  ('PAI', 'SPANISH'),
  ('PAL', 'SPANISH'),
  ('PAN', 'SPANISH'),
  ('PAR', 'DUTCH'),
  ('PAT', 'TURKISH'),
  ('PLM', 'SPANISH'),
  ('PLO', 'GUINEAN'),
  ('PLY', 'ENGLISH'),
  ('PON', 'PORTUGUESE'),
  ('POR', 'SPANISH'),
  ('PRT', 'SPANISH'),
  ('PTH', 'ENGLISH'),
  ('PTT', 'THAI'),
  ('PUL', 'INDIC'),
  ('QUA', 'CHINESE'),
  ('QUE', 'FRENCH'),
  ('REA', 'SPANISH'),
  ('REC', 'PORTUGUESE'),
  ('REY', 'NORDIC'),
  ('RHO', 'TURKISH'),
  ('RIG', 'SLAVIC'),
  ('RIO', 'PORTUGUESE'),
  ('ROT', 'DUTCH'),
  ('SAF', 'ARABIC'),
  ('SAI', 'GUINEAN'),
  ('SAK', 'JAPANESE'),
  ('SAL', 'ARABIC'),
  ('SAN', 'SPANISH'),
  ('SAO', 'GUINEAN'),
  ('SDG', 'SPANISH'),
  ('SET', 'PORTUGUESE'),
  ('SFR', 'SPANISH'),
  ('SGO', 'SPANISH'),
  ('SHI', 'JAPANESE'),
  ('SLV', 'PORTUGUESE'),
  ('SNL', 'SPANISH'),
  ('SNT', 'FRENCH'),
  ('SOF', 'PORTUGUESE'),
  ('SOS', 'PORTUGUESE'),
  ('SOY', 'PORTUGUESE'),
  ('SPL', 'ITALIAN'),
  ('SRT', 'INDIC'),
  ('STA', 'ENGLISH'),
  ('STG', 'ENGLISH'),
  ('STJ', 'ENGLISH'),
  ('STO', 'NORDIC'),
  ('SUA', 'TURKISH'),
  ('SUE', 'TURKISH'),
  ('SUR', 'MALAY'),
  ('SVQ', 'SPANISH'),
  ('SYD', 'MALAY'),
  ('TAI', 'CHINESE'),
  ('TAL', 'GERMAN'),
  ('TAN', 'ARABIC'),
  ('TEN', 'SPANISH'),
  ('TER', 'MALAY'),
  ('THA', 'INDIC'),
  ('THE', 'TURKISH'),
  ('TID', 'MALAY'),
  ('TOK', 'JAPANESE'),
  ('TON', 'KOREAN'),
  ('TOR', 'NORDIC'),
  ('TOU', 'FRENCH'),
  ('TRA', 'TURKISH'),
  ('TRI', 'TURKISH'),
  ('TRO', 'NORDIC'),
  ('TRP', 'TURKISH'),
  ('TSU', 'JAPANESE'),
  ('TUN', 'TURKISH'),
  ('TUR', 'NORDIC'),
  ('ULS', 'KOREAN'),
  ('VAL', 'SPANISH'),
  ('VAR', 'NORDIC'),
  ('VEN', 'ITALIAN'),
  ('VER', 'SPANISH'),
  ('VIS', 'NORDIC'),
  ('VLL', 'ITALIAN'),
  ('VLP', 'SPANISH'),
  ('WIL', 'DUTCH'),
  ('XIA', 'CHINESE'),
  ('YEO', 'KOREAN'),
  ('ZAK', 'ITALIAN'),
  ('ZAN', 'SWAHILI')
       ) w(port, language)
  join public.ports p on p.code = w.port and p.kind = 'HARBOUR';

-- ── 3. THE ONE ANSWERS ─────────────────────────────────────────────────────────────────────────
create or replace function public.trait_in_use(p_trait text)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $tu$
  -- 0156: THE ONE answer to "does this trait work today": some effect of it is read by a rule now
  -- (crew_effects.live). It works only as a captain's JOB — her first trait — until K5's public.crew_pct.
  select exists (select 1 from public.trait_effects te join public.crew_effects ce on ce.code = te.effect
                  where te.trait = p_trait and ce.live)
$tu$;
comment on function public.trait_in_use(text) is
  '0156: whether a trait works today (an effect of it is live). world.officers'' specialties_read and every '
  'card''s in_use read it; nothing else decides it.';

create or replace function public.trait_effect_words(p_words text, p_pct numeric, p_goods text)
returns text
language sql
immutable
as $tw$
  -- 0156: ONE line of a trait card, in the server's words (docs/WORDS.md): "+7.5% speed",
  -- "+5.4% better prices on gems". The per cent to the tenth, trailing zeros trimmed.
  select replace(replace(p_words, '{pct}', trim_scale(round(p_pct, 1))::text), '{goods}', coalesce(p_goods, ''))
$tw$;

create or replace function world.captain_card(p_officer uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $cc$
-- 0156: WHAT A CAPTAIN IS, built once — composed by world.inn (every guest) and world.officers (every
-- captain in the Codex). Her grade (and how many traits she uses / knows at it), her job and its focus,
-- the traits she KNOWS (her grade's `known` first of the ten), each with its lines, whether it works
-- today (only her job, and only if a rule reads it — public.trait_in_use) and, when not, why; and the
-- languages she speaks. A captain with no card is not a captain: it raises rather than serving a guest
-- with half her facts (NO_SPAGHETTI §7C).
declare
  v jsonb;
begin
  select jsonb_build_object(
           'grade', g.code,
           'grade_ord', g.ord,
           'slots', g.slots,
           'known', g.known,
           'job', t.code,
           'job_word', t.word,
           'focus', t.focus,
           'focus_word', f.word,
           'traits', (select coalesce(jsonb_agg(jsonb_build_object(
                          'code', kt.code,
                          'word', kt.word,
                          'focus_word', kf.word,
                          'pct', ct.base_pct,
                          'lines', (select jsonb_agg(public.trait_effect_words(ce.words, ct.base_pct * te.mult, kt.goods_word)
                                                     order by te.ord)
                                      from public.trait_effects te join public.crew_effects ce on ce.code = te.effect
                                     where te.trait = kt.code),
                          'uses', ct.ord <= g.slots,
                          'in_use', (ct.ord = 1 and public.trait_in_use(kt.code)),
                          'note', case when not (ct.ord = 1 and public.trait_in_use(kt.code)) then
                                    (select ce.waits from public.trait_effects te join public.crew_effects ce on ce.code = te.effect
                                      where te.trait = kt.code order by te.ord limit 1) end
                        ) order by ct.ord), '[]'::jsonb)
                         from public.captain_traits ct
                         join public.traits kt on kt.code = ct.trait
                         join public.trait_foci kf on kf.code = kt.focus
                        where ct.officer_id = o.id and ct.ord <= g.known),
           'languages', (select coalesce(jsonb_agg(l.name order by cl.ord), '[]'::jsonb)
                           from public.captain_languages cl join public.languages l on l.code = cl.language
                          where cl.officer_id = o.id),
           'speaks', (select 'Speaks ' || string_agg(l.name, ', ' order by cl.ord)
                        from public.captain_languages cl join public.languages l on l.code = cl.language
                       where cl.officer_id = o.id))
    into v
    from public.officers o
    join public.captain_profile cp on cp.officer_id = o.id
    join public.captain_grades g on g.code = cp.grade
    join public.traits t on t.code = cp.job_trait
    join public.trait_foci f on f.code = t.focus
   where o.id = p_officer;
  if v is null then
    raise exception 'E_NO_CARD: captain % has no grade, job or kit (public.captain_profile)', p_officer using errcode = 'P0001';
  end if;
  return v;
end $cc$;
comment on function world.captain_card(uuid) is
  '0156: THE one builder of a captain''s card (grade, job, focus, known traits with lines and in_use, languages). '
  'Composed by world.inn and world.officers. Server-only.';

revoke all on function public.trait_in_use(text) from public, anon, authenticated;
revoke all on function public.trait_effect_words(text, numeric, text) from public, anon, authenticated;
revoke all on function world.captain_card(uuid) from public, anon, authenticated;

-- ── 4. THE PEOPLE: the CHECK becomes a FOREIGN KEY, and 42 captains join the 63 ───────────────────
do $alter$
declare
  v_try   int := 0;
  v_check text;
  v_msg   text;
  v_state text;
begin
  select conname into v_check from pg_constraint
   where conrelid = 'public.officers'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%specialty%';
  if v_check is null then
    raise exception '0156 self-assert FAIL: the four-value specialty CHECK is not where 0015 put it';
  end if;
  loop
    v_try := v_try + 1;
    begin
      execute format('alter table public.officers drop constraint %I, '
                     'add constraint officers_specialty_is_a_trait foreign key (specialty) references public.traits(code) not valid',
                     v_check);
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0156 self-assert FAIL: LOCK CONTENTION, not a result — public.officers could not be altered in 5 tries (%: %). Re-run the push.',
          v_state, v_msg;
      end if;
      perform pg_sleep(0.5);
    end;
  end loop;
end $alter$;

comment on column public.officers.specialty is
  '0156: her JOB — a trait (public.traits), mirrored by captain_profile.job_trait and captain_traits ord 1. '
  'public.fleet_officer_bonus reads the four live jobs here until K5''s public.crew_pct; retired in K9.';

insert into public.officers (code, name, specialty, bonus_pct, wage_ducats, nation_id, home_port_id, blurb)
select w.code, w.name, w.specialty, w.bonus_pct, w.wage, n.id, p.id, w.blurb
  from (values
  ('LISBOAPIL', 'João de Lisboa', 'PILOT', 6, 870, 'PRT', 'LIS', 'Wrote the first Portuguese book on the compass needle, and trusts it less than his nose.'),
  ('URDANETA', 'Andrés de Urdaneta', 'PILOT', 9, 1500, 'ESP', 'ACA', 'Found the way back across the Pacific after forty years of everyone else getting lost.'),
  ('PIGAFETTA', 'Antonio Pigafetta', 'PROVISIONER', 4, 600, 'VEN', 'VEN', 'Counted every rat sold for half a ducat on Magellan''s ship, and still kept the diary dry.'),
  ('DARELL', 'Marmaduke Darell', 'PROVISIONER', 7.5, 1150, 'ENG', 'LON', 'Victualled Elizabeth''s navy on time, which nobody before him had managed.'),
  ('GIESE', 'Georg Giese', 'GRAIN_TRADER', 5, 700, 'POL', 'GDA', 'Danzig rye merchant; sat for Holbein once and has used the face for credit ever since.'),
  ('VANOS', 'Dirck van Os', 'GRAIN_TRADER', 7, 1040, 'NLD', 'AMS', 'Buys Baltic rye before it is sown and sells Amsterdam bread before it is baked.'),
  ('SCAPPI', 'Bartolomeo Scappi', 'FOOD_TRADER', 6.5, 930, null, 'ANC', 'Cooked for six popes and knows to the ounce what a cask of salted eel is worth.'),
  ('ESMERALDO', 'João Esmeraldo', 'FOOD_TRADER', 8.5, 1370, 'PRT', 'FNC', 'Turned a Madeira hillside into sugar and the sugar into the finest house in Funchal.'),
  ('XUCISHU', 'Xu Cishu', 'DRINK_TRADER', 4.5, 650, 'MNG', 'NIN', 'Wrote a whole book on tea and still cannot drink a bad cup in silence.'),
  ('PONTAC', 'Jean de Pontac', 'DRINK_TRADER', 9, 1510, 'FRA', 'BOR', 'Planted Haut-Brion, sold it to London, and lived to a hundred and one on the proceeds.'),
  ('ROLFE', 'John Rolfe', 'TOBACCO_TRADER', 5.5, 780, 'ENG', 'LON', 'Crossed Virginia tobacco with Trinidad seed and made a swamp colony solvent.'),
  ('NICOT', 'Jean Nicot', 'TOBACCO_TRADER', 7.5, 1140, 'FRA', 'MRS', 'Sent snuff to the Queen of France as medicine and got a chemical named after him.'),
  ('MALIKGOPI', 'Malik Gopi', 'SPICE_TRADER', 5, 710, 'GUJ', 'SRT', 'Pepper broker of Surat who made the Portuguese pay for the privilege of needing him.'),
  ('GRACIANASI', 'Gracia Mendes Nasi', 'SPICE_TRADER', 9, 1500, 'OTT', 'IST', 'Moved the Mendes pepper fortune out of Lisbon, Antwerp and Venice before the Inquisition could.'),
  ('MANASE', 'Manase Dōsan', 'MEDICINE_TRADER', 6, 860, 'JPN', 'OSA', 'Kyoto physician who taught the Chinese pharmacopoeia to a generation and priced it to match.'),
  ('DACOSTA', 'Cristóvão da Costa', 'MEDICINE_TRADER', 8, 1270, 'PRT', 'OLD', 'Walked Goa''s markets with a notebook and wrote down which drugs were real.'),
  ('ASSEZAT', 'Pierre d''Assézat', 'DYE_TRADER', 4.5, 660, 'FRA', 'BOR', 'Made a Toulouse fortune in blue woad and spent it on the city''s loveliest courtyard.'),
  ('PELSAERT', 'Francisco Pelsaert', 'DYE_TRADER', 7.5, 1150, 'NLD', 'AMS', 'Spent seven years in Agra learning indigo, then wrote the Dutch a report on it.'),
  ('KHWAJANAZAR', 'Khwaja Nazar', 'CLOTH_TRADER', 6.5, 930, 'PER', 'BAS', 'New Julfa silk prince; his Armenian cousins reach from Isfahan to Amsterdam and all owe him.'),
  ('CRANFIELD', 'Lionel Cranfield', 'CLOTH_TRADER', 8.5, 1380, 'ENG', 'LON', 'Shipped English broadcloth to Antwerp so profitably the King made him Treasurer.'),
  ('KAMIYA', 'Kamiya Jutei', 'METAL_TRADER', 4, 610, 'JPN', 'FUK', 'Hakata merchant who looked at a mountain in Iwami and saw a third of the world''s silver.'),
  ('THURZO', 'Georg Thurzo', 'METAL_TRADER', 7, 1040, 'POL', 'GDA', 'Pumped the water out of Hungarian copper mines and the Fuggers'' money into them.'),
  ('DECOUTRE', 'Jacques de Coutre', 'GEM_TRADER', 6, 870, 'ESP', 'BRU', 'Bruges jeweller who spent thirty years in Goa and came home with stones and a grudge.'),
  ('MIRJUMLA', 'Mir Jumla', 'GEM_TRADER', 9, 1500, null, 'MCH', 'Persian diamond dealer who bought Golconda''s mines and then, for tidiness, Golconda.'),
  ('BALLARIN', 'Giorgio Ballarin', 'CRAFTS_TRADER', 4.5, 650, 'VEN', 'VEN', 'Stole the Murano glass secrets once; has sold them honestly ever since.'),
  ('LIDAN', 'Li Dan', 'CRAFTS_TRADER', 8, 1260, null, 'TAI', 'Captain of the Chinese at Hirado; porcelain, silk and Dutch promises all cross his table.'),
  ('TRIP', 'Elias Trip', 'WEAPONS_TRADER', 6.5, 940, 'NLD', 'AMS', 'Dutch iron and cannon to anyone with cash, including both sides of the same war.'),
  ('AYALA', 'Tomás de Ayala', 'WEAPONS_TRADER', 7, 1030, 'ESP', 'SVQ', 'A Toledo blade with Ayala on the tang sells itself; he merely names the price.'),
  ('TANEGASHIMA', 'Tanegashima Tokitaka', 'GUNS_TRADER', 5, 700, 'JPN', 'KAG', 'Paid a fortune for two Portuguese arquebuses and had copies out within the year.'),
  ('DEGEER', 'Louis De Geer', 'GUNS_TRADER', 8, 1270, 'SWE', 'STO', 'Walloon who made Sweden the arsenal of Europe and himself the richest man in it.'),
  ('VALKENDORF', 'Christoffer Valkendorf', 'SHIP_SUPPLIES_TRADER', 5.5, 790, 'DNK', 'BER', 'Threw the Hansa out of Bergen and kept the Norwegian timber for the Crown.'),
  ('BOSOY', 'Kirill Bosoy', 'SHIP_SUPPLIES_TRADER', 7.5, 1150, 'RUS', 'ARK', 'Moscow hemp and tar down the Dvina to Arkhangelsk before the river freezes behind him.'),
  ('UYLENBURGH', 'Hendrick Uylenburgh', 'ART_TRADER', 5, 700, 'NLD', 'AMS', 'Rents a studio to a miller''s son called Rembrandt and takes a cut of every face.'),
  ('NIJS', 'Daniel Nijs', 'ART_TRADER', 8.5, 1370, 'VEN', 'VEN', 'Sold the entire Gonzaga collection to Charles I and forgot to mention a few pieces.'),
  ('YUXIANGDOU', 'Yu Xiangdou', 'BOOK_TRADER', 6, 870, 'MNG', 'FUZ', 'Prints cheap novels in Jianyang and puts his own portrait on the front page.'),
  ('PLANTIN', 'Christophe Plantin', 'BOOK_TRADER', 8, 1280, 'ESP', 'ARP', 'Eight presses in Antwerp, a polyglot Bible, and a receipt for every sheet.'),
  ('OXE', 'Peder Oxe', 'ANIMAL_TRADER', 4, 600, 'DNK', 'COP', 'Danish lord named Oxe who drives oxen to the Netherlands and insists it is not a joke.'),
  ('GHULAMHUSAYN', 'Hajji Ghulam Husayn', 'ANIMAL_TRADER', 7, 1050, 'PER', 'BAS', 'Walks Arabian horses from Bandar Abbas to Golconda and loses fewer than anyone.'),
  ('TARTAGLIA', 'Niccolò Tartaglia', 'GUNNER', 4.5, 650, 'VEN', 'VEN', 'Proved that cannon shot flies in a curve, then wondered aloud whether he should have.'),
  ('YIJANGSON', 'Yi Jang-son', 'GUNNER', 7.5, 1160, 'JOS', 'YEO', 'Built a mortar that explodes after landing, which the Japanese found unsporting.'),
  ('MURAKAMI', 'Murakami Takeyoshi', 'BOARDER', 6.5, 930, 'JPN', 'OSA', 'Inland Sea pirate lord; charges a toll, and boards anyone who thinks it optional.'),
  ('TURGUT', 'Turgut Reis', 'BOARDER', 9, 1500, 'OTT', 'TRP', 'Barbary corsair who took Tripoli, Gozo and a Genoese galley fleet, mostly at close range.')
       ) w(code, name, specialty, bonus_pct, wage, nation_code, home_code, blurb)
  left join public.nations n on n.code = w.nation_code
  join public.ports p on p.code = w.home_code and p.kind = 'HARBOUR';

alter table public.officers validate constraint officers_specialty_is_a_trait;

insert into public.captain_profile (officer_id, grade, job_trait)
select o.id, w.grade, w.job
  from (values
  ('CABRALNAV', 'A', 'NAVIGATOR'),
  ('ELCANO', 'S', 'NAVIGATOR'),
  ('CHANCELLOR', 'B', 'NAVIGATOR'),
  ('BARENTS', 'A', 'NAVIGATOR'),
  ('PIRIREIS', 'S', 'NAVIGATOR'),
  ('IBNMAJID', 'A', 'NAVIGATOR'),
  ('ZHENGPIL', 'A', 'NAVIGATOR'),
  ('JEONGNAV', 'B', 'NAVIGATOR'),
  ('BERGENNAV', 'C', 'NAVIGATOR'),
  ('VENEZNAV', 'B', 'NAVIGATOR'),
  ('MALACCANAV', 'B', 'NAVIGATOR'),
  ('ALBUQUERQ', 'A', 'QUARTERMASTER'),
  ('MENDANA', 'B', 'QUARTERMASTER'),
  ('HAWKINSQM', 'A', 'QUARTERMASTER'),
  ('COENQM', 'S', 'QUARTERMASTER'),
  ('HANSEQM', 'B', 'QUARTERMASTER'),
  ('GUJARATQM', 'A', 'QUARTERMASTER'),
  ('SAKAIQM', 'B', 'QUARTERMASTER'),
  ('MOROCCOQM', 'C', 'QUARTERMASTER'),
  ('SWEDQM', 'B', 'QUARTERMASTER'),
  ('GENOAQM', 'A', 'QUARTERMASTER'),
  ('GARCIAORTA', 'S', 'SURGEON'),
  ('MONARDES', 'A', 'SURGEON'),
  ('WOODALL', 'A', 'SURGEON'),
  ('TULPSURG', 'A', 'SURGEON'),
  ('SABUNCU', 'B', 'SURGEON'),
  ('PERSSURG', 'B', 'SURGEON'),
  ('HEOJUN', 'S', 'SURGEON'),
  ('LISHIZHEN', 'A', 'SURGEON'),
  ('DANESURG', 'B', 'SURGEON'),
  ('VENSURG', 'A', 'SURGEON'),
  ('MALSURG', 'C', 'SURGEON'),
  ('WELSER', 'S', 'PURSER'),
  ('MEDICI', 'A', 'PURSER'),
  ('GRESHAM', 'S', 'PURSER'),
  ('AMSPURSER', 'A', 'PURSER'),
  ('PORTPURSER', 'B', 'PURSER'),
  ('SEVPURSER', 'A', 'PURSER'),
  ('OTTPURSER', 'A', 'PURSER'),
  ('MUGPURSER', 'S', 'PURSER'),
  ('SAKAIPURSER', 'A', 'PURSER'),
  ('POLPURSER', 'B', 'PURSER'),
  ('RUSPURSER', 'B', 'PURSER'),
  ('ALCANT', 'B', 'QUARTERMASTER'),
  ('BARROS', 'C', 'PURSER'),
  ('DIASNAV', 'A', 'NAVIGATOR'),
  ('FUGGER', 'B', 'PURSER'),
  ('HOLBEK', 'C', 'QUARTERMASTER'),
  ('MOREAU', 'C', 'SURGEON'),
  ('NPCPILOTGEN', 'C', 'NAVIGATOR'),
  ('NPCPILOTMNG', 'C', 'NAVIGATOR'),
  ('NPCPILOTOTT', 'C', 'NAVIGATOR'),
  ('NPCPILOTPRT', 'C', 'NAVIGATOR'),
  ('NPCPURSERESP', 'C', 'PURSER'),
  ('NPCPURSERMUG', 'B', 'PURSER'),
  ('NPCPURSERVEN', 'C', 'PURSER'),
  ('NPCQMHAN', 'C', 'QUARTERMASTER'),
  ('NPCQMJPN', 'C', 'QUARTERMASTER'),
  ('NPCQMNLD', 'C', 'QUARTERMASTER'),
  ('NPCSURGENG', 'C', 'SURGEON'),
  ('NPCSURGFRA', 'C', 'SURGEON'),
  ('PINZON', 'C', 'NAVIGATOR'),
  ('ZAHRA', 'A', 'SURGEON'),
  ('LISBOAPIL', 'B', 'PILOT'),
  ('URDANETA', 'S', 'PILOT'),
  ('PIGAFETTA', 'C', 'PROVISIONER'),
  ('DARELL', 'A', 'PROVISIONER'),
  ('GIESE', 'C', 'GRAIN_TRADER'),
  ('VANOS', 'A', 'GRAIN_TRADER'),
  ('SCAPPI', 'B', 'FOOD_TRADER'),
  ('ESMERALDO', 'S', 'FOOD_TRADER'),
  ('XUCISHU', 'C', 'DRINK_TRADER'),
  ('PONTAC', 'S', 'DRINK_TRADER'),
  ('ROLFE', 'B', 'TOBACCO_TRADER'),
  ('NICOT', 'A', 'TOBACCO_TRADER'),
  ('MALIKGOPI', 'C', 'SPICE_TRADER'),
  ('GRACIANASI', 'S', 'SPICE_TRADER'),
  ('MANASE', 'B', 'MEDICINE_TRADER'),
  ('DACOSTA', 'A', 'MEDICINE_TRADER'),
  ('ASSEZAT', 'C', 'DYE_TRADER'),
  ('PELSAERT', 'A', 'DYE_TRADER'),
  ('KHWAJANAZAR', 'B', 'CLOTH_TRADER'),
  ('CRANFIELD', 'S', 'CLOTH_TRADER'),
  ('KAMIYA', 'C', 'METAL_TRADER'),
  ('THURZO', 'A', 'METAL_TRADER'),
  ('DECOUTRE', 'B', 'GEM_TRADER'),
  ('MIRJUMLA', 'S', 'GEM_TRADER'),
  ('BALLARIN', 'C', 'CRAFTS_TRADER'),
  ('LIDAN', 'A', 'CRAFTS_TRADER'),
  ('TRIP', 'B', 'WEAPONS_TRADER'),
  ('AYALA', 'A', 'WEAPONS_TRADER'),
  ('TANEGASHIMA', 'C', 'GUNS_TRADER'),
  ('DEGEER', 'A', 'GUNS_TRADER'),
  ('VALKENDORF', 'B', 'SHIP_SUPPLIES_TRADER'),
  ('BOSOY', 'A', 'SHIP_SUPPLIES_TRADER'),
  ('UYLENBURGH', 'C', 'ART_TRADER'),
  ('NIJS', 'S', 'ART_TRADER'),
  ('YUXIANGDOU', 'B', 'BOOK_TRADER'),
  ('PLANTIN', 'A', 'BOOK_TRADER'),
  ('OXE', 'C', 'ANIMAL_TRADER'),
  ('GHULAMHUSAYN', 'A', 'ANIMAL_TRADER'),
  ('TARTAGLIA', 'C', 'GUNNER'),
  ('YIJANGSON', 'A', 'GUNNER'),
  ('MURAKAMI', 'B', 'BOARDER'),
  ('TURGUT', 'S', 'BOARDER')
       ) w(code, grade, job)
  join public.officers o on o.code = w.code;

insert into public.captain_traits (officer_id, ord, trait, base_pct)
select o.id, w.ord, w.trait, w.pct
  from (values
  ('CABRALNAV', 1, 'NAVIGATOR', 7.5),
  ('CABRALNAV', 2, 'PILOT', 4.5),
  ('CABRALNAV', 3, 'PROVISIONER', 4.5),
  ('CABRALNAV', 4, 'SURGEON', 4.5),
  ('CABRALNAV', 5, 'PURSER', 4.5),
  ('CABRALNAV', 6, 'METAL_TRADER', 4.5),
  ('CABRALNAV', 7, 'BOOK_TRADER', 4.5),
  ('CABRALNAV', 8, 'GUNNER', 4.5),
  ('CABRALNAV', 9, 'GRAIN_TRADER', 4.5),
  ('CABRALNAV', 10, 'WEAPONS_TRADER', 4.5),
  ('ELCANO', 1, 'NAVIGATOR', 9),
  ('ELCANO', 2, 'PILOT', 5.4),
  ('ELCANO', 3, 'PROVISIONER', 5.4),
  ('ELCANO', 4, 'SURGEON', 5.4),
  ('ELCANO', 5, 'FOOD_TRADER', 5.4),
  ('ELCANO', 6, 'CLOTH_TRADER', 5.4),
  ('ELCANO', 7, 'GUNNER', 5.4),
  ('ELCANO', 8, 'DRINK_TRADER', 5.4),
  ('ELCANO', 9, 'TOBACCO_TRADER', 5.4),
  ('ELCANO', 10, 'METAL_TRADER', 5.4),
  ('CHANCELLOR', 1, 'NAVIGATOR', 6.5),
  ('CHANCELLOR', 2, 'PROVISIONER', 3.9),
  ('CHANCELLOR', 3, 'PILOT', 3.9),
  ('CHANCELLOR', 4, 'SURGEON', 3.9),
  ('CHANCELLOR', 5, 'TOBACCO_TRADER', 3.9),
  ('CHANCELLOR', 6, 'BOARDER', 3.9),
  ('CHANCELLOR', 7, 'QUARTERMASTER', 3.9),
  ('CHANCELLOR', 8, 'FOOD_TRADER', 3.9),
  ('CHANCELLOR', 9, 'METAL_TRADER', 3.9),
  ('CHANCELLOR', 10, 'CLOTH_TRADER', 3.9),
  ('BARENTS', 1, 'NAVIGATOR', 7),
  ('BARENTS', 2, 'PILOT', 4.2),
  ('BARENTS', 3, 'SURGEON', 4.2),
  ('BARENTS', 4, 'PROVISIONER', 4.2),
  ('BARENTS', 5, 'TOBACCO_TRADER', 4.2),
  ('BARENTS', 6, 'CRAFTS_TRADER', 4.2),
  ('BARENTS', 7, 'METAL_TRADER', 4.2),
  ('BARENTS', 8, 'SPICE_TRADER', 4.2),
  ('BARENTS', 9, 'SHIP_SUPPLIES_TRADER', 4.2),
  ('BARENTS', 10, 'ANIMAL_TRADER', 4.2),
  ('PIRIREIS', 1, 'NAVIGATOR', 8.5),
  ('PIRIREIS', 2, 'SURGEON', 5.1),
  ('PIRIREIS', 3, 'PILOT', 5.1),
  ('PIRIREIS', 4, 'PROVISIONER', 5.1),
  ('PIRIREIS', 5, 'ANIMAL_TRADER', 5.1),
  ('PIRIREIS', 6, 'DYE_TRADER', 5.1),
  ('PIRIREIS', 7, 'SPICE_TRADER', 5.1),
  ('PIRIREIS', 8, 'GEM_TRADER', 5.1),
  ('PIRIREIS', 9, 'MEDICINE_TRADER', 5.1),
  ('PIRIREIS', 10, 'GUNS_TRADER', 5.1),
  ('IBNMAJID', 1, 'NAVIGATOR', 8),
  ('IBNMAJID', 2, 'SURGEON', 4.8),
  ('IBNMAJID', 3, 'PILOT', 4.8),
  ('IBNMAJID', 4, 'PROVISIONER', 4.8),
  ('IBNMAJID', 5, 'SPICE_TRADER', 4.8),
  ('IBNMAJID', 6, 'BOOK_TRADER', 4.8),
  ('IBNMAJID', 7, 'ANIMAL_TRADER', 4.8),
  ('IBNMAJID', 8, 'DYE_TRADER', 4.8),
  ('IBNMAJID', 9, 'MEDICINE_TRADER', 4.8),
  ('IBNMAJID', 10, 'QUARTERMASTER', 4.8),
  ('ZHENGPIL', 1, 'NAVIGATOR', 7),
  ('ZHENGPIL', 2, 'PILOT', 4.2),
  ('ZHENGPIL', 3, 'SURGEON', 4.2),
  ('ZHENGPIL', 4, 'PROVISIONER', 4.2),
  ('ZHENGPIL', 5, 'PURSER', 4.2),
  ('ZHENGPIL', 6, 'MEDICINE_TRADER', 4.2),
  ('ZHENGPIL', 7, 'GRAIN_TRADER', 4.2),
  ('ZHENGPIL', 8, 'DYE_TRADER', 4.2),
  ('ZHENGPIL', 9, 'CRAFTS_TRADER', 4.2),
  ('ZHENGPIL', 10, 'FOOD_TRADER', 4.2),
  ('JEONGNAV', 1, 'NAVIGATOR', 5.5),
  ('JEONGNAV', 2, 'PILOT', 3.3),
  ('JEONGNAV', 3, 'PROVISIONER', 3.3),
  ('JEONGNAV', 4, 'SURGEON', 3.3),
  ('JEONGNAV', 5, 'GEM_TRADER', 3.3),
  ('JEONGNAV', 6, 'WEAPONS_TRADER', 3.3),
  ('JEONGNAV', 7, 'SPICE_TRADER', 3.3),
  ('JEONGNAV', 8, 'GUNNER', 3.3),
  ('JEONGNAV', 9, 'DYE_TRADER', 3.3),
  ('JEONGNAV', 10, 'GUNS_TRADER', 3.3),
  ('BERGENNAV', 1, 'NAVIGATOR', 5),
  ('BERGENNAV', 2, 'SURGEON', 3),
  ('BERGENNAV', 3, 'PILOT', 3),
  ('BERGENNAV', 4, 'PROVISIONER', 3),
  ('BERGENNAV', 5, 'PURSER', 3),
  ('BERGENNAV', 6, 'SPICE_TRADER', 3),
  ('BERGENNAV', 7, 'GUNNER', 3),
  ('BERGENNAV', 8, 'CLOTH_TRADER', 3),
  ('BERGENNAV', 9, 'SHIP_SUPPLIES_TRADER', 3),
  ('BERGENNAV', 10, 'DYE_TRADER', 3),
  ('VENEZNAV', 1, 'NAVIGATOR', 6),
  ('VENEZNAV', 2, 'PILOT', 3.6),
  ('VENEZNAV', 3, 'PROVISIONER', 3.6),
  ('VENEZNAV', 4, 'SURGEON', 3.6),
  ('VENEZNAV', 5, 'MEDICINE_TRADER', 3.6),
  ('VENEZNAV', 6, 'GRAIN_TRADER', 3.6),
  ('VENEZNAV', 7, 'DRINK_TRADER', 3.6),
  ('VENEZNAV', 8, 'DYE_TRADER', 3.6),
  ('VENEZNAV', 9, 'PURSER', 3.6),
  ('VENEZNAV', 10, 'GUNNER', 3.6),
  ('MALACCANAV', 1, 'NAVIGATOR', 6.5),
  ('MALACCANAV', 2, 'PILOT', 3.9),
  ('MALACCANAV', 3, 'PROVISIONER', 3.9),
  ('MALACCANAV', 4, 'SURGEON', 3.9),
  ('MALACCANAV', 5, 'GRAIN_TRADER', 3.9),
  ('MALACCANAV', 6, 'TOBACCO_TRADER', 3.9),
  ('MALACCANAV', 7, 'BOARDER', 3.9),
  ('MALACCANAV', 8, 'DYE_TRADER', 3.9),
  ('MALACCANAV', 9, 'GUNS_TRADER', 3.9),
  ('MALACCANAV', 10, 'MEDICINE_TRADER', 3.9),
  ('ALBUQUERQ', 1, 'QUARTERMASTER', 8),
  ('ALBUQUERQ', 2, 'GUNS_TRADER', 4.8),
  ('ALBUQUERQ', 3, 'SHIP_SUPPLIES_TRADER', 4.8),
  ('ALBUQUERQ', 4, 'SPICE_TRADER', 4.8),
  ('ALBUQUERQ', 5, 'SURGEON', 4.8),
  ('ALBUQUERQ', 6, 'CRAFTS_TRADER', 4.8),
  ('ALBUQUERQ', 7, 'GEM_TRADER', 4.8),
  ('ALBUQUERQ', 8, 'NAVIGATOR', 4.8),
  ('ALBUQUERQ', 9, 'DRINK_TRADER', 4.8),
  ('ALBUQUERQ', 10, 'TOBACCO_TRADER', 4.8),
  ('MENDANA', 1, 'QUARTERMASTER', 6),
  ('MENDANA', 2, 'ANIMAL_TRADER', 3.6),
  ('MENDANA', 3, 'CRAFTS_TRADER', 3.6),
  ('MENDANA', 4, 'DRINK_TRADER', 3.6),
  ('MENDANA', 5, 'SHIP_SUPPLIES_TRADER', 3.6),
  ('MENDANA', 6, 'SURGEON', 3.6),
  ('MENDANA', 7, 'WEAPONS_TRADER', 3.6),
  ('MENDANA', 8, 'BOARDER', 3.6),
  ('MENDANA', 9, 'GUNNER', 3.6),
  ('MENDANA', 10, 'FOOD_TRADER', 3.6),
  ('HAWKINSQM', 1, 'QUARTERMASTER', 7),
  ('HAWKINSQM', 2, 'WEAPONS_TRADER', 4.2),
  ('HAWKINSQM', 3, 'SPICE_TRADER', 4.2),
  ('HAWKINSQM', 4, 'CLOTH_TRADER', 4.2),
  ('HAWKINSQM', 5, 'PROVISIONER', 4.2),
  ('HAWKINSQM', 6, 'FOOD_TRADER', 4.2),
  ('HAWKINSQM', 7, 'BOARDER', 4.2),
  ('HAWKINSQM', 8, 'MEDICINE_TRADER', 4.2),
  ('HAWKINSQM', 9, 'GRAIN_TRADER', 4.2),
  ('HAWKINSQM', 10, 'NAVIGATOR', 4.2),
  ('COENQM', 1, 'QUARTERMASTER', 8.5),
  ('COENQM', 2, 'BOOK_TRADER', 5.1),
  ('COENQM', 3, 'PURSER', 5.1),
  ('COENQM', 4, 'DRINK_TRADER', 5.1),
  ('COENQM', 5, 'BOARDER', 5.1),
  ('COENQM', 6, 'PROVISIONER', 5.1),
  ('COENQM', 7, 'NAVIGATOR', 5.1),
  ('COENQM', 8, 'SURGEON', 5.1),
  ('COENQM', 9, 'FOOD_TRADER', 5.1),
  ('COENQM', 10, 'GUNNER', 5.1),
  ('HANSEQM', 1, 'QUARTERMASTER', 6.5),
  ('HANSEQM', 2, 'CRAFTS_TRADER', 3.9),
  ('HANSEQM', 3, 'GEM_TRADER', 3.9),
  ('HANSEQM', 4, 'SHIP_SUPPLIES_TRADER', 3.9),
  ('HANSEQM', 5, 'SURGEON', 3.9),
  ('HANSEQM', 6, 'PROVISIONER', 3.9),
  ('HANSEQM', 7, 'METAL_TRADER', 3.9),
  ('HANSEQM', 8, 'MEDICINE_TRADER', 3.9),
  ('HANSEQM', 9, 'ART_TRADER', 3.9),
  ('HANSEQM', 10, 'FOOD_TRADER', 3.9),
  ('GUJARATQM', 1, 'QUARTERMASTER', 7.5),
  ('GUJARATQM', 2, 'SHIP_SUPPLIES_TRADER', 4.5),
  ('GUJARATQM', 3, 'CLOTH_TRADER', 4.5),
  ('GUJARATQM', 4, 'DYE_TRADER', 4.5),
  ('GUJARATQM', 5, 'GUNNER', 4.5),
  ('GUJARATQM', 6, 'GEM_TRADER', 4.5),
  ('GUJARATQM', 7, 'BOOK_TRADER', 4.5),
  ('GUJARATQM', 8, 'SURGEON', 4.5),
  ('GUJARATQM', 9, 'CRAFTS_TRADER', 4.5),
  ('GUJARATQM', 10, 'PROVISIONER', 4.5),
  ('SAKAIQM', 1, 'QUARTERMASTER', 6),
  ('SAKAIQM', 2, 'GRAIN_TRADER', 3.6),
  ('SAKAIQM', 3, 'METAL_TRADER', 3.6),
  ('SAKAIQM', 4, 'TOBACCO_TRADER', 3.6),
  ('SAKAIQM', 5, 'BOARDER', 3.6),
  ('SAKAIQM', 6, 'SURGEON', 3.6),
  ('SAKAIQM', 7, 'NAVIGATOR', 3.6),
  ('SAKAIQM', 8, 'ANIMAL_TRADER', 3.6),
  ('SAKAIQM', 9, 'PURSER', 3.6),
  ('SAKAIQM', 10, 'SPICE_TRADER', 3.6),
  ('MOROCCOQM', 1, 'QUARTERMASTER', 5),
  ('MOROCCOQM', 2, 'SHIP_SUPPLIES_TRADER', 3),
  ('MOROCCOQM', 3, 'BOOK_TRADER', 3),
  ('MOROCCOQM', 4, 'MEDICINE_TRADER', 3),
  ('MOROCCOQM', 5, 'NAVIGATOR', 3),
  ('MOROCCOQM', 6, 'WEAPONS_TRADER', 3),
  ('MOROCCOQM', 7, 'ART_TRADER', 3),
  ('MOROCCOQM', 8, 'SURGEON', 3),
  ('MOROCCOQM', 9, 'CRAFTS_TRADER', 3),
  ('MOROCCOQM', 10, 'GUNNER', 3),
  ('SWEDQM', 1, 'QUARTERMASTER', 5.5),
  ('SWEDQM', 2, 'TOBACCO_TRADER', 3.3),
  ('SWEDQM', 3, 'MEDICINE_TRADER', 3.3),
  ('SWEDQM', 4, 'DRINK_TRADER', 3.3),
  ('SWEDQM', 5, 'PROVISIONER', 3.3),
  ('SWEDQM', 6, 'GUNNER', 3.3),
  ('SWEDQM', 7, 'METAL_TRADER', 3.3),
  ('SWEDQM', 8, 'SPICE_TRADER', 3.3),
  ('SWEDQM', 9, 'WEAPONS_TRADER', 3.3),
  ('SWEDQM', 10, 'GEM_TRADER', 3.3),
  ('GENOAQM', 1, 'QUARTERMASTER', 7),
  ('GENOAQM', 2, 'MEDICINE_TRADER', 4.2),
  ('GENOAQM', 3, 'BOOK_TRADER', 4.2),
  ('GENOAQM', 4, 'ANIMAL_TRADER', 4.2),
  ('GENOAQM', 5, 'GUNNER', 4.2),
  ('GENOAQM', 6, 'PURSER', 4.2),
  ('GENOAQM', 7, 'GUNS_TRADER', 4.2),
  ('GENOAQM', 8, 'DYE_TRADER', 4.2),
  ('GENOAQM', 9, 'GRAIN_TRADER', 4.2),
  ('GENOAQM', 10, 'WEAPONS_TRADER', 4.2),
  ('GARCIAORTA', 1, 'SURGEON', 9),
  ('GARCIAORTA', 2, 'NAVIGATOR', 5.4),
  ('GARCIAORTA', 3, 'PROVISIONER', 5.4),
  ('GARCIAORTA', 4, 'PILOT', 5.4),
  ('GARCIAORTA', 5, 'WEAPONS_TRADER', 5.4),
  ('GARCIAORTA', 6, 'DYE_TRADER', 5.4),
  ('GARCIAORTA', 7, 'QUARTERMASTER', 5.4),
  ('GARCIAORTA', 8, 'MEDICINE_TRADER', 5.4),
  ('GARCIAORTA', 9, 'CRAFTS_TRADER', 5.4),
  ('GARCIAORTA', 10, 'GRAIN_TRADER', 5.4),
  ('MONARDES', 1, 'SURGEON', 7),
  ('MONARDES', 2, 'PILOT', 4.2),
  ('MONARDES', 3, 'PROVISIONER', 4.2),
  ('MONARDES', 4, 'NAVIGATOR', 4.2),
  ('MONARDES', 5, 'GUNS_TRADER', 4.2),
  ('MONARDES', 6, 'FOOD_TRADER', 4.2),
  ('MONARDES', 7, 'GRAIN_TRADER', 4.2),
  ('MONARDES', 8, 'WEAPONS_TRADER', 4.2),
  ('MONARDES', 9, 'QUARTERMASTER', 4.2),
  ('MONARDES', 10, 'ANIMAL_TRADER', 4.2),
  ('WOODALL', 1, 'SURGEON', 8),
  ('WOODALL', 2, 'PILOT', 4.8),
  ('WOODALL', 3, 'PROVISIONER', 4.8),
  ('WOODALL', 4, 'NAVIGATOR', 4.8),
  ('WOODALL', 5, 'TOBACCO_TRADER', 4.8),
  ('WOODALL', 6, 'CLOTH_TRADER', 4.8),
  ('WOODALL', 7, 'SPICE_TRADER', 4.8),
  ('WOODALL', 8, 'ANIMAL_TRADER', 4.8),
  ('WOODALL', 9, 'DRINK_TRADER', 4.8),
  ('WOODALL', 10, 'BOOK_TRADER', 4.8),
  ('TULPSURG', 1, 'SURGEON', 7.5),
  ('TULPSURG', 2, 'NAVIGATOR', 4.5),
  ('TULPSURG', 3, 'PROVISIONER', 4.5),
  ('TULPSURG', 4, 'PILOT', 4.5),
  ('TULPSURG', 5, 'BOOK_TRADER', 4.5),
  ('TULPSURG', 6, 'DYE_TRADER', 4.5),
  ('TULPSURG', 7, 'SHIP_SUPPLIES_TRADER', 4.5),
  ('TULPSURG', 8, 'ANIMAL_TRADER', 4.5),
  ('TULPSURG', 9, 'WEAPONS_TRADER', 4.5),
  ('TULPSURG', 10, 'BOARDER', 4.5),
  ('SABUNCU', 1, 'SURGEON', 6.5),
  ('SABUNCU', 2, 'NAVIGATOR', 3.9),
  ('SABUNCU', 3, 'PILOT', 3.9),
  ('SABUNCU', 4, 'PROVISIONER', 3.9),
  ('SABUNCU', 5, 'PURSER', 3.9),
  ('SABUNCU', 6, 'MEDICINE_TRADER', 3.9),
  ('SABUNCU', 7, 'QUARTERMASTER', 3.9),
  ('SABUNCU', 8, 'SPICE_TRADER', 3.9),
  ('SABUNCU', 9, 'BOOK_TRADER', 3.9),
  ('SABUNCU', 10, 'GRAIN_TRADER', 3.9),
  ('PERSSURG', 1, 'SURGEON', 6),
  ('PERSSURG', 2, 'PILOT', 3.6),
  ('PERSSURG', 3, 'PROVISIONER', 3.6),
  ('PERSSURG', 4, 'NAVIGATOR', 3.6),
  ('PERSSURG', 5, 'ANIMAL_TRADER', 3.6),
  ('PERSSURG', 6, 'ART_TRADER', 3.6),
  ('PERSSURG', 7, 'GUNS_TRADER', 3.6),
  ('PERSSURG', 8, 'GUNNER', 3.6),
  ('PERSSURG', 9, 'CLOTH_TRADER', 3.6),
  ('PERSSURG', 10, 'SPICE_TRADER', 3.6),
  ('HEOJUN', 1, 'SURGEON', 8.5),
  ('HEOJUN', 2, 'PILOT', 5.1),
  ('HEOJUN', 3, 'PROVISIONER', 5.1),
  ('HEOJUN', 4, 'NAVIGATOR', 5.1),
  ('HEOJUN', 5, 'DRINK_TRADER', 5.1),
  ('HEOJUN', 6, 'BOOK_TRADER', 5.1),
  ('HEOJUN', 7, 'SPICE_TRADER', 5.1),
  ('HEOJUN', 8, 'GRAIN_TRADER', 5.1),
  ('HEOJUN', 9, 'METAL_TRADER', 5.1),
  ('HEOJUN', 10, 'ART_TRADER', 5.1),
  ('LISHIZHEN', 1, 'SURGEON', 8),
  ('LISHIZHEN', 2, 'PROVISIONER', 4.8),
  ('LISHIZHEN', 3, 'PILOT', 4.8),
  ('LISHIZHEN', 4, 'NAVIGATOR', 4.8),
  ('LISHIZHEN', 5, 'GEM_TRADER', 4.8),
  ('LISHIZHEN', 6, 'GUNS_TRADER', 4.8),
  ('LISHIZHEN', 7, 'MEDICINE_TRADER', 4.8),
  ('LISHIZHEN', 8, 'QUARTERMASTER', 4.8),
  ('LISHIZHEN', 9, 'SHIP_SUPPLIES_TRADER', 4.8),
  ('LISHIZHEN', 10, 'CLOTH_TRADER', 4.8),
  ('DANESURG', 1, 'SURGEON', 5.5),
  ('DANESURG', 2, 'NAVIGATOR', 3.3),
  ('DANESURG', 3, 'PROVISIONER', 3.3),
  ('DANESURG', 4, 'PILOT', 3.3),
  ('DANESURG', 5, 'BOARDER', 3.3),
  ('DANESURG', 6, 'ART_TRADER', 3.3),
  ('DANESURG', 7, 'TOBACCO_TRADER', 3.3),
  ('DANESURG', 8, 'METAL_TRADER', 3.3),
  ('DANESURG', 9, 'GUNS_TRADER', 3.3),
  ('DANESURG', 10, 'CRAFTS_TRADER', 3.3),
  ('VENSURG', 1, 'SURGEON', 7),
  ('VENSURG', 2, 'NAVIGATOR', 4.2),
  ('VENSURG', 3, 'PILOT', 4.2),
  ('VENSURG', 4, 'PROVISIONER', 4.2),
  ('VENSURG', 5, 'GUNNER', 4.2),
  ('VENSURG', 6, 'CLOTH_TRADER', 4.2),
  ('VENSURG', 7, 'SHIP_SUPPLIES_TRADER', 4.2),
  ('VENSURG', 8, 'BOOK_TRADER', 4.2),
  ('VENSURG', 9, 'GRAIN_TRADER', 4.2),
  ('VENSURG', 10, 'GEM_TRADER', 4.2),
  ('MALSURG', 1, 'SURGEON', 5),
  ('MALSURG', 2, 'PILOT', 3),
  ('MALSURG', 3, 'NAVIGATOR', 3),
  ('MALSURG', 4, 'PROVISIONER', 3),
  ('MALSURG', 5, 'GEM_TRADER', 3),
  ('MALSURG', 6, 'FOOD_TRADER', 3),
  ('MALSURG', 7, 'CLOTH_TRADER', 3),
  ('MALSURG', 8, 'WEAPONS_TRADER', 3),
  ('MALSURG', 9, 'ANIMAL_TRADER', 3),
  ('MALSURG', 10, 'METAL_TRADER', 3),
  ('WELSER', 1, 'PURSER', 9),
  ('WELSER', 2, 'ART_TRADER', 5.4),
  ('WELSER', 3, 'GRAIN_TRADER', 5.4),
  ('WELSER', 4, 'CRAFTS_TRADER', 5.4),
  ('WELSER', 5, 'SURGEON', 5.4),
  ('WELSER', 6, 'METAL_TRADER', 5.4),
  ('WELSER', 7, 'FOOD_TRADER', 5.4),
  ('WELSER', 8, 'GEM_TRADER', 5.4),
  ('WELSER', 9, 'NAVIGATOR', 5.4),
  ('WELSER', 10, 'MEDICINE_TRADER', 5.4),
  ('MEDICI', 1, 'PURSER', 8),
  ('MEDICI', 2, 'QUARTERMASTER', 4.8),
  ('MEDICI', 3, 'ART_TRADER', 4.8),
  ('MEDICI', 4, 'CRAFTS_TRADER', 4.8),
  ('MEDICI', 5, 'BOARDER', 4.8),
  ('MEDICI', 6, 'PROVISIONER', 4.8),
  ('MEDICI', 7, 'NAVIGATOR', 4.8),
  ('MEDICI', 8, 'TOBACCO_TRADER', 4.8),
  ('MEDICI', 9, 'SPICE_TRADER', 4.8),
  ('MEDICI', 10, 'FOOD_TRADER', 4.8),
  ('GRESHAM', 1, 'PURSER', 8.5),
  ('GRESHAM', 2, 'GUNS_TRADER', 5.1),
  ('GRESHAM', 3, 'MEDICINE_TRADER', 5.1),
  ('GRESHAM', 4, 'GEM_TRADER', 5.1),
  ('GRESHAM', 5, 'FOOD_TRADER', 5.1),
  ('GRESHAM', 6, 'BOOK_TRADER', 5.1),
  ('GRESHAM', 7, 'SPICE_TRADER', 5.1),
  ('GRESHAM', 8, 'NAVIGATOR', 5.1),
  ('GRESHAM', 9, 'QUARTERMASTER', 5.1),
  ('GRESHAM', 10, 'ART_TRADER', 5.1),
  ('AMSPURSER', 1, 'PURSER', 7.5),
  ('AMSPURSER', 2, 'QUARTERMASTER', 4.5),
  ('AMSPURSER', 3, 'GRAIN_TRADER', 4.5),
  ('AMSPURSER', 4, 'SHIP_SUPPLIES_TRADER', 4.5),
  ('AMSPURSER', 5, 'NAVIGATOR', 4.5),
  ('AMSPURSER', 6, 'BOOK_TRADER', 4.5),
  ('AMSPURSER', 7, 'ANIMAL_TRADER', 4.5),
  ('AMSPURSER', 8, 'PILOT', 4.5),
  ('AMSPURSER', 9, 'GEM_TRADER', 4.5),
  ('AMSPURSER', 10, 'SURGEON', 4.5),
  ('PORTPURSER', 1, 'PURSER', 6.5),
  ('PORTPURSER', 2, 'BOOK_TRADER', 3.9),
  ('PORTPURSER', 3, 'CLOTH_TRADER', 3.9),
  ('PORTPURSER', 4, 'GRAIN_TRADER', 3.9),
  ('PORTPURSER', 5, 'PILOT', 3.9),
  ('PORTPURSER', 6, 'GUNS_TRADER', 3.9),
  ('PORTPURSER', 7, 'CRAFTS_TRADER', 3.9),
  ('PORTPURSER', 8, 'METAL_TRADER', 3.9),
  ('PORTPURSER', 9, 'DYE_TRADER', 3.9),
  ('PORTPURSER', 10, 'GUNNER', 3.9),
  ('SEVPURSER', 1, 'PURSER', 7),
  ('SEVPURSER', 2, 'FOOD_TRADER', 4.2),
  ('SEVPURSER', 3, 'GUNS_TRADER', 4.2),
  ('SEVPURSER', 4, 'GEM_TRADER', 4.2),
  ('SEVPURSER', 5, 'SHIP_SUPPLIES_TRADER', 4.2),
  ('SEVPURSER', 6, 'GUNNER', 4.2),
  ('SEVPURSER', 7, 'BOOK_TRADER', 4.2),
  ('SEVPURSER', 8, 'QUARTERMASTER', 4.2),
  ('SEVPURSER', 9, 'TOBACCO_TRADER', 4.2),
  ('SEVPURSER', 10, 'GRAIN_TRADER', 4.2),
  ('OTTPURSER', 1, 'PURSER', 7.5),
  ('OTTPURSER', 2, 'WEAPONS_TRADER', 4.5),
  ('OTTPURSER', 3, 'GEM_TRADER', 4.5),
  ('OTTPURSER', 4, 'CLOTH_TRADER', 4.5),
  ('OTTPURSER', 5, 'GUNNER', 4.5),
  ('OTTPURSER', 6, 'BOARDER', 4.5),
  ('OTTPURSER', 7, 'QUARTERMASTER', 4.5),
  ('OTTPURSER', 8, 'GUNS_TRADER', 4.5),
  ('OTTPURSER', 9, 'SURGEON', 4.5),
  ('OTTPURSER', 10, 'PILOT', 4.5),
  ('MUGPURSER', 1, 'PURSER', 9),
  ('MUGPURSER', 2, 'FOOD_TRADER', 5.4),
  ('MUGPURSER', 3, 'GUNS_TRADER', 5.4),
  ('MUGPURSER', 4, 'QUARTERMASTER', 5.4),
  ('MUGPURSER', 5, 'GEM_TRADER', 5.4),
  ('MUGPURSER', 6, 'PILOT', 5.4),
  ('MUGPURSER', 7, 'SHIP_SUPPLIES_TRADER', 5.4),
  ('MUGPURSER', 8, 'CLOTH_TRADER', 5.4),
  ('MUGPURSER', 9, 'SURGEON', 5.4),
  ('MUGPURSER', 10, 'SPICE_TRADER', 5.4),
  ('SAKAIPURSER', 1, 'PURSER', 7),
  ('SAKAIPURSER', 2, 'WEAPONS_TRADER', 4.2),
  ('SAKAIPURSER', 3, 'MEDICINE_TRADER', 4.2),
  ('SAKAIPURSER', 4, 'GRAIN_TRADER', 4.2),
  ('SAKAIPURSER', 5, 'NAVIGATOR', 4.2),
  ('SAKAIPURSER', 6, 'PILOT', 4.2),
  ('SAKAIPURSER', 7, 'GEM_TRADER', 4.2),
  ('SAKAIPURSER', 8, 'SPICE_TRADER', 4.2),
  ('SAKAIPURSER', 9, 'TOBACCO_TRADER', 4.2),
  ('SAKAIPURSER', 10, 'GUNS_TRADER', 4.2),
  ('POLPURSER', 1, 'PURSER', 6),
  ('POLPURSER', 2, 'SHIP_SUPPLIES_TRADER', 3.6),
  ('POLPURSER', 3, 'BOOK_TRADER', 3.6),
  ('POLPURSER', 4, 'DRINK_TRADER', 3.6),
  ('POLPURSER', 5, 'METAL_TRADER', 3.6),
  ('POLPURSER', 6, 'MEDICINE_TRADER', 3.6),
  ('POLPURSER', 7, 'CLOTH_TRADER', 3.6),
  ('POLPURSER', 8, 'WEAPONS_TRADER', 3.6),
  ('POLPURSER', 9, 'FOOD_TRADER', 3.6),
  ('POLPURSER', 10, 'GEM_TRADER', 3.6),
  ('RUSPURSER', 1, 'PURSER', 6.5),
  ('RUSPURSER', 2, 'ART_TRADER', 3.9),
  ('RUSPURSER', 3, 'GRAIN_TRADER', 3.9),
  ('RUSPURSER', 4, 'CLOTH_TRADER', 3.9),
  ('RUSPURSER', 5, 'BOARDER', 3.9),
  ('RUSPURSER', 6, 'NAVIGATOR', 3.9),
  ('RUSPURSER', 7, 'SPICE_TRADER', 3.9),
  ('RUSPURSER', 8, 'GUNS_TRADER', 3.9),
  ('RUSPURSER', 9, 'PILOT', 3.9),
  ('RUSPURSER', 10, 'BOOK_TRADER', 3.9),
  ('ALCANT', 1, 'QUARTERMASTER', 6),
  ('ALCANT', 2, 'GUNS_TRADER', 3.6),
  ('ALCANT', 3, 'ART_TRADER', 3.6),
  ('ALCANT', 4, 'MEDICINE_TRADER', 3.6),
  ('ALCANT', 5, 'DRINK_TRADER', 3.6),
  ('ALCANT', 6, 'TOBACCO_TRADER', 3.6),
  ('ALCANT', 7, 'PILOT', 3.6),
  ('ALCANT', 8, 'NAVIGATOR', 3.6),
  ('ALCANT', 9, 'GEM_TRADER', 3.6),
  ('ALCANT', 10, 'DYE_TRADER', 3.6),
  ('BARROS', 1, 'PURSER', 4),
  ('BARROS', 2, 'CRAFTS_TRADER', 2.4),
  ('BARROS', 3, 'QUARTERMASTER', 2.4),
  ('BARROS', 4, 'FOOD_TRADER', 2.4),
  ('BARROS', 5, 'DRINK_TRADER', 2.4),
  ('BARROS', 6, 'MEDICINE_TRADER', 2.4),
  ('BARROS', 7, 'SURGEON', 2.4),
  ('BARROS', 8, 'ART_TRADER', 2.4),
  ('BARROS', 9, 'SPICE_TRADER', 2.4),
  ('BARROS', 10, 'METAL_TRADER', 2.4),
  ('DIASNAV', 1, 'NAVIGATOR', 8),
  ('DIASNAV', 2, 'PILOT', 4.8),
  ('DIASNAV', 3, 'SURGEON', 4.8),
  ('DIASNAV', 4, 'PROVISIONER', 4.8),
  ('DIASNAV', 5, 'METAL_TRADER', 4.8),
  ('DIASNAV', 6, 'QUARTERMASTER', 4.8),
  ('DIASNAV', 7, 'SHIP_SUPPLIES_TRADER', 4.8),
  ('DIASNAV', 8, 'ANIMAL_TRADER', 4.8),
  ('DIASNAV', 9, 'GUNS_TRADER', 4.8),
  ('DIASNAV', 10, 'BOARDER', 4.8),
  ('FUGGER', 1, 'PURSER', 6),
  ('FUGGER', 2, 'TOBACCO_TRADER', 3.6),
  ('FUGGER', 3, 'GUNS_TRADER', 3.6),
  ('FUGGER', 4, 'QUARTERMASTER', 3.6),
  ('FUGGER', 5, 'PROVISIONER', 3.6),
  ('FUGGER', 6, 'METAL_TRADER', 3.6),
  ('FUGGER', 7, 'ART_TRADER', 3.6),
  ('FUGGER', 8, 'MEDICINE_TRADER', 3.6),
  ('FUGGER', 9, 'NAVIGATOR', 3.6),
  ('FUGGER', 10, 'PILOT', 3.6),
  ('HOLBEK', 1, 'QUARTERMASTER', 4),
  ('HOLBEK', 2, 'PURSER', 2.4),
  ('HOLBEK', 3, 'GEM_TRADER', 2.4),
  ('HOLBEK', 4, 'SPICE_TRADER', 2.4),
  ('HOLBEK', 5, 'PILOT', 2.4),
  ('HOLBEK', 6, 'SURGEON', 2.4),
  ('HOLBEK', 7, 'ART_TRADER', 2.4),
  ('HOLBEK', 8, 'WEAPONS_TRADER', 2.4),
  ('HOLBEK', 9, 'TOBACCO_TRADER', 2.4),
  ('HOLBEK', 10, 'CRAFTS_TRADER', 2.4),
  ('MOREAU', 1, 'SURGEON', 4),
  ('MOREAU', 2, 'PROVISIONER', 2.4),
  ('MOREAU', 3, 'NAVIGATOR', 2.4),
  ('MOREAU', 4, 'PILOT', 2.4),
  ('MOREAU', 5, 'ANIMAL_TRADER', 2.4),
  ('MOREAU', 6, 'WEAPONS_TRADER', 2.4),
  ('MOREAU', 7, 'ART_TRADER', 2.4),
  ('MOREAU', 8, 'BOOK_TRADER', 2.4),
  ('MOREAU', 9, 'METAL_TRADER', 2.4),
  ('MOREAU', 10, 'BOARDER', 2.4),
  ('NPCPILOTGEN', 1, 'NAVIGATOR', 4),
  ('NPCPILOTGEN', 2, 'PROVISIONER', 2.4),
  ('NPCPILOTGEN', 3, 'PILOT', 2.4),
  ('NPCPILOTGEN', 4, 'SURGEON', 2.4),
  ('NPCPILOTGEN', 5, 'TOBACCO_TRADER', 2.4),
  ('NPCPILOTGEN', 6, 'METAL_TRADER', 2.4),
  ('NPCPILOTGEN', 7, 'SHIP_SUPPLIES_TRADER', 2.4),
  ('NPCPILOTGEN', 8, 'DRINK_TRADER', 2.4),
  ('NPCPILOTGEN', 9, 'ART_TRADER', 2.4),
  ('NPCPILOTGEN', 10, 'FOOD_TRADER', 2.4),
  ('NPCPILOTMNG', 1, 'NAVIGATOR', 4.5),
  ('NPCPILOTMNG', 2, 'PROVISIONER', 2.7),
  ('NPCPILOTMNG', 3, 'SURGEON', 2.7),
  ('NPCPILOTMNG', 4, 'PILOT', 2.7),
  ('NPCPILOTMNG', 5, 'SHIP_SUPPLIES_TRADER', 2.7),
  ('NPCPILOTMNG', 6, 'PURSER', 2.7),
  ('NPCPILOTMNG', 7, 'ART_TRADER', 2.7),
  ('NPCPILOTMNG', 8, 'CLOTH_TRADER', 2.7),
  ('NPCPILOTMNG', 9, 'ANIMAL_TRADER', 2.7),
  ('NPCPILOTMNG', 10, 'SPICE_TRADER', 2.7),
  ('NPCPILOTOTT', 1, 'NAVIGATOR', 5),
  ('NPCPILOTOTT', 2, 'PROVISIONER', 3),
  ('NPCPILOTOTT', 3, 'PILOT', 3),
  ('NPCPILOTOTT', 4, 'SURGEON', 3),
  ('NPCPILOTOTT', 5, 'METAL_TRADER', 3),
  ('NPCPILOTOTT', 6, 'GEM_TRADER', 3),
  ('NPCPILOTOTT', 7, 'ANIMAL_TRADER', 3),
  ('NPCPILOTOTT', 8, 'SPICE_TRADER', 3),
  ('NPCPILOTOTT', 9, 'WEAPONS_TRADER', 3),
  ('NPCPILOTOTT', 10, 'CLOTH_TRADER', 3),
  ('NPCPILOTPRT', 1, 'NAVIGATOR', 4),
  ('NPCPILOTPRT', 2, 'PROVISIONER', 2.4),
  ('NPCPILOTPRT', 3, 'SURGEON', 2.4),
  ('NPCPILOTPRT', 4, 'PILOT', 2.4),
  ('NPCPILOTPRT', 5, 'CRAFTS_TRADER', 2.4),
  ('NPCPILOTPRT', 6, 'GUNS_TRADER', 2.4),
  ('NPCPILOTPRT', 7, 'FOOD_TRADER', 2.4),
  ('NPCPILOTPRT', 8, 'WEAPONS_TRADER', 2.4),
  ('NPCPILOTPRT', 9, 'GUNNER', 2.4),
  ('NPCPILOTPRT', 10, 'BOARDER', 2.4),
  ('NPCPURSERESP', 1, 'PURSER', 4.5),
  ('NPCPURSERESP', 2, 'CLOTH_TRADER', 2.7),
  ('NPCPURSERESP', 3, 'SHIP_SUPPLIES_TRADER', 2.7),
  ('NPCPURSERESP', 4, 'GUNS_TRADER', 2.7),
  ('NPCPURSERESP', 5, 'GRAIN_TRADER', 2.7),
  ('NPCPURSERESP', 6, 'PROVISIONER', 2.7),
  ('NPCPURSERESP', 7, 'GEM_TRADER', 2.7),
  ('NPCPURSERESP', 8, 'CRAFTS_TRADER', 2.7),
  ('NPCPURSERESP', 9, 'BOARDER', 2.7),
  ('NPCPURSERESP', 10, 'TOBACCO_TRADER', 2.7),
  ('NPCPURSERMUG', 1, 'PURSER', 6),
  ('NPCPURSERMUG', 2, 'QUARTERMASTER', 3.6),
  ('NPCPURSERMUG', 3, 'CLOTH_TRADER', 3.6),
  ('NPCPURSERMUG', 4, 'ANIMAL_TRADER', 3.6),
  ('NPCPURSERMUG', 5, 'TOBACCO_TRADER', 3.6),
  ('NPCPURSERMUG', 6, 'GUNS_TRADER', 3.6),
  ('NPCPURSERMUG', 7, 'SURGEON', 3.6),
  ('NPCPURSERMUG', 8, 'CRAFTS_TRADER', 3.6),
  ('NPCPURSERMUG', 9, 'FOOD_TRADER', 3.6),
  ('NPCPURSERMUG', 10, 'BOARDER', 3.6),
  ('NPCPURSERVEN', 1, 'PURSER', 5),
  ('NPCPURSERVEN', 2, 'ANIMAL_TRADER', 3),
  ('NPCPURSERVEN', 3, 'GUNS_TRADER', 3),
  ('NPCPURSERVEN', 4, 'WEAPONS_TRADER', 3),
  ('NPCPURSERVEN', 5, 'PROVISIONER', 3),
  ('NPCPURSERVEN', 6, 'PILOT', 3),
  ('NPCPURSERVEN', 7, 'GRAIN_TRADER', 3),
  ('NPCPURSERVEN', 8, 'QUARTERMASTER', 3),
  ('NPCPURSERVEN', 9, 'ART_TRADER', 3),
  ('NPCPURSERVEN', 10, 'NAVIGATOR', 3),
  ('NPCQMHAN', 1, 'QUARTERMASTER', 4.5),
  ('NPCQMHAN', 2, 'DRINK_TRADER', 2.7),
  ('NPCQMHAN', 3, 'SHIP_SUPPLIES_TRADER', 2.7),
  ('NPCQMHAN', 4, 'FOOD_TRADER', 2.7),
  ('NPCQMHAN', 5, 'SURGEON', 2.7),
  ('NPCQMHAN', 6, 'PURSER', 2.7),
  ('NPCQMHAN', 7, 'PILOT', 2.7),
  ('NPCQMHAN', 8, 'TOBACCO_TRADER', 2.7),
  ('NPCQMHAN', 9, 'GUNNER', 2.7),
  ('NPCQMHAN', 10, 'GRAIN_TRADER', 2.7),
  ('NPCQMJPN', 1, 'QUARTERMASTER', 5),
  ('NPCQMJPN', 2, 'METAL_TRADER', 3),
  ('NPCQMJPN', 3, 'CRAFTS_TRADER', 3),
  ('NPCQMJPN', 4, 'PURSER', 3),
  ('NPCQMJPN', 5, 'SPICE_TRADER', 3),
  ('NPCQMJPN', 6, 'BOARDER', 3),
  ('NPCQMJPN', 7, 'DRINK_TRADER', 3),
  ('NPCQMJPN', 8, 'MEDICINE_TRADER', 3),
  ('NPCQMJPN', 9, 'SURGEON', 3),
  ('NPCQMJPN', 10, 'PROVISIONER', 3),
  ('NPCQMNLD', 1, 'QUARTERMASTER', 5),
  ('NPCQMNLD', 2, 'DYE_TRADER', 3),
  ('NPCQMNLD', 3, 'METAL_TRADER', 3),
  ('NPCQMNLD', 4, 'SPICE_TRADER', 3),
  ('NPCQMNLD', 5, 'SURGEON', 3),
  ('NPCQMNLD', 6, 'CRAFTS_TRADER', 3),
  ('NPCQMNLD', 7, 'SHIP_SUPPLIES_TRADER', 3),
  ('NPCQMNLD', 8, 'PROVISIONER', 3),
  ('NPCQMNLD', 9, 'GUNNER', 3),
  ('NPCQMNLD', 10, 'WEAPONS_TRADER', 3),
  ('NPCSURGENG', 1, 'SURGEON', 4),
  ('NPCSURGENG', 2, 'NAVIGATOR', 2.4),
  ('NPCSURGENG', 3, 'PILOT', 2.4),
  ('NPCSURGENG', 4, 'PROVISIONER', 2.4),
  ('NPCSURGENG', 5, 'DYE_TRADER', 2.4),
  ('NPCSURGENG', 6, 'QUARTERMASTER', 2.4),
  ('NPCSURGENG', 7, 'PURSER', 2.4),
  ('NPCSURGENG', 8, 'FOOD_TRADER', 2.4),
  ('NPCSURGENG', 9, 'SHIP_SUPPLIES_TRADER', 2.4),
  ('NPCSURGENG', 10, 'GUNS_TRADER', 2.4),
  ('NPCSURGFRA', 1, 'SURGEON', 4),
  ('NPCSURGFRA', 2, 'PILOT', 2.4),
  ('NPCSURGFRA', 3, 'PROVISIONER', 2.4),
  ('NPCSURGFRA', 4, 'NAVIGATOR', 2.4),
  ('NPCSURGFRA', 5, 'METAL_TRADER', 2.4),
  ('NPCSURGFRA', 6, 'PURSER', 2.4),
  ('NPCSURGFRA', 7, 'GUNNER', 2.4),
  ('NPCSURGFRA', 8, 'SPICE_TRADER', 2.4),
  ('NPCSURGFRA', 9, 'WEAPONS_TRADER', 2.4),
  ('NPCSURGFRA', 10, 'GUNS_TRADER', 2.4),
  ('PINZON', 1, 'NAVIGATOR', 5),
  ('PINZON', 2, 'PROVISIONER', 3),
  ('PINZON', 3, 'PILOT', 3),
  ('PINZON', 4, 'SURGEON', 3),
  ('PINZON', 5, 'TOBACCO_TRADER', 3),
  ('PINZON', 6, 'DYE_TRADER', 3),
  ('PINZON', 7, 'CRAFTS_TRADER', 3),
  ('PINZON', 8, 'BOARDER', 3),
  ('PINZON', 9, 'CLOTH_TRADER', 3),
  ('PINZON', 10, 'GRAIN_TRADER', 3),
  ('ZAHRA', 1, 'SURGEON', 7),
  ('ZAHRA', 2, 'PILOT', 4.2),
  ('ZAHRA', 3, 'NAVIGATOR', 4.2),
  ('ZAHRA', 4, 'PROVISIONER', 4.2),
  ('ZAHRA', 5, 'GRAIN_TRADER', 4.2),
  ('ZAHRA', 6, 'FOOD_TRADER', 4.2),
  ('ZAHRA', 7, 'BOARDER', 4.2),
  ('ZAHRA', 8, 'MEDICINE_TRADER', 4.2),
  ('ZAHRA', 9, 'QUARTERMASTER', 4.2),
  ('ZAHRA', 10, 'DYE_TRADER', 4.2),
  ('LISBOAPIL', 1, 'PILOT', 6),
  ('LISBOAPIL', 2, 'PROVISIONER', 3.6),
  ('LISBOAPIL', 3, 'SURGEON', 3.6),
  ('LISBOAPIL', 4, 'NAVIGATOR', 3.6),
  ('LISBOAPIL', 5, 'GUNS_TRADER', 3.6),
  ('LISBOAPIL', 6, 'GUNNER', 3.6),
  ('LISBOAPIL', 7, 'PURSER', 3.6),
  ('LISBOAPIL', 8, 'BOARDER', 3.6),
  ('LISBOAPIL', 9, 'CRAFTS_TRADER', 3.6),
  ('LISBOAPIL', 10, 'DRINK_TRADER', 3.6),
  ('URDANETA', 1, 'PILOT', 9),
  ('URDANETA', 2, 'SURGEON', 5.4),
  ('URDANETA', 3, 'PROVISIONER', 5.4),
  ('URDANETA', 4, 'NAVIGATOR', 5.4),
  ('URDANETA', 5, 'CLOTH_TRADER', 5.4),
  ('URDANETA', 6, 'SHIP_SUPPLIES_TRADER', 5.4),
  ('URDANETA', 7, 'METAL_TRADER', 5.4),
  ('URDANETA', 8, 'GEM_TRADER', 5.4),
  ('URDANETA', 9, 'WEAPONS_TRADER', 5.4),
  ('URDANETA', 10, 'GRAIN_TRADER', 5.4),
  ('PIGAFETTA', 1, 'PROVISIONER', 4),
  ('PIGAFETTA', 2, 'PILOT', 2.4),
  ('PIGAFETTA', 3, 'SURGEON', 2.4),
  ('PIGAFETTA', 4, 'NAVIGATOR', 2.4),
  ('PIGAFETTA', 5, 'PURSER', 2.4),
  ('PIGAFETTA', 6, 'MEDICINE_TRADER', 2.4),
  ('PIGAFETTA', 7, 'BOOK_TRADER', 2.4),
  ('PIGAFETTA', 8, 'DYE_TRADER', 2.4),
  ('PIGAFETTA', 9, 'TOBACCO_TRADER', 2.4),
  ('PIGAFETTA', 10, 'GUNS_TRADER', 2.4),
  ('DARELL', 1, 'PROVISIONER', 7.5),
  ('DARELL', 2, 'PILOT', 4.5),
  ('DARELL', 3, 'NAVIGATOR', 4.5),
  ('DARELL', 4, 'SURGEON', 4.5),
  ('DARELL', 5, 'SPICE_TRADER', 4.5),
  ('DARELL', 6, 'ART_TRADER', 4.5),
  ('DARELL', 7, 'SHIP_SUPPLIES_TRADER', 4.5),
  ('DARELL', 8, 'ANIMAL_TRADER', 4.5),
  ('DARELL', 9, 'DRINK_TRADER', 4.5),
  ('DARELL', 10, 'GRAIN_TRADER', 4.5),
  ('GIESE', 1, 'GRAIN_TRADER', 5),
  ('GIESE', 2, 'WEAPONS_TRADER', 3),
  ('GIESE', 3, 'GEM_TRADER', 3),
  ('GIESE', 4, 'CLOTH_TRADER', 3),
  ('GIESE', 5, 'QUARTERMASTER', 3),
  ('GIESE', 6, 'NAVIGATOR', 3),
  ('GIESE', 7, 'BOARDER', 3),
  ('GIESE', 8, 'BOOK_TRADER', 3),
  ('GIESE', 9, 'METAL_TRADER', 3),
  ('GIESE', 10, 'PURSER', 3),
  ('VANOS', 1, 'GRAIN_TRADER', 7),
  ('VANOS', 2, 'PURSER', 4.2),
  ('VANOS', 3, 'MEDICINE_TRADER', 4.2),
  ('VANOS', 4, 'SPICE_TRADER', 4.2),
  ('VANOS', 5, 'NAVIGATOR', 4.2),
  ('VANOS', 6, 'ANIMAL_TRADER', 4.2),
  ('VANOS', 7, 'BOOK_TRADER', 4.2),
  ('VANOS', 8, 'TOBACCO_TRADER', 4.2),
  ('VANOS', 9, 'DYE_TRADER', 4.2),
  ('VANOS', 10, 'SHIP_SUPPLIES_TRADER', 4.2),
  ('SCAPPI', 1, 'FOOD_TRADER', 6.5),
  ('SCAPPI', 2, 'TOBACCO_TRADER', 3.9),
  ('SCAPPI', 3, 'BOOK_TRADER', 3.9),
  ('SCAPPI', 4, 'DRINK_TRADER', 3.9),
  ('SCAPPI', 5, 'PROVISIONER', 3.9),
  ('SCAPPI', 6, 'GUNNER', 3.9),
  ('SCAPPI', 7, 'NAVIGATOR', 3.9),
  ('SCAPPI', 8, 'SHIP_SUPPLIES_TRADER', 3.9),
  ('SCAPPI', 9, 'BOARDER', 3.9),
  ('SCAPPI', 10, 'QUARTERMASTER', 3.9),
  ('ESMERALDO', 1, 'FOOD_TRADER', 8.5),
  ('ESMERALDO', 2, 'GUNS_TRADER', 5.1),
  ('ESMERALDO', 3, 'QUARTERMASTER', 5.1),
  ('ESMERALDO', 4, 'SPICE_TRADER', 5.1),
  ('ESMERALDO', 5, 'CRAFTS_TRADER', 5.1),
  ('ESMERALDO', 6, 'CLOTH_TRADER', 5.1),
  ('ESMERALDO', 7, 'ANIMAL_TRADER', 5.1),
  ('ESMERALDO', 8, 'BOOK_TRADER', 5.1),
  ('ESMERALDO', 9, 'PROVISIONER', 5.1),
  ('ESMERALDO', 10, 'DRINK_TRADER', 5.1),
  ('XUCISHU', 1, 'DRINK_TRADER', 4.5),
  ('XUCISHU', 2, 'GRAIN_TRADER', 2.7),
  ('XUCISHU', 3, 'ANIMAL_TRADER', 2.7),
  ('XUCISHU', 4, 'CLOTH_TRADER', 2.7),
  ('XUCISHU', 5, 'BOARDER', 2.7),
  ('XUCISHU', 6, 'PILOT', 2.7),
  ('XUCISHU', 7, 'PURSER', 2.7),
  ('XUCISHU', 8, 'DYE_TRADER', 2.7),
  ('XUCISHU', 9, 'NAVIGATOR', 2.7),
  ('XUCISHU', 10, 'QUARTERMASTER', 2.7),
  ('PONTAC', 1, 'DRINK_TRADER', 9),
  ('PONTAC', 2, 'SHIP_SUPPLIES_TRADER', 5.4),
  ('PONTAC', 3, 'ART_TRADER', 5.4),
  ('PONTAC', 4, 'DYE_TRADER', 5.4),
  ('PONTAC', 5, 'GUNNER', 5.4),
  ('PONTAC', 6, 'GEM_TRADER', 5.4),
  ('PONTAC', 7, 'BOOK_TRADER', 5.4),
  ('PONTAC', 8, 'GUNS_TRADER', 5.4),
  ('PONTAC', 9, 'MEDICINE_TRADER', 5.4),
  ('PONTAC', 10, 'SURGEON', 5.4),
  ('ROLFE', 1, 'TOBACCO_TRADER', 5.5),
  ('ROLFE', 2, 'CRAFTS_TRADER', 3.3),
  ('ROLFE', 3, 'BOOK_TRADER', 3.3),
  ('ROLFE', 4, 'QUARTERMASTER', 3.3),
  ('ROLFE', 5, 'BOARDER', 3.3),
  ('ROLFE', 6, 'ART_TRADER', 3.3),
  ('ROLFE', 7, 'PROVISIONER', 3.3),
  ('ROLFE', 8, 'WEAPONS_TRADER', 3.3),
  ('ROLFE', 9, 'GUNS_TRADER', 3.3),
  ('ROLFE', 10, 'SURGEON', 3.3),
  ('NICOT', 1, 'TOBACCO_TRADER', 7.5),
  ('NICOT', 2, 'WEAPONS_TRADER', 4.5),
  ('NICOT', 3, 'QUARTERMASTER', 4.5),
  ('NICOT', 4, 'GUNS_TRADER', 4.5),
  ('NICOT', 5, 'GUNNER', 4.5),
  ('NICOT', 6, 'ART_TRADER', 4.5),
  ('NICOT', 7, 'PILOT', 4.5),
  ('NICOT', 8, 'DRINK_TRADER', 4.5),
  ('NICOT', 9, 'METAL_TRADER', 4.5),
  ('NICOT', 10, 'SHIP_SUPPLIES_TRADER', 4.5),
  ('MALIKGOPI', 1, 'SPICE_TRADER', 5),
  ('MALIKGOPI', 2, 'GUNS_TRADER', 3),
  ('MALIKGOPI', 3, 'MEDICINE_TRADER', 3),
  ('MALIKGOPI', 4, 'CRAFTS_TRADER', 3),
  ('MALIKGOPI', 5, 'SURGEON', 3),
  ('MALIKGOPI', 6, 'PROVISIONER', 3),
  ('MALIKGOPI', 7, 'ART_TRADER', 3),
  ('MALIKGOPI', 8, 'WEAPONS_TRADER', 3),
  ('MALIKGOPI', 9, 'SHIP_SUPPLIES_TRADER', 3),
  ('MALIKGOPI', 10, 'CLOTH_TRADER', 3),
  ('GRACIANASI', 1, 'SPICE_TRADER', 9),
  ('GRACIANASI', 2, 'SHIP_SUPPLIES_TRADER', 5.4),
  ('GRACIANASI', 3, 'BOOK_TRADER', 5.4),
  ('GRACIANASI', 4, 'ANIMAL_TRADER', 5.4),
  ('GRACIANASI', 5, 'GRAIN_TRADER', 5.4),
  ('GRACIANASI', 6, 'WEAPONS_TRADER', 5.4),
  ('GRACIANASI', 7, 'PURSER', 5.4),
  ('GRACIANASI', 8, 'ART_TRADER', 5.4),
  ('GRACIANASI', 9, 'GUNS_TRADER', 5.4),
  ('GRACIANASI', 10, 'BOARDER', 5.4),
  ('MANASE', 1, 'MEDICINE_TRADER', 6),
  ('MANASE', 2, 'METAL_TRADER', 3.6),
  ('MANASE', 3, 'ART_TRADER', 3.6),
  ('MANASE', 4, 'FOOD_TRADER', 3.6),
  ('MANASE', 5, 'PILOT', 3.6),
  ('MANASE', 6, 'SHIP_SUPPLIES_TRADER', 3.6),
  ('MANASE', 7, 'PURSER', 3.6),
  ('MANASE', 8, 'CLOTH_TRADER', 3.6),
  ('MANASE', 9, 'GEM_TRADER', 3.6),
  ('MANASE', 10, 'DYE_TRADER', 3.6),
  ('DACOSTA', 1, 'MEDICINE_TRADER', 8),
  ('DACOSTA', 2, 'CLOTH_TRADER', 4.8),
  ('DACOSTA', 3, 'QUARTERMASTER', 4.8),
  ('DACOSTA', 4, 'GUNS_TRADER', 4.8),
  ('DACOSTA', 5, 'BOARDER', 4.8),
  ('DACOSTA', 6, 'PROVISIONER', 4.8),
  ('DACOSTA', 7, 'ART_TRADER', 4.8),
  ('DACOSTA', 8, 'TOBACCO_TRADER', 4.8),
  ('DACOSTA', 9, 'GRAIN_TRADER', 4.8),
  ('DACOSTA', 10, 'WEAPONS_TRADER', 4.8),
  ('ASSEZAT', 1, 'DYE_TRADER', 4.5),
  ('ASSEZAT', 2, 'DRINK_TRADER', 2.7),
  ('ASSEZAT', 3, 'CLOTH_TRADER', 2.7),
  ('ASSEZAT', 4, 'ANIMAL_TRADER', 2.7),
  ('ASSEZAT', 5, 'GUNNER', 2.7),
  ('ASSEZAT', 6, 'MEDICINE_TRADER', 2.7),
  ('ASSEZAT', 7, 'BOARDER', 2.7),
  ('ASSEZAT', 8, 'TOBACCO_TRADER', 2.7),
  ('ASSEZAT', 9, 'METAL_TRADER', 2.7),
  ('ASSEZAT', 10, 'BOOK_TRADER', 2.7),
  ('PELSAERT', 1, 'DYE_TRADER', 7.5),
  ('PELSAERT', 2, 'SPICE_TRADER', 4.5),
  ('PELSAERT', 3, 'CLOTH_TRADER', 4.5),
  ('PELSAERT', 4, 'GUNS_TRADER', 4.5),
  ('PELSAERT', 5, 'METAL_TRADER', 4.5),
  ('PELSAERT', 6, 'GRAIN_TRADER', 4.5),
  ('PELSAERT', 7, 'BOOK_TRADER', 4.5),
  ('PELSAERT', 8, 'GEM_TRADER', 4.5),
  ('PELSAERT', 9, 'BOARDER', 4.5),
  ('PELSAERT', 10, 'SURGEON', 4.5),
  ('KHWAJANAZAR', 1, 'CLOTH_TRADER', 6.5),
  ('KHWAJANAZAR', 2, 'CRAFTS_TRADER', 3.9),
  ('KHWAJANAZAR', 3, 'BOOK_TRADER', 3.9),
  ('KHWAJANAZAR', 4, 'WEAPONS_TRADER', 3.9),
  ('KHWAJANAZAR', 5, 'PROVISIONER', 3.9),
  ('KHWAJANAZAR', 6, 'SURGEON', 3.9),
  ('KHWAJANAZAR', 7, 'PILOT', 3.9),
  ('KHWAJANAZAR', 8, 'MEDICINE_TRADER', 3.9),
  ('KHWAJANAZAR', 9, 'SHIP_SUPPLIES_TRADER', 3.9),
  ('KHWAJANAZAR', 10, 'ANIMAL_TRADER', 3.9),
  ('CRANFIELD', 1, 'CLOTH_TRADER', 8.5),
  ('CRANFIELD', 2, 'GUNS_TRADER', 5.1),
  ('CRANFIELD', 3, 'SPICE_TRADER', 5.1),
  ('CRANFIELD', 4, 'MEDICINE_TRADER', 5.1),
  ('CRANFIELD', 5, 'PILOT', 5.1),
  ('CRANFIELD', 6, 'ART_TRADER', 5.1),
  ('CRANFIELD', 7, 'SURGEON', 5.1),
  ('CRANFIELD', 8, 'NAVIGATOR', 5.1),
  ('CRANFIELD', 9, 'CRAFTS_TRADER', 5.1),
  ('CRANFIELD', 10, 'PROVISIONER', 5.1),
  ('KAMIYA', 1, 'METAL_TRADER', 4),
  ('KAMIYA', 2, 'MEDICINE_TRADER', 2.4),
  ('KAMIYA', 3, 'TOBACCO_TRADER', 2.4),
  ('KAMIYA', 4, 'CRAFTS_TRADER', 2.4),
  ('KAMIYA', 5, 'SURGEON', 2.4),
  ('KAMIYA', 6, 'CLOTH_TRADER', 2.4),
  ('KAMIYA', 7, 'SPICE_TRADER', 2.4),
  ('KAMIYA', 8, 'ART_TRADER', 2.4),
  ('KAMIYA', 9, 'GRAIN_TRADER', 2.4),
  ('KAMIYA', 10, 'DRINK_TRADER', 2.4),
  ('THURZO', 1, 'METAL_TRADER', 7),
  ('THURZO', 2, 'TOBACCO_TRADER', 4.2),
  ('THURZO', 3, 'BOOK_TRADER', 4.2),
  ('THURZO', 4, 'CRAFTS_TRADER', 4.2),
  ('THURZO', 5, 'SURGEON', 4.2),
  ('THURZO', 6, 'BOARDER', 4.2),
  ('THURZO', 7, 'DYE_TRADER', 4.2),
  ('THURZO', 8, 'GUNS_TRADER', 4.2),
  ('THURZO', 9, 'PURSER', 4.2),
  ('THURZO', 10, 'PROVISIONER', 4.2),
  ('DECOUTRE', 1, 'GEM_TRADER', 6),
  ('DECOUTRE', 2, 'MEDICINE_TRADER', 3.6),
  ('DECOUTRE', 3, 'SHIP_SUPPLIES_TRADER', 3.6),
  ('DECOUTRE', 4, 'FOOD_TRADER', 3.6),
  ('DECOUTRE', 5, 'SURGEON', 3.6),
  ('DECOUTRE', 6, 'BOARDER', 3.6),
  ('DECOUTRE', 7, 'PILOT', 3.6),
  ('DECOUTRE', 8, 'CLOTH_TRADER', 3.6),
  ('DECOUTRE', 9, 'DYE_TRADER', 3.6),
  ('DECOUTRE', 10, 'PURSER', 3.6),
  ('MIRJUMLA', 1, 'GEM_TRADER', 9),
  ('MIRJUMLA', 2, 'CLOTH_TRADER', 5.4),
  ('MIRJUMLA', 3, 'FOOD_TRADER', 5.4),
  ('MIRJUMLA', 4, 'SPICE_TRADER', 5.4),
  ('MIRJUMLA', 5, 'SURGEON', 5.4),
  ('MIRJUMLA', 6, 'PILOT', 5.4),
  ('MIRJUMLA', 7, 'PROVISIONER', 5.4),
  ('MIRJUMLA', 8, 'MEDICINE_TRADER', 5.4),
  ('MIRJUMLA', 9, 'GRAIN_TRADER', 5.4),
  ('MIRJUMLA', 10, 'CRAFTS_TRADER', 5.4),
  ('BALLARIN', 1, 'CRAFTS_TRADER', 4.5),
  ('BALLARIN', 2, 'CLOTH_TRADER', 2.7),
  ('BALLARIN', 3, 'BOOK_TRADER', 2.7),
  ('BALLARIN', 4, 'WEAPONS_TRADER', 2.7),
  ('BALLARIN', 5, 'PROVISIONER', 2.7),
  ('BALLARIN', 6, 'NAVIGATOR', 2.7),
  ('BALLARIN', 7, 'GRAIN_TRADER', 2.7),
  ('BALLARIN', 8, 'PILOT', 2.7),
  ('BALLARIN', 9, 'PURSER', 2.7),
  ('BALLARIN', 10, 'ART_TRADER', 2.7),
  ('LIDAN', 1, 'CRAFTS_TRADER', 8),
  ('LIDAN', 2, 'CLOTH_TRADER', 4.8),
  ('LIDAN', 3, 'PURSER', 4.8),
  ('LIDAN', 4, 'SPICE_TRADER', 4.8),
  ('LIDAN', 5, 'GEM_TRADER', 4.8),
  ('LIDAN', 6, 'BOOK_TRADER', 4.8),
  ('LIDAN', 7, 'ANIMAL_TRADER', 4.8),
  ('LIDAN', 8, 'MEDICINE_TRADER', 4.8),
  ('LIDAN', 9, 'GUNS_TRADER', 4.8),
  ('LIDAN', 10, 'ART_TRADER', 4.8),
  ('TRIP', 1, 'WEAPONS_TRADER', 6.5),
  ('TRIP', 2, 'SHIP_SUPPLIES_TRADER', 3.9),
  ('TRIP', 3, 'TOBACCO_TRADER', 3.9),
  ('TRIP', 4, 'FOOD_TRADER', 3.9),
  ('TRIP', 5, 'NAVIGATOR', 3.9),
  ('TRIP', 6, 'SURGEON', 3.9),
  ('TRIP', 7, 'PILOT', 3.9),
  ('TRIP', 8, 'BOOK_TRADER', 3.9),
  ('TRIP', 9, 'DRINK_TRADER', 3.9),
  ('TRIP', 10, 'CLOTH_TRADER', 3.9),
  ('AYALA', 1, 'WEAPONS_TRADER', 7),
  ('AYALA', 2, 'FOOD_TRADER', 4.2),
  ('AYALA', 3, 'PURSER', 4.2),
  ('AYALA', 4, 'SHIP_SUPPLIES_TRADER', 4.2),
  ('AYALA', 5, 'SURGEON', 4.2),
  ('AYALA', 6, 'GUNNER', 4.2),
  ('AYALA', 7, 'NAVIGATOR', 4.2),
  ('AYALA', 8, 'CRAFTS_TRADER', 4.2),
  ('AYALA', 9, 'TOBACCO_TRADER', 4.2),
  ('AYALA', 10, 'ANIMAL_TRADER', 4.2),
  ('TANEGASHIMA', 1, 'GUNS_TRADER', 5),
  ('TANEGASHIMA', 2, 'MEDICINE_TRADER', 3),
  ('TANEGASHIMA', 3, 'BOOK_TRADER', 3),
  ('TANEGASHIMA', 4, 'FOOD_TRADER', 3),
  ('TANEGASHIMA', 5, 'PROVISIONER', 3),
  ('TANEGASHIMA', 6, 'METAL_TRADER', 3),
  ('TANEGASHIMA', 7, 'GUNNER', 3),
  ('TANEGASHIMA', 8, 'SHIP_SUPPLIES_TRADER', 3),
  ('TANEGASHIMA', 9, 'NAVIGATOR', 3),
  ('TANEGASHIMA', 10, 'CRAFTS_TRADER', 3),
  ('DEGEER', 1, 'GUNS_TRADER', 8),
  ('DEGEER', 2, 'FOOD_TRADER', 4.8),
  ('DEGEER', 3, 'GEM_TRADER', 4.8),
  ('DEGEER', 4, 'WEAPONS_TRADER', 4.8),
  ('DEGEER', 5, 'GUNNER', 4.8),
  ('DEGEER', 6, 'PILOT', 4.8),
  ('DEGEER', 7, 'PURSER', 4.8),
  ('DEGEER', 8, 'MEDICINE_TRADER', 4.8),
  ('DEGEER', 9, 'DYE_TRADER', 4.8),
  ('DEGEER', 10, 'ANIMAL_TRADER', 4.8),
  ('VALKENDORF', 1, 'SHIP_SUPPLIES_TRADER', 5.5),
  ('VALKENDORF', 2, 'METAL_TRADER', 3.3),
  ('VALKENDORF', 3, 'BOOK_TRADER', 3.3),
  ('VALKENDORF', 4, 'CRAFTS_TRADER', 3.3),
  ('VALKENDORF', 5, 'SPICE_TRADER', 3.3),
  ('VALKENDORF', 6, 'QUARTERMASTER', 3.3),
  ('VALKENDORF', 7, 'NAVIGATOR', 3.3),
  ('VALKENDORF', 8, 'WEAPONS_TRADER', 3.3),
  ('VALKENDORF', 9, 'BOARDER', 3.3),
  ('VALKENDORF', 10, 'PROVISIONER', 3.3),
  ('BOSOY', 1, 'SHIP_SUPPLIES_TRADER', 7.5),
  ('BOSOY', 2, 'CLOTH_TRADER', 4.5),
  ('BOSOY', 3, 'GRAIN_TRADER', 4.5),
  ('BOSOY', 4, 'METAL_TRADER', 4.5),
  ('BOSOY', 5, 'ART_TRADER', 4.5),
  ('BOSOY', 6, 'FOOD_TRADER', 4.5),
  ('BOSOY', 7, 'QUARTERMASTER', 4.5),
  ('BOSOY', 8, 'MEDICINE_TRADER', 4.5),
  ('BOSOY', 9, 'ANIMAL_TRADER', 4.5),
  ('BOSOY', 10, 'PURSER', 4.5),
  ('UYLENBURGH', 1, 'ART_TRADER', 5),
  ('UYLENBURGH', 2, 'GRAIN_TRADER', 3),
  ('UYLENBURGH', 3, 'SHIP_SUPPLIES_TRADER', 3),
  ('UYLENBURGH', 4, 'PURSER', 3),
  ('UYLENBURGH', 5, 'GUNNER', 3),
  ('UYLENBURGH', 6, 'PROVISIONER', 3),
  ('UYLENBURGH', 7, 'NAVIGATOR', 3),
  ('UYLENBURGH', 8, 'MEDICINE_TRADER', 3),
  ('UYLENBURGH', 9, 'SURGEON', 3),
  ('UYLENBURGH', 10, 'SPICE_TRADER', 3),
  ('NIJS', 1, 'ART_TRADER', 8.5),
  ('NIJS', 2, 'GEM_TRADER', 5.1),
  ('NIJS', 3, 'TOBACCO_TRADER', 5.1),
  ('NIJS', 4, 'CLOTH_TRADER', 5.1),
  ('NIJS', 5, 'SPICE_TRADER', 5.1),
  ('NIJS', 6, 'WEAPONS_TRADER', 5.1),
  ('NIJS', 7, 'DRINK_TRADER', 5.1),
  ('NIJS', 8, 'PURSER', 5.1),
  ('NIJS', 9, 'GRAIN_TRADER', 5.1),
  ('NIJS', 10, 'FOOD_TRADER', 5.1),
  ('YUXIANGDOU', 1, 'BOOK_TRADER', 6),
  ('YUXIANGDOU', 2, 'GUNS_TRADER', 3.6),
  ('YUXIANGDOU', 3, 'CRAFTS_TRADER', 3.6),
  ('YUXIANGDOU', 4, 'GEM_TRADER', 3.6),
  ('YUXIANGDOU', 5, 'PILOT', 3.6),
  ('YUXIANGDOU', 6, 'PROVISIONER', 3.6),
  ('YUXIANGDOU', 7, 'BOARDER', 3.6),
  ('YUXIANGDOU', 8, 'NAVIGATOR', 3.6),
  ('YUXIANGDOU', 9, 'DYE_TRADER', 3.6),
  ('YUXIANGDOU', 10, 'METAL_TRADER', 3.6),
  ('PLANTIN', 1, 'BOOK_TRADER', 8),
  ('PLANTIN', 2, 'CLOTH_TRADER', 4.8),
  ('PLANTIN', 3, 'CRAFTS_TRADER', 4.8),
  ('PLANTIN', 4, 'GEM_TRADER', 4.8),
  ('PLANTIN', 5, 'SPICE_TRADER', 4.8),
  ('PLANTIN', 6, 'GUNNER', 4.8),
  ('PLANTIN', 7, 'DRINK_TRADER', 4.8),
  ('PLANTIN', 8, 'GRAIN_TRADER', 4.8),
  ('PLANTIN', 9, 'QUARTERMASTER', 4.8),
  ('PLANTIN', 10, 'ART_TRADER', 4.8),
  ('OXE', 1, 'ANIMAL_TRADER', 4),
  ('OXE', 2, 'MEDICINE_TRADER', 2.4),
  ('OXE', 3, 'GRAIN_TRADER', 2.4),
  ('OXE', 4, 'DRINK_TRADER', 2.4),
  ('OXE', 5, 'PILOT', 2.4),
  ('OXE', 6, 'BOARDER', 2.4),
  ('OXE', 7, 'NAVIGATOR', 2.4),
  ('OXE', 8, 'SURGEON', 2.4),
  ('OXE', 9, 'PROVISIONER', 2.4),
  ('OXE', 10, 'GUNNER', 2.4),
  ('GHULAMHUSAYN', 1, 'ANIMAL_TRADER', 7),
  ('GHULAMHUSAYN', 2, 'SPICE_TRADER', 4.2),
  ('GHULAMHUSAYN', 3, 'ART_TRADER', 4.2),
  ('GHULAMHUSAYN', 4, 'DRINK_TRADER', 4.2),
  ('GHULAMHUSAYN', 5, 'SURGEON', 4.2),
  ('GHULAMHUSAYN', 6, 'BOOK_TRADER', 4.2),
  ('GHULAMHUSAYN', 7, 'PROVISIONER', 4.2),
  ('GHULAMHUSAYN', 8, 'QUARTERMASTER', 4.2),
  ('GHULAMHUSAYN', 9, 'NAVIGATOR', 4.2),
  ('GHULAMHUSAYN', 10, 'BOARDER', 4.2),
  ('TARTAGLIA', 1, 'GUNNER', 4.5),
  ('TARTAGLIA', 2, 'BOARDER', 2.7),
  ('TARTAGLIA', 3, 'QUARTERMASTER', 2.7),
  ('TARTAGLIA', 4, 'CLOTH_TRADER', 2.7),
  ('TARTAGLIA', 5, 'DRINK_TRADER', 2.7),
  ('TARTAGLIA', 6, 'GRAIN_TRADER', 2.7),
  ('TARTAGLIA', 7, 'NAVIGATOR', 2.7),
  ('TARTAGLIA', 8, 'SPICE_TRADER', 2.7),
  ('TARTAGLIA', 9, 'SHIP_SUPPLIES_TRADER', 2.7),
  ('TARTAGLIA', 10, 'PURSER', 2.7),
  ('YIJANGSON', 1, 'GUNNER', 7.5),
  ('YIJANGSON', 2, 'BOARDER', 4.5),
  ('YIJANGSON', 3, 'GRAIN_TRADER', 4.5),
  ('YIJANGSON', 4, 'GUNS_TRADER', 4.5),
  ('YIJANGSON', 5, 'MEDICINE_TRADER', 4.5),
  ('YIJANGSON', 6, 'PROVISIONER', 4.5),
  ('YIJANGSON', 7, 'QUARTERMASTER', 4.5),
  ('YIJANGSON', 8, 'ART_TRADER', 4.5),
  ('YIJANGSON', 9, 'CRAFTS_TRADER', 4.5),
  ('YIJANGSON', 10, 'FOOD_TRADER', 4.5),
  ('MURAKAMI', 1, 'BOARDER', 6.5),
  ('MURAKAMI', 2, 'GUNNER', 3.9),
  ('MURAKAMI', 3, 'SURGEON', 3.9),
  ('MURAKAMI', 4, 'QUARTERMASTER', 3.9),
  ('MURAKAMI', 5, 'DYE_TRADER', 3.9),
  ('MURAKAMI', 6, 'GEM_TRADER', 3.9),
  ('MURAKAMI', 7, 'SHIP_SUPPLIES_TRADER', 3.9),
  ('MURAKAMI', 8, 'ART_TRADER', 3.9),
  ('MURAKAMI', 9, 'ANIMAL_TRADER', 3.9),
  ('MURAKAMI', 10, 'PURSER', 3.9),
  ('TURGUT', 1, 'BOARDER', 9),
  ('TURGUT', 2, 'GUNNER', 5.4),
  ('TURGUT', 3, 'GUNS_TRADER', 5.4),
  ('TURGUT', 4, 'TOBACCO_TRADER', 5.4),
  ('TURGUT', 5, 'GRAIN_TRADER', 5.4),
  ('TURGUT', 6, 'METAL_TRADER', 5.4),
  ('TURGUT', 7, 'DRINK_TRADER', 5.4),
  ('TURGUT', 8, 'PURSER', 5.4),
  ('TURGUT', 9, 'PROVISIONER', 5.4),
  ('TURGUT', 10, 'CLOTH_TRADER', 5.4)
       ) w(code, ord, trait, pct)
  join public.officers o on o.code = w.code;

insert into public.captain_languages (officer_id, ord, language)
select o.id, w.ord, w.language
  from (values
  ('CABRALNAV', 1, 'PORTUGUESE'),
  ('CABRALNAV', 2, 'SPANISH'),
  ('ELCANO', 1, 'SPANISH'),
  ('ELCANO', 2, 'PORTUGUESE'),
  ('ELCANO', 3, 'TURKISH'),
  ('CHANCELLOR', 1, 'ENGLISH'),
  ('BARENTS', 1, 'DUTCH'),
  ('BARENTS', 2, 'FRENCH'),
  ('PIRIREIS', 1, 'TURKISH'),
  ('PIRIREIS', 2, 'ITALIAN'),
  ('PIRIREIS', 3, 'SPANISH'),
  ('IBNMAJID', 1, 'INDIC'),
  ('IBNMAJID', 2, 'PORTUGUESE'),
  ('ZHENGPIL', 1, 'PORTUGUESE'),
  ('ZHENGPIL', 2, 'CHINESE'),
  ('JEONGNAV', 1, 'KOREAN'),
  ('BERGENNAV', 1, 'NORDIC'),
  ('VENEZNAV', 1, 'ITALIAN'),
  ('MALACCANAV', 1, 'PORTUGUESE'),
  ('ALBUQUERQ', 1, 'ITALIAN'),
  ('ALBUQUERQ', 2, 'PORTUGUESE'),
  ('MENDANA', 1, 'SPANISH'),
  ('HAWKINSQM', 1, 'ENGLISH'),
  ('HAWKINSQM', 2, 'SPANISH'),
  ('COENQM', 1, 'MALAY'),
  ('COENQM', 2, 'DUTCH'),
  ('COENQM', 3, 'SPANISH'),
  ('HANSEQM', 1, 'GERMAN'),
  ('GUJARATQM', 1, 'INDIC'),
  ('GUJARATQM', 2, 'PORTUGUESE'),
  ('SAKAIQM', 1, 'JAPANESE'),
  ('MOROCCOQM', 1, 'FRENCH'),
  ('SWEDQM', 1, 'SLAVIC'),
  ('GENOAQM', 1, 'SPANISH'),
  ('GENOAQM', 2, 'ITALIAN'),
  ('GARCIAORTA', 1, 'ITALIAN'),
  ('GARCIAORTA', 2, 'PORTUGUESE'),
  ('GARCIAORTA', 3, 'SPANISH'),
  ('MONARDES', 1, 'SPANISH'),
  ('MONARDES', 2, 'PORTUGUESE'),
  ('WOODALL', 1, 'ENGLISH'),
  ('WOODALL', 2, 'SPANISH'),
  ('TULPSURG', 1, 'DUTCH'),
  ('TULPSURG', 2, 'FRENCH'),
  ('SABUNCU', 1, 'TURKISH'),
  ('PERSSURG', 1, 'INDIC'),
  ('HEOJUN', 1, 'KOREAN'),
  ('HEOJUN', 2, 'SPANISH'),
  ('HEOJUN', 3, 'PORTUGUESE'),
  ('LISHIZHEN', 1, 'CHINESE'),
  ('LISHIZHEN', 2, 'PORTUGUESE'),
  ('DANESURG', 1, 'NORDIC'),
  ('VENSURG', 1, 'ITALIAN'),
  ('VENSURG', 2, 'TURKISH'),
  ('MALSURG', 1, 'PORTUGUESE'),
  ('WELSER', 1, 'GERMAN'),
  ('WELSER', 2, 'NORDIC'),
  ('WELSER', 3, 'SLAVIC'),
  ('MEDICI', 1, 'SPANISH'),
  ('MEDICI', 2, 'ITALIAN'),
  ('GRESHAM', 1, 'ENGLISH'),
  ('GRESHAM', 2, 'SPANISH'),
  ('GRESHAM', 3, 'PORTUGUESE'),
  ('AMSPURSER', 1, 'DUTCH'),
  ('AMSPURSER', 2, 'FRENCH'),
  ('PORTPURSER', 1, 'PORTUGUESE'),
  ('SEVPURSER', 1, 'SPANISH'),
  ('SEVPURSER', 2, 'PORTUGUESE'),
  ('OTTPURSER', 1, 'TURKISH'),
  ('OTTPURSER', 2, 'ITALIAN'),
  ('MUGPURSER', 1, 'INDIC'),
  ('MUGPURSER', 2, 'PORTUGUESE'),
  ('MUGPURSER', 3, 'ARABIC'),
  ('SAKAIPURSER', 1, 'JAPANESE'),
  ('SAKAIPURSER', 2, 'SPANISH'),
  ('POLPURSER', 1, 'SLAVIC'),
  ('RUSPURSER', 1, 'NORDIC'),
  ('ALCANT', 1, 'PORTUGUESE'),
  ('BARROS', 1, 'SPANISH'),
  ('DIASNAV', 1, 'PORTUGUESE'),
  ('DIASNAV', 2, 'SPANISH'),
  ('FUGGER', 1, 'TURKISH'),
  ('HOLBEK', 1, 'DUTCH'),
  ('MOREAU', 1, 'FRENCH'),
  ('NPCPILOTGEN', 1, 'SPANISH'),
  ('NPCPILOTMNG', 1, 'CHINESE'),
  ('NPCPILOTOTT', 1, 'TURKISH'),
  ('NPCPILOTPRT', 1, 'PORTUGUESE'),
  ('NPCPURSERESP', 1, 'SPANISH'),
  ('NPCPURSERMUG', 1, 'INDIC'),
  ('NPCPURSERVEN', 1, 'ITALIAN'),
  ('NPCQMHAN', 1, 'NORDIC'),
  ('NPCQMJPN', 1, 'JAPANESE'),
  ('NPCQMNLD', 1, 'DUTCH'),
  ('NPCSURGENG', 1, 'ENGLISH'),
  ('NPCSURGFRA', 1, 'FRENCH'),
  ('PINZON', 1, 'SPANISH'),
  ('ZAHRA', 1, 'TURKISH'),
  ('ZAHRA', 2, 'ARABIC'),
  ('LISBOAPIL', 1, 'PORTUGUESE'),
  ('URDANETA', 1, 'SPANISH'),
  ('URDANETA', 2, 'PORTUGUESE'),
  ('URDANETA', 3, 'TURKISH'),
  ('PIGAFETTA', 1, 'ITALIAN'),
  ('DARELL', 1, 'ENGLISH'),
  ('DARELL', 2, 'SPANISH'),
  ('GIESE', 1, 'SLAVIC'),
  ('VANOS', 1, 'DUTCH'),
  ('VANOS', 2, 'FRENCH'),
  ('SCAPPI', 1, 'ITALIAN'),
  ('ESMERALDO', 1, 'PORTUGUESE'),
  ('ESMERALDO', 2, 'SPANISH'),
  ('ESMERALDO', 3, 'TURKISH'),
  ('XUCISHU', 1, 'CHINESE'),
  ('PONTAC', 1, 'FRENCH'),
  ('PONTAC', 2, 'DUTCH'),
  ('PONTAC', 3, 'SPANISH'),
  ('ROLFE', 1, 'ENGLISH'),
  ('NICOT', 1, 'FRENCH'),
  ('NICOT', 2, 'SPANISH'),
  ('MALIKGOPI', 1, 'INDIC'),
  ('GRACIANASI', 1, 'TURKISH'),
  ('GRACIANASI', 2, 'ITALIAN'),
  ('GRACIANASI', 3, 'SPANISH'),
  ('MANASE', 1, 'JAPANESE'),
  ('DACOSTA', 1, 'PORTUGUESE'),
  ('DACOSTA', 2, 'INDIC'),
  ('ASSEZAT', 1, 'FRENCH'),
  ('PELSAERT', 1, 'DUTCH'),
  ('PELSAERT', 2, 'FRENCH'),
  ('KHWAJANAZAR', 1, 'PERSIAN'),
  ('CRANFIELD', 1, 'ENGLISH'),
  ('CRANFIELD', 2, 'SPANISH'),
  ('CRANFIELD', 3, 'PORTUGUESE'),
  ('KAMIYA', 1, 'JAPANESE'),
  ('THURZO', 1, 'SLAVIC'),
  ('THURZO', 2, 'NORDIC'),
  ('DECOUTRE', 1, 'SPANISH'),
  ('MIRJUMLA', 1, 'INDIC'),
  ('MIRJUMLA', 2, 'PORTUGUESE'),
  ('MIRJUMLA', 3, 'SPANISH'),
  ('BALLARIN', 1, 'ITALIAN'),
  ('LIDAN', 1, 'CHINESE'),
  ('LIDAN', 2, 'PORTUGUESE'),
  ('TRIP', 1, 'DUTCH'),
  ('AYALA', 1, 'SPANISH'),
  ('AYALA', 2, 'PORTUGUESE'),
  ('TANEGASHIMA', 1, 'JAPANESE'),
  ('DEGEER', 1, 'NORDIC'),
  ('DEGEER', 2, 'GERMAN'),
  ('VALKENDORF', 1, 'NORDIC'),
  ('BOSOY', 1, 'SLAVIC'),
  ('BOSOY', 2, 'NORDIC'),
  ('UYLENBURGH', 1, 'DUTCH'),
  ('NIJS', 1, 'ITALIAN'),
  ('NIJS', 2, 'TURKISH'),
  ('NIJS', 3, 'SPANISH'),
  ('YUXIANGDOU', 1, 'CHINESE'),
  ('PLANTIN', 1, 'SPANISH'),
  ('PLANTIN', 2, 'FRENCH'),
  ('OXE', 1, 'NORDIC'),
  ('GHULAMHUSAYN', 1, 'PERSIAN'),
  ('GHULAMHUSAYN', 2, 'TURKISH'),
  ('TARTAGLIA', 1, 'ITALIAN'),
  ('YIJANGSON', 1, 'KOREAN'),
  ('YIJANGSON', 2, 'SPANISH'),
  ('MURAKAMI', 1, 'JAPANESE'),
  ('TURGUT', 1, 'TURKISH'),
  ('TURGUT', 2, 'ARABIC'),
  ('TURGUT', 3, 'SPANISH')
       ) w(code, ord, language)
  join public.officers o on o.code = w.code;

-- ── 5. THE RE-CUTS ────────────────────────────────────────────────────────────────────────────
do $recut$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0156 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0156 where fn = d.fn order by n loop
      if pg_temp.occurs_0156(v_def, h.old) <> 1 then
        raise exception '0156 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against',
          h.n, d.fn, pg_temp.occurs_0156(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $recut$;

-- ── 6. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  b        record;
  d        record;
  h        record;
  v_p      record;
  v_def    text;
  v_n      int;
  v_bad    int;
  v_shift  int;
  v_new    jsonb;
  v_old    jsonb;
  v_card   text[] := array['grade', 'grade_ord', 'slots', 'known', 'job', 'job_word', 'focus', 'focus_word', 'traits', 'languages', 'speaks'];
  v_placed int;
  v_avg    numeric;
  v_max    int;
  v_inn_ms numeric;
  v_off_ms numeric;
  t0       timestamptz;
  v_grades text;
begin
  select * into b from before_0156;
  v_shift := b.shift;

  -- (a) THE CATALOGUE AND THE ROSTER, counted against the data's own sizes (pasted by the generator)
  if (select count(*) from public.officers) <> b.officers + 42 or (select count(*) from public.officers) <> 105 then
    raise exception '0156 self-assert FAIL: % captains, expected % (% of today + % new)',
      (select count(*) from public.officers), 105, b.officers, 42;
  end if;
  if (select md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s|%s', o.code, o.name, o.specialty, o.bonus_pct, o.wage_ducats,
                                   o.nation_id, o.home_port_id, o.blurb), '/' order by o.code))
        from public.officers o join old_officers_0156 x on x.id = o.id) <> b.roster_hash then
    raise exception '0156 self-assert FAIL: a captain of today moved';
  end if;
  if (select count(*) from public.traits) <> 25 or (select count(*) from public.crew_effects) <> 11
     or (select count(*) from public.languages) <> 20 or (select count(*) from public.captain_grades) <> 4
     or (select count(*) from public.trait_effects) <> 27 then
    raise exception '0156 self-assert FAIL: the catalogue did not land whole';
  end if;
  if exists (select 1 from public.officers o where not exists (select 1 from public.captain_profile cp where cp.officer_id = o.id)) then
    raise exception '0156 self-assert FAIL: a captain has no card';
  end if;
  -- the mirror (§2): specialty = job = ord 1, bonus_pct = ord 1's value
  select count(*) into v_bad
    from public.officers o
    join public.captain_profile cp on cp.officer_id = o.id
    left join public.captain_traits ct on ct.officer_id = o.id and ct.ord = 1
   where ct.trait is distinct from o.specialty or cp.job_trait <> o.specialty or ct.base_pct is distinct from o.bonus_pct;
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % captain(s) whose job, first trait and specialty / value disagree', v_bad;
  end if;
  -- every grade by D10's floors; the 63 of today fall 18 / 17 / 20 / 8
  select count(*) into v_bad from public.officers o join public.captain_profile cp on cp.officer_id = o.id
   where cp.grade <> (select g.code from public.captain_grades g where g.floor_pct <= o.bonus_pct order by g.ord desc limit 1);
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % captain(s) graded off the floors', v_bad;
  end if;
  select string_agg(format('%s %s', g, n), ' / ' order by g) into v_grades
    from (select cp.grade as g, count(*) as n from public.captain_profile cp join old_officers_0156 x on x.id = cp.officer_id group by 1) z;
  if v_grades <> 'A 20 / B 17 / C 18 / S 8' then
    raise exception '0156 self-assert FAIL: the captains of today grade as % (D10 says A 20 / B 17 / C 18 / S 8)', v_grades;
  end if;
  -- every kit is ten distinct traits; the extras at the kit's share of the job value
  select count(*) into v_bad from public.officers o
   where (select count(*) from public.captain_traits ct where ct.officer_id = o.id) <> 10
      or exists (select 1 from public.captain_traits ct where ct.officer_id = o.id and ct.ord > 1
                    and ct.base_pct <> round(o.bonus_pct * 60 / 100.0, 1));
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % kit(s) are not ten traits at the job value and % %%', v_bad, 60;
  end if;
  -- every job held by two or more, one C/B and one A/S; every focus a captain of every grade
  select count(*) into v_bad from public.traits t
   where (select count(*) from public.captain_profile cp where cp.job_trait = t.code) < 2
      or not exists (select 1 from public.captain_profile cp where cp.job_trait = t.code and cp.grade in ('C', 'B'))
      or not exists (select 1 from public.captain_profile cp where cp.job_trait = t.code and cp.grade in ('A', 'S'));
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % job(s) without a lesser and a greater captain (D15)', v_bad;
  end if;
  select count(*) into v_bad from public.trait_foci f cross join public.captain_grades g
   where not exists (select 1 from public.captain_profile cp join public.traits t on t.code = cp.job_trait
                      where t.focus = f.code and cp.grade = g.code);
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % focus × grade pair(s) with no captain', v_bad;
  end if;
  -- languages: every harbour one, every language somewhere, every captain her home's first
  if exists (select 1 from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.port_language pl where pl.port_id = p.id))
     or exists (select 1 from public.port_language pl join public.ports p on p.id = pl.port_id where p.kind <> 'HARBOUR')
     or exists (select 1 from public.languages l where not exists (select 1 from public.port_language pl where pl.language = l.code)) then
    raise exception '0156 self-assert FAIL: a harbour without a language, a sea point with one, or a language nobody speaks';
  end if;
  select count(*) into v_bad from public.officers o
   where (select cl.language from public.captain_languages cl where cl.officer_id = o.id and cl.ord = 1)
         is distinct from (select pl.language from public.port_language pl where pl.port_id = o.home_port_id)
      or (select count(*) from public.captain_languages cl where cl.officer_id = o.id)
         <> 1 + (select case cp.grade when 'A' then 1 when 'S' then 2 else 0 end from public.captain_profile cp where cp.officer_id = o.id);
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % captain(s) do not speak their home''s language first, or speak the wrong number (D14)', v_bad;
  end if;

  -- (b) DARK: what every company's captains are worth, and who is in which room
  select count(*) into v_bad from bonus_before_0156 x
   where public.fleet_officer_bonus(x.fleet_id, x.sp) is distinct from x.v;
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % fleet × job officer bonus(es) MOVED — K4 is dark', v_bad;
  end if;
  if (select count(*) from bonus_before_0156) < 4 then
    raise exception '0156 self-assert FAIL: the bonus pre-image is empty — the claim proves nothing';
  end if;
  select count(*) into v_bad from rooms_before_0156 r
   where world.inn_present(r.officer_id, r.port_id, v_shift) is distinct from r.here;
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % captain × harbour room(s) changed for a captain of today', v_bad;
  end if;

  -- (c) THE READS: the 63 exactly as before, plus the card; the cap and specialties_read unmoved
  for h in select * from inn_before_0156 loop
    v_new := world.inn(h.port_id);
    if (v_new - 'present') <> (h.j - 'present') then
      raise exception '0156 self-assert FAIL: world.inn''s frame moved at %', h.port_id;
    end if;
    -- 2026-10-18 (self-assert only): world.inn orders its room by (specialty, name), and two PURSERs
    -- share a name (MUGPURSER 0073, NPCPURSERMUG 0098: Virji Vora), so their relative order is the
    -- plan's, not the read's — it flipped in a from-zero world (nightly, 2026-10-17). Both sides are
    -- compared in one canonical order (specialty, name, code), as 0166 later does with canon_0166, and
    -- the read's own order is asserted to be (specialty, name) — the order its body states.
    select coalesce(jsonb_agg(g - v_card order by g->>'specialty', g->>'name', g->>'code'), '[]'::jsonb) into v_old
      from jsonb_array_elements(v_new->'present') g
     where g->>'code' in (select code from old_officers_0156);
    if v_old <> (select coalesce(jsonb_agg(g order by g->>'specialty', g->>'name', g->>'code'), '[]'::jsonb)
                   from jsonb_array_elements(h.j->'present') g) then
      raise exception '0156 self-assert FAIL: world.inn at % serves the captains of today differently: % vs %', h.port_id, v_old, h.j->'present';
    end if;
    if exists (select 1
                 from jsonb_array_elements(v_new->'present') with ordinality x(g, o)
                 join jsonb_array_elements(v_new->'present') with ordinality y(g2, o2) on o2 = o + 1
                where (g->>'specialty', g->>'name') > (g2->>'specialty', g2->>'name')) then
      raise exception '0156 self-assert FAIL: world.inn at % does not seat its room by job and name', h.port_id;
    end if;
    if exists (select 1 from jsonb_array_elements(v_new->'present') g where not (g ?& v_card)) then
      raise exception '0156 self-assert FAIL: a guest at % has no card', h.port_id;
    end if;
  end loop;
  select world.officers() into v_new;
  select j into v_old from officers_before_0156;
  if (v_new - 'officers') <> (v_old - 'officers') then
    raise exception '0156 self-assert FAIL: world.officers'' cap or specialties_read moved: % vs %', v_new - 'officers', v_old - 'officers';
  end if;
  if (select coalesce(jsonb_agg(g - v_card order by o), '[]'::jsonb)
        from jsonb_array_elements(v_new->'officers') with ordinality x(g, o)
       where g->>'code' in (select code from old_officers_0156)) <> v_old->'officers' then
    raise exception '0156 self-assert FAIL: world.officers serves the captains of today differently';
  end if;
  if jsonb_array_length(v_new->'officers') <> 105 then
    raise exception '0156 self-assert FAIL: the Codex lists % captains, expected %', jsonb_array_length(v_new->'officers'), 105;
  end if;
  -- the card is the tables' own: grade, job, the known count, the job first and in use only if live
  select count(*) into v_bad
    from jsonb_array_elements(v_new->'officers') g
    join public.officers o on o.code = g->>'code'
    join public.captain_profile cp on cp.officer_id = o.id
    join public.captain_grades cg on cg.code = cp.grade
   where g->>'grade' <> cp.grade or g->>'job' <> cp.job_trait
      or jsonb_array_length(g->'traits') <> cg.known
      or g->'traits'->0->>'code' <> cp.job_trait
      or (g->'traits'->0->>'in_use')::boolean <> (cp.job_trait in ('NAVIGATOR', 'QUARTERMASTER', 'PURSER', 'SURGEON'))
      or (g->>'takes_effect')::boolean <> (g->'traits'->0->>'in_use')::boolean
      or exists (select 1 from jsonb_array_elements(g->'traits') with ordinality t(x, n) where n > 1 and (x->>'in_use')::boolean)
      or exists (select 1 from jsonb_array_elements(g->'traits') t(x) where not (x->>'in_use')::boolean and x->>'note' is null)
      or g->>'speaks' not like 'Speaks %'
      or exists (select 1 from jsonb_array_elements(g->'traits') t(x), jsonb_array_elements_text(x->'lines') l(s)
                  where s like '%{%' or s not like '%' || trim_scale(round((x->>'pct')::numeric, 1))::text || '%');
  if v_bad <> 0 then
    raise exception '0156 self-assert FAIL: % Codex card(s) disagree with the tables', v_bad;
  end if;

  -- (d) EVERY NEW CAPTAIN IS IN SOME INN WITHIN 24 HOURS (96 quarter hours, derived)
  select count(*) into v_placed from public.officers o
   where o.id not in (select id from old_officers_0156)
     and exists (select 1 from generate_series(0, 95) s(k)
                   join public.port_buildings pb on pb.kind = 'inn'
                  where world.inn_present(o.id, pb.port_id, v_shift + s.k));
  if v_placed <> 42 then
    raise exception '0156 self-assert FAIL: only % of % new captains are in any inn within 24 hours', v_placed, 42;
  end if;
  select avg(c)::numeric(6,2), max(c) into v_avg, v_max
    from (select pb.port_id, count(*) filter (where world.inn_present(o.id, pb.port_id, v_shift)) c
            from public.port_buildings pb cross join public.officers o where pb.kind = 'inn' group by pb.port_id) x;

  -- (e) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0156 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0156 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0156(v_def, h.new) <> 1 then
        raise exception '0156 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0156 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0156 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0156 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0156 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0156 self-assert FAIL: the client entry points moved (% → %)', b.entry_points, (select count(*) from public.client_rpc_entry_points());
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
               cross join unnest(array['public.trait_foci', 'public.captain_grades', 'public.crew_effects', 'public.traits',
                                       'public.trait_effects', 'public.languages', 'public.port_language', 'public.captain_profile',
                                       'public.captain_traits', 'public.captain_languages']) t(tab)
              where has_table_privilege(r.role, t.tab, 'select,insert,update,delete'))
     or exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
                 where has_function_privilege(r.role, 'world.captain_card(uuid)', 'execute')) then
    raise exception '0156 self-assert FAIL: a client can read or write a captains table, or call the card builder directly';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0156 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;

  -- (f) TIMING — notice only (prod's CPU is burstable)
  t0 := clock_timestamp();
  perform world.inn(port_id) from inn_before_0156;
  v_inn_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp();
  perform world.officers();
  v_off_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice '0156 timing: world.inn over 60 harbours % → % ms; world.officers % → % ms',
    round((select inn_ms from time_before_0156)), round(v_inn_ms), round((select officers_ms from time_before_0156)), round(v_off_ms);

  raise notice '0156 self-assert ok: A CAPTAIN HAS A GRADE, A KIT AND A TONGUE (K4, DARK). % captains (% of today, column for column unmoved, + % new so every one of the % jobs has a lesser and a greater captain), graded by D10''s floors — today''s fall %; every kit ten traits, the job first at her value and the rest at % %%; % languages, one per harbour (all % harbours) and her home''s first for every captain. The job is still read only through officers.specialty / bonus_pct (the mirror holds for all %): every fleet × the four live jobs answers its pre-image, every captain of today is in exactly the rooms she was in, and world.inn (60 harbours) and world.officers serve the captains of today key for key as before plus the card. Every new captain is in some inn within 24 hours; the average inn holds % and the fullest %. The two re-cuts reverse to their pre-images; no new entry point; 0 client write grants.',
    105, b.officers, 42, 25, v_grades, 60, 20,
    (select count(*) from public.port_language), 105, v_avg, v_max;
end $$;
