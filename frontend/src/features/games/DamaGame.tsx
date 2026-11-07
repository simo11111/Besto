import { useEffect, useMemo, useState } from 'react';
import { getLegalDamaMoves, isDamaDarkSquare, type DamaBoard, type DamaMove, type DamaPiece, type DamaPlayer } from './damaGame';
export type DamaGameState={session_id:string;board:number[];first_player:string;second_player:string;current_player:string;winner_user_id:string|null;is_draw:boolean;move_count:number;quiet_moves:number;version:number;updated_at:string};
type Props={state:DamaGameState;currentUserId:string;firstPlayerName:string;secondPlayerName:string;firstRating:number;secondRating:number;busy:boolean;canRematch:boolean;onRematch:()=>void;onMove:(path:number[])=>void};
const ownerOf=(piece:DamaPiece):DamaPlayer|null=>piece===1||piece===3?1:piece===2||piece===4?2:null;
export default function DamaGame({state,currentUserId,firstPlayerName,secondPlayerName,firstRating,secondRating,busy,canRematch,onRematch,onMove}:Props){
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
 const mandatoryCapture=legalMoves.some(move=>move.captures.length>0);
 const selectedCaptures=selection?.moves.some(move=>move.captures.length>0)??false;
 const firstActive=active&&state.current_player===state.first_player;
 const secondActive=active&&state.current_player===state.second_player;
 return <section className="dama-game" aria-label="الضامة المغربية">
  <div className="dama-game-head"><div className="dama-turn-info"><strong>{state.winner_user_id?'المباراة سالات':state.is_draw?'تعادل':myTurn?'دورك دابا':'الدور ديال الخصم'}</strong><small>{active?'الدور الحالي: '+currentName:state.is_draw?'تعادل بعد سلسلة نقلات هادئة':'الفائز: '+winnerName}</small></div><span className="dama-move-count">{state.move_count} نقلة</span></div>
  <div className="dama-player-strip">
   <article className={'dama-player-card first '+(firstActive?'turn-active':'')}><span className="dama-player-avatar">♟</span><span className="dama-player-data"><b>{firstPlayerName}</b><small>{firstActive?'الدور ديالو دابا':'اللاعب الأول'}</small></span><strong>{firstPieces}<small>قطع</small></strong><small className="duel-rating">{firstRating} MMR</small></article>
   <article className={'dama-player-card second '+(secondActive?'turn-active':'')}><span className="dama-player-avatar">♟</span><span className="dama-player-data"><b>{secondPlayerName}</b><small>{secondActive?'الدور ديالو دابا':'اللاعب الثاني'}</small></span><strong>{secondPieces}<small>قطع</small></strong><small className="duel-rating">{secondRating} MMR</small></article>
  </div>
  <div className="dama-board-shell"><div className="dama-board-label"><span>♛ MOROCCAN DAMA</span><span>{mandatoryCapture?'⚡ الأكل إجباري':'8 × 8 · مباراة تكتيكية'}</span></div>
   <div className="dama-board" role="grid" aria-label="رقعة الضامة" dir="ltr">{board.map((piece,index)=>{const dark=isDamaDarkSquare(index),selected=selection?.from===index,target=targets.includes(index),king=piece===3||piece===4;return <button type="button" role="gridcell" key={index} aria-label={'المربع '+(index+1)} disabled={!dark||!myTurn||busy} onClick={()=>chooseSquare(index)} className={['dama-square',dark?'dark':'light',selected?'selected':'',target?'legal-target':'',target&&mandatoryCapture?'capture-target':''].filter(Boolean).join(' ')}>{piece!==0&&<span className={'dama-piece '+(ownerOf(piece)===1?'first':'second')+(king?' king':'')}>{king?'♛':''}</span>}</button>;})}</div>
   <div className="dama-board-footer"><span>الأبيض {firstPieces}/12</span><span>{selection?'المسار: '+selection.path.map(index=>index+1).join(' ← '):'اختار قطعة باش تشوف النقلات'}</span><span>الأحمر {secondPieces}/12</span></div>
  </div>
  <div className="dama-action-hint">{myTurn?<><strong>{mandatoryCapture?'خاصك تاكل قطعة من الخصم':'دورك — اختار أحسن نقلة'}</strong><small>{selection?(selectedCaptures?'كمل سلسلة الأكل، ما تقدرش توقف فالنص.':'اختار الخانة المضيئة لإتمام النقلة.'):'النقلات القانونية كتظهر باللون الأخضر.'}</small></>:<><strong>{active?'الدور ديال '+currentName:'المباراة سالات'}</strong><small>{active?'كنستناو النقلة ديال الخصم…':'شوف النتيجة وعاود التحدي'}</small></>}</div>
  {active&&!myTurn&&<p className="dama-hint">كنستناو {currentName} يلعب…</p>}{active&&myTurn&&<p className="dama-hint">{selection?'اختار الخانة المضيئة باش تكمل النقلة.':'اختار قطعة ديالك؛ النقلات القانونية غادي يبانوا.'}</p>}{!active&&<><p className="dama-result">{state.is_draw?'🤝 تعادل! لعبتو مباراة متوازنة.':'🏆 '+winnerName+' ربح الضامة!'}</p>{canRematch?<button type="button" className="duel-rematch-btn" disabled={busy} onClick={onRematch}>↻ عاود المباراة</button>:<small className="dama-hint">كنستناو صاحب الغرفة يعاود المباراة.</small>}</>}
  <small className="dama-rules-note">8×8 · 12 قطعة لكل لاعب · القطعة العادية كتأكل للأمام فقط · الأكل إجباري وأكبر سلسلة كتربح، والدامة كتطير.</small>
 </section>;
}
