-- Hard limit: 5 cloud-save worlds per account.
--
-- The client checks the limit before uploading to Storage and offers a
-- replacement chooser; this trigger is the database backstop for races or
-- non-game clients. Upserts to an existing slot are updates, not new rows, and
-- must not be blocked.

create or replace function public.enforce_cloud_save_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
	if exists (
		select 1 from public.cloud_saves
		where user_id = new.user_id and slot = new.slot
	) then
		return new;   -- UPDATE of an existing slot
	end if;
	if (
		select count(*) from public.cloud_saves where user_id = new.user_id
	) >= 5 then
		raise exception 'cloud save limit reached (5)' using errcode = 'P0001';
	end if;
	return new;
end;
$$;

drop trigger if exists cloud_saves_limit on public.cloud_saves;
create trigger cloud_saves_limit
	before insert on public.cloud_saves
	for each row execute function public.enforce_cloud_save_limit();
