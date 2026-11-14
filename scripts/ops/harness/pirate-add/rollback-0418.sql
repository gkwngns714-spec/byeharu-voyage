-- 0418 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and deploy it as any migration (owner only).
-- It takes 0418's lines out of public.pirate_add: the add again asks only for the fleet public.pirate_next_ord names, so the roster again waits behind any of 0339's ships the day's room cannot build.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_def text := replace(pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure), E'\r', '');
  v_a   int := position(E'  -- 0418: THE ROSTER DOES NOT WAIT' in v_def);
  v_b   int := position(E'  if v_ord is null then\n    return null;' in v_def);
begin
  if v_a = 0 or v_b <= v_a then
    raise exception 'rollback 0418 refuses: the lines of 0418 are not in public.pirate_add as it wrote them';
  end if;
  execute substr(v_def, 1, v_a - 1) || substr(v_def, v_b);
  if position('0418' in pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure)) > 0 then
    raise exception 'rollback 0418 FAIL: a line of 0418 is still in the body';
  end if;
  raise notice 'rollback 0418 ok: md5 %', md5(replace(pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure), E'\r', ''));
end $r$;
