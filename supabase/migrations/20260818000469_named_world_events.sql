-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0469 - NAMED WORLD EVENTS: A FAMINE, A FESTIVAL, A BLOCKADE  (dark: the owner's switch world_events_enabled, false; lit, the server
--        names a few events a day at real harbours, each with a start and an end in real hours, and each moves that market)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/playable-2026-11-22.md P2 ("named world events (famine, blockade, festival) on the fair's rails"), and
--   docs/design/content-plan-2026-11.md item 8 ("Famine ... stands on city_wants"). docs/dev-log/2026-11-22-world-events.md.
--
-- THE RAILS (one authority per concept; nothing here is a second spelling of a rule that exists):
--   * WHAT AN EVENT IS: a row of public.buff_kinds (0026: "adding a kind of buff is a ROW"), off the calendar (season_seconds null:
--     "a buff some other rule awards"), so public.tick_buff_calendar never draws one.
--   * WHERE AND WHEN: a row of public.active_buffs (0026: a fact with a beginning and an end), at a HARBOUR (0036's trigger), with
--     source 'event:<slot>'. One writer: public.tick_world_events.
--   * WHAT IT DOES TO A PRICE, by kind:
--       FAMINE    effect WANT, food + grain: the city pays x2 for them (magnitude 100), up to world_event_want_cap_pct (25 %) of its
--                 stock target a want-period. 6 hours.
--       FESTIVAL  effect WANT, drink + gems + art: the city pays x1.75 (magnitude 75), the same cap. 4 hours.
--       BLOCKADE  effect TOLL: the port's published cut (world.spread) rises by 20 points of the price (magnitude 20): a buy there
--                 costs about 10 % more and a sale pays about 10 % less. 4 hours.
--     A WANT is the city wants' own rail (0255): world.want_left stays THE one reader of "what does this city pay over the price for
--     this good, and for how many units", so the quote's walk (world.quote_priced), the sale's tally (cmd.do_sell), the short
--     city's rule (0263), the market rows' `wanted` (world.market), the Trade cards' "Wanted x2" and every merchant house's sale
--     read it without one line of theirs changing. A famine's want is served beside the drawn want and the higher one is served.
--     A TOLL is read where the cut is published (world.spread), so every quote, trade and merchant house pays it.
--   * WHO HEARS: public.news_post, three news kinds (EVENT_FAMINE, EVENT_FESTIVAL, EVENT_BLOCKADE), world scope, importance 3:
--     posted the moment an event is named, an hour before it starts.
--
-- WHAT THIS FILE DOES:
--   1. THE SWITCH world_events_enabled (false, DARK) and six knobs (the slot, the chance, the most at once, the lead, the cap, the
--      keep). Dark nothing below writes, serves or moves anything (asserted: every harbour's cut and the want reader byte for byte).
--   2. buff_kinds: the effect list gains WANT and TOLL (each read below, in this file, as 0026 requires); a `categories` column
--      (the goods a WANT is for; null for every other effect); three rows, off the calendar.
--   3. public.world_events_on() (THE switch's one reader), public.want_mult_of(magnitude) (the one spelling of a WANT's multiple),
--      public.event_want(port, good) (lit, closed economy: the event's multiple and cap for that good now, or no row),
--      public.world_event_toll(port) (lit: buff_multiplier's TOLL fraction; dark 0).
--   4. public.tick_world_events(now): THE ONE writer. Dark null at once. Lit, once a slot (world_event_slot_seconds, 3,600): a draw
--      against world_event_chance (0.5); if fewer than world_event_max (3) events are running or announced, one kind and one
--      harbour (no harbour holds two; a WANT only where the quay shows at least 3 of its goods) are drawn from md5(slot), the event
--      starts world_event_lead_seconds (3,600) later, the market rows it wants get the want marker (port_goods.want_period, the
--      quote walk's "ask want_left" flag, only where it was never set), and the news is posted. Events ended more than
--      world_event_keep_hours (24) ago are deleted. A try-lock (never a wait) makes two callers in one slot name one.
--   5. HUNKS: public.tick_buff_calendar (1, its last line calls the tick: the byeharu-voyage:buff-calendar job (every 10 min), and
--      world.fleets and world.buffs, which wind it, so it runs in every world with or without a scheduler); world.want_left (1,
--      the event's want beside the drawn one, the higher served); world.spread (1, + the toll); world.buffs (1, the effects the
--      rules read: SPREAD, WANT, TOLL); public.client_rpc_entry_points (1, world.world_events).
--   6. world.world_events(): the client's one read. Stable. Dark {"on": false}. Lit, every event running or announced: kind, effect,
--      multiple or toll, categories, harbour, start, end, live.
-- NOT CHANGED: the Fair and its calendar, buff_multiplier, the quote walk, cmd.do_sell, the drawn wants, world.market's body, any
--   merchant house's rule, any price knob. The merchant houses react as they already do: their sales at a famine harbour read the
--   same want, their trades at a blockaded one pay the same cut.
-- ROWS (lit): at most one event a slot (an hour) at chance 0.5, ~0.5 an hour, steady about 2.8 running or announced (5 h average
--   span + 1 h lead), never more than 3: ONE active_buffs insert, ONE world_news insert and at most ~130 port_goods want-marker
--   updates (a famine at a large harbour, only rows never marked) per event; one delete per event a day later. ABOUT 0.02 INSERTS
--   AND UNDER 1.2 ROW UPDATES A MINUTE on average, all on the minute an event is named. Reads: one world_config read per
--   tick_buff_calendar call dark; lit one md5 and one probe of active_buffs (~60 rows); want_left one active_buffs index probe
--   per call (a market read's rows, a sale). Dark: one world_config read per call of each.
--   -- budget: none (no cron, no reschedule, no fillfactor, no autovacuum setting; the tick rides byeharu-voyage:buff-calendar)
--   -- retention: active_buffs event rows are deleted world_event_keep_hours (24) after they end; world_news keeps its own rule
-- LOCKS: CREATE OR REPLACE x5 by hunks; ALTER TABLE buff_kinds (one row; an ACCESS EXCLUSIVE lock for a moment, every quote reads it) for the check and the column; four new
--   functions, one read. TIME: a second. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, world_events_enabled false (the read answers {"on": false}, the want and the toll stop at
--   once, the tick writes nothing; rows already named stay inert until deleted). Full: a new migration reversing the five hunks
--   (OLD texts below verbatim), dropping the four functions and the read, the three kinds and news kinds, the column, the knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked functions' grants, volatility, definer, search
--   path, owner unmoved; the knobs; world.world_events registered for authenticated alone; the new functions private. DARK, BYTE
--   FOR BYTE: world.spread of every harbour and world.want_left of every Lisbon row equal their pre-image. THE PROBE (rolled back):
--   dark the tick writes nothing and the read is {"on": false}; lit a tick names one event in an unheld slot, starting an hour
--   later, with its news, and a second tick in the slot names none; at the most-at-once it names none; a running famine at Lisbon
--   serves x2 and a 25 % cap through want_left and doubles a sale's quote; a running blockade adds 0.20 to Lisbon's cut; the read
--   lists both; switched off, the want, the toll and the read are dark again at once. Proof 172 plays the job's path and the news.
-- VERSION: 0469 = prod head 0467 + 2 (0468 is another builder's and deploys first; this file reads none of its bodies, and its
--   hunks sit on lines 0468 is not written to cut: if one does, this file refuses at "occurs 0 time(s)" and is rebased).
-- news: none (dark: nothing changes for a player until the owner lights world_events_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.tick_buff_calendar(timestamp with time zone)', 'world.want_left(uuid,uuid)', 'world.spread(uuid)',
                                    'world.buffs(uuid)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.world_events_on()', 'public.want_mult_of(numeric)', 'public.event_want(uuid,uuid)',
                                    'public.world_event_toll(uuid)', 'public.tick_world_events(timestamp with time zone)', 'world.world_events()'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_spread0   text;
  v_want0     text;
  v_lis       uuid;
  v_food      uuid;
  v_target    numeric;
  v_dark_q    numeric;
  v_lit_q     numeric;
  v_qty       numeric;
  v_sp_dark   numeric;
  v_r         jsonb;
  v_slot      bigint;
  v_at        timestamptz;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'world_events_enabled')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'buff_kinds' and column_name = 'categories') then
    raise exception '0469 refuses: it has been applied once';
  end if;
  if to_regclass('public.buff_kinds') is null or to_regclass('public.active_buffs') is null or to_regclass('public.city_want_fills') is null
     or to_regprocedure('world.want_left(uuid,uuid)') is null or to_regprocedure('public.buff_multiplier(text,uuid,text,timestamp with time zone)') is null
     or to_regprocedure('public.news_post(text,uuid,uuid,uuid,text,text,jsonb)') is null or to_regprocedure('public.news_place(uuid)') is null
     or to_regprocedure('public.want_period(timestamp with time zone)') is null or to_regprocedure('public.economy_closed()') is null
     or to_regprocedure('world.houses_week()') is null then
    raise exception '0469 refuses: 0026 (buffs), 0255 (city wants), 0347 (news) or 0467 (the houses'' board) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select p.id into v_lis from public.ports p where p.code = 'LIS';
  -- what a player is quoted today: every harbour's published cut, and the want reader on every Lisbon row
  select md5(string_agg(p.code || '=' || coalesce(world.spread(p.id)::text, 'null'), ',' order by p.code)) into v_spread0
    from public.ports p where p.kind = 'HARBOUR';
  select md5(coalesce(string_agg(pg.good_id::text || '=' || coalesce((select w.mult::text || '/' || w.left_units::text from world.want_left(pg.port_id, pg.good_id) w), '-'), ',' order by pg.good_id), ''))
    into v_want0 from public.port_goods pg where pg.port_id = v_lis;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('world_events_enabled', 'false'::jsonb, '0469: THE SWITCH (the owner''s). true: the server names a famine, a festival or a blockade at a harbour now and then (public.tick_world_events, on the buff-calendar job), each a few real hours, and it moves that market (a famine''s and a festival''s want through world.want_left, a blockade''s toll through world.spread); world.world_events serves them. false: none named, none served, none acting (at once, even one already named).'),
    ('world_event_slot_seconds', '3600'::jsonb, '0469: how often the server may name a world event, in real seconds (one draw a slot).'),
    ('world_event_chance', '0.5'::jsonb, '0469: the chance a slot names an event (when fewer than world_event_max are running or announced).'),
    ('world_event_max', '3'::jsonb, '0469: the most world events running or announced at once, worldwide.'),
    ('world_event_lead_seconds', '3600'::jsonb, '0469: how long before it starts an event is named (in the news, on the map, on Trade).'),
    ('world_event_want_cap_pct', '0.25'::jsonb, '0469: the units a city buys at a famine''s or a festival''s price per want-period, as a fraction of its stock target of that good.'),
    ('world_event_keep_hours', '24'::jsonb, '0469: how long after it ends an event''s row is kept, then deleted by public.tick_world_events.');

  -- ── 3. WHAT AN EVENT IS: buff_kinds ──
  select c.conname into v_def from pg_constraint c
   where c.conrelid = 'public.buff_kinds'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%effect%' and pg_get_constraintdef(c.oid) like '%SPREAD%';
  if v_def is null then
    raise exception '0469 refuses: buff_kinds has no effect check to widen';
  end if;
  execute format('alter table public.buff_kinds drop constraint %I', v_def);
  alter table public.buff_kinds add constraint buff_kinds_effect_check check (effect in ('SPREAD', 'WANT', 'TOLL'));
  alter table public.buff_kinds add column categories text[];
  alter table public.buff_kinds add constraint buff_kinds_categories_check check ((effect = 'WANT') = (categories is not null and cardinality(categories) > 0));
  comment on column public.buff_kinds.categories is
    '0469: the goods.category values a WANT kind is for (a famine: food, grain). Null for every other effect.';
  comment on column public.buff_kinds.effect is
    'The ONE number this kind moves, and the direction is part of the effect''s meaning: SPREAD SHAVES the port''s published cut by '
    'magnitude_pct of itself (0026). WANT (0469): the city pays public.want_mult_of(magnitude_pct) times the price for goods of the '
    'kind''s categories, read through world.want_left. TOLL (0469): ADDS magnitude_pct points of the price to the port''s published cut '
    '(world.spread). Exactly one effect per kind.';
  insert into public.buff_kinds (code, name, subject_kind, effect, magnitude_pct, duration_seconds, season_seconds, chance_per_season, blurb, categories) values
    ('FAMINE', 'Famine', 'PORT', 'WANT', 100.00, 21600, null, null,
     'The harvest failed and the granaries are bare. The city pays double for food and grain brought in, for as long as it lasts.',
     array['food', 'grain']),
    ('FESTIVAL', 'Festival', 'PORT', 'WANT', 75.00, 14400, null, null,
     'The city keeps its feast days. Wine, fine things and jewels sell high while the streets are full.',
     array['drink', 'gems', 'art']),
    ('BLOCKADE', 'Blockade', 'PORT', 'TOLL', 20.00, 14400, null, null,
     'Warships lie off the harbour mouth. What still comes and goes pays dearly for the risk: buying here costs more and selling pays less.',
     null);

  -- ── 4. THE FUNCTIONS ──
  execute $f$
create function public.world_events_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0469: THE one reader of the switch world_events_enabled.
  select coalesce(public.wc('world_events_enabled') = 'true'::jsonb, false)
$body$
  $f$;
  execute $f$
create function public.want_mult_of(p_magnitude_pct numeric)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0469: THE one spelling of a WANT kind's multiple: magnitude 100 pays x2.
  select round(1 + p_magnitude_pct / 100.0, 2)
$body$
  $f$;
  execute $f$
create function public.event_want(p_port uuid, p_good uuid)
returns table (mult numeric, cap numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0469: a world event's want for this good at this harbour NOW: the multiple (the strongest running WANT whose categories hold the
  -- good) and the units a want-period it buys at it. No row dark, in an open economy (the city pays from its purse, as 0255's wants),
  -- or when no such event is running. Read only by world.want_left, THE one reader of a want.
  select public.want_mult_of(max(k.magnitude_pct)), round(public.wc_num('world_event_want_cap_pct') * max(pg.stock_target), 2)
    from public.active_buffs ab
    join public.buff_kinds k on k.code = ab.kind_code
    join public.goods g on g.id = p_good
    join public.port_goods pg on pg.port_id = p_port and pg.good_id = p_good
   where public.world_events_on() and coalesce(public.economy_closed(), false)
     and ab.subject_id = p_port and ab.starts_at <= now() and ab.ends_at > now()
     and k.subject_kind = 'PORT' and k.effect = 'WANT' and g.category = any (k.categories)
  having count(*) > 0
$body$
  $f$;
  execute $f$
create function public.world_event_toll(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0469: what a blockade ADDS to the port's published cut now, as a fraction of the price (0.20 = 20 points), through
  -- public.buff_multiplier (THE reading of what is running on a subject). 0 dark, so world.spread is 0026's to the digit.
  select case when public.world_events_on() then public.buff_multiplier('PORT', p_port, 'TOLL', now()) else 0::numeric end
$body$
  $f$;
  execute $f$
create function public.tick_world_events(p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0469: THE ONE writer of the world events. Called at the end of public.tick_buff_calendar (the buff-calendar job every 10 minutes, and
-- the reads that wind it). Dark: null at once, nothing read or written. Lit: once a slot, a draw; under the most-at-once, one kind and one
-- harbour drawn from the slot, named an hour ahead, with its news. Events ended more than world_event_keep_hours ago are deleted.
declare
  v_slot  bigint;
  v_key   text;
  v_u     numeric;
  v_n     int;
  v_gone  int := 0;
  v_marks int := 0;
  v_kind  public.buff_kinds%rowtype;
  v_port  uuid;
  v_start timestamptz;
  v_end   timestamptz;
  v_id    uuid;
  r       record;
begin
  if not public.world_events_on() then
    return null;
  end if;
  v_slot := floor(extract(epoch from p_at) / public.wc_num('world_event_slot_seconds'))::bigint;
  v_key  := 'event:' || v_slot;
  v_u    := ((('x' || substr(md5('world-event:' || v_slot), 1, 12))::bit(48)::bigint)::numeric / 281474976710656);
  if v_u >= public.wc_num('world_event_chance') then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'draw');
  end if;
  if exists (select 1 from public.active_buffs ab where ab.source = v_key) then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'held');
  end if;
  -- the most at once is read before any lock: a full world costs each caller one small count and nothing else
  select count(*)::int into v_n
    from public.active_buffs ab join public.buff_kinds k on k.code = ab.kind_code
   where k.season_seconds is null and ab.source like 'event:%' and ab.ends_at > p_at;
  if v_n >= public.wc_int('world_event_max') then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'full');
  end if;
  -- two callers in one slot (the job and a read) name one event: the second does not wait, it leaves it to the first
  if not pg_try_advisory_xact_lock(hashtext('byeharu-voyage:world-events')) then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'busy');
  end if;
  if exists (select 1 from public.active_buffs ab where ab.source = v_key) then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'held');
  end if;

  delete from public.active_buffs ab
   using public.buff_kinds k
   where k.code = ab.kind_code and k.season_seconds is null and ab.source like 'event:%'
     and ab.ends_at < p_at - make_interval(hours => public.wc_int('world_event_keep_hours'));
  get diagnostics v_gone = row_count;

  select * into v_kind from public.buff_kinds k
   where k.season_seconds is null and k.subject_kind = 'PORT' and k.effect in ('WANT', 'TOLL')
   order by md5(v_slot || ':kind:' || k.code), k.code
   limit 1;
  if not found then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'no kind', 'deleted', v_gone);
  end if;

  -- the harbour: in the slot's own order, the first that holds no event and, for a WANT, whose quay shows at least three of its goods
  -- (so the Trade cards carry the want); walked one harbour at a time and stopped at the first, so the usual cost is a few harbours
  for r in select p.id from public.ports p
            where p.kind = 'HARBOUR'
              and not exists (select 1 from public.active_buffs ab join public.buff_kinds k on k.code = ab.kind_code
                               where k.season_seconds is null and ab.subject_id = p.id and ab.source like 'event:%' and ab.ends_at > p_at)
            order by md5(v_slot || ':port:' || p.id::text), p.code
  loop
    if v_kind.effect <> 'WANT'
       or (select count(*) from (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id
                                  where pg.port_id = r.id and g.category = any (v_kind.categories) and public.quay_shows(pg.port_id, pg.good_id)
                                  limit 3) z) >= 3 then
      v_port := r.id;
      exit;
    end if;
  end loop;
  if v_port is null then
    return jsonb_build_object('slot', v_slot, 'named', false, 'why', 'no harbour', 'deleted', v_gone);
  end if;

  v_start := p_at + make_interval(secs => public.wc_num('world_event_lead_seconds'));
  v_end   := v_start + make_interval(secs => v_kind.duration_seconds);
  insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
  values (v_kind.code, v_port, null, v_start, v_end, v_key)
  returning id into v_id;

  if v_kind.effect = 'WANT' then
    -- the quote walk asks world.want_left only on a row that carries the marker (0255): set it where it was never set
    update public.port_goods pg set want_period = public.want_period(v_start)
      from public.goods g
     where pg.port_id = v_port and g.id = pg.good_id and g.category = any (v_kind.categories) and pg.want_period is null;
    get diagnostics v_marks = row_count;
  end if;

  perform public.news_post('EVENT_' || v_kind.code, v_port, null, null, null, 'world-event:' || v_id::text,
                           jsonb_build_object('words', jsonb_build_object('city', public.news_place(v_port)),
                                              'event', v_kind.code, 'starts_at', v_start, 'ends_at', v_end));

  return jsonb_build_object('slot', v_slot, 'named', true, 'kind', v_kind.code, 'port_id', v_port, 'starts_at', v_start, 'ends_at', v_end,
                            'marked', v_marks, 'deleted', v_gone);
end
$body$
  $f$;
  execute $f$
create function world.world_events()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0469: THE WORLD EVENTS, served: every event running or announced, soonest first. A row says the kind, its effect and what it is worth
-- (a WANT's multiple, a TOLL's points), the goods it is for, the harbour, its start and end, and whether it is on now. Nothing about who
-- trades there. Dark: {"on": false}.
declare
  v_now timestamptz := now();
begin
  if not public.world_events_on() then
    return jsonb_build_object('on', false);
  end if;
  return jsonb_build_object(
    'on', true,
    'now', v_now,
    'events', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', ab.id, 'code', k.code, 'effect', k.effect,
               'mult', case when k.effect = 'WANT' then public.want_mult_of(k.magnitude_pct) end,
               'toll_pct', case when k.effect = 'TOLL' then k.magnitude_pct end,
               'categories', coalesce(to_jsonb(k.categories), '[]'::jsonb),
               'port_id', p.id, 'port_code', p.code, 'port_name', p.name,
               'starts_at', ab.starts_at, 'ends_at', ab.ends_at, 'live', ab.starts_at <= v_now)
             order by ab.starts_at, p.code), '[]'::jsonb)
        from public.active_buffs ab
        join public.buff_kinds k on k.code = ab.kind_code
        join public.ports p on p.id = ab.subject_id
       where k.season_seconds is null and ab.source like 'event:%' and ab.ends_at > v_now));
