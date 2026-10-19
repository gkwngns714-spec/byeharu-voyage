begin transaction read only;
select json_agg(version order by version) from supabase_migrations.schema_migrations where version > '20260818000198';
rollback;
