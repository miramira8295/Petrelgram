import { describe, expect, it } from '@ohos/hypium';
import {
  COMPOSER_EDIT, COMPOSER_IDLE, COMPOSER_REPLY, ComposerMode,
  cancelEdit, clearReply, draftToRestore, enterEdit, enterReply, idleComposer
} from '../main/ets/util/composerMode';

// 输入框上方那一条只有一个位置，所以回复和编辑不可能同时存在——这里的用例
// 就是把这条不变量钉死。
export default function composerModeTest() {
  describe('composerMode', () => {
    it('初始是普通输入', 0, () => {
      expect(idleComposer().kind).assertEqual(COMPOSER_IDLE);
    });

    it('回复带上目标和摘要', 0, () => {
      const m: ComposerMode = enterReply(idleComposer(), 42, '小明', '在吗');
      expect(m.kind).assertEqual(COMPOSER_REPLY);
      expect(m.replyToId).assertEqual(42);
      expect(m.replyName).assertEqual('小明');
      expect(m.replyText).assertEqual('在吗');
    });

    it('进入编辑必定清掉待回复', 0, () => {
      let m: ComposerMode = enterReply(idleComposer(), 42, '小明', '在吗');
      m = enterEdit(m, 7, 'text', '原文', '草稿');
      expect(m.kind).assertEqual(COMPOSER_EDIT);
      expect(m.replyToId).assertEqual(0);
      expect(m.replyName).assertEqual('');
      expect(m.replyText).assertEqual('');
    });

    it('进入回复也会作废正在进行的编辑', 0, () => {
      let m: ComposerMode = enterEdit(idleComposer(), 7, 'text', '原文', '草稿');
      m = enterReply(m, 42, '小明', '在吗');
      expect(m.editingId).assertEqual(0);
      expect(m.kind).assertEqual(COMPOSER_REPLY);
    });

    it('首次进编辑记下草稿，编辑期间换目标不冲掉它', 0, () => {
      let m: ComposerMode = enterEdit(idleComposer(), 7, 'text', '原文', '写了一半');
      expect(m.draftBeforeEdit).assertEqual('写了一半');
      m = enterEdit(m, 8, 'caption', '另一条', '原文');
      expect(m.draftBeforeEdit).assertEqual('写了一半');
      expect(m.editingId).assertEqual(8);
    });

    it('取消编辑回到普通输入，并给出要还的草稿', 0, () => {
      const m: ComposerMode = enterEdit(idleComposer(), 7, 'text', '原文', '写了一半');
      expect(draftToRestore(m)).assertEqual('写了一半');
      expect(cancelEdit(m).kind).assertEqual(COMPOSER_IDLE);
    });

    it('不在编辑态时没有可还的草稿', 0, () => {
      expect(draftToRestore(idleComposer())).assertEqual('');
      expect(draftToRestore(enterReply(idleComposer(), 42, 'a', 'b'))).assertEqual('');
    });

    it('取消不匹配的状态是空操作', 0, () => {
      const reply: ComposerMode = enterReply(idleComposer(), 42, 'a', 'b');
      expect(cancelEdit(reply).kind).assertEqual(COMPOSER_REPLY);
      const edit: ComposerMode = enterEdit(idleComposer(), 7, 'text', 'x', '');
      expect(clearReply(edit).kind).assertEqual(COMPOSER_EDIT);
    });

    it('非法目标 id 不改变状态', 0, () => {
      const m: ComposerMode = idleComposer();
      expect(enterReply(m, 0, 'a', 'b').kind).assertEqual(COMPOSER_IDLE);
      expect(enterEdit(m, 0, 'text', 'x', '').kind).assertEqual(COMPOSER_IDLE);
    });
  });
}
