import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  MEMBER_ROLE_ADMIN, MEMBER_ROLE_CREATOR, MEMBER_ROLE_NONE,
  MemberRole, memberRoleOf, memberRoleRank
} from '../main/ets/util/memberRole';

function status(type: string, custom: string): TdObject {
  const o: TdObject = { '@type': type };
  if (custom !== '') {
    o['custom_title'] = custom;
  }
  return o;
}

export default function memberRoleTest() {
  describe('memberRole', () => {
    it('创建者和管理员各自成一档', 0, () => {
      expect(memberRoleOf(status('chatMemberStatusCreator', '')).kind).assertEqual(MEMBER_ROLE_CREATOR);
      expect(memberRoleOf(status('chatMemberStatusAdministrator', '')).kind).assertEqual(MEMBER_ROLE_ADMIN);
    });

    it('普通成员没有标签', 0, () => {
      expect(memberRoleOf(status('chatMemberStatusMember', '')).kind).assertEqual(MEMBER_ROLE_NONE);
    });

    it('拿不到 status 时按普通成员处理', 0, () => {
      expect(memberRoleOf(undefined).kind).assertEqual(MEMBER_ROLE_NONE);
    });

    it('自定义头衔原样带出，两边空白去掉', 0, () => {
      const r: MemberRole = memberRoleOf(status('chatMemberStatusAdministrator', '  打杂的  '));
      expect(r.title).assertEqual('打杂的');
    });

    it('普通成员即使带了头衔也不显示', 0, () => {
      expect(memberRoleOf(status('chatMemberStatusMember', '路人')).title).assertEqual('');
    });

    it('排序权重：创建者 < 管理员 < 其余', 0, () => {
      expect(memberRoleRank(MEMBER_ROLE_CREATOR) < memberRoleRank(MEMBER_ROLE_ADMIN)).assertTrue();
      expect(memberRoleRank(MEMBER_ROLE_ADMIN) < memberRoleRank(MEMBER_ROLE_NONE)).assertTrue();
    });
  });
}
