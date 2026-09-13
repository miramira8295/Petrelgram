import { ComponentContent, UIContext } from '@kit.ArkUI';
import { COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { logE } from '../../util/log';

// 带勾选项的确认弹窗：标题 + 一句说明 + 若干复选框 + 取消/确认。
// 第一个用户是会话操作条的「屏蔽」（issue #201 第 8 条，勾选「同时删除对话」）。
// 结构照 DeleteMessagesDialog：ComponentContent + openCustomDialog，不用
// CustomDialogController（官方明写仅限状态管理 V1）；实底不走材质。
export interface ChecklistOption {
  id: string;
  label: string;
  checked: boolean;
}

export interface ChecklistDialogParams {
  title: string;
  hint: string;
  options: ChecklistOption[];
  confirmLabel: string;
  destructive: boolean;
  onConfirm: (checkedIds: string[]) => void;
  onClose: () => void;
}

@Component
export struct ChecklistDialog {
  title: string = '';
  hint: string = '';
  options: ChecklistOption[] = [];
  confirmLabel: string = '';
  destructive: boolean = false;
  onConfirm: (checkedIds: string[]) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State checked: string[] = [];

  aboutToAppear(): void {
    this.checked = this.options.filter((o: ChecklistOption): boolean => o.checked)
      .map((o: ChecklistOption): string => o.id);
  }

  private isOn(id: string): boolean {
    return this.checked.indexOf(id) >= 0;
  }

  private toggle(id: string): void {
    this.checked = this.isOn(id)
      ? this.checked.filter((x: string): boolean => x !== id)
      : this.checked.concat([id]);
  }

  build() {
    Column({ space: 14 }) {
      Text(this.title)
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center).width('100%');
      if (this.hint !== '') {
        Text(this.hint).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
          .textAlign(TextAlign.Center).width('100%');
      }
      ForEach(this.options, (o: ChecklistOption) => {
        Row({ space: 10 }) {
          Checkbox().select(this.isOn(o.id)).selectedColor(COLOR_PRIMARY)
            .onChange((_v: boolean): void => { this.toggle(o.id); });
          Text(o.label).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .onClick((): void => { this.toggle(o.id); });
      }, (o: ChecklistOption): string => o.id);
      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(22).layoutWeight(1).height(44)
          .onClick((): void => { this.onClose(); });
        Button(this.confirmLabel)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_PRIMARY)
          .backgroundColor(this.destructive ? '#E5484D' : COLOR_PRIMARY)
          .borderRadius(22).layoutWeight(1).height(44)
          .onClick((): void => {
            const ids: string[] = this.checked.slice();
            this.onClose();
            this.onConfirm(ids);
          });
      }
      .width('100%');
    }
    .width('86%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18);
  }
}

@Builder
function checklistDialogLayer(p: ChecklistDialogParams) {
  ChecklistDialog({
    title: p.title, hint: p.hint, options: p.options, confirmLabel: p.confirmLabel,
    destructive: p.destructive, onConfirm: p.onConfirm, onClose: p.onClose
  })
}

export function openChecklistDialog(ui: UIContext, title: string, hint: string,
  options: ChecklistOption[], confirmLabel: string, destructive: boolean,
  onConfirm: (checkedIds: string[]) => void): void {
  let content: ComponentContent<ChecklistDialogParams> | null = null;
  const close = (): void => {
    const open: ComponentContent<ChecklistDialogParams> | null = content;
    if (open === null) {
      return;
    }
    ui.getPromptAction().closeCustomDialog(open)
      .catch((e: Object): void => { logE(`openChecklistDialog close failed: ${e}`); });
  };
  const params: ChecklistDialogParams = {
    title, hint, options, confirmLabel, destructive, onConfirm, onClose: close
  };
  const node: ComponentContent<ChecklistDialogParams> =
    new ComponentContent(ui, wrapBuilder(checklistDialogLayer), params);
  content = node;
  ui.getPromptAction().openCustomDialog(node, {
    autoCancel: true,
    alignment: DialogAlignment.Center,
    onDidDisappear: (): void => {
      content = null;
      node.dispose();
    }
  }).catch((e: Object): void => {
    content = null;
    node.dispose();
    logE(`openChecklistDialog open failed: ${e}`);
  });
}
