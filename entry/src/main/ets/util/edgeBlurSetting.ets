// 屏幕上下边缘渐变虚化（linearGradientBlur）的统一性能控制。
//
// 【管什么】只管屏幕**最上沿/最下沿**那一条内容渐隐变糊的效果，也就是挂在页面
// 滚动容器上的 linearGradientBlur。**不碰**顶栏、输入栏、导航栏、卡片、弹窗那些
// 玻璃组件（backdropBlur / 系统材质是另一套，见 util/surfaceGlass 与 util/materialTuning）。
//
// 【用户口径（2026-11-19 m00431）】
//   全局：总开关 + 顶部 + 底部（各自独立）。
//   页面：固定三类，不得增减——聊天页 / 聊天列表页 / 其他页面；每类只有顶部、底部
//        两个简单开关，可覆盖全局对应项；**不提供「跟随/强制」三态**。
//   优先级：总开关最高（关掉即全部不糊）；其次页面开关；页面没单独设过时用全局默认。
//
// 【两类存储】
//   三个全局值是 boolean；六个页面项是字符串 follow/on/off，但 UI 永远只显示布尔
//   （follow 时取全局值）。这样既满足「只显示开关」，又能在用户把页面开关拨回与
//   全局相同的位置时自动回到跟随（见 setter 注释），不会把用户锁死在强制值上。
//
// 【两条消费通道】
//   V1 @Component   → @StorageProp(KEY_EDGE_BLUR_*)（V1 只认 AppStorage）
//   V2 @ComponentV2 → 读 @Trace 单例 edgeBlurSwitch（V2 里 @StorageProp 是编译错误）
// 唯一写入口是 AppSettings.setBoolean / setString，它们同时更新 AppStorage、本单例
// 与磁盘，三个入口不会各说各话。
//
// 【关闭时怎么写】不要直接链式调用 `.linearGradientBlur(0, ...)`：真机 Rosen 实测
// 即使半径 0 且 stops 全 0，节点仍会挂上 `NeedFilter[true]` + `RSLinearGradientBlurFilterBlur`，
// 触发整屏脏区扩张与每帧整屏离屏快照。请统一走 util/scrollEdgeBlurModifier 的
// ScrollEdgeBlurBinder + `.attributeModifier(...)`，关闭时根本不调用 linearGradientBlur。

export const KEY_EDGE_BLUR_ON: string = 'edgeBlurOn';
export const KEY_EDGE_BLUR_TOP_ON: string = 'edgeBlurTopOn';
export const KEY_EDGE_BLUR_BOTTOM_ON: string = 'edgeBlurBottomOn';
/** 页面级六项：聊天页、聊天列表页、其他页面，各一份顶部/底部覆盖。 */
export const KEY_EDGE_BLUR_CHAT_TOP: string = 'edgeBlurChatTop';
export const KEY_EDGE_BLUR_CHAT_BOTTOM: string = 'edgeBlurChatBottom';
export const KEY_EDGE_BLUR_LIST_TOP: string = 'edgeBlurListTop';
export const KEY_EDGE_BLUR_LIST_BOTTOM: string = 'edgeBlurListBottom';
export const KEY_EDGE_BLUR_OTHER_TOP: string = 'edgeBlurOtherTop';
export const KEY_EDGE_BLUR_OTHER_BOTTOM: string = 'edgeBlurOtherBottom';

/** 全局默认开启；动态时间线单独默认关闭，保留已验证的无整表滤镜路径。 */
export const EDGE_BLUR_ON_DEFAULT: boolean = true;
export const EDGE_BLUR_TOP_ON_DEFAULT: boolean = true;
export const EDGE_BLUR_BOTTOM_ON_DEFAULT: boolean = true;

/** 页面级内部取值：跟随全局 / 强制开 / 强制关（UI 不展示这三个词，只展示开关）。 */
export const EDGE_BLUR_FOLLOW: string = 'follow';
export const EDGE_BLUR_FORCE_ON: string = 'on';
export const EDGE_BLUR_FORCE_OFF: string = 'off';

export function normalizeEdgeBlurOverride(value: string): string {
  if (value === EDGE_BLUR_FORCE_ON || value === EDGE_BLUR_FORCE_OFF) {
    return value;
  }
  return EDGE_BLUR_FOLLOW;
}

@ObservedV2
export class EdgeBlurSwitch {
  @Trace master: boolean = EDGE_BLUR_ON_DEFAULT;
  @Trace top: boolean = EDGE_BLUR_TOP_ON_DEFAULT;
  @Trace bottom: boolean = EDGE_BLUR_BOTTOM_ON_DEFAULT;
  @Trace chatTop: string = EDGE_BLUR_FORCE_OFF;
  @Trace chatBottom: string = EDGE_BLUR_FORCE_OFF;
  @Trace listTop: string = EDGE_BLUR_FORCE_OFF;
  @Trace listBottom: string = EDGE_BLUR_FORCE_OFF;
  @Trace otherTop: string = EDGE_BLUR_FOLLOW;
  @Trace otherBottom: string = EDGE_BLUR_FOLLOW;
}

export const edgeBlurSwitch: EdgeBlurSwitch = new EdgeBlurSwitch();

/** 播种全局三项：启动读盘、磁盘不可用时的默认值、用户拨动开关，三条路径都走这里。 */
export function seedEdgeBlurOn(master: boolean, top: boolean = EDGE_BLUR_TOP_ON_DEFAULT,
  bottom: boolean = EDGE_BLUR_BOTTOM_ON_DEFAULT): void {
  edgeBlurSwitch.master = master;
  edgeBlurSwitch.top = top;
  edgeBlurSwitch.bottom = bottom;
  AppStorage.setOrCreate(KEY_EDGE_BLUR_ON, master);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_TOP_ON, top);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_BOTTOM_ON, bottom);
}

