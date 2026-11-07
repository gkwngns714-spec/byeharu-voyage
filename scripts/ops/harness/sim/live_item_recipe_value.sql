-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this file re-creates functions (a kept copy of live bodies / a candidate body). The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
CREATE OR REPLACE FUNCTION public.item_recipe_value(p_item text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- 0158 (S13, §6.5): WHAT AN ITEM IS MADE OF, IN COIN — Σ recipe qty × the good's base value (0068's
  -- recipe, 0002's value; §6.4's prices are this figure). Read by public.unit_repair_cost.
  return (select coalesce(sum(ir.qty * g.base_value), 0)
            from public.item_recipes ir join public.goods g on g.id = ir.good_id
           where ir.item_code = p_item);
end $function$
