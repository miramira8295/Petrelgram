import { AuthStage } from '../tdkit/AuthService';

// 现在是不是"系统启动窗刚消失、还没有任何界面可画"的那一段。
//
// **为什么要单独成一个判据而不是就写在 build 的 else 里。** Index 的 build 用
// 这个条件决定画启动图，外层 Stack 的 padding 也要用它——启动图必须**顶到屏幕
// 最上沿**才能和系统启动窗对齐，而登录页需要留出状态栏高度。两处条件一旦drift，
// 现象是启动图被整体下移一个状态栏的高度，与系统启动窗错位一下再跳回来——正是
// 这次要消掉的那种割裂。写成一个函数、两处都调它，就没有 drift 的余地。
//
// 判据取反着写（"不是任何一个有界面的阶段"）而不是 `stage === Init`：将来
// AuthStage 若加了新值，新值默认落进"还没有界面可画"这一侧，画一张启动图；
// 写成 `=== Init` 则会掉进一个什么都不画的空白分支。
//
// **切账号要排除掉。** 切账号时 bindAuthService 也会把 stage 打回 Init，但那时
// 窗口早就在前台、系统启动窗根本不存在，铺一张全屏启动图会让人以为应用重启了。
export function isStartupStage(stage: AuthStage, accountSwitching: boolean): boolean {
  if (accountSwitching) {
    return false;
  }
  return stage !== AuthStage.WaitPhone
    && stage !== AuthStage.WaitQrCode
    && stage !== AuthStage.WaitCode
    && stage !== AuthStage.WaitPassword
    && stage !== AuthStage.WaitRegistration
    && stage !== AuthStage.Ready
    && stage !== AuthStage.LoggedOut;
}
