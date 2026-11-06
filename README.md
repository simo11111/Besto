# DIMA PLAY

منصة ألعاب اجتماعية مغربية بالدارجة، بتصميم Dark Gaming وتجربة Mobile-first وPWA.

## Stack
- React + TypeScript + Vite + Tailwind
- Supabase Auth + PostgreSQL + RLS + Realtime
- WebRTC صوت مباشر (STUN مبدئي؛ TURN مطلوب للإنتاج)

## إعداد قاعدة البيانات
شغّل ملفات SQL بالترتيب في Supabase SQL Editor:
1. `database/001_initial.sql`
2. `database/002_rooms_chat_voice.sql`
3. `database/003_competitive_games.sql`
4. `database/004_gameplay_hardening.sql`
5. `database/005_game_authorization_fixes.sql`
6. `database/006_voice_impostor_game.sql`
7. `database/007_impostor_scoring_fix.sql`
8. `database/008_foreign_key_indexes.sql`

إذا كان Data API عندك مضبوطاً على قائمة schemas/tables محددة، تأكد أن `public` exposed وأن صلاحيات SELECT الممنوحة في migrations مفعلة. لا تفتح private schema للـ Data API.

## إعداد التطبيق
1. انسخ `.env.example` إلى `.env` في جذر المشروع.
2. ضع `VITE_SUPABASE_URL` و`VITE_SUPABASE_PUBLISHABLE_KEY` من Project Connect.
3. فعّل Email Auth وتأكيد البريد، واضبط SMTP قبل الإطلاق العام.
4. شغّل `npm install` ثم `npm run dev`.

## الألعاب
- **شفتي الديب؟** أدوار سرية وتصويت لاكتشاف الذئب.
- **شكون فينا؟** سؤال اجتماعي وتصويت على اللاعب الأكثر انطباقاً.
- **شكون الكذاب؟** كلمة سرية يعرفها الجميع إلا لاعب واحد. كل لاعب يطرح سؤالاً شفوياً على لاعب آخر؛ اللاعبون الذين توجّهت إليهم الأسئلة يردّون بتلميح غير مباشر عبر الصوت. بعد اكتمال الأسئلة والتلميحات يصوت الجميع لكشف الكذاب.

الألعاب الاجتماعية تعتمد على الكلام والصوت داخل الغرفة؛ لا توجد خانات لكتابة أجوبة لعبة الكذاب. التصويت يتم من الواجهة.

احتساب النتائج وXP والعملات يتم داخل PostgreSQL RPC وليس من متصفح اللاعب. المستويات والإنجازات والمتجر والمكافأة اليومية ولوحة المتصدرين مرتبطة بقاعدة البيانات.

## Voice
WebRTC mesh مناسب للمجموعات الصغيرة فقط. STUN وحده لا يضمن الاتصال عبر جميع أنواع NAT والشبكات؛ أضف TURN service موثوقاً وبيانات اعتماد قصيرة الأجل عبر خادم آمن قبل الإنتاج. لا تضع TURN secrets في Vite env.

## Security / release checklist
- RLS مفعّل على جداول public.
- أدوار الذئب وكلمات اللعبة السرية في schema غير مكشوفة.
- RPCs تتحقق من auth.uid وعضوية الغرفة وصلاحية صاحب الغرفة.
- عمليات العملات والمكافآت ونتائج الجولات تُحسب في قاعدة البيانات.
- راجع Supabase Security/Performance Advisors بعد تطبيق migrations.
- اختبر تسجيل الدخول، إنشاء/الانضمام/الخروج، الغرف الخاصة، chat، الصوت على شبكات مختلفة، وتزامن لاعبين متعددين.
- CI يبني TypeScript frontend/backend ويفشل عند ثغرات npm عالية الخطورة.
- لم يُجر اختبار اختراق مستقل؛ لا يوجد ادعاء بأن التطبيق خالٍ 100% من الثغرات.
- ممنوع رفع service-role/secret keys أو كلمات مرور قاعدة البيانات أو TURN credentials إلى GitHub.
