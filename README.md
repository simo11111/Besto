# DIMA PLAY

منصة ألعاب اجتماعية مغربية بالدارجة، بتصميم Dark Gaming وتجربة Mobile-first.

## Stack
- Frontend: React + TypeScript + Vite + Tailwind
- Backend: Node.js + Express + Zod + Helmet + rate limiting
- Database/Auth: Supabase (Postgres + Auth + RLS)
- PWA: manifest + service worker

## التشغيل المحلي
1. نسخ `.env.example` إلى `.env` وإعداد متغيرات Supabase.
2. تشغيل `npm install`.
3. تشغيل `npm run dev`.

الواجهة على المنفذ 5173 والـ API على 4000.

## الحالة الحالية
هذه نسخة تأسيسية قابلة للتطوير وليست منصة Multiplayer جاهزة للإطلاق. واجهة الألعاب موجودة، لكن إنشاء الغرف وتسجيل الدخول وحفظ الجولات والصوت الجماعي لم تكتمل بعد. API الحالي يتحقق من بيانات الغرفة فقط ولا ينشئها أو يحفظها.

قبل الإطلاق يجب إكمال مصادقة Supabase والتحقق من صلاحيات المستخدم في الخادم، وسياسات RLS وعمليات الغرف والجولات، وإشارات WebRTC مع STUN/TURN، ثم إجراء اختبارات أمنية ووظيفية.

**مهم:** لا تضع Supabase service-role key أو أسرار TURN في كود الواجهة أو GitHub. احتفظ بها في متغيرات بيئة الخادم.
