import { ComponentContent, promptAction, UIContext } from '@kit.ArkUI';
import { COLOR_ON_PRIMARY, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { ReportFlowUi, ReportOption } from '../../util/reportFlow';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 举报流程的 UI 适配：把 util/reportFlow 要的三件事接到真正的弹层上。
// 会话页与消息菜单共用，所以放 common。
//
// 选原因走 promptAction.showActionMenu（沿用会话页原来的做法，按钮上限见
// REPORT_OPTION_LIMIT）；补充说明需要一个输入框，系统弹窗排不了，用
// ComponentContent + UIContext.openCustomDialog——与 DeleteMessagesDialog 同一
// 条路，理由也一样：不走 CustomDialogController（官方明写仅限状态管理 V1）。

export interface ReportTextDialogParams {
  onSubmit: (text: string) => void;
  onClose: () => void;
}

@Component
export struct ReportTextDialog {
  onSubmit: (text: string) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State text: string = '';

  build() {
    Column({ space: 14 }) {
      Text($r('app.string.rf_text_title'))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center).width('100%');
      TextArea({ text: $$this.text, placeholder: $r('app.string.rf_text_hint') })
        .fontSize(14).width('100%').constraintSize({ minHeight: 88, maxHeight: 160 })
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(22).layoutWeight(1).height(44)
          .onClick((): void => { this.onClose(); });
        Button($r('app.string.send'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_PRIMARY)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22).layoutWeight(1).height(44)
          .enabled(this.text.trim() !== '')
          .onClick((): void => {
            const typed: string = this.text.trim();
            this.onClose();
            this.onSubmit(typed);
          });
      }
      .width('100%');
    }
    .width('86%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    // 实底不走材质，理由同 DeleteMessagesDialog：输入框压在消息上必须可读。
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18);
  }
}

// ComponentContent 要 wrapBuilder 包过的全局 @Builder（见 DeleteMessagesDialog 的说明）。
@Builder
function reportTextDialogLayer(p: ReportTextDialogParams) {
  ReportTextDialog({ onSubmit: p.onSubmit, onClose: p.onClose })
}

// resolve(null) = 用户取消（点取消或点遮罩）。
function askReportText(ui: UIContext): Promise<string | null> {
  return new Promise<string | null>((resolve: (v: string | null) => void): void => {
    let content: ComponentContent<ReportTextDialogParams> | null = null;
    let submitted: string | null = null;
    const close = (): void => {
      const open: ComponentContent<ReportTextDialogParams> | null = content;
      if (open === null) {
        return;
      }
      ui.getPromptAction().closeCustomDialog(open)
        .catch((e: Object): void => { logE(`askReportText close failed: ${e}`); });
    };
    const params: ReportTextDialogParams = {
      onSubmit: (text: string): void => { submitted = text; },
      onClose: close
    };
    const node: ComponentContent<ReportTextDialogParams> =
      new ComponentContent(ui, wrapBuilder(reportTextDialogLayer), params);
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
      logE(`askReportText open failed: ${e}`);
      resolve(null);
    });
  });
}

function pickReportOption(title: string, options: ReportOption[]): Promise<ReportOption | null> {
  const buttons: promptAction.Button[] = options.map((o: ReportOption): promptAction.Button =>
    ({ text: o.text, color: '#E5484D' } as promptAction.Button));
  return promptAction.showActionMenu({
    title: title !== '' ? title : str('cpp_report_reason'),
    buttons: buttons as [promptAction.Button, promptAction.Button?, promptAction.Button?,
      promptAction.Button?, promptAction.Button?, promptAction.Button?]
  }).then((chosen: promptAction.ActionMenuSuccessResponse): ReportOption | null =>
    options[chosen.index] ?? null
  ).catch((): ReportOption | null => null);
}

// 接口里是方法签名，ArkTS 不让对象字面量直接充当（arkts-no-untyped-obj-literals），用类。
class ReportPromptsUi implements ReportFlowUi {
  private readonly ui: UIContext;
  constructor(ui: UIContext) { this.ui = ui; }
  pickOption(title: string, options: ReportOption[]): Promise<ReportOption | null> {
    return pickReportOption(title, options);
  }
  askText(): Promise<string | null> {
    return askReportText(this.ui);
  }
  toast(key: string): void {
    promptAction.showToast({ message: str(key), duration: 1800 });
  }
}

export function reportFlowUiFor(ui: UIContext): ReportFlowUi {
  return new ReportPromptsUi(ui);
}
