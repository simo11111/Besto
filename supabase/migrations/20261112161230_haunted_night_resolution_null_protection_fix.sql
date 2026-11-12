-- Preserve NOT NULL protection flags when the Faqih does not submit a choice.
create or replace function public.resolve_haunted_night(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
 v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_action public.haunted_night_actions%rowtype;
 v_killed uuid; v_protected uuid; v_alive integer; v_villagers integer; v_result jsonb;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user) then raise exception 'ما عندكش الحق فهاد الغرفة'; end if;
 if v_game.status<>'night' then return jsonb_build_object('status',v_game.status); end if;
 if v_game.phase_deadline_at>now() then raise exception 'وقت الليل مازال ما سالاش'; end if;
 select * into v_action from public.haunted_night_actions where game_id=p_game_id and round=v_game.round for update;
 v_killed:=case when v_action.haunter_target is null then null when v_action.haunter_target=v_action.faqih_target then null else v_action.haunter_target end;
 v_protected:=v_action.faqih_target;
 if v_killed is not null then update public.haunted_players set is_alive=false where game_id=p_game_id and user_id=v_killed and is_alive; end if;
 update public.haunted_players set is_protected_this_night=(v_protected is not null and user_id=v_protected) where game_id=p_game_id;
 update public.haunted_night_actions set resolved=true,killed_user_id=v_killed,protected_user_id=v_protected where game_id=p_game_id and round=v_game.round;
 select count(*) into v_villagers from public.haunted_players where game_id=p_game_id and role<>'haunter' and is_alive;
 select count(*) into v_alive from public.haunted_players where game_id=p_game_id and is_alive;
 if v_alive<=1 or v_villagers<=1 then
  update public.haunted_games set status='day',phase_deadline_at=now()+interval '1 second' where id=p_game_id;
 else
  update public.haunted_games set status='morning',phase_deadline_at=now()+interval '15 seconds' where id=p_game_id;
 end if;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(p_game_id,v_game.round,'night_resolved',jsonb_build_object('killed_user_id',v_killed,'message',case when v_killed is null then 'الليلة دازت بسلام، ما مات حتى واحد.' else 'لقينا واحد من اللاعبين ميت فالصباح.' end));
 v_result:=jsonb_build_object('killed_user_id',v_killed);
 if v_alive<=1 or v_villagers<=1 then perform private.finish_haunted_game(p_game_id,'haunter'); end if;
 return v_result;
end;
$function$;
revoke all on function public.resolve_haunted_night(uuid) from public,anon;
grant execute on function public.resolve_haunted_night(uuid) to authenticated;
