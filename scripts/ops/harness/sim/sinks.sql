begin transaction read only;
with st as (select s.route_id, s.ord, s.port_id, count(*) over (partition by s.route_id) n from public.standing_route_stops s join public.npc_fleets nf on nf.route_id=s.route_id),
 b as (select l.route_id, l.good_id, s1.port_id src, s2.port_id sink from public.standing_route_lines l
        join st s1 on s1.route_id=l.route_id and s1.ord=l.stop_ord
        join st s2 on s2.route_id=l.route_id and s2.ord=(l.stop_ord+1) % s1.n
        join public.standing_routes sr on sr.id=l.route_id and coalesce(sr.paused_reason,'') not in ('laid_up','error')
       where l.kind='BUY'),
 d as (select good_id, sink, count(distinct route_id) k from b group by 1,2),
 ref as (select p.id sink, g.id good_id, count(*) refused
           from public.standing_route_laps lp join public.npc_fleets nf on nf.route_id=lp.route_id
           cross join lateral jsonb_array_elements(lp.skipped) e
           join public.ports p on p.code = e->>'port' join public.goods g on g.code = split_part(e->>'line',' ',2)
          where lp.closed_at > now()-interval '3 hours' and e->>'verb'='SELL' and e->>'code'='E_PRICE_LIMIT' group by 1,2)
select json_build_object(
  'buy_lines', (select count(*) from b),
  'pairs', (select count(*) from d),
  'by_k', (select json_agg(json_build_object('k', k, 'pairs', n, 'routes', r, 'refused', rf) order by k) from (select least(d.k,6) k, count(*) n, sum(d.k) r, coalesce(sum(ref.refused),0) rf from d left join ref on ref.sink=d.sink and ref.good_id=d.good_id group by 1) z),
  'sell_refusals_total', (select sum(refused) from ref)
) j;
rollback;
