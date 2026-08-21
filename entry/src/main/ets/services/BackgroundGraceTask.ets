import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE, logI } from '../util/log';

// 切后台后的"宽限期"：申请短时任务，让进程在被系统挂起前多存活几分钟，
// 覆盖"刚切出去那阵"——这段时间内 TDLib 长连接仍在，新消息实时到达并弹通知。
// 与长时任务不同，短时任务是系统允许的有限延迟，不属于常驻保活。
//
// 约束（官方规则）：单应用同一时刻最多 3 个短时任务；系统给的时长有限且会
// 递减，超时前必须主动取消，否则可能被强制终止。
class BackgroundGraceTask {
  private requestId: number = -1;
  private expireTimer: number = -1;

  // 切后台时调用。系统回调 onExpire 表示配额即将耗尽，必须立刻取消。
  begin(): void {
    if (this.requestId !== -1) {
      return;
    }
    try {
      const info = backgroundTaskManager.requestSuspendDelay('telegram-message-sync',
        (): void => {
          // 配额耗尽：系统即将挂起进程，主动收尾避免被强杀。
          logI('[BackgroundGraceTask] expired by system');
          this.end();
        });
      this.requestId = info.requestId;
      // 到期前主动释放：留出余量，不等系统回调最后一刻。
      backgroundTaskManager.getRemainingDelayTime(this.requestId)
        .then((remainingMs: number): void => {
          logI(`[BackgroundGraceTask] granted ${remainingMs}ms`);
          const safeMs: number = Math.max(1000, remainingMs - 5000);
          this.expireTimer = setTimeout((): void => {
            this.expireTimer = -1;
            this.end();
          }, safeMs);
        })
        .catch((e: BusinessError): void => {
          logE(`[BackgroundGraceTask] getRemainingDelayTime failed: ${e.message}`);
        });
    } catch (e) {
      // 配额用尽或系统拒绝：不是错误路径，安静退回"立即挂起"的默认行为。
      logI(`[BackgroundGraceTask] request rejected: ${(e as BusinessError).message}`);
      this.requestId = -1;
    }
  }

  // 回前台或宽限期结束时调用。
  end(): void {
    if (this.expireTimer !== -1) {
      clearTimeout(this.expireTimer);
      this.expireTimer = -1;
    }
    if (this.requestId === -1) {
      return;
    }
    const id: number = this.requestId;
    this.requestId = -1;
    try {
      backgroundTaskManager.cancelSuspendDelay(id);
      logI('[BackgroundGraceTask] cancelled');
    } catch (e) {
      logE(`[BackgroundGraceTask] cancel failed: ${(e as BusinessError).message}`);
    }
  }
}

export const backgroundGraceTask: BackgroundGraceTask = new BackgroundGraceTask();
