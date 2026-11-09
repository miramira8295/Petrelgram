import { TdObject } from '../tdkit/TdTypes';

// 成员在群/频道里的身份。列表右侧那枚标签就是它。
//
// 只区分三种：创建者、管理员、普通成员。受限和被封禁的成员不会出现在成员
// 列表里（TDLib 的 supergroupMembersFilterRecent 不返回他们），所以不给它们
// 留分支——真需要时另开一个筛选。

export const MEMBER_ROLE_NONE: string = '';
export const MEMBER_ROLE_CREATOR: string = 'creator';
export const MEMBER_ROLE_ADMIN: string = 'admin';

export interface MemberRole {
  kind: string;
  // 自定义头衔。群主可以把"创建者"改成任意字样（TDLib 的 custom_title），
  // 有就显示它——官方端也是这么做的，不显示反而对不上。
  title: string;
}

export function memberRoleOf(status: TdObject | undefined): MemberRole {
  if (status === undefined) {
    return { kind: MEMBER_ROLE_NONE, title: '' };
  }
  const type: string = (status['@type'] as string | undefined) ?? '';
  const custom: string = ((status['custom_title'] as string | undefined) ?? '').trim();
  if (type === 'chatMemberStatusCreator') {
    return { kind: MEMBER_ROLE_CREATOR, title: custom };
  }
  if (type === 'chatMemberStatusAdministrator') {
    return { kind: MEMBER_ROLE_ADMIN, title: custom };
  }
  return { kind: MEMBER_ROLE_NONE, title: '' };
}

// 排序权重：创建者在最前，管理员次之，其余保持原顺序。
export function memberRoleRank(kind: string): number {
  if (kind === MEMBER_ROLE_CREATOR) {
    return 0;
  }
  return kind === MEMBER_ROLE_ADMIN ? 1 : 2;
}
