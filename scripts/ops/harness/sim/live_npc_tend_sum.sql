CREATE OR REPLACE FUNCTION public.npc_tend_sum(p_a jsonb, p_b jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE one place npc_tend's receipt is added up — the counts of two steps summed (a missing
-- count is 0), their notes concatenated in order. npc_tend_sum(x, '{}') is x with every count present.
declare
  v_k text;
  v   jsonb := jsonb_build_object('notes', coalesce(p_a->'notes', '[]'::jsonb) || coalesce(p_b->'notes', '[]'::jsonb));
begin
  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up', 'refounded', 'refound_unfunded',
                             'invested', 'donated', 'busy', 'failed', 'deferred',
                             'built', 'ceiling', 'ceiling_given', 'waiting'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given; 0181: waiting
    v := v || jsonb_build_object(v_k, coalesce((p_a->>v_k)::int, 0) + coalesce((p_b->>v_k)::int, 0));
  end loop;
  return v;
end $function$
