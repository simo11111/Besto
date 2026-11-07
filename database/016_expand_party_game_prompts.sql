insert into public.game_prompts(game_key,prompt,accepted_answers,forbidden_words)
select v.game_key,v.prompt,v.answers,v.forbidden
from (values
 ('ten_seconds','سمي 3 أكلات مغربية مشهورة',array['طاجين','كسكس','حريرة','بسطيلة','رفيسة','بغرير']::text[],array[]::text[]),
 ('ten_seconds','سمي 3 أشياء كتلقاها فالقسم',array['سبورة','قلم','كتاب','كرسي','طاولة','دفتر','محفظة']::text[],array[]::text[]),
 ('ten_seconds','سمي 3 حيوانات أليفة',array['قط','كلب','عصفور','سمكة','أرنب','سلحفاة']::text[],array[]::text[]),
 ('ten_seconds','سمي 3 وسائل نقل',array['سيارة','طوبيس','حافلة','قطار','طائرة','دراجة','دراجة نارية']::text[],array[]::text[]),
 ('ten_seconds','سمي 3 حاجات كتكون باردة',array['ثلج','ماء','عصير','آيس كريم','مثلجات']::text[],array[]::text[]),
 ('ten_seconds','سمي 3 مدن مغربية أخرى',array['الحسيمة','الناظور','العرائش','خريبكة','بني ملال','الداخلة','العيون']::text[],array[]::text[]),
 ('forbidden','الكلمة هي: شمس',array['شمس','الشمس']::text[],array['ضو','نهار','سخون','سماء']::text[]),
 ('forbidden','الكلمة هي: مدرسة',array['مدرسة','المدرسة']::text[],array['أستاذ','تلميذ','قسم','قراية']::text[]),
 ('forbidden','الكلمة هي: طيارة',array['طيارة','طائرة']::text[],array['سما','مطار','سفر','جناح']::text[]),
 ('forbidden','الكلمة هي: قهوة',array['قهوة','القهوة']::text[],array['كاس','كافيين','صباح','مرة']::text[]),
 ('forbidden','الكلمة هي: أسد',array['أسد','الأسد']::text[],array['غابة','ملك','حيوان','زئير']::text[]),
 ('forbidden','الكلمة هي: تلفاز',array['تلفاز','تلفزيون']::text[],array['قنوات','ريموت','شاشة','مسلسلات']::text[]),
 ('who','شكون فيكم يقدر ينسى عيد ميلاد صاحبو؟',array[]::text[],array[]::text[]),
 ('who','شكون فيكم غالباً كيتأخر على الموعد؟',array[]::text[],array[]::text[]),
 ('who','شكون فيكم يقدر يضحك فموقف جدي؟',array[]::text[],array[]::text[]),
 ('who','شكون فيكم عندو حظ كبير فالألعاب؟',array[]::text[],array[]::text[]),
 ('impostor','الكسكس',array['الكسكس']::text[],array[]::text[]),
 ('impostor','الثلج',array['الثلج']::text[],array[]::text[]),
 ('impostor','المسبح',array['المسبح']::text[],array[]::text[]),
 ('impostor','الطبيب',array['الطبيب']::text[],array[]::text[]),
 ('impostor','السوق',array['السوق']::text[],array[]::text[]),
 ('impostor','المدرسة',array['المدرسة']::text[],array[]::text[])
) as v(game_key,prompt,answers,forbidden)
where not exists(select 1 from public.game_prompts p where p.game_key=v.game_key and p.prompt=v.prompt);
