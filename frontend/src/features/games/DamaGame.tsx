import { useEffect, useMemo, useState } from 'react';
import { getLegalDamaMoves, isDamaDarkSquare, type DamaBoard, type DamaMove, type DamaPiece, type DamaPlayer } from './damaGame';
export type DamaGameState={session_id:string;board:number[];first_player:string;second_player:string;current_player:string;winner_user_id:string|null;is_draw:boolean;move_count:number;quiet_moves:number;version:number;updated_at:string};
type Props={state:DamaGameState;currentUserId:string;firstPlayerName:string;secondPlayerName:string;busy:boolean;onMove:(path:number[])=>void};
const ownerOf=(piece:DamaPiece):DamaPlayer|null=>piece===1||piece===3?1:piece===2||piece===4?2:null;
export default function DamaGame({state,currentUserId,firstPlayerName,secondPlayerName,busy,onMove}:Props){
 const board=state.board as DamaBoard;
 const myPlayer:DamaPlayer=currentUserId===state.first_player?1:2;
 const active=!state.winner_user_id&&!state.is_draw;
 const myTurn=active&&state.current_player===currentUserId;
 const currentName=state.current_player===state.first_player?firstPlayerName:secondPlayerName;
 const winnerName=state.winner_user_id===state.first_player?firstPlayerName:secondPlayerName;
 const legalMoves=useMemo(()=>getLegalDamaMoves(board,myPlayer),[state.board,myPlayer]);
 const [selection,setSelection]=useState<{from:number;path:number[];moves:DamaMove[]}|null>(null);
 useEffect(()=>setSelection(null),[state.version]);
 const targets=selection?[...new Set(selection.moves.map(move=>move.path[selection.path.length]))]:[];
 function chooseSquare(index:number){
  if(!myTurn||busy||!isDamaDarkSquare(index))return;
  if(!selection){if(ownerOf(board[index])===myPlayer)setSelection({from:index,path:[],moves:legalMoves.filter(move=>move.from===index)});return;}
  const matching=selection.moves.filter(move=>move.path[selection.path.length]===index);
  if(matching.length){
   const path=[...selection.path,index],complete=matching.find(move=>move.path.length===path.length);
   if(complete){onMove([selection.from,...path]);setSelection(null);}else setSelection({from:selection.from,path,moves:matching});
   return;
  }
  if(ownerOf(board[index])===myPlayer)setSelection({from:index,path:[],moves:legalMoves.filter(move=>move.from===index)});else setSelection(null);
 }
 const firstPieces=board.filter(piece=>ownerOf(piece)===1).length,secondPieces=board.filter(piece=>ownerOf(piece)===2).length;
 return <section className="dama-game" aria-label="الضامة المغربية">
  <div className="dama-game-head"><div className="dama-turn-info"><strong>{state.winner_user_id?'المباراة سالات':state.is_draw?'تعادل':myTurn?'دورك دابا':'الدور ديال الخصم'}</strong><small>{active?'الدور الحالي: '+currentName:state.is_draw?'تعادل بعد سلسلة نقلات هادئة':'الفائز: '+winnerName}</small></div><span className="dama-move-count">{state.move_count} نقلة</span></div>
  <div className="dama-score-strip"><span><i className="dama-piece-dot first"/>{firstPlayerName} <b>{firstPieces}</b></span><span><i className="dama-piece-dot second"/>{secondPlayerName} <b>{secondPieces}</b></span></div>
  <div className="dama-board" role="grid" aria-label="رقعة الضامة" dir="ltr">{board.map((piece,index)=>{const dark=isDamaDarkSquare(index),selected=selection?.from===index,target=targets.includes(index),king=piece===3||piece===4;return <button type="button" role="gridcell" key={index} aria-label={'المربع '+(index+1)} disabled={!dark||!myTurn||busy} onClick={()=>chooseSquare(index)} className={['dama-square',dark?'dark':'light',selected?'selected':'',target?'legal-target':''].filter(Boolean).join(' ')}>{piece!==0&&<span className={'dama-piece '+(ownerOf(piece)===1?'first':'second')+(king?' king':'')}>{king?'♛':''}</span>}</button>;})}</div>
  {active&&!myTurn&&<p className="dama-hint">كنستناو {currentName} يلعب…</p>}{active&&myTurn&&<p className="dama-hint">{selection?'اختار الخانة المضيئة باش تكمل النقلة.':'اختار قطعة ديالك؛ النقلات القانونية غادي يبانوا.'}</p>}{!active&&<p className="dama-result">{state.is_draw?'🤝 تعادل! لعبتو مباراة متوازنة.':'🏆 '+winnerName+' ربح الضامة!'}</p>}
  <small className="dama-rules-note">8×8 · 12 قطعة لكل لاعب · الأكل إجباري · خاصك تختار أكبر سلسلة أكل، والدامة كتتحرك بعيداً.</small>
 </section>;
}
