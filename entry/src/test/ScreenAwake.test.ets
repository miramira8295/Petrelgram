import { describe, it, expect } from '@ohos/hypium';
import {
  AWAKE_OWNER_LIVE, requestScreenAwake, resetScreenAwakeForTest, screenAwakeApplyFailed,
  screenAwakeOwnerCount, videoAwakeOwner
} from '../main/ets/util/screenAwake';

export default function screenAwakeTest() {
  describe('ScreenAwake', () => {
    it('第一个持有者进来要推 true，最后一个放开要推 false', 0, () => {
      resetScreenAwakeForTest();
      expect(requestScreenAwake('a', true)).assertEqual(true);
      expect(requestScreenAwake('a', false)).assertEqual(false);
    });

    // 中间的增减不产生系统调用：集合空/非空没翻转就没必要再推一次。
    it('同一持有者重复登记不重复推', 0, () => {
      resetScreenAwakeForTest();
      expect(requestScreenAwake('a', true)).assertEqual(true);
      expect(requestScreenAwake('a', true)).assertNull();
      expect(screenAwakeOwnerCount()).assertEqual(1);
    });

    // 这条是本模块存在的理由：直播悬浮窗还开着的时候暂停一个视频，
    // 不能把直播的那份一起放掉。
    it('多个持有者时，放掉其中一个不熄屏', 0, () => {
      resetScreenAwakeForTest();
      expect(requestScreenAwake(AWAKE_OWNER_LIVE, true)).assertEqual(true);
      expect(requestScreenAwake('video:1', true)).assertNull();
      expect(requestScreenAwake('video:1', false)).assertNull();
      expect(screenAwakeOwnerCount()).assertEqual(1);
      expect(requestScreenAwake(AWAKE_OWNER_LIVE, false)).assertEqual(false);
    });

    it('没登记过的持有者注销不做任何事', 0, () => {
      resetScreenAwakeForTest();
      expect(requestScreenAwake('ghost', false)).assertNull();
      expect(screenAwakeOwnerCount()).assertEqual(0);
    });

    it('空名字一律忽略', 0, () => {
      resetScreenAwakeForTest();
      expect(requestScreenAwake('', true)).assertNull();
      expect(screenAwakeOwnerCount()).assertEqual(0);
    });

    // 同一时刻可能有两个播放器活着（全屏查看器从气泡接管的那一瞬间），
    // 名字必须按实例分开，否则先退场的会把后接手的一起放掉。
    it('每个播放器实例拿到不同的名字', 0, () => {
      resetScreenAwakeForTest();
      const first: string = videoAwakeOwner();
      const second: string = videoAwakeOwner();
      expect(first === second).assertFalse();
      requestScreenAwake(first, true);
      requestScreenAwake(second, true);
      requestScreenAwake(first, false);
      expect(screenAwakeOwnerCount()).assertEqual(1);
    });

    // 系统调用失败要回滚记账，否则下一次同方向的请求被当成"没变化"，
    // 永远不再重试。
    it('推送失败后同方向的请求会重试', 0, () => {
      resetScreenAwakeForTest();
      expect(requestScreenAwake('a', true)).assertEqual(true);
      screenAwakeApplyFailed(true);
      expect(requestScreenAwake('b', true)).assertEqual(true);
    });
  });
}
