-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0486 - CHOICES AT SEA  (dark: the owner's switch sea_choices_enabled, false; lit, a long trip can meet one event - a storm, a wreck or a
--        strange sail - that offers two or three options with honest odds and payoffs; she chooses on HQ in one press, or the safe default
--        applies; the outcome is settled at her arrival, through the city purse and her ledger)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 16 ("Choices at sea"); docs/design/hq-command-2026-11-23.md (every activity in HQ);
--   docs/dev-log/2026-11-23-sea-choices.md.
--
-- WHY: the owner, 2026-11-23: "i want this game to be strategical game, where all the work(activities) are done in HQ - words with
--   graphics. choosing best options available, finding best options." Slice 16: "a storm, a wreck or a strange sail on a long trip: a
--   choice, with a safe default for a player who is away. It touches the voyage's exact settle."
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob or one table in one function):
--   SET AT DEPARTURE (voyage.depart's human arm, ONE hunk -> public.sea_choice_plan, beside 0477's early sighting): a company's trip harbour
--     to harbour of sea_choices_trip_min_s (600 real seconds) or more, with no other choice of hers open, meets an event when
--     voyage.rng(voyage, 0, 'sea_choice') < sea_choices_chance (0.35). The kind: voyage.rng(voyage, 0, 'sea_choice_kind'): under 0.40 a
--     STORM, under 0.75 a WRECK, else a STRANGE SAIL. One row in public.sea_choices (the voyage is the key), shown from sea_choices_appear_at
--     (0.25) of the trip. Never raises: a fault is a warning, and the departure stands.
--   THE OPTIONS (public.sea_choice_options, THE ONE TABLE; pure): each {key, p, win, lose, ev, safe}: the odds p of the good end, the coin
--     of the good end (win) and of the bad end (lose), the expected coin ev = p x win + (1 - p) x lose, and whether it is the safe default.
--     The stake S = her cargo at cost x sea_choices_stake_pct (0.10), held to sea_choices_stake_min (200) .. sea_choices_stake_max
--     (20,000). The danger d is the highest danger her legs were frozen at (voyage.leg_danger, 1-5); the guns g her escort score
--     (voyage.escort_score), both read once at departure:
--       STORM  shelter (SAFE: a sure -0.25 S) | push on (p = 0.90 - 0.08 d: 0, else -0.8 S)
--       WRECK  sail on (SAFE: 0) | salvage (p 0.70: +0.8 S, else -0.3 S) | dive the hold (p 0.35: +2.5 S, else -0.5 S)
--       SAIL   keep away (SAFE: 0) | hail her (p = 0.80 - 0.06 d: +0.6 S, else -0.6 S) | give chase (p = g / (g + 30), 0.15-0.85:
--              +1.5 S, else -0.8 S)
--     The best by expected coin (public.sea_choice_best: the highest ev; a tie goes to the safe one, then the table's order) is served.
--   THE CHOICE (cmd.sea_choose(choice, option), registered for signed-in companies, the {ok: false} envelope): hers, open, shown
--     (appears_at passed), her voyage still sailing and before its arrival; she may change it until then. Dark E_NOT_IN_USE.
--   THE OUTCOME (public.sea_choice_result; pure in (voyage, option, world secret)): the good end when p = 1 or
--     voyage.rng(voyage, 0, 'sea_choice:' || option) < p. No random(), no clock: the same voyage, event and option give the same end
--     whenever it is settled.
--   THE SETTLE, AT HER ARRIVAL (voyage.settle's arrival, ONE hunk -> public.sea_choice_settle, in the company-only block beside the levels):
--     her option, or the safe default when she chose none, by its result; a gain is paid by the harbour she made (public.city_pays,
--     SEA_FIND, cut to what its purse holds when the purses are lit), a loss is paid to it (public.pay_city, SEA_LOSS, cut to what her
--     purse holds). One SEA_CHOICE event (the arrival card's and the history's line), the row settled at the voyage's eta. Never raises.
--     A voyage that ends without arriving (sent home dry, diverted) leaves its choice open; her next departure marks it lapsed (no coin).
--   THE READ world.sea_choices() (STABLE, registered): dark {"on": false}; lit, signed out or a merchant {"on": true, "company": false}; lit
--     her company {"on", "company", open: [the shown, open choices of voyages under way], recent: [the settled, newest first, 10]}.
-- ONE AUTHORITY EACH: the event, public.sea_choice_plan; the options and their odds, public.sea_choice_options; the best,
--   public.sea_choice_best; the end, public.sea_choice_result; the settle, public.sea_choice_settle; the page, world.sea_choices(). Money
--   moves by public.city_pays and public.pay_city alone (public.credit and public.treasury_post under them).
-- NOT CHANGED: voyage.hazard_roll, voyage.rng, every day of voyage.settle (its draw, its payloads, its delays), the VOYAGE_REPORT, the
--   arrival's order of acts, a merchant's voyage, the beat's statements (dark: one knob read at a company's departure and arrival).
-- ROWS. Dark: none. Lit: at most one open row a company; a settle writes the row, one event, one ledger row and one treasury row.
--   -- retention: public.sea_choices keeps a settled or lapsed row sea_choices_keep_days (3) days; her own older rows are deleted at her
--   next departure by public.sea_choice_plan (bounded by her own rows), and a row goes with its voyage (on delete cascade)
--   -- budget: no cron job and no beat step; dark one knob read at a company's departure and arrival; lit one insert at an eligible
--   departure, one primary-key probe at a company's arrival, and at most 3 rows written by a settle
-- LOCKS: CREATE TABLE x1 (new), CREATE FUNCTION x10, CREATE OR REPLACE x3 by hunks (voyage.depart, voyage.settle,
--   public.client_rpc_entry_points), two rows into public.stats_flow_words, the knobs. TIME: a few seconds. BUDGET: statement_timeout 60 s,
--   lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, sea_choices_enabled false (no event is set, the door refuses, the read is {"on": false}; an open
--   choice is not settled at its arrival and lapses at her next departure). Full: a new migration reversing the three hunks (OLD text below
--   verbatim), dropping the functions and the table, deleting the knobs and the two money-log words.
-- SELF-ASSERT: the hunks once each and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the knobs; the reads STABLE; the two doors registered for authenticated alone; every core server only (public, anon,
--   authenticated and service_role refused: the platform grants a new function to service_role by default, 0484's refusal); the table no
--   client's. THE PROBE (rolled back; deterministic: no time-budgeted read is asked and nothing is compared twice but the pure end;
--   one transaction; the sailing scenes start at 01:00 UTC of the day it runs, so a scene never straddles a UTC midnight): dark nothing is
--   set, the door refuses, the read is {"on": false}; lit a departure sets the event with its odds and expected coin, she picks the best
--   and her arrival (voyage.settle) settles it to the ducat; a second trip she leaves alone takes the safe default at its arrival; a short
--   trip sets nothing; an ended voyage's choice lapses; the door takes her pick and refuses the wrong ones; the read serves open and
--   recent; signed out the read is {"on": true, "company": false}. Proof 189 plays the rest.
-- VERSION: 0486 = 0485 + 1 (prod head 0485; the entry points' hunk is anchored on 0485's own line).
-- news: none (dark: nothing changes for a player until the owner lights sea_choices_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ── 0. GUARD, AND THE PRE-IMAGE (every function this file does not hunk or create: it must not move) ──
do $g$
begin
  if exists (select 1 from public.world_config where key = 'sea_choices_enabled') or to_regclass('public.sea_choices') is not null then
    raise exception '0486 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.early_sighting_plan(uuid,timestamp with time zone)') is null or to_regprocedure('voyage.rng(uuid,integer,text)') is null
     or to_regprocedure('voyage.leg_danger(jsonb)') is null or to_regprocedure('voyage.escort_score(uuid)') is null
     or to_regprocedure('public.city_pays(uuid,uuid,text,bigint,uuid)') is null or to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.sea_course(uuid,uuid)') is null or to_regprocedure('cmd.set_ship_role(uuid,text)') is null then
    raise exception '0486 refuses: 0485, 0482, 0477, 0330, 0168 or 0122 is not in this world';
  end if;
  create temp table pre_0486 on commit drop as
    select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text)) as fns,
           (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
              from pg_proc q where q.oid in ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure, 'voyage.settle(uuid,timestamp with time zone)'::regprocedure,
                                             'public.client_rpc_entry_points()'::regprocedure)) as meta
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
       and p.oid not in ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure, 'voyage.settle(uuid,timestamp with time zone)'::regprocedure,
                         'public.client_rpc_entry_points()'::regprocedure);
