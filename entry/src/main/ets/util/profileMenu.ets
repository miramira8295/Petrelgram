import { TdObject } from '../tdkit/TdTypes';

// 私聊资料页右上角「⋯」菜单里放什么（#219-2）。
//
// 那个按钮从初始提交起就是占位（回调是空函数），报告人点了没反应。只放已经有
// 完整实现的三项：屏蔽/解除屏蔽、举报、删除联系人。「开始私密聊天」「添加联系人」
// 在页面上已经是两行按钮，不重复；分享联系人/改备注还没写，不放进来当摆设。

export const PM_BLOCK: string = 'block';
export const PM_UNBLOCK: string = 'unblock';
export const PM_REPORT: string = 'report';
export const PM_DELETE_CONTACT: string = 'deleteContact';

export interface ProfileMenuState {
  isSelf: boolean;
  isBlocked: boolean;
  isContact: boolean;
}

// 返回空数组 = 不显示按钮（自己的资料页）。
export function profileMenuItems(state: ProfileMenuState): string[] {
  if (state.isSelf) {
    return [];
  }
  const items: string[] = [state.isBlocked ? PM_UNBLOCK : PM_BLOCK, PM_REPORT];
  if (state.isContact) {
    items.push(PM_DELETE_CONTACT);
  }
  return items;
}

// userFullInfo.block_list：null/缺省 = 没屏蔽；任何 blockList* = 在某个屏蔽名单里。
export function isBlockedFromFullInfo(full: TdObject): boolean {
  const list = full['block_list'] as TdObject | undefined | null;
  return list !== undefined && list !== null;
}
