import { musicGlassEffect, musicGlassFill, musicSheetBlur } from '../../util/musicCenterStyle';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 音乐中心几张底部浮层共用的壳：顶上一条小横杠、标题、副标题，内容由调用方给。
//
// 【为什么不是 bindSheet】音乐中心自己就是一页 NavDestination，浮层要和页面里的
// 搜索层、遮罩共用一个 Stack 的层序；而 bindSheet 在平板分栏下不支持转屏
// （见 [[media-viewer-as-own-destination]] 里记的那条隐患），页面内自绘更可控。

export const MUSIC_SHEET_RADIUS: number = 32;

@Component
export struct MusicSheetShell {
  @Prop title: ResourceStr;
  // 空串 = 不显示副标题。
  @Prop subTitle: string;
  @Prop bottomInset: number;
  @BuilderParam content: () => void;

  build() {
    Column() {
      Column()
        .width(40).height(5).borderRadius(3)
        .backgroundColor($r('app.color.divider'))
        .margin({ top: 10 });
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .width('100%');
        if (this.subTitle !== '') {
          Text(this.subTitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        }
      }
      .width('100%').padding({ left: 22, right: 22, top: 14, bottom: 12 })
      .alignItems(HorizontalAlign.Start);
      this.content();
    }
    .width('100%')
    .constraintSize({ maxHeight: '78%' })
    .padding({ bottom: this.bottomInset + 16 })
    .borderRadius({ topLeft: MUSIC_SHEET_RADIUS, topRight: MUSIC_SHEET_RADIUS })
    .clip(true)
    .backgroundColor(musicGlassFill())
    .backdropBlur(musicSheetBlur())
    .visualEffect(musicGlassEffect())
    .border({ width: 0.5, color: $r('app.color.divider') });
  }
}
