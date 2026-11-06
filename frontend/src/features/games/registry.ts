export type GameKey = 'wolf' | 'who' | 'impostor' | 'forbidden' | 'ten_seconds' | 'connect4';
export type GameMode = 'party' | 'duel';
export type GameDefinition = {
  readonly key: GameKey;
  readonly name: string;
  readonly desc: string;
  readonly players: string;
  readonly mode: GameMode;
  readonly minPlayers: number;
  readonly maxPlayers: number;
  readonly difficulty: 'social' | 'casual' | 'competitive';
  readonly rewards: { readonly xp: number; readonly coins: number };
  readonly color: 'purple' | 'pink' | 'orange' | 'mint' | 'amber' | 'blue';
  readonly rules: readonly string[];
  readonly roundFlow: readonly string[];
};
export const games: readonly GameDefinition[] = [
  { key:'wolf', name:'شفتي الديب؟', desc:'واحد فيكم ذيب… واش غادي تكشفوه قبل ما يهرب؟', players:'4–12', mode:'party', minPlayers:4, maxPlayers:12, difficulty:'social', rewards:{xp:35,coins:15}, color:'purple', rules:['كل لاعب كياخذ دور سري: ذيب أو قروي.','تناقشو وحاولو تعرفو شكون الذئب.','صوّتو على اللاعب المشكوك فيه.','إلا تصاد الذئب، القرويين كيربحو النقاط.'], roundFlow:['توزيع الأدوار السرية','نقاش جماعي','تصويت سري','كشف الذئب والنتيجة'] },
  { key:'who', name:'شكون فينا؟', desc:'سؤال واحد، وتصويتات كثيرة… والضحك مضمون.', players:'2–16', mode:'party', minPlayers:2, maxPlayers:16, difficulty:'social', rewards:{xp:25,coins:10}, color:'pink', rules:['كيبان سؤال على المجموعة.','كل لاعب كيختار الشخص اللي كينطبق عليه السؤال.','كتبان نتيجة التصويت والتعليقات.','الأكثر تصويتاً كيربح نقاط الجولة.'], roundFlow:['السؤال','تصويت سري','كشف الأصوات','ترتيب الجولة'] },
  { key:'impostor', name:'شكون الكذاب؟', desc:'واحد ما عارفش الكلمة… واش غادي تكشفوه؟', players:'4–12', mode:'party', minPlayers:4, maxPlayers:12, difficulty:'social', rewards:{xp:40,coins:20}, color:'orange', rules:['كلشي كيعرف نفس الكلمة ما عدا الكذاب.','كل لاعب كيسول لاعباً آخر سؤالاً.','الجواب يكون تلميح خفيف بلا ما يفضح الكلمة.','من بعد الأسئلة، صوّتو على اللي شاكّين فيه.'], roundFlow:['توزيع الكلمة السرية','أسئلة وتلميحات','تصويت سري','كشف الكذاب والكلمة'] },
  { key:'forbidden', name:'ممنوع تقولها', desc:'شرح الكلمة بلا ما تقرب للكلمات الممنوعة.', players:'3–12', mode:'party', minPlayers:3, maxPlayers:12, difficulty:'social', rewards:{xp:30,coins:15}, color:'mint', rules:['لاعب واحد كيشوف الكلمة والكلمات الممنوعة.','شرحها لصحابك بالصوت بلا ما تستعمل الكلمات الممنوعة.','الباقي يحاولو يخمّنو الكلمة.','كل تخمين صحيح كيزيد نقاط الفريق.'], roundFlow:['اختيار الشارح','شرح الكلمة','تخمينات اللاعبين','كشف الكلمة واحتساب النقاط'] },
  { key:'ten_seconds', name:'تحدي 10 ثواني', desc:'سؤال سريع: اختار الجواب الصحيح أو جمع أكبر عدد من الأجوبة قبل ما يسالي الوقت.', players:'2–12', mode:'party', minPlayers:2, maxPlayers:12, difficulty:'casual', rewards:{xp:25,coins:10}, color:'amber', rules:['كل جولة فيها 10 ثواني فقط.','إلا كان السؤال باختيارات، اختار جواب واحد.','إلا طلب منك تسمي 3 حاجات، كتبهم مفصولين بفاصلة.','كل جواب صحيح كيعطي نقاط؛ الأجوبة المكررة ما كتزيدش نقاط.'], roundFlow:['ظهور التحدي','عداد 10 ثواني','إغلاق الإجابات','كشف الأجوبة والنقاط'] },
  { key:'connect4', name:'أربعة فالسطر', desc:'مواجهة مباشرة بين جوج لاعبين. أول واحد يصفّ 4 قطع كيربح.', players:'2', mode:'duel', minPlayers:2, maxPlayers:2, difficulty:'competitive', rewards:{xp:40,coins:20}, color:'blue', rules:['كل لاعب كيلعب بقطعته الخاصة.','اختار العمود، والقطعة كتهبط لأول خانة خاوية.','جمع 4 قطع متصلة أفقياً أو عمودياً أو قطرياً.','كل نقلة كتتحقق فالخادم، والدور كيتبدل تلقائياً.'], roundFlow:['دخول لاعبين','تحديد أول لاعب','نقلات بالتناوب','فوز أو تعادل وتحديث التصنيف'] }
] as const;
