import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import {
  MATERIAL_EPOCH, overlayBackdropBlur, overlayGlassFill, overlayMaterial
} from '../../util/overlayMaterial';

// 单独改成员头衔的小弹窗。
//
// 官方 PC 端把「编辑标签」做成菜单里独立的一项，而不是埋进管理员权限面板：
// 改个称呼是高频小操作，为它进那一大页开关不划算。这里只放一个输入框。
//
// 留空即清掉头衔，回到默认的「管理员」——和官方一致，不需要额外的删除按钮。
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
      TextInput({ text: this.title, placeholder: $r('app.string.ga_admin') })
        // TDLib 对 custom_title 的上限是 16 个字符，超了会被服务端拒。
        .maxLength(16)
        .width('100%').height(44)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .onChange((value: string): void => { this.title = value; });
      Text($r('app.string.ga_title_hint'))
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
    .systemMaterial(overlayMaterial('dialog'))
    .borderRadius(20)
    .alignItems(HorizontalAlign.Start);
  }
}
