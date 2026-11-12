-- Give a human faqih a full, visible turn after the haunter chooses.
create or replace function private.notify_haunted_faqih_turn()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_mode text;
  v_human_faqih boolean := false;
begin
  if new.haunter_target is not null
     and (tg_op = 'INSERT' or old.haunter_target is distinct from new.haunter_target) then
    select game_mode into v_mode from public.haunted_games where id = new.game_id;
    if v_mode = 'standard' then
      select exists (
        select 1 from public.haunted_players
        where game_id = new.game_id and role = 'faqih' and is_alive and not is_bot
      ) into v_human_faqih;
      if v_human_faqih then
        update public.haunted_games
        set phase_deadline_at = now() + interval '30 seconds', bot_next_action_at = null
        where id = new.game_id and status = 'night';
      end if;
      insert into public.haunted_events(game_id, round, event_type, payload)
      values (new.game_id, new.round, 'faqih_turn_opened',
        jsonb_build_object('message', 'المسكون اختار الضحية. دابا جا دور الفقيه.', 'role_turn', 'faqih'));
    end if;
  end if;
  return new;
end;
$function$;

-- Replace repetitive generic bot lines with a varied Darija phrase pool.
create or replace function private.rewrite_haunted_bot_chat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_message text;
  v_phrases text[] := array[
    'واحد فيكم كيهضر بزاف ولكن ما جاوبش على السؤال اللي تسول ليه.',
    'خلّيو كل واحد يشرح فين كان ملي هبط الليل.',
    'أنا شاك فالتصرفات، ماشي غير فالهضرة.',
    'واش حتى نتوما لاحظتو شكون تبدل كلامو من الصباح؟',
    'ما بغيتش نظلم شي واحد، ولكن خاصنا نركزو فالتفاصيل.',
    'كاين شي واحد كيبغي يسرّع التصويت بلا دليل.',
    'سمعت واحد الحركة حد الخيمة، وباقي ما فهمتش شنو وقع.',
    'كل واحد يقول شنو لاحظ، يمكن نجمعو الخيوط.',
    'اللي واثق من الشك ديالو يعطينا السبب، ماشي غير الاسم.',
    'ما تنساوش أن المسكون يقدر يبان هادئ بحالنا كاملين.',
    'أنا باقي كنقارن بين التصرفات ديال الجولة اللي فاتت.',
    'علاش هاد اللاعب ساكت منين كنهدرو على الليل؟',
    'خاصنا نسمعو لبعضياتنا قبل ما نحسمو فشي تصويت.',
    'شي جواب اليوم ما راكبش مع اللي تقال البارح.',
    'ماشي كل واحد كيدافع على راسو راه بريء، ركزو مزيان.',
    'إلا عند شي واحد قرينة يقولها دابا باش ما نضيعوش الوقت.',
    'كنفضّل نصبر شوية على أن نصوّت بلا ما نفهم.',
    'واش كاين شي حد لاحظ شكون كان أول واحد بدّل الموضوع؟'
  ];
begin
  if new.event_type <> 'bot_chat'
     or coalesce(new.payload->>'system', 'false') = 'true'
     or not (new.payload ? 'bot_user_id')
     or new.payload->>'bot_user_id' is null then
    return new;
  end if;
  select phrase into v_message
  from unnest(v_phrases) as phrase
  where not exists (
    select 1 from (
      select payload->>'message' as message
      from public.haunted_events
      where game_id = new.game_id and round = new.round
        and event_type = 'bot_chat' and payload ? 'bot_user_id'
      order by created_at desc limit 5
    ) recent where recent.message = phrase
  )
  order by random() limit 1;
  if v_message is null then
    select phrase into v_message from unnest(v_phrases) as phrase order by random() limit 1;
  end if;
  new.payload := jsonb_set(new.payload, '{message}', to_jsonb(v_message), true);
  return new;
end;
$function$;

drop trigger if exists haunted_bot_chat_variety on public.haunted_events;
create trigger haunted_bot_chat_variety
before insert on public.haunted_events
for each row execute function private.rewrite_haunted_bot_chat();
