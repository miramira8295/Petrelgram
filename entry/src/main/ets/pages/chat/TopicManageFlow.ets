import { ComponentContent, promptAction, UIContext } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { ForumTopicRow } from '../../util/forumTopicModel';
import { forumTopicCreateRequest, forumTopicDeleteRequest } from '../../util/forumTopicRequests';
import { logE } from '../../util/log';
import { str } from '../../util/strings';
import { COLOR_ON_PRIMARY, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

// 详情页顶栏话题横条上的「新建话题」与长按删除（issue #206，Bot 私聊话题模式）。
// ChatPage 只接线：拿到结果后刷新横条、切话题。
//
// 输入框弹层走 ComponentContent + UIContext.openCustomDialog，与 ReportPrompts /
// DeleteMessagesDialog 同一条路（CustomDialogController 官方限定状态管理 V1）。
//
// 失败提示不用话题列表页那两条 ft_*_failed：那两条写着「需要管理话题权限」，是给论坛
// 超级群的；Bot 私聊里没有这回事，照搬会误导。

export interface CreatedTopic {
  threadId: number;
  name: string;
}

interface TopicNameDialogParams {
  onSubmit: (name: string) => void;
  onClose: () => void;
}

@Component
struct TopicNameDialog {
  onSubmit: (name: string) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State name: string = '';

  build() {
    Column({ space: 14 }) {
      Text($r('app.string.ft_new_topic'))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center).width('100%');
      TextInput({ text: $$this.name, placeholder: $r('app.string.ft_topic_name') })
        .fontSize(15).width('100%').height(44)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10)
        .defaultFocus(true)
        .onSubmit((): void => { this.submit(); });
      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(22).layoutWeight(1).height(44)
          .onClick((): void => { this.onClose(); });
        Button($r('app.string.create'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_PRIMARY)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22).layoutWeight(1).height(44)
          .enabled(this.name.trim() !== '')
          .onClick((): void => { this.submit(); });
      }
      .width('100%');
    }
    .width('86%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    // 实底不走材质：输入框压在消息上必须可读（同 ReportTextDialog）。
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18);
  }

  private submit(): void {
    const typed: string = this.name.trim();
    if (typed === '') {
      return;
    }
    this.onClose();
    this.onSubmit(typed);
  }
}

// ComponentContent 要 wrapBuilder 包过的全局 @Builder。
@Builder
function topicNameDialogLayer(p: TopicNameDialogParams) {
  TopicNameDialog({ onSubmit: p.onSubmit, onClose: p.onClose })
}

// resolve(null) = 用户取消（点取消或点遮罩）。
function askTopicName(ui: UIContext): Promise<string | null> {
  return new Promise<string | null>((resolve: (v: string | null) => void): void => {
    let content: ComponentContent<TopicNameDialogParams> | null = null;
    let submitted: string | null = null;
    const close = (): void => {
      const open: ComponentContent<TopicNameDialogParams> | null = content;
      if (open === null) {
        return;
      }
      ui.getPromptAction().closeCustomDialog(open)
        .catch((e: Object): void => { logE(`askTopicName close failed: ${e}`); });
    };
    const params: TopicNameDialogParams = {
      onSubmit: (name: string): void => { submitted = name; },
      onClose: close
    };
    const node: ComponentContent<TopicNameDialogParams> =
      new ComponentContent(ui, wrapBuilder(topicNameDialogLayer), params);
    content = node;
    ui.getPromptAction().openCustomDialog(node, {
      autoCancel: true,
      alignment: DialogAlignment.Center,
      onDidDisappear: (): void => {
        content = null;
        node.dispose();
        resolve(submitted);
      }
    }).catch((e: Object): void => {
      content = null;
      node.dispose();
      logE(`askTopicName open failed: ${e}`);
      resolve(null);
    });
  });
}

// 问名字 → createForumTopic。成功返回新话题；取消或失败返回 null（失败已提示）。
export function createTopicFlow(ui: UIContext, chatId: number): Promise<CreatedTopic | null> {
  return askTopicName(ui).then((name: string | null): Promise<CreatedTopic | null> => {
    const req: TdRequest | null = name !== null ? forumTopicCreateRequest(chatId, name) : null;
    if (name === null || req === null) {
      return Promise.resolve(null);
    }
    const trimmed: string = name.trim();
    return getTdClient().send(req).then((info: TdObject): CreatedTopic | null => {
      const threadId: number = (info['forum_topic_id'] as number | undefined) ?? 0;
      return threadId > 0 ? { threadId: threadId, name: trimmed } : null;
    }).catch((e: TdError): CreatedTopic | null => {
      logE(`TopicManageFlow.createForumTopic failed: ${e.message}`);
      promptAction.showToast({ message: str('ga_failed'), duration: 2000 });
      return null;
    });
  });
}

// 确认 → deleteForumTopic。General 话题不可删。返回是否真的删掉了。
export function deleteTopicFlow(chatId: number, row: ForumTopicRow): Promise<boolean> {
  const req: TdRequest | null = forumTopicDeleteRequest(chatId, row.threadId);
  if (row.isGeneral || req === null) {
    return Promise.resolve(false);
  }
  return promptAction.showDialog({
    title: str('ft_delete_topic'),
    message: str('ft_delete_confirm', row.name),
    buttons: [
      { text: str('cancel'), color: '#8E8E93' },
      { text: str('delete'), color: '#E5484D' }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): Promise<boolean> => {
    if (result.index !== 1) {
      return Promise.resolve(false);
    }
    return getTdClient().send(req).then((): boolean => true).catch((e: TdError): boolean => {
      logE(`TopicManageFlow.deleteForumTopic failed: ${e.message}`);
      promptAction.showToast({ message: str('delete_failed'), duration: 2000 });
      return false;
    });
  }).catch((): boolean => false);
}
