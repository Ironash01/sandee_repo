-- Fix: `claim_reward(text, integer, integer)` had an input parameter named
-- `reward_id`, which collides with the `reward_claims.reward_id` column inside
-- PL/pgSQL (`column reference "reward_id" is ambiguous`, SQLSTATE 42702).
--
-- The parameters are renamed with a `p_` prefix. PostgreSQL cannot rename an
-- input parameter through CREATE OR REPLACE, so the old signature is dropped
-- first. Nothing else depends on the function yet.
--
-- PostgREST RPC call shape now:
--   POST /rest/v1/rpc/claim_reward
--   { "p_reward_id": "dungeon_1", "p_blue": 3, "p_yellow": 1 }

drop function if exists public.claim_reward(text, integer, integer);

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

revoke all on function public.claim_reward(text, integer, integer) from public, anon;
grant execute on function public.claim_reward(text, integer, integer) to authenticated;
