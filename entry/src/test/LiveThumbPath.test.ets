import { describe, expect, it } from '@ohos/hypium';
import { liveThumbPath } from '../main/ets/util/liveThumbPath';
import { shouldReattachThumb } from '../main/ets/util/liveThumbAttach';

export default function liveThumbPathTest() {
  describe('liveThumbPath', () => {
    it('fileId 为 0 时新路径替换旧消息的图片', 0, (): void => {
      expect(liveThumbPath(0, '', '/old.jpg', '/new.jpg', true)).assertEqual('/new.jpg');
      expect(liveThumbPath(0, '', '/old.jpg', '', true)).assertEqual('');
    });

    it('通道路径对可下载文件具有最高优先级', 0, (): void => {
      expect(liveThumbPath(42, '/landed.jpg', '/old.jpg', '/seed.jpg', true))
        .assertEqual('/landed.jpg');
    });

    it('同一文件跨复用池时保留已有图片', 0, (): void => {
      expect(liveThumbPath(42, '', '/decoded.jpg', '', true)).assertEqual('/decoded.jpg');
    });

    it('换文件且通道未落地时不保留上一张图', 0, (): void => {
      expect(liveThumbPath(99, '', '/old.jpg', '', false)).assertEqual('');
      expect(liveThumbPath(99, '', '/old.jpg', '/new-seed.jpg', false))
        .assertEqual('/new-seed.jpg');
    });
    // 2026-09-10 真机定案的回归：LiveThumbImage 的 6 个 @Param 合并成 spec 对象
    // 之后，两个自愈用的 @Monitor 还写着合并前的名字（'fileId'/'initialPath'），
    // 组件里已无此成员 ⇒ ArkUI 静默不触发 ⇒ 复用时挂着上一行的文件不放，
    // 表现为"图配错文"：文字是新消息的、图还是上一条的。实测 50 次 attach
    // 里那两个回调触发 0 次，同一次滑动抓到 7 次挂错行。
    it('reattaches_the_thumbnail_when_the_row_changes_file', 0, () => {
      // 换了文件：必须重挂，否则画的是上一行的图。
      expect(shouldReattachThumb(14680, '', 14667, 'old_121.jpg')).assertTrue();
      // 反方向（往回滑）同样成立。
      expect(shouldReattachThumb(14950, '', 14980, 'newer_121.jpg')).assertTrue();
      // 回收之后还没重挂（-1）：也要重挂。
      expect(shouldReattachThumb(14993, '', -1, 'leftover_121.jpg')).assertTrue();
      // 同一个可下载文件：路径由通道自己推，别做无谓的退订+重订阅。
      expect(shouldReattachThumb(14680, '', 14680, 'x_120.jpg')).assertFalse();
      // 纯路径模式：身份是 initialPath 本身。
      expect(shouldReattachThumb(0, 'mine.jpg', 0, 'previous.jpg')).assertTrue();
      expect(shouldReattachThumb(0, 'mine.jpg', 0, 'mine.jpg')).assertFalse();
      // 两种模式互相切换都要重挂。
      expect(shouldReattachThumb(0, 'mine.jpg', 14680, 'x_120.jpg')).assertTrue();
      expect(shouldReattachThumb(14680, '', 0, 'mine.jpg')).assertTrue();
    });

  });
}
