import { describe, it, expect } from '@ohos/hypium';
import {
  actionBarButtons, actionBarKindOf, ActionBarButton, ACTION_REPORT, ACTION_BLOCK, ACTION_ADD_CONTACT,
  ACTION_SHARE_PHONE, ACTION_UNARCHIVE
} from '../main/ets/util/chatActionBar';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// 会话操作条（issue #201 第 8 条）：TDLib 的 chat.action_bar 七种形态 → 按钮列表。
function bar(type: string, canUnarchive: boolean = false): TdObject {
  const b: TdObject = { '@type': type };
  b['can_unarchive'] = canUnarchive;
  return b;
}
function ids(list: ActionBarButton[]): string {
  return list.map((b: ActionBarButton): string => b.id).join(',');
}

export default function chatActionBarTest(): void {
  describe('chatActionBar', (): void => {
    it('kindOf：取 @type，缺省空串', 0, (): void => {
      expect(actionBarKindOf(bar('chatActionBarReportSpam'))).assertEqual('chatActionBarReportSpam');
      expect(actionBarKindOf(undefined)).assertEqual('');
    });
    it('陌生人私聊：举报 / 添加联系人 / 屏蔽', 0, (): void => {
      expect(ids(actionBarButtons('chatActionBarReportAddBlock', false)))
        .assertEqual([ACTION_REPORT, ACTION_ADD_CONTACT, ACTION_BLOCK].join(','));
    });
    it('群/频道垃圾信息：只有举报；加联系人 / 分享手机号各自一个按钮', 0, (): void => {
      expect(ids(actionBarButtons('chatActionBarReportSpam', false))).assertEqual(ACTION_REPORT);
      expect(ids(actionBarButtons('chatActionBarAddContact', false))).assertEqual(ACTION_ADD_CONTACT);
      expect(ids(actionBarButtons('chatActionBarSharePhoneNumber', false))).assertEqual(ACTION_SHARE_PHONE);
    });
    it('can_unarchive 时多一个「移出归档」按钮，排在最前', 0, (): void => {
      const list: ActionBarButton[] = actionBarButtons('chatActionBarReportSpam', true);
      expect(list[0].id).assertEqual(ACTION_UNARCHIVE);
      expect(list.length).assertEqual(2);
    });
    it('屏蔽与举报是危险色，其余不是', 0, (): void => {
      const list: ActionBarButton[] = actionBarButtons('chatActionBarReportAddBlock', false);
      expect(list.find((b: ActionBarButton): boolean => b.id === ACTION_BLOCK)!.destructive).assertTrue();
      expect(list.find((b: ActionBarButton): boolean => b.id === ACTION_ADD_CONTACT)!.destructive).assertFalse();
    });
    it('这轮不做的形态（邀请成员 / 位置不符 / 入群申请 / 未知 / 空）不出按钮', 0, (): void => {
      expect(actionBarButtons('chatActionBarInviteMembers', false).length).assertEqual(0);
      expect(actionBarButtons('chatActionBarReportUnrelatedLocation', false).length).assertEqual(0);
      expect(actionBarButtons('chatActionBarJoinRequest', false).length).assertEqual(0);
      expect(actionBarButtons('', true).length).assertEqual(0);
    });
  });
}
