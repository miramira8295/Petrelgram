import { promptAction, UIContext } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { blockPrivateChatSender } from '../../store/ChatActions';
import { ReportTarget, runReportFlow } from '../../util/reportFlow';
import { PM_BLOCK, PM_DELETE_CONTACT, PM_REPORT, PM_UNBLOCK } from '../../util/profileMenu';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { logE } from '../../util/log';
import { reportFlowUiFor } from '../common/ReportPrompts';
import { openChecklistDialog } from '../common/ChecklistDialog';

// 私聊资料页右上角「⋯」菜单的四个动作（#219-2）。哪几项出现由 util/profileMenu
// 决定；这里只负责菜单、确认框、请求和提示。ProfilePage 只留按钮上的一处接线。
//
// 屏蔽/举报的交互与会话操作条（ChatActionBarActions）同一套文案和确认框。

export interface ProfileMenuContext {
  userId: number;
  name: string;
  ui: UIContext;
}

const DESTRUCTIVE_RED: string = '#E64646';

function send(req: TdRequest): Promise<TdObject> {
  return getTdClient().send(req, 15000);
}

function toast(message: string): void {
  promptAction.showToast({ message, duration: 1600 });
}

export function profileMenuLabel(id: string): string {
  if (id === PM_BLOCK) {
    return str('ab_block');
  }
  if (id === PM_UNBLOCK) {
    return str('bu_unblock_title');
  }
  if (id === PM_REPORT) {
    return str('mb_report');
  }
  return str('ct_delete');
}

export function runProfileMenuAction(id: string, ctx: ProfileMenuContext): void {
  if (ctx.userId <= 0) {
    return;
  }
  if (id === PM_BLOCK) {
    confirmBlock(ctx);
  } else if (id === PM_UNBLOCK) {
    confirmUnblock(ctx);
  } else if (id === PM_REPORT) {
    report(ctx);
  } else if (id === PM_DELETE_CONTACT) {
    confirmDeleteContact(ctx);
  }
}

// 私聊的 chat_id 就是对方的 user id，blockPrivateChatSender 按此构造发送者——
// 没聊过也成立，不需要先建会话。
function confirmBlock(ctx: ProfileMenuContext): void {
  openChecklistDialog(ctx.ui, str('ab_block_title', ctx.name), str('ab_block_hint'), [],
    str('ab_block'), true, (): void => {
      blockPrivateChatSender(ctx.userId).then((): void => {
        toast(str('ab_blocked'));
      }).catch((e: TdError): void => {
        logE(`ProfileMoreMenu.block failed: ${e.message}`);
        toast(str('bu_block_failed'));
      });
    });
}

// 不带 block_list = 从所有屏蔽名单里移出（与 BlockedUsersPage 同一个请求）。
function confirmUnblock(ctx: ProfileMenuContext): void {
  promptAction.showDialog({
    title: str('bu_unblock_title'),
    message: str('bu_unblock_confirm', ctx.name),
    buttons: [
      { text: str('cancel'), color: COLOR_TEXT_SECONDARY as string },
      { text: str('bu_unblock'), color: COLOR_PRIMARY as string }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index !== 1) {
      return;
    }
    const req: TdRequest = { '@type': 'setMessageSenderBlockList' };
    req['sender_id'] = { '@type': 'messageSenderUser', 'user_id': ctx.userId } as TdObject;
    send(req).catch((e: TdError): void => {
      logE(`ProfileMoreMenu.unblock failed: ${e.message}`);
      toast(str('action_failed_retry'));
    });
  }).catch((): void => {});
}

// 举报只有 reportChat 一个入口，要的是会话 id。没聊过的人私聊会话可能还不存在，
// 先 createPrivateChat（force=false，不会凭空给对方造出会话列表条目）。
function report(ctx: ProfileMenuContext): void {
  const req: TdRequest = { '@type': 'createPrivateChat' };
  req['user_id'] = ctx.userId;
  req['force'] = false;
  send(req).then((chat: TdObject): void => {
    const chatId: number = (chat['id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      toast(str('action_failed_retry'));
      return;
    }
    runReportFlow(send, { chatId, messageIds: [] } as ReportTarget, reportFlowUiFor(ctx.ui));
  }).catch((e: TdError): void => {
    logE(`ProfileMoreMenu.report createPrivateChat failed: ${e.message}`);
    toast(str('action_failed_retry'));
  });
}

// 与联系人页长按删除同一套文案；聊天记录不删（确认框里写明了）。
function confirmDeleteContact(ctx: ProfileMenuContext): void {
  promptAction.showDialog({
    title: str('ct_delete'),
    message: str('ct_delete_confirm', ctx.name),
    buttons: [
      { text: str('cancel'), color: COLOR_TEXT_SECONDARY as string },
      { text: str('delete'), color: DESTRUCTIVE_RED }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index !== 1) {
      return;
    }
    const req: TdRequest = { '@type': 'removeContacts' };
    req['user_ids'] = [ctx.userId];
    send(req).then((): void => {
      toast(str('ct_deleted', ctx.name));
    }).catch((e: TdError): void => {
      logE(`ProfileMoreMenu.removeContacts failed: ${e.message}`);
      toast(str('ct_delete_failed'));
    });
  }).catch((): void => {});
}

// 弹出菜单。屏蔽和删除联系人用红色，与会话操作条、话题菜单的破坏性项一致。
export function showProfileMoreMenu(items: string[], ctx: ProfileMenuContext): void {
  if (items.length === 0) {
    return;
  }
  const buttons: promptAction.Button[] = items.map((id: string): promptAction.Button => ({
    text: profileMenuLabel(id),
    color: id === PM_BLOCK || id === PM_DELETE_CONTACT ? DESTRUCTIVE_RED : '#007AFF'
  } as promptAction.Button));
  // 菜单最多三项（profileMenuItems），在 showActionMenu 的 1–6 个上限之内。
  promptAction.showActionMenu({
    title: ctx.name,
    buttons: buttons as [promptAction.Button, promptAction.Button?, promptAction.Button?,
      promptAction.Button?, promptAction.Button?, promptAction.Button?]
  }).then(
    (result: promptAction.ActionMenuSuccessResponse): void => {
      const id: string | undefined = items[result.index];
      if (id !== undefined) {
        runProfileMenuAction(id, ctx);
      }
    }).catch((): void => {});
}
