import { Gamepad2, Users } from 'lucide-react';
import type { GameDefinition } from './registry';

type GameCardProps = {
  game: GameDefinition;
  selected?: boolean;
  onClick: () => void;
};

export default function GameCard({ game, selected = false, onClick }: GameCardProps) {
  return (
    <button className={'game-card ' + (selected ? 'selected' : '')} onClick={onClick}>
      <div className="game-top">
        <img className="game-icon-image" src={'/games/' + game.key + '.svg'} alt="" />
        <span className="tag">{game.players} لاعبين</span>
      </div>
      <h3>{game.name}</h3>
      <p>{game.desc}</p>
      <div className="game-bottom">
        <span><Users size={14} />{game.players}</span>
        <span className="play-link">التفاصيل ←</span>
      </div>
    </button>
  );
}
