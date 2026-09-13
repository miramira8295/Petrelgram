import { promptAction, UIContext } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  ACTION_ADD_CONTACT, ACTION_BLOCK, ACTION_REPORT, ACTION_SHARE_PHONE, ACTION_UNARCHIVE
} from '../../util/chatActionBar';
import { blockPrivateChatSender } from '../../store/ChatActions';
import { ReportTarget, runReportFlow } from '../../util/reportFlow';
import { reportFlowUiFor } from '../common/ReportPrompts';
import { openChecklistDialog, ChecklistOption } from '../common/ChecklistDialog';
import { navigateToProfile } from '../../util/profileNav';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 会话操作条的动作（issue #201 第 8 条）。ChatPage 只把按钮 id 转过来。
export interface ActionBarContext {
  chatId: number;
  // 私聊里对方的 user id（操作条只在私聊/群里出现；加联系人、分享手机号只对私聊有意义）。
  peerUserId: number;
  peerTitle: string;
  ui: UIContext;
  // 会话被删掉之后由页面退出自己（ChatPage.goBack）。
  onChatRemoved: () => void;
}

const OPTION_DELETE_CHAT: string = 'deleteChat';

function send(req: TdRequest): Promise<TdObject> {
  return getTdClient().send(req, 15000);
}

export function dismissActionBar(chatId: number): void {
  const req: TdRequest = { '@type': 'removeChatActionBar' };
  req['chat_id'] = chatId;
  send(req).catch((e: TdError): void => { logE(`removeChatActionBar failed: ${e.message}`); });
}

function unarchive(chatId: number): void {
  const req: TdRequest = { '@type': 'addChatToList' };
  req['chat_id'] = chatId;
  req['chat_list'] = { '@type': 'chatListMain' } as TdObject;
  send(req).catch((e: TdError): void => { logE(`addChatToList failed: ${e.message}`); });
}

function sharePhone(ctx: ActionBarContext): void {
  openChecklistDialog(ctx.ui, str('ab_share_title', ctx.peerTitle), '', [],
    str('ab_share_phone'), false, (): void => {
      const req: TdRequest = { '@type': 'sharePhoneNumber' };
      req['user_id'] = ctx.peerUserId;
      send(req).then((): void => {
        promptAction.showToast({ message: str('ab_shared'), duration: 1500 });
      }).catch((e: TdError): void => {
        logE(`sharePhoneNumber failed: ${e.message}`);
        promptAction.showToast({ message: str('cpp_report_failed'), duration: 1500 });
      });
    });
}

// 屏蔽：确认框带「同时删除对话」勾选（默认勾，Telegram 的默认行为）。
function block(ctx: ActionBarContext): void {
  const options: ChecklistOption[] = [
    { id: OPTION_DELETE_CHAT, label: str('ab_block_delete'), checked: true } as ChecklistOption
  ];
  openChecklistDialog(ctx.ui, str('ab_block_title', ctx.peerTitle), str('ab_block_hint'), options,
    str('ab_block'), true, (checked: string[]): void => {
      const alsoDelete: boolean = checked.indexOf(OPTION_DELETE_CHAT) >= 0;
      blockPrivateChatSender(ctx.chatId).then((): Promise<TdObject> => {
        if (!alsoDelete) {
          return Promise.resolve({ '@type': 'ok' } as TdObject);
        }
        const req: TdRequest = { '@type': 'deleteChatHistory' };
        req['chat_id'] = ctx.chatId;
        req['remove_from_chat_list'] = true;
        req['revoke'] = false;
        return send(req);
      }).then((): void => {
        promptAction.showToast({ message: str('ab_blocked'), duration: 1500 });
        if (alsoDelete) {
          ctx.onChatRemoved();
        }
      }).catch((e: TdError): void => {
        logE(`action bar block failed: ${e.message}`);
        promptAction.showToast({ message: str('cpp_report_failed'), duration: 1500 });
      });
    });
}

export function handleActionBar(id: string, ctx: ActionBarContext): void {
  if (id === ACTION_REPORT) {
    // 会话级举报，走和资料页一样的那棵树；服务端受理后自己撤操作条。
    runReportFlow(send, { chatId: ctx.chatId, messageIds: [] } as ReportTarget, reportFlowUiFor(ctx.ui));
    return;
  }
  if (id === ACTION_BLOCK) {
    block(ctx);
    return;
  }
  if (id === ACTION_ADD_CONTACT) {
    // 资料页上有完整的「添加联系人」流程（要填名字），直接跳过去。
    const params: Record<string, Object> = { 'userId': ctx.peerUserId };
    navigateToProfile(params);
    return;
  }
  if (id === ACTION_SHARE_PHONE) {
    sharePhone(ctx);
    return;
  }
  if (id === ACTION_UNARCHIVE) {
    unarchive(ctx.chatId);
  }
}
