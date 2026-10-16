import { ComponentContent, UIContext } from '@kit.ArkUI';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_ON_PRIMARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { logE } from '../../util/log';
import { DeleteMessageChoice, ModerationOptions, noModeration, hasModeration, MessageDeleteScope, messageDeleteRevoke } from '../../util/messageModeration';

// 删除消息的确认弹窗。用自定义弹窗而不是 promptAction.showDialog：后者只能排
// 按钮，挂不了复选框，而"是否同时为对方删除"是一个开关而非第三个按钮 —— 做成
// 三按钮时用户得在两个红色危险项之间辨认，容易点错。
//
// 走 ComponentContent + UIContext.openCustomDialog（API 12 起），不走
// @CustomDialog + CustomDialogController：后两者官方明写只在状态管理 V1 中
// 使用，而聊天详情页要迁 V2。这一层本身仍是普通的 V1 @Component。
export interface DeleteMessagesDialogParams {
  // 复选框文案里的对方名字；群聊传空，显示"为所有人删除"。
  peerName: string;
  scope: MessageDeleteScope;
  options: ModerationOptions;
  targetName: string;
  onConfirm: (choice: DeleteMessageChoice) => void;
  // 由打开方接上 closeCustomDialog——这一层不再持有 controller。
  onClose: () => void;
}

@Component
struct DeleteActionOption {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop canToggle: boolean = true;
  onChange: (value: boolean) => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Checkbox().select(this.selected).selectedColor(COLOR_PRIMARY)
        .onChange((checked: boolean): void => { this.onChange(checked); });
      Text(this.label).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
        .onClick((): void => { this.onChange(!this.selected); });
    }.width('100%').alignItems(VerticalAlign.Center).enabled(this.canToggle);
  }
}

@Component
export struct DeleteMessagesDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  peerName: string = '';
  scope: MessageDeleteScope = { self: false, all: false };
  options: ModerationOptions = noModeration();
  targetName: string = '';
  onConfirm: (choice: DeleteMessageChoice) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State revoke: boolean = false;
  @State report: boolean = false;
  @State deleteAll: boolean = false;
  @State memberAction: string = '';
  private confirmed: boolean = false;

  private revokeLabel(): string {
    return this.peerName !== '' ? str('dm_delete_for_both', this.peerName) : str('dm_delete_for_everyone');
  }


  build() {
    Column({ space: 18 }) {
      Text($r('app.string.dm_confirm'))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center).width('100%');

      Scroll() {
        Column({ space: 10 }) {
          if (this.scope.self && this.scope.all && !this.deleteAll) {
            DeleteActionOption({ label: this.revokeLabel(), selected: this.revoke,
              onChange: (checked: boolean): void => { this.revoke = checked; } });
          } else {
            Text(str(this.deleteAll || this.scope.all ? 'dm_scope_all' : 'dm_scope_self'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).width('100%');
          }
          if (hasModeration(this.options)) {
            Text(str('dm_moderation_target', this.targetName))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
            if (this.options.report) {
              DeleteActionOption({ label: str('ab_report_spam'), selected: this.report,
                onChange: (checked: boolean): void => { this.report = checked; } });
            }
            if (this.options.deleteAll) {
              DeleteActionOption({ label: str('ga_delete_all'), selected: this.deleteAll,
                onChange: (checked: boolean): void => { this.deleteAll = checked; } });
              if (this.deleteAll) {
                Text($r('app.string.mm_delete_all_confirm')).fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY).width('100%');
              }
            }
            if (this.options.ban) {
              DeleteActionOption({ label: str('ga_ban'), selected: this.memberAction === 'ban',
                onChange: (checked: boolean): void => {
                  if (checked || this.memberAction === 'ban') { this.memberAction = checked ? 'ban' : ''; }
                } });
              if (this.memberAction === 'ban') {
                Text($r('app.string.mm_ban_confirm')).fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY).width('100%');
              }
            }
            if (this.options.remove) {
              DeleteActionOption({ label: str('ga_remove_member'), selected: this.memberAction === 'remove',
                onChange: (checked: boolean): void => {
                  if (checked || this.memberAction === 'remove') { this.memberAction = checked ? 'remove' : ''; }
                } });
            }
          }
        }.width('100%');
      }.width('100%').constraintSize({ maxHeight: 320 });

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(22)
          .layoutWeight(1).height(44)
          .onClick((): void => { this.onClose(); });
        Button($r('app.string.delete'))
          .enabled(this.scope.self || this.scope.all)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_PRIMARY)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22)
          .layoutWeight(1).height(44)
          .onClick((): void => {
            if (this.confirmed) { return; }
            this.confirmed = true;
            const choice: DeleteMessageChoice = {
              revoke: messageDeleteRevoke(this.scope, this.revoke, this.deleteAll), report: this.report,
              deleteAll: this.deleteAll, memberAction: this.memberAction
            };
            this.onClose();
            this.onConfirm(choice);
          });
      }
      .width('100%');
    }
    // customStyle 下宽度完全由内容决定，给 100% 就会顶满整屏。
    .width('86%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    // **这个弹窗不走玻璃/材质，用实底。**
    //
    // 走 overlayGlassFill('dialog', …) 时，设备自报支持沉浸材质就会拿到
    // material_tint —— 那只是薄薄一层淡色，本意是叠在**真的渲染出来的**材质
    // 之上。而这台机器（PLA-AL10 / OpenHarmony 7.0.0.105）实测材质挂了却不渲染
    // （见 overlayMaterial.overlayGlassFill 里 08-29 那段记录），于是那层淡色
    // 成了唯一的背板：顶栏压在均匀底上还行，**确认弹窗压在花花绿绿的消息上就是
    // 一块透明的窟窿，文字和按钮都读不清**（用户实测截图）。
    //
    // 弹窗和栏的取舍不一样：栏可以为了通透牺牲一点对比，而**确认框必须在材质
    // 完全不画的时候仍然可读**——它要用户做一个不可撤销的决定。所以这里不赌
    // 材质，直接给实底。
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18);
  }
}

