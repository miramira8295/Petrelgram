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

// 设置栈里 NavDestination 的实例键。
//
// 十六个设置子页是单例语义（同一个页面不存在「另一个实例」，没有 chatId 那样的
// 参数），键恒为空串，去重完全由 name 决定：栈顶已经是这一页时 decidePush 返回
// skip。
//
// **ProxyPage 是唯一的例外**：tg://proxy 深链会带着一组代理参数把它拉起来，
// 页面据此把「新增代理」表单预填好并弹出（迁移前那是 router.pushUrl 的 params，
// 每次都新建一个页面实例）。键若仍恒为空串，站在 ProxyPage 上再点第二条代理
// 链接就会被判成 skip——表单不弹，现象是"点了没反应"。所以带参数的那一层按
// 「服务器:端口」区分实例：
//   · 同一条代理链接点两次 → 键相同 → skip（表单已经开着，正是想要的）；
//   · 另一条代理链接      → 键不同 → clearAndPush，重建页面吃新参数；
//   · 从设置列表点进来（无参数）→ 键是空串，和任何带参数的层都不等 →
//     clearAndPush，得到一个干净的、不预填表单的代理页。
export function settingFrameKey(name: string, param: Object | undefined): string {
  if (param === undefined) {
    return '';
  }
  const fields = param as Record<string, Object>;
  const server = (fields['proxyServer'] as string | undefined) ?? '';
  const port = (fields['proxyPort'] as number | undefined) ?? 0;
  if (server === '' || port <= 0) {
    // 参数不成形（或者是将来某个页面塞的别的形状）：退回单例语义，别拿一个
    // 随机键把去重打散。
    return '';
  }
  return `${server}:${port}`;
}

// 返回 false 表示栈还没注册（SettingsPage 尚未挂树，只可能出现在登录前/冷启动
// 早期的深链上）。**故意不回退到 router.pushUrl**：目标页已经不在 main_pages.json
// 里，那条回退必然失败，调用方拿一个假的"成功"比拿 false 更糟。调用方据此给
// 用户一条"请从底部栏进设置"的提示。
// param 只有 tg://proxy 深链会传（预填代理表单用），其余调用方一律省略——
// 省略时行为与加这个参数之前逐字一致：pushPath 不带 param，settingFrameKey
// 返回空串。
export function navigateToSetting(dest: string, param?: Object): boolean {
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
  const target: StackFrame = { name: dest, key: settingFrameKey(dest, param) };
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
  stack.pushPath({ name: dest, param: param });
  return true;
}