/** 播种页面级六项。 */
export function seedEdgeBlurPages(chatTop: string, chatBottom: string, listTop: string,
  listBottom: string, otherTop: string, otherBottom: string): void {
  const ct: string = normalizeEdgeBlurOverride(chatTop);
  const cb: string = normalizeEdgeBlurOverride(chatBottom);
  const lt: string = normalizeEdgeBlurOverride(listTop);
  const lb: string = normalizeEdgeBlurOverride(listBottom);
  const ot: string = normalizeEdgeBlurOverride(otherTop);
  const ob: string = normalizeEdgeBlurOverride(otherBottom);
  edgeBlurSwitch.chatTop = ct;
  edgeBlurSwitch.chatBottom = cb;
  edgeBlurSwitch.listTop = lt;
  edgeBlurSwitch.listBottom = lb;
  edgeBlurSwitch.otherTop = ot;
  edgeBlurSwitch.otherBottom = ob;
  AppStorage.setOrCreate(KEY_EDGE_BLUR_CHAT_TOP, ct);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_CHAT_BOTTOM, cb);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_LIST_TOP, lt);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_LIST_BOTTOM, lb);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_OTHER_TOP, ot);
  AppStorage.setOrCreate(KEY_EDGE_BLUR_OTHER_BOTTOM, ob);
}

/**
 * 页面开关的显示值：全局为默认，页面单独设过就用自己的。
 * 不含总开关——总开关关掉时子开关仍然显示各自的配置（设置项的常见形态），
 * 真正生效与否由 edgeBlurPageTopOn/BottomOn 把关。
 */
export function edgeBlurStateOn(globalOn: boolean, override: string): boolean {
  const o: string = normalizeEdgeBlurOverride(override);
  if (o === EDGE_BLUR_FORCE_ON) {
    return true;
  }
  if (o === EDGE_BLUR_FORCE_OFF) {
    return false;
  }
  return globalOn;
}

/** 页面级：该页面顶部是否真的该糊（总开关最高）。 */
export function edgeBlurPageTopOn(master: boolean, globalTop: boolean, override: string): boolean {
  return master && edgeBlurStateOn(globalTop, override);
}

/** 页面级：该页面底部是否真的该糊（总开关最高）。 */
export function edgeBlurPageBottomOn(master: boolean, globalBottom: boolean, override: string): boolean {
  return master && edgeBlurStateOn(globalBottom, override);
}

/** 「其他页面」顶部是否该糊——绝大多数页面（设置、联系人、资料……）都走这一条。 */
export function edgeBlurOtherTopOn(master: boolean, globalTop: boolean, otherTop: string): boolean {
  return edgeBlurPageTopOn(master, globalTop, otherTop);
}

/** 「其他页面」底部是否该糊。 */
export function edgeBlurOtherBottomOn(master: boolean, globalBottom: boolean, otherBottom: string): boolean {
  return edgeBlurPageBottomOn(master, globalBottom, otherBottom);
}

/** 非 UI 代码用的当前值（V2 UI 请直接读 edgeBlurSwitch 的 @Trace 字段）。 */
export function edgeBlurMasterOn(): boolean {
  return AppStorage.get<boolean>(KEY_EDGE_BLUR_ON) ?? edgeBlurSwitch.master;
}

/** 只改总开关（AppSettings.setBoolean 用），不动顶部/底部与页面级。 */
export function setEdgeBlurMaster(value: boolean): void {
  edgeBlurSwitch.master = value;
  AppStorage.setOrCreate(KEY_EDGE_BLUR_ON, value);
}

/** 只改全局顶部默认值。 */
export function setEdgeBlurTop(value: boolean): void {
  edgeBlurSwitch.top = value;
  AppStorage.setOrCreate(KEY_EDGE_BLUR_TOP_ON, value);
}

/** 只改全局底部默认值。 */
export function setEdgeBlurBottom(value: boolean): void {
  edgeBlurSwitch.bottom = value;
  AppStorage.setOrCreate(KEY_EDGE_BLUR_BOTTOM_ON, value);
}

/** 把六个页面级键之一同步进 @Trace 单例（AppSettings.setString 用）。 */
export function applyEdgeBlurPageValue(key: string, value: string): void {
  const v: string = normalizeEdgeBlurOverride(value);
  if (key === KEY_EDGE_BLUR_CHAT_TOP) { edgeBlurSwitch.chatTop = v; }
  if (key === KEY_EDGE_BLUR_CHAT_BOTTOM) { edgeBlurSwitch.chatBottom = v; }
  if (key === KEY_EDGE_BLUR_LIST_TOP) { edgeBlurSwitch.listTop = v; }
  if (key === KEY_EDGE_BLUR_LIST_BOTTOM) { edgeBlurSwitch.listBottom = v; }
  if (key === KEY_EDGE_BLUR_OTHER_TOP) { edgeBlurSwitch.otherTop = v; }
  if (key === KEY_EDGE_BLUR_OTHER_BOTTOM) { edgeBlurSwitch.otherBottom = v; }
}

/**
 * 页面开关被拨动后要写什么：值与全局默认相同就回到「跟随」，不同才写强制。
 * 这样用户没有「恢复默认」按钮也能回到跟随，界面上永远只是两个状态。
 */
export function edgeBlurOverrideFor(globalOn: boolean, value: boolean): string {
  if (value === globalOn) {
    return EDGE_BLUR_FOLLOW;
  }
  return value ? EDGE_BLUR_FORCE_ON : EDGE_BLUR_FORCE_OFF;
}
