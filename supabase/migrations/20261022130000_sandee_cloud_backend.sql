-- SandEE cloud backend: profiles, star progression, leaderboards, reward claims,
-- cloud-save metadata and RLS.
--
-- The remote project already had `profiles` (id, email, username, created_at),
-- `saves` (user_id, data, updated_at) and `username_available(text)` created
-- outside the migration workflow. Everything here is idempotent so it can be
-- applied on top without destroying data:
--   * CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS
--   * DROP POLICY IF EXISTS before CREATE POLICY
--   * CREATE OR REPLACE FUNCTION / VIEW
--
-- Client access rules:
--   * clients use the PUBLISHABLE key only; RLS + column grants protect data.
--   * `profiles.email` is never granted to anon/authenticated.
--   * stars are only incremented by the SECURITY DEFINER `claim_reward()` RPC,
--     which is idempotent per (user, reward).
--   * cloud-save objects live in the private `cloud-saves` bucket, path
--     `<auth.uid()>/<slot>.json`, with owner-only storage policies.

-- ── 1. Profiles + star progression ────────────────────────────────
create table if not exists public.profiles (
	id          uuid primary key references auth.users (id) on delete cascade,
	email       text not null,
	username    text not null,
	created_at  timestamptz default now()
);

alter table public.profiles add column if not exists blue_stars   integer not null default 0;
alter table public.profiles add column if not exists yellow_stars integer not null default 0;
alter table public.profiles add column if not exists updated_at   timestamptz not null default now();
alter table public.profiles alter column created_at set default now();

-- Usernames are unique regardless of case ("IronFox" == "ironfox").
create unique index if not exists profiles_username_lower_key
	on public.profiles (lower(username));

-- ── 2. Profile bootstrap on signup ────────────────────────────────
-- The Godot client signs up with `data: {username: "..."}`; this trigger creates
-- the profile row. If the username was taken between the availability check and
-- signup, it falls back to a stable generated name instead of failing signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
	begin
		insert into public.profiles (id, email, username)
		values (
			new.id,
			coalesce(new.email, ''),
			coalesce(nullif(trim(new.raw_user_meta_data->>'username'), ''),
				'player_' || substr(new.id::text, 1, 8))
		)
		on conflict (id) do nothing;
	exception when unique_violation then
		insert into public.profiles (id, email, username)
		values (new.id, coalesce(new.email, ''),
			'player_' || substr(new.id::text, 1, 8))
		on conflict (id) do nothing;
	end;
	return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
	after insert on auth.users
	for each row execute function public.handle_new_user();

