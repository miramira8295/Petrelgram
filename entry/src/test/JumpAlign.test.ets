import { describe, expect, it } from '@ohos/hypium';
import { isResumeLanding } from '../main/ets/util/jumpAlign';

// 跳转落点居中（#219-6），但「回到上次阅读位置」必须原样恢复，不能也居中。
export default function jumpAlignTest() {
  describe('JumpAlign', () => {
    it('目标行就是记下的阅读位置那一行 = 恢复位置', 0, () => {
      expect(isResumeLanding(12, 12)).assertTrue();
    });

    // 相册：记下的是这一行的首条 id，跳转目标可能是其中另一张——按行比才认得出。
    // （按 id 比会漏判，原来的 itemY 分支就是按 id 比的。）
    it('按行比较，不按消息 id', 0, () => {
      expect(isResumeLanding(3, 3)).assertTrue();
      expect(isResumeLanding(3, 4)).assertFalse();
    });

    it('没有记下的阅读位置（行下标 < 0）时一律是普通跳转', 0, () => {
      expect(isResumeLanding(5, -1)).assertFalse();
      expect(isResumeLanding(-1, -1)).assertFalse();
    });
  });
}
