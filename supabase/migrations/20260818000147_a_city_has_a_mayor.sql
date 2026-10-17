-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0147 — A CITY HAS A MAYOR  (docs/INFLUENCE.md slice I5)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- O3 (2026-10-17): rewards for leading a city — a city Mayor and cheaper trade (and fame and
-- dividends, I6). O4 (2026-10-15, docs/ECONOMY_LOOP.md §11): "later the rate will be set by the
-- city's mayor = its highest investor (within 0–20 %)" — world.tax_rate is where it plugs in.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.port_mayor(port, player, since, tax_rate, tax_set_at). Written by tick_influence's step
--     4 (the person) and cmd.set_tax (the rate) alone.
-- (2) tick_influence step 4 MAYOR (D8 + A2): in every city a country holds — home cities included —
--     the mayor is the company that has given the most there FOR THAT COUNTRY and sails for it NOW
--     (a company that changed country leaves its mayorship behind); ties: the earlier giver. A new
--     mayor starts from the city's own rate (tax_rate null). A city nobody of its country has given
--     to has no mayor. Counted in the receipt (`mayors`, `new_mayors`).
-- (3) cmd.set_tax(port, rate) — the mayor sets the city's profit tax within 0–tax_rate_max (O4),
--     once a real day (Origin's rule); from anywhere (an office, not cargo). Refuses E_NOT_MAYOR,
--     E_TAX_BAND, E_ONCE_A_DAY. Registered. A merchant mayor never calls it.
-- (4) world.tax_rate(port, player default null) — THE one tax authority, generalised: lit, the
--     mayor's rate when the race is on and one is set, else the city's (0122's line, unchanged);
--     halved (influence_citizen_tax_cut 0.5, D9) for a company of the country that holds the city,
--     while the race is on. The one-argument form is dropped (two overloads with a default would be
--     an ambiguous call); every caller that names no company still resolves, and reads the city's
--     base rate. public.profit_tax gains the seller the same way; cmd.do_sell passes the seller and
--     public.npc_leg_lines the merchant (so merchants also prefer to sell where their country leads).
--     PL/pgSQL (PG 17 re-plans SQL bodies per call: both are on the selling path).
-- (5) world.town_hall_influence serves `mayor` {name, merchant, since, tax_rate} and `you.tax_rate`
--     (your rate here) and `you.mayor`.
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * The mayor's rate counts only while the race is lit — influence_switch(false) puts every
--   consequence back (docs/INFLUENCE.md §7).
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- (a) world.tax_rate / public.profit_tax with no company equal their pre-images at every harbour,
--     dark and lit; with a company, dark (race off) too. (b) The re-cuts reverse to their
--     pre-images; ACLs carried. (c) Lit, on probe rows: the mayor is the holder's top giver, not a
--     richer foreigner nor a former citizen; set_tax refuses a non-mayor, 0.21 and a second same-day
--     call; the mayor's rate is the city's; a citizen pays half the profit tax on a probe sale and a
--     foreigner pays it all. Timings: raise notice only.
--
-- ROLLBACK: influence_switch(false) (the mayor's rate and the halving stop at once).
-- SUPERSEDES, by hunks sliced from the LIVE bodies: public.tick_influence (0146),
-- world.town_hall_influence (0146), cmd.do_sell (0122), public.npc_leg_lines (0129),
-- public.client_rpc_entry_points (0144); world.tax_rate and public.profit_tax re-created with one
-- more (defaulted) argument. VERSION: 0147. Applies on 0146.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0147(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0147 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.tick_influence(timestamp with time zone)'),
               ('world.town_hall_influence(uuid, uuid)'),
               ('cmd.do_sell(uuid, jsonb)'),
               ('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'),
               ('public.client_rpc_entry_points()')) f(fn);

-- the answers the parity proof compares: every harbour, dark and lit, with no company
create temp table pre_0147 on commit drop as
select p.id as port_id, false as lit, world.tax_rate(p.id)::text as rate, public.profit_tax(p.id, 1000)::text as tax
  from public.ports p where p.kind = 'HARBOUR';
do $$
declare
  v_was jsonb := (select value from public.world_config where key = 'city_treasury_enabled');
begin
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  insert into pre_0147
  select p.id, true, world.tax_rate(p.id)::text, public.profit_tax(p.id, 1000)::text from public.ports p where p.kind = 'HARBOUR';
  update public.world_config set value = v_was where key = 'city_treasury_enabled';
end $$;

-- the grants the two re-created functions carry over
create temp table grants_0147 on commit drop as
select f.fn, a.grantee, a.privilege_type
  from (values ('world.tax_rate(uuid)'), ('public.profit_tax(uuid, numeric)')) f(fn)
  join pg_proc p on p.oid = f.fn::regprocedure
  cross join lateral aclexplode(p.proacl) a
 where a.grantee <> p.proowner;

-- ── 1. THE KNOB AND THE OFFICE ─────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('influence_citizen_tax_cut', to_jsonb(0.5),
   '0147 (D9): the share of the profit tax a company of the country that holds a city is spared there.')
on conflict (key) do nothing;

create table public.port_mayor (
  port_id    uuid primary key references public.ports(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  since      timestamptz not null default now(),
  tax_rate   numeric check (tax_rate is null or tax_rate >= 0),
  tax_set_at timestamptz
);
comment on table public.port_mayor is
  '0147 (docs/INFLUENCE.md §5.1): a city''s mayor — the top giver of the country that holds it who '
  'sails for it now (tick_influence step 4) — and the rate the mayor set (cmd.set_tax).';
alter table public.port_mayor enable row level security;
revoke all on table public.port_mayor from public, anon, authenticated;

-- ── 2. THE ONE TAX AUTHORITY, GENERALISED ──────────────────────────────────────────────────────
drop function world.tax_rate(uuid);
create function world.tax_rate(p_port uuid, p_player uuid default null)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0122: dark, the column (a tax on turnover, riding the quote — as since 0005). Lit, a tax on
-- PROFIT: the column × profit_tax_scale, never above tax_rate_max (20 %). Each city keeps its own
-- rate. 0147: while the race is on, the MAYOR's rate replaces the city's when one is set (O4), and
-- a company of the country that holds the city pays (1 − influence_citizen_tax_cut) of it (D9).
-- Without a company: the city's base rate. THE one authority.
declare
  v_col  numeric := coalesce((select tax_rate from public.ports where id = p_port), public.wc_num('tax_rate_default'));
  v_base numeric;
begin
  if not public.city_treasury_on() then
    return v_col;
  end if;
  v_base := least(v_col * public.wc_num('profit_tax_scale'), public.wc_num('tax_rate_max'));
  if not public.influence_on() then
    return v_base;
  end if;
  v_base := coalesce((select m.tax_rate from public.port_mayor m where m.port_id = p_port), v_base);
  if p_player is not null
     and (select pl.nation_id from public.players pl where pl.id = p_player) = public.port_nation(p_port) then
    return v_base * (1 - public.wc_num('influence_citizen_tax_cut'));
  end if;
  return v_base;
end $$;

drop function public.profit_tax(uuid, numeric);
create function public.profit_tax(p_port uuid, p_profit numeric, p_player uuid default null)
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0122: THE charge. Tax on the profit of a sale, nothing on a loss, a break-even, or a profit the
-- game cannot know (null). Dark: nothing (the turnover tax still rides the quote). 0147: at the
-- seller's rate (world.tax_rate(port, seller)).
begin
  return case when public.city_treasury_on() and p_profit > 0
              then round(p_profit * world.tax_rate(p_port, p_player))::bigint else 0::bigint end;
end $$;

do $$
declare
  g record;
  v_new text;
begin
  revoke all on function world.tax_rate(uuid, uuid) from public;
  revoke all on function public.profit_tax(uuid, numeric, uuid) from public;
  for g in select * from grants_0147 loop
    v_new := case g.fn when 'world.tax_rate(uuid)' then 'world.tax_rate(uuid, uuid)' else 'public.profit_tax(uuid, numeric, uuid)' end;
    execute format('grant %s on function %s to %s', g.privilege_type, v_new,
                   case when g.grantee = 0 then 'public' else quote_ident(g.grantee::regrole::text) end);
  end loop;
end $$;

-- ── 3. SET THE TAX ─────────────────────────────────────────────────────────────────────────────
create or replace function cmd.set_tax(p_port uuid, p_rate numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0147: the caller, if the city's mayor, sets its profit tax within 0–tax_rate_max (O4), once a
-- real day. From anywhere: a mayor holds an office, not cargo.
declare
  v_player uuid := public.current_player_id();
  m        public.port_mayor%rowtype;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    select x.* into m from public.port_mayor x where x.port_id = p_port for update;
    if m.player_id is distinct from v_player or not public.influence_on() then
      perform cmd.refuse('E_NOT_MAYOR', 'only the mayor sets this city''s tax');
    end if;
    if p_rate is null or p_rate < 0 or p_rate > public.wc_num('tax_rate_max') then
      perform cmd.refuse('E_TAX_BAND', format('the tax is between 0%% and %s%% of the profit',
                                              round(public.wc_num('tax_rate_max') * 100)));
    end if;
    if m.tax_set_at is not null and m.tax_set_at > now() - interval '1 day' then
      perform cmd.refuse('E_ONCE_A_DAY', format('a mayor sets the tax once a day; the next change opens %s UTC',
                                                to_char((m.tax_set_at + interval '1 day') at time zone 'UTC', 'YYYY-MM-DD HH24:MI')));
    end if;
    update public.port_mayor set tax_rate = p_rate, tax_set_at = now() where port_id = p_port;
    perform public.emit_event(v_player, 'TAX_SET', jsonb_build_object(
      'port', (select code from public.ports where id = p_port), 'port_name', (select name from public.ports where id = p_port),
      'rate', p_rate));
    return jsonb_build_object('ok', true, 'port', (select code from public.ports where id = p_port), 'tax_rate', p_rate);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;
revoke all on function cmd.set_tax(uuid, numeric) from public, anon;
grant execute on function cmd.set_tax(uuid, numeric) to authenticated;

-- ── 4. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create temp table hunks_0147 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0147 values
('public.tick_influence(timestamp with time zone)', 1,
$h$  v_pname   text;
begin$h$,
$h$  v_pname   text;
  v_mayors  int := 0;   -- 0147
  v_new     int := 0;   -- 0147
begin$h$),
('public.tick_influence(timestamp with time zone)', 2,
$h$  -- 6 RECEIPT
  return jsonb_build_object('enabled', true, 'at', p_now, 'decayed', v_decayed, 'removed', v_removed,
                            'changed', v_changed, 'claimed', v_claimed, 'skipped', v_skipped,$h$,
$h$  -- 4 MAYOR (0147, D8 + A2): in every city a country holds, its top giver who sails for it now.
  v_t := clock_timestamp();
  begin
    with top as (
      select distinct on (i.port_id) i.port_id, i.player_id
        from public.port_influence i
        join public.players pl on pl.id = i.player_id and pl.nation_id = i.nation_id
       where i.nation_id = public.port_nation(i.port_id)
       group by i.port_id, i.player_id
       order by i.port_id, sum(i.points) desc, min(i.updated_at), i.player_id
    ), gone as (
      delete from public.port_mayor m where not exists (select 1 from top t where t.port_id = m.port_id)
      returning m.port_id
    ), up as (
      insert into public.port_mayor as m (port_id, player_id, since, tax_rate, tax_set_at)
      select t.port_id, t.player_id, p_now, null, null from top t
      on conflict (port_id) do update
         set player_id = excluded.player_id, since = p_now, tax_rate = null, tax_set_at = null
       where m.player_id <> excluded.player_id
      returning m.port_id
    )
    select (select count(*) from top), (select count(*) from up) into v_mayors, v_new;
  exception when others then
    v_err := v_err || jsonb_build_object('step', 'mayor', 'error', sqlerrm);
  end;
  v_ms := v_ms || jsonb_build_object('mayor', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 6 RECEIPT
  return jsonb_build_object('enabled', true, 'at', p_now, 'decayed', v_decayed, 'removed', v_removed,
                            'changed', v_changed, 'claimed', v_claimed, 'skipped', v_skipped,
                            'mayors', v_mayors, 'new_mayors', v_new,   -- 0147$h$),
('world.town_hall_influence(uuid, uuid)', 1,
$h$       'cap', public.wc_int('influence_day_cap'),$h$,
$h$       'tax_rate', world.tax_rate(p_port, p_player),                                   -- 0147: yours here
       'mayor', exists (select 1 from public.port_mayor m where m.port_id = p_port and m.player_id = p_player),   -- 0147
       'cap', public.wc_int('influence_day_cap'),$h$),
('world.town_hall_influence(uuid, uuid)', 2,
$h$    'open', public.city_treasury_on() and public.influence_on(),$h$,
$h$    'open', public.city_treasury_on() and public.influence_on(),
    -- 0147: the city's mayor (D8) and the rate the mayor set (null: the city's own).
    'mayor', (select jsonb_build_object('name', pl.company_name, 'merchant', pl.is_npc, 'since', m.since,
                                        'tax_rate', m.tax_rate, 'tax_set_at', m.tax_set_at)
                from public.port_mayor m join public.players pl on pl.id = m.player_id where m.port_id = p_port),$h$),
('cmd.do_sell(uuid, jsonb)', 1,
$h$  v_tax    := public.profit_tax(f.port_id, v_profit);   -- 0122: on the profit, nothing else$h$,
$h$  v_tax    := public.profit_tax(f.port_id, v_profit, f.player_id);   -- 0122: on the profit, nothing else; 0147: at the seller's rate$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 1,
$h$      v_net := (q_sell.total - q_buy.total) - public.profit_tax(p_to, q_sell.total - q_buy.total);$h$,
$h$      v_net := (q_sell.total - q_buy.total) - public.profit_tax(p_to, q_sell.total - q_buy.total,
                 (select sr.player_id from public.standing_routes sr where sr.id = p_route));   -- 0147: her rate$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'preview_donate',        'uuid, bigint')
    ) as t(s, f, a)$h$,
$h$      ('cmd',         'preview_donate',        'uuid, bigint'),
      -- 0147: the mayor sets the city's profit tax (docs/INFLUENCE.md I5).
      ('cmd',         'set_tax',               'uuid, numeric')
    ) as t(s, f, a)$h$);

do $$
declare
  d record;
  h record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0147 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0147 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0147(v_def, h.old);
      if v_n <> 1 then
        raise exception '0147 self-assert FAIL: hunk % of % occurs % time(s), not once', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
  for d in select * from defs_before_0147 loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0147 where fn = d.fn order by n desc loop
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl then
      raise exception '0147 self-assert FAIL: % does not reverse to its pre-image, or its ACL moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 5. THE PROOF ───────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_was jsonb := (select value from public.world_config where key = 'city_treasury_enabled');
  v_bad int;
  v_any uuid := (select id from public.players order by is_npc, id limit 1);
begin
  -- (a) no company: the pre-image at every harbour, dark and lit; a company, race off: the same
  update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
  select count(*) into v_bad from pre_0147 x
   where not x.lit and (world.tax_rate(x.port_id)::text <> x.rate or public.profit_tax(x.port_id, 1000)::text <> x.tax
                        or world.tax_rate(x.port_id, v_any)::text <> x.rate);
  if v_bad > 0 then raise exception '0147 self-assert FAIL: dark, % harbours'' tax moved', v_bad; end if;
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  select count(*) into v_bad from pre_0147 x
   where x.lit and (world.tax_rate(x.port_id)::text <> x.rate or public.profit_tax(x.port_id, 1000)::text <> x.tax
                    or world.tax_rate(x.port_id, v_any)::text <> x.rate or public.profit_tax(x.port_id, 1000, v_any)::text <> x.tax);
  update public.world_config set value = v_was where key = 'city_treasury_enabled';
  if v_bad > 0 then raise exception '0147 self-assert FAIL: lit with the race off, % harbours'' tax moved', v_bad; end if;
  if (select count(*) from pre_0147) <> 2 * (select count(*) from public.ports where kind = 'HARBOUR') then
    raise exception '0147 self-assert FAIL: the parity set is not every harbour twice';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'set_tax'
        and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute')) <> 1
     or has_function_privilege('anon', 'cmd.set_tax(uuid, numeric)', 'execute') then
    raise exception '0147 self-assert FAIL: cmd.set_tax is not registered for authenticated alone';
  end if;
end $$;

create or replace function pg_temp.probe_0147()
returns jsonb
language plpgsql
as $$
declare
  c_a  constant uuid := '00000000-0147-4000-8000-00000000000a';
  c_b  constant uuid := '00000000-0147-4000-8000-00000000000b';
  c_c  constant uuid := '00000000-0147-4000-8000-00000000000c';
  v_prt uuid := (select id from public.nations where code = 'PRT');
  v_esp uuid := (select id from public.nations where code = 'ESP');
  v_a  uuid;   -- PRT, gives 1,000 for PRT: the mayor
  v_b  uuid;   -- ESP, gives 5,000 for ESP: a richer foreigner
  v_c  uuid;   -- gave 3,000 for PRT, then left for ESP: a former citizen
  v_city uuid;
  v_r  jsonb;
  v_full numeric;
  v_out jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    v_a := public.new_house(c_a, 'Casa do Alcaide 0147', 'PRT');
    v_b := public.new_house(c_b, 'Casa del Rico 0147', 'ESP');
    v_c := public.new_house(c_c, 'Casa do Ausente 0147', 'ESP');
    select port_id into v_city from public.port_allegiance where not home order by md5(port_id::text || '0147') limit 1;
    update public.port_allegiance set nation_id = v_prt where port_id = v_city;
    delete from public.port_influence where port_id = v_city;
    insert into public.port_influence (port_id, nation_id, player_id, points) values
      (v_city, v_prt, v_a, 1000), (v_city, v_esp, v_b, 2000), (v_city, v_prt, v_c, 3000);
    -- PRT holds with 4,000 against ESP 2,000 (no flip); c's PRT points stay PRT's, but c sails for ESP
    v_r := public.tick_influence(now());
    if (select player_id from public.port_mayor where port_id = v_city) is distinct from v_a then
      raise exception '0147 self-assert FAIL: the mayor is not the holder''s top giver who sails for it now: %',
        (select company_name from public.players where id = (select player_id from public.port_mayor where port_id = v_city));
    end if;
    -- set_tax: a non-mayor, out of band, then the mayor, then again the same day
    perform cmd.assume_identity(c_b);
    if cmd.set_tax(v_city, 0.05)->>'error_code' <> 'E_NOT_MAYOR' then raise exception '0147 self-assert FAIL: a non-mayor set the tax'; end if;
    perform cmd.assume_identity(c_a);
    if cmd.set_tax(v_city, 0.21)->>'error_code' <> 'E_TAX_BAND' then raise exception '0147 self-assert FAIL: 21 %% was accepted'; end if;
    v_r := cmd.set_tax(v_city, 0.10);
    if not coalesce((v_r->>'ok')::boolean, false) or world.tax_rate(v_city) <> 0.10 then
      raise exception '0147 self-assert FAIL: the mayor''s rate is not the city''s: % / %', v_r, world.tax_rate(v_city);
    end if;
    if cmd.set_tax(v_city, 0.12)->>'error_code' <> 'E_ONCE_A_DAY' then raise exception '0147 self-assert FAIL: the tax moved twice in a day'; end if;
    -- a citizen pays half, a foreigner all
    v_full := public.profit_tax(v_city, 10000, v_b);
    if v_full <> 1000 or public.profit_tax(v_city, 10000, v_a) <> 500 then
      raise exception '0147 self-assert FAIL: citizen % / foreigner % on a 10,000 profit at 10 %%', public.profit_tax(v_city, 10000, v_a), v_full;
    end if;
    -- the town hall serves it
    v_r := world.town_hall_influence(v_city, v_a);
    if v_r->'mayor'->>'name' <> 'Casa do Alcaide 0147' or (v_r->'you'->>'tax_rate')::numeric <> 0.05 or not (v_r->'you'->>'mayor')::boolean then
      raise exception '0147 self-assert FAIL: the town hall''s mayor block: %', v_r;
    end if;
    -- race off: the mayor's rate and the halving stop at once
    update public.world_config set value = 'false'::jsonb where key = 'influence_enabled';
    if world.tax_rate(v_city) = 0.10 or public.profit_tax(v_city, 10000, v_a) <> public.profit_tax(v_city, 10000, v_b) then
      raise exception '0147 self-assert FAIL: with the race off the mayor''s rate or the halving still bites';
    end if;
    v_out := jsonb_build_object('mayor', 'the holder''s citizen with 1,000, not ESP''s 2,000 nor a former citizen''s 3,000',
                                'tax', 'non-mayor / 21 % / twice a day refused; 10 % set; citizen 500, foreigner 1,000 on 10,000');
    raise exception 'PROBE_ROLLBACK_0147';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0147' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v_out;
end $$;

do $$
declare
  v_p jsonb := pg_temp.probe_0147();
begin
  if (select value from public.world_config where key = 'influence_enabled') <> 'false'::jsonb then
    raise exception '0147 self-assert FAIL: the probe left the race lit';
  end if;
  raise notice '0147 self-assert ok: A CITY HAS A MAYOR — world.tax_rate / profit_tax with no company equal their pre-images at every harbour dark and lit (and with a company while the race is off); 5 bodies reverse to their pre-images; %', v_p;
end $$;
