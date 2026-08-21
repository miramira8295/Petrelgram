import { logE } from './log';
import { decidePush, StackAction, StackFrame } from './splitRouting';
import { NavStackLike, snapshotOf, stackOf } from './navStacks';
import { KEY_MAIN_TAB } from './chatNav';

// 打开一个**已经迁成 HdsNavDestination 的**设置子页。
//
// 为什么需要这个漏斗：设置子页看着只有 SettingsPage 那张列表一个入口，实际上
// 还有第二条——tg://settings/... 深链（util/openTelegramLink.ets 的
// openSettingsSection，七个 section 各对应一个子页）。迁移把页面从
// main_pages.json 摘掉之后，那条路上的 router.pushUrl 会**在运行期直接失败**
// （目标不再是 router 页），而它原本连 catch 都没有，现象是点了深链什么都不
// 发生。两个入口共用这一个函数，以后每迁一个页面只要改两处的映射表。
//
// MainScreen.build() 里 TabContent 的顺序：ChatListPage / ContactsPage /
// SettingsPage / MyProfilePage。
export const SETTINGS_TAB_INDEX: number = 2;

// 设置栈里 NavDestination 的实例键。设置子页都是单例语义（同一个页面不存在
// 「另一个实例」，没有 chatId 那样的参数），所以键恒为空串，去重完全由 name
// 决定：栈顶已经是这一页时 decidePush 返回 skip。
export function settingFrameKey(name: string, param: Object | undefined): string {
  return '';
}

// 返回 false 表示栈还没注册（SettingsPage 尚未挂树，只可能出现在登录前/冷启动
// 早期的深链上）。**故意不回退到 router.pushUrl**：目标页已经不在 main_pages.json
// 里，那条回退必然失败，调用方拿一个假的"成功"比拿 false 更糟。调用方据此给
// 用户一条"请从底部栏进设置"的提示。
export function navigateToSetting(dest: string): boolean {
  const stack: NavStackLike | undefined = stackOf('settings');
  if (stack === undefined) {
    logE(`navigateToSetting(${dest}): settings stack not registered`);
    return false;
  }
  // 推进去的是**设置页签的栈**，所以必须先确保设置页签是当前页签——否则子页
  // 推进去了却在屏幕外（深链可能在任何页签上被点开）。同值不写：setOrCreate
  // 即便同值也会惊动 MainScreen 的 @Watch。
  if (AppStorage.get<number>(KEY_MAIN_TAB) !== SETTINGS_TAB_INDEX) {
    AppStorage.setOrCreate<number>(KEY_MAIN_TAB, SETTINGS_TAB_INDEX);
  }
  const target: StackFrame = { name: dest, key: '' };
  // origin 恒为 'navbar'：设置子页要么从左栏那张列表点进来，要么从深链进来，
  // 两者的语义都是「换一个右栏内容」，所以 decidePush 给的是 clearAndPush——
  // 右栏是替换不是叠加。由此设置栈的深度恒为 1。将来若出现「子页里再点进下
  // 一层」的入口，那一处该传 'content'。
  const snap: StackFrame[] = snapshotOf(stack, settingFrameKey);
  const action: StackAction = decidePush(snap, 'navbar', target);
  if (action === 'skip') {
    return true;
  }
  if (action === 'clearAndPush') {
    stack.clear(false);
  }
  stack.pushPath({ name: dest });
  return true;
}
