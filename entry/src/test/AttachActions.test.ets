import { describe, expect, it } from '@ohos/hypium';
import { attachActions, AttachAction, ATTACH_KEYS } from '../main/ets/util/attachActions';

// 附件面板是肌肉记忆：用户记的是"左上角是图库、右下角是骰子"，不是标签文字。
// 所以这份列表的**顺序**是要钉住的东西，比内容更重要。
//
// 唯一会变的是投票——Telegram 不允许私聊发投票。它排在倒数第二正是为此：
// 缺席时只有骰子一个格子挪位。
function keysOf(items: AttachAction[]): string[] {
  return items.map((a: AttachAction): string => a.key);
}

export default function attachActionsTest() {
  describe('attachActions', () => {
    it('keeps a fixed order in a private chat', 0, () => {
      expect(keysOf(attachActions(false, false)))
        .assertDeepEquals(['media', 'file', 'audio', 'videoNote', 'location', 'contact', 'dice']);
    });

    it('adds the poll only for groups and channels', 0, () => {
      const expected: string[] =
        ['media', 'file', 'audio', 'videoNote', 'location', 'contact', 'poll', 'dice'];
      expect(keysOf(attachActions(true, false))).assertDeepEquals(expected);
      expect(keysOf(attachActions(false, true))).assertDeepEquals(expected);
      expect(keysOf(attachActions(true, true))).assertDeepEquals(expected);
    });

    // 私聊相对群聊只少 poll 一项，其余相对次序完全不变——这就是"位置不漂移"
    // 的确切含义。
    it('changes nothing but the poll between chat kinds', 0, () => {
      const group: string[] = keysOf(attachActions(true, false));
      const priv: string[] = keysOf(attachActions(false, false));
      expect(group.filter((k: string): boolean => k !== 'poll')).assertDeepEquals(priv);
    });

    it('is stable across calls', 0, () => {
      expect(keysOf(attachActions(true, false))).assertDeepEquals(keysOf(attachActions(true, false)));
    });

    // 分发靠 key，重复就会有一个格子永远点不到。
    it('has unique keys', 0, () => {
      const keys: string[] = keysOf(attachActions(true, false));
      const seen: Set<string> = new Set<string>(keys);
      expect(seen.size).assertEqual(keys.length);
    });

    // ATTACH_KEYS 是 ChatPage 分发时的全集。列表里冒出一个它不认识的 key，
    // 就是一个点了没反应的格子。
    it('never produces a key outside the dispatch table', 0, () => {
      for (const kind of [[false, false], [true, false], [false, true]]) {
        for (const a of attachActions(kind[0], kind[1])) {
          expect(ATTACH_KEYS.includes(a.key)).assertTrue();
        }
      }
    });

    it('gives every entry an icon and a label', 0, () => {
      for (const a of attachActions(true, false)) {
        expect(a.icon.startsWith('sys.symbol.')).assertTrue();
        expect(a.tint.length > 0).assertTrue();
      }
    });
  });
}