end
$g$;

-- ── 1. THE KNOBS ──
insert into public.world_config (key, value, description) values
  ('sea_choices_enabled', 'false'::jsonb,
   '0486: THE SWITCH (the owner''s). true: a company''s long trip harbour to harbour may meet one event (a storm, a wreck, a strange sail) with two or three options; she chooses on HQ before her arrival, or the safe default applies; the end is settled at her arrival through the city purse (SEA_FIND, SEA_LOSS). false: nothing is set, the door refuses E_NOT_IN_USE, the read is {"on": false}, and an open choice is not settled (it lapses at her next departure).'),
  ('sea_choices_chance', to_jsonb(0.35), '0486: the chance an eligible trip meets an event (voyage.rng(voyage, 0, ''sea_choice'') under it).'),
  ('sea_choices_trip_min_s', to_jsonb(600), '0486: the shortest trip (real seconds, departure to arrival) that can meet an event.'),
  ('sea_choices_appear_at', to_jsonb(0.25), '0486: the share of the trip after which the event is shown and may be chosen (the choice closes at her arrival).'),
  ('sea_choices_stake_pct', to_jsonb(0.10), '0486: the stake of an event: her cargo at cost at departure times this; every option''s coin is a multiple of it.'),
  ('sea_choices_stake_min', to_jsonb(200), '0486: the least stake (an empty hold still meets the sea).'),
  ('sea_choices_stake_max', to_jsonb(20000), '0486: the most stake.'),
  ('sea_choices_keep_days', to_jsonb(3), '0486: a settled or lapsed choice is kept this many days, then deleted at her next departure.');

-- ── 2. THE TABLE ──
-- retention: sea_choices_keep_days (3): a settled or lapsed row is deleted at her next departure (public.sea_choice_plan, her own rows
--   only), and with its voyage (on delete cascade); open rows are at most one a company
create table public.sea_choices (
  voyage_id   uuid primary key references public.voyages(id) on delete cascade,
  player_id   uuid not null references public.players(id) on delete cascade,
  fleet_id    uuid not null references public.fleets(id) on delete cascade,
  kind        text not null check (kind in ('storm', 'wreck', 'sail')),
  stake       bigint not null check (stake > 0),
  danger      numeric not null,
  guns        numeric not null,
  options     jsonb not null check (jsonb_typeof(options) = 'array'),
  appears_at  timestamptz not null,
  created_at  timestamptz not null,
  state       text not null default 'open' check (state in ('open', 'settled', 'lapsed')),
  chosen      text,
  chosen_at   timestamptz,
  decided_by  text check (decided_by in ('you', 'default')),
  outcome     jsonb,
  settled_at  timestamptz
);
create index sea_choices_player on public.sea_choices (player_id, state);
alter table public.sea_choices enable row level security;
revoke all on table public.sea_choices from public, anon, authenticated;
comment on table public.sea_choices is
  '0486: the one event a company''s long trip met (storm, wreck, strange sail): its options and odds, her choice, and its end. Written by public.sea_choice_plan, cmd.sea_choose and public.sea_choice_settle alone. Server only.';

