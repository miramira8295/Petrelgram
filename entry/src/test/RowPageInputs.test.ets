import { describe, it, expect } from '@ohos/hypium';
import { buildRowPageInputs, rowPageKeyPart, RowPageInputs, RowPageInputsSource } from '../main/ets/util/rowPageInputs';

// 消息行 prepare 的页面级输入（第三刀）。键片段必须与改造前 cacheKey 里的对应各段逐字
// 一致（只是挪到末尾），任何一个输入变了键都得跟着变——漏一个就是缓存命中旧气泡。
function base(): RowPageInputsSource {
  return {
    isGroup: true, isChannel: false, translationActive: false, editingActive: false,
    liveCallActive: false, liveGroupCallId: 0, liveLocationMessageId: 0, autoplayMuted: true,
    appearanceEpoch: 3, materialEpoch: 5, appDark: false, selectionActive: false,
    chatContentWidth: 360, canReply: true, playSlotKey: '', freshSinceId: 0,
    pausedAnimationIds: [], forcedAnimationIds: [], failedAnimationIds: [], paidMediaPendingIds: []
  };
}

export default function rowPageInputsTest(): void {
  describe('rowPageInputs', (): void => {
    it('键片段逐段与改造前的写法一致', 0, (): void => {
      expect(rowPageKeyPart(base())).assertEqual(
        '|g10|tr0|edit0|live0|call0|mute1|appearance3|material5|dark0|select0|reply1');
    });

    it('每一个进键的输入变了，键都跟着变', 0, (): void => {
      const k0: string = rowPageKeyPart(base());
      const variants: RowPageInputsSource[] = [];
      let s: RowPageInputsSource = base(); s.isGroup = false; variants.push(s);
      s = base(); s.isChannel = true; variants.push(s);
      s = base(); s.translationActive = true; variants.push(s);
      s = base(); s.editingActive = true; variants.push(s);
      s = base(); s.liveGroupCallId = 7; variants.push(s);
      s = base(); s.liveLocationMessageId = 9; variants.push(s);
      s = base(); s.autoplayMuted = false; variants.push(s);
      s = base(); s.appearanceEpoch = 4; variants.push(s);
      s = base(); s.materialEpoch = 6; variants.push(s);
      s = base(); s.appDark = true; variants.push(s);
      s = base(); s.selectionActive = true; variants.push(s);
      s = base(); s.canReply = false; variants.push(s);
      const seen: Set<string> = new Set<string>([k0]);
      for (const v of variants) {
        const k: string = rowPageKeyPart(v);
        expect(seen.has(k)).assertFalse();
        seen.add(k);
      }
    });

    it('四个 id 数组转成集合，成员判定与 indexOf 一致', 0, (): void => {
      const s: RowPageInputsSource = base();
      s.pausedAnimationIds = [11, 12];
      s.forcedAnimationIds = [13];
      s.failedAnimationIds = [12];
      s.paidMediaPendingIds = [21];
      const p: RowPageInputs = buildRowPageInputs(s);
      expect(p.pausedIds.has(11)).assertTrue();
      expect(p.pausedIds.has(13)).assertFalse();
      expect(p.forcedIds.has(13)).assertTrue();
      expect(p.failedIds.has(12)).assertTrue();
      expect(p.paidMediaPendingIds.has(21)).assertTrue();
      expect(p.paidMediaPendingIds.has(11)).assertFalse();
    });

    it('其余页面级取值原样透传', 0, (): void => {
      const s: RowPageInputsSource = base();
      s.liveCallActive = true; s.liveGroupCallId = 42; s.chatContentWidth = 520;
      s.playSlotKey = '99:-1'; s.freshSinceId = 1000; s.selectionActive = true;
      const p: RowPageInputs = buildRowPageInputs(s);
      expect(p.liveCallActive).assertTrue();
      expect(p.liveGroupCallId).assertEqual(42);
      expect(p.chatContentWidth).assertEqual(520);
      expect(p.playSlotKey).assertEqual('99:-1');
      expect(p.freshSinceId).assertEqual(1000);
      expect(p.selectionActive).assertTrue();
      expect(p.isGroup).assertTrue();
      expect(p.canReply).assertTrue();
      expect(p.keyPart).assertEqual(rowPageKeyPart(s));
    });
  });
}
