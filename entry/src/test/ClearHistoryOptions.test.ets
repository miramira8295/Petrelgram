import { describe, it, expect } from '@ohos/hypium';
import {
  ClearHistoryOption, canClearHistory, clearHistoryOptions, deleteChatRevoke
} from '../main/ets/store/ClearHistoryOptions';

// TDLib 的 deleteChatHistory 由 chat 上的两个能力位把关：
//   revoke=false 需要 can_be_deleted_only_for_self
//   revoke=true  需要 can_be_deleted_for_all_users
// 这里钉住四种组合。曾经的实现对任何会话都硬给 revoke=false，超级群/频道
// （两位皆假）因此报 "Can't delete history of <id> only for self"。

function keys(options: ClearHistoryOption[]): string[] {
  return options.map((o: ClearHistoryOption): string => o.labelKey);
}

function revokes(options: ClearHistoryOption[]): boolean[] {
  return options.map((o: ClearHistoryOption): boolean => o.revoke);
}

export default function clearHistoryOptionsTest() {
  describe('ClearHistoryOptions', () => {
    // 组合 1：只能为自己清（普通私聊里 revoke_pm_inbox 关掉时、基础群非创建者）。
    it('only_for_self_offers_single_non_revoking_option', 0, () => {
      const options = clearHistoryOptions(true, false, 'basicGroup');
      expect(options.length).assertEqual(1);
      expect(keys(options)[0]).assertEqual('clear_all');
      expect(revokes(options)[0]).assertEqual(false);
    });

    // 组合 2：只能为所有人清。活跃密聊就是这种（TDLib: "active secret chats
    // can be deleted only for both users"），群主的私有超级群同理。
    it('only_for_all_users_offers_single_revoking_option', 0, () => {
      const secret = clearHistoryOptions(false, true, 'secret');
      expect(secret.length).assertEqual(1);
      expect(keys(secret)[0]).assertEqual('cl_clear_for_both');
      expect(revokes(secret)[0]).assertEqual(true);

      const group = clearHistoryOptions(false, true, 'supergroup');
      expect(keys(group)[0]).assertEqual('cl_clear_for_everyone');
      expect(revokes(group)[0]).assertEqual(true);
    });

    // 组合 3：两种都行 —— 普通私聊。顺序固定：先"只为自己"，后"为对方/所有人"。
    it('both_offers_two_options_least_destructive_first', 0, () => {
      const options = clearHistoryOptions(true, true, 'private');
      expect(options.length).assertEqual(2);
      expect(keys(options)[0]).assertEqual('clear_all');
      expect(keys(options)[1]).assertEqual('cl_clear_for_both');
      expect(revokes(options)[0]).assertEqual(false);
      expect(revokes(options)[1]).assertEqual(true);
    });

    // 组合 4：都不行 —— 公开超级群 / 广播频道 / 话题群的非创建者。
    // 空数组是"连菜单项都别出现"的信号。
    it('neither_offers_nothing', 0, () => {
      expect(clearHistoryOptions(false, false, 'supergroup').length).assertEqual(0);
      expect(clearHistoryOptions(false, false, 'channel').length).assertEqual(0);
    });

    it('can_clear_matches_option_availability', 0, () => {
      expect(canClearHistory(true, false)).assertEqual(true);
      expect(canClearHistory(false, true)).assertEqual(true);
      expect(canClearHistory(true, true)).assertEqual(true);
      expect(canClearHistory(false, false)).assertEqual(false);
    });

    // 「删除聊天」只在能为自己删不掉时才升级成 revoke=true，避免把私聊的
    // 历史顺手给对方也删了。
    it('delete_chat_revoke_only_when_self_delete_impossible', 0, () => {
      expect(deleteChatRevoke(true, false)).assertEqual(false);
      expect(deleteChatRevoke(true, true)).assertEqual(false);
      expect(deleteChatRevoke(false, true)).assertEqual(true);
      expect(deleteChatRevoke(false, false)).assertEqual(false);
    });
  });
}
