-- Mission → star synchronization with server-side guards.
--
-- Why: local missions/clears are per-world, while the leaderboard stars are
-- account-wide. The old UI counted "completed missions + cleared dungeons" and
-- never pushed anything to the profile. This migration makes the server the
-- only writer of star totals and lets the client claim known mission rewards.
--
-- Exploit guards:
--   * `mission_rewards` is a whitelist of every valid mission/clear id. The RPC
--     ignores unknown ids, so a client cannot invent missions for free stars.
--   * `reward_claims` stays unique per (user, reward_id): each mission/clear can
--     be claimed exactly once per account, no matter how many local worlds exist.
--   * A BEFORE UPDATE trigger on `profiles` rejects star changes unless the
--     transaction explicitly opted in via `sandee.stars_write`, which only the
--     SECURITY DEFINER functions below do. Direct PATCHes, SQL edits or a
--     compromised client cannot set arbitrary totals.
--   * `claim_reward(text,int,int)` (arbitrary amounts) is revoked from client
--     roles and kept only for service_role/admin use.
--
-- The one-time migration case ("cloud is 0 but the local world already has
-- stars") is handled by the client syncing every completed local mission on
-- world load: the whitelist turns that into the exact bounded star total.

create table if not exists public.mission_rewards (
	reward_id text primary key,
	kind      text not null check (kind in ('blue', 'yellow')),
	amount    integer not null default 1 check (amount between 1 and 2),
	label     text not null default ''
);

alter table public.mission_rewards enable row level security;
revoke all on public.mission_rewards from public, anon, authenticated;

insert into public.mission_rewards (reward_id, kind, amount, label) values
	('mission:move', 'yellow', 1, 'quest: move'),
	('mission:open_inventory', 'yellow', 1, 'quest: open_inventory'),
	('mission:cut_tree', 'yellow', 1, 'quest: cut_tree'),
	('mission:craft_item', 'yellow', 1, 'quest: craft_item'),
	('mission:collect_wood', 'yellow', 1, 'quest: collect_wood'),
	('mission:craft_sword', 'yellow', 1, 'quest: craft_sword'),
	('mission:craft_pickaxe', 'yellow', 1, 'quest: craft_pickaxe'),
	('mission:mine_stone', 'yellow', 1, 'quest: mine_stone'),
	('mission:place_blocks', 'yellow', 1, 'quest: place_blocks'),
	('mission:defeat_wolves', 'yellow', 1, 'quest: defeat_wolves'),
	('mission:build_shelter', 'yellow', 1, 'quest: build_shelter'),
	('mission:craft_chest', 'yellow', 1, 'quest: craft_chest'),
	('mission:enter_cave', 'yellow', 1, 'quest: enter_cave'),
	('mission:mine_iron', 'yellow', 1, 'quest: mine_iron'),
	('mission:smelt_iron', 'yellow', 1, 'quest: smelt_iron'),
	('mission:craft_iron_sword', 'yellow', 1, 'quest: craft_iron_sword'),
	('mission:craft_iron_pickaxe', 'yellow', 1, 'quest: craft_iron_pickaxe'),
	('mission:place_torch', 'yellow', 1, 'quest: place_torch'),
	('mission:explore_tiles', 'yellow', 1, 'quest: explore_tiles'),
	('mission:survive_days', 'yellow', 1, 'quest: survive_days'),
	('mission:defeat_worms', 'yellow', 1, 'quest: defeat_worms'),
	('mission:enter_dungeon', 'yellow', 1, 'quest: enter_dungeon'),
	('mission:clear_dungeon', 'yellow', 1, 'quest: clear_dungeon'),
	('mission:learn_entry', 'yellow', 1, 'quest: learn_entry'),
	('mission:mine_diamond', 'yellow', 1, 'quest: mine_diamond'),
	('mission:run_program', 'yellow', 1, 'quest: run_program'),
	('dungeon_mission:dungeon_1', 'blue', 1, 'dungeon mission 1'),
	('dungeon_clear:1', 'blue', 1, 'dungeon clear 1'),
	('dungeon_mission:dungeon_2', 'blue', 1, 'dungeon mission 2'),
	('dungeon_clear:2', 'blue', 1, 'dungeon clear 2'),
	('dungeon_mission:dungeon_3', 'blue', 1, 'dungeon mission 3'),
	('dungeon_clear:3', 'blue', 1, 'dungeon clear 3'),
	('dungeon_mission:dungeon_4', 'blue', 1, 'dungeon mission 4'),
	('dungeon_clear:4', 'blue', 1, 'dungeon clear 4'),
	('dungeon_mission:dungeon_5', 'blue', 1, 'dungeon mission 5'),
	('dungeon_clear:5', 'blue', 1, 'dungeon clear 5'),
	('dungeon_mission:dungeon_6', 'blue', 1, 'dungeon mission 6'),
	('dungeon_clear:6', 'blue', 1, 'dungeon clear 6'),
	('dungeon_mission:dungeon_7', 'blue', 1, 'dungeon mission 7'),
	('dungeon_clear:7', 'blue', 1, 'dungeon clear 7'),
	('dungeon_mission:dungeon_8', 'blue', 1, 'dungeon mission 8'),
	('dungeon_clear:8', 'blue', 1, 'dungeon clear 8'),
	('dungeon_mission:dungeon_9', 'blue', 1, 'dungeon mission 9'),
	('dungeon_clear:9', 'blue', 1, 'dungeon clear 9'),
	('dungeon_mission:dungeon_10', 'blue', 1, 'dungeon mission 10'),
	('dungeon_clear:10', 'blue', 1, 'dungeon clear 10'),
	('dungeon_mission:dungeon_11', 'blue', 1, 'dungeon mission 11'),
	('dungeon_clear:11', 'blue', 1, 'dungeon clear 11'),
	('dungeon_mission:dungeon_26', 'blue', 1, 'dungeon mission 26'),
	('dungeon_clear:26', 'blue', 1, 'dungeon clear 26'),
	('dungeon_mission:dungeon_27', 'blue', 1, 'dungeon mission 27'),
	('dungeon_clear:27', 'blue', 1, 'dungeon clear 27'),
	('dungeon_mission:dungeon_28', 'blue', 1, 'dungeon mission 28'),
	('dungeon_clear:28', 'blue', 1, 'dungeon clear 28'),
	('dungeon_mission:dungeon_29', 'blue', 1, 'dungeon mission 29'),
	('dungeon_clear:29', 'blue', 1, 'dungeon clear 29'),
	('dungeon_mission:dungeon_30', 'blue', 1, 'dungeon mission 30'),
	('dungeon_clear:30', 'blue', 1, 'dungeon clear 30'),
	('dungeon_mission:dungeon_31', 'blue', 1, 'dungeon mission 31'),
	('dungeon_clear:31', 'blue', 1, 'dungeon clear 31'),
	('dungeon_mission:dungeon_32', 'blue', 1, 'dungeon mission 32'),
	('dungeon_clear:32', 'blue', 1, 'dungeon clear 32'),
	('dungeon_mission:dungeon_33', 'blue', 1, 'dungeon mission 33'),
	('dungeon_clear:33', 'blue', 1, 'dungeon clear 33'),
	('dungeon_mission:dungeon_34', 'blue', 1, 'dungeon mission 34'),
	('dungeon_clear:34', 'blue', 1, 'dungeon clear 34'),
	('dungeon_mission:dungeon_35', 'blue', 1, 'dungeon mission 35'),
	('dungeon_clear:35', 'blue', 1, 'dungeon clear 35'),
	('dungeon_mission:dungeon_36', 'blue', 1, 'dungeon mission 36'),
	('dungeon_clear:36', 'blue', 1, 'dungeon clear 36'),
	('dungeon_mission:dungeon_37', 'blue', 1, 'dungeon mission 37'),
	('dungeon_clear:37', 'blue', 1, 'dungeon clear 37'),
	('dungeon_mission:dungeon_38', 'blue', 1, 'dungeon mission 38'),
	('dungeon_clear:38', 'blue', 1, 'dungeon clear 38'),
	('dungeon_mission:dungeon_39', 'blue', 1, 'dungeon mission 39'),
	('dungeon_clear:39', 'blue', 1, 'dungeon clear 39')
on conflict (reward_id) do nothing;

-- ── Guard: star totals are server-controlled ──────────────────────
create or replace function public.guard_profile_stars()
returns trigger
language plpgsql
set search_path = public
as $$
begin
	if (new.blue_stars is distinct from old.blue_stars
			or new.yellow_stars is distinct from old.yellow_stars)
		and coalesce(current_setting('sandee.stars_write', true), '') <> 'on' then
		raise exception 'star totals are server-controlled' using errcode = '42501';
	end if;
	return new;
end;
$$;

drop trigger if exists profiles_guard_stars on public.profiles;
create trigger profiles_guard_stars
	before update on public.profiles
	for each row execute function public.guard_profile_stars();

-- The existing arbitrary-amount RPC must opt into the guard (it now
-- increments totals itself, so the trigger would otherwise block it).
create or replace function public.claim_reward(
	p_reward_id text,
	p_blue integer default 0,
	p_yellow integer default 0
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
		insert into public.reward_claims as rc (user_id, reward_id, blue_stars, yellow_stars)
		values (auth.uid(), p_reward_id, greatest(p_blue, 0), greatest(p_yellow, 0))
		on conflict (user_id, reward_id) do nothing
		returning 1
	)
	select exists(select 1 from ins) into inserted;

	if inserted then
		perform set_config('sandee.stars_write', 'on', true);
		update public.profiles as p
		set blue_stars   = p.blue_stars   + greatest(p_blue, 0),
			yellow_stars = p.yellow_stars + greatest(p_yellow, 0),
			updated_at   = now()
		where p.id = auth.uid();
	end if;

	return query
		select inserted, p.blue_stars, p.yellow_stars
		from public.profiles p where p.id = auth.uid();
end;
$$;

-- Client roles must not be able to award arbitrary amounts.
revoke all on function public.claim_reward(text, integer, integer) from public, anon, authenticated;
grant execute on function public.claim_reward(text, integer, integer) to service_role;

-- ── Claim known mission rewards (batch, whitelisted, once per account) ──
create or replace function public.claim_missions(p_reward_ids text[])
returns table (claimed integer, blue_total integer, yellow_total integer)
language plpgsql
security definer
set search_path = public
as $$
declare
	inc_blue integer := 0;
	inc_yellow integer := 0;
	inserted_count integer := 0;
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;
	if coalesce(array_length(p_reward_ids, 1), 0) > 200 then
		raise exception 'too many rewards in one request' using errcode = '22023';
	end if;

	with valid as (
		select reward_id, kind, amount
		from public.mission_rewards
		where reward_id = any(coalesce(p_reward_ids, '{}'::text[]))
	), ins as (
		insert into public.reward_claims (user_id, reward_id, blue_stars, yellow_stars)
		select auth.uid(), v.reward_id,
			case when v.kind = 'blue' then v.amount else 0 end,
			case when v.kind = 'yellow' then v.amount else 0 end
		from valid v
		on conflict (user_id, reward_id) do nothing
		returning reward_id
	)
	select
		coalesce(sum(case when v.kind = 'blue' then v.amount else 0 end), 0)::integer,
		coalesce(sum(case when v.kind = 'yellow' then v.amount else 0 end), 0)::integer,
		count(*)::integer
	into inc_blue, inc_yellow, inserted_count
	from ins i
	join valid v on v.reward_id = i.reward_id;

	if inserted_count > 0 then
		perform set_config('sandee.stars_write', 'on', true);
		update public.profiles as p
		set blue_stars   = p.blue_stars   + inc_blue,
			yellow_stars = p.yellow_stars + inc_yellow,
			updated_at   = now()
		where p.id = auth.uid();
	end if;

	return query
		select inserted_count, p.blue_stars, p.yellow_stars
		from public.profiles p where p.id = auth.uid();
end;
$$;

revoke all on function public.claim_missions(text[]) from public, anon;
grant execute on function public.claim_missions(text[]) to authenticated;
