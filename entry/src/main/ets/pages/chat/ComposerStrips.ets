import { InlineResultRow } from '../../store/BotApi';
import { COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 输入框上方的两条横向建议带：@机器人 的内联结果、打字触发的贴纸提示。
//
// 从 ChatPage 搬出来。两者互斥（有内联结果就不显示贴纸提示），各自只有一个
// 动作，都回调出去——发送要碰 store。
//
// 外壳只差一个高度（88 / 70），刻意**没有**再抽一层共用壳：那点重复只有四行
// 属性，抽出来绕的弯比省的多。抽屉那次值得，是因为重复的是二十行注释加八个
// 属性。

// 一条打字触发的贴纸提示。ChatPage 里原本就是本地 interface，跟着搬过来。
export interface StickerSuggestion {
  fileId: number;
  thumbId: number;
  thumbPath: string;
}

@Component
export struct InlineResultsBar {
  @Prop results: InlineResultRow[];

  onPick: (row: InlineResultRow) => void = (): void => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.results, (row: InlineResultRow) => {
          Column({ space: 3 }) {
            Stack({ alignContent: Alignment.Center }) {
              if (row.thumbPath !== '') {
                Image(`file://${row.thumbPath}`).draggable(false).width(56).height(56)
                  .objectFit(ImageFit.Cover).borderRadius(8);
              } else {
                // 缩略图还没下下来：占位用文档图标，别让整条塌下去。
                SymbolGlyph($r('sys.symbol.doc')).fontSize(22)
                  .fontColor([COLOR_ICON_SECONDARY]);
              }
            }.width(58).height(58)
            .backgroundColor($r('app.color.surface_alt')).borderRadius(8);
            if (row.title !== '') {
              Text(row.title).fontSize(10).fontColor(COLOR_TEXT_SECONDARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 62 });
            }
          }
          .onClick((): void => { this.onPick(row); });
        }, (row: InlineResultRow): string => `ir_${row.resultId}`);
      }.padding({ left: 10, right: 10, top: 6, bottom: 6 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(88)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }
}

@Component
export struct StickerSuggestionBar {
  @Prop suggestions: StickerSuggestion[];

  onPick: (fileId: number) => void = (): void => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.suggestions, (row: StickerSuggestion) => {
          Stack({ alignContent: Alignment.Center }) {
            if (row.thumbPath !== '') {
              Image(`file://${row.thumbPath}`).draggable(false)
                .width(56).height(56).objectFit(ImageFit.Contain);
            } else {
              LoadingProgress().width(20).height(20).color(COLOR_TEXT_SECONDARY);
            }
          }
          .width(62).height(62)
          .onClick((): void => { this.onPick(row.fileId); });
        }, (row: StickerSuggestion): string => `sg_${row.fileId}`);
      }.padding({ left: 10, right: 10 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(70)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }
}