-- ── 3. THE MONEY LOG'S WORDS (money moved between a city and a company, never made) ──
insert into public.stats_flow_words (kind, side, word, ord) values
  ('SEA_FIND', 'moved', 'Finds at sea paid', 68),
  ('SEA_LOSS', 'moved', 'Losses at sea', 69);

-- ── 4. THE RULES ──
create function public.sea_choices_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0486: THE SWITCH, read once: world_config sea_choices_enabled.
  select public.wc('sea_choices_enabled') = 'true'::jsonb
$body$;

create function public.sea_choice_options(p_kind text, p_stake bigint, p_danger numeric, p_guns numeric)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0486: THE ONE TABLE of an event's options: {key, p, win, lose, ev, safe}, in the order shown; the safe default first. Pure.
  with o(ord, key, p, w, l, safe) as (
    select * from (values
      (1, 'shelter', 1.0, -0.25, -0.25, true),
      (2, 'push',    round(least(0.95, greatest(0.30, 0.90 - 0.08 * coalesce(p_danger, 1))), 2), 0.0, -0.8, false)) s
     where p_kind = 'storm'
    union all
    select * from (values
      (1, 'pass',    1.0, 0.0, 0.0, true),
      (2, 'salvage', 0.70, 0.8, -0.3, false),
      (3, 'dive',    0.35, 2.5, -0.5, false)) s
     where p_kind = 'wreck'
    union all
    select * from (values
      (1, 'away',    1.0, 0.0, 0.0, true),
      (2, 'hail',    round(least(0.95, greatest(0.30, 0.80 - 0.06 * coalesce(p_danger, 1))), 2), 0.6, -0.6, false),
      (3, 'chase',   round(least(0.85, greatest(0.15, coalesce(p_guns, 0) / (greatest(coalesce(p_guns, 0), 0) + 30))) * 20) / 20, 1.5, -0.8, false)) s
     where p_kind = 'sail'
  ), c as (
    select o.ord, o.key, o.p, round(p_stake * o.w)::bigint as win, round(p_stake * o.l)::bigint as lose, o.safe from o
  )
  select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'p', c.p, 'win', c.win, 'lose', c.lose,
                                               'ev', round(c.p * c.win + (1 - c.p) * c.lose)::bigint, 'safe', c.safe) order by c.ord), '[]'::jsonb)
    from c
$body$;

create function public.sea_choice_best(p_options jsonb)
returns text
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0486: THE BEST BY EXPECTED COIN: the highest ev; a tie goes to the safe one, then the table's order. Pure.
  select o.e->>'key'
    from jsonb_array_elements(p_options) with ordinality o(e, n)
   order by (o.e->>'ev')::bigint desc, (o.e->>'safe')::boolean desc, o.n
   limit 1
$body$;