// ComponentContent 要的是 wrapBuilder 包过的全局 @Builder，不能是裸箭头函数：
// 全局 @Builder 在 struct 之外被直接调用时没有组件上下文，会抛
// "Cannot read property observeComponentCreation2 of undefined"。
@Builder
function deleteMessagesDialogLayer(p: DeleteMessagesDialogParams) {
  DeleteMessagesDialog({
    peerName: p.peerName,
    scope: p.scope,
    options: p.options,
    targetName: p.targetName,
    onConfirm: p.onConfirm,
    onClose: p.onClose
  })
}

// 打开弹窗的唯一入口。ComponentContent 是脱离组件树管理的节点实体，关掉之后
// 必须 dispose，否则那棵子树泄漏；onDidDisappear 覆盖了点遮罩自动取消这条路。
export function openDeleteMessagesDialog(ui: UIContext, peerName: string, scope: MessageDeleteScope,
  onConfirm: (choice: DeleteMessageChoice) => void,
  options: ModerationOptions = noModeration(), targetName: string = ''): () => void {
  let content: ComponentContent<DeleteMessagesDialogParams> | null = null;
  const close = (): void => {
    const open: ComponentContent<DeleteMessagesDialogParams> | null = content;
    if (open === null) {
      return;
    }
    ui.getPromptAction().closeCustomDialog(open)
      .catch((e: Object): void => { logE(`openDeleteMessagesDialog close failed: ${e}`); });
  };
  const params: DeleteMessagesDialogParams = {
    peerName: peerName,
    scope: scope,
    options: options,
    targetName: targetName,
    onConfirm: onConfirm,
    onClose: close
  };
  const node: ComponentContent<DeleteMessagesDialogParams> =
    new ComponentContent(ui, wrapBuilder(deleteMessagesDialogLayer), params);
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
    logE(`openDeleteMessagesDialog open failed: ${e}`);
  });
  return close;
}
