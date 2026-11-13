import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { Gamepad2, ShieldCheck, Trophy, Users } from 'lucide-react';
import { Toast } from '../shared/ui';

type NoticeProps = { notice: string; onCloseNotice: () => void };


export function InstallAppBanner() {
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null);
  const [installed, setInstalled] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  const [isIOS, setIsIOS] = useState(false);
  const [isAndroid, setIsAndroid] = useState(false);

  useEffect(() => {
    const ua = navigator.userAgent || '';
    const ios = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    setIsIOS(ios);
    setIsAndroid(/Android/i.test(ua));
    const standalone = window.matchMedia('(display-mode: standalone)').matches || (navigator as any).standalone === true;
    setInstalled(standalone);
    const onPrompt = (event: Event) => {
      event.preventDefault();
      setDeferredPrompt(event);
    };
    const onInstalled = () => { setInstalled(true); setDeferredPrompt(null); };
    window.addEventListener('beforeinstallprompt', onPrompt);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  async function install() {
    if (deferredPrompt) {
      await deferredPrompt.prompt();
      setDeferredPrompt(null);
      return;
    }
    setHelpOpen(value => !value);
  }

  if (installed) return null;
  return <section className="install-app-banner" aria-label="تثبيت ليلة فالخيمة">
    <img src="/night-camp-icon.svg?v=20261113c" alt="شعار ليلة فالخيمة" />
    <div className="install-app-copy">
      <b>خلي ليلة فالخيمة ديما معاك</b>
      <span>ثبّت التطبيق على هاتفك أو حاسوبك، وادخل ليه مباشرة من الشاشة الرئيسية.</span>
    </div>
    <button type="button" className="install-app-action" onClick={install}>
      {deferredPrompt ? 'تثبيت التطبيق' : isIOS ? 'طريقة التثبيت على iPhone' : isAndroid ? 'إضافة للشاشة الرئيسية' : 'تثبيت على الجهاز'}
    </button>
    {helpOpen && <div className="install-app-help">
      {isIOS ? <>على iPhone أو iPad: اضغط على زر <b>المشاركة</b> في Safari، ثم اختر <b>Add to Home Screen / إضافة إلى الشاشة الرئيسية</b> واضغط إضافة.</> :
      isAndroid ? <>في Chrome: افتح قائمة <b>⋮</b> ثم اختر <b>Install app / تثبيت التطبيق</b> أو <b>Add to Home screen / إضافة إلى الشاشة الرئيسية</b>.</> :
      <>في Chrome أو Edge على الحاسوب: اضغط على أيقونة التثبيت بجانب شريط العنوان، أو افتح القائمة واختر <b>Install ليلة فالخيمة</b>.</>}
    </div>}
  </section>;
}

export function SetupRequiredScreen() {
  return <main className="shell"><header className="topbar"><div className="brand"><img className="brand-icon" src="/night-camp-icon.svg?v=20261113c" alt=""/>ليلة فالخيمة</div></header><section className="setup-card"><ShieldCheck/><h1>خاص ربط Supabase</h1><p>خاصنا Project URL و Publishable Key فـ .env. ما تحطش service-role key فالواجهة.</p></section></main>;
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
  return <main className="shell auth-shell"><InstallAppBanner/><div className="auth-scene"><img className="auth-art-img" src="/night-camp-login.svg" alt="ليلة فالخيمة — الفقيه والمسكون"/><div className="auth-scene-copy"><h1>مرحبا بك فليلة فالخيمة</h1><p>اللعبة الجماعية ديال الفقيه والمسكون</p></div></div><section className="auth-card"><div className="auth-kicker">ليلة فالخيمة · الفقيه والمسكون</div><h2>{authMode==='login'?'دخول إلى عالمك':'دخل لعالم الخيمة'}</h2><p className="auth-intro">{authMode==='login'?'رجع للّمة والتحديات ديالك.':'أنشئ حسابك وابدأ اللعب مع الأصدقاء.'}</p><button type="button" className="google-auth" onClick={signInWithGoogle} disabled={busy}><span className="google-g" aria-hidden="true">G</span><span>المتابعة باستخدام Google</span></button><div className="auth-divider"><span>أو</span></div><form onSubmit={authSubmit} className="auth-form">{authMode==='signup'&&<label>الاسم المعروض<input value={username} onChange={e=>setUsername(e.target.value)} minLength={3} maxLength={20} required placeholder="الاسم الذي سيظهر للآخرين"/></label>}<label>البريد الإلكتروني<input type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} required placeholder="name@example.com"/></label><label>كلمة المرور<input type="password" autoComplete={authMode==='login'?'current-password':'new-password'} minLength={8} value={password} onChange={e=>setPassword(e.target.value)} required placeholder="8 أحرف على الأقل"/></label><button className="primary wide auth-submit" disabled={busy}>{busy?'يرجى الانتظار...':authMode==='login'?'تسجيل الدخول':'إنشاء الحساب'}</button></form><button type="button" className="text-button auth-reset" onClick={sendPasswordReset} disabled={busy}>نسيت كلمة المرور؟ استرجاع الحساب</button><button type="button" className="text-button auth-resend" onClick={resendConfirmation} disabled={busy}>ما وصلش رابط التأكيد؟ عاود صيفطو</button><div className="auth-switch">{authMode==='login'?'ليس لديك حساب؟':'لديك حساب بالفعل؟'} <button type="button" onClick={()=>setAuthMode(authMode==='login'?'signup':'login')}>{authMode==='login'?'إنشاء حساب جديد':'تسجيل الدخول'}</button></div></section><div className="auth-benefits"><div><Gamepad2/><span>ألعاب متنوعة</span></div><div><Users/><span>غرف خاصة وعامة</span></div><div><Trophy/><span>تحديات وجوائز</span></div></div>{notice&&<Toast message={notice} close={onCloseNotice}/>}</main>;
}

type PasswordRecoveryScreenProps = NoticeProps & {
  newPassword: string;
  busy: boolean;
  onPasswordChange: (value: string) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
};

export function PasswordRecoveryScreen(props: PasswordRecoveryScreenProps) {
  const { newPassword, busy, notice, onCloseNotice, onPasswordChange: setNewPassword, onSubmit: saveNewPassword } = props;
  return <main className="shell auth-shell"><header className="topbar"><div className="brand"><img className="brand-mascot-mark" src="/mascot-idle.svg" alt="ليلة فالخيمة"/>ليلة فالخيمة<span className="aqua">PLAY</span></div></header><section className="auth-card"><div className="eyebrow"><ShieldCheck/> استرجاع الحساب</div><h1>بدّل كلمة السر</h1><form className="auth-form" onSubmit={saveNewPassword}><label>كلمة السر الجديدة<input type="password" minLength={8} autoComplete="new-password" value={newPassword} onChange={e=>setNewPassword(e.target.value)} required/></label><button className="primary wide" disabled={busy||newPassword.length<8}>{busy?'كنحفظ...':'حفظ كلمة السر'}</button></form>{notice&&<Toast message={notice} close={onCloseNotice}/>}</section></main>;
}
