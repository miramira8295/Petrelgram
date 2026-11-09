import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { runHeadlessSync } from '../services/HeadlessSync';
import { logE, logI } from '../util/log';

// 系统延迟任务回调（独立扩展进程）：主进程死亡期间定时补收消息并发通知。
export default class MessageSyncWorkAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    logI(`[MessageSyncWork] start workId=${work.workId}`);
    runHeadlessSync(this.context).then((): void => {
      logI('[MessageSyncWork] done');
    }).catch((e: Error): void => {
      logE(`[MessageSyncWork] failed: ${e.message}`);
    });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    logI(`[MessageSyncWork] stop workId=${work.workId}`);
  }
}
