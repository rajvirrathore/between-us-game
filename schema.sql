-- Run in Supabase SQL Editor. Never put a service-role key in the frontend.
create table public.rooms (
 code text primary key check (code ~ '^[A-Z0-9]{6}$'),
 host_id uuid not null,
 guest_id uuid,
 round integer not null default 0 check (round between 0 and 15),
 question_count integer not null default 15 check (question_count between 5 and 15),
 question_ids integer[] not null default array[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14],
 seen_question_ids integer[] not null default array[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14],
 constraint rooms_deck_length check (cardinality(question_ids) = question_count),
 created_at timestamptz not null default now()
);
create table public.answers (
 room_code text not null references public.rooms(code) on delete cascade,
 round integer not null check (round between 0 and 14),
 player_id uuid not null,
 value integer not null check (value between 0 and 100),
 primary key(room_code,round,player_id)
);
create index answers_room_round on public.answers(room_code,round);
alter table public.rooms enable row level security;
alter table public.answers enable row level security;

-- Only authenticated anonymous users who are players in a room can see it.
create policy "players read rooms" on public.rooms for select to authenticated using (auth.uid() = host_id or auth.uid() = guest_id);
create policy "players read answers only after both submitted" on public.answers for select to authenticated using (
 exists (select 1 from public.rooms r where r.code = room_code and (r.host_id = auth.uid() or r.guest_id = auth.uid()))
 and (player_id = auth.uid() or
   (select count(*) from public.answers a where a.room_code = answers.room_code and a.round = answers.round) = 2)
);
-- All writes are done via security-definer RPCs below.
create or replace function public.join_room(p_code text)
returns void language plpgsql security definer set search_path = public as $$
begin
 update rooms set guest_id = auth.uid()
 where code = upper(trim(p_code)) and guest_id is null and host_id <> auth.uid();
 if not found then raise exception 'Room unavailable or already full'; end if;
end $$;
create or replace function public.create_room(p_code text,p_question_count integer)
returns void language plpgsql security definer set search_path=public as $$
declare deck integer[];
begin
 if auth.uid() is null then raise exception 'Sign in before creating a room'; end if;
 if p_question_count is null or p_question_count not between 5 and 15 then raise exception 'Choose between 5 and 15 questions'; end if;
 select array_agg(id) into deck from (select id from generate_series(0,114) id order by random() limit p_question_count) q;
 insert into rooms(code,host_id,question_count,question_ids,seen_question_ids)
 values(p_code,auth.uid(),p_question_count,deck,deck);
end $$;

create or replace function public.submit_answer(p_code text,p_round integer,p_question_id integer,p_value integer)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or auth.uid() is null or (auth.uid() <> r.host_id and auth.uid() is distinct from r.guest_id) then raise exception 'Not a player in this room'; end if;
 if r.guest_id is null then raise exception 'Waiting for second player'; end if;
 if p_round is distinct from r.round or r.round >= r.question_count or p_question_id is distinct from r.question_ids[r.round+1] then raise exception 'Question changed. Please refresh and answer the current question'; end if;
 if p_value is null or p_value not between 0 and 100 then raise exception 'Invalid answer'; end if;
 insert into answers(room_code,round,player_id,value) values(r.code,r.round,auth.uid(),p_value)
 on conflict(room_code,round,player_id) do nothing;
end $$;

create or replace function public.reroll_question(p_code text,p_round integer,p_question_id integer)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; replacement integer;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or auth.uid() is null or (auth.uid() <> r.host_id and auth.uid() is distinct from r.guest_id) then raise exception 'Not a player in this room'; end if;
 if r.guest_id is null or r.round >= r.question_count then raise exception 'Room not ready'; end if;
 if p_round is distinct from r.round or p_question_id is distinct from r.question_ids[r.round+1] then raise exception 'Question already changed'; end if;
 if exists(select 1 from answers where room_code=r.code and round=r.round) then raise exception 'Cannot reroll after either player locks in an answer'; end if;
 select id into replacement from generate_series(0,114) id where not(id=any(r.seen_question_ids)) order by random() limit 1;
 if replacement is null then raise exception 'No fresh questions left in this room'; end if;
 r.question_ids[r.round+1] := replacement;
 update rooms set question_ids=r.question_ids,seen_question_ids=array_append(r.seen_question_ids,replacement) where code=r.code;
end $$;

create or replace function public.advance_round(p_code text,p_round integer)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or auth.uid() is distinct from r.host_id then raise exception 'Only host can advance'; end if;
 if p_round is distinct from r.round or r.guest_id is null or r.round >= r.question_count then raise exception 'Round already changed or room not ready'; end if;
 if (select count(*) from answers where room_code=r.code and round=r.round) <> 2 then raise exception 'Both players must answer'; end if;
 update rooms set round=round+1 where code=r.code;
end $$;

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
revoke all on function public.create_room(text,integer),public.submit_answer(text,integer,integer,integer),public.reroll_question(text,integer,integer),public.advance_round(text,integer),public.game_state(text) from public;
grant execute on function public.create_room(text,integer),public.submit_answer(text,integer,integer,integer),public.reroll_question(text,integer,integer),public.advance_round(text,integer),public.game_state(text) to authenticated;

revoke all on function public.join_room(text) from public;
grant execute on function public.join_room(text) to authenticated;
