import { describe, expect, it } from '@ohos/hypium';
import {
  formatViewCount, publishViewCount, subscribeViewCount, viewCountLabelFor, viewCountOf,
  viewsReserve
} from '../main/ets/util/viewCountChannel';
import { interactionChanged } from '../main/ets/util/interactionDelta';
import { ReactionInfo } from '../main/ets/store/MessageEntry';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function rx(emoji: string, count: number, chosen: boolean = false): ReactionInfo {
  return { emoji, count, isChosen: chosen, customEmojiId: '', customEmojiPath: '' };
}

export default function viewCountChannelTest() {
  describe('ViewCountChannel', () => {
    // 与官方客户端同一种缩写：千以下原样，一万以下带一位小数，再往上取整。
    it('千以下原样显示，0 和负数不显示', 0, () => {
      expect(formatViewCount(0)).assertEqual('');
      expect(formatViewCount(-3)).assertEqual('');
      expect(formatViewCount(1)).assertEqual('1');
      expect(formatViewCount(999)).assertEqual('999');
    });

    it('一万以下带一位小数，整数时不带 .0', 0, () => {
      expect(formatViewCount(1000)).assertEqual('1K');
      expect(formatViewCount(5000)).assertEqual('5K');
      expect(formatViewCount(5231)).assertEqual('5.2K');
      expect(formatViewCount(9999)).assertEqual('9.9K');
    });

    // 2300/1000*10 在浮点里是 22.999…，直接 floor 会显示成 2.2K——必须整数运算。
    it('不受浮点误差影响', 0, () => {
      expect(formatViewCount(2300)).assertEqual('2.3K');
      expect(formatViewCount(4100)).assertEqual('4.1K');
      expect(formatViewCount(8200)).assertEqual('8.2K');
    });

    // 向下取整：1999 显示 2.0K 就是把没到的数说成到了。
    it('一律向下取整，不会凑成下一档', 0, () => {
      expect(formatViewCount(1999)).assertEqual('1.9K');
      expect(formatViewCount(999999)).assertEqual('999K');
      expect(formatViewCount(12345)).assertEqual('12K');
    });

    it('百万级用 M', 0, () => {
      expect(formatViewCount(1000000)).assertEqual('1M');
      expect(formatViewCount(1250000)).assertEqual('1.2M');
      expect(formatViewCount(45600000)).assertEqual('45M');
    });

    it('从 TDLib 消息里取浏览数，缺字段按 0', 0, () => {
      const withViews: TdObject = {
        'id': 1, 'interaction_info': { 'view_count': 5231 } as TdObject
      };
      expect(viewCountOf(withViews)).assertEqual(5231);
      const bare: TdObject = { 'id': 1 };
      expect(viewCountOf(bare)).assertEqual(0);
      // TDLib 对没有互动信息的消息给的是 JSON null，不是缺字段。
      const nullInfo: TdObject = JSON.parse('{"id":1,"interaction_info":null}') as TdObject;
      expect(viewCountOf(nullInfo)).assertEqual(0);
    });

    // ── 通道：这是「别让 UI 线程白干活」的那一半 ──────────────────────
    //
    // 频道里浏览数几乎每秒都在涨，5231 → 5232 → 5233 在界面上都是「5.2K」。
    // 标签没变就不叫醒气泡——订阅者一次都不该被调用。
    it('标签不变时不通知订阅者', 0, () => {
      publishViewCount(-100901, 1, 5231);
      let calls: number = 0;
      const off = subscribeViewCount(-100901, 1, (): void => { calls++; });
      publishViewCount(-100901, 1, 5232);
      publishViewCount(-100901, 1, 5299);
      expect(calls).assertEqual(0);
      publishViewCount(-100901, 1, 5300);
      expect(calls).assertEqual(1);
      off();
    });

    it('通知带的是新标签', 0, () => {
      let last: string = '';
      const off = subscribeViewCount(-100902, 7, (label: string): void => { last = label; });
      publishViewCount(-100902, 7, 999);
      expect(last).assertEqual('999');
      publishViewCount(-100902, 7, 1000);
      expect(last).assertEqual('1K');
      off();
    });

    // 浏览数只增不减。晚到的旧快照（翻页重新拉到的历史、乱序的推送）不能把它压回去。
    it('只增不减：旧值不覆盖新值', 0, () => {
      publishViewCount(-100903, 2, 8000);
      publishViewCount(-100903, 2, 7000);
      expect(viewCountLabelFor(-100903, 2)).assertEqual('8K');
    });

    // 消息 id 只在会话内唯一，键必须带会话。
    it('不同会话的同号消息互不串', 0, () => {
      publishViewCount(-100904, 3, 50);
      publishViewCount(-100905, 3, 70000);
      expect(viewCountLabelFor(-100904, 3)).assertEqual('50');
      expect(viewCountLabelFor(-100905, 3)).assertEqual('70K');
    });

    it('没发布过的消息标签为空', 0, () => {
      expect(viewCountLabelFor(-100906, 9)).assertEqual('');
    });

    it('退订之后不再收到通知', 0, () => {
      let calls: number = 0;
      const off = subscribeViewCount(-100907, 4, (): void => { calls++; });
      off();
      publishViewCount(-100907, 4, 10);
      expect(calls).assertEqual(0);
    });

    // 没有浏览数的消息（群聊、私聊）占位必须是空串，否则每条消息末尾都多出一截空白。
    it('无标签时占位为空，有标签时带图标位和标签', 0, () => {
      expect(viewsReserve('')).assertEqual('');
      const r: string = viewsReserve('5.2K');
      expect(r.endsWith('5.2K')).assertTrue();
      expect(r.length > '5.2K'.length).assertTrue();
    });

    it('非法输入被忽略', 0, () => {
      publishViewCount(0, 5, 100);
      publishViewCount(-100908, 0, 100);
      publishViewCount(-100908, 5, 0);
      expect(viewCountLabelFor(0, 5)).assertEqual('');
      expect(viewCountLabelFor(-100908, 0)).assertEqual('');
      expect(viewCountLabelFor(-100908, 5)).assertEqual('');
    });
  });

  // ── 「只有浏览数变了」时 store 不再克隆整行 ──────────────────────────
  describe('InteractionDelta', () => {
    it('评论与反应都没变 = 未变化', 0, () => {
      expect(interactionChanged(3, [1, 2], [rx('👍', 5)], 3, [1, 2], [rx('👍', 5)])).assertFalse();
      expect(interactionChanged(0, [], [], 0, [], [])).assertFalse();
    });

    it('评论数或评论人变化都算变化', 0, () => {
      expect(interactionChanged(3, [1], [], 4, [1], [])).assertTrue();
      expect(interactionChanged(3, [1], [], 3, [2], [])).assertTrue();
      expect(interactionChanged(3, [1], [], 3, [1, 2], [])).assertTrue();
    });

    it('反应的数量、选中态、种类、个数变化都算变化', 0, () => {
      expect(interactionChanged(0, [], [rx('👍', 5)], 0, [], [rx('👍', 6)])).assertTrue();
      expect(interactionChanged(0, [], [rx('👍', 5)], 0, [], [rx('👍', 5, true)])).assertTrue();
      expect(interactionChanged(0, [], [rx('👍', 5)], 0, [], [rx('❤', 5)])).assertTrue();
      expect(interactionChanged(0, [], [rx('👍', 5)], 0, [], [rx('👍', 5), rx('❤', 1)])).assertTrue();
    });

    // 推送里的自定义表情位图路径总是 ''（还没解析），行里的已经解析好了。
    // 拿路径比会让每次浏览数推送都判成"变了"，又回到整行克隆。
    it('自定义表情的本地路径不参与比较', 0, () => {
      const resolved: ReactionInfo = {
        emoji: '', count: 2, isChosen: false, customEmojiId: '42', customEmojiPath: '/a/b.png'
      };
      const pushed: ReactionInfo = {
        emoji: '', count: 2, isChosen: false, customEmojiId: '42', customEmojiPath: ''
      };
      expect(interactionChanged(0, [], [resolved], 0, [], [pushed])).assertFalse();
    });
  });
}
