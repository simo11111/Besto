import { Swords, Users, Zap } from 'lucide-react';
import type { GameDefinition } from './registry';

type GameCardProps = { game: GameDefinition; selected?: boolean; onClick: () => void };
const modeLabel = (mode: GameDefinition['mode']) => mode === 'duel' ? 'مواجهة 1 ضد 1' : 'لعبة جماعية';
const difficultyLabel = (difficulty: GameDefinition['difficulty']) => difficulty === 'competitive' ? 'تنافسية' : difficulty === 'casual' ? 'خفيفة' : 'اجتماعية';

export default function GameCard({ game, selected = false, onClick }: GameCardProps) {
  return (
    <button type="button" className={'game-card premium-game-card ' + (selected ? 'selected' : '')} onClick={onClick} aria-pressed={selected} aria-label={'اختيار لعبة ' + game.name}>
      <div className="premium-game-art">
        <img src={'/games/' + game.key + '.svg'} alt="" loading="lazy" />
        <span className={'game-mode-chip ' + game.mode}>{game.mode === 'duel' ? <Swords size={12} /> : <Users size={12} />}{modeLabel(game.mode)}</span>
        <span className="game-difficulty-chip">{difficultyLabel(game.difficulty)}</span>
      </div>
      <div className="premium-game-copy">
        <div className="premium-game-title-row"><h3>{game.name}</h3><span className="premium-game-players">{game.players}</span></div>
        <p>{game.desc}</p>
      </div>
      <div className="premium-game-footer"><span><Zap size={13} /> {game.rewards.xp} XP</span><span className="premium-game-cta">{selected ? 'مختارة' : 'شوف القواعد ←'}</span></div>
    </button>
  );
}
