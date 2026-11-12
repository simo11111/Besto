export type GameKey = 'haunted_camp';
export type GameMode = 'party';
export type GameDefinition = {
  readonly key: GameKey;
  readonly name: string;
  readonly desc: string;
  readonly players: string;
  readonly mode: GameMode;
  readonly minPlayers: number;
  readonly maxPlayers: number;
  readonly difficulty: 'social';
  readonly rewards: { readonly xp: number; readonly coins: number };
  readonly color: 'purple';
  readonly rules: readonly string[];
  readonly roundFlow: readonly string[];
};
export const games: readonly GameDefinition[] = [
  {
    key: 'haunted_camp',
    name: 'ليلة فالخيمة',
    desc: 'الفقيه والمسكون: أدوار سرية، حماية، نقاش وتصويت وسط مخيم غامض.',
    players: '4–10',
    mode: 'party',
    minPlayers: 4,
    maxPlayers: 10,
    difficulty: 'social',
    rewards: { xp: 50, coins: 10 },
    color: 'purple',
    rules: [
      'الطور العادي من 4 حتى 10 لاعبين: مسكون واحد وفقيه واحد والباقي مواطنين.',
      'الطور السريع من 4 لاعبين أو أكثر: مسكون واحد بلا فقيه.',
      'فالليل المسكون كيختار ضحية والفقيه كيحمي لاعباً؛ القرارات سرية.',
      'فالصباح كيبان غير واش مات شي حد أو نجا المخيم، بلا كشف الأدوار.',
      'فالنهار ناقشو وصوّتو على لاعب حي؛ التعادل كيعطي إعادة تصويت.',
      'المواطنين كيربحو إلا طردو المسكون؛ المسكون كيربح إلا بقا مواطن واحد أو أقل.'
    ],
    roundFlow: ['توزيع الأدوار السرية', 'ليل: قتل وحماية', 'صباح: إعلان النتيجة', 'نهار: نقاش وتصويت', 'كشف الأدوار والفائز']
  }
] as const;
