import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { ForumTopicRow } from '../../util/forumTopicModel';
import { guardKey } from '../../util/keyGuard';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';

// 聊天详情页顶栏里的话题横条（2026-09-16）。
//
// 【形态】与首页文件夹条同一种控件，所以尺寸也照抄它，不另编数字：
// 条高 36（CHAT_TOPIC_BAR_HEIGHT / FOLDER_BAR_HEIGHT）、胶囊高 28、左右内边距 7、
// 右外边距 6、圆角取半高、未选态铺一层 material_tint、选中态用主色。
// 它挂在标题行下面的 bottomBuilder 槽里。**那个槽本身不提供玻璃**——置顶条/直播条
// 那张浮卡的质感是 TopBanners 自绘的（plainGlassFill + plainBackdropBlur +
// hdsVisualEffect('bar')）。我第一版误以为槽会给玻璃、本组件什么背板都没画，结果横条
// 是裸的、消息直接从下面透上来（用户 2026-09-16：「这个横条没有顶部的玻璃质感」）。
// 现在照 TopBanners 同一套自绘：半透明底 + backdropBlur 一起上（不透明底会把模糊盖死），
// 圆角与左右外边距也与那张浮卡对齐，视觉上是并列的两张卡。
//
// 【为什么是 LazyForEach 而不是 ForEach】大话题群有上百个话题（getForumTopics 一次取
// 100）。ForEach 会把每一格都建出来——今天刚在查看器缩略图条上付过这笔账
// （见 util/viewerFilmstrip 的文件头）。
//
// 【为什么胶囊没有 aboutToRecycle/aboutToReuse】今天那条教训的前提是**组件建立了需要
// 撤销的东西**（旁路订阅、定时器、原生 handle）。这一格只画文字和角标，不持有任何这类
// 资源，@Param 换值就够了。别机械照搬钩子——挂了反而多一层没有意义的生命周期。

// 槽里给这条留的高度（= CHAT_TOPIC_BAR_HEIGHT）。卡片本身矮 2，剩下的是与下面那张
// 浮卡之间的呼吸位——和 TopBanners 的 margin bottom 2 对齐。
const BAR_HEIGHT: number = 36;
const CARD_HEIGHT: number = 34;
const CHIP_HEIGHT: number = 28;

@ReusableV2
@ComponentV2
struct TopicPill {
  @Require @Param row: ForumTopicRow;
  @Param selected: boolean = false;
  @Event onTap: (threadId: number) => void = (_id: number): void => {};
  @Event onLongPress: (threadId: number) => void = (_id: number): void => {};

  build() {
    Row({ space: 5 }) {
      // 话题图标色是 TDLib 给的六色之一，用一个小圆点表达，不抢文字。
      Circle({ width: 6, height: 6 }).fill(this.row.iconColor);
      Text(this.row.name)
        .fontSize(14)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 120 });
      if (this.row.unreadCount > 0) {
        Text(this.row.unreadCount > 99 ? '99+' : `${this.row.unreadCount}`)
          .fontSize(10).fontColor(Color.White)
          .padding({ left: 5, right: 5 })
          .height(16).borderRadius(8)
          .backgroundColor(COLOR_PRIMARY);
      }
    }
    .height(CHIP_HEIGHT)
    .padding({ left: 7, right: 7 })
    .borderRadius(CHIP_HEIGHT / 2)
    // 未选项一层轻量 tint；选中项用主色描边表达，避免和顶栏玻璃打架。
    .backgroundColor(this.selected ? Color.Transparent : $r('app.color.material_tint'))
    .border({ width: this.selected ? 1.5 : 0, color: COLOR_PRIMARY })
    .onClick((): void => { this.onTap(this.row.threadId); })
    .gesture(LongPressGesture().onAction((): void => { this.onLongPress(this.row.threadId); }));
  }
}

@ComponentV2
export struct ChatTopicBar {
  // 数据源由 ChatPage 维护（store 的行 → update(items, ids, keys)）。
  @Require @Param source: KeyedListDataSource<ForumTopicRow>;
  // 当前所在话题，就是 ChatPage 的 forumTopicId。
  @Param selectedThreadId: number = 0;
  @Event onSelect: (threadId: number) => void = (_id: number): void => {};
  // 横条自己的滚动控制器由页面持有：切话题后要把选中项滚到可见处。
  @Require @Param scroller: Scroller;
  // 话题条目数。**必须监听它**：首次进入时话题列表还没回来、数据源是空的，
  // 那时即使选中项已经定了也找不到下标；等列表到齐、行数一变才滚得动。
  @Param rowCount: number = 0;
  // 允许用户自己建/删话题（目前只有 Bot 私聊的话题模式，issue #206）：末尾给一个「+」，
  // 长按胶囊才往上报。不允许时长按什么也不做。
  @Param canCreate: boolean = false;
  @Event onCreate: () => void = (): void => {};
  @Event onLongPressTopic: (threadId: number) => void = (_id: number): void => {};

