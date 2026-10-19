begin transaction read only;
select json_agg(json_build_array(fn, n, (length(d) - length(replace(d, old, ''))) / length(old)) order by fn, n)
  from (select v.fn, v.n, v.old, replace(pg_get_functiondef(v.fn::regprocedure), E'', '') d from (values ('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 1, $o0$--             weighed for a fight hand to hand — read against fight_board_bands: DRIVEN_OFF, RANSOM,
--             PLUNDERED, STRIPPED.
$o0$),
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 2, $o1$  v_ratio  numeric;
begin
$o1$),
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 3, $o2$    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'
                      when v_ratio >= (v_bands->>1)::numeric then 'RANSOM'
                      when v_ratio >= (v_bands->>2)::numeric then 'PLUNDERED'
                      else 'STRIPPED' end;
$o2$),
('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 4, $o3$                           || case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                             when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                             when 'PLUNDERED'  then ' They board and take what they can carry.'
                                             else ' They board and take everything but the ships.' end);
    v_sentence := case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                 when 'RANSOM'     then 'They came alongside and we paid them off.'
                                 when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
                                 else 'They took everything but the ships themselves.' end;
$o3$)) v(fn, n, old)) z;
rollback;
