-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0318 — A HOUSE HAS A REGARD: how a country stands with one company, kept as earned points that fade. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner row 288, slice W1 of docs/WORLD_POWERS.md (section 2.1): *"we need to build systems such as affinity prior to the system"*. It comes before anything fights. The word in the database
-- is REGARD, because `affinity`, `stance` and `standings` are taken. The player reads the existing Relationship / 관계.
--
-- WHAT THIS FILE ADDS, ALL DARK (`regard_enabled` false):
--   public.house_regard (player, nation, points, as_of): only EARNED points are stored, so a merchant has no row and pays no cost.
--   public.regard_of        THE one reader: stance base + points × 0.5 ^ (hours since as_of / regard_half_life_hours). Fades with no job and no beat cost.
--   public.regard_add       THE one writer: folds the fade in, adds, writes event REGARD_CHANGED. Dark, a merchant, a free city or a zero delta: writes nothing.
--   public.regard_band      THE bands, from one knob. The score is rounded first, so the band always agrees with the whole number the player reads.
--   public.regard_factor    THE multiplier on country_factor's result. Dark, a merchant, a free city: 1, before any row of house_regard is read.
--   public.regard_line      The hall's line, inside `dues`: {score, band, factor, fine}. Dark, a merchant, a free city: not served at all.
--   public.regard_gift      A gift or a stake in a city a country holds: +regard_per_100k per 100,000 d. Hooked in public.donate_for and public.invest_for.
--   public.fine_owed, public.fine_for, cmd.pay_fine   FINE: player to that country's capital, through public.pay_city. A MOVED kind.
--
-- THE HUNKS, each occurs once and reverses to its pre-image:
--   world.tax_rate(uuid,uuid), public.port_fee, public.port_dues (2), public.donate_for, public.invest_for, public.client_rpc_entry_points (the door's row in the registry).
--   NOT world.town_hall: 0317 cuts hunks there. The hall already concatenates public.port_dues, so the line reaches it with no hunk, and the board's `dues` carries the same line.
--   NOT world.report or world.books: an unknown kind already lands in 'other', worded 'Fine'.
--
-- DARK IS BYTE-IDENTICAL: public.regard_factor answers the integer 1, so numeric × 1 keeps its value and its scale. The dark path costs one world_config read per quote. No row is read.
--
-- NOT HERE, on purpose: the attack, sink and pirate rows of section 2.1. Those events do not exist yet; W11 and W19 hook them. Nothing in this file lets a player attack anything.
-- The no-PvP law stands.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - The gift hook is in this slice: section 2.1 prices it, it can happen today, and no later slice names it. Without it `regard_add` would have no caller but the fine.
--   - A FINE IS A WAY BACK, NOT A WAY UP. It buys back earned bad points only (points < 0), never the stance base, so it cannot lift a company above where she stood. Without this limit
--     a fine at 200 d. a point is 50 × cheaper than a donation (10,000 d. a point) and Honoured costs 100,000 d. Paid at that country's capital, a fleet docked there, as Donate.
--     What she asks is held to what is owed and what her purse holds, so a stale button never refuses for a fade that happened after the read.
--   - A fine buys no influence: public.pay_city counts SHARE and DONATION only.
--   - tariff_rate_max still caps the rate, on top of the multiplier: the cap is the owner's and a Hostile company at war can meet it. The dock fee has no cap.
--
-- LIT, ON DAY ONE, WITH NO ROW WRITTEN (the owner's switch, not this file): the stance base alone sets a band. Home +200 is Friendly (× 0.9) and war -200 is Wary (× 1.25) for every company.
--
-- SELF-ASSERT: the catalog and the pure band table only: hunks once and reversing; ACL, volatility and config unmoved; no other function and no other knob; no row. THIS FILE RUNS NO GAME STEP,
-- in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 27, scripts/db/proofs/27_regard.sql, and tests/rpc.regard.spec.ts for the seam.
-- Mutation controls: scripts/ops/harness/regard/proof-0318.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `regard_enabled` false is the switch. To remove: swap this file's v_old and v_new, then drop what it created. FINE ledger rows stay.
-- VERSION: 0318 - prod head 0315 (2026-11-06); 0316 (#499) and 0317 (#505) deploy first. Neither touches a function hunked here (read, 2026-11-06).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_words_before text;
  v_meta_before  text;
  c_new_fns constant text[] := array[
    'public.regard_on()', 'public.regard_fold(numeric,timestamp with time zone)', 'public.regard_of(uuid,uuid)', 'public.regard_band(numeric)',
    'public.regard_factor(uuid,uuid)', 'public.regard_add(uuid,uuid,numeric,text)', 'public.regard_gift(uuid,uuid,bigint,text)', 'public.regard_line(uuid,uuid)',
    'public.fine_owed(uuid,uuid)', 'public.fine_for(uuid,uuid,bigint)', 'cmd.pay_fine(uuid,bigint)'];
  c_hunked constant text[] := array[
    'world.tax_rate(uuid,uuid)', 'public.port_fee(uuid,uuid,numeric)', 'public.port_dues(uuid,uuid,numeric)', 'public.donate_for(uuid,uuid,bigint)', 'public.invest_for(uuid,uuid,text,integer)',
    'public.client_rpc_entry_points()'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.house_regard') is not null or to_regprocedure('public.regard_of(uuid,uuid)') is not null
     or exists (select 1 from public.world_config c where c.key like 'regard%')
     or exists (select 1 from public.stats_flow_words w where w.kind = 'FINE') then
    raise exception '0318 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.country_factor(text)') is null or to_regprocedure('public.power_stance(uuid,uuid)') is null or to_regprocedure('public.city_capital(uuid)') is null then
    raise exception '0318 refuses: 0172 / 0196 / 0237 (the capital, the stance, the country factor) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_words_before
    from public.stats_flow_words w;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 1. THE TABLE ──
  create table public.house_regard (
    player_id uuid        not null references public.players(id) on delete cascade,
    nation_id uuid        not null references public.nations(id),
    points    numeric     not null,
    as_of     timestamptz not null default now(),
    primary key (player_id, nation_id)
  );
  comment on table public.house_regard is
    '0318 (docs/WORLD_POWERS.md section 2.1): what a human company has EARNED with a country, as it stood at as_of. The stance base is derived, so a merchant has no row. One reader: public.regard_of. One writer: public.regard_add. Server-only.';
  alter table public.house_regard enable row level security;
  revoke all on table public.house_regard from public, anon, authenticated;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('regard_enabled', 'false'::jsonb, '0318: THE switch of a company''s regard with a country. False: multiplier 1, regard_add writes nothing, the hall serves no line, cmd.pay_fine refuses E_NOT_IN_USE.'),
    ('regard_half_life_hours', '72'::jsonb, '0318: earned regard halves in this many real hours (public.regard_fold).'),
    ('regard_stance_base', '{"home": 200, "ally": 100, "peace": 0, "rival": -100, "war": -200}'::jsonb, '0318: the score a company starts from with a country, by public.power_stance. Derived, never stored.'),
    ('regard_bands', '[{"band": "honoured", "from": 500, "factor": 0.8}, {"band": "friendly", "from": 150, "factor": 0.9}, {"band": "neutral", "from": -149, "factor": 1}, {"band": "wary", "from": -299, "factor": 1.25}, {"band": "hostile", "from": null, "factor": 2}]'::jsonb,
     '0318: the bands, highest first. The score is rounded, then the first band whose `from` it reaches applies; null `from` catches the rest. `factor` multiplies tax and dock fee.'),
    ('regard_per_100k', '10'::jsonb, '0318: regard earned per 100,000 d. given to or invested in a city that country holds.'),
    ('regard_fine_per_point', '200'::jsonb, '0318: ducats a fine costs per point of bad regard bought back.');

  -- ── 3. THE MONEY KIND ──
  insert into public.stats_flow_words (kind, side, word, ord) values ('FINE', 'moved', 'Fines', 48);

  -- ── 4. THE READERS ──
  execute $f$
create function public.regard_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0318: THE one reader of regard_enabled.
  select public.wc('regard_enabled') = 'true'::jsonb
$$
  $f$;

  execute $f$
create function public.regard_fold(p_points numeric, p_as_of timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0318: THE one fade: earned points as they stand now. Bounded at 1,000 half-lives so a very old row reads as nothing and never underflows. A future as_of does not grow.
  select p_points * power(0.5::numeric,
           least(greatest(extract(epoch from now() - p_as_of) / 3600, 0)::numeric / public.wc_num('regard_half_life_hours'), 1000)::numeric)
$$
  $f$;

  execute $f$
create function public.regard_of(p_player uuid, p_nation uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0318: THE one reader of a company's regard with a country: the stance base (public.power_stance through regard_stance_base) plus her earned points, faded. One primary-key read of each table.
-- A stance the knob does not price RAISES (a defect, never a silent 0).
declare
  v_stance text := public.power_stance((select pl.nation_id from public.players pl where pl.id = p_player), p_nation);
  v_base   numeric := (public.wc('regard_stance_base') ->> v_stance)::numeric;
begin
  if v_base is null then
    raise exception 'E_NO_REGARD_BASE: regard_stance_base does not price the stance "%"', coalesce(v_stance, '') using errcode = 'P0001';
  end if;
  return v_base + coalesce((select public.regard_fold(r.points, r.as_of) from public.house_regard r
                             where r.player_id = p_player and r.nation_id = p_nation), 0);
end $$
  $f$;

  execute $f$
create function public.regard_band(p_score numeric)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0318: THE bands: {band, from, factor}. The score is rounded first, so -149.5 is the -150 the player reads, and Wary.
  select b.value from jsonb_array_elements(public.wc('regard_bands')) with ordinality b(value, ord)
   where b.value ->> 'from' is null or round(p_score) >= (b.value ->> 'from')::numeric
   order by b.ord limit 1
$$
  $f$;

  execute $f$
create function public.regard_factor(p_player uuid, p_port uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0318: THE multiplier a company's regard puts on country_factor's result, in world.tax_rate and public.port_fee. Dark, a merchant, a free city: 1, before any read of public.house_regard.
declare
  v_nation uuid;
begin
  if not public.regard_on() or p_player is null then
    return 1;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 1;
  end if;
  v_nation := public.port_nation(p_port);
  if v_nation is null then
    return 1;
  end if;
  return (public.regard_band(public.regard_of(p_player, v_nation)) ->> 'factor')::numeric;
end $$
  $f$;

  execute $f$
create function public.fine_owed(p_player uuid, p_nation uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0318: what a company may pay this country: her earned BAD points as they stand now, at regard_fine_per_point, rounded up to a whole point. Never the stance base. 0 with none.
  select coalesce((select ceil(-x.p)::bigint * public.wc_int('regard_fine_per_point')
                     from (select public.regard_fold(r.points, r.as_of) as p from public.house_regard r
                            where r.player_id = p_player and r.nation_id = p_nation) x
                    where x.p < 0), 0)::bigint
$$
  $f$;

  execute $f$
create function public.regard_line(p_port uuid, p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0318: one term of public.port_dues: {regard: {score, band, factor, fine}}. `fine` is what she may pay here: only at that country's capital, else 0. Dark, a merchant, a free city: {}.
declare
  v_nation uuid;
  v_score  numeric;
  v_band   jsonb;
begin
  if not public.regard_on() or p_player is null then
    return '{}'::jsonb;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return '{}'::jsonb;
  end if;
  v_nation := public.port_nation(p_port);
  if v_nation is null then
    return '{}'::jsonb;
  end if;
  v_score := public.regard_of(p_player, v_nation);
  v_band := public.regard_band(v_score);
  return jsonb_build_object('regard', jsonb_build_object(
    'score', round(v_score), 'band', v_band ->> 'band', 'factor', (v_band ->> 'factor')::numeric,
    'fine', case when public.city_capital(p_port) = p_port then public.fine_owed(p_player, v_nation) else 0 end));
end $$
  $f$;

  -- ── 5. THE WRITERS ──
  execute $f$
create function public.regard_add(p_player uuid, p_nation uuid, p_delta numeric, p_reason text)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0318: THE one writer of public.house_regard. Folds the fade in, adds, stamps as_of, writes event REGARD_CHANGED, answers the score. Dark, a merchant, no nation, no delta: writes nothing, answers null.
declare
  v_score numeric;
begin
  if not public.regard_on() or p_player is null or p_nation is null or coalesce(p_delta, 0) = 0 then
    return null;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return null;
  end if;
  insert into public.house_regard as r (player_id, nation_id, points, as_of)
  values (p_player, p_nation, p_delta, now())
  on conflict (player_id, nation_id) do update
     set points = public.regard_fold(r.points, r.as_of) + excluded.points, as_of = excluded.as_of;
  v_score := public.regard_of(p_player, p_nation);
  perform public.emit_event(p_player, 'REGARD_CHANGED', jsonb_build_object(
    'nation', (select n.code from public.nations n where n.id = p_nation),
    'delta', round(p_delta, 2), 'reason', p_reason, 'score', round(v_score), 'band', public.regard_band(v_score) ->> 'band'));
  return v_score;
end $$
  $f$;

  execute $f$
create function public.regard_gift(p_player uuid, p_port uuid, p_coin bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0318: a gift or a stake in a city earns regard with the country that holds it (regard_per_100k). Called by public.donate_for and public.invest_for, which merchants share: public.regard_add turns them away.
begin
  if not public.regard_on() then
    return;
  end if;
  perform public.regard_add(p_player, public.port_nation(p_port), p_coin * public.wc_num('regard_per_100k') / 100000, p_reason);
end $$
  $f$;

  execute $f$
create function public.fine_for(p_player uuid, p_port uuid, p_coin bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0318: THE one way a company pays a fine (docs/WORLD_POWERS.md sections 2.1, 4.5). At the capital of the country she owes, with a fleet docked there. She pays what she asked, held to what is owed
-- and what her purse holds. FINE is moved: public.pay_city, house to capital, nothing made. +1 regard per regard_fine_per_point. Refuses before anything moves. Server-only.
declare
  p       public.ports%rowtype;
  v_nat   uuid;
  v_per   bigint := public.wc_int('regard_fine_per_point');
  v_have  bigint;
  v_owed  bigint;
  v_pay   bigint;
  v_event uuid;
  v_after bigint;
  v_score numeric;
begin
  if not public.regard_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'fines are not in use');
  end if;
  select x.* into p from public.ports x where x.id = p_port;
  if p.id is null or p.kind <> 'HARBOUR' then
    perform cmd.refuse('E_NOT_FOUND', 'there is no such harbour');
  end if;
  v_nat := public.port_nation(p_port);
  if v_nat is null or public.city_capital(p_port) is distinct from p_port then
    perform cmd.refuse('E_NOT_A_CAPITAL', format('%s is not a capital: a fine is paid at the capital', p.name));
  end if;
  if not exists (select 1 from public.fleets f where f.player_id = p_player and f.status = 'DOCKED' and f.port_id = p_port) then
    perform cmd.refuse('E_NOT_DOCKED', 'dock a fleet here to pay a fine');
  end if;
  -- 0122's ONE LOCK ORDER: the house's row first, then the city's.
  select pl.ducats into v_have from public.players pl where pl.id = p_player for update;
  v_owed := public.fine_owed(p_player, v_nat);
  if v_owed <= 0 then
    perform cmd.refuse('E_NO_FINE', format('you owe %s no fine', p.name));
  end if;
  v_pay := least(greatest(coalesce(p_coin, 0), 0), v_owed, coalesce(v_have, 0));
  if v_pay < v_per then
    perform cmd.refuse('E_FINE_MIN', format('the smallest fine is %s coin', v_per),
                       cmd.figures(greatest(v_pay, 0), v_per, 'ducats'));
  end if;
  v_event := public.emit_event(p_player, 'FINE_PAID', jsonb_build_object(
               'port', p.code, 'port_name', p.name, 'amount', v_pay,
               'nation', (select n.code from public.nations n where n.id = v_nat)));
  v_after := public.pay_city(p_player, p_port, 'FINE', v_pay, v_event);
  v_score := public.regard_add(p_player, v_nat, v_pay::numeric / v_per, 'FINE');
  return jsonb_build_object('ok', true, 'port', p.code, 'amount', v_pay, 'purse', v_after,
                            'score', round(v_score), 'band', public.regard_band(v_score) ->> 'band',
                            'owed', public.fine_owed(p_player, v_nat));
end $$
  $f$;

  execute $f$
create function cmd.pay_fine(p_port uuid, p_coin bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0318: the caller's company pays a fine at p_port. The core is public.fine_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  perform voyage.settle(f.id) from public.fleets f where f.player_id = v_player and f.status = 'SAILING';
  begin
    return public.fine_for(v_player, p_port, p_coin);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  revoke all on function public.regard_on() from public, anon, authenticated;
  revoke all on function public.regard_fold(numeric, timestamptz) from public, anon, authenticated;
  revoke all on function public.regard_of(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.regard_band(numeric) from public, anon, authenticated;
  revoke all on function public.regard_factor(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.regard_add(uuid, uuid, numeric, text) from public, anon, authenticated;
  revoke all on function public.regard_gift(uuid, uuid, bigint, text) from public, anon, authenticated;
  revoke all on function public.regard_line(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.fine_owed(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.fine_for(uuid, uuid, bigint) from public, anon, authenticated;
  revoke all on function cmd.pay_fine(uuid, bigint) from public, anon;
  grant execute on function cmd.pay_fine(uuid, bigint) to authenticated;

  -- ── 6. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0318 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0318 values
  ('world.tax_rate(uuid,uuid)', 1,
$h$    return least(v_base * public.country_factor(v_stance), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$,
$h$    -- 0318 (docs/WORLD_POWERS.md section 2.1): her regard with the holder sits on the country factor, under the same cap. 1 while dark, for a merchant and in a free city.
    return least(v_base * public.country_factor(v_stance) * public.regard_factor(p_player, p_port), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$),
  ('public.port_fee(uuid,uuid,numeric)', 1,
$h$                               (select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))))::bigint;
$h$,
$h$                               (select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))
                           * public.regard_factor(p_player, p_port)))::bigint;   -- 0318: 1 while dark, for a merchant and in a free city. She still docks, whatever her band
$h$),
  ('public.port_dues(uuid,uuid,numeric)', 1,
$h$    'stance', v_stance, 'factor', public.country_factor(v_stance),
$h$,
$h$    'stance', v_stance, 'factor', public.country_factor(v_stance) * public.regard_factor(p_player, p_port),   -- 0318: the factor she really pays
$h$),
  ('public.port_dues(uuid,uuid,numeric)', 2,
$h$    'prep_seconds', public.wc_num('port_prep_seconds')));
$h$,
$h$    'prep_seconds', public.wc_num('port_prep_seconds')) || public.regard_line(p_port, p_player));   -- 0318: served only while lit
$h$),
  ('public.donate_for(uuid,uuid,bigint)', 1,
$h$  v_after := public.pay_city(p_player, p_port, 'DONATION', p_coin, v_event);
$h$,
$h$  v_after := public.pay_city(p_player, p_port, 'DONATION', p_coin, v_event);
  perform public.regard_gift(p_player, p_port, p_coin, 'DONATION');   -- 0318: dark, nothing
$h$),
  ('public.invest_for(uuid,uuid,text,integer)', 1,
$h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
$h$,
$h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
  perform public.regard_gift(p_player, p_port, v_cost, 'SHARE');   -- 0318: dark, nothing
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'donate',                'uuid, bigint'),
$h$,
$h$      ('cmd',         'donate',                'uuid, bigint'),
      ('cmd',         'pay_fine',              'uuid, bigint'),
$h$);

  for v_h in select h.fn from hunks_0318 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0318 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0318 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0318 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0318 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0318 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 7. THE SELF-ASSERT: the catalog and the pure band table. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0318 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not like 'regard%') <> v_cfg_before then
    raise exception '0318 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> 'FINE') <> v_words_before then
    raise exception '0318 self-assert FAIL: a money word moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0318 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if public.regard_on() then
    raise exception '0318 self-assert FAIL: regard is not dark';
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'FINE') <> 'moved' then
    raise exception '0318 self-assert FAIL: FINE is not a moved kind';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute')
                 or (has_function_privilege('authenticated', f::regprocedure, 'execute') <> (f = 'cmd.pay_fine(uuid,bigint)'))) then
    raise exception '0318 self-assert FAIL: the grants are not the contract: only cmd.pay_fine, only to authenticated';
  end if;
  if exists (select 1 from (values (500::numeric, 'honoured'), (499.5, 'honoured'), (499.4, 'friendly'), (150, 'friendly'), (149.5, 'friendly'), (149.4, 'neutral'), (0, 'neutral'), (-149, 'neutral'),
                                   (-149.4, 'neutral'), (-149.5, 'wary'), (-150, 'wary'), (-299, 'wary'), (-299.4, 'wary'), (-299.5, 'hostile'), (-300, 'hostile'), (-100000, 'hostile')) t(score, band)
              where public.regard_band(t.score) ->> 'band' is distinct from t.band) then
    raise exception '0318 self-assert FAIL: a band is not where section 2.1 puts it';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'pay_fine' and e.fn is not null) <> 1 then
    raise exception '0318 self-assert FAIL: cmd.pay_fine is not in the client registry';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0318 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0318 self-assert ok: A HOUSE HAS A REGARD, dark. % hunks once each and reversing; no other function, no other knob; no game step ran (proof 27 runs them in CI). % ms.',
    (select count(*) from hunks_0318), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0318;
end
$m$;
