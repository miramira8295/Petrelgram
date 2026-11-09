import { logW } from './log';

// 常驻不变量：**旁路快照压过 @Param 时，两者描述的必须是同一条消息**。
//
// ReusableMessageBubble.currentGroup() 让 messageRowPresentationChannel 的快照
// 优先于结构性 @Param，守卫只有 `rowId 相等`——那只保证"同一行"，不保证"同一
// 份内容版本"。通道给了旧快照时，上游所有判据看到的都对，画出来的却是旧的。
//
// 2026-09-10 那轮"消息重复/相册变文本"的排查里，这道闸全程 0 告警，正是它把
// 旁路这条路彻底排除掉，才让注意力集中到 Repeat 的 ListItem 复用上
// （见 ChatPage 里 virtualScroll 那段注释）。留着它，下次同类症状能直接跳过
// 这一段。
//
// 前 20 条全打 + 每 50 次一行汇总：只报一次会在"正在持续错"时变瞎，那是上一
// 版踩过的坑。

const MAX_LINES: number = 20;
let liveLines: number = 0;
let liveHits: number = 0;

export function checkRenderedGroup(paramId: number, renderedId: number, rowId: number): void {
  if (paramId === renderedId) {
    return;
  }
  liveHits++;
  if (liveLines < MAX_LINES) {
    liveLines++;
    logW(`[RowGuard] channel snapshot won over the param: rowId=${rowId}` +
      ` param=${paramId} rendered=${renderedId}`);
    return;
  }
  if (liveHits % 50 === 0) {
    logW(`[RowGuard] channel-override sum hits=${liveHits}`);
  }
}
