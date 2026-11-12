# Mimox

منصة ألعاب اجتماعية مغربية بالدارجة، بتصميم Gaming داكن وتجربة Mobile-first وPWA.

## المنصة والتقنيات
- React 18 + TypeScript + Vite.
- Supabase Auth + PostgreSQL + RLS + Realtime.
- Cloudflare Pages للنشر.
- WebRTC للصوت المباشر داخل الغرف (mesh للمجموعات الصغيرة).

## الوظائف الموجودة
- تسجيل الدخول بالبريد وكلمة المرور، إنشاء حساب مع تأكيد البريد، واسترجاع/تغيير كلمة السر.
- تسجيل Google OAuth في الواجهة؛ يلزم إعداد Google Client ID وClient Secret في Supabase قبل استعماله.
- إنشاء غرف عامة وخاصة، والانضمام بكود، ومغادرة الغرفة.
- لائحة الغرف العامة وتحديث لائحة الأعضاء مباشرة.
- دردشة الغرفة مع تحديث فوري وحدود للرسائل.
- صوت مباشر مع كتم الميكروفون، وSTUN fallback. TURN ما زال يحتاج إعداد مفاتيح Cloudflare Realtime.
- رفع صور البروفايل وتخزينها في Supabase Storage بصلاحيات لكل مستخدم.
- ألعاب نصية مناسبة لشخصين أو أكثر (شكون فينا؟ وتحدي 10 ثواني) بدون فرض الميكروفون.
- خمس ألعاب جماعية: شفتي الديب؟، شكون فينا؟، شكون الكذاب؟، ممنوع تقولها، وتحدي 10 ثواني.
- احتساب النقاط وXP والعملات في PostgreSQL، مع تخزين نتائج الجولات.
- مهمات يومية ومكافأة يومية وسلسلة الدخول.
- متجر إطارات وألقاب، شراء وتجهيز العناصر.
- بروفايل، إحصائيات، إنجازات ولوحة المتصدرين.
- PWA قابلة للتثبيت على الهاتف.

## قاعدة البيانات
المigrations مطبقة على مشروع Supabase المرتبط. عند إعداد نسخة جديدة، طبّق الملفات بالترتيب:
1. `database/001_initial.sql`
2. `database/002_rooms_chat_voice.sql`
3. `database/003_competitive_games.sql`
4. `database/004_gameplay_hardening.sql`
5. `database/005_game_authorization_fixes.sql`
6. `database/006_voice_impostor_game.sql`
7. `database/007_impostor_scoring_fix.sql`
8. `database/008_foreign_key_indexes.sql`
9. `database/009_security_rls_hardening.sql`
10. `database/010_impostor_vote_tie.sql`
11. `database/011_restore_party_game_scoring.sql`
12. `database/012_daily_missions.sql`
13. `database/013_expand_cosmetic_shop.sql`
14. `database/014_gameplay_completion.sql`
15. `database/015_room_presence_realtime_index.sql`
16. `database/016_expand_party_game_prompts.sql`
17. `database/017_game_round_progress.sql`
18. `database/018_room_owner_handoff.sql`
19. `database/019_profile_avatars_and_two_player_games.sql`

لا تفتح schema `private` للـ Data API، ولا تضع service-role أو TURN secrets في الواجهة أو GitHub.

## إعداد وتشغيل الواجهة
1. انسخ `.env.example` إلى `.env`.
2. ضع `VITE_SUPABASE_URL` و`VITE_SUPABASE_PUBLISHABLE_KEY`.
3. فعّل Email Auth واضبط SMTP لتأكيد البريد.
4. في Supabase → Authentication → URL Configuration، اجعل Site URL هو `https://mimox-c5a.pages.dev` وأضف `https://mimox-c5a.pages.dev/**` إلى Redirect URLs.
5. لتفعيل Google: Authentication → Providers → Google، أدخل Google OAuth Client ID وClient Secret، ثم أضف Supabase Callback URL إلى Google Cloud Console.
6. شغّل `npm install` ثم `npm run dev`.

## الصوت
WebRTC mesh مناسب للمجموعات الصغيرة، لكن STUN وحده لا يضمن الاتصال عبر جميع أنواع NAT والشبكات. خدمة Worker تتحقق من جلسة Supabase وتصدر بيانات TURN مؤقتة، لكن يلزم إعداد `TURN_KEY_ID` وsecret باسم `TURN_API_TOKEN` داخل Worker. لا تضع هذه القيم في Vite env أو GitHub. إذا لم تكن مفاتيح TURN متوفرة، سيحاول التطبيق الاتصال المباشر عبر STUN وقد يفشل الصوت على بعض الشبكات.

