-- Case-insensitive username lookup for the `login-with-username` Edge Function.
--
-- Usernames are unique on `lower(username)` (profiles_username_lower_key), so
-- "IronFox" and "ironfox" are the same account and must resolve to the same
-- login. The Edge Function runs with the service role; regular clients can
-- neither execute this function nor read `profiles.email`.

create or replace function public.username_email(uname text)
returns text
language sql
stable
security definer
set search_path = public
as $$
	select email
	from public.profiles
	where lower(username) = lower(trim(uname))
	limit 1;
$$;

revoke all on function public.username_email(text) from public, anon, authenticated;
grant execute on function public.username_email(text) to service_role;