create function public.sea_choice_result(p_voyage uuid, p_option jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0486: THE END of one option on one voyage: pure in (voyage, option, world secret) - voyage.rng's own seed, never random() or the
  -- clock. {option, good, amount}: the good end (win) when p is 1 or the option's own stream draws under p, else the bad end (lose).
  select jsonb_build_object('option', p_option->>'key', 'good', x.good,
                            'amount', case when x.good then (p_option->>'win')::bigint else (p_option->>'lose')::bigint end)
    from (select (p_option->>'p')::numeric >= 1
                 or voyage.rng(p_voyage, 0, 'sea_choice:' || (p_option->>'key')) < (p_option->>'p')::numeric as good) x
$body$;

create function public.sea_choice_plan(p_voyage uuid, p_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0486: DOES THIS DEPARTURE MEET AN EVENT? Called by voyage.depart for a company alone. Dark: one knob read, false. Lit: her own rows are
-- tidied (an open choice whose voyage no longer sails lapses; a settled or lapsed one past sea_choices_keep_days goes); then a trip harbour
-- to harbour of sea_choices_trip_min_s or more, with no other choice of hers open, meets one when its draw is under sea_choices_chance: the
-- kind by its own draw, the options by public.sea_choice_options. Never raises: a fault is a warning and false.
declare
  v       public.voyages%rowtype;
  v_secs  numeric;
  v_r     numeric;
  v_kind  text;
  v_dng   numeric;
  v_guns  numeric;
  v_stake bigint;
begin
  if not public.sea_choices_on() then
    return false;
  end if;
  begin
    select * into v from public.voyages x where x.id = p_voyage;
    if v.id is null or not exists (select 1 from public.players p where p.id = v.player_id and not p.is_npc) then
      return false;
    end if;
    update public.sea_choices c set state = 'lapsed', settled_at = p_at, outcome = jsonb_build_object('lapsed', true)
     where c.player_id = v.player_id and c.state = 'open' and c.voyage_id <> v.id
       and not exists (select 1 from public.voyages x where x.id = c.voyage_id and x.status = 'SAILING');
    delete from public.sea_choices c
     where c.player_id = v.player_id and c.state <> 'open'
       and c.settled_at < p_at - make_interval(days => greatest(1, public.wc_int('sea_choices_keep_days')));
    if v.origin_port_id is null or v.dest_port_id is null or v.origin_port_id = v.dest_port_id
       or (select count(*) from public.ports p where p.id in (v.origin_port_id, v.dest_port_id) and p.kind = 'HARBOUR') <> 2 then
      return false;
    end if;
    v_secs := extract(epoch from v.eta - v.departed_at);
    if v_secs < public.wc_num('sea_choices_trip_min_s')
       or exists (select 1 from public.sea_choices c where c.player_id = v.player_id and c.state = 'open')
       or voyage.rng(v.id, 0, 'sea_choice') >= public.wc_num('sea_choices_chance') then
      return false;
    end if;
    v_r := voyage.rng(v.id, 0, 'sea_choice_kind');
    v_kind := case when v_r < 0.40 then 'storm' when v_r < 0.75 then 'wreck' else 'sail' end;
    select coalesce(max(voyage.leg_danger(e)), 1) into v_dng from jsonb_array_elements(v.path) e;
    v_guns := round(coalesce(voyage.escort_score(v.fleet_id), 0), 2);
    v_stake := least(public.wc_int('sea_choices_stake_max'),
                     greatest(public.wc_int('sea_choices_stake_min'), round(public.fleet_stock_at_cost(v.fleet_id) * public.wc_num('sea_choices_stake_pct'))::bigint));
    insert into public.sea_choices (voyage_id, player_id, fleet_id, kind, stake, danger, guns, options, appears_at, created_at)
    values (v.id, v.player_id, v.fleet_id, v_kind, v_stake, round(v_dng, 2), v_guns, public.sea_choice_options(v_kind, v_stake, v_dng, v_guns),
            v.departed_at + make_interval(secs => (v_secs * least(1, greatest(0, public.wc_num('sea_choices_appear_at'))))::double precision), p_at);
    return true;
  exception when others then
    raise warning 'sea_choice_plan: voyage % was not set (SQLSTATE %: %)', p_voyage, sqlstate, sqlerrm;
    return false;
  end;
end
$body$;

create function public.sea_choice_settle(p_voyage uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0486: THE SETTLE, at her arrival (voyage.settle, the company block). Dark: one knob read, null. Lit: her open choice of this voyage (none:
-- null): her option, or the safe default, by public.sea_choice_result; a gain paid by the harbour she made (public.city_pays SEA_FIND, cut
-- to its purse when the purses are lit), a loss paid to it (public.pay_city SEA_LOSS, cut to her purse); one SEA_CHOICE event; the row
-- settled at the voyage's eta. Never raises: a fault is a warning and the row lapses (no coin). Answers the outcome.
declare
  c       public.sea_choices%rowtype;
  v       public.voyages%rowtype;
  v_opt   jsonb;
  v_res   jsonb;
  v_amt   bigint;
  v_full  bigint;
  v_by    text;
  v_ev    uuid;
  v_out   jsonb;
  v_purse bigint;
begin
  if not public.sea_choices_on() then
    return null;
  end if;
  select * into c from public.sea_choices x where x.voyage_id = p_voyage and x.state = 'open' for update;
  if c.voyage_id is null then
    return null;
  end if;
  begin
    select * into v from public.voyages x where x.id = p_voyage;
    v_by := case when c.chosen is null then 'default' else 'you' end;
    select o.e into v_opt from jsonb_array_elements(c.options) o(e)
     where case when c.chosen is null then (o.e->>'safe')::boolean else o.e->>'key' = c.chosen end
     limit 1;
    v_res  := public.sea_choice_result(p_voyage, v_opt);
    v_full := (v_res->>'amount')::bigint;
    v_amt  := v_full;
    if v_amt > 0 and public.city_treasury_on() then
      v_amt := least(v_amt, greatest(0, public.treasury_balance(v.dest_port_id)));
    elsif v_amt < 0 then
      select greatest(0, p.ducats) into v_purse from public.players p where p.id = c.player_id for update;
      v_amt := -least(-v_amt, coalesce(v_purse, 0));
    end if;
    v_out := v_res || jsonb_build_object('by', v_by, 'kind', c.kind, 'amount', v_amt, 'full', v_full);
    v_ev := public.emit_event(c.player_id, 'SEA_CHOICE', v_out || jsonb_build_object(
              'fleet', (select f.name from public.fleets f where f.id = c.fleet_id), 'voyage_id', p_voyage,
              'port', (select p.code from public.ports p where p.id = v.dest_port_id)));
    if v_amt > 0 then
      perform public.city_pays(v.dest_port_id, c.player_id, 'SEA_FIND', v_amt, v_ev);
    elsif v_amt < 0 then
      perform public.pay_city(c.player_id, v.dest_port_id, 'SEA_LOSS', -v_amt, v_ev);
    end if;
    update public.sea_choices x set state = 'settled', decided_by = v_by, outcome = v_out, settled_at = v.eta where x.voyage_id = p_voyage;
    return v_out;
  exception when others then
    raise warning 'sea_choice_settle: voyage % was not settled (SQLSTATE %: %)', p_voyage, sqlstate, sqlerrm;
    update public.sea_choices x set state = 'lapsed', outcome = jsonb_build_object('lapsed', true, 'error', sqlstate),
                                    settled_at = coalesce(v.eta, c.appears_at) where x.voyage_id = p_voyage;
    return null;
  end;
end
$body$;

create function public.sea_choice_pick(p_player uuid, p_choice uuid, p_option text, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0486: HER PICK (cmd.sea_choose's core): hers, open, shown, her voyage sailing and before its arrival, an option of the event. She may
-- change it until then. Raises the refusal; answers {ok, choice, option}. Server only.
declare
  c public.sea_choices%rowtype;
  v public.voyages%rowtype;
begin
  select * into c from public.sea_choices x where x.voyage_id = p_choice for update;
  if c.voyage_id is null or c.player_id is distinct from p_player then
    perform cmd.refuse('E_NO_CHOICE', 'there is no such choice');
  end if;
  select * into v from public.voyages x where x.id = c.voyage_id;
  if c.state <> 'open' or v.status is distinct from 'SAILING' or p_now >= v.eta then
    perform cmd.refuse('E_TOO_LATE', 'she has made port: the choice is closed');
  end if;
  if p_now < c.appears_at then
    perform cmd.refuse('E_NO_CHOICE', 'nothing has been met yet');
  end if;
  if not exists (select 1 from jsonb_array_elements(c.options) o(e) where o.e->>'key' = p_option) then
    perform cmd.refuse('E_BAD_ORDER', 'no such option');
  end if;
  update public.sea_choices x set chosen = p_option, chosen_at = p_now where x.voyage_id = p_choice;
  return jsonb_build_object('ok', true, 'choice', p_choice, 'option', p_option);
end
$body$;

create function public.sea_choice_row(p_voyage uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0486: one choice as the read serves it: the event, the fleet, the trip, the deadline (her voyage's eta), the options with the best,
  -- her pick, and the end once settled.
  select jsonb_build_object('id', c.voyage_id, 'kind', c.kind, 'fleet', c.fleet_id, 'fleet_name', f.name,
           'from', (select p.code from public.ports p where p.id = v.origin_port_id), 'to', (select p.code from public.ports p where p.id = v.dest_port_id),
           'appears_at', c.appears_at, 'deadline', v.eta, 'stake', c.stake, 'danger', c.danger, 'guns', c.guns,
           'options', c.options, 'best', public.sea_choice_best(c.options), 'chosen', c.chosen, 'state', c.state, 'by', c.decided_by,
           'outcome', c.outcome, 'settled_at', c.settled_at)
    from public.sea_choices c
    join public.voyages v on v.id = c.voyage_id
    left join public.fleets f on f.id = c.fleet_id
   where c.voyage_id = p_voyage
$body$;

create function world.sea_choices()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0486: HER CHOICES AT SEA (the client's one read). Dark {"on": false}; lit, signed out or a merchant {"on": true, "company": false}; lit her
-- company {"on", "company", open (shown, open, her voyage sailing), recent (settled, newest first, 10)}. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if not public.sea_choices_on() then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return jsonb_build_object('on', true, 'company', true,
    'open', (select coalesce(jsonb_agg(public.sea_choice_row(c.voyage_id) order by c.appears_at, c.voyage_id), '[]'::jsonb)
               from public.sea_choices c join public.voyages v on v.id = c.voyage_id
              where c.player_id = v_me and c.state = 'open' and c.appears_at <= now() and v.status = 'SAILING'),
    'recent', (select coalesce(jsonb_agg(public.sea_choice_row(x.voyage_id) order by x.settled_at desc, x.voyage_id), '[]'::jsonb)
                 from (select c.voyage_id, c.settled_at from public.sea_choices c
                        where c.player_id = v_me and c.state = 'settled' order by c.settled_at desc, c.voyage_id limit 10) x));
end
$body$;

create function cmd.sea_choose(p_choice uuid, p_option text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0486: CHOOSE AT SEA (HQ's decision card, one press): her pick of the event's options, until her arrival (public.sea_choice_pick). The
-- switch (E_NOT_IN_USE), her company (E_NO_HOUSE); every refusal as the {ok: false} envelope.
declare
  v_me  uuid := public.current_player_id();
  v_det text;
begin
  if not public.sea_choices_on() then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_USE', 'error_message', 'Choices at sea are not open yet.', 'fixes', '[]'::jsonb);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.sea_choice_pick(v_me, p_choice, p_option, now());
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;

-- grants: the two doors to authenticated alone; every core server only (service_role too: the platform grants execute on a new function
-- by default, 0484's refusal)
do $gr$
declare
  q text;
begin
  foreach q in array array['cmd.sea_choose(uuid,text)', 'world.sea_choices()'] loop
    execute format('revoke all on function %s from public, anon, service_role', q::regprocedure);
    execute format('grant execute on function %s to authenticated', q::regprocedure);
  end loop;
  foreach q in array array['public.sea_choices_on()', 'public.sea_choice_options(text,bigint,numeric,numeric)', 'public.sea_choice_best(jsonb)',
                           'public.sea_choice_result(uuid,jsonb)', 'public.sea_choice_plan(uuid,timestamptz)', 'public.sea_choice_settle(uuid)',
                           'public.sea_choice_pick(uuid,uuid,text,timestamptz)', 'public.sea_choice_row(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', q::regprocedure);
  end loop;
end
$gr$;
comment on function world.sea_choices() is
  '0486: her choices at sea (dark {"on": false}): the open ones shown now, and the lately settled with their ends. A read. Client door.';

-- ── 5. THE HUNKS, THE SELF-ASSERT, THE PROBE ──
do $m$
declare
  c_new    constant text[] := array['public.sea_choices_on()', 'public.sea_choice_options(text,bigint,numeric,numeric)', 'public.sea_choice_best(jsonb)',
                                    'public.sea_choice_result(uuid,jsonb)', 'public.sea_choice_plan(uuid,timestamptz)', 'public.sea_choice_settle(uuid)',
                                    'public.sea_choice_pick(uuid,uuid,text,timestamptz)', 'public.sea_choice_row(uuid)',
                                    'cmd.sea_choose(uuid,text)', 'world.sea_choices()'];
  c_doors  constant text[] := array['cmd.sea_choose(uuid,text)', 'world.sea_choices()'];
  c_hunked constant text[] := array['voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'voyage.settle(uuid,timestamp with time zone)',
                                    'public.client_rpc_entry_points()'];
  c_ua     constant uuid := '00000000-0486-4000-8000-0000000000a1';
  c_ub     constant uuid := '00000000-0486-4000-8000-0000000000b1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_note      text := '';
  v_lived     boolean := false;
  v_day       timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';   -- 00:00 UTC of today: the scenes start at 01:00
  v_a         uuid;
  v_b         uuid;
  v_fa        uuid;
  v_fb        uuid;
  v_lis       uuid;
  v_to        uuid;
  v_tocode    text;
  v_good      text;
  v_out       jsonb;
  v_back      jsonb;
  v_vy        uuid;
  v_vy2       uuid;
  v_c         public.sea_choices%rowtype;
  v_opt       jsonb;
  v_res       jsonb;
  v_pick      text;
  v_r         jsonb;
  v_read      jsonb;
  v_eta       timestamptz;
  v_led       bigint;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0486 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0486 values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$h$    perform public.early_sighting_plan(v_voyage, p_at);   -- 0477: is this the trip a weak pirate sights? (dark: one knob read; never raises)
$h$,
$h$    perform public.early_sighting_plan(v_voyage, p_at);   -- 0477: is this the trip a weak pirate sights? (dark: one knob read; never raises)
    perform public.sea_choice_plan(v_voyage, p_at);   -- 0486: does this long trip meet a storm, a wreck or a strange sail? (dark: one knob read; never raises)
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$      perform public.level_arrival(f.player_id, v.id);
$h$,
$h$      perform public.level_arrival(f.player_id, v.id);
      -- 0486: a choice met at sea is settled at her arrival: her pick, or the safe default (public.sea_choice_settle; dark one knob read; never raises)
      perform public.sea_choice_settle(v.id);
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'ship_roles',            ''),$h$,
$h$      ('world',       'ship_roles',            ''),
      -- 0486: choices at sea (dark: the door E_NOT_IN_USE, the read {"on": false})
      ('cmd',         'sea_choose',            'uuid, text'),
      ('world',       'sea_choices',           ''),$h$);

  for v_h in select h.fn from hunks_0486 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0486 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0486 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0486 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0486 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0486 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── SELF-ASSERT: the catalog, the knobs, the doors ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) is distinct from (select pre.fns from pre_0486 pre) then
    raise exception '0486 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
        from pg_proc q where q.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q))))
     is distinct from (select pre.meta from pre_0486 pre) then
    raise exception '0486 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select count(*) from pg_proc p
       where p.oid = any (array['public.sea_choices_on()', 'public.sea_choice_result(uuid,jsonb)', 'public.sea_choice_row(uuid)', 'world.sea_choices()']::regprocedure[]::oid[])
         and p.provolatile = 's') <> 4
     or (select count(*) from pg_proc p
          where p.oid = any (array['public.sea_choice_options(text,bigint,numeric,numeric)', 'public.sea_choice_best(jsonb)']::regprocedure[]::oid[])
            and p.provolatile = 'i') <> 2 then
    raise exception '0486 self-assert FAIL: a read is not STABLE, or the table of options and the best are not pure';
  end if;
  if public.wc('sea_choices_enabled') <> 'false'::jsonb or public.wc_num('sea_choices_chance') <> 0.35 or public.wc_int('sea_choices_trip_min_s') <> 600
     or public.wc_num('sea_choices_appear_at') <> 0.25 or public.wc_num('sea_choices_stake_pct') <> 0.10 or public.wc_int('sea_choices_stake_min') <> 200
     or public.wc_int('sea_choices_stake_max') <> 20000 or public.wc_int('sea_choices_keep_days') <> 3
     or (select count(*) from public.world_config c where c.key like 'sea\_choices\_%') <> 8 then
    raise exception '0486 self-assert FAIL: the knobs are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) in (('cmd', 'sea_choose', 'uuid, text'), ('world', 'sea_choices', ''))
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')
         and not has_function_privilege('service_role', e.fn, 'execute')) <> 2
     or exists (select 1 from unnest(c_new) u(q)
                 where u.q <> all (c_doors)
                   and (has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                        or has_function_privilege('service_role', u.q::regprocedure, 'execute')))
     or has_table_privilege('authenticated', 'public.sea_choices', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.sea_choices', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.sea_choices'::regclass)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0486 self-assert FAIL: a door is not registered for authenticated alone, a core is reachable by a client or service_role, or the table is';
  end if;
  -- the table of options as written: the expected coin of each, and the best (pure: no clock, no draw)
  if public.sea_choice_options('wreck', 1000, 1, 0) <> '[{"p": 1.0, "ev": 0, "key": "pass", "win": 0, "lose": 0, "safe": true}, {"p": 0.70, "ev": 470, "key": "salvage", "win": 800, "lose": -300, "safe": false}, {"p": 0.35, "ev": 550, "key": "dive", "win": 2500, "lose": -500, "safe": false}]'::jsonb
     or public.sea_choice_best(public.sea_choice_options('wreck', 1000, 1, 0)) <> 'dive'
     or public.sea_choice_best(public.sea_choice_options('storm', 1000, 5, 0)) <> 'shelter'
     or public.sea_choice_best(public.sea_choice_options('storm', 1000, 1, 0)) <> 'push'
     or public.sea_choice_best(public.sea_choice_options('sail', 1000, 1, 0)) <> 'hail'
     or public.sea_choice_best(public.sea_choice_options('sail', 1000, 1, 90)) <> 'chase'
     or jsonb_array_length(public.sea_choice_options('storm', 1000, 1, 0)) <> 2 then
    raise exception '0486 self-assert FAIL: the table of options is not as written: % / %', public.sea_choice_options('wreck', 1000, 1, 0), public.sea_choice_options('storm', 1000, 5, 0);
  end if;

  -- ── THE PROBE, rolled back by a raised sentinel (no time-budgeted read is asked; only the pure end is compared again) ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa do Mar 0486', 'PRT');
    v_b := public.new_house(c_ub, 'Casa da Vela 0486', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    select f.id into v_fb from public.fleets f where f.player_id = v_b;
    update public.players p set ducats = 200000 where p.id in (v_a, v_b);
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id in (v_fa, v_fb);
    -- her stores for a long trip (the sea's own days run in voyage.settle), and a cargo at cost 50,000 (the stake 5,000)
    select g.code into v_good from public.goods g where g.bulk > 0 order by g.bulk, g.code limit 1;
    update public.ships set water_t = 500, food_t = 500, cargo = jsonb_build_object(v_good, 100), cargo_basis = jsonb_build_object(v_good, 500)
     where fleet_id in (v_fa, v_fb);
    -- B: the nearest harbour 150 miles or more from Lisbon with a stored course
    select r.port_id, r.code into v_to, v_tocode
      from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
     where r.nm >= 150 and public.sea_course(v_lis, r.port_id) is not null
     order by r.nm, r.code limit 1;
    if v_to is null or v_good is null then
      raise exception '0486 self-assert FAIL: the world has no harbour with a stored course from Lisbon, or no good';
    end if;
    perform cmd.assume_identity(c_ua);

    -- (a) DARK: a departure sets nothing, the door refuses, the read is {"on": false}, the settle is nothing
    v_vy := voyage.depart(v_fa, voyage.segments_from_course(public.sea_course(v_lis, v_to)), v_lis, v_to, v_day + interval '1 hour');
    if exists (select 1 from public.sea_choices) or world.sea_choices() is distinct from '{"on": false}'::jsonb
       or cmd.sea_choose(v_vy, 'pass')->>'error_code' is distinct from 'E_NOT_IN_USE' or public.sea_choice_settle(v_vy) is not null then
      raise exception '0486 self-assert FAIL: dark, an event was set, the door opened, the read is not {"on": false} or the settle acted';
    end if;
    update public.voyages set status = 'ARRIVED' where id = v_vy;
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fa;
    update public.world_config set value = 'true'::jsonb where key = 'sea_choices_enabled';
    update public.world_config set value = to_jsonb(1) where key = 'sea_choices_chance';
    update public.world_config set value = to_jsonb(0) where key = 'sea_choices_trip_min_s';

    -- (b) LIT, A DEPARTURE MEETS AN EVENT: its kind, its stake, the options with their odds and expected coin, shown at a quarter of the trip
    v_vy := voyage.depart(v_fa, voyage.segments_from_course(public.sea_course(v_lis, v_to)), v_lis, v_to, v_day + interval '1 hour');
    select * into v_c from public.sea_choices c where c.voyage_id = v_vy;
    select v.eta into v_eta from public.voyages v where v.id = v_vy;
    if v_c.voyage_id is null or v_c.state <> 'open' or v_c.stake <> 5000 or v_c.kind not in ('storm', 'wreck', 'sail')
       or v_c.options <> public.sea_choice_options(v_c.kind, 5000, v_c.danger, v_c.guns)
       or (select count(*) from jsonb_array_elements(v_c.options) o(e) where (o.e->>'safe')::boolean) <> 1
       or exists (select 1 from jsonb_array_elements(v_c.options) o(e)
                   where (o.e->>'ev')::bigint <> round((o.e->>'p')::numeric * (o.e->>'win')::bigint + (1 - (o.e->>'p')::numeric) * (o.e->>'lose')::bigint))
       or abs(extract(epoch from v_c.appears_at - (v_day + interval '1 hour')) - extract(epoch from v_eta - (v_day + interval '1 hour')) * 0.25) > 0.01 then
      raise exception '0486 self-assert FAIL: the event was not set as written: %', to_jsonb(v_c);
    end if;
    -- (c) SHE PICKS THE BEST (not the safe one where they differ), and HER ARRIVAL SETTLES IT (voyage.settle) to the ducat
    v_pick := public.sea_choice_best(v_c.options);
    if (select (o.e->>'safe')::boolean from jsonb_array_elements(v_c.options) o(e) where o.e->>'key' = v_pick) then
      select o.e->>'key' into v_pick from jsonb_array_elements(v_c.options) with ordinality o(e, n) where not (o.e->>'safe')::boolean order by o.n limit 1;
    end if;
    v_r := public.sea_choice_pick(v_a, v_vy, v_pick, v_c.appears_at + interval '1 second');
    select o.e into v_opt from jsonb_array_elements(v_c.options) o(e) where o.e->>'key' = v_pick;
    v_res := public.sea_choice_result(v_vy, v_opt);
    perform voyage.settle(v_fa, v_eta + interval '1 second');
    select * into v_c from public.sea_choices c where c.voyage_id = v_vy;
    select coalesce(sum(l.ducats_delta), 0) into v_led from public.ledger l where l.player_id = v_a and l.kind in ('SEA_FIND', 'SEA_LOSS');
    if (v_r->>'ok')::boolean is not true or (select v.status from public.voyages v where v.id = v_vy) <> 'ARRIVED'
       or v_c.state <> 'settled' or v_c.decided_by <> 'you' or v_c.settled_at <> (select v.eta from public.voyages v where v.id = v_vy)
       or v_c.outcome->>'option' <> v_pick or (v_c.outcome->'good') <> (v_res->'good') or (v_c.outcome->>'full')::bigint <> (v_res->>'amount')::bigint
       or v_led <> (v_c.outcome->>'amount')::bigint
       or not exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'SEA_CHOICE' and e.payload->>'voyage_id' = v_vy::text
                         and (e.payload->>'amount')::bigint = v_led and e.payload->>'port' = v_tocode) then
      raise exception '0486 self-assert FAIL: her pick was not settled at her arrival to the ducat: % / % / ledger %', v_r, to_jsonb(v_c), v_led;
    end if;
    v_out := v_c.outcome;

    -- (d) THE SECOND TRIP, LEFT ALONE: the safe default at its arrival
    v_vy2 := voyage.depart(v_fa, voyage.segments_from_course(public.sea_course(v_to, v_lis)), v_to, v_lis, v_eta + interval '10 minutes');
    select * into v_c from public.sea_choices c where c.voyage_id = v_vy2;
    select v.eta into v_eta from public.voyages v where v.id = v_vy2;
    perform voyage.settle(v_fa, v_eta + interval '1 second');
    select * into v_c from public.sea_choices c where c.voyage_id = v_vy2;
    select o.e into v_opt from jsonb_array_elements(v_c.options) o(e) where (o.e->>'safe')::boolean;
    if v_c.state <> 'settled' or v_c.decided_by <> 'default' or v_c.chosen is not null or v_c.outcome->>'option' <> v_opt->>'key'
       or (v_c.outcome->>'amount')::bigint <> (v_opt->>'win')::bigint
       or (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_a and l.kind in ('SEA_FIND', 'SEA_LOSS')) <> v_led + (v_opt->>'win')::bigint then
      raise exception '0486 self-assert FAIL: left alone, the safe default was not settled: %', to_jsonb(v_c);
    end if;
    v_back := v_c.outcome;

    -- (e) A SHORT TRIP SETS NOTHING; AN ENDED VOYAGE'S CHOICE LAPSES at her next departure
    v_vy := voyage.depart(v_fa, voyage.segments_from_course(public.sea_course(v_lis, v_to)), v_lis, v_to, v_eta + interval '20 minutes');
    if not exists (select 1 from public.sea_choices c where c.voyage_id = v_vy and c.state = 'open') then
      raise exception '0486 self-assert FAIL: a third trip met no event';
    end if;
    update public.voyages set status = 'ARRIVED' where id = v_vy;   -- ended without her arrival (placed by hand: sent home, diverted)
    update public.fleets set status = 'DOCKED', port_id = v_to, lat = null, lon = null where id = v_fa;
    update public.world_config set value = to_jsonb(1000000) where key = 'sea_choices_trip_min_s';
    v_vy2 := voyage.depart(v_fa, voyage.segments_from_course(public.sea_course(v_to, v_lis)), v_to, v_lis, v_eta + interval '30 minutes');
    if (select c.state from public.sea_choices c where c.voyage_id = v_vy) <> 'lapsed' or exists (select 1 from public.sea_choices c where c.voyage_id = v_vy2) then
      raise exception '0486 self-assert FAIL: the ended voyage''s choice did not lapse, or a short trip met an event';
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'sea_choices_trip_min_s';

    -- (f) THE DOOR (B, sailing now): not yet shown refused; shown, a wrong option refused, her pick taken; the read serves it open
    perform cmd.assume_identity(c_ub);
    v_vy := voyage.depart(v_fb, voyage.segments_from_course(public.sea_course(v_lis, v_to)), v_lis, v_to, now());
    update public.sea_choices set appears_at = now() + interval '1 hour' where voyage_id = v_vy;
    if cmd.sea_choose(v_vy, 'pass')->>'error_code' is distinct from 'E_NO_CHOICE' then
      raise exception '0486 self-assert FAIL: a choice not yet shown was taken';
    end if;
    update public.sea_choices set appears_at = now() - interval '1 second' where voyage_id = v_vy;
    select * into v_c from public.sea_choices c where c.voyage_id = v_vy;
    v_pick := (v_c.options->1->>'key');
    if cmd.sea_choose(v_vy, 'nonsense')->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.sea_choose(gen_random_uuid(), v_pick)->>'error_code' is distinct from 'E_NO_CHOICE' then
      raise exception '0486 self-assert FAIL: a wrong pick was not refused by its own code';
    end if;
    v_r := cmd.sea_choose(v_vy, v_pick);
    v_read := world.sea_choices();
    if (v_r->>'ok')::boolean is not true or (select c.chosen from public.sea_choices c where c.voyage_id = v_vy) <> v_pick
       or jsonb_array_length(v_read->'open') <> 1 or v_read->'open'->0->>'chosen' <> v_pick or v_read->'open'->0->>'best' is null
       or (v_read->'open'->0->>'id')::uuid <> v_vy then
      raise exception '0486 self-assert FAIL: the door did not take her pick, or the read does not serve it: % / %', v_r, left(v_read::text, 600);
    end if;
    perform cmd.assume_identity(c_ua);
    v_read := world.sea_choices();
    if jsonb_array_length(v_read->'recent') <> 2 or jsonb_array_length(v_read->'open') <> 0 then
      raise exception '0486 self-assert FAIL: her settled choices are not served as recent: %', left(v_read::text, 600);
    end if;
    if cmd.sea_choose(v_vy, v_pick)->>'error_code' is distinct from 'E_NO_CHOICE' then
      raise exception '0486 self-assert FAIL: another company''s choice was taken';
    end if;
    v_note := format('%s %s at LIS-%s: %s; left alone %s %s', (v_out->>'kind'), (v_out->>'option'), v_tocode, v_out->>'amount', v_back->>'option', v_back->>'amount');

    -- (g) SIGNED OUT: no company
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);
    if world.sea_choices() is distinct from '{"on": true, "company": false}'::jsonb then
      raise exception '0486 self-assert FAIL: lit and signed out, the read is not {"on": true, "company": false}';
    end if;
    raise exception using errcode = 'ZX486', message = 'PROBE_ROLLBACK_0486';
  exception when sqlstate 'ZX486' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0486 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0486' or p.auth_uid in (c_ua, c_ub))
     or exists (select 1 from public.sea_choices)
     or public.wc('sea_choices_enabled') is distinct from 'false'::jsonb or public.wc_num('sea_choices_chance') <> 0.35
     or public.current_player_id() is not null then
    raise exception '0486 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0486 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0486 self-assert ok: CHOICES AT SEA (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; two doors registered for authenticated alone, every core server only (service_role too); one table (RLS, no client grant); 8 knobs (sea_choices_enabled false). Probe (rolled back): dark nothing set; lit %. % ms.',
    (select count(*) from hunks_0486), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
