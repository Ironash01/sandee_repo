-- Cross-platform cloud-save identity and revision metadata.
--
-- `slot` is still the UI-facing world slot (1..10, hard cloud limit 5), but a
-- slot alone cannot distinguish an updated Windows/Android copy from a
-- different world that happens to use the same slot on another device.
--
--   world_uid : stable 32-hex world identity carried inside every save file.
--   revision  : monotonically increasing per-world save counter.
--
-- Both are written by the client with each upload. RLS and the existing owner
-- policies continue to scope every row to auth.uid(); no policy is weakened.
-- Apply this migration before shipping clients that include the new columns.

alter table public.cloud_saves
	add column if not exists world_uid text;

alter table public.cloud_saves
	add column if not exists revision bigint not null default 0;

comment on column public.cloud_saves.world_uid is
	'Stable world identity shared by Windows and Android copies; empty on legacy rows.';
comment on column public.cloud_saves.revision is
	'Per-world save revision, independent of device clocks; legacy rows are 0.';

-- Keep metadata reads/writes owner-scoped (the table already has RLS enabled).
-- Reassert the policy idempotently so a partially applied older backend cannot
-- accidentally expose cloud-save metadata.
alter table public.cloud_saves enable row level security;

drop policy if exists "cloud saves owner" on public.cloud_saves;
create policy "cloud saves owner" on public.cloud_saves
	for all to authenticated
	using (auth.uid() = user_id) with check (auth.uid() = user_id);
