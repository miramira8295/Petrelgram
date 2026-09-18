import { MusicCollection, MusicLibrarySummary, musicCollectionsSummary } from '../../util/musicCollectionModel';
import { musicEmptyTileFill, musicGlassBlur, musicGlassFill, musicKeyGradient } from '../../util/musicCenterStyle';
import { musicCoverColors, MusicCoverColors } from '../../util/musicTrackModel';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 「我的」页签：合集网格（设计稿 isMineGrid 那一段）。
//
// 两列，最后补一张虚线的「创建合集」卡。卡片自己不持有数据——合集从
// MusicCollectionStore 来，由 MusicCenterPage 传进来；这里只画。
//
// 【为什么不用 Grid】外面是一个 Scroll，Grid 嵌在可滚容器里要额外处理滚动传递，
// 而合集是用户手建的、数量以个位数计，两两成行的 ForEach 更省事也更好读。

const CARD_RADIUS: number = 22;
const CARD_MIN_HEIGHT: number = 150;
const TILE_SIZE: number = 30;
const TILE_GAP: number = 4;

@Component
export struct MusicCollectionsView {
  @Prop collections: MusicCollection[];
  onSelect: (collectionId: string) => void = (): void => {};
  onCreate: () => void = (): void => {};

  // 两两成行；单数时最后一行只有一张卡，另一半由「创建」卡补上。
  private rows(): MusicCollection[][] {
    const out: MusicCollection[][] = [];
    for (let i = 0; i < this.collections.length; i += 2) {
      out.push(this.collections.slice(i, i + 2));
    }
    return out;
  }

  private summaryLabel(): string {
    const summary: MusicLibrarySummary = musicCollectionsSummary(this.collections);
    return str('mc_collections_summary', summary.collections, summary.tracks);
  }

  // 卡片右上角那团光，取合集第一首歌的封面色；空合集用中性色。
  private glowColor(collection: MusicCollection): string {
    if (collection.trackKeys.length === 0) {
      return '#8A93A6';
    }
    const colors: MusicCoverColors = musicCoverColors(collection.trackKeys[0]);
    return colors.to;
  }

  @Builder
  tile(collection: MusicCollection, slot: number, size: number) {
    if (slot < collection.trackKeys.length) {
      Column().width(size).height(size).borderRadius(size / 4)
        .linearGradient(musicKeyGradient(collection.trackKeys[slot]));
    } else {
      Column().width(size).height(size).borderRadius(size / 4)
        .backgroundColor(musicEmptyTileFill());
    }
  }

  // 2×2 的马赛克。两行 Row 而不是 Flex 换行：Flex 的 space 要 LengthMetrics，
  // 而这里的格子数恒为四，写死两行更直白。
  @Builder
  tiles(collection: MusicCollection, size: number, gap: number) {
    Column({ space: gap }) {
      Row({ space: gap }) {
        this.tile(collection, 0, size);
        this.tile(collection, 1, size);
      }
      Row({ space: gap }) {
        this.tile(collection, 2, size);
        this.tile(collection, 3, size);
      }
    }
    .width(size * 2 + gap);
  }

  @Builder
  card(collection: MusicCollection) {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 光晕：卡片外的圆被裁掉一半，正是设计稿里那种"从角上透出来"的样子。
      Column()
        .width(110).height(110).borderRadius(55)
        .backgroundColor(this.glowColor(collection))
        .opacity(0.5)
        .blur(24)
        .offset({ x: 30, y: -30 });
      Column() {
        this.tiles(collection, TILE_SIZE, TILE_GAP);
        Column({ space: 2 }) {
          Text(collection.name)
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(str('mc_track_count', collection.trackKeys.length))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        }
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%').height('100%').padding(14)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween);
    }
    .layoutWeight(1).height(CARD_MIN_HEIGHT)
    .borderRadius(CARD_RADIUS)
    .clip(true)
    .backgroundColor(musicGlassFill())
    .backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: $r('app.color.divider') })
    .onClick((): void => { this.onSelect(collection.id); });
  }

  @Builder
  createCard() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.plus')).fontSize(26).fontColor([COLOR_TEXT_SECONDARY]);
      Text($r('app.string.mc_create_collection')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .layoutWeight(1).height(CARD_MIN_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(CARD_RADIUS)
    .border({ width: 1, color: $r('app.color.divider'), style: BorderStyle.Dashed })
    .onClick((): void => { this.onCreate(); });
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.mc_my_collections'))
            .fontSize(26).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text(this.summaryLabel()).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(16).fontColor([COLOR_TEXT_PRIMARY]);
          Text($r('app.string.mc_new_collection'))
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        }
        .height(36).padding({ left: 10, right: 14 }).borderRadius(18)
        .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
        .border({ width: 0.5, color: $r('app.color.divider') })
        .onClick((): void => { this.onCreate(); });
      }
      .width('100%').alignItems(VerticalAlign.Bottom);

      Column({ space: 12 }) {
        ForEach(this.rows(), (row: MusicCollection[], index: number): void => {
          Row({ space: 12 }) {
            ForEach(row, (collection: MusicCollection): void => {
              this.card(collection);
            }, (collection: MusicCollection): string => collection.id);
            // 这一行只有一张卡时，"创建"卡正好补上右半边。
            if (row.length === 1 && index === this.rows().length - 1) {
              this.createCard();
            }
          }
          .width('100%').alignItems(VerticalAlign.Top);
        }, (row: MusicCollection[], index: number): string => `row-${index}-${row.length}`);
        // 合集是偶数张（含一张都没有）时，"创建"卡自己占一行的左半边。
        if (this.collections.length % 2 === 0) {
          Row({ space: 12 }) {
            this.createCard();
            Column().layoutWeight(1);
          }
          .width('100%').alignItems(VerticalAlign.Top);
        }
      }
      .width('100%').margin({ top: 18 });
    }
    .width('100%');
  }
}
