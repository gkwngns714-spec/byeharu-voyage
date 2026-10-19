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
