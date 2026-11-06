import type { FormEvent } from 'react';
import { Gamepad2, ShieldCheck, Trophy, Users } from 'lucide-react';
import { Toast } from '../shared/ui';

type NoticeProps = { notice: string; onCloseNotice: () => void };

export function SetupRequiredScreen() {
  return <main className="shell"><header className="topbar"><div className="brand"><img className="brand-icon" src="/mimox-icon.svg" alt=""/>MIMOX</div></header><section className="setup-card"><ShieldCheck/><h1>خاص ربط Supabase</h1><p>خاصنا Project URL و Publishable Key فـ .env. ما تحطش service-role key فالواجهة.</p></section></main>;
}

type AuthScreenProps = NoticeProps & {
  authMode: 'login' | 'signup';
  email: string;
  password: string;
  username: string;
  busy: boolean;
  onEmailChange: (value: string) => void;
  onPasswordChange: (value: string) => void;
  onUsernameChange: (value: string) => void;
  onAuthModeChange: (value: 'login' | 'signup') => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  onGoogleSignIn: () => void;
  onPasswordReset: () => void;
  onResendConfirmation: () => void;
};

export function AuthScreen(props: AuthScreenProps) {
  const { authMode, email, password, username, busy, notice, onCloseNotice, onEmailChange: setEmail, onPasswordChange: setPassword, onUsernameChange: setUsername, onAuthModeChange: setAuthMode, onSubmit: authSubmit, onGoogleSignIn: signInWithGoogle, onPasswordReset: sendPasswordReset, onResendConfirmation: resendConfirmation } = props;
  return <main className="shell auth-shell"><div className="auth-scene"><img className="auth-art-img" src="/mimox-login.svg" alt="MIMOX gaming world"/><div className="auth-scene-copy"><h1>مرحباً بك في MIMOX</h1><p>منصة الألعاب والتحديات الاجتماعية</p></div></div><section className="auth-card"><div className="auth-kicker">MIMOX · YOUR PLAYGROUND</div><h2>{authMode==='login'?'دخول إلى عالمك':'انضم إلى MIMOX'}</h2><p className="auth-intro">{authMode==='login'?'رجع للّمة والتحديات ديالك.':'أنشئ حسابك وابدأ اللعب مع الأصدقاء.'}</p><button type="button" className="google-auth" onClick={signInWithGoogle} disabled={busy}><span className="google-g" aria-hidden="true">G</span><span>المتابعة باستخدام Google</span></button><div className="auth-divider"><span>أو</span></div><form onSubmit={authSubmit} className="auth-form">{authMode==='signup'&&<label>الاسم المعروض<input value={username} onChange={e=>setUsername(e.target.value)} minLength={3} maxLength={20} required placeholder="الاسم الذي سيظهر للآخرين"/></label>}<label>البريد الإلكتروني<input type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} required placeholder="name@example.com"/></label><label>كلمة المرور<input type="password" autoComplete={authMode==='login'?'current-password':'new-password'} minLength={8} value={password} onChange={e=>setPassword(e.target.value)} required placeholder="8 أحرف على الأقل"/></label><button className="primary wide auth-submit" disabled={busy}>{busy?'يرجى الانتظار...':authMode==='login'?'تسجيل الدخول':'إنشاء الحساب'}</button></form><button type="button" className="text-button auth-reset" onClick={sendPasswordReset} disabled={busy}>نسيت كلمة المرور؟ استرجاع الحساب</button><button type="button" className="text-button auth-resend" onClick={resendConfirmation} disabled={busy}>ما وصلش رابط التأكيد؟ عاود صيفطو</button><div className="auth-switch">{authMode==='login'?'ليس لديك حساب؟':'لديك حساب بالفعل؟'} <button type="button" onClick={()=>setAuthMode(authMode==='login'?'signup':'login')}>{authMode==='login'?'إنشاء حساب جديد':'تسجيل الدخول'}</button></div></section><div className="auth-benefits"><div><Gamepad2/><span>ألعاب متنوعة</span></div><div><Users/><span>غرف خاصة وعامة</span></div><div><Trophy/><span>تحديات وجوائز</span></div></div>{notice&&<Toast message={notice} close={()=>setNotice('')}/>}</main>;
}

type PasswordRecoveryScreenProps = NoticeProps & {
  newPassword: string;
  busy: boolean;
  onPasswordChange: (value: string) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
};

export function PasswordRecoveryScreen(props: PasswordRecoveryScreenProps) {
  const { newPassword, busy, notice, onCloseNotice, onPasswordChange: setNewPassword, onSubmit: saveNewPassword } = props;
  return <main className="shell auth-shell"><header className="topbar"><div className="brand"><img className="brand-mascot-mark" src="/mascot-idle.svg" alt="Mimox"/>MIMOX<span className="aqua">PLAY</span></div></header><section className="auth-card"><div className="eyebrow"><ShieldCheck/> استرجاع الحساب</div><h1>بدّل كلمة السر</h1><form className="auth-form" onSubmit={saveNewPassword}><label>كلمة السر الجديدة<input type="password" minLength={8} autoComplete="new-password" value={newPassword} onChange={e=>setNewPassword(e.target.value)} required/></label><button className="primary wide" disabled={busy||newPassword.length<8}>{busy?'كنحفظ...':'حفظ كلمة السر'}</button></form>{notice&&<Toast message={notice} close={()=>setNotice('')}/>}</section></main>;
}
