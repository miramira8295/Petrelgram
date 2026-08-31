// 文件夹左右切换时，Tabs 会同时合成当前页和目标页。全玻璃 + 光感下，两屏
// ChatRow 的 systemMaterial / lightEffect 会一起跟着背景移动，是切换卡顿的主因。
// 切换期间只暂停这些实时效果；ChatRow 自己的半透明 tint、边框和轮廓保持不变。

export const KEY_FOLDER_SWITCH_EFFECTS_ACTIVE: string = 'folderSwitchEffectsActive';

const FOLDER_SWITCH_EFFECTS_MAX_MS: number = 3000;
const FOLDER_SWITCH_EFFECTS_SETTLE_MS: number = 96;
let folderSwitchWatchdog: number = -1;
let folderSwitchSettleTimer: number = -1;
let folderSwitchEffectsActive: boolean = false;

function clearFolderSwitchWatchdog(): void {
  if (folderSwitchWatchdog !== -1) {
    clearTimeout(folderSwitchWatchdog);
    folderSwitchWatchdog = -1;
  }
}

function publishFolderSwitchEffectsActive(active: boolean): void {
  folderSwitchEffectsActive = active;
  if ((AppStorage.get<boolean>(KEY_FOLDER_SWITCH_EFFECTS_ACTIVE) ?? false) !== active) {
    AppStorage.setOrCreate(KEY_FOLDER_SWITCH_EFFECTS_ACTIVE, active);
  }
}

function armFolderSwitchWatchdog(): void {
  clearFolderSwitchWatchdog();
  folderSwitchWatchdog = setTimeout((): void => {
    folderSwitchWatchdog = -1;
    publishFolderSwitchEffectsActive(false);
  }, FOLDER_SWITCH_EFFECTS_MAX_MS);
}

// onGestureSwipe 每帧都会来。已开启时直接返回，不在热路径里重复写 AppStorage
// 或反复创建定时器；onAnimationStart 用 restart=true 给最终落位动画续看门狗。
export function beginFolderSwitchEffects(restart: boolean = false): void {
  if (folderSwitchSettleTimer !== -1) {
    clearTimeout(folderSwitchSettleTimer);
    folderSwitchSettleTimer = -1;
  }
  if (folderSwitchEffectsActive && !restart) {
    return;
  }
  publishFolderSwitchEffectsActive(true);
  armFolderSwitchWatchdog();
}

export function finishFolderSwitchEffects(): void {
  clearFolderSwitchWatchdog();
  if (folderSwitchSettleTimer !== -1) {
    clearTimeout(folderSwitchSettleTimer);
  }
  // 给 Tabs 的回弹和相邻页回收留一小段时间，避免结束回调同一帧给两屏行节点
  // 批量重新挂回 systemMaterial。
  folderSwitchSettleTimer = setTimeout((): void => {
    folderSwitchSettleTimer = -1;
    publishFolderSwitchEffectsActive(false);
  }, FOLDER_SWITCH_EFFECTS_SETTLE_MS);
}
