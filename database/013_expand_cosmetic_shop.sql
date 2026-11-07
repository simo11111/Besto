insert into public.cosmetic_catalog(id,name,category,price,rarity,preview) values
 ('frame_ocean','إطار المحيط','frame',350,'rare','🌊'),
 ('frame_shadow','إطار الظل','frame',650,'epic','🌑'),
 ('frame_royal','إطار ملكي','frame',1200,'legendary','💎'),
 ('frame_emerald','إطار الزمرد','frame',800,'epic','💚'),
 ('frame_sunset','إطار الغروب','frame',450,'rare','🌅'),
 ('title_champion','بطل الساحة','title',550,'epic','🥇'),
 ('title_night','فارس الليل','title',400,'rare','🌙'),
 ('title_diamond','نخبة الماس','title',1500,'legendary','💠'),
 ('title_sniper','ملك التركيز','title',600,'epic','🎯'),
 ('title_veteran','لاعب مخضرم','title',900,'legendary','🛡️'),
 ('title_lucky','وجه السعد','title',300,'rare','🍀'),
 ('title_comeback','ملك الريمونتادا','title',750,'epic','⚡')
on conflict(id) do update set name=excluded.name,category=excluded.category,price=excluded.price,rarity=excluded.rarity,preview=excluded.preview;