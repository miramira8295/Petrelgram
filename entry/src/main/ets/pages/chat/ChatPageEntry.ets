import { ChatPage } from './ChatPage';
import { ReusableMessageBubble } from './ReusableMessageBubble';
import { globalReusePoolAvailable } from '../../util/messageReusePool';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { KEY_APP_DARK } from '../../util/theme';
import {
  BG_BLUR_DEFAULT, BG_PATTERN_DEFAULT, KEY_AUTOPLAY_MUTED, KEY_BG_BLUR,
  KEY_BG_PATTERN, KEY_BG_PATTERN_DARK, KEY_CHAT_DIM,
  KEY_LOCAL_BG_EPOCH, KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_VIDEO,
  KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BACKGROUND, KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_REACTIONS, KEY_POWER_PARTICLES, KEY_REDUCE_ANIM,
  KEY_SEND_BY_ENTER, KEY_TRANSLATE_CHATS,
} from '../../store/AppSettings';
import { KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT } from '../../util/debugListPerf';

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再需要进 main_pages.json。
// V1 外壳组件：只做一件事——订阅 AppStorage，把 21 个全局单值透传给 V2 的
// ChatPage。
//
// 为什么需要它：@StorageProp / @StorageLink 是状态管理 V1 独有的装饰器，
// ChatPage 迁 @ComponentV2 之后不能再声明它们；而官方 FAQ《如何实现 V1、V2
// 版本之间父子组件的数据传递与共享》写明「AppStorage 在 V1 向 V2 传递的场景下，
// V2 版本的子组件不能自动同步更新，只能通过 AppStorage.get 手动获取」。
//
// 为什么不直接搬去 AppStorageV2：官方《AppStorageV2》「使用限制」两条都是硬的
// ——「AppStorage 与 AppStorageV2 之间的数据互不共享」、「不支持存储基本类型，
// 如 string、number、boolean」。这 21 个键全是 number/boolean，而且不是本页
// 私有的：全仓 @StorageProp/@StorageLink 共 513 处、分布在 100 个文件，写入方
// 主要在 AppSettings.ets / EntryAbility.ets / Globals.ets。只搬会话页这一份，
// 同一个键就会变成「V1 写、V2 读」，永远读到默认值，而且不报错。
//
// 合法性：《@ReusableV2装饰器：V2组件复用》的混用支持表「V1 普通组件 → V2 普通
// 组件：支持」。基本类型不需要 UIUtils.enableV2Compatibility 桥接——那个接口
// 「不支持非 object 类型」，对 number/boolean 调了也只是返回入参自身。
//
// 代价：某个 epoch 变一次，这一层就重跑一次 build()，把 21 个 @Param 重新交给
// ChatPage。@Param 只在值真的变化（===）时才向下传播刷新，所以代价是一次
// 参数比较，不是一次页面重建。
@Preview
@Component
struct ChatPageChrome {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(MATERIAL_EPOCH) materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp(KEY_APP_DARK) appDark: boolean = false;
  @StorageProp(KEY_LOCAL_BG_EPOCH) localBgEpoch: number = 0;
  // 聊天壁纸的三根滑杆：纹理按深浅色分两个键（既有行为），模糊与遮罩暂时仍是
  // 单键——四槽位独立化是下一步，这里先把"由谁来读"这件事挪对位置。
  @StorageProp(KEY_BG_BLUR) chatBgBlur: number = BG_BLUR_DEFAULT;
  @StorageProp(KEY_BG_PATTERN) chatBgPatternLight: number = BG_PATTERN_DEFAULT;
  @StorageProp(KEY_BG_PATTERN_DARK) chatBgPatternDark: number = BG_PATTERN_DEFAULT;
  @StorageProp(KEY_CHAT_DIM) chatBgDim: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('keyboardHeightVp') keyboardH: number = 0;
  @StorageProp('appIsForeground') appIsForeground: boolean = true;
  @StorageProp(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp('screenHeightVp') screenH: number = 780;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) powerChatEffects: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_BACKGROUND) powerBackgroundEffect: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) powerParticles: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) powerEmoji: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) powerEmojiReactions: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_AUTOPLAY_MUTED) autoplayMuted: boolean = true;
  @StorageProp(KEY_TRANSLATE_CHATS) translateChatsEnabled: boolean = false;
  // ⚠️ 临时（P6 标定）：cachedCount 档位。它走这一层而不是 ChatPage 直接读
  // AppStorage，是因为「立即生效」靠的正是这条 V1→V2 的透传链：@StorageProp
  // 观测到键变化 → 本层重跑 build() → @Param 值变了 → ChatPage 里依赖它的
  // .cachedCount() 重新求值。ChatPage 自己 AppStorage.get 是读不到变化的。
  @StorageProp(KEY_DEBUG_LIST_CACHED) listCachedCount: number = LIST_CACHED_COUNT_DEFAULT;

  build() {
    ChatPage({
      appearanceEpoch: this.appearanceEpoch,
      materialEpoch: this.materialEpoch,
      localBgEpoch: this.localBgEpoch,
      chatBgBlur: this.chatBgBlur,
      chatBgPattern: this.appDark ? this.chatBgPatternDark : this.chatBgPatternLight,
      chatBgDim: this.chatBgDim,
      langEpoch: this.langEpoch,
      appDark: this.appDark,
      topSafe: this.topSafe,
      bottomSafe: this.bottomSafe,
      keyboardH: this.keyboardH,
      appIsForeground: this.appIsForeground,
      sendByEnter: this.sendByEnter,
      screenW: this.screenW,
      screenH: this.screenH,
      powerSaving: this.powerSaving,
      powerChatEffects: this.powerChatEffects,
      powerBackgroundEffect: this.powerBackgroundEffect,
      powerParticles: this.powerParticles,
      powerEmoji: this.powerEmoji,
      powerEmojiReactions: this.powerEmojiReactions,
      reduceAnimations: this.reduceAnimations,
      autoplayVideo: this.autoplayVideo,
      autoplayMuted: this.autoplayMuted,
      translateChatsEnabled: this.translateChatsEnabled,
      listCachedCount: this.listCachedCount
    });
  }
}

