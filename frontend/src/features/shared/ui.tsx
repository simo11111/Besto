import { useEffect, type ReactNode } from 'react';
import { Award, Check, Gift, Gamepad2, ShieldCheck, Star, Trophy, X } from 'lucide-react';

type DailyMissionSummary = { mission_key: string };

export function SideButton({active,icon,label,onClick}:{active:boolean;icon:ReactNode;label:string;onClick:()=>void}){return <button className={'side-button '+(active?'active':'')} onClick={onClick}>{icon}<span>{label}</span></button>}
export function PageHead({eyebrow,title,subtitle}:{eyebrow:string;title:string;subtitle:string}){return <div className="page-head"><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{subtitle}</p></div>}
export function MissionIcon({mission}:{mission:DailyMissionSummary}){const key=mission.mission_key.toLowerCase();if(key.includes('daily')||key.includes('claim'))return <Gift/>;if(key.includes('play')||key.includes('game'))return <Gamepad2/>;if(key.includes('win'))return <Trophy/>;return <Star/>;}

export function Stat({icon,value,label}:{icon:ReactNode;value:string|number;label:string}){return <div className="stat-card">{icon}<b>{value}</b><small>{label}</small></div>}
export function Achievement({icon,name,desc,unlocked}:{icon:ReactNode;name:string;desc:string;unlocked:boolean}){return <div className={'achievement '+(unlocked?'unlocked':'locked')}><span>{icon}</span><div><b>{name}</b><small>{desc}</small></div>{unlocked?<Check/>:<ShieldCheck/>}</div>}
export function Toast({message,close}:{message:string;close:()=>void}){useEffect(()=>{const timer=window.setTimeout(close,4500);return()=>window.clearTimeout(timer);},[message,close]);return <div className="toast" role="status" aria-live="polite">{message}<button aria-label="إغلاق الإشعار" onClick={close}><X size={16}/></button></div>}
