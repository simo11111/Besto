export type DamaPlayer = 1 | 2;
export type DamaPiece = 0 | 1 | 2 | 3 | 4;
export type DamaBoard = DamaPiece[];
export type DamaMove = { from: number; path: number[]; captures: number[]; capturedKings: number };
export type DamaPosition = { board: DamaBoard; currentPlayer: DamaPlayer; winner: DamaPlayer | null; draw: boolean; moveCount: number; quietMoves: number };
const SIZE=8;
const DIRECTIONS=[[-1,-1],[-1,1],[1,-1],[1,1]] as const;
const isKing=(piece:DamaPiece):boolean=>piece===3||piece===4;
const ownerOf=(piece:DamaPiece):DamaPlayer|null=>piece===1||piece===3?1:piece===2||piece===4?2:null;
const isInside=(row:number,column:number):boolean=>row>=0&&row<SIZE&&column>=0&&column<SIZE;
const indexOf=(row:number,column:number):number=>row*SIZE+column;
export function createInitialDamaBoard():DamaBoard{
 const board=Array<DamaPiece>(64).fill(0);
 for(let row=0;row<3;row+=1)for(let column=0;column<8;column+=1)if((row+column)%2===1)board[indexOf(row,column)]=2;
 for(let row=5;row<8;row+=1)for(let column=0;column<8;column+=1)if((row+column)%2===1)board[indexOf(row,column)]=1;
 return board;
}
export function createInitialDamaPosition():DamaPosition{return{board:createInitialDamaBoard(),currentPlayer:1,winner:null,draw:false,moveCount:0,quietMoves:0};}
function getCaptureSteps(board:readonly DamaPiece[],player:DamaPlayer,position:number,captured:readonly number[]):Array<{landing:number;captured:number}>{
 const piece=board[position],row=Math.floor(position/8),column=position%8,king=isKing(piece);
 const steps:Array<{landing:number;captured:number}>=[];
 if(!king){
  for(const [dr,dc] of DIRECTIONS){
   const er=row+dr,ec=column+dc,lr=row+dr*2,lc=column+dc*2;
   if(!isInside(er,ec)||!isInside(lr,lc))continue;
   const enemy=indexOf(er,ec),landing=indexOf(lr,lc),enemyPiece=board[enemy];
   if(ownerOf(enemyPiece)!==null&&ownerOf(enemyPiece)!==player&&!captured.includes(enemy)&&board[landing]===0)steps.push({landing,captured:enemy});
  }
  return steps;
 }
 for(const [dr,dc] of DIRECTIONS){
  let enemy=-1,enemyDistance=-1;
  for(let distance=1;distance<8;distance+=1){
   const r=row+dr*distance,c=column+dc*distance;if(!isInside(r,c))break;
   const index=indexOf(r,c),occupant=board[index];if(occupant===0)continue;
   if(captured.includes(index)||ownerOf(occupant)===player||ownerOf(occupant)===null)break;
   enemy=index;enemyDistance=distance;break;
  }
  if(enemy<0)continue;
  for(let distance=enemyDistance+1;distance<8;distance+=1){
   const r=row+dr*distance,c=column+dc*distance;if(!isInside(r,c))break;
   const landing=indexOf(r,c);if(board[landing]!==0)break;
   steps.push({landing,captured:enemy});
  }
 }
 return steps;
}
function getCaptureSequences(board:readonly DamaPiece[],player:DamaPlayer,from:number,position:number,path:readonly number[],captures:readonly number[],capturedKings:number):DamaMove[]{
 const steps=getCaptureSteps(board,player,position,captures);
 if(steps.length===0)return captures.length?[{from,path:[...path],captures:[...captures],capturedKings}]:[];
 const sequences:DamaMove[]=[];
 for(const step of steps){
  const next=[...board];next[position]=0;next[step.landing]=board[position];
  sequences.push(...getCaptureSequences(next,player,from,step.landing,[...path,step.landing],[...captures,step.captured],capturedKings+(isKing(board[step.captured])?1:0)));
 }
 return sequences;
}
function getQuietMoves(board:readonly DamaPiece[],player:DamaPlayer,from:number):DamaMove[]{
 const piece=board[from],row=Math.floor(from/8),column=from%8;
 const directions=isKing(piece)?DIRECTIONS:DIRECTIONS.filter(([dr])=>dr===(player===1?-1:1));
 const moves:DamaMove[]=[];
 for(const [dr,dc] of directions)for(let distance=1;distance<=(isKing(piece)?7:1);distance+=1){
  const r=row+dr*distance,c=column+dc*distance;if(!isInside(r,c))break;
  const destination=indexOf(r,c);if(board[destination]!==0)break;
  moves.push({from,path:[destination],captures:[],capturedKings:0});
 }
 return moves;
}
export function getLegalDamaMoves(board:readonly DamaPiece[],player:DamaPlayer):DamaMove[]{
 if(board.length!==64)return[];
 const captures:DamaMove[]=[];
 for(let from=0;from<64;from+=1)if(ownerOf(board[from])===player)captures.push(...getCaptureSequences(board,player,from,from,[],[],0));
 if(captures.length){
  const maxPieces=Math.max(...captures.map(move=>move.captures.length));
  const longest=captures.filter(move=>move.captures.length===maxPieces);
  const maxKings=Math.max(...longest.map(move=>move.capturedKings));
  return longest.filter(move=>move.capturedKings===maxKings);
 }
 const moves:DamaMove[]=[];
 for(let from=0;from<64;from+=1)if(ownerOf(board[from])===player)moves.push(...getQuietMoves(board,player,from));
 return moves;
}
export function applyDamaMove(position:DamaPosition,move:DamaMove,player:DamaPlayer):DamaPosition|null{
 if(position.winner||position.draw||position.currentPlayer!==player)return null;
 const legal=getLegalDamaMoves(position.board,player);
 const chosen=legal.find(candidate=>candidate.from===move.from&&candidate.path.length===move.path.length&&candidate.path.every((square,index)=>square===move.path[index]));
 if(!chosen)return null;
 const board=[...position.board],piece=board[chosen.from];board[chosen.from]=0;
 for(const captured of chosen.captures)board[captured]=0;
 const destination=chosen.path[chosen.path.length-1],row=Math.floor(destination/8);
 const promoted:DamaPiece=piece===1&&row===0?3:piece===2&&row===7?4:piece;
 board[destination]=promoted;
 const opponent:DamaPlayer=player===1?2:1;
 const count=board.filter(cell=>ownerOf(cell)===opponent).length;
 const canMove=count>0&&getLegalDamaMoves(board,opponent).length>0;
 const winner=count===0||!canMove?player:null;
 const quietMoves=chosen.captures.length>0||!isKing(piece)?0:position.quietMoves+1;
 const draw=!winner&&quietMoves>=50;
 return{board,currentPlayer:opponent,winner:draw?null:winner,draw,moveCount:position.moveCount+1,quietMoves};
}
export function isDamaDarkSquare(index:number):boolean{return Number.isInteger(index)&&index>=0&&index<64&&(Math.floor(index/8)+(index%8))%2===1;}
