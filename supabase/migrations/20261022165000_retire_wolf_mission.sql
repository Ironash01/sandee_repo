-- Retire the "Defeat 5 wolves" mission.
--
-- The mission is removed from the game's registry (wolf.gd no longer reports
-- progress). This cleans up the cloud side so the account star totals match the
-- CURRENT mission set:
--   * remove the retired reward id from the whitelist,
--   * remove any claim already recorded for it,
--   * subtract the single yellow star it awarded (never below 0).
--
-- The subtraction is performed under the same `sandee.stars_write` opt-in that
-- the star guard requires.

delete from public.mission_rewards
where reward_id = 'mission:defeat_wolves';

select set_config('sandee.stars_write', 'on', true);

with retired as (
	delete from public.reward_claims
	where reward_id = 'mission:defeat_wolves'
	returning user_id
)
update public.profiles as p
set yellow_stars = greatest(0, p.yellow_stars - 1),
	updated_at   = now()
from retired r
where p.id = r.user_id;