## النشر والاختبار
- Cloudflare Pages project: `mimox`.
- Production URL: https://mimox-c5a.pages.dev
- GitHub: https://github.com/simo11111/Besto
- CI يبني TypeScript frontend/backend ويجري فحص npm audit.
- يجب اختبار التسجيل والغرف والألعاب والصوت بحسابين أو أكثر وعلى شبكات مختلفة قبل اعتبار الإصدار جاهزاً للإطلاق العام.
- لم يُجر اختبار اختراق مستقل، ولا يمكن ضمان خلو التطبيق من كل الثغرات.
- مجلد backend يحتوي حالياً API scaffold تجريبياً ولا تعتمد عليه الواجهة في الإنتاج؛ عمليات التطبيق الأساسية تنفذ عبر Supabase RPC.


## لعبة الفقيه والمسكون (Haunted Camp)

اللعبة الاجتماعية الجديدة كتخدم داخل غرف MIMOX من 4 حتى 10 لاعبين:
- الطور العادي (5–10): مسكون واحد، فقيه واحد، والباقي مواطنين.
- الطور السريع (4–10): مسكون واحد بلا فقيه؛ فـ4 لاعبين كيتفعّل تلقائياً كاختيار افتراضي.
- الليل فيه اختيار سري للضحية والحماية، والصباح كيعرض غير النتيجة العلنية، والنهار للنقاش والتصويت.
- التعادل الأول كيطلق إعادة التصويت؛ التعادل الثاني ما كيخرج حتى لاعب.
- الفوز للمواطنين بطرد المسكون، وللمسكون ملي كيبقا مواطن واحد أو أقل.

### قاعدة البيانات والأمان
- migration الجديدة: `database/033_haunted_camp_game.sql` (تجي بعد migrations 020–032 الموجودة فالمستودع وقاعدة البيانات).
- جميع الكتابات كتدوز من RPCs بـ `SECURITY DEFINER` و`search_path` ثابت، مع التحقق من `auth.uid()` وعضوية الغرفة.
- الواجهة ما كتقراش أدوار اللاعبين الآخرين ولا `haunted_night_actions`. قراءة الدور كتجي فقط من `get_haunted_game_state` للمستخدم الحالي، والأدوار الكاملة كتظهر بعد نهاية اللعبة فقط.
- جدول الأصوات كيسمح لكل لاعب يشوف غير صوته. قرارات الليل ما عندها حتى صلاحية قراءة من الـData API.
- Realtime كيتابع تغييرات اللعبة والأحداث العمومية؛ ما كنشتركوش مباشرة فـ`haunted_players` لأن بث صفوفه يقدر يسرّب الدور السري. تحديث قائمة اللاعبين كيدوز عبر RPC آمن.
- إذا انقطع اتصال مول اللعبة، أي عضو يقدر يحرّك المرحلة بعد انتهاء العداد، مع بقاء التحقق النهائي داخل PostgreSQL.

### الواجهة والصوت
- React component: `frontend/src/features/games/HauntedCampGame.tsx`.
- Hook: `frontend/src/hooks/useHauntedGame.ts`.
- Types: `frontend/src/types/haunted.ts`.
- المؤثرات كتتولد محلياً بـWeb Audio API وGainNode، بما فيها ambience ديال الليل، كشف الدور، الصباح، الموت، النجاة، التصويت والنهاية. هاد النسخة ما كتحتاجش MP3 خارجية؛ بالتالي الصوت الاصطناعي كيخدم Offline وما كايناش ملفات صوتية مضغوطة خاصها تتضاف للكاش.
- الأنيميشن CSS مع احترام `prefers-reduced-motion`، والتصميم Mobile-first.

### التحقق
- اختبارات القواعد: حماية الضحية، القتل، التعادل وإعادة التصويت، وشروط الفوز فـ`frontend/src/features/games/hauntedRules.test.ts`.
- خاص قبل الإطلاق اختبار Multiplayer يدوي بحسابات منفصلة (4 و6 لاعبين)، والتحقق من RLS، انقطاع الاتصال، المايك، والصوت على Android. نجاح Build أو اختبارات القواعد ما كيعوضش هاد الاختبار اليدوي.
