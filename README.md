# DIMA PLAY

منصة ألعاب اجتماعية مغربية بالدارجة، بتصميم Dark Gaming وتجربة Mobile-first.

## Stack
- Frontend: React + TypeScript + Vite + Tailwind + Supabase JS
- Backend: Node.js + Express + Zod + Helmet + rate limiting
- Database/Auth/Realtime: Supabase Postgres + Auth + RLS + private Broadcast
- Voice: WebRTC audio mesh (experimental; TURN server required for reliable production connectivity)
- PWA: manifest + service worker

## Setup
1. أنشئ مشروع Supabase.
2. شغّل database/001_initial.sql ثم database/002_rooms_chat_voice.sql في SQL Editor.
3. انسخ .env.example إلى .env داخل جذر المشروع وعمّر VITE_SUPABASE_URL و VITE_SUPABASE_ANON_KEY.
4. فعّل Email Auth في Supabase، واجعل قنوات Realtime private.
5. شغّل npm install ثم npm run dev.

## Implemented
- Email sign-up/sign-in through Supabase Auth.
- Transactional room creation, join-by-code and leave operations.
- Persistent rooms: leaving does not delete the room.
- Room roster and persisted room chat.
- Private Realtime Broadcast signaling restricted by room membership.
- WebRTC microphone audio mesh for small rooms (beta).

## Production limitations
- Voice mesh مناسب لغرف صغيرة (4–6 مشاركين كحد عملي). يلزم TURN server وبيانات اعتماد مؤقتة تصدر من الخادم لاجتياز NAT بشكل موثوق.
- صلاحيات Realtime مبنية على عضوية الغرفة؛ اعتبر أعضاء الغرفة أطرافاً موثوقين. يوصى بخادم signaling موثّق مستقل قبل الإطلاق العام الكبير.
- اضبط تأكيد البريد، سياسة كلمات المرور، SMTP، النسخ الاحتياطي، مراقبة الإساءة، والتبليغ والحظر.
- لم يُجرَ اختبار اختراق مستقل، ولا يوجد ادعاء بانعدام الثغرات.
- ممنوع رفع service-role keys أو كلمات مرور قاعدة البيانات أو TURN secrets إلى GitHub.
