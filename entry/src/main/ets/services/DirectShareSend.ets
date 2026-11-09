import { SendPermissionError } from '../store/SendPermissionApi';
import { promptAction } from '@kit.ArkUI';
import { ShareArrivalHost, sendShareDirectly, remainingDirectShare, applyShareArrival } from '../util/shareArrival';
import { SendProgress } from '../util/sendProgress';
import { UpgradedShare } from '../util/shareLivePhoto';
import { peekPendingShare, stashPendingShare, pendingShareGeneration } from './ShareInbox';
import { logE } from '../util/log';

export async function sendDirectShareWithRecovery(upgraded: UpgradedShare, host: ShareArrivalHost,
  active: () => boolean): Promise<boolean> {
  const progress = new SendProgress();
  const generation: number = pendingShareGeneration();
  const current = (): boolean => active() && pendingShareGeneration() === generation;
  try {
    await sendShareDirectly(upgraded.payload, host, upgraded.geometry, progress, current);
    return current();
  } catch (error) {
    logE(`Direct share failed: ${error}`);
    if (!current()) { return false; }
    if (progress.hasUncertain()) {
      promptAction.showToast({ message: $r('app.string.share_result_unknown'), duration: 3000 });
      return false;
    }
    promptAction.showToast({ message: error instanceof SendPermissionError ? error.message : $r('app.string.fw_failed'), duration: 2000 });
    // 另一份分享已经到达时，旧失败任务不能覆盖它。
    if (peekPendingShare() === null) {
      stashPendingShare(remainingDirectShare(upgraded.payload, progress));
      AppStorage.setOrCreate('pendingShareAutoSend', false);
      AppStorage.setOrCreate('pendingShareChatId', 0);
      AppStorage.setOrCreate('pendingShareEpoch', 0);
      AppStorage.setOrCreate('pendingShareEpoch', Date.now());
    }
    return false;
  }
}

export async function stageShareWithPermissions(upgraded: UpgradedShare, host: ShareArrivalHost,
  alreadyStaged: number, active: () => boolean): Promise<void> {
  const generation: number = pendingShareGeneration();
  try {
    await host.checkPermissions?.(upgraded.payload);
    if (!active() || pendingShareGeneration() !== generation) { return; }
    applyShareArrival(upgraded.payload, host, alreadyStaged, upgraded.geometry);
  } catch (error) {
    if (!active() || pendingShareGeneration() !== generation) { return; }
    promptAction.showToast({ message: error instanceof SendPermissionError ? error.message : $r('app.string.fw_failed'),
      duration: 2500 });
    if (peekPendingShare() === null) { stashPendingShare(upgraded.payload); }
  }
}
