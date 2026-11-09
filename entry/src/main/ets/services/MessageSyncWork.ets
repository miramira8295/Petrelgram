import { workScheduler } from '@kit.BackgroundTasksKit';
import { logE, logI } from '../util/log';

const WORK_ID: number = 8298;
// 系统按应用活跃分组管控实际触发间隔（活跃分组最小 2 小时）。
const CYCLE_MS: number = 2 * 3600 * 1000;

// 登录就绪后注册周期补收任务；重复注册（应用每次启动）无害——
// 相同 workId 直接覆盖或抛已存在错误，均忽略。
export function registerMessageSyncWork(bundleName: string): void {
  const info: workScheduler.WorkInfo = {
    workId: WORK_ID,
    bundleName: bundleName,
    abilityName: 'MessageSyncWorkAbility',
    networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
    isRepeat: true,
    repeatCycleTime: CYCLE_MS
  };
  try {
    workScheduler.startWork(info);
    logI('[MessageSyncWork] registered');
    logWorkStatus();
  } catch (e) {
    // 9700005 = 该任务已在系统队列中（应用每次启动都会调一次注册），
    // 属于正常路径而非错误：任务仍然有效，继续自查状态。
    const message: string = (e as Error).message;
    if (message.indexOf('9700005') >= 0) {
      logI('[MessageSyncWork] already registered (kept)');
      logWorkStatus();
      return;
    }
    logE(`[MessageSyncWork] register failed: ${message}`);
  }
}

// 自查：延迟任务是否真的在系统队列里。设备侧 hidumper 对 WorkSchedule 的
// 输出被安全策略屏蔽，只能用官方 API 从应用内确认注册状态。
export function logWorkStatus(): void {
  try {
    workScheduler.getWorkStatus(WORK_ID, (err: Error, work: workScheduler.WorkInfo): void => {
      if (err !== null && err !== undefined) {
        logE(`[MessageSyncWork] status unavailable: ${err.message}`);
        return;
      }
      logI(`[MessageSyncWork] status workId=${work.workId} ` +
        `repeat=${work.isRepeat} cycle=${work.repeatCycleTime} ` +
        `network=${work.networkType} ability=${work.abilityName}`);
    });
  } catch (e) {
    logE(`[MessageSyncWork] getWorkStatus threw: ${(e as Error).message}`);
  }
}

export function unregisterMessageSyncWork(bundleName: string): void {
  const info: workScheduler.WorkInfo = {
    workId: WORK_ID,
    bundleName: bundleName,
    abilityName: 'MessageSyncWorkAbility'
  };
  try {
    workScheduler.stopWork(info, true);
    logI('[MessageSyncWork] unregistered');
  } catch (e) {
    logE(`[MessageSyncWork] unregister failed: ${(e as Error).message}`);
  }
}
