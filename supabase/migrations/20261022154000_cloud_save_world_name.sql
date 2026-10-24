-- Cloud-save metadata only stored the slot, so the Cloud Saves screen could not
-- show which world a slot belonged to. Uploads now carry the world name.

alter table public.cloud_saves
	add column if not exists world_name text not null default '';
