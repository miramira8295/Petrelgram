import { TdObject } from '../tdkit/TdTypes';

// 会话操作条（issue #201 第 8 条）——Telegram 里陌生人私聊顶上那条
// 「举报 / 添加联系人 / 屏蔽」。该不该出、出哪种，TDLib 已经在 chat.action_bar
// 里算好了（变化时推 updateChatActionBar），这里只把七种形态映射成按钮。
// 邀请成员、位置不符、入群申请三种这轮不出按钮。

export const ACTION_REPORT: string = 'report';
export const ACTION_BLOCK: string = 'block';
export const ACTION_ADD_CONTACT: string = 'addContact';
export const ACTION_SHARE_PHONE: string = 'sharePhone';
export const ACTION_UNARCHIVE: string = 'unarchive';

export interface ActionBarButton {
  id: string;
  labelKey: string;      // 字符串资源键
  destructive: boolean;  // 红色
}

export function actionBarKindOf(bar: TdObject | undefined): string {
  return bar !== undefined ? ((bar['@type'] as string | undefined) ?? '') : '';
}

export function actionBarCanUnarchiveOf(bar: TdObject | undefined): boolean {
  return bar !== undefined ? ((bar['can_unarchive'] as boolean | undefined) ?? false) : false;
}

function button(id: string, labelKey: string, destructive: boolean): ActionBarButton {
  return { id, labelKey, destructive };
}

export function actionBarButtons(kind: string, canUnarchive: boolean): ActionBarButton[] {
  const out: ActionBarButton[] = [];
  let body: ActionBarButton[] = [];
  if (kind === 'chatActionBarReportAddBlock') {
    body = [
      button(ACTION_REPORT, 'ab_report_spam', true),
      button(ACTION_ADD_CONTACT, 'ct_add_contact', false),
      button(ACTION_BLOCK, 'ab_block', true)
    ];
  } else if (kind === 'chatActionBarReportSpam') {
    body = [button(ACTION_REPORT, 'ab_report_spam', true)];
  } else if (kind === 'chatActionBarAddContact') {
    body = [button(ACTION_ADD_CONTACT, 'ct_add_contact', false)];
  } else if (kind === 'chatActionBarSharePhoneNumber') {
    body = [button(ACTION_SHARE_PHONE, 'ab_share_phone', false)];
  }
  if (body.length === 0) {
    return out;
  }
  if (canUnarchive) {
    out.push(button(ACTION_UNARCHIVE, 'ab_unarchive', false));
  }
  return out.concat(body);
}