-- ── 3. Username availability (public, used before signup) ─────────
create or replace function public.username_available(uname text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
	select not exists (
		select 1 from public.profiles
		where lower(username) = lower(trim(uname))
	);
$$;

grant execute on function public.username_available(text) to anon, authenticated;

-- ── 4. Legacy JSON saves (one row per user, owner-only) ───────────
create table if not exists public.saves (
	user_id    uuid primary key references auth.users (id) on delete cascade,
	data       jsonb not null default '{}'::jsonb,
	updated_at timestamptz not null default now()
);
-- Needed for PostgREST upserts even on an older remote table without the PK.
create unique index if not exists saves_user_id_key on public.saves (user_id);

-- ── 5. Cloud-save metadata (files live in the private bucket) ─────
create table if not exists public.cloud_saves (
	user_id     uuid not null references auth.users (id) on delete cascade,
	slot        integer not null check (slot between 1 and 10),
	object_path text not null,
	size_bytes  bigint not null default 0,
	checksum    text,
	updated_at  timestamptz not null default now(),
	primary key (user_id, slot)
);

-- ── 6. Reward claims (idempotent star awards) ────────────────────
create table if not exists public.reward_claims (
	user_id      uuid not null references auth.users (id) on delete cascade,
	reward_id    text not null,
	blue_stars   integer not null default 0 check (blue_stars >= 0),
	yellow_stars integer not null default 0 check (yellow_stars >= 0),
	claimed_at   timestamptz not null default now(),
	primary key (user_id, reward_id)
);

-- Adds stars exactly once per reward. Calling it again for the same reward
-- returns claimed = false and does not change the totals.
create or replace function public.claim_reward(
	reward_id text,
	blue integer default 0,
	yellow integer default 0
)
returns table (claimed boolean, blue_stars integer, yellow_stars integer)
language plpgsql
security definer
set search_path = public
as $$
declare
	inserted boolean := false;
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;

	with ins as (
		insert into public.reward_claims (user_id, reward_id, blue_stars, yellow_stars)
		values (auth.uid(), claim_reward.reward_id,
			greatest(claim_reward.blue, 0), greatest(claim_reward.yellow, 0))
		on conflict (user_id, reward_id) do nothing
		returning 1
	)
	select exists(select 1 from ins) into inserted;

	if inserted then
		update public.profiles
		set blue_stars   = profiles.blue_stars   + greatest(claim_reward.blue, 0),
			yellow_stars = profiles.yellow_stars + greatest(claim_reward.yellow, 0),
			updated_at   = now()
		where profiles.id = auth.uid();
	end if;

	return query
		select inserted, p.blue_stars, p.yellow_stars
		from public.profiles p where p.id = auth.uid();
end;
$$;

revoke all on function public.claim_reward(text, integer, integer) from public, anon;
grant execute on function public.claim_reward(text, integer, integer) to authenticated;

-- ── 7. Leaderboard view (public columns only) ────────────────────
create or replace view public.leaderboard
with (security_invoker = true)
as
select
	id,
	username,
	blue_stars,
	yellow_stars,
	(blue_stars + yellow_stars) as total_stars,
	updated_at
from public.profiles;

grant select on public.leaderboard to anon, authenticated;

-- ── 8. Row Level Security ────────────────────────────────────────
alter table public.profiles       enable row level security;
alter table public.saves          enable row level security;
alter table public.cloud_saves    enable row level security;
alter table public.reward_claims  enable row level security;

drop policy if exists "profiles are public" on public.profiles;
create policy "profiles are public" on public.profiles
	for select to anon, authenticated using (true);

drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles
	for insert to authenticated with check (auth.uid() = id);

drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles
	for update to authenticated
	using (auth.uid() = id) with check (auth.uid() = id);

-- Column privileges: email is not readable by clients (the edge function uses
-- the service role), and stars are not client-writable (only claim_reward()).
revoke select on public.profiles from anon, authenticated;
grant select (id, username, blue_stars, yellow_stars, created_at, updated_at)
	on public.profiles to anon, authenticated;
revoke update on public.profiles from anon, authenticated;
grant update (username) on public.profiles to authenticated;

drop policy if exists "saves owner" on public.saves;
create policy "saves owner" on public.saves
	for all to authenticated
	using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "cloud saves owner" on public.cloud_saves;
create policy "cloud saves owner" on public.cloud_saves
	for all to authenticated
	using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "reward claims read own" on public.reward_claims;
create policy "reward claims read own" on public.reward_claims
	for select to authenticated using (auth.uid() = user_id);

-- ── 9. Private storage bucket for cloud saves ────────────────────
insert into storage.buckets (id, name, public)
values ('cloud-saves', 'cloud-saves', false)
on conflict (id) do nothing;

drop policy if exists "cloud saves read own" on storage.objects;
create policy "cloud saves read own" on storage.objects
	for select to authenticated
	using (bucket_id = 'cloud-saves'
		and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "cloud saves insert own" on storage.objects;
create policy "cloud saves insert own" on storage.objects
	for insert to authenticated
	with check (bucket_id = 'cloud-saves'
		and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "cloud saves update own" on storage.objects;
create policy "cloud saves update own" on storage.objects
	for update to authenticated
	using (bucket_id = 'cloud-saves'
		and (storage.foldername(name))[1] = auth.uid()::text)
	with check (bucket_id = 'cloud-saves'
		and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "cloud saves delete own" on storage.objects;
create policy "cloud saves delete own" on storage.objects
	for delete to authenticated
	using (bucket_id = 'cloud-saves'
		and (storage.foldername(name))[1] = auth.uid()::text);
