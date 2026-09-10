import { AlbumGroup } from '../../util/collapseAlbums';
import {
  MessageBubbleActions, MessageBubbleRenderData, ReusableMessageBubble
} from './ReusableMessageBubble';

// Repeat 与 @ReusableV2 之间的那一层薄壳。**只有转发，没有任何逻辑。**
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
// 【为什么参数原样透传】这一层不做缓存也不做判断：任何在这里加工的东西都会
// 变成第二个真相来源。它存在的唯一意义是给 Repeat 一个普通 V2 组件当边界。
//
// 【reuseId 挂在这一层里面】内层气泡的复用分档照旧由 rowReuseId 决定，
// 调用方把算好的字符串传进来——放在这里而不是外面，是为了让 Repeat 看到的
// 直接子节点是普通 V2 组件。
@ComponentV2
export struct MessageRowHost {
  @Require @Param group: AlbumGroup;
  @Param nowSec: number = 0;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param bubbleReuseId: string;

  build() {
    ReusableMessageBubble({
      group: this.group,
      nowSec: this.nowSec,
      data: this.data,
      actions: this.actions
    }).reuse({ reuseId: (): string => this.bubbleReuseId });
  }
}
