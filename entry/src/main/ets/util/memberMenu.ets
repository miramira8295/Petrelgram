import { MEMBER_ROLE_ADMIN, MEMBER_ROLE_CREATOR } from './memberRole';

// 菜单项标识。用常量而不是下标，免得菜单顺序一变行为就跟着错位。
export const MEMBER_ACTION_PROMOTE: string = 'promote';
export const MEMBER_ACTION_TITLE: string = 'editTitle';
export const MEMBER_ACTION_RESTRICT: string = 'restrict';
export const MEMBER_ACTION_BAN: string = 'ban';
export const MEMBER_ACTION_REMOVE: string = 'remove';
export const MEMBER_ACTION_DELETE_MESSAGES: string = 'deleteMessages';
// 单独改头衔。官方 PC 端把它做成菜单里独立的一项，而不是埋进管理员权限面板
// ——改个称呼是高频小操作，不该每次都进那一大页开关。

// 长按成员时那份菜单该出哪几项。
//
// 逐项按权限判定，不用"有任意一项管理权限"这种粗粒度开关：只会封禁的管理员
// 不该看到提权，只会提权的不该看到踢人。点了才失败对管理员是最糟的体验。

export interface ViewerAdminRights {
  isCreator: boolean;
  canPromoteMembers: boolean;
  canRestrictMembers: boolean;
  canDeleteMessages: boolean;
  // 设置群成员标签（chatMemberTag）的权限，TDLib 字段 can_manage_tags。
  canManageTags: boolean;
}

export interface MemberMenuOptions {
  showPromote: boolean;
  // 对方已经是管理员时，同一个入口的文案是「编辑管理员权限」。
  promoteIsEdit: boolean;
  // 「编辑标签」——**群成员标签**（chatMemberTag），不是管理员头衔。任何
  // 成员都能被打标、全员可见，需要 can_manage_tags 权限。频道没有这功能。
  //
  // 曾经这一项接的是管理员头衔（custom_title），还试过给普通成员零权限/最小
  // 权限提权来挂头衔——服务端要么静默丢头衔要么真把人提成管理员，全是弯路；
  // 后来发现 Telegram 新出的成员标签才是正主。
  showEditTitle: boolean;
  showRestrict: boolean;
  showBan: boolean;
  showRemove: boolean;
  showDeleteMessages: boolean;
  anyVisible: boolean;
}

export function noMemberMenu(): MemberMenuOptions {
  return {
    showPromote: false, promoteIsEdit: false, showEditTitle: false, showRestrict: false,
    showBan: false, showRemove: false, showDeleteMessages: false,
    anyVisible: false
  };
}

export function memberMenuOptions(
  viewer: ViewerAdminRights, targetRole: string, isSelf: boolean, isChannel: boolean
): MemberMenuOptions {
  // 对自己动手没有意义（退群走别的入口），对群主动手谁也没这个权限。
  if (isSelf || targetRole === MEMBER_ROLE_CREATOR) {
    return noMemberMenu();
  }
  const isAdmin = targetRole === MEMBER_ROLE_ADMIN;
  const canPromote = viewer.isCreator || viewer.canPromoteMembers;
  const canRestrict = viewer.isCreator || viewer.canRestrictMembers;
  const canDelete = viewer.isCreator || viewer.canDeleteMessages;
  // 频道没有"受限成员"这个状态：chatMemberStatusRestricted 只对超级群有效，
  // 对频道调用会被 TDLib 拒。踢人和封禁在频道里是有的，所以只藏这一项。
  const showRestrict = canRestrict && !isChannel;
  return {
    showPromote: canPromote,
    promoteIsEdit: isAdmin,
    showEditTitle: (viewer.isCreator || viewer.canManageTags) && !isChannel,
    showRestrict,
    showBan: canRestrict,
    showRemove: canRestrict,
    showDeleteMessages: canDelete,
    anyVisible: canPromote || showRestrict || canRestrict || canDelete ||
      ((viewer.isCreator || viewer.canManageTags) && !isChannel)
  };
}

// ForEach 的 key 里要带上菜单形态：权限是异步读回来的，形态变了而 key 没变，
// 复用的行会一直挂着旧菜单。
export function memberMenuSignature(o: MemberMenuOptions): string {
  const bit = (v: boolean): string => v ? '1' : '0';
  return `${bit(o.showPromote)}${bit(o.promoteIsEdit)}${bit(o.showEditTitle)}` +
    `${bit(o.showRestrict)}` +
    `${bit(o.showBan)}${bit(o.showRemove)}${bit(o.showDeleteMessages)}`;
}
