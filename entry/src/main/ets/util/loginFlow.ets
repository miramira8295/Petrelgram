import { getAuthService, resetAuthorizationForPhoneLogin } from '../tdkit/Globals';
import { needsAuthorizationReset } from './authError';
import { logW } from './log';

// 授权流被重置过一次、需要提示用户重新输入。由 loginFlow 置位，PhoneNumberPage
// 读取并清零——跨组件重建传递，所以不能用组件状态。
export const AUTH_RESET_NOTICE: string = 'authResetNotice';

// 提交手机号，并在 TDLib 卡死在扫码授权态时自救一次。
//
// **为什么需要自救**：用户点过一次扫码登录之后，TDLib 就把
// authorizationStateWaitOtherDeviceConfirmation 写进 td.binlog。之后每次冷启动都从
// binlog 恢复成扫码态、**跳过 WaitPhoneNumber**，而 setAuthenticationPhoneNumber 只在
// WaitPhoneNumber 下被接受——于是被永久拒绝。用户看到的是：手机号页能打开、能输入、
// 一点「继续」就报错，且**重启多少次都一样**，只能去系统设置里清除应用数据。
// 判定条件与 hilog 实证见 util/authError.ets。
//
// **为什么放在这一层而不是 AuthService 里**：自救要销毁并重建整个运行时，重建之后
// AuthService 是一个**新实例**——旧实例上的 this 已经作废，没法在它内部完成重试。
// 所以顺序必须是：旧实例提交 → 失败 → 重建 → **重新取**实例再提交。
//
// **重建之后的那次提交为什么不会又撞上时机问题**：新运行时要先走
// WaitTdlibParameters → WaitPhoneNumber（实测几十毫秒），这期间提交会被拒。
// AuthService.sendAuthRequest 的三次重试正好覆盖这个窗口，不必在这里再等一层。
//
// **只自救一次**：如果重建之后仍然失败，那就不是扫码态卡死，而是别的问题
// （号码非法、被限频、网络断了）。再循环下去只会把用户的本地数据反复清掉。
export async function submitPhoneWithRecovery(phone: string): Promise<void> {
  const auth = getAuthService();
  try {
    await auth.submitPhone(phone);
    return;
  } catch (e) {
    const error = e as Error;
    if (!needsAuthorizationReset(error.message, auth.getCurrentAuthType())) {
      throw error;
    }
    logW('loginFlow: TDLib stuck in QR authorization state; resetting local authorization');
  }
  // 重建运行时会把登录页整个重挂——表单被清空、国家回到默认。不留一句话的话，
  // 用户看到的是"点了继续，什么都没发生，输入还没了"，只会以为点击失灵。
  // 标记放 AppStorage 而不是组件状态：正是因为组件会被重建，状态留不住。
  AppStorage.setOrCreate<boolean>(AUTH_RESET_NOTICE, true);
  await resetAuthorizationForPhoneLogin();
  // 重建之后 AuthService 是新实例，必须重新取。这一次提交可能赶在 TDLib 走到
  // WaitPhoneNumber 之前——sendAuthRequest 的重试覆盖那个窗口。**但它不保证成功**：
  // 手机模拟器实测里这次提交没走通（页面已随重建重挂，in-flight 的调用跟着旧组件
  // 一起没了），用户是靠上面那句提示重输一次完成登录的。留着它是因为时序好的时候
  // 能省用户一次操作，不留着也不会更坏。
  await getAuthService().submitPhone(phone);
}
