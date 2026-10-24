-- Final cleanup of the integration-test accounts used to verify the live
-- Supabase project on 2026-10-22. The test accounts all use @example.com
-- addresses with the `godot.` or `sandee.e2e` prefixes, so this also removes
-- any stragglers from earlier runs. Real players are never affected.
--
-- Profiles, saves, cloud-save metadata and reward claims disappear through the
-- existing ON DELETE CASCADE foreign keys.

delete from auth.users
where email like 'godot.%@example.com'
   or email like 'sandee.e2e%@example.com';
