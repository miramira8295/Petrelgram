import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { PendingMediaItem } from '../../util/pendingMedia';
import { plural } from '../../util/strings';

// 输入框上方那一条：已经选好、还没发出去的媒体。
//
// 和 EditStrip / ReplyStrip 同一个位置、同一套观感（左侧强调色竖条 + 标题 +
// 副标题 + 右侧 ✕），但它和那两条**不互斥**——回复某条 + 附图 + 配文是一次
// 完整操作，所以这一条叠在回复条上方，两条可以同时在。
//
// 缩略图用横向 List 而不是 Row+Scroll：换序要靠 List 的 onItemDragStart /
// onItemDrop，Row 里没有这套回调。
//
// 副标题复用 mp_item_count 这个已有的复数键（19 种语言都带正确的复数类别），
// 而不是新造"N 张图片 / N 个视频"——后者要新增 plural 条目，每种语言的复数
// 类别都不一样，而缩略图本身已经把张数和类型说清楚了。

const THUMB: number = 56;

@Component
export struct MediaStrip {
  @Prop items: PendingMediaItem[];

  onRemoveAt: (index: number) => void = (): void => {};
  onMove: (from: number, to: number) => void = (): void => {};
  onCancel: () => void = (): void => {};

  // 拖起来的那一张的下标。onItemDrop 只给落点，起点得自己记。
  @State private dragFrom: number = -1;

  @Builder
  thumb(item: PendingMediaItem, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(`file://${item.path}`)
        .draggable(false)
        .width(THUMB).height(THUMB)
        .objectFit(ImageFit.Cover)
        .borderRadius(8);
      if (item.isVideo) {
        // 视频角标：缩略图是首帧，不标一下和图片分不出来。
        Row() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(10).fontColor([Color.White]);
        }
        .width(18).height(18).borderRadius(9)
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.Center)
        .margin({ top: THUMB - 20, right: THUMB - 20 });
      }
      // 单张移除。热区做到 22×22 而图标 14——44 的标准热区在 56 的缩略图上
      // 会盖掉大半张图，这里取一个能点中又不挡图的折中。
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(11).fontColor([Color.White]);
      }
      .width(22).height(22).borderRadius(11)
      .backgroundColor('#A6000000')
      .justifyContent(FlexAlign.Center)
      .margin({ top: -2, right: -2 })
      .onClick((): void => { this.onRemoveAt(index); });
    }
    .width(THUMB).height(THUMB);
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
        Column({ space: 1 }) {
          Text($r('app.string.cp_pending_media'))
            .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          Text(plural('mp_item_count', this.items.length, this.items.length))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
        }
        .width(32).height(32).borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .accessibilityText($r('app.string.cancel'))
        .onClick((): void => { this.onCancel(); });
      }
      .width('100%').height(40).padding({ left: 12, right: 8 });

      List({ space: 8 }) {
        ForEach(this.items, (item: PendingMediaItem, index: number) => {
          ListItem() {
            this.thumb(item, index);
          }
        }, (item: PendingMediaItem, index: number): string => `pm_${index}_${item.path}`);
      }
      .listDirection(Axis.Horizontal)
      .width('100%').height(THUMB + 4)
      .padding({ left: 12, right: 12 })
      .scrollBar(BarState.Off)
      // 长按拖起来换序。发送顺序就是这里的排列顺序，所以这不是装饰。
      .editMode(true)
      .onItemDragStart((_event: ItemDragInfo, itemIndex: number): void => {
        this.dragFrom = itemIndex;
      })
      .onItemDrop((_event: ItemDragInfo, _itemIndex: number,
        insertIndex: number, isSuccess: boolean): void => {
        const from: number = this.dragFrom;
        this.dragFrom = -1;
        // 松手落在列表外时 isSuccess 为假；此时什么都不做，别把那一张挪走。
        if (isSuccess && from >= 0) {
          this.onMove(from, insertIndex);
        }
      });
    }
    .width('100%')
    .padding({ bottom: 6 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      }));
  }
}
