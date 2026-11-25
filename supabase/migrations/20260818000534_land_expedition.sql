-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0534 - LAND EXPEDITION  (dark: land_expedition_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "you will take provisions and crews. Create a expedition with captains. How many crews you can assemble depends on
--   your combat level. The more crew you have, the more provision you can carry -> the more dungeon raids, mining, woodcutting etc. can be done."
--   docs/design/captains-land-2026-11-25.md section 6; docs/design/rounds-2026-11-25.md; docs/dev-log/2026-11-25-captain-works.md.
--   (The design's slice 0531: numbered 0534 because it stands on 0532 and 0533.)
--
-- THE WIDENING OF 0518 (a run belongs to a WORKER, a fleet or a land party):
--   public.round_runs    party_id (NEW, land_parties, unique, cascade); fleet_id and sea_id may be null; a check: exactly one of fleet and party, and a fleet's
--                        run has its sea. The primary key is worker (NEW, generated: the fleet, or the party). fleet_id keeps a unique constraint, so
--                        every `on conflict (fleet_id)` and every `where fleet_id =` of 0518 to 0524 is as it was; NO BODY of theirs is cut for it.
--   public.round_works   kind may be `land`; two land works, whose lit_by is a knob that is never true: no fleet can be sent on one, none is listed.
-- THE EXPEDITION (lit: land_expedition_enabled, and rounds, captains' works and the land):
--   land_expedition_terms    what a Send freezes and costs; land_expedition_stop: the stop rule as arithmetic on it (MIN or her number, provisions, load,
--                            the 12 h away cap); land_expedition_round: round n, pure in the terms; land_expedition_card: what a screen may show (no odds).
--   land_expedition_send_for, _home_for, _settle (the one writer), _settle_due (public.round_settle_due calls it: the jobs' tick, 1 hunk; never the beat).
--   land_expedition_party    a captain's party on expeditions: numbers 2 and up, one a captain; party 1 stays the dig's, with its exact terms.
--   land_party_out           the one reading of a party that is out (six hunks: the seat's, the dismissal's, the upgrade's and the card's checks).
--   crew_hire_cost_at        public.crew_hire_cost's lines, moved there whole (1 hunk): a party hires at the price a fleet does, from the same pool.
--   cmd.land_expedition(code, ask), world.land_expedition(code, ask): the door and the read (registry, 1 hunk).
-- COIN: the hands, the provisions and a day's pay a man for each day begun go to the harbour she lives in (HIRE, PROVISION, WAGES). A raid's gold is her
--   country's capital's (VOYAGE_REWARD by public.capital_pays; none while the purses are dark, none when it cannot pay). Nothing is minted.
-- NOT HERE: woodcutting (no job of the land gathers wood yet), artifacts (0524), weapons carried.
-- ROWS: 2 works, 1 Reputation kind, 6 config rows. Lit: one run row a party, kept; a press 3 to 6 rows; home 4 to 9 once. 0 rows a minute idle.
-- budget: no cron job, no autovacuum or fillfactor change, no new table; two columns on land_parties, two on round_runs.
-- LOCKS: ALTER round_runs, round_works, land_parties (ACCESS EXCLUSIVE for an instant, small tables); CREATE OR REPLACE x8 by hunks.
-- ROLLBACK (forward, owner only): land_expedition_enabled false: no Send; one that is out is settled by its own time.
-- SELF-ASSERT: hunks once and reversing; no other function or knob moved; then a probe company, rolled back, on a job of the data and a foe of its own:
--   the widened table refuses a run of both, of neither, and two of one worker, and 0518's own upsert still works; the hire price is what it was; dark
--   refused; the bill is what leaves the purse; the stop by food, crew, load, her number and the cap; booked in one go as in nine; home: goods,
--   experience, badges, hands; nobody is moved while out; a repeat goes again. The market, the dice and other companies are asked nothing.
-- VERSION: 0534.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.crew_hire_cost(uuid,integer)', 'public.round_settle_due(timestamp with time zone,integer)', 'public.seat_captain_for(uuid,text,uuid,integer)', 'public.captain_land_for(uuid,text,integer)', 'public.captain_dismiss_for(uuid,text)', 'public.captain_upgrade_for(uuid,text,text)', 'world.captains()', 'public.client_rpc_entry_points()']::text[];
  c_new    constant text[] := array['public.land_expedition_on()', 'public.crew_hire_cost_at(uuid,uuid,integer)', 'public.land_party_out(uuid)', 'public.land_expedition_round(jsonb,integer)', 'public.land_expedition_stop(jsonb)', 'public.land_expedition_terms(uuid,uuid,jsonb,uuid)', 'public.land_expedition_card(jsonb)', 'public.land_expedition_party(uuid,uuid)', 'public.land_expedition_send_for(uuid,text,jsonb,timestamp with time zone)', 'public.land_expedition_settle(uuid,timestamp with time zone)', 'public.land_expedition_settle_due(timestamp with time zone,integer)', 'public.land_expedition_home_for(uuid,text,timestamp with time zone)', 'cmd.land_expedition(text,jsonb)', 'world.land_expedition(text,jsonb)']::text[];
  c_doors  constant text[] := array['cmd.land_expedition(text,jsonb)', 'world.land_expedition(text,jsonb)']::text[];
  c_knobs  constant text[] := array['land_expedition_enabled', 'land_works_are_no_fleets', 'land_crew_carry', 'land_round_stores', 'land_round_stores_crew', 'land_raid_march_s']::text[];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_me uuid; v_fl uuid; v_po uuid; v_code text; v_act text; v_pt uuid; v_pa uuid; v_t jsonb; v_r jsonb; v_bad int := 0; v_at timestamptz := now(); v_home timestamptz; v_h0 jsonb;
  r1 public.round_runs%rowtype; i int; v_sea uuid;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0534 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regclass('public.round_runs') is null or to_regprocedure('public.land_raid_terms(uuid,text,integer,uuid,uuid)') is null then
    raise exception '0534 refuses: a body it cuts or a reading it asks is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE TABLES ──
  alter table public.land_parties add column crew int not null default 0 check (crew >= 0), add column stores_t numeric not null default 0 check (stores_t >= 0);
  comment on column public.land_parties.crew is '0534: the hands with an expedition''s party, out or home.';
  comment on column public.land_parties.stores_t is '0534: the provisions with it, in tons.';
  alter table public.round_works drop constraint round_works_kind_check, add constraint round_works_kind_check check (kind in ('combat', 'sea', 'land'));
  alter table public.round_runs drop constraint round_runs_pkey;
  alter table public.round_runs alter column fleet_id drop not null, alter column sea_id drop not null;
  alter table public.round_runs add column party_id uuid references public.land_parties(id) on delete cascade;
  alter table public.round_runs add column worker uuid generated always as (coalesce(fleet_id, party_id)) stored;
  alter table public.round_runs add constraint round_runs_pkey primary key (worker),
    add constraint round_runs_one_a_fleet unique (fleet_id), add constraint round_runs_one_a_party unique (party_id),
    add constraint round_runs_a_worker check ((fleet_id is null) <> (party_id is null) and (fleet_id is null or sea_id is not null));
  comment on column public.round_runs.worker is '0534: whose run it is: the fleet, or the land party.';
  insert into public.round_works (code, ord, kind, word, skill, level, seconds, food_days, water_days, crew_pct, lit_by) values
    ('land_gather', 90, 'land', 'Gathering', 'mining', 1, 600, 0, 0, 0.1, 'land_works_are_no_fleets'),
    ('land_raid',   91, 'land', 'Raid',      'combat', 1, 600, 0, 0, 0,   'land_works_are_no_fleets');
  insert into public.reputation_kinds (code, sign, capped, word) values ('land', 1, true, 'Land expedition');

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('land_expedition_enabled', 'false'::jsonb, '0534: THE SWITCH (the owner''s). true (with rounds_enabled, captain_works_enabled, land_enabled): a captain may be sent on a land expedition with crew and provisions. false: no Send; one that is out comes home by its own stop.'),
    ('land_works_are_no_fleets', 'false'::jsonb, '0534: never true: the land works of public.round_works wait for it, so no fleet is sent on one and none is listed for a fleet.'),
    ('land_crew_carry', '1'::jsonb, '0534: tons one hand of a land expedition carries (provisions out, the load home).'),
    ('land_round_stores', '0.3'::jsonb, '0534: tons of provisions a round of a land expedition eats, whatever its crew.'),
    ('land_round_stores_crew', '0.01'::jsonb, '0534: tons of provisions a round eats for each of its crew.'),
    ('land_raid_march_s', '900'::jsonb, '0534: seconds a land expedition marches to a raid, and back.');

  -- ── 4. THE RULES ──

  execute $f$
create function public.land_expedition_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0534: THE SWITCH, and what a land expedition stands on: the rounds (0518), the captains' works (0527), the land (0455).
  select public.wc('land_expedition_enabled') = 'true'::jsonb and public.rounds_on() and public.captain_works_on() and public.land_on()
$body$
  $f$;

  execute $f$
create function public.crew_hire_cost_at(p_player uuid, p_port uuid, p_count int)
returns jsonb language plpgsql stable set search_path = public, pg_temp
as $body$
-- 0534: WHAT HIRING n HANDS COSTS A COMPANY AT A HARBOUR: public.crew_hire_cost's own lines (0154), moved here whole: it calls this for a fleet
-- where she lies, a land party asks it of the harbour it lives in. {normal, urgent, cost}.
declare
  v_count int := p_count;
  v_pool  int;
  v_rate  numeric := public.wc_num('hire_crew_rate');
  v_norm  int;
  v_urg   int;
  v_cost  bigint;
  v_pct   numeric := 0;
begin
  select crew_pool into v_pool from public.ports where id = p_port;
  v_norm := least(v_count, case when exists (select 1 from public.players p where p.id = p_player and p.is_npc)
                                then greatest(0, v_pool - public.wc_int('npc_crew_pool_floor'))
                                else v_pool end);
  v_urg  := v_count - v_norm;
  if public.skills_bite_on() then
    v_pct := world.skill_pct(p_player, null, 'crew_hire');
  end if;
  if v_pct = 0 then
    v_cost := round(v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))::bigint;
  else
    v_cost := round((v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))
                    * (1 - least(v_pct, 100) / 100.0))::bigint;
  end if;
  return jsonb_build_object('normal', v_norm, 'urgent', v_urg, 'cost', v_cost);
end
$body$
  $f$;

  execute $f$
create function public.land_party_out(p_party uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0534: THE ONE READING of "is that land party out": on a job of the land's, or on an expedition.
  select exists (select 1 from public.land_parties lp where lp.id = p_party and lp.action is not null)
         or exists (select 1 from public.round_runs r where r.party_id = p_party and r.state = 'out')
$body$
  $f$;

  execute $f$
create function public.land_expedition_round(p_terms jsonb, p_n int)
returns table (hands int, xp int, gold int, rp int, units int, fed boolean, result int)
language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0534: ROUND n of an expedition sent on p_terms. A raid: public.land_raid_round (0532). Gathering: the hands by the running fraction of the terms'
  -- loss, the units, the experience. fed: this round ate nothing of the stores (one in terms.forage). Pure in (terms, n): the dice are the Send's.
  select coalesce(r.hands, (floor(z.c * p_n) - floor(z.c * (p_n - 1)))::int), coalesce(r.xp, (p_terms->>'xp')::int), coalesce(r.gold, 0), coalesce(r.rp, (p_terms->>'rp')::int),
         coalesce((p_terms->>'units')::int, 0), coalesce(mod(p_n, (p_terms->>'forage')::int) = 0, false), coalesce(r.result, 1)
    from (select coalesce((p_terms->>'loss')::numeric, 0) as c) z
    left join lateral public.land_raid_round(p_terms->'raid', (p_terms->>'seed')::uuid, p_n) r on p_terms ? 'raid'
$body$
  $f$;

  execute $f$
create function public.land_expedition_stop(p_terms jsonb)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
as $body$
-- 0534: THE STOP RULE, ARITHMETIC ON THE FROZEN TERMS: the last round after which the hands are at MIN or above, the stores had the round's food and
-- the load is carried; her own number; the away cap. {most, why, hands, left}. So a late settle and a prompt one are one answer.
declare
  v_cap   int := greatest(0, floor((public.wc_num('land_away_hours') * 3600 - 2 * (p_terms->>'lead')::numeric) / (p_terms->>'seconds')::numeric))::int;
  v_crew  int := (p_terms->>'crew')::int;
  v_food  numeric := (p_terms->>'stores')::numeric;
  v_use   numeric := (p_terms->>'use')::numeric;
  v_load  numeric := 0;
  v_bulk  numeric := coalesce((p_terms->>'bulk')::numeric, 0);
  v_want  int := (p_terms #>> '{stop,rounds}')::int;
  n       int := 0;
  r       record;
  v_why   text;
begin
  loop
    if n >= v_cap then v_why := 'cap'; exit; end if;
    if n >= v_want then v_why := 'rounds'; exit; end if;
    select * into r from public.land_expedition_round(p_terms, n + 1);
    if not r.fed and v_food < v_use then v_why := 'food'; exit; end if;
    if v_crew - r.hands < (p_terms->>'min')::int then v_why := 'crew'; exit; end if;
    if v_load + r.units * v_bulk > greatest(0, (p_terms->>'carry')::numeric - (v_food - case when r.fed then 0 else v_use end)) then v_why := 'load'; exit; end if;
    v_food := v_food - case when r.fed then 0 else v_use end;
    v_crew := v_crew - r.hands;
    v_load := v_load + r.units * v_bulk;
    n := n + 1;
  end loop;
  return jsonb_build_object('most', n, 'why', v_why, 'hands', (p_terms->>'crew')::int - v_crew, 'left', round(v_food, 3));
end
$body$
  $f$;

  execute $f$
create function public.land_expedition_terms(p_player uuid, p_signing uuid, p_ask jsonb, p_seed uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
as $body$
-- 0534: WHAT A SEND WOULD FREEZE AND COST for a captain of hers: p_ask {work: land_gather | land_raid, target (a mining job | a foe), crew, stores (tons; none: all
-- they carry on a raid, half on a gathering), stop {crew, rounds}, then: home | repeat}. Every figure an authority's: the level's perk (captain_work_perk), the job's turn and march
-- (land_terms), the fight (land_raid_terms), the hands' and the stores' price (crew_hire_cost_at, stores_cost). short: the refusal a Send would meet.
-- The public part is public.land_expedition_card's. Writes nothing.
declare
  v_work  text := p_ask->>'work';
  v_tgt   text := p_ask->>'target';
  v_crew  int;
  lp      public.land_parties%rowtype;
  v_port  uuid;
  v_perk  jsonb;
  j       jsonb;
  v_r     jsonb;
  v_t     jsonb;
  w       public.round_works%rowtype;
  v_carry numeric;
  v_st    numeric;
  v_hire  jsonb;
  v_new   int;
  v_secs  int;
  v_a     numeric;
  v_s     jsonb;
  v_cap   int;
begin
  if not public.land_expedition_on() then
    return jsonb_build_object('short', cmd.refusal('E_NOT_IN_USE', 'land expeditions are not open yet'));
  end if;
  select * into w from public.round_works x where x.code = v_work and x.kind = 'land';
  if w.code is null then
    return jsonb_build_object('short', cmd.refusal('E_NO_SUCH_JOB', 'there is no such expedition'));
  end if;
  v_crew := (p_ask->>'crew')::int;
  v_cap := public.land_raid_crew_cap(p_player);
  if coalesce(v_crew, 0) < 1 then
    return jsonb_build_object('short', cmd.refusal('E_CREW_SHORT', 'an expedition needs hands', cmd.figures(0, 1, 'crew')));
  elsif v_crew > v_cap then
    return jsonb_build_object('short', cmd.refusal('E_AT_CAPACITY', format('Crew %s / %s', v_crew, v_cap)));
  end if;
  select lpx.* into lp from public.captain_seats cs join public.land_parties lpx on lpx.id = cs.party_id where cs.player_officer_id = p_signing and lpx.ord > 1;
  v_port := coalesce(lp.port_id, public.home_port_of(p_player));
  if v_port is null then
    return jsonb_build_object('short', cmd.refusal('E_NO_HOUSE', 'a company with no home city has no party'));
  end if;
  v_perk := public.captain_work_perk(p_signing, case when v_work = 'land_raid' then 'arms' else 'mining' end);
  v_t := jsonb_build_object('work', v_work, 'target', v_tgt, 'crew', v_crew, 'cap', v_cap, 'level', v_perk->'level', 'forage', v_perk->'forage', 'seed', p_seed,
                            'min', greatest(1, coalesce((p_ask #>> '{stop,crew}')::int, 1)), 'stop', coalesce(p_ask->'stop', '{}'::jsonb),
                            'then', case when p_ask->>'then' = 'repeat' then 'repeat' else 'home' end);
  if v_work = 'land_raid' then
    v_r := public.land_raid_terms(p_player, v_tgt, v_crew, p_signing, p_seed);
    if v_r ? 'short' then
      return jsonb_build_object('short', v_r->'short');
    end if;
    v_secs := round(w.seconds * (1 - (v_perk->>'time_pct')::numeric / 100));
    v_t := v_t || jsonb_build_object('raid', v_r, 'word', v_r->'word', 'lead', public.wc_int('land_raid_march_s'), 'rp', v_r->'rp', 'xp', v_r->'xp',
                                     'cost', public.land_raid_card(v_r)->'cost');
  else
    j := public.land_terms(p_player, v_tgt);
    if j is null or j->>'skill' <> 'mining' or j ? 'make' then
      return jsonb_build_object('short', cmd.refusal('E_NO_SUCH_JOB', 'there is no such place to gather'));
    elsif jsonb_typeof(j->'short') = 'object' then
      return jsonb_build_object('short', j->'short');
    end if;
    -- one turn of the job's own, at the company's level, less the captain's; a round is as many whole turns as fit in it, one at the least
    v_a := greatest(1, round((j->>'a')::numeric * (1 - case when j ? 'captain' then 0 else (v_perk->>'time_pct')::numeric end / 100)));
    v_secs := greatest(w.seconds, v_a)::int;
    v_t := v_t || jsonb_build_object('good', j->'good', 'word', (select g.name from public.goods g where g.id = (j->>'good')::uuid),
                                     'bulk', (select g.bulk from public.goods g where g.id = (j->>'good')::uuid), 'units', floor(v_secs / v_a)::int,
                                     'lead', (j->>'s')::int + (j->>'m')::int, 'xp', floor(v_secs / v_a)::int * (j->>'xp')::int, 'rp', 0,
                                     'loss', round(v_crew * w.crew_pct / 100 * (1 - (v_perk->>'crew_pct')::numeric / 100), 4));
    v_t := v_t || jsonb_build_object('cost', jsonb_build_object('hands', round((v_t->>'loss')::numeric, 2)));
  end if;
  -- what they carry, and what they eat
  v_carry := round(v_crew * public.wc_num('land_crew_carry') * (1 + coalesce((v_perk->>'carry_pct')::numeric, 0) / 100), 2);
  v_st := least(v_carry, greatest(0, coalesce((p_ask->>'stores')::numeric, case when v_work = 'land_raid' then v_carry else round(v_carry / 2, 2) end)));   -- gathering: half of it is room for the load
  v_t := v_t || jsonb_build_object('seconds', v_secs, 'carry', v_carry, 'stores', v_st, 'use', round(public.wc_num('land_round_stores') + public.wc_num('land_round_stores_crew') * v_crew, 3));
  v_s := public.land_expedition_stop(v_t);
  v_t := v_t || v_s;
  if (v_s->>'most')::int < 1 then
    return jsonb_build_object('short', cmd.refusal('E_ROUND_SHORT', case v_s->>'why' when 'food' then 'not enough food for one round' when 'crew' then 'not enough crew above the least for one round'
                                                                                      when 'load' then 'they cannot carry one round''s load' else 'no round to do' end));
  end if;
  -- the bill: the hands she lacks, the stores they lack, a day's pay a man for every day begun
  v_new := greatest(0, v_crew - coalesce(lp.crew, 0));
  v_hire := public.crew_hire_cost_at(p_player, v_port, v_new);
  if v_new > 0 and (v_hire->>'normal')::int <= 0 and (v_hire->>'urgent')::int = v_new and coalesce((select p.crew_pool from public.ports p where p.id = v_port), 0) <= 0 then
    return jsonb_build_object('short', cmd.refusal('E_CREW_POOL', 'no crew to be had in this port', cmd.figures(0, v_new, 'crew')));
  end if;
  v_t := v_t || jsonb_build_object('port', v_port, 'hire', v_new, 'bill', jsonb_build_object(
           'hire', case when v_new > 0 then (v_hire->>'cost')::bigint else 0 end, 'normal', v_hire->'normal',
           'stores', public.stores_cost(p_player, greatest(0, v_st - coalesce(lp.stores_t, 0)) / 2, greatest(0, v_st - coalesce(lp.stores_t, 0)) / 2),
           'wages', round(v_crew * public.wc_num('wage_per_crew_day') * ceil((2 * (v_t->>'lead')::numeric + (v_s->>'most')::int * v_secs) / 86400))::bigint));
  return v_t || jsonb_build_object('total', (v_t #>> '{bill,hire}')::bigint + (v_t #>> '{bill,stores}')::bigint + (v_t #>> '{bill,wages}')::bigint);
end
$body$
  $f$;

  execute $f$
create function public.land_expedition_card(p_terms jsonb)
returns jsonb language sql immutable set search_path = public, pg_temp
as $body$
  -- 0534: what a screen may show of the terms: no seed, no result, no chance.
  select case when p_terms ? 'short' then p_terms else p_terms - 'seed' - 'raid' - 'port' - 'good' - 'loss' - 'hands' end
$body$
  $f$;

  execute $f$
create function public.land_expedition_party(p_player uuid, p_signing uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0534: the party a captain leads on expeditions: hers, else one of the company's that nobody leads and that is home, else a new one (its number above
-- the dig's, 1). One a captain, so a company has no more than its captains. She takes its seat (public.captain_land_put).
declare
  v_id uuid;
begin
  select lp.id into v_id from public.captain_seats cs join public.land_parties lp on lp.id = cs.party_id where cs.player_officer_id = p_signing and lp.ord > 1;
  if v_id is not null then
    return v_id;
  end if;
  select lp.id into v_id from public.land_parties lp
   where lp.player_id = p_player and lp.ord > 1 and not public.land_party_out(lp.id) and not exists (select 1 from public.captain_seats cs where cs.party_id = lp.id)
   order by lp.ord limit 1;
  if v_id is null then
    insert into public.land_parties (player_id, port_id, ord)
    select p_player, public.home_port_of(p_player), coalesce(max(lp.ord), 1) + 1 from public.land_parties lp where lp.player_id = p_player
    returning id into v_id;
  end if;
  perform public.captain_land_put(p_signing, v_id);
  return v_id;
end
$body$
  $f$;

  execute $f$
create function public.land_expedition_send_for(p_player uuid, p_code text, p_ask jsonb, p_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0534: SEND: a captain of hers (ashore, docked, or with a party at home), her terms frozen, the bill paid to the harbour the party lives in (the hands
-- drawn from its pool as cmd.do_hire draws them), one round_runs row of the party. Refusals raise 'E_CODE: sentence'. Server only.
declare
  v_po    uuid;
  v_name  text;
  v_now   record;
  v_party uuid;
  t       jsonb;
  v_ev    uuid;
  v_over  int;
begin
  if not public.land_expedition_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'land expeditions are not open yet');
  end if;
  perform 1 from public.players pl where pl.id = p_player for update;
  select po.id, o.name into v_po, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = p_player and o.code = upper(btrim(coalesce(p_code, '')));
  if v_po is null then
    perform cmd.refuse('E_NOT_SIGNED', 'You do not keep that captain.');
  end if;
  select cs.ship_id, f.status, public.land_party_out(cs.party_id) as away into v_now
    from public.captain_seats cs left join public.ships s on s.id = cs.ship_id left join public.fleets f on f.id = s.fleet_id where cs.player_officer_id = v_po;
  if v_now.ship_id is not null and v_now.status is distinct from 'DOCKED' then
    perform cmd.refuse('E_NOT_IN_PORT', format('%s is aboard a ship that is not in port.', v_name));
  elsif coalesce(v_now.away, false) then
    perform cmd.refuse('E_LAND_OUT', format('%s is out already', v_name));
  end if;
  t := public.land_expedition_terms(p_player, v_po, p_ask, gen_random_uuid());
  if t ? 'short' then
    perform cmd.refuse(t->'short');
  end if;
  if (select pl.ducats from public.players pl where pl.id = p_player) < (t->>'total')::bigint then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', format('Money %s / %s', (select pl.ducats from public.players pl where pl.id = p_player), t->>'total'),
                       cmd.figures((select pl.ducats from public.players pl where pl.id = p_player), (t->>'total')::numeric, 'ducats'));
  end if;
  v_party := public.land_expedition_party(p_player, v_po);
  -- the bill, and the hands
  v_over := greatest(0, (select lp.crew from public.land_parties lp where lp.id = v_party) - (t->>'crew')::int);
  if (t #>> '{bill,hire}')::bigint > 0 then
    update public.ports set crew_pool = greatest(0, crew_pool - (t #>> '{bill,normal}')::int) where id = (t->>'port')::uuid;
    v_ev := public.emit_event(p_player, 'HIRED', jsonb_build_object('fleet', v_name, 'count', (t->>'hire')::int, 'urgent', (t->>'hire')::int - (t #>> '{bill,normal}')::int, 'cost', (t #>> '{bill,hire}')::bigint));
    perform public.pay_city(p_player, (t->>'port')::uuid, 'HIRE', (t #>> '{bill,hire}')::bigint, v_ev);
  end if;
  if v_over > 0 then
    update public.ports set crew_pool = crew_pool + v_over where id = (t->>'port')::uuid;
  end if;
  if (t #>> '{bill,stores}')::bigint > 0 then
    perform public.pay_city(p_player, (t->>'port')::uuid, 'PROVISION', (t #>> '{bill,stores}')::bigint, null);
  end if;
  if (t #>> '{bill,wages}')::bigint > 0 then
    perform public.pay_city(p_player, (t->>'port')::uuid, 'WAGES', (t #>> '{bill,wages}')::bigint, null);
  end if;
  update public.land_parties set crew = (t->>'crew')::int, stores_t = (t->>'stores')::numeric where id = v_party;
  insert into public.round_runs as r (party_id, player_id, work, state, sent_at, stop_at, booked, terms, stop)
  values (v_party, p_player, t->>'work', 'out', p_at, p_at + make_interval(secs => (2 * (t->>'lead')::numeric + (t->>'most')::int * (t->>'seconds')::numeric)::double precision), 0,
          t || jsonb_build_object('captain', v_po, 'ask', p_ask), coalesce(p_ask->'stop', '{}'::jsonb))
  on conflict (party_id) do update set work = excluded.work, state = 'out', sent_at = excluded.sent_at, stop_at = excluded.stop_at, booked = 0, terms = excluded.terms,
        stop = excluded.stop, carry = '{}', log = '[]', ended = null, updated_at = now();
  return jsonb_build_object('ok', true, 'officer', upper(btrim(p_code)), 'rounds', t->'most', 'home_at', p_at + make_interval(secs => (2 * (t->>'lead')::numeric + (t->>'most')::int * (t->>'seconds')::numeric)::double precision),
                            'paid', t->'total', 'sentence', format('%s: %s rounds', v_name, t->>'most'));
end
$body$
  $f$;

  execute $f$
create function public.land_expedition_settle(p_party uuid, p_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0534: THE ONE WRITER of an expedition: books the rounds that have passed and are not booked (public.round_clock from the march's end): hands, stores, what
-- they have in hand, the last 20 lines. Past the stop and the march back she is home: the goods into the harbour's Storage (what does not fit waits with
-- the party, as the land's), experience to the company and to her captain, Reputation, gold from her country's capital (never minted: none while the
-- purses are dark, none when the capital cannot), HONOR BADGES, one ROUNDS_DONE event. then repeat: sent again with the same ask, or it stays home and says why.
declare
  r       public.round_runs%rowtype;
  lp      public.land_parties%rowtype;
  t       jsonb;
  c       record;
  v_most  int;
  v_new   int;
  z       record;
  v_log   jsonb;
  v_c     jsonb;
  v_over  boolean;
  v_g     public.goods%rowtype;
  v_fit   numeric;
  v_put   int;
  v_units int;
  v_n     int;
  v_res   jsonb;
  v_cap   uuid;
  v_nat   uuid;
  v_badge int;
  v_name  text;
  v_again text;
begin
  select * into r from public.round_runs x where x.party_id = p_party for update;
  if r.party_id is null or r.state <> 'out' then
    return jsonb_build_object('new', 0, 'over', false);
  end if;
  t := r.terms;
  v_most := (t->>'most')::int;
  select * into c from public.round_clock(r.sent_at + make_interval(secs => (t->>'lead')::double precision), (t->>'seconds')::numeric, p_at,
                                          r.sent_at + make_interval(secs => ((t->>'lead')::numeric + v_most * (t->>'seconds')::numeric)::double precision));
  v_new := greatest(0, least(c.n, v_most)::int - r.booked);
  v_over := p_at >= r.stop_at;
  if v_new = 0 and not v_over then
    return jsonb_build_object('new', 0, 'over', false);
  end if;
  v_c := r.carry;
  if v_new > 0 then
    select sum(e.hands)::int as hands, sum(e.xp)::int as xp, sum(e.gold)::int as gold, sum(e.rp)::int as rp, sum(e.units)::int as units,
           count(*) filter (where not e.fed)::int as ate, count(*) filter (where e.result = 1)::int as won,
           jsonb_agg(jsonb_build_object('r', n, 'at', r.sent_at + make_interval(secs => ((t->>'lead')::numeric + n * (t->>'seconds')::numeric)::double precision), 'crew', e.hands,
                                        'xp', e.xp, 'gold', e.gold, 'units', e.units, 'fed', e.fed, 'result', e.result) order by n desc) as lines
      into z from generate_series(r.booked + 1, r.booked + v_new) n cross join lateral public.land_expedition_round(t, n) e;
    select coalesce(jsonb_agg(q.l order by (q.l->>'r')::int), '[]'::jsonb) into v_log
      from (select e.l from (select e1.l from jsonb_array_elements(r.log) e1(l) union all select e2.l from jsonb_array_elements(z.lines) e2(l)) e order by (e.l->>'r')::int desc limit 20) q;
    v_c := jsonb_build_object('hands', coalesce((v_c->>'hands')::int, 0) + z.hands, 'xp', coalesce((v_c->>'xp')::int, 0) + z.xp, 'gold', coalesce((v_c->>'gold')::int, 0) + z.gold,
                              'rp', coalesce((v_c->>'rp')::int, 0) + z.rp, 'units', coalesce((v_c->>'units')::int, 0) + z.units, 'won', coalesce((v_c->>'won')::int, 0) + z.won);
    update public.land_parties set crew = greatest(0, crew - z.hands), stores_t = greatest(0, round(stores_t - z.ate * (t->>'use')::numeric, 3)) where id = p_party;
    r.booked := r.booked + v_new;
    r.log := v_log;
  end if;
  update public.round_runs set booked = r.booked, log = r.log, carry = v_c, state = case when v_over then 'home' else 'out' end,
         ended = case when v_over then coalesce(ended, t->>'why') else ended end, updated_at = now()
   where party_id = p_party;
  if not v_over then
    return jsonb_build_object('new', v_new, 'over', false);
  end if;

  -- HOME
  select * into lp from public.land_parties x where x.id = p_party for update;
  v_units := coalesce((v_c->>'units')::int, 0);
  if v_units > 0 then
    select * into v_g from public.goods where id = (t->>'good')::uuid;
    v_fit := floor(greatest(public.storage_cap(lp.port_id) - public.storage_used(lp.player_id, lp.port_id), 0) / v_g.bulk);
    v_put := least(v_units, v_fit)::int;
    if v_put > 0 then
      perform public.storage_put(lp.player_id, lp.port_id, v_g.id, v_put, 0);
    end if;
    if v_units > v_put then   -- it waits with the party, as a haul of the land's (a find of another good keeps its own place)
      update public.land_parties set found_waiting = jsonb_set(found_waiting, array[v_g.code], to_jsonb(coalesce((found_waiting->>v_g.code)::int, 0) + v_units - v_put)) where id = p_party;
    end if;
  end if;
  if coalesce((v_c->>'xp')::int, 0) > 0 then
    if t->>'work' = 'land_gather' then
      perform public.level_grant(lp.player_id, (select la.code from public.level_activities la where la.skill = 'mining' order by la.ord limit 1), (v_c->>'xp')::int, 'landx:' || (t->>'seed'));
    end if;
    perform public.captain_work_credit((t->>'captain')::uuid, case when t->>'work' = 'land_raid' then 'arms' else 'mining' end, (v_c->>'xp')::int);
  end if;
  if coalesce((v_c->>'rp')::int, 0) > 0 then
    perform public.reputation_credit(lp.player_id, 'land', (v_c->>'rp')::int, 'landx:' || (t->>'seed'));
  end if;
  if coalesce((v_c->>'gold')::int, 0) > 0 then
    select pl.nation_id into v_nat from public.players pl where pl.id = lp.player_id;
    select cp.id into v_cap from public.nations n join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR' where n.id = v_nat;
    if v_cap is not null and public.city_treasury_on() then
      v_res := public.capital_pays(v_cap, v_nat, lp.player_id, 'VOYAGE_REWARD', (v_c->>'gold')::bigint, null, false, null);
    end if;
    v_c := v_c || jsonb_build_object('paid', coalesce((v_res->>'paid')::bigint, 0));
  end if;
  v_badge := floor(case when t->>'work' = 'land_raid' then coalesce((v_c->>'won')::int, 0)::numeric / 6 else r.booked::numeric / 24 end)::int;
  v_badge := v_badge * (1 + coalesce((t #>> '{raid,level}')::int, 1) / 40);
  if v_badge > 0 then
    v_badge := public.honor_credit(lp.player_id, 'land', v_badge, 'landx:' || (t->>'seed'));
  end if;
  select o.name into v_name from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = (t->>'captain')::uuid;
  perform public.emit_event(lp.player_id, 'ROUNDS_DONE', jsonb_build_object('fleet', coalesce(v_name, 'Land party'), 'party', lp.ord, 'work', r.work, 'rounds', r.booked, 'why', t->>'why',
            'crew', v_c->'hands', 'good', v_g.code, 'units', v_units, 'xp', v_c->'xp', 'gold', v_c->'paid', 'reputation', v_c->'rp', 'honor', v_badge));
  if t->>'then' = 'repeat' and r.ended is null then
    begin
      perform public.land_expedition_send_for(lp.player_id, (select o.code from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = (t->>'captain')::uuid), t->'ask', p_at);
    exception when others then
      v_again := substring(sqlerrm from '^(E_[A-Z0-9_]+)');
      if v_again is null then raise; end if;
      update public.round_runs set ended = v_again where party_id = p_party;
    end;
  end if;
  return jsonb_build_object('new', v_new, 'over', true, 'carry', v_c, 'honor', v_badge, 'again', v_again);
end
$body$
  $f$;

  execute $f$
create function public.land_expedition_settle_due(p_now timestamptz, p_most int)
returns int language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0534: the parties whose expedition is over, settled (public.round_settle_due calls this: the jobs' tick, every 2 minutes; never the beat).
declare
  x   record;
  v_n int := 0;
begin
  for x in select r.party_id from public.round_runs r where r.party_id is not null and r.state = 'out' and r.stop_at <= p_now order by r.stop_at limit p_most for update skip locked loop
    perform public.land_expedition_settle(x.party_id, p_now);
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$body$
  $f$;

  execute $f$
create function public.land_expedition_home_for(p_player uuid, p_code text, p_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0534: CALL THEM HOME: the rounds passed are kept, a round under way is given up, they march back (as long as they marched out, or what of it they had
-- marched). Home already: refused. It is settled when they are there. Server only.
declare
  r      public.round_runs%rowtype;
  v_back numeric;
begin
  select rr.* into r from public.round_runs rr
    join public.captain_seats cs on cs.party_id = rr.party_id
    join public.player_officers po on po.id = cs.player_officer_id
    join public.officers o on o.id = po.officer_id
   where po.player_id = p_player and o.code = upper(btrim(coalesce(p_code, ''))) and rr.state = 'out' for update of rr;
  if r.party_id is null then
    perform cmd.refuse('E_NOT_SAILING', 'she is not out on an expedition');
  end if;
  perform public.land_expedition_settle(r.party_id, p_at);
  select * into r from public.round_runs x where x.party_id = r.party_id;
  if r.state = 'out' and r.ended is null then
    v_back := least((r.terms->>'lead')::numeric, extract(epoch from p_at - r.sent_at));
    update public.round_runs set ended = 'called', stop_at = least(stop_at, p_at + make_interval(secs => v_back::double precision)),
           terms = terms || jsonb_build_object('most', booked, 'why', 'called', 'then', 'home'), updated_at = now()
     where party_id = r.party_id returning * into r;
  end if;
  return jsonb_build_object('ok', true, 'rounds', r.booked, 'home_at', r.stop_at, 'sentence', format('%s rounds', r.booked));
end
$body$
  $f$;

  execute $f$
create function cmd.land_expedition(p_code text, p_ask jsonb default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0534: send a captain of yours on a land expedition (p_ask: public.land_expedition_terms), or call her home (p_ask null).
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null or coalesce((select p.is_npc from public.players p where p.id = v_player), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if p_ask is null then
      return public.land_expedition_home_for(v_player, p_code, now());
    end if;
    return public.land_expedition_send_for(v_player, p_code, p_ask, now());
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      return jsonb_build_object('ok', false, 'error_code', 'E_BAD_ORDER', 'error_message', 'a number was expected', 'fixes', '[]'::jsonb);
    when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      get stacked diagnostics v_det = pg_exception_detail;
      return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  execute $f$
create function world.land_expedition(p_code text default null, p_ask jsonb default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
as $body$
-- 0534: THE LAND EXPEDITIONS, the client's one read. {on: false} dark. runs: her captains' parties that were sent (the run, its rounds, its log). Named a
-- captain: targets (the places to gather and the foes, each with its level and whether hers is enough), the crew cap, and with p_ask the card of that
-- very Send (public.land_expedition_card: what it costs and brings; or the refusal). Its raid is quoted on a seed of the question's own, never the Send's. Reads only.
declare
  v_me uuid := public.current_player_id();
  v_po uuid;
begin
  if not public.land_expedition_on() then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_me and o.code = upper(btrim(coalesce(p_code, '')));
  return jsonb_build_object('on', true, 'company', true, 'now', now(), 'raids', public.land_raids_on(),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object(
               'party', lp.ord, 'captain', o.code, 'name', o.name, 'crew', lp.crew, 'stores', lp.stores_t, 'work', r.work, 'word', r.terms->'word', 'target', r.terms->'target',
               'state', case when r.state = 'out' and now() >= r.stop_at then 'home' else r.state end, 'ended', r.ended, 'sent_at', r.sent_at, 'home_at', r.stop_at,
               'rounds', greatest(r.booked, least((r.terms->>'most')::int, (select k.n from public.round_clock(r.sent_at + make_interval(secs => (r.terms->>'lead')::double precision), (r.terms->>'seconds')::numeric, now(),
                                   r.sent_at + make_interval(secs => ((r.terms->>'lead')::numeric + (r.terms->>'most')::int * (r.terms->>'seconds')::numeric)::double precision)) k))),
               'most', r.terms->'most', 'why', r.terms->>'why', 'seconds', r.terms->'seconds', 'lead', r.terms->'lead', 'min', r.terms->'min', 'then', r.terms->>'then', 'cost', r.terms->'cost',
               'carry', r.carry, 'log', r.log, 'waiting', lp.found_waiting) order by lp.ord), '[]'::jsonb)
               from public.land_parties lp join public.round_runs r on r.party_id = lp.id
               left join public.player_officers po on po.id = (r.terms->>'captain')::uuid left join public.officers o on o.id = po.officer_id
              where lp.player_id = v_me)) ||
    case when v_po is null then '{}'::jsonb else jsonb_build_object(
      'cap', public.land_raid_crew_cap(v_me),
      'targets', (select coalesce(jsonb_agg(q.t order by q.o1, q.o2), '[]'::jsonb) from (
                    select 1 as o1, a.ord as o2, jsonb_build_object('work', 'land_gather', 'target', a.code, 'word', g.name, 'level', a.level, 'open', public.level_of('mining', coalesce((select x.xp from public.level_xp x where x.player_id = v_me and x.skill = 'mining'), 0)) >= a.level) as t
                      from public.land_actions a join public.goods g on g.id = a.good_id where a.skill = 'mining' and a.kind <> 'make'
                    union all
                    select 2, f.ord, jsonb_build_object('work', 'land_raid', 'target', f.code, 'word', f.word, 'level', f.level, 'open', public.captain_work_level(v_po, 'arms') >= f.level)
                      from public.land_foes f where public.land_raids_on()) q),
      'card', case when p_ask is null then null else public.land_expedition_card(public.land_expedition_terms(v_me, v_po, p_ask, md5(v_po::text || coalesce(p_ask->>'target', ''))::uuid)) end) end;
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0534 (fn text, ord int, old text, new text) on commit drop;

  insert into hunks_0534 values ('public.crew_hire_cost(uuid,integer)', 1,
$h$  select * into f from public.fleets where id = p_fleet;
  select crew_pool into v_pool from public.ports where id = f.port_id;
  v_norm := least(v_count, case when exists (select 1 from public.players p where p.id = f.player_id and p.is_npc)
                                then greatest(0, v_pool - public.wc_int('npc_crew_pool_floor'))
                                else v_pool end);
  v_urg  := v_count - v_norm;
  if public.skills_bite_on() then
    v_pct := world.skill_pct(f.player_id, null, 'crew_hire');
  end if;
  if v_pct = 0 then
    v_cost := round(v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))::bigint;
  else
    v_cost := round((v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))
                    * (1 - least(v_pct, 100) / 100.0))::bigint;
  end if;
  return jsonb_build_object('normal', v_norm, 'urgent', v_urg, 'cost', v_cost);
$h$,
$h$  select * into f from public.fleets where id = p_fleet;
  -- 0534: the lines are public.crew_hire_cost_at's (moved there whole): a land party asks the same of the harbour it lives in
  return public.crew_hire_cost_at(f.player_id, f.port_id, p_count);
$h$);

  insert into hunks_0534 values ('public.round_settle_due(timestamp with time zone,integer)', 1,
$h$  end loop;
  return v_n;$h$,
$h$  end loop;
  v_n := v_n + public.land_expedition_settle_due(p_now, p_most);   -- 0534: and the land expeditions whose time is over
  return v_n;$h$);

  insert into hunks_0534 values ('public.seat_captain_for(uuid,text,uuid,integer)', 1,
$h$where cs.player_officer_id = v_po and lp.action is not null) then$h$,
$h$where cs.player_officer_id = v_po and public.land_party_out(lp.id)) then   -- 0534: or on an expedition$h$);

  insert into hunks_0534 values ('public.captain_land_for(uuid,text,integer)', 1,
$h$select s.name as ship, f.status, lp.action into v_now$h$,
$h$select s.name as ship, f.status, case when public.land_party_out(lp.id) then 'out' end as action into v_now   -- 0534$h$);

  insert into hunks_0534 values ('public.captain_land_for(uuid,text,integer)', 2,
$h$where lp.id = v_party and lp.action is not null) then$h$,
$h$where lp.id = v_party and public.land_party_out(lp.id)) then   -- 0534$h$);

  insert into hunks_0534 values ('public.captain_dismiss_for(uuid,text)', 1,
$h$select cs.ship_id, f.status, lp.action into v_now$h$,
$h$select cs.ship_id, f.status, case when public.land_party_out(lp.id) then 'out' end as action into v_now   -- 0534$h$);

  insert into hunks_0534 values ('public.captain_upgrade_for(uuid,text,text)', 1,
$h$select cs.ship_id, f.status, lp.action into v_now$h$,
$h$select cs.ship_id, f.status, case when public.land_party_out(lp.id) then 'out' end as action into v_now   -- 0534$h$);

  insert into hunks_0534 values ('world.captains()', 1,
$h$where lp.id = cs.party_id and lp.action is not null))$h$,
$h$where lp.id = cs.party_id and public.land_party_out(lp.id)))$h$);

  insert into hunks_0534 values ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'captain_land',          'text, int'),
$h$,
$h$      ('cmd',         'captain_land',          'text, int'),
      -- 0534: a land expedition sent or called home, and its read (dark: E_NOT_IN_USE; {"on": false})
      ('cmd',         'land_expedition',       'text, jsonb'),
      ('world',       'land_expedition',       'text, jsonb'),
$h$);


  for v_h in select h.fn from hunks_0534 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0534 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0534 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0534 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0534 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0534 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0534 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0534 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0534 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0534 self-assert FAIL: a knob of another file moved';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin
    v_me := public.new_house('00000000-0534-4000-8000-000000000001', 'Casa da Mata 0534', 'PRT');
    perform cmd.assume_identity('00000000-0534-4000-8000-000000000001');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    v_pt := public.home_port_of(v_me);
    update public.players set ducats = 1000000 where id = v_me;
    update public.ports set crew_pool = 500 where id = v_pt;
    update public.world_config set value = 'false'::jsonb where key in ('skills_bite', 'levels_bite', 'city_treasury_enabled', 'economy_closed');
    select o.code into v_code from public.officers o join public.captain_profile cp on cp.officer_id = o.id
     where not exists (select 1 from public.player_officers po where po.player_id = v_me and po.officer_id = o.id) order by o.code limit 1;
    v_po := public.captain_sign_rows(v_me, (select o.id from public.officers o where o.code = v_code));
    -- THE HIRE PRICE is what it was: the moved lines against 0154's own sums
    v_h0 := public.crew_hire_cost(v_fl, 520);
    if v_h0 <> jsonb_build_object('normal', 500, 'urgent', 20, 'cost', round(500 * public.wc_num('hire_crew_rate') + 20 * public.wc_num('hire_crew_rate') * public.wc_num('crew_urgent_multiplier'))::bigint)
       or public.crew_hire_cost_at(v_me, v_pt, 520) is distinct from v_h0 then
      raise exception '0534 self-assert FAIL: the hire price moved: %', v_h0;
    end if;
    -- THE WIDENED TABLE
    v_pa := public.land_party(v_me);
    v_sea := (select p.sea_id from public.ports p where p.id = v_pt);
    begin insert into public.round_runs (player_id, work, sea_id, state, sent_at, stop_at, terms) values (v_me, 'land_raid', v_sea, 'home', now(), now(), '{}'); exception when check_violation or not_null_violation then v_bad := v_bad + 1; end;
    begin insert into public.round_runs (fleet_id, party_id, player_id, work, sea_id, state, sent_at, stop_at, terms) values (v_fl, v_pa, v_me, 'land_raid', v_sea, 'home', now(), now(), '{}'); exception when check_violation then v_bad := v_bad + 1; end;
    begin insert into public.round_runs (fleet_id, player_id, work, state, sent_at, stop_at, terms) values (v_fl, v_me, 'land_raid', 'home', now(), now(), '{}'); exception when check_violation then v_bad := v_bad + 1; end;
    begin insert into public.round_runs (party_id, player_id, work, state, sent_at, stop_at, terms) values (v_pa, v_me, 'land_raid', 'home', now(), now(), '{}'), (v_pa, v_me, 'land_raid', 'home', now(), now(), '{}'); exception when unique_violation then v_bad := v_bad + 1; end;
    insert into public.round_runs (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, terms) values (v_fl, v_me, 'land_raid', v_sea, 'home', now(), now(), '{}');
    insert into public.round_runs as r (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, terms) values (v_fl, v_me, 'land_gather', v_sea, 'home', now(), now(), '{}')
    on conflict (fleet_id) do update set work = excluded.work;
    if v_bad <> 4 or (select rr.work from public.round_runs rr where rr.worker = v_fl) <> 'land_gather' then
      raise exception '0534 self-assert FAIL: the widened table (% of 4 refused)', v_bad;
    end if;
    delete from public.round_runs where fleet_id = v_fl;
    -- DARK
    select a.code into v_act from public.land_actions a where a.skill = 'mining' and a.kind <> 'make' and a.level = 1 order by a.ord limit 1;
    if cmd.land_expedition(v_code, jsonb_build_object('work', 'land_gather', 'target', v_act, 'crew', 5))->>'error_code' <> 'E_NOT_IN_USE' or world.land_expedition() <> '{"on": false}'::jsonb then
      raise exception '0534 self-assert FAIL: dark, an expedition is open';
    end if;
    update public.world_config set value = 'true'::jsonb where key in ('land_expedition_enabled', 'rounds_enabled', 'captain_works_enabled', 'land_enabled', 'land_raids_enabled', 'honor_enabled', 'reputation_on');
    -- no fleet may be sent on a land work, and none is listed
    if exists (select 1 from jsonb_array_elements(public.round_works_for(v_me, v_fl)) w where w->>'kind' = 'land') then
      raise exception '0534 self-assert FAIL: a land work is offered to a fleet';
    end if;
    -- a job in reach, and a foe of this probe's own (so nothing of the data or of the sea's fight is asked a sign)
    select a.code into v_act from public.land_actions a where a.skill = 'mining' and a.kind <> 'make' and a.level = 1 and jsonb_typeof(public.land_terms(v_me, a.code)->'short') = 'null'
     order by (public.land_terms(v_me, a.code)->>'trip')::numeric, a.ord limit 1;
    if v_act is null then
      raise exception '0534 self-assert FAIL: the probe found no mining job of level 1 in reach (static rows)';
    end if;
    insert into public.land_foes (code, ord, word, level, count, health, attack, accuracy, crew, tier, xp, gold, rp) values ('probe_straw', 98, 'Straw 0534', 1, 1, 0.01, 0.0001, 1, 1, 1, 8, 5, 1);
    -- THE CARD, the refusals
    v_r := world.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 10, "stop": {"rounds": 12}}');
    v_t := v_r->'card';
    if (v_r->>'cap')::int <> 10 or v_t ? 'seed' or v_t ? 'raid' or v_t::text ~* '(chance|odds)' or (v_t->>'most')::int <> 12 or v_t->>'why' <> 'rounds' or (v_t->>'carry')::numeric <> 10 or (v_t->>'use')::numeric <> 0.4
       or (v_t->>'total')::bigint <> (v_t #>> '{bill,hire}')::bigint + (v_t #>> '{bill,stores}')::bigint + (v_t #>> '{bill,wages}')::bigint or (v_t #>> '{bill,hire}')::bigint <> round(10 * public.wc_num('hire_crew_rate'))::bigint then
      raise exception '0534 self-assert FAIL: the card: %', v_t;
    end if;
    if cmd.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 11}')->>'error_code' <> 'E_AT_CAPACITY' or cmd.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 0}')->>'error_code' <> 'E_CREW_SHORT'
       or cmd.land_expedition(v_code, '{"work": "fish", "crew": 1}')->>'error_code' <> 'E_NO_SUCH_JOB' or cmd.land_expedition('NOBODY-0534', '{"work": "land_raid", "target": "probe_straw", "crew": 5}')->>'error_code' <> 'E_NOT_SIGNED'
       or cmd.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": "many"}')->>'error_code' <> 'E_BAD_ORDER' or cmd.land_expedition(v_code, null)->>'error_code' <> 'E_NOT_SAILING'
       or cmd.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 5, "stores": 0.1}')->>'error_code' <> 'E_ROUND_SHORT' then
      raise exception '0534 self-assert FAIL: a refusal is missing';
    end if;
    update public.players set ducats = (v_t->>'total')::bigint - 1 where id = v_me;
    v_r := cmd.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 10, "stop": {"rounds": 12}}');
    if v_r->>'error_code' <> 'E_INSUFFICIENT_FUNDS' or (select pl.ducats from public.players pl where pl.id = v_me) <> (v_t->>'total')::bigint - 1
       or exists (select 1 from public.land_parties lp where lp.player_id = v_me and lp.ord > 1) then
      raise exception '0534 self-assert FAIL: sent without the coin, or something was taken: %', v_r;
    end if;
    update public.players set ducats = 1000000 where id = v_me;
    -- THE STOP RULE by each of its five
    v_t := public.land_expedition_terms(v_me, v_po, '{"work": "land_raid", "target": "probe_straw", "crew": 10}', '00000000-0534-4000-8000-0000000000aa');
    if (v_t->>'why') <> 'food' or (v_t->>'most')::int <> 25 then
      raise exception '0534 self-assert FAIL: ten hands'' provisions are 25 rounds, not % (%)', v_t->>'most', v_t->>'why';
    end if;
    if public.land_expedition_stop(v_t || '{"stores": 1000, "carry": 1000}') ->> 'why' <> 'cap'
       or public.land_expedition_stop((v_t - 'raid') || '{"loss": 0.5, "min": 8, "units": 0}') ->> 'why' <> 'crew'
       or public.land_expedition_stop((v_t - 'raid') || '{"loss": 0.5, "min": 8, "units": 0}') ->> 'most' <> '5'
       or public.land_expedition_stop((v_t - 'raid') || '{"loss": 0, "units": 4, "bulk": 1, "stores": 10}') ->> 'why' <> 'load'
       or public.land_expedition_stop((v_t - 'raid') || '{"loss": 0, "units": 0, "forage": 2}') ->> 'most' <> '50'
       or public.land_expedition_stop(v_t || '{"stop": {"rounds": 3}}') ->> 'most' <> '3' then
      raise exception '0534 self-assert FAIL: the stop rule: % / % / % / %', public.land_expedition_stop(v_t || '{"stores": 1000, "carry": 1000}'), public.land_expedition_stop((v_t - 'raid') || '{"loss": 0.5, "min": 8, "units": 0}'),
        public.land_expedition_stop((v_t - 'raid') || '{"loss": 0, "units": 4, "bulk": 1, "stores": 10}'), public.land_expedition_stop((v_t - 'raid') || '{"loss": 0, "units": 0, "forage": 2}');
    end if;
    -- SENT: the bill leaves the purse, the hands leave the pool, nobody moves while out
    v_t := world.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 10, "stop": {"rounds": 12}}')->'card';
    v_r := public.land_expedition_send_for(v_me, v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 10, "stop": {"rounds": 12}}', v_at);
    select lp.id into v_pa from public.land_parties lp where lp.player_id = v_me and lp.ord > 1;
    select * into r1 from public.round_runs rr where rr.party_id = v_pa;
    if (select pl.ducats from public.players pl where pl.id = v_me) <> 1000000 - (v_t->>'total')::bigint or (v_r->>'paid')::bigint <> (v_t->>'total')::bigint or (select p.crew_pool from public.ports p where p.id = v_pt) <> 490
       or r1.state <> 'out' or r1.worker <> v_pa or r1.stop_at <> v_at + make_interval(secs => 1800 + 12 * 600) or (select lp.crew from public.land_parties lp where lp.id = v_pa) <> 10 then
      raise exception '0534 self-assert FAIL: the Send: % / %', v_r, to_jsonb(r1) - 'terms';
    end if;
    if cmd.captain_land(v_code, 1)->>'error_code' <> 'E_LAND_OUT' or public.seat_captain_for(v_me, v_code, null, null)->>'error_code' <> 'E_LAND_OUT'
       or cmd.land_expedition(v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 5}')->>'error_code' <> 'E_LAND_OUT' or cmd.captain_upgrade(v_code, 'drill')->>'error_code' <> 'E_LAND_OUT' then
      raise exception '0534 self-assert FAIL: she could be moved while out';
    end if;
    -- BOOKED in one go as in nine: the same run settled both ways (the first rolled back)
    begin
      v_r := public.land_expedition_settle(v_pa, r1.stop_at);
      raise exception using errcode = 'ZY534', message = (select jsonb_build_object('c', rr.carry - 'paid', 'l', rr.log, 'b', rr.booked, 'h', lp.crew, 's', lp.stores_t, 'x', (select z.xp from public.captain_work_xp z where z.player_officer_id = v_po and z.work = 'arms'))::text
        from public.round_runs rr join public.land_parties lp on lp.id = rr.party_id where rr.party_id = v_pa);
    exception when sqlstate 'ZY534' then v_h0 := sqlerrm::jsonb;
    end;
    for i in 1 .. 9 loop
      v_r := public.land_expedition_settle(v_pa, v_at + (r1.stop_at - v_at) * i / 9);
    end loop;
    v_t := (select jsonb_build_object('c', rr.carry - 'paid', 'l', rr.log, 'b', rr.booked, 'h', lp.crew, 's', lp.stores_t, 'x', (select z.xp from public.captain_work_xp z where z.player_officer_id = v_po and z.work = 'arms'))
      from public.round_runs rr join public.land_parties lp on lp.id = rr.party_id where rr.party_id = v_pa);
    if v_t is distinct from v_h0 or (v_t->>'b')::int <> 12 or (v_t #>> '{c,xp}')::int <> 96 or (v_t->>'x')::int <> 96 or jsonb_array_length(v_t->'l') <> 12 or (v_t->>'s')::numeric <> 10 - 12 * 0.4 then
      raise exception '0534 self-assert FAIL: one go % / nine %', v_h0, v_t;
    end if;
    -- HOME: 12 rounds won are 2 badges, no coin while the purses are dark; the event
    if (select b.balance from public.honor_balance b where b.player_id = v_me) <> 2 or (select count(*) from public.events e where e.player_id = v_me and e.kind = 'ROUNDS_DONE' and (e.payload->>'honor')::int = 2) <> 1
       or (select pl.ducats from public.players pl where pl.id = v_me) <> 1000000 - (r1.terms->>'total')::bigint or public.land_party_out(v_pa) then
      raise exception '0534 self-assert FAIL: home: badges %', (select b.balance from public.honor_balance b where b.player_id = v_me);
    end if;
    -- GATHERING, and called home: ten home, eight sent, two back to the pool; the rounds passed kept, the load whole
    update public.land_parties set crew = 10 where id = v_pa;
    v_r := public.land_expedition_send_for(v_me, v_code, jsonb_build_object('work', 'land_gather', 'target', v_act, 'crew', 8, 'stop', '{"rounds": 4}'::jsonb), v_at);
    select * into r1 from public.round_runs rr where rr.party_id = v_pa;
    if (r1.terms->>'hire')::int <> 0 or (select p.crew_pool from public.ports p where p.id = v_pt) <> 492 then
      raise exception '0534 self-assert FAIL: ten home, eight sent: % hired', r1.terms->>'hire';
    end if;
    v_home := v_at + make_interval(secs => ((r1.terms->>'lead')::numeric + 2.5 * (r1.terms->>'seconds')::numeric)::double precision);
    v_r := public.land_expedition_home_for(v_me, v_code, v_home);
    select * into r1 from public.round_runs rr where rr.party_id = v_pa;
    if (r1.terms->>'most')::int <> r1.booked or (v_r->>'rounds')::int <> r1.booked or r1.booked > 2 or r1.state <> 'out' or r1.stop_at > v_home + make_interval(secs => (r1.terms->>'lead')::double precision) then
      raise exception '0534 self-assert FAIL: called home: %', v_r;
    end if;
    perform public.land_expedition_settle(v_pa, r1.stop_at);
    if coalesce((select sum(ps.qty) from public.player_storage ps where ps.player_id = v_me and ps.good_id = (r1.terms->>'good')::uuid), 0)
       + coalesce((select sum(e.value::numeric) from public.land_parties lp, jsonb_each_text(lp.found_waiting) e where lp.id = v_pa), 0) <> r1.booked * (r1.terms->>'units')::int then
      raise exception '0534 self-assert FAIL: the load did not come home whole';
    end if;
    -- REPEAT, through the tick's own step; then short of coin it stays home and says why
    update public.land_parties set found_waiting = '{}' where id = v_pa;
    perform public.land_expedition_send_for(v_me, v_code, '{"work": "land_raid", "target": "probe_straw", "crew": 8, "stop": {"rounds": 2}, "then": "repeat"}', v_at - interval '2 hours');
    v_r := public.land_expedition_settle(v_pa, v_at);
    select * into r1 from public.round_runs rr where rr.party_id = v_pa;
    if r1.state <> 'out' or r1.sent_at <> v_at or r1.booked <> 0 then
      raise exception '0534 self-assert FAIL: repeat did not go again: % %', r1.state, r1.ended;
    end if;
    update public.players set ducats = 0 where id = v_me;
    update public.land_parties set stores_t = 0 where id = v_pa;
    perform public.land_expedition_settle(v_pa, r1.stop_at);
    select * into r1 from public.round_runs rr where rr.party_id = v_pa;
    if r1.state <> 'home' or r1.ended <> 'E_INSUFFICIENT_FUNDS' then
      raise exception '0534 self-assert FAIL: with no coin it did not stay home and say why: % %', r1.state, r1.ended;
    end if;
    raise exception using errcode = 'ZX534', message = 'PROBE_ROLLBACK_0534';
  exception when sqlstate 'ZX534' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0534 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0534-4000-8000-%') or public.wc('land_expedition_enabled') is distinct from 'false'::jsonb then
    raise exception '0534 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0534 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0534 self-assert ok: LAND EXPEDITION (dark). Nine hunks once and reversing; fourteen new functions, a door and a read; round_runs keyed by a worker; no other function or knob moved. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
