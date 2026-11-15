-- 0430 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add a news line
-- and deploy it as any migration (owner only). Tested on the local chain: after it the four re-cut bodies are 0426's to the byte.
-- Gives back public.convoy_ships_wanted (the curve, no pirates), public.convoy_ships_of (min for no row), public.convoy_fleet_settle (the dead band)
-- and public.cargo_ship_step (an emptied ship sails the rest of her circuit): each of 0430's hunks reversed, checked once. Restores 0326's four
-- knobs at 0326's values, convoy_retire_per_run 3, drops cargo_fleet_total, cargo_pirate_min and the pirates' fleet number. Ships laid up by 0430 are woken by the
-- job (public.cargo_ships_commission, convoy_commission_per_run a run) as the curve's numbers come back at the next hourly read.
-- The quick way back with no file: cargo_fleet_total 1000 (nothing more lays up; the job makes ships up to each country's share of it).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_h   record;
  x     record;
  v_def text;
  v_n   int;
begin
  create temp table hunks_r430 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_r430 values
  -- S1. the share
  ('public.convoy_ships_wanted()', 1,
$h$  -- 0326: THE curve (owner: "bigger country with more cash - max 50, min 20"). Cash: the summed public.treasury_balance of the harbours under a flag, so a bigger country has more. Log from lo to the richest, whole ships.
  -- lo is the larger of the poorest realm and the richest / convoy_ships_span, so the poorest is always min and a realm near nothing cannot stretch the rest. All level: min. Read by public.convoy_fleet_settle alone.
  with c as (
    select g.nation_id,
           public.realm_purse(g.nation_id) as cash   -- 0331: lifted
      from public.great_powers g
     where not g.pirate   -- 0338: the pirates have no crown, so no cargo ships
  ), b as (
    select max(c.cash)::numeric as hi, greatest(min(c.cash)::numeric, max(c.cash)::numeric / public.wc_num('convoy_ships_span'), 1) as lo from c
  )
  select c.nation_id, c.cash,
         case when b.hi <= b.lo then public.wc_int('convoy_ships_min')
              else public.wc_int('convoy_ships_min')
                   + round((public.wc_int('convoy_ships_max') - public.wc_int('convoy_ships_min')) * ln(greatest(c.cash::numeric, b.lo) / b.lo) / ln(b.hi / b.lo))::integer end
    from c cross join b
$h$,
$h$  -- 0430: THE SHARE (owner 2026-11-15: "each countries including pirates should have cargo ships that are proportional to their size"; "reduce the cargo ship number to 100").
  -- Size: the harbours under a flag (the harbours public.realm_purse sums). Every great power with a harbour, the pirates too, keeps 1; the rest of cargo_fleet_total is shared by harbours,
  -- whole ships by the largest remainder (ties: more harbours, then the code), so the shares sum to the total exactly. No harbour: no row, no share. cash: the purse, for the record.
  -- The pirates keep at least cargo_pirate_min (their gold ships, 0429): when their share falls under it they hold the minimum and the others share what is left by the same rule.
  -- Read by public.convoy_fleet_settle alone.
  with s as (
    select x.* from (
      select g.nation_id, n.code, g.pirate,
             (select count(*) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = g.nation_id)::numeric as harbours
        from public.great_powers g join public.nations n on n.id = g.nation_id) x
     where x.harbours > 0
  ), k as (
    select greatest(public.wc_int('cargo_fleet_total'), count(*))::numeric as total, count(*)::numeric as n,
           least(public.wc_int('cargo_pirate_min'), greatest(public.wc_int('cargo_fleet_total'), count(*)) - count(*) + 1)::integer as pm from s
  ), q1 as (
    select s.*, 1 + (k.total - k.n) * s.harbours / sum(s.harbours) over () as quota from s cross join k
  ), r1 as (
    select q1.*, floor(q1.quota)::integer as base, row_number() over (order by q1.quota - floor(q1.quota) desc, q1.harbours desc, q1.code) as rk from q1
  ), b as (
    select exists (select 1 from r1 cross join k
                    where r1.pirate and r1.base + case when r1.rk <= k.total - (select sum(x.base) from r1 x) then 1 else 0 end < k.pm) as bind
  ), pool as (
    select s.*, k.total - case when b.bind then k.pm else 0 end as total from s cross join k cross join b where not (b.bind and s.pirate)
  ), q as (
    select pool.*, 1 + (pool.total - count(*) over ()) * pool.harbours / sum(pool.harbours) over () as quota from pool
  ), r as (
    select q.*, floor(q.quota)::integer as base, row_number() over (order by q.quota - floor(q.quota) desc, q.harbours desc, q.code) as rk from q
  )
  select r.nation_id, public.realm_purse(r.nation_id) as cash,
         r.base + case when r.rk <= r.total - (select sum(r2.base) from r r2) then 1 else 0 end as ships
    from r
  union all
  select s.nation_id, public.realm_purse(s.nation_id), k.pm from s cross join k cross join b where b.bind and s.pirate
$h$),
  -- S2. no row: no ship
  ('public.convoy_ships_of(uuid)', 1,
$h$  -- 0326: THE ONE READER of how many cargo ships a country keeps: the number it rests at. A power with no row yet: min, until the next read of the curve.
  select coalesce((select s.ships from public.cargo_fleet_sizes s where s.nation_id = p_nation), public.wc_int('convoy_ships_min'))
$h$,
$h$  -- 0326: THE ONE READER of how many cargo ships a country keeps: the number it rests at. 0430: a power with no row has no share: 0.
  select coalesce((select s.ships from public.cargo_fleet_sizes s where s.nation_id = p_nation), 0)
$h$),
  -- S2. the number is the share
  ('public.convoy_fleet_settle(timestamp with time zone)', 1,
$h$-- 0326: the one writer of public.cargo_fleet_sizes. Each convoy_size_read_minutes it reads the curve once. A number moves only when the curve is more than convoy_ships_band from it, or it has left min..max: the dead band, so
-- ordinary swings of a purse never turn ships over. Answers how many numbers moved. Between reads: one indexed read.
$h$,
$h$-- 0326: the one writer of public.cargo_fleet_sizes. Each convoy_size_read_minutes it reads the curve once.
-- 0430: it writes every power's share (public.convoy_ships_wanted) exactly, so the numbers sum to cargo_fleet_total, and drops the row of a power with no share. No dead band: shares move only when a
-- harbour changes flag. Answers how many numbers moved. Between reads: one indexed read.
$h$),
  ('public.convoy_fleet_settle(timestamp with time zone)', 2,
$h$       set cash = excluded.cash, read_at = p_now,
           ships = case when abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')
                          or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')
                        then excluded.ships else s.ships end,
           set_at = case when abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')
                           or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')
                         then p_now else s.set_at end
    returning s.set_at
  )
  select count(*) into v_n from u where u.set_at = p_now;
$h$,
$h$       set cash = excluded.cash, read_at = p_now,
           ships = excluded.ships,
           set_at = case when excluded.ships <> s.ships then p_now else s.set_at end
    returning s.set_at
  ), d as (
    delete from public.cargo_fleet_sizes x where not exists (select 1 from w where w.nation_id = x.nation_id)
    returning x.nation_id
  )
  select (select count(*) from u where u.set_at = p_now) + (select count(*) from d) into v_n;
