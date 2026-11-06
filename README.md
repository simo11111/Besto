# Mimox

منصة ألعاب اجتماعية مغربية بالدارجة، بتصميم Gaming داكن وتجربة Mobile-first وPWA.

## المنصة والتقنيات
- React 18 + TypeScript + Vite.
- Supabase Auth + PostgreSQL + RLS + Realtime.
- Cloudflare Pages للنشر.
- WebRTC للصوت المباشر داخل الغرف (mesh للمجموعات الصغيرة).

## الوظائف الموجودة
- تسجيل الدخول بالبريد وكلمة المرور، وإنشاء حساب مع تأكيد البريد.
- تسجيل Google OAuth في الواجهة؛ يلزم إعداد Google Client ID وClient Secret في Supabase قبل استعماله.
- إنشاء غرف عامة وخاصة، والانضمام بكود، ومغادرة الغرفة.
- لائحة الغرف العامة وتحديث لائحة الأعضاء مباشرة.
- دردشة الغرفة مع تحديث فوري وحدود للرسائل.
- صوت مباشر مع كتم الميكروفون، وSTUN fallback. TURN ما زال يحتاج إعداد مفاتيح Cloudflare Realtime.
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
