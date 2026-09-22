import { AWAKE_OWNER_LIVE, requestScreenAwake, screenAwakeApplyFailed } from '../../util/screenAwake';
import { common } from '@kit.AbilityKit';
import { promptAction, window } from '@kit.ArkUI';
import { logE } from '../../util/log';

const EXIT_RED: string = '#E64646';
const LEAVE_BLUE: string = '#3E8BFF';
const SECONDARY_TEXT: string = '#8E8E93';
let mediaOrientationRequestSeq: number = 0;
let liveFullscreenRequestSeq: number = 0;
let liveFullscreenTask: Promise<void> = Promise.resolve();
let liveKeepScreenRequestSeq: number = 0;

function liveFullscreenOrientation(
  fullscreen: boolean, videoAspectRatio: number
): window.Orientation {
  if (!fullscreen) { return window.Orientation.PORTRAIT; }
  // Only lock clearly landscape/portrait pictures. Square and not-yet-decoded
  // frames follow the sensor so a transient geometry callback cannot cause an
  // unnecessary second rotation.
  if (videoAspectRatio > 1.15) { return window.Orientation.AUTO_ROTATION_LANDSCAPE; }
  if (videoAspectRatio > 0 && videoAspectRatio < 0.87) {
    return window.Orientation.AUTO_ROTATION_PORTRAIT;
  }
  return window.Orientation.AUTO_ROTATION;
}

export function confirmLeaveLiveStream(
  onConfirm: () => void, onDismiss: () => void = (): void => {}
): void {
  promptAction.showDialog({
    title: $r('app.string.lv_leave_title'),
    message: $r('app.string.lv_leave_body'),
    buttons: [
      { text: $r('app.string.lv_keep_watching'), color: SECONDARY_TEXT },
      { text: $r('app.string.lv_leave'), color: EXIT_RED }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index === 1) { onConfirm(); }
    onDismiss();
  }).catch((): void => { onDismiss(); });
}

export function confirmAdminLeaveLiveStream(
  onLeave: () => void, onEnd: () => void, onDismiss: () => void = (): void => {}
): void {
  promptAction.showDialog({
    title: $r('app.string.lv_manage'),
    message: $r('app.string.lv_manage_body'),
    buttons: [
      { text: $r('app.string.lv_keep_streaming'), color: SECONDARY_TEXT },
      { text: $r('app.string.lv_leave'), color: LEAVE_BLUE },
      { text: $r('app.string.lv_end'), color: EXIT_RED }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index === 1) {
      onLeave();
    } else if (result.index === 2) {
      onEnd();
    }
    onDismiss();
  }).catch((): void => { onDismiss(); });
}

export function setLiveStreamFullscreen(
  context: common.UIAbilityContext, fullscreen: boolean, videoAspectRatio: number = 0
): Promise<void> {
  const requestSeq: number = ++liveFullscreenRequestSeq;
  const orientation: window.Orientation = liveFullscreenOrientation(fullscreen, videoAspectRatio);
  const systemBars: Array<'status' | 'navigation'> = fullscreen ? [] : ['status', 'navigation'];
  // Window operations are serialized. A stale operation may already be in the
  // platform queue, but the newest target always runs after it and restores a
  // coherent orientation/system-bar state.
  liveFullscreenTask = liveFullscreenTask.then((): Promise<void> => {
    if (requestSeq !== liveFullscreenRequestSeq) { return Promise.resolve(); }
    return window.getLastWindow(context).then((mainWindow: window.Window): Promise<void> => {
      if (requestSeq !== liveFullscreenRequestSeq) { return Promise.resolve(); }
      return mainWindow.setPreferredOrientation(orientation).then((): Promise<void> => {
        if (requestSeq !== liveFullscreenRequestSeq) { return Promise.resolve(); }
        return mainWindow.setWindowSystemBarEnable(systemBars);
      });
    });
  }).catch((caught: Error): void => {
    logE(`LiveViewerUi.setLiveStreamFullscreen failed: ${caught.message}`);
  });
  return liveFullscreenTask;
}

// 「屏幕别熄」的唯一出口。**谁要亮由 util/screenAwake 仲裁**，这里只负责把
// 仲裁结果推给窗口——setWindowKeepScreenOn 是窗口上的一个布尔开关，谁最后调
// 谁说了算，各调各的就会互相掐（详见 screenAwake 文件头）。
//
// 序号守卫防止一个更早发出的异步取窗口请求覆盖掉更晚的那次决定。
export function setScreenAwakeFor(
  context: common.UIAbilityContext, owner: string, keepScreenOn: boolean
): void {
  const next: boolean | null = requestScreenAwake(owner, keepScreenOn);
  if (next === null) {
    return; // 集合空/非空没翻转，不需要碰窗口
  }
  const wanted: boolean = next;
  const requestSeq: number = ++liveKeepScreenRequestSeq;
  window.getLastWindow(context).then((mainWindow: window.Window): Promise<void> => {
    if (requestSeq !== liveKeepScreenRequestSeq) { return Promise.resolve(); }
    return mainWindow.setWindowKeepScreenOn(wanted);
  }).catch((caught: Error): void => {
    screenAwakeApplyFailed(wanted);
    logE(`LiveViewerUi.setKeepScreenOn failed: ${caught.message}`);
  });
}

// Keep the display awake only while a live viewer or its floating overlay owns
// the active Session. 观看页和悬浮窗本来就共享同一个标志，所以共用一个持有者名。
export function setLiveStreamKeepScreenOn(
  context: common.UIAbilityContext, keepScreenOn: boolean
): void {
  setScreenAwakeFor(context, AWAKE_OWNER_LIVE, keepScreenOn);
}

// The media viewer already owns the whole page, so this control changes only
// screen orientation. It intentionally leaves system bars and viewer chrome
// alone; closing the viewer always calls it with landscape=false.
export function setMediaViewerOrientation(
  context: common.UIAbilityContext, landscape: boolean
): void {
  const requestSeq: number = ++mediaOrientationRequestSeq;
  window.getLastWindow(context).then((mainWindow: window.Window): void => {
    if (requestSeq !== mediaOrientationRequestSeq) {
      return;
    }
    const orientation: window.Orientation = landscape
      ? window.Orientation.AUTO_ROTATION_LANDSCAPE
      : window.Orientation.PORTRAIT;
    mainWindow.setPreferredOrientation(orientation).catch((caught: Error): void => {
      logE(`LiveViewerUi.setMediaOrientation failed: ${caught.message}`);
    });
  }).catch((caught: Error): void => {
    logE(`LiveViewerUi.getMediaWindow failed: ${caught.message}`);
  });
}
