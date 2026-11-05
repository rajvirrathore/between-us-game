-- Existing Supabase projects: run once in SQL Editor before using the new app.
-- Deploy between games and have both players reload afterward.
begin;
lock table public.answers in access exclusive mode;
alter table public.answers drop constraint answers_value_check;
-- Preserve the relative positions and scores of existing 1–5 answers.
update public.answers set value = (value - 1) * 25;
alter table public.answers add constraint answers_value_check check (value between 0 and 100);

create or replace function public.submit_answer(p_code text,p_round integer,p_value integer)
returns void language plpgsql security definer set search_path = public as $$
declare r rooms%rowtype;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or auth.uid() is null or (auth.uid() <> r.host_id and auth.uid() is distinct from r.guest_id) then raise exception 'Not a player in this room'; end if;
 if r.guest_id is null then raise exception 'Waiting for second player'; end if;
 if r.round <> p_round or p_round < 0 or p_round >= 15 or p_value is null or p_value not between 0 and 100 then raise exception 'Invalid round or answer'; end if;
 insert into answers(room_code,round,player_id,value) values(r.code,p_round,auth.uid(),p_value)
 on conflict(room_code,round,player_id) do nothing;
end $$;
revoke all on function public.submit_answer(text,integer,integer) from public;
grant execute on function public.submit_answer(text,integer,integer) to authenticated;
commit;
