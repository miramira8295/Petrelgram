import { describe, expect, it } from '@ohos/hypium';
import {
  PM_BLOCK, PM_DELETE_CONTACT, PM_REPORT, PM_UNBLOCK, isBlockedFromFullInfo, profileMenuItems
} from '../main/ets/util/profileMenu';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// 私聊资料页右上角「⋯」（#219-2）。原来回调是空函数，点了没反应。
export default function profileMenuTest() {
  describe('ProfileMenu', () => {
    it('陌生人：屏蔽 + 举报，没有删除联系人', 0, () => {
      const items = profileMenuItems({ isSelf: false, isBlocked: false, isContact: false });
      expect(items.join(',')).assertEqual([PM_BLOCK, PM_REPORT].join(','));
    });

    it('联系人：多一项删除联系人', 0, () => {
      const items = profileMenuItems({ isSelf: false, isBlocked: false, isContact: true });
      expect(items.join(',')).assertEqual([PM_BLOCK, PM_REPORT, PM_DELETE_CONTACT].join(','));
    });

    // 同一个位置按状态切换文字，不能同时出现两项。
    it('已屏蔽时换成解除屏蔽', 0, () => {
      const items = profileMenuItems({ isSelf: false, isBlocked: true, isContact: false });
      expect(items.indexOf(PM_UNBLOCK)).assertEqual(0);
      expect(items.indexOf(PM_BLOCK)).assertEqual(-1);
    });

    // 自己的资料页：屏蔽/举报/删除自己都没有意义，菜单为空（按钮随之隐藏）。
    it('自己的资料页没有菜单', 0, () => {
      expect(profileMenuItems({ isSelf: true, isBlocked: false, isContact: true }).length)
        .assertEqual(0);
    });

    // userFullInfo.block_list：null = 没屏蔽；blockListMain / blockListStories = 已屏蔽。
    // 「只屏蔽快拍」也算屏蔽了——菜单给「解除屏蔽」，否则用户看不出它在名单里。
    it('从 userFullInfo 读屏蔽状态', 0, () => {
      const blocked: TdObject = { 'block_list': { '@type': 'blockListMain' } as TdObject };
      const storiesOnly: TdObject = { 'block_list': { '@type': 'blockListStories' } as TdObject };
      const none: TdObject = JSON.parse('{"block_list":null}') as TdObject;
      const missing: TdObject = {};
      expect(isBlockedFromFullInfo(blocked)).assertTrue();
      expect(isBlockedFromFullInfo(storiesOnly)).assertTrue();
      expect(isBlockedFromFullInfo(none)).assertFalse();
      expect(isBlockedFromFullInfo(missing)).assertFalse();
    });
  });
}