// 消息行外壳的**全局复用池宿主**（API 26 起）。
//
// 它只做一件事：在 ChatPageChrome 之上多一层，把 reusePool / poolAccepts 挂
// 出去。官方《全局复用：集中化的组件回收与复用》——复用组件创建或销毁时，
// 框架「向上遍历组件树」找接纳该类型的全局池；找不到就退回父组件的默认池。
// 所以宿主只需要是 ReusableMessageBubble 的**任一祖先**，不必是它的父组件，
// 也不必知道列表长什么样。
//
// ── 为什么必须是单独一层，而不是把参数写在 ChatPageChrome 或 ChatPage 上 ──
//
// reusePool / poolAccepts 是**装饰器参数**，编译期就定死，没有任何运行时开关。
// 而这个能力从 API 26 才有，本仓 compatibleSdkVersion 是 6.0.0(20)。要做成
// 双路径，唯一的办法是让「挂了池的组件」和「没挂池的组件」是两个不同的类，
// 在运行时按设备版本二选一地**实例化**——见下面的 ChatPageBuilder。
//
// 低版本上这个 struct 只是一个从不被 new 出来的类：ChatPageBuilder 那条 if
// 永远走 else，池配置一次也不会被触碰，行为与 P4 完全一致（回退到默认复用池）。
//
// ── 为什么是 'shared' 而不是 'perInstance' ──
//
// 本应用的聊天详情页**可以同时存在多个实例**：
//   - 平板分栏（docs 2026-08-21-tablet-split-view-design）左右两栏各一页；
//   - Navigation 栈里从搜索结果进会话、再返回，栈上会先后压着两份；
//   - 会话 → 资料页 → 共同群组 → 另一个会话，栈里两份会话页同时活着。
// perInstance 的池「生命周期与其拥有组件实例相同」——上面每一种情况都是
// 「关掉一栏/弹一层，那一份池连同里面所有回收实例一起销毁」，而下一次打开
// 会话只能从零重建。shared 则是「只要还有任意一个宿主实例活着，池就活着」，
// 分栏切会话、返回再进，都能从池里取。
//
// 官方两处也都指向 shared：能力对比表「shared 模式允许拥有组件类的所有实例
// 共享单个池」，所有权模式一节直接写「建议开发者配置 shared 所有权。这样可以
// 获得更好的复用率和更低的内存占用」。
//
// shared 的代价官方也点了名：「只要拥有组件类的任何实例存在，池就会持续存在
// ……回收的组件可能会累积。使用 maxCount 来控制内存使用」——这正是 ChatPage
// 里 capMessageReuseBuckets() 存在的理由。
//
// freezeWhenInactive 必须显式给（官方使用限制：「配置 reusePool 和 poolAccepts
// 启用全局复用的同时，需要额外配置 freezeWhenInactive 参数」）。给 false 是
// 因为 ChatPageChrome 现在就是不冻结的（@Component 不写这个参数即为 false），
// 这一层不该顺手改变冻结语义。
// ── preRender 为什么没有开：它和首屏分级揭示是打架的 ────────────────────
//
// 全局池的第三项能力是 IReusePool.preRender(builder, times)：调度**空闲任务**
// 提前把复用组件建好放进池子，「加快初始渲染速度」。本页已经有一套解决首屏的
// 机制——首屏分级揭示（initialMessageStage：进页面先只放 1 行真身、其余是估高
// 占位，之后每次 release 只放行 1 行）。两者都在解决首屏，所以必须挑一个，
// 不能两个都开着还不说。
//
// **结论：保留分级揭示，不开 preRender。** 三条理由，从硬到软：
//
// 1. 同一个窗口、同一条线程，而且抢的正是对方赖以成立的那点空隙。
//    分级揭示的整个机制就是「每个 VSync 只允许建一行」这条硬上限——
//    nextInitialMessageRevealCount 的注释记着为什么是 1 而不是 3：一对含贴纸的
//    行能吃掉 26~28ms，六行挤进一次布局是 65ms。而 preRender 是**空闲任务**，
//    它跑的就是每帧建完那一行之后剩下的那段空闲。在首屏窗口里开 preRender，
//    等于一边限流一边从旁路灌水，被拖长的恰好是分级揭示要保护的那几帧。
//
// 2. 首屏那一刻**不知道该预建哪个桶**。全局池是按 reuseId 分区存放的，
//    REUSE_ID_LEVEL = 'medium' 之下 rowReuseId 是一个 12 维的字符串，完全由
//    行自己的数据算出来。而 preRender 必须在数据到达之前调用才谈得上「提前」
//    ——那时一行消息都还没有，猜错的桶里那个实例不会被任何一行取走，只是白建
//    一次、再白占一份内存。
//
// 3. preRender 吃的是 WrappedBuilder<[]>（零参 @Builder），意味着要在里面凭空
//    造一个 AlbumGroup / MessageEntry 喂给 ReusableMessageBubble。而这棵子树
//    挂载时是有副作用的：ReusableMessageBubble.aboutToAppear 会按
//    (chatId, rowId) 去 messageRowPresentationChannel 订阅，更深的 MessageBubble
//    会按内容发起缩略图/媒体的取数。拿一条**不存在的消息**去跑这些，副作用是
//    真的会发出去的。
//
// 而 preRender 本来想给的那份「打开会话时池子已经是热的」，shared 池自己就给了：
// 只要还有任意一个宿主实例活着，上一个会话回收的行就还在池子里，下一个会话
// 直接取。这是不用伪造任何数据、也不占用首屏那段线程的同一份收益。
//
// 什么时候可以回头再看这条：如果上机数据显示首屏的瓶颈不在**建树**而在别处，
// 或者分级揭示被证明可以撤掉，那时 preRender 才有位置——调用点是本组件的
// aboutToAppear（官方示例就在那里），拿 UIUtils.getCustomComponentContext(this)
// .getReusePool() 取池。在那之前，这里刻意什么都不做。
@ComponentV2({
  reusePool: 'shared',
  poolAccepts: [ReusableMessageBubble],
  freezeWhenInactive: false
})
struct ChatPagePoolHost {
  build() {
    ChatPageChrome();
  }
}

@Builder
export function ChatPageBuilder(): void {
  // 双路径。形状照 util/overlayMaterial.ets：判定是一个纯函数吃设备版本，
  // 调用点只问「赢了没有」。
  //
  // 低版本这一支与 P4 逐字节相同：ChatPageChrome 直接上，
  // ReusableMessageBubble 用父组件的默认复用池，rowReuseId 分档照旧生效。
  if (globalReusePoolAvailable()) {
    ChatPagePoolHost();
  } else {
    ChatPageChrome();
  }
}
