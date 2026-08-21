import { common } from '@kit.AbilityKit';
import { initTdKit, getAuthService, getTdClient } from '../tdkit/Globals';
import { AuthStage } from '../tdkit/AuthService';
import { TdRequest, TdError, TdObject } from '../tdkit/TdTypes';
import { logE, logI } from '../util/log';

// 延迟任务补收：主进程死亡时在扩展进程无头拉起 TDLib，等登录态就绪、
// 给通知管理器一个收集窗口（初始化时机由 Globals 装配的
// NotificationService 承担渲染），随后干净关闭。
// 主进程仍活着时 TDLib 数据库被锁，Ready 永远不会到达 —— 超时静默退出，
// 消息由主进程自身处理。
const READY_TIMEOUT_MS: number = 20000;
const COLLECT_WINDOW_MS: number = 15000;

export function runHeadlessSync(context: common.Context): Promise<void> {
  // 扩展进程没有 UIAbility 维护前台标记；显式置后台，
  // NotificationService 的前台抑制才不会吞掉补收通知。
  AppStorage.setOrCreate('appIsForeground', false);
  initTdKit(context);
  return new Promise<void>((resolve: (v: void) => void) => {
    let settled = false;
    let offAuth: (() => void) | null = null;
    const finish = (): void => {
      if (settled) {
        return;
      }
      settled = true;
      if (offAuth !== null) {
        offAuth();
        offAuth = null;
      }
      // 请求 TDLib 干净关闭（binlog 落盘）；不等回执，进程随任务结束。
      const req: TdRequest = { '@type': 'close' };
      getTdClient().send(req).catch((e: TdError): void => {
        logE(`HeadlessSync.close failed: ${e.message}`);
      });
      resolve();
    };
    const timeout = setTimeout((): void => {
      logI('[HeadlessSync] ready timeout — main process likely alive, skip');
      finish();
    }, READY_TIMEOUT_MS);
    offAuth = getAuthService().onStageChange((stage: AuthStage): void => {
      if (stage !== AuthStage.Ready || settled) {
        return;
      }
      clearTimeout(timeout);
      logI('[HeadlessSync] td ready — collecting notifications');
      setTimeout((): void => {
        logI('[HeadlessSync] collect window closed');
        finish();
      }, COLLECT_WINDOW_MS);
    });
  });
}
