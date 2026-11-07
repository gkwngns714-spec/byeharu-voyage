-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this file re-creates functions (a kept copy of live bodies / a candidate body). The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
CREATE OR REPLACE FUNCTION public.npc_purse_ceiling(p_player uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0180: THE one reading of a merchant house's purse ceiling — floor(capital × npc_purse_ceiling).
  -- Null for a company that is not a merchant house.
  select floor(h.capital * public.wc_num('npc_purse_ceiling'))::bigint
    from public.npc_houses h where h.player_id = p_player
$function$
