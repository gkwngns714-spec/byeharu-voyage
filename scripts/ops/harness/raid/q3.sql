begin transaction read only;
select pg_get_functiondef('voyage.settle(uuid, timestamp with time zone)'::regprocedure);
rollback;
