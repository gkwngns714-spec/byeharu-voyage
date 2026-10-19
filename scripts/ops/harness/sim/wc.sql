begin transaction read only;
select json_object_agg(key, value) from world_config;
rollback;
