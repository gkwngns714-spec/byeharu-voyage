-- 0412 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). It gives each of the fourteen tables back EXACTLY the autovacuum settings it carried before 0412, as 0412
-- wrote them down on that server (public.autovacuum_was): the eight autovacuum options 0412 set are reset, then the table's old ones are set again.
-- An option 0412 never touched (a fillfactor) stays as it is now. public.autovacuum_was is left in place: it is the record.
-- SHARE UPDATE EXCLUSIVE a table, lock_timeout 8 s, as 0412. FOR ONE TABLE, BY HAND (owner): the same two statements for that table alone.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  w     record;
  v_set text;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '8s', true);
  if to_regclass('public.autovacuum_was') is null then
    raise exception '0412 rollback refuses: public.autovacuum_was is not here (0412 was not applied)';
  end if;
  for w in select a.tbl, a.reloptions from public.autovacuum_was a where a.by_file = '0412' order by a.tbl loop
    execute format('alter table public.%I reset (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold, autovacuum_vacuum_insert_scale_factor, '
                   || 'autovacuum_vacuum_insert_threshold, autovacuum_analyze_scale_factor, autovacuum_analyze_threshold, '
                   || 'autovacuum_vacuum_cost_delay, autovacuum_vacuum_cost_limit)', w.tbl);
    v_set := (select string_agg(o, ', ') from unnest(coalesce(w.reloptions, '{}'::text[])) o where o like 'autovacuum_%');
    if v_set is not null then
      execute format('alter table public.%I set (%s)', w.tbl, v_set);
    end if;
    if (select array(select o from unnest(coalesce(c.reloptions, '{}'::text[])) o where o like 'autovacuum_%' order by o)
          from pg_class c where c.oid = ('public.' || w.tbl)::regclass)
         is distinct from array(select o from unnest(coalesce(w.reloptions, '{}'::text[])) o where o like 'autovacuum_%' order by o) then
      raise exception '0412 rollback FAIL: public.% reads % and held % before 0412', w.tbl,
        (select c.reloptions from pg_class c where c.oid = ('public.' || w.tbl)::regclass), w.reloptions;
    end if;
  end loop;
  raise notice '0412 rollback ok: the fourteen tables carry the autovacuum settings they held before 0412.';
end $r$;
