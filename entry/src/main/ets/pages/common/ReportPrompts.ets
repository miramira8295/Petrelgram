import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { syncTdLanguage, tdLanguageGeneration } from '../../services/TdLanguage';
import { reportDisplayText } from '../../util/reportLabels';
import { ComponentContent, promptAction, UIContext } from '@kit.ArkUI';
import { COLOR_ON_PRIMARY, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { ReportFlowUi, ReportOption } from '../../util/reportFlow';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 举报流程的 UI 适配：把 util/reportFlow 要的三件事接到真正的弹层上。
// 会话页与消息菜单共用，所以放 common。
//
// 选原因用可滚动列表，完整显示服务器的动态选项；补充说明使用输入框。两者用
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

export interface ReportOptionsDialogParams {
  title: string;
  options: ReportOption[];
  onSelect: (option: ReportOption) => void;
  onClose: () => void;
}

@Component
export struct ReportOptionsDialog {
  title: string = '';
  options: ReportOption[] = [];
  onSelect: (option: ReportOption) => void = (): void => {};
  onClose: () => void = (): void => {};
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageChanged') languageEpoch: number = 0;

  private onLanguageChanged(): void { this.onClose(); }

  build() {
    Column({ space: 12 }) {
      Text(reportDisplayText(this.title, str, true))
        .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%').textAlign(TextAlign.Center);
      List({ space: 4 }) {
        ForEach(this.options, (option: ReportOption) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Text(reportDisplayText(option.text, str)).fontSize(16)
                .fontColor(COLOR_TEXT_PRIMARY).width('100%');
            }
            .width('100%').constraintSize({ minHeight: 48 })
            .padding({ top: 12, bottom: 12, left: 14, right: 14 })
            .backgroundColor(COLOR_PAGE_BG).borderRadius(10)
            .onClick((): void => { this.onSelect(option); });
          }
        }, (option: ReportOption, index: number): string => `${index}:${option.id}`);
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto);
      Button($r('app.string.cancel')).width('100%').height(44)
        .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
        .backgroundColor($r('app.color.surface_alt'))
        .onClick((): void => { this.onClose(); });
    }
    .width('86%').height('70%').constraintSize({ maxWidth: 400, maxHeight: 560 })
    .padding(20).backgroundColor($r('app.color.surface')).borderRadius(18);
  }
}

@Builder
function reportOptionsDialogLayer(p: ReportOptionsDialogParams) {
  ReportOptionsDialog({ title: p.title, options: p.options, onSelect: p.onSelect, onClose: p.onClose })
}

function pickReportOption(ui: UIContext, title: string, options: ReportOption[]): Promise<ReportOption | null> {
  return new Promise<ReportOption | null>((resolve): void => {
    let content: ComponentContent<ReportOptionsDialogParams> | null = null;
    let selected: ReportOption | null = null;
    let closing: boolean = false;
    let finished: boolean = false;
    const epoch: number = AppStorage.get<number>(LANGUAGE_EPOCH) ?? 0;
    const finish = (): void => {
      if (finished) { return; }
      finished = true;
      const node: ComponentContent<ReportOptionsDialogParams> | null = content;
      content = null;
      node?.dispose();
      resolve(epoch === (AppStorage.get<number>(LANGUAGE_EPOCH) ?? 0) ? selected : null);
    };
    const close = (option: ReportOption | null): void => {
      if (closing || content === null) { return; }
      selected = option;
      closing = true;
      ui.getPromptAction().closeCustomDialog(content).catch((): void => {
        selected = null;
        closing = false;
        logE('Report options dialog close failed');
      });
    };
    const params: ReportOptionsDialogParams = {
      title, options,
      onSelect: (option: ReportOption): void => { close(option); },
      onClose: (): void => { close(null); }
    };
    content = new ComponentContent(ui, wrapBuilder(reportOptionsDialogLayer), params);
    ui.getPromptAction().openCustomDialog(content, {
      autoCancel: true, alignment: DialogAlignment.Center,
      onDidDisappear: finish
    }).catch((): void => {
      selected = null;
      finish();
      logE('Report options dialog open failed');
    });
  });
}

// 接口里是方法签名，ArkTS 不让对象字面量直接充当（arkts-no-untyped-obj-literals），用类。
class ReportPromptsUi implements ReportFlowUi {
  private readonly ui: UIContext;
  private readonly runtime: number = tdLanguageGeneration();
  private readonly epoch: number = AppStorage.get<number>(LANGUAGE_EPOCH) ?? 0;
  async prepare(): Promise<boolean> {
    await syncTdLanguage();
    return this.current();
  }
  private current(): boolean {
    return this.runtime === tdLanguageGeneration() &&
      this.epoch === (AppStorage.get<number>(LANGUAGE_EPOCH) ?? 0);
  }
  constructor(ui: UIContext) { this.ui = ui; }
  pickOption(title: string, options: ReportOption[]): Promise<ReportOption | null> {
    return this.current() ? pickReportOption(this.ui, title, options) : Promise.resolve(null);
  }
  askText(): Promise<string | null> {
    return this.current() ? askReportText(this.ui) : Promise.resolve(null);
  }
  toast(key: string): void {
    promptAction.showToast({ message: str(key), duration: 1800 });
  }
}

export function reportFlowUiFor(ui: UIContext): ReportFlowUi {
  return new ReportPromptsUi(ui);
}
