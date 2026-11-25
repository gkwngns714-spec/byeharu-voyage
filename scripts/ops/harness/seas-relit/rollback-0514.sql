-- 0514 ROLLBACK of the light, at once (owner, or the lead on a red after-check): every passage is judged as before the light. The news row stays (it is history).
update public.world_config set value = 'false'::jsonb, updated_at = now() where key = 'sea_conditions_bite' returning key, value;
