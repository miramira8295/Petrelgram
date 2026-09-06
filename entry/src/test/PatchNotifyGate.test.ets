import { describe, expect, it } from '@ohos/hypium';
import { patchNeedsNotify, PatchSignature } from '../main/ets/util/patchNotifyGate';

// 「这次 patch 值不值得发一次快照」的判据测试。
//
// 这条判据卡在一个很贵的东西前面：每次 store notify 都让 ChatPage 把整个已加载
// 窗口重新 collapseAlbums 一遍（mediaProgressChannel 文件头记的真机实测：
// 421 条时 8–20ms 主线程 JS，滑动中每秒 10 次）。
//
// 但它也卡在一个很关键的东西前面：**路径落地必须发**，否则贴纸/视频永远不显示。
// 所以这里的用例分两组——「该跳过的」和「绝不能跳过的」，后者更要紧。

function sig(path: string, failed: boolean, active: boolean): PatchSignature {
  return { path: path, failed: failed, active: active };
}

export default function patchNotifyGateTest() {
  describe('PatchNotifyGate', () => {

    // ——— 绝不能跳过的（漏发 = 内容永远不显示） ———

    it('路径落地必须发——这是漏发后果最严重的一条', 0, () => {
      expect(patchNeedsNotify(sig('', false, true), sig('/data/a.webp', false, false))).assertTrue();
    });

    it('失败标志翻转必须发', 0, () => {
      expect(patchNeedsNotify(sig('', false, true), sig('', true, false))).assertTrue();
      // 重试成功：failed 由真转假，同样要发
      expect(patchNeedsNotify(sig('', true, false), sig('', false, true))).assertTrue();
    });

    it('下载活跃态翻转必须发（进度环的显隐靠它）', 0, () => {
      expect(patchNeedsNotify(sig('', false, false), sig('', false, true))).assertTrue();
      expect(patchNeedsNotify(sig('', false, true), sig('', false, false))).assertTrue();
    });

    it('路径变成另一个路径也要发（重试落到新文件）', 0, () => {
      expect(patchNeedsNotify(sig('/data/a.webp', false, false), sig('/data/b.webp', false, false)))
        .assertTrue();
    });

    // ——— 该跳过的 ———

    // 这条是本判据存在的**全部意义**：进度是唯一的高频项（每秒十几次），
    // 而它走 mediaProgressChannel 旁路直达进度环，根本不进行 key。
    // 注意签名里**没有进度字段**——那正是设计：判据不看进度，所以进度怎么变
    // 都落到"无差别"这一档。
    it('只有进度变化时不发（签名里根本没有进度字段）', 0, () => {
      const before: PatchSignature = sig('', false, true);
      const after: PatchSignature = sig('', false, true);
      expect(patchNeedsNotify(before, after)).assertFalse();
    });

    it('三个字段全同就是不发', 0, () => {
      expect(patchNeedsNotify(sig('/p', true, true), sig('/p', true, true))).assertFalse();
      expect(patchNeedsNotify(sig('', false, false), sig('', false, false))).assertFalse();
    });

    // ——— 边界 ———

    it('任意一个字段不同就发（逐字段各验一次）', 0, () => {
      const base: PatchSignature = sig('/p', false, false);
      expect(patchNeedsNotify(base, sig('/q', false, false))).assertTrue();
      expect(patchNeedsNotify(base, sig('/p', true, false))).assertTrue();
      expect(patchNeedsNotify(base, sig('/p', false, true))).assertTrue();
    });
  });
}
