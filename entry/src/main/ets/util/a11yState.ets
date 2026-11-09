import { accessibility } from '@kit.AccessibilityKit';
import { logE } from './log';

// 读屏（无障碍）此刻开没开。
//
// 【为什么值得单独查一次】`ChatRow` 的 `.accessibilityText(...)` 参数是**每行
// 每次渲染都要求值**的，而它里面要拼标题/置顶/静音/未读数/最后一条消息，
// 未读那一段还要打一次 `plural()` 的 NAPI。2026-09-09 的 Frame 录制量到：
// `accessibilitySummary` self **38.07ms**，占 ChatRow 复用体（60.33ms）的
// **63%**；`plural` 自身 16.5ms（`getIntPluralStringByNameSync`）。
//
// 而读屏没开的时候，这段话**根本没有任何人读**。所以先问一句，关着就返回空串。
//
// 【为什么还要订阅状态变更】用户可能在应用运行期间打开读屏。只查一次会让已经
// 建好的行永远没有无障碍文本。订阅之后把纪元 +1，行按 @StorageProp 订阅它，
// 翻转那一刻整表重刷一次——和 LANGUAGE_EPOCH 是同一套办法。

export const A11Y_EPOCH: string = 'a11yEpoch';

let cached: boolean = false;
let initialized: boolean = false;

function bumpEpoch(): void {
  AppStorage.setOrCreate<number>(A11Y_EPOCH,
    (AppStorage.get<number>(A11Y_EPOCH) ?? 0) + 1);
}

// 应用启动时调一次。查询与订阅都包在 try/catch 里：这是纯增强能力，
// 任何一步失败都只该退化成"当读屏没开"，不能影响启动。
export function initA11yState(): void {
  if (initialized) {
    return;
  }
  initialized = true;
  try {
    cached = accessibility.isOpenAccessibilitySync();
  } catch (e) {
    logE(`initA11yState query failed: ${e}`);
    cached = false;
  }
  try {
    accessibility.on('accessibilityStateChange', (open: boolean): void => {
      if (cached !== open) {
        cached = open;
        bumpEpoch();
      }
    });
  } catch (e) {
    logE(`initA11yState subscribe failed: ${e}`);
  }
}

export function screenReaderOn(): boolean {
  return cached;
}
