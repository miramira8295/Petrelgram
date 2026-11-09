import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  AdminRights, RIGHT_CHANGE_INFO, RIGHT_POST_STORIES, RIGHT_PROMOTE_MEMBERS,
  STORY_RIGHT_KEYS, adminRightValue, adminRightsFromTd, adminRightsOfStatus,
  adminRightsToTd, allAdminRights, anyAdminRight, defaultAdminRights,
  limitAdminRights, storyRightsOnCount, withAdminRight
} from '../main/ets/util/adminRights';

function rightsObject(): TdObject {
  const r: TdObject = { '@type': 'chatAdministratorRights' };
  r['can_manage_chat'] = true;
  r['can_restrict_members'] = true;
  r['can_manage_topics'] = true;
  r['can_promote_members'] = false;
  return r;
}

export default function adminRightsTest() {
  describe('adminRights', () => {
    it('读出来再写回去，界面上不展示的字段也原样保留', 0, () => {
      const parsed: AdminRights = adminRightsFromTd(rightsObject());
      expect(parsed.manageTopics).assertTrue();
      const back = adminRightsToTd(parsed);
      // manage_topics 面板上没有开关，但绝不能在保存时被抹掉。
      expect(back['can_manage_topics'] as boolean).assertTrue();
      expect(back['can_promote_members'] as boolean).assertFalse();
    });

    it('勾了任意一项就带上 can_manage_chat', 0, () => {
      const only = withAdminRight(allAdminRights(false), RIGHT_CHANGE_INFO, true);
      expect(adminRightsToTd(only)['can_manage_chat'] as boolean).assertTrue();
      expect(adminRightsToTd(allAdminRights(false))['can_manage_chat'] as boolean).assertFalse();
    });

    it('群主没有 rights 字段，但什么都能做', 0, () => {
      const status: TdObject = { '@type': 'chatMemberStatusCreator' };
      expect(adminRightsOfStatus(status).promoteMembers).assertTrue();
      const member: TdObject = { '@type': 'chatMemberStatusMember' };
      expect(anyAdminRight(adminRightsOfStatus(member))).assertFalse();
      expect(adminRightsOfStatus(undefined).manageChat).assertFalse();
    });

    it('管理员的 rights 从 status 里取', 0, () => {
      const status: TdObject = { '@type': 'chatMemberStatusAdministrator' };
      status['rights'] = rightsObject();
      expect(adminRightsOfStatus(status).restrictMembers).assertTrue();
    });

    it('授不出去自己没有的权限', 0, () => {
      const desired = allAdminRights(true);
      const mine = withAdminRight(allAdminRights(false), RIGHT_CHANGE_INFO, true);
      const granted = limitAdminRights(desired, mine);
      expect(adminRightValue(granted, RIGHT_CHANGE_INFO)).assertTrue();
      expect(adminRightValue(granted, RIGHT_PROMOTE_MEMBERS)).assertFalse();
      // 群主是全 true，与任何集合相交都还是原集合。
      expect(limitAdminRights(desired, allAdminRights(true)).promoteMembers).assertTrue();
    });

    it('动态子组按开着的项数计数', 0, () => {
      expect(storyRightsOnCount(allAdminRights(true))).assertEqual(STORY_RIGHT_KEYS.length);
      expect(storyRightsOnCount(allAdminRights(false))).assertEqual(0);
      const one = withAdminRight(allAdminRights(false), RIGHT_POST_STORIES, true);
      expect(storyRightsOnCount(one)).assertEqual(1);
    });

    it('withAdminRight 不改原对象', 0, () => {
      const base = defaultAdminRights();
      const next = withAdminRight(base, RIGHT_PROMOTE_MEMBERS, true);
      expect(base.promoteMembers).assertFalse();
      expect(next.promoteMembers).assertTrue();
    });
  });
}
