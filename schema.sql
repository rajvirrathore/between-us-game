-- Run in Supabase SQL Editor. Never put a service-role key in the frontend.
create table public.rooms (
 code text primary key check (code ~ '^[A-Z0-9]{6}$'),
 host_id uuid not null,
 guest_id uuid,
 round integer not null default 0 check (round between 0 and 15),
 created_at timestamptz not null default now()
);
create table public.answers (
 room_code text not null references public.rooms(code) on delete cascade,
 round integer not null check (round between 0 and 14),
 player_id uuid not null,
 value integer not null check (value between 1 and 5),
 primary key(room_code,round,player_id)
);
create index answers_room_round on public.answers(room_code,round);
alter table public.rooms enable row level security;
alter table public.answers enable row level security;

-- Only authenticated anonymous users who are players in a room can see it.
create policy "players read rooms" on public.rooms for select to authenticated using (auth.uid() = host_id or auth.uid() = guest_id);
create policy "create own room" on public.rooms for insert to authenticated with check (host_id = auth.uid() and guest_id is null and round = 0);
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
create or replace function public.submit_answer(p_code text,p_round integer,p_value integer)
returns void language plpgsql security definer set search_path = public as $$
declare r rooms%rowtype;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or auth.uid() is null or (auth.uid() <> r.host_id and auth.uid() is distinct from r.guest_id) then raise exception 'Not a player in this room'; end if;
 if r.guest_id is null then raise exception 'Waiting for second player'; end if;
 if r.round <> p_round or p_round < 0 or p_round >= 15 or p_value not between 1 and 5 then raise exception 'Invalid round or answer'; end if;
 insert into answers(room_code,round,player_id,value) values(r.code,p_round,auth.uid(),p_value)
 on conflict(room_code,round,player_id) do nothing;
end $$;
create or replace function public.advance_round(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare r rooms%rowtype;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or auth.uid() is distinct from r.host_id then raise exception 'Only host can advance'; end if;
 if r.guest_id is null or r.round >= 15 then raise exception 'Room not ready'; end if;
 if (select count(*) from answers where room_code=r.code and round=r.round) <> 2 then raise exception 'Both players must answer'; end if;
 update rooms set round=round+1 where code=r.code;
end $$;
-- RPC for private per-player status and reveal after both answers; no unrestricted answer access.
create or replace function public.game_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; mine integer; theirs integer; all_scores jsonb; result jsonb;
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
 result=jsonb_build_object('code',r.code,'round',r.round,'role',case when auth.uid()=r.host_id then 'host' else 'guest' end,'joined',r.guest_id is not null,'mine',mine,'theirs',theirs,'scores',all_scores);
 return result;
end $$;
revoke all on function public.join_room(text),public.submit_answer(text,integer,integer),public.advance_round(text),public.game_state(text) from public;
grant execute on function public.join_room(text),public.submit_answer(text,integer,integer),public.advance_round(text),public.game_state(text) to authenticated;
-- Authenticated users need room insert; direct room updates and answer inserts are denied.
