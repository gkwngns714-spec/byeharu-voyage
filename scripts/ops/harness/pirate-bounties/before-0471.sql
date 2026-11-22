-- PROD CHECK (read only) before 0471 (bounties on named pirates): each OLD text of 0471's five hunks occurs once in its live body (and the
-- NEW marker 0 times); no 0471 knob, word or table yet; the four bodies' md5; and THE MEASURE before: the raids of the last 24 h by how they
-- ended, those on a company's ship and how many of those the company won by 0471's rule (public.bounty_beaten's RAID arm, spelled out here:
-- DRIVEN_OFF, or broke_off / b_fled, and the company not fled / slipped / stood_off), the pirates at work and hunting, and the smallest
-- surplus of a harbour the pirates do not hold. Calls only stable functions (city_surplus, port_nation, pirate_power: 's'). One statement.
begin transaction read only;
with fn(f) as (values ('public.battle_resolve(uuid,timestamp with time zone)'), ('public.raid_close(uuid,jsonb,timestamp with time zone)'),
                      ('public.tick_pirates(timestamp with time zone)'), ('public.client_rpc_entry_points()')),
     h(f, k, t) as (values
       ('public.battle_resolve(uuid,timestamp with time zone)', 'attack', $h$    v_spoils := public.attack_close(p_battle, v_f, p_now) || public.navy_close(p_battle, p_now);   -- 0333: the ships called are freed, and the report says who came$h$),
       ('public.battle_resolve(uuid,timestamp with time zone)', 'raid', $h$    v_spoils := public.navy_close(p_battle, p_now);$h$),
       ('public.raid_close(uuid,jsonb,timestamp with time zone)', 'report', $h$      'fights', '[]'::jsonb));$h$),
       ('public.tick_pirates(timestamp with time zone)', 'tick', $h$         -- 0445: LAST, the one ship of this run that may trade takes her step (its `steps` replaces the one above, with her answer counted)$h$),
       ('public.client_rpc_entry_points()', 'registry', $h$      ('world',       'pirate_ship_card',      'uuid'),$h$),
       ('public.battle_resolve(uuid,timestamp with time zone)', 'new', $h$0471$h$)),
     r as (select x.id, x.result, p.is_npc as d_npc
             from public.battles x
             join public.battle_sides s on s.battle_id = x.id and s.side = 'DEFENDER' and s.how = 'OPENED'
             join public.fleets f on f.id = s.fleet_id join public.players p on p.id = f.player_id
            where x.kind = 'RAID' and x.started_at > now() - interval '24 hours' and x.status <> 'FIGHTING')
select (select jsonb_object_agg(h.k, (length(d.b) - length(replace(d.b, h.t, ''))) / length(h.t))
          from h cross join lateral (select replace(pg_get_functiondef(to_regprocedure(h.f)), E'\r', '') as b) d) as hunks,   -- want attack 1, raid 1, report 1, tick 1, registry 1, new 0
       (select jsonb_object_agg(fn.f, md5(replace(pg_get_functiondef(to_regprocedure(fn.f)), E'\r', ''))) from fn) as md5,
       (select count(*) from public.world_config w where w.key in ('pirate_bounties_enabled', 'bounty_named', 'bounty_base', 'bounty_per_hour', 'bounty_per_ship',
                                                                  'bounty_cap', 'bounty_respawn_hours', 'bounty_keep_days')) as knobs,          -- want 0
       (select count(*) from public.stats_flow_words w where w.kind = 'PIRATE_BOUNTY') as word,                                              -- want 0
       to_regclass('public.pirate_bounties') is not null as table_exists,                                                                    -- want false
       (select jsonb_object_agg(q.o, q.n) from (select coalesce(r.result ->> 'outcome', '?') as o, count(*) as n from r group by 1) q) as raids_24h_by_outcome,
       (select count(*) from r where not r.d_npc) as raids_on_companies_24h,
       (select count(*) from r where not r.d_npc
           and (r.result ->> 'outcome' = 'DRIVEN_OFF' or coalesce((r.result ->> 'broke_off')::boolean, false) or coalesce((r.result ->> 'b_fled')::boolean, false))
           and not coalesce((r.result ->> 'fled')::boolean, false) and not coalesce((r.result ->> 'slipped')::boolean, false)
           and not coalesce((r.result ->> 'stood_off')::boolean, false)) as company_wins_24h,
       (select count(*) from r where r.result ->> 'outcome' in ('PLUNDERED', 'RANSOM')) as pirate_wins_24h,
       (select count(*) from public.pirate_ships_at_work) as pirates_at_work,
       (select count(*) from public.pirate_ships_cruising) as pirates_hunting,
       (select min(public.city_surplus(t.port_id)) from public.port_treasury t join public.ports p on p.id = t.port_id
         where p.kind = 'HARBOUR' and not public.pirate_power(public.port_nation(p.id))) as min_harbour_surplus,
       (select jsonb_object_agg(w.key, w.value) from public.world_config w
         where w.key in ('pirates_bite', 'city_treasury_enabled', 'attack_enabled', 'raid_companies_enabled')) as switches,
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                             -- 0467..0470 before this file
commit;
