import type { ConnectFourBoard, Disc } from './connectFour';

export type DuelGameState = {
  session_id: string;
  board: number[];
  first_player: string;
  second_player: string;
  current_player: string;
  winner_user_id: string | null;
  is_draw: boolean;
  move_count: number;
  winning_cells: number[];
  version: number;
  updated_at: string;
};

type ConnectFourGameProps = {
  state: DuelGameState;
  currentUserId: string;
  firstPlayerName: string;
  secondPlayerName: string;
  busy: boolean;
  canRematch: boolean;
  onRematch: () => void;
  onMove: (column: number) => void;
};

export default function ConnectFourGame({
  state,
  currentUserId,
  firstPlayerName,
  secondPlayerName,
  busy,
  canRematch,
  onRematch,
  onMove
}: ConnectFourGameProps) {
  const active = !state.winner_user_id && !state.is_draw;
  const myTurn = state.current_player === currentUserId;
  const currentName = state.current_player === state.first_player ? firstPlayerName : secondPlayerName;
  const winnerName = state.winner_user_id === state.first_player ? firstPlayerName : secondPlayerName;
  const board = state.board as Disc[];
  const winningCells = new Set(state.winning_cells);

  return (
    <section className="connect-four-game" aria-label="لعبة أربعة فالسطر">
      <div className="connect-four-status">
        <div className="connect-four-turn">
          <span className={'connect-four-turn-dot ' + (state.current_player === state.first_player ? 'first' : 'second')} />
          <div>
            <strong>{state.winner_user_id ? 'المباراة سالات' : state.is_draw ? 'تعادل' : myTurn ? 'دورك دابا' : 'الدور ديال الخصم'}</strong>
            <small>{active ? 'الدور الحالي: ' + currentName : state.is_draw ? 'ما بقى حتى مكان فاللوحة' : 'الفائز: ' + winnerName}</small>
          </div>
        </div>
        <span className="connect-four-move-count">{state.move_count}/42 نقلة</span>
      </div>

      <div className="connect-four-board-wrap">
        <div className="connect-four-column-actions" dir="ltr">
          {Array.from({ length: 7 }, (_, column) => (
            <button
              type="button"
              key={column}
              aria-label={'العب فالعمود ' + (column + 1)}
              disabled={!active || !myTurn || busy || board[column] !== 0}
              onClick={() => onMove(column)}
            >
              ↓
            </button>
          ))}
        </div>
        <div className="connect-four-board" role="grid" aria-label="لوحة اللعب" dir="ltr">
          {board.map((disc, index) => (
            <div
              role="gridcell"
              aria-label={'الخانة ' + (index + 1)}
              key={index}
              className={[
                'connect-four-cell',
                disc === 1 ? 'disc-first' : '',
                disc === 2 ? 'disc-second' : '',
                winningCells.has(index) ? 'winning-cell' : ''
              ].filter(Boolean).join(' ')}
            >
              <span />
            </div>
          ))}
        </div>
      </div>

      <div className="connect-four-legend">
        <span><i className="connect-four-turn-dot first" />{firstPlayerName}</span>
        <span><i className="connect-four-turn-dot second" />{secondPlayerName}</span>
      </div>
      {active && !myTurn && <p className="connect-four-hint">كنستناو {currentName} يلعب…</p>}
      {active && myTurn && <p className="connect-four-hint">اختار العمود اللي بغيتي تهبط فيه القطعة.</p>}
      {!active && <><p className="connect-four-result">{state.is_draw ? '🤝 تعادل زوين!' : '🏆 ' + winnerName + ' ربح المباراة!'}</p>{canRematch?<button type="button" className="duel-rematch-btn" disabled={busy} onClick={onRematch}>↻ عاود المباراة</button>:<small className="connect-four-hint">كنستناو صاحب الغرفة يعاود المباراة.</small>}</>}
      <small className="connect-four-secure-note">كل نقلة كتتحقق فالخادم؛ ما يمكنش تبدل الدور أو النتيجة من المتصفح.</small>
    </section>
  );
}
