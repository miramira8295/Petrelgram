import { describe, expect, it } from '@ohos/hypium';
import {
  MEMBER_ROLE_ADMIN, MEMBER_ROLE_CREATOR, MEMBER_ROLE_NONE
} from '../main/ets/util/memberRole';
import {
  MemberMenuOptions, ViewerAdminRights, memberMenuOptions, memberMenuSignature
} from '../main/ets/util/memberMenu';

function viewer(
  isCreator: boolean, promote: boolean, restrict: boolean, del: boolean,
  tags: boolean = false
): ViewerAdminRights {
  return {
    isCreator, canPromoteMembers: promote, canRestrictMembers: restrict,
    canDeleteMessages: del, canManageTags: tags
  };
}

const CREATOR: ViewerAdminRights = viewer(true, false, false, false);
const NOBODY: ViewerAdminRights = viewer(false, false, false, false);

export default function memberMenuTest() {
  describe('memberMenu', () => {
    it('群主对普通成员什么都能做', 0, () => {
      const o: MemberMenuOptions = memberMenuOptions(CREATOR, MEMBER_ROLE_NONE, false, false);
      expect(o.showPromote).assertTrue();
      expect(o.showRestrict).assertTrue();
      expect(o.showBan).assertTrue();
      expect(o.showRemove).assertTrue();
      expect(o.showDeleteMessages).assertTrue();
      expect(o.anyVisible).assertTrue();
    });

    it('普通成员看不到任何入口', 0, () => {
      const o = memberMenuOptions(NOBODY, MEMBER_ROLE_NONE, false, false);
      expect(o.anyVisible).assertFalse();
    });

    it('编辑标签跟 can_manage_tags 走，频道不给', 0, () => {
      const tagger: ViewerAdminRights = viewer(false, false, false, false, true);
      expect(memberMenuOptions(tagger, MEMBER_ROLE_NONE, false, false).showEditTitle).assertTrue();
      expect(memberMenuOptions(tagger, MEMBER_ROLE_ADMIN, false, false).showEditTitle).assertTrue();
      expect(memberMenuOptions(tagger, MEMBER_ROLE_NONE, false, true).showEditTitle).assertFalse();
      expect(memberMenuOptions(NOBODY, MEMBER_ROLE_NONE, false, false).showEditTitle).assertFalse();
    });

    it('对自己和对群主都不给入口', 0, () => {
      expect(memberMenuOptions(CREATOR, MEMBER_ROLE_NONE, true, false).anyVisible).assertFalse();
      expect(memberMenuOptions(CREATOR, MEMBER_ROLE_CREATOR, false, false).anyVisible).assertFalse();
    });

    it('逐项按权限出条目，不是有一项就全给', 0, () => {
      // 只会封禁的管理员：能限制/封禁/踢，但不该看到提权和删消息。
      const o = memberMenuOptions(viewer(false, false, true, false), MEMBER_ROLE_NONE, false, false);
      expect(o.showRestrict).assertTrue();
      expect(o.showBan).assertTrue();
      expect(o.showRemove).assertTrue();
      expect(o.showPromote).assertFalse();
      expect(o.showDeleteMessages).assertFalse();
      // 只会提权的管理员反过来。
      const p = memberMenuOptions(viewer(false, true, false, false), MEMBER_ROLE_NONE, false, false);
      expect(p.showPromote).assertTrue();
      expect(p.showBan).assertFalse();
    });

    it('对方已是管理员时提权入口变成编辑', 0, () => {
      expect(memberMenuOptions(CREATOR, MEMBER_ROLE_ADMIN, false, false).promoteIsEdit).assertTrue();
      expect(memberMenuOptions(CREATOR, MEMBER_ROLE_NONE, false, false).promoteIsEdit).assertFalse();
    });

    it('频道里没有「限制」，但封禁和移出还在', 0, () => {
      const o = memberMenuOptions(CREATOR, MEMBER_ROLE_NONE, false, true);
      expect(o.showRestrict).assertFalse();
      expect(o.showBan).assertTrue();
      expect(o.anyVisible).assertTrue();
    });

    it('菜单形态不同则签名不同（列表 key 靠它重建行）', 0, () => {
      const a = memberMenuSignature(memberMenuOptions(CREATOR, MEMBER_ROLE_NONE, false, false));
      const b = memberMenuSignature(memberMenuOptions(NOBODY, MEMBER_ROLE_NONE, false, false));
      expect(a === b).assertFalse();
      const c = memberMenuSignature(memberMenuOptions(CREATOR, MEMBER_ROLE_ADMIN, false, false));
      expect(a === c).assertFalse();
    });
  });
}
