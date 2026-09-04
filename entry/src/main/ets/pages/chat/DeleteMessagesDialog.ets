import { ComponentContent, UIContext } from '@kit.ArkUI';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

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
  onConfirm: (revoke: boolean) => void;
  // 由打开方接上 closeCustomDialog——这一层不再持有 controller。
  onClose: () => void;
}

@Component
export struct DeleteMessagesDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  peerName: string = '';
  onConfirm: (revoke: boolean) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State revoke: boolean = false;

  private revokeLabel(): string {
    return this.peerName !== '' ? str('dm_delete_for_both', this.peerName) : str('dm_delete_for_everyone');
  }

  build() {
    Column({ space: 18 }) {
      Text($r('app.string.dm_confirm'))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center).width('100%');

      Row({ space: 10 }) {
        Checkbox()
          .select(this.revoke)
          .selectedColor(COLOR_PRIMARY)
          .onChange((checked: boolean): void => { this.revoke = checked; });
        Text(this.revokeLabel())
          .fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => { this.revoke = !this.revoke; });

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(22)
          .layoutWeight(1).height(44)
          .onClick((): void => { this.onClose(); });
        Button($r('app.string.delete'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22)
          .layoutWeight(1).height(44)
          .onClick((): void => {
            const revoke: boolean = this.revoke;
            this.onClose();
            this.onConfirm(revoke);
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
    onConfirm: p.onConfirm,
    onClose: p.onClose
  })
}

// 打开弹窗的唯一入口。ComponentContent 是脱离组件树管理的节点实体，关掉之后
// 必须 dispose，否则那棵子树泄漏；onDidDisappear 覆盖了点遮罩自动取消这条路。
export function openDeleteMessagesDialog(ui: UIContext, peerName: string,
  onConfirm: (revoke: boolean) => void): void {
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
}
