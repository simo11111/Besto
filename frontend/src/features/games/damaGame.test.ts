import {describe,expect,it} from 'vitest';
import{applyDamaMove,createInitialDamaBoard,createInitialDamaPosition,getLegalDamaMoves,isDamaDarkSquare,type DamaBoard,type DamaPiece}from'./damaGame';
const sq=(r:number,c:number)=>r*8+c,empty=():DamaBoard=>Array<DamaPiece>(64).fill(0);
describe('Moroccan Dama rules',()=>{
 it('starts 8x8 with twelve pieces per player',()=>{const b=createInitialDamaBoard();expect(b).toHaveLength(64);expect(b.filter(p=>p===1)).toHaveLength(12);expect(b.filter(p=>p===2)).toHaveLength(12);expect(b.every((p,i)=>p===0||isDamaDarkSquare(i))).toBe(true);});
 it('moves men forward only when no capture is available',()=>{const b=empty();b[sq(5,2)]=1;expect(getLegalDamaMoves(b,1).map(m=>m.path[0]).sort((a,c)=>a-c)).toEqual([sq(4,1),sq(4,3)]);});
 it('forces capture and chooses the longest sequence',()=>{const b=empty();b[sq(5,0)]=1;b[sq(4,1)]=2;b[sq(2,3)]=2;b[sq(5,4)]=1;b[sq(4,5)]=2;const m=getLegalDamaMoves(b,1);expect(m).toHaveLength(1);expect(m[0].from).toBe(sq(5,0));expect(m[0].path).toEqual([sq(3,2),sq(1,4)]);expect(m[0].captures).toHaveLength(2);});
 it('does not allow men to capture backwards',()=>{const b=empty();b[sq(3,2)]=1;b[sq(4,3)]=2;expect(getLegalDamaMoves(b,1).every(m=>m.captures.length===0)).toBe(true);});
 it('allows men to capture forward',()=>{const b=empty();b[sq(3,2)]=1;b[sq(2,3)]=2;expect(getLegalDamaMoves(b,1).some(m=>m.from===sq(3,2)&&m.path[0]===sq(1,4))).toBe(true);});
 it('ends a capture sequence when a man reaches the promotion row',()=>{const b=empty();b[sq(2,1)]=1;b[sq(1,2)]=2;b[sq(1,4)]=2;const moves=getLegalDamaMoves(b,1);expect(moves).toHaveLength(1);expect(moves[0].path).toEqual([sq(0,3)]);expect(moves[0].captures).toHaveLength(1);});
 it('allows a flying Dama to land beyond the captured piece',()=>{const b=empty();b[sq(5,0)]=3;b[sq(3,2)]=2;expect(getLegalDamaMoves(b,1).map(m=>m.path[0]).sort((a,c)=>a-c)).toEqual([sq(0,5),sq(1,4),sq(2,3)]);});
 it('prefers capturing a Dama when capture counts are equal',()=>{const b=empty();b[sq(5,0)]=1;b[sq(4,1)]=2;b[sq(5,4)]=1;b[sq(4,5)]=4;const m=getLegalDamaMoves(b,1);expect(m).toHaveLength(1);expect(m[0].captures).toEqual([sq(4,5)]);expect(m[0].capturedKings).toBe(1);});
 it('promotes a man after the move completes',()=>{const p=createInitialDamaPosition();p.board.fill(0);p.board[sq(1,2)]=1;const m=getLegalDamaMoves(p.board,1).find(x=>x.from===sq(1,2)&&x.path[0]===sq(0,3));expect(m).toBeDefined();expect(applyDamaMove(p,m!,1)?.board[sq(0,3)]).toBe(3);});
 it('rejects illegal turns',()=>{const p=createInitialDamaPosition(),m=getLegalDamaMoves(p.board,1)[0];expect(applyDamaMove(p,m,2)).toBeNull();expect(applyDamaMove(p,{...m,path:[63]},1)).toBeNull();});
})