  aboutToAppear(): void {
    this.scrollSelectedIntoView();
  }

  // ⚠️ 名字必须与上面的 @Param 逐字一致：写错了 ArkUI 既不报错也不告警，
  // 自愈会静默失效（本仓有前科）。
  @Monitor('selectedThreadId', 'rowCount')
  onSelectionChanged(): void {
    this.scrollSelectedIntoView();
  }

  private indexOfSelected(): number {
    const total: number = this.source.totalCount();
    for (let i = 0; i < total; i++) {
      if (this.source.getData(i).threadId === this.selectedThreadId) {
        return i;
      }
    }
    return -1;
  }

  // 把选中的胶囊滚到中间。
  //
  // 【下一帧再滚】刚变更这一帧 LazyForEach 可能还没建出目标格，量不到位置。
  // 【不能用 smooth】懒加载列表上带动画的 scrollToIndex 要一项项走过去，屏幕上
  // 就是"从头滚到尾"——今天刚在查看器缩略图条上付过这笔账。
  private scrollSelectedIntoView(): void {
    setTimeout((): void => {
      const index: number = this.indexOfSelected();
      if (index < 0) {
        return;
      }
      try {
        this.scroller.scrollToIndex(index, false, ScrollAlign.CENTER);
      } catch (e) {
        // 条还没挂上（切组的同一帧）时会抛，下一次选中变化会再来一次。
      }
    }, 0);
  }

  build() {
    List({ space: 6, scroller: this.scroller }) {
      LazyForEach(this.source, (row: ForumTopicRow) => {
        ListItem() {
          TopicPill({
            row: row,
            selected: row.threadId === this.selectedThreadId,
            onTap: (threadId: number): void => { this.onSelect(threadId); },
            onLongPress: (threadId: number): void => {
              if (this.canCreate) {
                this.onLongPressTopic(threadId);
              }
            }
          })
            .reuse({ reuseId: (): string => 'topic' });
        }
      }, (row: ForumTopicRow, index: number): string =>
        guardKey(this.source.keyTableId, index,
          `${row.threadId}|${row.name}|${row.unreadCount}|${row.isPinned}`));
      // 放在末尾而不是开头：开头多一格会让 scrollSelectedIntoView 按数据源算出的下标错一位。
      if (this.canCreate) {
        ListItem() {
          Row() {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(16).fontColor([COLOR_PRIMARY]);
          }
          .width(CHIP_HEIGHT).height(CHIP_HEIGHT)
          .borderRadius(CHIP_HEIGHT / 2)
          .backgroundColor($r('app.color.material_tint'))
          .justifyContent(FlexAlign.Center)
          .accessibilityText($r('app.string.ft_new_topic'))
          .onClick((): void => { this.onCreate(); });
        }
      }
    }
    .listDirection(Axis.Horizontal)
    .width('100%').height(CARD_HEIGHT)
    // 首尾留白走 contentStartOffset/EndOffset，**不能用容器 padding**：padding 只影响
    // 初始布局，内容一滚就滚进 padding 区，再叠上 clip(true) 就是胶囊贴着卡片边缘
    // （用户 2026-09-16：「两侧顶边了」）。SDK 对这两个属性的定义是「内容起点/终点到
    // 显示区边界的偏移」，沿**主轴**——横向时正是左右，跟着内容走。
    .contentStartOffset(8)
    .contentEndOffset(8)
    // 交叉轴对齐默认是 Start，而横向 List 的交叉轴就是垂直方向：28 高的胶囊会贴在
    // 34 高的卡片顶部、底下空 6（用户：「胶囊上下不剧中」）。
    .alignListItem(ListItemAlign.Center)
    .scrollBar(BarState.Off)
    .cachedCount(4)
    // 与置顶条那张浮卡同一档 'bar' 玻璃：半透明底 + backdropBlur 必须一起上。
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .backdropBlur(plainBackdropBlur('bar'))
    .borderRadius(14)
    .margin({ left: 12, right: 12, bottom: BAR_HEIGHT - CARD_HEIGHT })
    .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 1 })
    .clip(true)
    .visualEffect(hdsVisualEffect('bar'));
  }
}
