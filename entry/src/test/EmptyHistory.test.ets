import { describe, expect, it } from '@ohos/hypium';
import {
  emptyHistoryHint, emptyHistoryIcon, emptyHistoryTitle
} from '../main/ets/util/emptyHistory';

// 宿主单测里没装文案源，str() 原样返回 key——断言落在"选了哪条文案"上。
export default function emptyHistoryTest() {
  describe('emptyHistory', () => {
    it('单聊 / 群 / 频道的默认文案各不相同', 0, () => {
      expect(emptyHistoryTitle(0, 'writable', false, false)).assertEqual('cp_no_messages');
      expect(emptyHistoryTitle(0, 'writable', false, true)).assertEqual('cp_group_empty');
      expect(emptyHistoryTitle(0, 'writable', true, false)).assertEqual('cp_channel_empty');
      expect(emptyHistoryHint(0, 'writable', false, false)).assertEqual('cp_send_to_start');
      expect(emptyHistoryHint(0, 'writable', false, true)).assertEqual('cp_send_first_group');
      expect(emptyHistoryHint(0, 'writable', true, false)).assertEqual('cp_posts_appear_here');
    });

    it('话题（评论区）在标题和副标题里都排最高', 0, () => {
      expect(emptyHistoryTitle(7, 'blocked', true, false)).assertEqual('cp_no_replies');
      expect(emptyHistoryHint(7, 'joinable', true, false)).assertEqual('cp_no_replies_sub');
      // 能写才提示"发第一条回复"。
      expect(emptyHistoryHint(7, 'writable', false, true)).assertEqual('cp_send_first_reply');
    });

    it('被挡：标题排第二，副标题却排在待加入之后——两边不对称', 0, () => {
      // 标题里 blocked 盖过频道/群。
      expect(emptyHistoryTitle(0, 'blocked', true, false)).assertEqual('cp_cannot_show');
      // 副标题里 joinable 先判，所以 joinable 会盖过 blocked——两者互斥，
      // 这条钉的是"顺序如此"，改动时不至于以为可以随便调。
      expect(emptyHistoryHint(0, 'joinable', true, false)).assertEqual('cp_join_to_chat');
      expect(emptyHistoryHint(0, 'blocked', true, false)).assertEqual('cp_maybe_removed');
      expect(emptyHistoryHint(0, 'checking', true, false)).assertEqual('cp_confirming_membership');
    });

    it('图标：被挡 > 待加入 > 话题 > 默认', 0, () => {
      expect(emptyHistoryIcon(7, 'blocked')).assertEqual('sys.symbol.lock_fill');
      expect(emptyHistoryIcon(7, 'joinable')).assertEqual('sys.symbol.person_badge_plus');
      expect(emptyHistoryIcon(7, 'writable')).assertEqual('sys.symbol.arrowshape_turn_up_left');
      expect(emptyHistoryIcon(0, 'writable')).assertEqual('sys.symbol.message');
      // 图标把话题排在身份之后，标题却把话题排在最前——这处不对称是有意的：
      // 被挡时锁比回复箭头更该出现。
      expect(emptyHistoryTitle(7, 'blocked', false, false)).assertEqual('cp_no_replies');
    });
  });
}
