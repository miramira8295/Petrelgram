import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';

// 删除消息的确认弹窗。用 CustomDialog 而不是 promptAction.showDialog：后者
// 只能排按钮，挂不了复选框，而"是否同时为对方删除"是一个开关而非第三个按钮
// —— 做成三按钮时用户得在两个红色危险项之间辨认，容易点错。
@CustomDialog
export struct DeleteMessagesDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  controller?: CustomDialogController;
  // 复选框文案里的对方名字；群聊传空，显示"为所有人删除"。
  peerName: string = '';
  onConfirm: (revoke: boolean) => void = (): void => {};
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
          .onClick((): void => { this.controller?.close(); });
        Button($r('app.string.delete'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22)
          .layoutWeight(1).height(44)
          .onClick((): void => {
            const revoke: boolean = this.revoke;
            this.controller?.close();
            this.onConfirm(revoke);
          });
      }
      .width('100%');
    }
    // customStyle 下宽度完全由内容决定，给 100% 就会顶满整屏。
    .width('86%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor(overlayGlassFill('dialog', $r('app.color.surface')))
    .borderRadius(18)
    .backdropBlur(overlayBackdropBlur('dialog'))
    .attributeModifier(materialModifier('dialog'));
  }
}
