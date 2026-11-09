import { AlbumGroup } from '../../util/collapseAlbums';
import { CHAT_PAGE_REUSE_ID_LEVEL, rowReuseId } from '../../util/rowReuseId';
import {
  MessageBubbleActions, MessageBubbleRenderData, ReusableMessageBubble
} from './ReusableMessageBubble';

// Repeat 与 @ReusableV2 之间的薄壳，使用已准备的 data 与当前 group 计算复用桶。
//
// 【为什么必须有它】官方《@ReusableV2装饰器》的使用限制原话：
//   「V2 的复用组件当前不支持直接用于 Repeat 的 template 中，
//     但是可以用在 template 中的 V2 自定义组件中。」
// 配套示例给的正确结构是 template → ListItem → Column → **普通 V2 组件** →
// V2 复用组件。而本项目此前是 each → ListItem → … → ReusableMessageBubble
// 直接暴露在 Repeat 之下，正处在文档说"不支持"的形状里——2026-09-10 那一整轮
// "消息重复 / 相册变文本 / 不该有图却有图"很可能就是它（见
// util 侧的排查记录）。
//
// 参数原样透传，不另建准备缓存；复用桶继续调用统一的 rowReuseId 算法。
//
// 【reuseId 挂在这一层里面】内层气泡的复用分档照旧由 rowReuseId 决定，
// 使用调用方已经准备的参数——放在这里而不是外面，是为了让 Repeat 看到的
// 直接子节点是普通 V2 组件。
@ComponentV2
export struct MessageRowHost {
  @Require @Param group: AlbumGroup;
  @Param nowSec: number = 0;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param reusePageScope: number;

  // @ReusableV2 用 .reuse({ reuseId })（API 18 起）取代 V1 的 .reuseId()。
  //
  // ⚠️ 官方《复用选项》对 reuseId 有一条版本相关的行为差，调研没有覆盖到：
  // 「在 API 版本 26.0.0 之前，当 reuseId 不是**显式返回字符串字面量**的回调
  // 方法时，实际的复用标识 id 为该自定义组件的名称」。下面这个回调不是字面量，
  // 所以在旧行为下会被降级成单一的 'ReusableMessageBubble'，CHAT_PAGE_REUSE_ID_LEVEL 的
  // 分档静默失效、所有行共用一个池。
  //
  // 走的是哪一侧，看编译产物就知道——ets-loader 把它编成了运行时判断：
  //   getReuseId: getUINativeModule().common.getApiTargetVersion() >= 26
  //     ? () => rowReuseId(...) : () => "ReusableMessageBubble"
  // 闸门是 **getApiTargetVersion()**，也就是 build-profile 里的 targetSdkVersion
  // （本仓 "26.0.0"），不是 compatibleSdkVersion("6.0.0(20)")、也不是设备版本。
  // 按这条推断分档是生效的，但这是读产物推出来的，**没上机验过**，列入待验清单。
  //
  // ⚠️ **别再试图用「低版本不走 .reuse()」绕开那段探测——试过了，绕不掉。**
  // 2026-08-26 的编译实验（把 .reuse({ reuseId }) 整个删掉、只留裸的
  // ReusableMessageBubble({...})，重新 assembleHap 再读产物）结果是：
  //   getReuseId: getUINativeModule().common.getApiTargetVersion() >= 26
  //     ? () => "ReusableMessageBubble" : () => "ReusableMessageBubble",
  // 探测**照样生成**，两侧只是塌成了同一个组件名。也就是说这段代码是
  // **@ReusableV2 子组件实例化**的产物，与 reuseId 是不是字符串字面量、与
  // 有没有 .reuse() 都**无关**。同一次实验里 V1 的 @Reusable（ChatRow）产物
  // 里一处都没有；当时全仓的这类探测只出现在 ChatPage 编译产物中。
  //
  // 结论：如果 getUINativeModule().common.getApiTargetVersion 在 API 20~25 的
  // 运行时不存在，那是 **d949bde（P3 批 1 迁 @ReusableV2）** 带进来的风险，
  // 不是 P5 的 .reuse() 带进来的；唯一的移除路径是退回 V1 @Reusable，那是
  // 整轮回滚，不是一处旁路。低版本设备是否真的会炸只能上机确认。
  //
  // 行的复用桶 id。**必须每次现算，不能跟着 prepared 一起缓存。**
  //
  // 【2026-09-11 回归，1.4.7 已发】用户报「点表情回复要退出重进才显示；已经有
  // 表情行的则不用」。根因就在这里：
  //   · rowReuseId 的中档桶里有 `hasReactionBar(msg) ? 'reactions' : 'no-reactions'`
  //     ——有没有表情行**是结构的一部分**，0→1 必须换桶（1→2 不换，所以那种
  //     情况一直是好的）。
  //   · 而 prepared 的 cacheKey 以 rowKeyOf(g) 打头，它走的是 rowIdentity
  //     （`message_${rowId}`），**不含 mutableSig**。加第一个表情时 cacheKey
  //     一个字不变 ⇒ 命中缓存 ⇒ reuseId 被冻在 'no-reactions' 那一档 ⇒ 框架
  //     发一个没有表情行的壳过来。
  // 当时把 rowReuseId 一起缓存仅省下一次计算，却造成了结构错配。
  // 此处读取当前 group 并现算 reuseId，避免重新调用页面的行准备函数，也不缓存桶 id。
  private bubbleReuseId(): string {
    return `chatPage${this.reusePageScope}_` +
      rowReuseId(this.data, this.group, CHAT_PAGE_REUSE_ID_LEVEL);
  }

  build() {
    ReusableMessageBubble({
      group: this.group,
      nowSec: this.nowSec,
      data: this.data,
      actions: this.actions
    }).reuse({ reuseId: (): string => this.bubbleReuseId() });
  }
}
