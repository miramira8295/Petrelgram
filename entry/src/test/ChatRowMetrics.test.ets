import { describe, expect, it } from '@ohos/hypium';
import {
  chatRowAvatarColumnHeight, chatRowSpec, ChatRowSpec
} from '../main/ets/util/chatRowMetrics';
import { ROW_PAD_V } from '../main/ets/util/theme';

// 会话行的两套尺寸（2026-09-18）。手机 60、平板分栏 72，判据是 splitMetrics
// 那条「只分手机与平板分栏，强制单栏算手机」。

export default function chatRowMetricsTest() {
  describe('ChatRowMetrics', () => {
    it('手机紧凑 62，平板分栏保留 72', 0, (): void => {
      expect(chatRowSpec(false).minHeight).assertEqual(62);
      expect(chatRowSpec(true).minHeight).assertEqual(72);
    });

    // 这条是这一组数字存在的理由：头像那一列必须**正好**填满行高，多一点行会被
    // 顶高、少一点就是白留的空。两档都要成立。
    it('头像 + 上下内边距 == 行高（两档都成立）', 0, (): void => {
      const phone: ChatRowSpec = chatRowSpec(false);
      const tablet: ChatRowSpec = chatRowSpec(true);
      expect(chatRowAvatarColumnHeight(phone)).assertEqual(phone.minHeight);
      expect(chatRowAvatarColumnHeight(tablet)).assertEqual(tablet.minHeight);
      expect(phone.avatar + ROW_PAD_V * 2).assertEqual(62);
      expect(tablet.avatar + ROW_PAD_V * 2).assertEqual(72);
    });

    // 文字列（标题 17 + 间距 + 预览）加上下内边距也必须落在行高以内，否则
    // minHeight 形同虚设——72→60 那一版就是先踩了这个才发现只改头像没用。
    it('文字列同样卡在行高以内', 0, (): void => {
      const titleFont: number = 17;
      [chatRowSpec(false), chatRowSpec(true)].forEach((spec: ChatRowSpec): void => {
        const textColumn: number = titleFont + spec.titleGap + spec.previewFont + ROW_PAD_V * 2;
        expect(textColumn <= spec.minHeight).assertTrue();
      });
    });

    it('紧凑档每一项都不大于宽松档', 0, (): void => {
      const phone: ChatRowSpec = chatRowSpec(false);
      const tablet: ChatRowSpec = chatRowSpec(true);
      expect(phone.avatar <= tablet.avatar).assertTrue();
      expect(phone.titleGap <= tablet.titleGap).assertTrue();
      expect(phone.previewFont <= tablet.previewFont).assertTrue();
    });
  });
}
