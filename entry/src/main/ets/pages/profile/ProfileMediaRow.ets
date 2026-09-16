import { ProfileContentItem } from '../../store/ChatProfileStore';
import { COLOR_ICON_SECONDARY } from '../../util/theme';

// 共享媒体网格的一行（群资料页、个人资料页共用）。原来整张网格是 Flex 折行 + ForEach，
// 每一格提前建好；现在 List 的一项是一行，走 LazyForEach，这个组件在滚动时进出复用池。
//
// 回调只收 messageId：它跟着复用节点走，不能攥着建它时的那一行数据。
@Reusable
@Component
export struct ProfileMediaRow {
  @Prop items: ProfileContentItem[] = [];
  // 格子边长由页面按量到的内容宽算（util/mediaGrid），每行都一样。
  @Prop cellSize: number = 92;
  // 两个页面的按压透明度原来就不一样（0.58 / 0.62），各自传。
  @Prop pressedOpacity: number = 0.6;
  onOpen: (messageId: number) => void = (_messageId: number): void => {};

  @Styles
  cellNormalStyle() {
    .opacity(1)
  }

  @Styles
  cellPressedStyle() {
    .opacity(this.pressedOpacity)
  }

  build() {
    Row() {
      ForEach(this.items, (item: ProfileContentItem) => {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (item.thumbPath !== '') {
            Image(`file://${item.thumbPath}`).draggable(false).width('100%').height('100%')
              .objectFit(ImageFit.Cover);
          } else {
            Column() {
              SymbolGlyph($r(item.isVideo ? 'sys.symbol.video_fill' : 'sys.symbol.photo_fill'))
                .fontSize(26).fontColor([COLOR_ICON_SECONDARY]);
            }
            .width('100%').height('100%').justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.surface_alt'));
          }
          if (item.isVideo) {
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(10).fontColor([Color.White]);
              if (item.duration !== '') {
                Text(item.duration).fontSize(11).fontColor(Color.White);
              }
              if (item.cached) {
                SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(10).fontColor([Color.White]);
              }
            }
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .margin({ right: 5, bottom: 5 })
            .backgroundColor('#70000000').borderRadius(8);
          }
        }
        .width(this.cellSize).height(this.cellSize)
        .margin({ right: 2, bottom: 2 })
        .stateStyles({ normal: this.cellNormalStyle, pressed: this.cellPressedStyle })
        .onClick((): void => { this.onOpen(item.messageId); });
      }, (item: ProfileContentItem): string => `${item.messageId}_${item.thumbPath}_${item.cached}`);
    }
    .width('100%')
    .justifyContent(FlexAlign.Start);
  }
}
