-- Keep `updated_at` server-authoritative on profiles and cloud-save metadata so
-- the client never has to trust (or send) a local clock.
--
-- `cloud_saves` rows are upserted by the client on every upload; without this
-- trigger the timestamp would keep the value from the original insert.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
	new.updated_at = now();
	return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
	before insert or update on public.profiles
	for each row execute function public.touch_updated_at();

drop trigger if exists cloud_saves_touch_updated_at on public.cloud_saves;
create trigger cloud_saves_touch_updated_at
	before insert or update on public.cloud_saves
	for each row execute function public.touch_updated_at();
