import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import {
  MATERIAL_EPOCH, overlayBackdropBlur, overlayGlassFill
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';

// 群成员标签（chatMemberTag）的小弹窗。任何成员都能被打标、全员可见；
// 留空即清除，不需要额外的删除按钮。上限 16 字符、不支持表情，超了服务端拒。
@CustomDialog
export struct MemberTitleDialog {
  // 材质档位改变时重绘。overlayMaterial 是 util，订阅不了 AppStorage。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  controller?: CustomDialogController;
  memberName: string = '';
  @State title: string = '';
  onConfirm: (title: string) => void = (): void => {};

  build() {
    Column({ space: 14 }) {
      Text($r('app.string.ga_edit_title'))
        .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.memberName)
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      TextInput({ text: this.title })
        // chatMemberTag 的上限是 16 个字符，超了会被服务端拒。
        .maxLength(16)
        .width('100%').height(44)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .onChange((value: string): void => { this.title = value; });
      Text($r('app.string.mt_tag_hint'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(22).layoutWeight(1).height(44)
          .onClick((): void => { this.controller?.close(); });
        Button($r('app.string.save'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22).layoutWeight(1).height(44)
          .onClick((): void => {
            this.controller?.close();
            this.onConfirm(this.title);
          });
      }.width('100%');
    }
    .width('88%').padding(20)
    .backgroundColor(overlayGlassFill('dialog', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('dialog'))
    .attributeModifier(materialModifier('dialog'))
    .borderRadius(20)
    .alignItems(HorizontalAlign.Start);
  }
}
