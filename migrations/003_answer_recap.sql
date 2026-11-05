-- Run after migration 002, then refresh both browsers. Safe to rerun.
begin;
create or replace function public.game_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; mine integer; theirs integer; all_scores jsonb; all_answers jsonb := '[]'::jsonb;
begin
 select * into r from rooms where code=upper(trim(p_code));
 if not found or auth.uid() is null or (auth.uid() <> r.host_id and auth.uid() is distinct from r.guest_id) then raise exception 'Room not found'; end if;
 select value into mine from answers where room_code=r.code and round=r.round and player_id=auth.uid();
 if (select count(*) from answers where room_code=r.code and round=r.round)=2 then
   select value into theirs from answers where room_code=r.code and round=r.round and player_id<>auth.uid();
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('round',x.round,'distance',abs(x.h-x.g)) order by x.round),'[]'::jsonb) into all_scores
 from (select a.round,max(a.value) filter(where a.player_id=r.host_id) h,max(a.value) filter(where a.player_id=r.guest_id) g
       from answers a where a.room_code=r.code and a.round<r.round group by a.round) x where x.h is not null and x.g is not null;
 if r.round >= r.question_count then
  select coalesce(jsonb_agg(jsonb_build_object('round',x.round,'question_id',r.question_ids[x.round+1],
   'mine',case when auth.uid()=r.host_id then x.h else x.g end,
   'theirs',case when auth.uid()=r.host_id then x.g else x.h end) order by x.round),'[]'::jsonb) into all_answers
  from (select a.round,max(a.value) filter(where a.player_id=r.host_id) h,max(a.value) filter(where a.player_id=r.guest_id) g
        from answers a where a.room_code=r.code and a.round<r.question_count group by a.round) x
  where x.h is not null and x.g is not null;
 end if;
 return jsonb_build_object('code',r.code,'round',r.round,'question_count',r.question_count,'question_id',r.question_ids[r.round+1],
 'can_reroll',r.guest_id is not null and r.round<r.question_count and cardinality(r.seen_question_ids)<115 and not exists(select 1 from answers where room_code=r.code and round=r.round),
 'role',case when auth.uid()=r.host_id then 'host' else 'guest' end,'joined',r.guest_id is not null,'mine',mine,'theirs',theirs,'scores',all_scores,'answers',all_answers);
end $$;
revoke all on function public.game_state(text) from public;
grant execute on function public.game_state(text) to authenticated;
commit;
