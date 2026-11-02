-- Cross-platform cloud-save deletion tombstones.
--
-- A world deleted on one platform must not be re-uploaded by another platform
-- that still has a local copy. The client records one row per (account,
-- world_uid) BEFORE deleting the cloud object/metadata. Other devices fetch
-- these rows during sync, delete the matching local world, and never upload
-- that UID again.
--
-- The tombstone is permanent. world_uid is globally unique per world, so a new
-- world that later reuses the same numeric slot has a different UID and is not
-- affected.

create table if not exists public.cloud_save_deletions (
	user_id    uuid not null references auth.users (id) on delete cascade,
	world_uid  text not null,
	slot       integer not null check (slot between 1 and 10),
	deleted_at timestamptz not null default now(),
	primary key (user_id, world_uid)
);

comment on table public.cloud_save_deletions is
	'Worlds deleted on any platform; other devices remove their local copy and never re-upload the UID.';

create index if not exists cloud_save_deletions_slot_idx
	on public.cloud_save_deletions (user_id, slot);

alter table public.cloud_save_deletions enable row level security;

drop policy if exists "cloud save deletions owner" on public.cloud_save_deletions;
create policy "cloud save deletions owner" on public.cloud_save_deletions
	for all to authenticated
	using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.cloud_save_deletions from anon;
grant select, insert, update, delete on public.cloud_save_deletions to authenticated;