$h$),
  -- S4. an empty ship sails home
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$  v_cir   bigint;
  v_leg   int;
$h$,
$h$  v_cir   bigint;
  v_leg   int;
  v_home  jsonb;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
    -- 0430: EMPTY, SHE SAILS HOME. Nothing left aboard after this city: not the rest of the circuit (that was the roaming, owner 2026-11-15) but one leg straight home, the course
    -- a rebase leg takes. At home the lap closes as before (HOME). No course home: she goes on by the circuit, whose last leg is home.
    if c.out_load is not null and not exists (select 1 from public.cargo_ship_aboard(p_fleet)) then
      if f.ready_at is not null and f.ready_at > p_now then
        return 'IN_PORT';
      end if;
      v_home := public.cargo_circuit_plan(c.nation_id, f.port_id, c.home_port_id) #> '{legs,0}';
      if v_home is not null then
        perform public.cargo_upkeep(p_fleet, f.port_id);   -- 0328: this leg too, as every leg
        perform voyage.depart(p_fleet, voyage.segments_from_course(v_home -> 'course'), f.port_id, c.home_port_id, p_now);
        return 'HOMEWARD';
      end if;
    end if;
$h$);

  for v_h in select h.fn from hunks_r430 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_r430 h where h.fn = v_h.fn order by h.ord desc loop
      v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
      if v_n <> 1 then
        raise exception 'rollback-0430: hunk % of % occurs % time(s), not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    execute v_def;
  end loop;
  insert into public.world_config (key, value, description) values
    ('convoy_ships_min', to_jsonb(20), '0326: cargo ships of the poorest great power. public.convoy_ships_wanted.'),
    ('convoy_ships_max', to_jsonb(50), '0326: cargo ships of the richest great power. public.convoy_ships_wanted.'),
    ('convoy_ships_span', to_jsonb(100), '0326: the curve''s low anchor is the richest realm''s cash over this, or the poorest realm if that is more. Below it a realm is at min. Keeps a nearly broke realm from moving every other realm''s number.'),
    ('convoy_ships_band', to_jsonb(3), '0326: a country''s number moves only when the curve is more than this many ships away. Measured on prod: docs/dev-log/2026-11-06-cargo-ships-follow-wealth.md.')
  on conflict (key) do nothing;
  update public.world_config set value = to_jsonb(3) where key = 'convoy_retire_per_run';
  delete from public.world_config where key in ('cargo_fleet_total', 'cargo_pirate_min');
  delete from public.cargo_fleet_sizes s where s.nation_id in (select g.nation_id from public.great_powers g where g.pirate);
  update public.cargo_fleet_sizes set read_at = '-infinity';
  perform public.convoy_fleet_settle(now());
  raise notice 'rollback-0430 ok: the four bodies back, the curve''s numbers: %',
    (select string_agg(n.code || ' ' || s.ships, ', ' order by n.code) from public.cargo_fleet_sizes s join public.nations n on n.id = s.nation_id);
end $r$;