end
$body$
  $f$;
  revoke all on function public.world_events_on() from public, anon, authenticated;
  revoke all on function public.want_mult_of(numeric) from public, anon, authenticated;
  revoke all on function public.event_want(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.world_event_toll(uuid) from public, anon, authenticated;
  revoke all on function public.tick_world_events(timestamptz) from public, anon, authenticated;
  grant execute on function public.tick_world_events(timestamptz) to service_role;
  revoke all on function world.world_events() from public, anon;
  grant execute on function world.world_events() to authenticated;

  -- ── 5. THE NEWS KINDS ──
  insert into public.news_kinds (kind, importance, scope, en, ko) values
    ('EVENT_FAMINE',   3, 'world', 'Famine in {city}',   '{city} 기근'),
    ('EVENT_FESTIVAL', 3, 'world', 'Festival in {city}', '{city} 축제'),
    ('EVENT_BLOCKADE', 3, 'world', 'Blockade of {city}', '{city} 봉쇄');

  -- ── 6. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0469 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0469 values
  ('public.tick_buff_calendar(timestamp with time zone)', 1,
$h$  return v_total;$h$,
$h$  perform public.tick_world_events(p_at);   -- 0469: the world events ride this job (null at once while dark)
  return v_total;$h$),
  ('world.want_left(uuid,uuid)', 1,
$h$  select w.mult, greatest(0, w.cap - coalesce(f.units, 0))
    from public.city_wants w
    left join public.city_want_fills f on f.port_id = w.port_id and f.good_id = w.good_id and f.period = w.period
   where public.wants_lit() and current_setting('byeharu.want_off', true) is distinct from 'on'   -- 0263: off for a short city's sale
     and w.period = public.want_period(now()) and w.port_id = p_port and w.good_id = p_good$h$,
$h$  select w.mult, greatest(0, w.cap - coalesce(f.units, 0))
    from (select d.mult, d.cap, d.period, d.port_id, d.good_id
            from (select c.mult, c.cap, c.period, c.port_id, c.good_id
                    from public.city_wants c
                   where public.wants_lit()
                     and c.period = public.want_period(now()) and c.port_id = p_port and c.good_id = p_good
                  union all   -- 0469: a world event's want (a famine, a festival), on this period's tally; none dark
                  select e.mult, e.cap, public.want_period(now()), p_port, p_good from public.event_want(p_port, p_good) e) d
           order by d.mult desc
           limit 1) w
    left join public.city_want_fills f on f.port_id = w.port_id and f.good_id = w.good_id and f.period = w.period
   where current_setting('byeharu.want_off', true) is distinct from 'on'   -- 0263: off for a short city's sale$h$),
  ('world.spread(uuid)', 1,
$h$         * (1 - public.buff_multiplier('PORT', p.id, 'SPREAD', now()))$h$,
$h$         * (1 - public.buff_multiplier('PORT', p.id, 'SPREAD', now()))
         -- ... and plus what a blockade adds to it (0469: points of the price; 0 dark)
         + public.world_event_toll(p.id)$h$),
  ('world.buffs(uuid)', 1,
$h$  v_read constant text[] := array['SPREAD'];$h$,
$h$  v_read constant text[] := array['SPREAD', 'WANT', 'TOLL'];   -- 0469: WANT (world.want_left) and TOLL (world.spread) are read$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'houses_week',           ''),$h$,
$h$      ('world',       'houses_week',           ''),
      -- 0469: the world events (dark: {"on": false})
      ('world',       'world_events',          ''),$h$);

  for v_h in select h.fn from hunks_0469 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0469 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0469 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0469 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0469 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0469 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 7. SELF-ASSERT: the catalog, the knobs, the door, dark byte for byte ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0469 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0469 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if public.wc('world_events_enabled') <> 'false'::jsonb or public.world_events_on() then
    raise exception '0469 self-assert FAIL: world_events_enabled is not false';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'world_events', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or exists (select 1 from unnest(c_new) u(q) where u.q <> 'world.world_events()' and has_function_privilege('authenticated', u.q::regprocedure, 'execute'))
     or (select p.provolatile from pg_proc p where p.oid = 'world.world_events()'::regprocedure) <> 's'
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0469 self-assert FAIL: world.world_events is not registered for authenticated alone, or a client reaches a server-only function';
  end if;
  if (select md5(string_agg(p.code || '=' || coalesce(world.spread(p.id)::text, 'null'), ',' order by p.code)) from public.ports p where p.kind = 'HARBOUR') <> v_spread0 then
    raise exception '0469 self-assert FAIL: dark, a harbour''s published cut moved';
  end if;
  if (select md5(coalesce(string_agg(pg.good_id::text || '=' || coalesce((select w.mult::text || '/' || w.left_units::text from world.want_left(pg.port_id, pg.good_id) w), '-'), ',' order by pg.good_id), ''))
        from public.port_goods pg where pg.port_id = v_lis) <> v_want0 then
    raise exception '0469 self-assert FAIL: dark, the want reader moved on a Lisbon row';
  end if;
  if exists (select 1 from public.buff_kinds k where k.code in ('FAMINE', 'FESTIVAL', 'BLOCKADE') and k.season_seconds is not null)
     or (select count(*) from public.buff_kinds k where k.code in ('FAMINE', 'FESTIVAL', 'BLOCKADE')) <> 3 then
    raise exception '0469 self-assert FAIL: an event kind is on the fair''s calendar, or one is missing';
  end if;

  -- ── 8. THE PROBE, rolled back by a raised sentinel ──
  begin
    select pg.good_id, pg.stock_target into v_food, v_target
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and g.category in ('food', 'grain') and pg.stock_target >= 40 and pg.stock > 0
     order by g.code limit 1;
    if v_food is null then
      raise exception '0469 self-assert FAIL: Lisbon keeps no food or grain to probe a famine with';
    end if;
    v_qty := least(10, floor(0.25 * v_target));
    -- the drawn wants out of the way, so the probe reads the event's want alone; a closed economy, as production
    delete from public.city_want_fills where port_id = v_lis and good_id = v_food;
    update public.world_config set value = 'false'::jsonb where key = 'city_wants';
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    update public.port_goods set want_period = coalesce(want_period, public.want_period(now())) where port_id = v_lis and good_id = v_food;
    select q.avg_price into v_dark_q from world.quote(v_lis, v_food, v_qty, 'sell', null, null) q;
    v_sp_dark := world.spread(v_lis);

    -- DARK: nothing named, nothing served, nothing acting
    if public.tick_world_events(now()) is not null or exists (select 1 from public.active_buffs ab where ab.source like 'event:%') then
      raise exception '0469 self-assert FAIL: dark, the tick named an event';
    end if;
    if world.world_events() <> '{"on": false}'::jsonb then
      raise exception '0469 self-assert FAIL: dark, the read served %', world.world_events();
    end if;
    insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source) values
      ('FAMINE',   v_lis, null, now() - interval '1 minute', now() + interval '1 hour', 'event:probe-0469'),
      ('BLOCKADE', v_lis, null, now() - interval '1 minute', now() + interval '1 hour', 'event:probe-0469b');
    if exists (select 1 from world.want_left(v_lis, v_food)) or world.spread(v_lis) <> v_sp_dark then
      raise exception '0469 self-assert FAIL: dark, a named event acted (want or toll)';
    end if;

    -- LIT: a running famine and blockade at Lisbon act
    update public.world_config set value = 'true'::jsonb where key = 'world_events_enabled';
    if (select count(*) from world.want_left(v_lis, v_food)) <> 1
       or (select w.mult from world.want_left(v_lis, v_food) w) <> 2.00
       or (select w.left_units from world.want_left(v_lis, v_food) w) <> round(0.25 * v_target, 2) then
      raise exception '0469 self-assert FAIL: lit, the famine''s want is not x2 for 25 %% of the target: %', (select jsonb_agg(to_jsonb(w)) from world.want_left(v_lis, v_food) w);
    end if;
    select q.avg_price into v_lit_q from world.quote(v_lis, v_food, v_qty, 'sell', null, null) q;
    if v_dark_q is null or v_lit_q is null or v_lit_q < v_dark_q * 1.5 then
      raise exception '0469 self-assert FAIL: lit, a sale of % at the famine is not priced up (dark %, lit %)', v_qty, v_dark_q, v_lit_q;
    end if;
    if abs(world.spread(v_lis) - (v_sp_dark + 0.20)) > 0.000001 then
      raise exception '0469 self-assert FAIL: lit, the blockade did not add 0.20 to the cut (dark %, lit %)', v_sp_dark, world.spread(v_lis);
    end if;
    v_r := world.world_events();
    if (v_r ->> 'on')::boolean is not true or jsonb_array_length(v_r -> 'events') < 2
       or not exists (select 1 from jsonb_array_elements(v_r -> 'events') e where e ->> 'code' = 'FAMINE' and (e ->> 'mult')::numeric = 2 and (e ->> 'live')::boolean and e ->> 'port_code' = 'LIS')
       or not exists (select 1 from jsonb_array_elements(v_r -> 'events') e where e ->> 'code' = 'BLOCKADE' and (e ->> 'toll_pct')::numeric = 20) then
      raise exception '0469 self-assert FAIL: lit, the read does not list both: %', v_r;
    end if;

    -- the tick: in a slot nobody holds, at chance 1 and room for one more, it names one event an hour ahead, with its news
    update public.world_config set value = '1'::jsonb where key = 'world_event_chance';
    update public.world_config set value = '3'::jsonb where key = 'world_event_max';
    v_at   := '2099-01-01 00:30:00+00';
    v_slot := floor(extract(epoch from v_at) / 3600)::bigint;
    v_r := public.tick_world_events(v_at);
    if (v_r ->> 'named')::boolean is not true
       or (select count(*) from public.active_buffs ab where ab.source = 'event:' || v_slot) <> 1
       or (select ab.starts_at from public.active_buffs ab where ab.source = 'event:' || v_slot) <> v_at + interval '1 hour'
       or not exists (select 1 from public.active_buffs ab join public.ports p on p.id = ab.subject_id where ab.source = 'event:' || v_slot and p.kind = 'HARBOUR')
       or not exists (select 1 from public.world_news w join public.active_buffs ab on w.key = 'world-event:' || ab.id::text
                       where ab.source = 'event:' || v_slot and w.kind = 'EVENT_' || ab.kind_code and w.port_id = ab.subject_id and w.scope = 'world') then
      raise exception '0469 self-assert FAIL: lit, the tick did not name one event an hour ahead with its news: %', v_r;
    end if;
    if (public.tick_world_events(v_at + interval '10 minutes') ->> 'named')::boolean
       or (select count(*) from public.active_buffs ab where ab.source like 'event:' || v_slot || '%') <> 1 then
      raise exception '0469 self-assert FAIL: lit, a second tick in the slot named another event';
    end if;
    -- at the most at once (one, the one named, still announced or running an hour later): the next slot names none
    update public.world_config set value = '1'::jsonb where key = 'world_event_max';
    if (public.tick_world_events(v_at + interval '1 hour') ->> 'named')::boolean then
      raise exception '0469 self-assert FAIL: lit, the tick named an event past world_event_max';
    end if;
    v_note := format('; named %s at %s', v_r ->> 'kind', (select p.code from public.ports p where p.id = (v_r ->> 'port_id')::uuid));

    -- SWITCHED OFF: dark again at once, with the rows still there
    update public.world_config set value = 'false'::jsonb where key = 'world_events_enabled';
    if exists (select 1 from world.want_left(v_lis, v_food)) or world.spread(v_lis) <> v_sp_dark or world.world_events() <> '{"on": false}'::jsonb then
      raise exception '0469 self-assert FAIL: switched off, an event still acts or is served';
    end if;
    raise exception sqlstate 'BV469';
  exception when sqlstate 'BV469' then null;
  end;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0469 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0469 self-assert ok: NAMED WORLD EVENTS (dark). % hunks once each and reversing; grants and volatility unmoved; no other function moved; world_events_enabled false; world.world_events registered for authenticated alone; dark byte for byte (every harbour''s cut, every Lisbon want); probe: dark nothing named or acting, lit a famine x2 / 25 %% cap and a sale priced up, a blockade +0.20 on the cut, the read lists them, one event a slot with its news, none past the most-at-once, off dark at once%; % ms.',
    (select count(*) from hunks_0469), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0469;
end $m$;
