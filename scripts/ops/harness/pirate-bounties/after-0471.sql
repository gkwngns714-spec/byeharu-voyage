-- PROD CHECK (read only) after 0471 (bounties on named pirates): the five NEW texts once each, the switch false and the seven knobs at their
-- values, PIRATE_BOUNTY a moved word, the table empty (dark: nothing named), world.pirate_bounties registered for authenticated alone and
-- stable, and the four bodies' md5 (compare with docs/dev-log/2026-11-22-pirate-bounties.md). Lit (the owner's switch), the same file shows
-- how many pirates stand named, the claims, what was paid and what the harbours paid out. Catalog and two small tables only. One statement.
begin transaction read only;
with fn(f) as (values ('public.battle_resolve(uuid,timestamp with time zone)'), ('public.raid_close(uuid,jsonb,timestamp with time zone)'),
                      ('public.tick_pirates(timestamp with time zone)'), ('public.client_rpc_entry_points()')),
     h(f, k, t) as (values
       ('public.battle_resolve(uuid,timestamp with time zone)', 'attack', $h$-- 0471: a named pirate beaten by the company that attacked her$h$),
       ('public.battle_resolve(uuid,timestamp with time zone)', 'raid', $h$-- 0471: a named pirate's raid$h$),
       ('public.raid_close(uuid,jsonb,timestamp with time zone)', 'report', $h$-- 0471: the bounty she collected, said on her report$h$),
       ('public.tick_pirates(timestamp with time zone)', 'tick', $h$-- 0471: the named pirates (public.bounty_step$h$),
       ('public.client_rpc_entry_points()', 'registry', $h$('world',       'pirate_bounties',       ''),$h$))
select (select jsonb_object_agg(h.k, (length(d.b) - length(replace(d.b, h.t, ''))) / length(h.t))
          from h cross join lateral (select replace(pg_get_functiondef(to_regprocedure(h.f)), E'\r', '') as b) d) as hunks,   -- want each 1
       (select jsonb_object_agg(fn.f, md5(replace(pg_get_functiondef(to_regprocedure(fn.f)), E'\r', ''))) from fn) as md5,
       (select jsonb_object_agg(w.key, w.value) from public.world_config w
         where w.key in ('pirate_bounties_enabled', 'bounty_named', 'bounty_base', 'bounty_per_hour', 'bounty_per_ship', 'bounty_cap', 'bounty_respawn_hours', 'bounty_keep_days')) as knobs,
       (select w.side from public.stats_flow_words w where w.kind = 'PIRATE_BOUNTY') as word,                                                -- want moved
       (select jsonb_build_object('open', count(*) filter (where x.closed_at is null), 'claimed', count(*) filter (where x.closed = 'CLAIMED'),
                                  'lapsed', count(*) filter (where x.closed = 'LAPSED'), 'paid', coalesce(sum(x.paid), 0), 'taken', coalesce(sum(x.taken), 0))
          from public.pirate_bounties x) as bounties,                                                                                         -- dark: all 0
       (select count(*) from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'pirate_bounties'
           and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) as registered,   -- want 1
       (select p.provolatile from pg_proc p where p.oid = to_regprocedure('world.pirate_bounties()')) as read_volatility,                    -- want s
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                             -- want 20260818000471
commit;
