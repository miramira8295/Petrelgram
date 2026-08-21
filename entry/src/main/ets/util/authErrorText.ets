import { str } from './strings';
import { isInternalAuthError } from './authError';

// 登录页要显示的错误文案。判定在 authError（纯函数、可单测），取文案在这里
// （要碰资源管理器，进不了宿主单测），分成两个模块就是为了这条界线。
//
// 五个登录页共十处 `this.errorText = caught.message`，全部改走这里。新增登录
// 相关的 catch 时也用它——把 TDLib 的内部状态抱怨糊到界面上，用户看到的是
// 一串不随语言变的英文方法名。
export function authErrorText(raw: string): string {
  return isInternalAuthError(raw) ? str('lg_auth_retry_later') : raw;
}
