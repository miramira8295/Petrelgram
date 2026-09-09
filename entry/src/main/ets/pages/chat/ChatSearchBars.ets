import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  SEARCH_LABEL_COUNTER, SEARCH_LABEL_NONE,
  canStepNewer, canStepOlder, hashtagQueryOf, searchCounterText, searchLabelKind
} from '../../util/searchPaging';
import { CHAT_SEARCH_HEADER_BASE_HEIGHT } from '../../util/ChatChromeGeometry';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
import {
  BOTTOM_PILL_GAP, BOTTOM_PILL_HEIGHT, BOTTOM_PILL_PADDING, bottomPillRadius
} from '../../util/bottomPill';
import { str } from '../../util/strings';
import { SearchSession } from './SearchSession';

// 会话内搜索的两条：顶上的输入框、底下的计数与上下翻。
//
// 从 ChatPage 搬出来。搜索态下这两条**同时**替换掉常规顶栏和输入区，是同一个
// 特性的两半，所以放一个文件里。
//
// 全部动作回调给页面：翻页要碰 TDLib 分页、跳转要碰 scroller 和高亮。
// 翻页决策与两个箭头的亮灭在 util/searchPaging（有单测）。
//
// 状态管理 V2（B2 批：ChatPage 组合的几个 V1 宿主统一迁 @ComponentV2）。迁移的
// 理由不是「顺手统一」而是前置条件：V1 的 @Component 既不能声明 @Param、也订阅
// 不了 @ObservedV2 的 @Trace，后面那一步「宿主接收 SearchSession 控制器、在自己
// 的 build() 里读 @Trace，把搜索键入的重渲染半径从 ChatPage 缩到这两条」就无从
// 谈起。本批本身不追求任何性能收益，只求零行为变更地把体系换过来。
//
// 迁移前逐条核对过：本文件没有 @StorageProp（V2 里不存在的东西），也没有
// @Watch；组件内部对自己的入参一次赋值都没有（@Param 只读这条约束在这里不产生
// 任何改动）。两个 build() 里渲染的全是内置组件（Row / TextInput / SymbolGlyph
// / Text / Blank），一个自定义子组件都没有，因此不触碰「V2 普通组件 → V1
// @Reusable 复用组件」那条会**静默失败**（整块 UI 一个节点都不建）的混用禁区。
//
// 【B6 落地】上一段说的"后面那一步"就是这次：query/loadedCount/total/
// currentIndex 四个标量 @Param 收成一个 `@Require @Param search: SearchSession`
// 引用，两个 build() 直接读 this.search.xxx。topSafe/bottomGap 不属于搜索簇
// （几何/键盘让位相关），全部 @Event（跨簇动作回调，恒新闭包、不具备观测能力）
// 原样保留，都不进这次替换。
//
// 【为什么值得换】改前这四个值住在 ChatPage 的 @Local 里：搜索框敲一个字，先要
// 重跑页面 chatTitleBar 闭包把 query/loadedCount/total/currentIndex 都重新算
// 一遍，再逐个做 4 次 @Param 比较，才轮到这两条本身重绘。改后本组件直接持有
// SearchSession 控制器引用、在自己的 build()/@Builder 里读 @Trace：敲一个字
// 只刷新这里读到它的那个 TextInput 或计数/翻页节点，ChatPage 一个字都不读，
// 4 次比较也一起消失——只把字段搬进控制器、读点还留在页面的话收益就只有行数，
// 这两个 struct 必须改成直读才是真正缩小重渲染半径的地方。

@ComponentV2
export struct SearchHeader {
  // B6：query 不再是独立的标量 @Param，改成读 search.query（引用型
  // @Require @Param，见下面 search 字段）。搜索框仍然是
  // `text: this.search.query` 单向绑定 + onChange 把新值交回页面（页面调
  // this.search.updateQuery(v)），**不是** $$ 双向绑定——本组件从不写
  // this.search.query，这条约束原样保留，只是住的地方从裸标量换成了控制器上的
  // @Trace。
  @Require @Param search: SearchSession;
  @Param topSafe: number = 0;

  // 函数型入参一律 @Event：调用点传的是内联箭头函数，页面每重建一次都是一个新
  // 闭包，若留作 @Param，那个 `!==` 恒不相等会让本层跟着页面的每次重建白刷；
  // @Event 不具备观测能力，正好复现迁移前「普通字段只在构造时赋值一次」的行为。
  // 空实现默认值按仓库惯例保留，组件仍可脱离页面单独预览。
  @Event onExit: () => void = (): void => {};
  @Event onQueryChange: (value: string) => void = (): void => {};
  @Event onSubmit: () => void = (): void => {};

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.68)
  }

  build() {
    Row({ space: 4 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .onClick((): void => { this.onExit(); })
      .accessibilityText($r('app.string.cp_back_to_chat'));
      TextInput({ text: this.search.query, placeholder: $r('app.string.cp_search_messages') })
        .layoutWeight(1).height(40).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .defaultFocus(true)
        .onChange((v: string): void => { this.onQueryChange(v); })
        .onSubmit((): void => { this.onSubmit(); });
      if (this.search.query !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(19).fontColor([COLOR_ICON_SECONDARY]);
        }
        .width(34).height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.onQueryChange(''); })
        .accessibilityText($r('app.string.clear_search'));
      }
    }
    .width('calc(100% - 24vp)').height(CHAT_SEARCH_HEADER_BASE_HEIGHT - 16)
    .padding({ left: 3, right: 6 })
    .margin({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    // 【和下面那条控制条同一副材质】上一轮只迁了 SearchBottomBar，这条顶栏
    // 还留着实心底色——真机上底下透、上面不透，一眼就看得出不是一路
    // （用户 2026-09-08：「搜索的顶部搜索条还是标准的，不是 HDS 的光感」）。
    // 玻璃走自绘那一对，理由见 MembershipBar 文件头。
    //
    // ⚠️ **border 必须写在 borderRadius 之前**：`.border({width,color})` 不带
    // radius 时会把先前设过的 borderRadius 重置成 0（ScrollFab 那次真机事故就
    // 是这条），顺序反了整条会变成直角方块。
    .border({ width: 0.5, color: $r('app.color.divider') })
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .borderRadius(23)
    .backdropBlur(plainBackdropBlur('card'))
    .visualEffect(hdsVisualEffect('card'))
    .shadow({ radius: 5, color: '#16000000', offsetX: 0, offsetY: 1 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}

// 同上，B2 批迁 @ComponentV2。五个入参全是基本类型，@Prop → @Param 在基本类型
// 上等价；本组件同样一次都没写过自己的入参，裸 @Param 即可。
//
// B6：query/loadedCount/total/currentIndex 四个标量 @Param 收进一个
// `@Require @Param search: SearchSession` 引用——分别对应 search.query /
// search.results.length / search.total / search.idx，字段名与取值和搬之前
// 一一对应，只是住的地方从裸标量换成了控制器上的 @Trace。bottomGap 不属于
// 搜索簇（键盘/抽屉让位的几何量），原样保留。
@ComponentV2
export struct SearchBottomBar {
  @Require @Param search: SearchSession;
  // 输入区底部让出的高度，由页面按键盘/抽屉状态算好传进来。
  @Param bottomGap: number = 0;

  // 两个翻页动作同样一律 @Event（理由见 SearchHeader）。
  @Event onOlder: () => void = (): void => {};
  @Event onNewer: () => void = (): void => {};
  // 「在公开帖子中搜索」：跳全局搜索的帖子页签。要碰导航栈，所以同样交给页面。
  @Event onPublicPosts: (tag: string) => void = (_tag: string): void => {};

  // 胶囊里显示什么。三种情形各有一句话，**没有"什么都不显示"这一档**：
  //
  //   有结果   → 「第 n / 共 m 条」
  //   没结果   → 「没有找到相关消息」
  //   还没搜   → 「输入关键词搜索」
  //
  // 原来"没结果"那一支渲染的是 `Text('')`。在整条铺满的控制栏里看不出来；改成
  // 胶囊之后，空文本外面还裹着玻璃和内边距，就成了一颗悬在那儿的**空胶囊**
  // （用户 2026-09-08 实测）。给它一句明确的话，比留白或者整颗撤掉都好：
  // 撤掉的话用户分不清"搜完没有"和"还没开始搜"。
  @Builder
  label() {
    if (searchLabelKind(this.search.results.length, this.search.total, this.search.query) === SEARCH_LABEL_COUNTER) {
      Text(searchCounterText(this.search.idx, this.search.total))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    } else if (searchLabelKind(this.search.results.length, this.search.total, this.search.query) === SEARCH_LABEL_NONE) {
      Text($r('app.string.cp_search_no_result'))
        .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
    } else {
      Text($r('app.string.cp_search_placeholder'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    }
  }

  // 标签搜索的升级入口。只在关键词是 `#话题` / `$代码` 时出现——普通关键词
  // 走不了 TDLib 的公开帖子接口，那行摆着也点不出东西。
  //
  // 点标签现在先搜本会话（SearchSession.enterForQuery），"看全网"从这里走。
  @Builder
  publicPostsRow(tag: string) {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(15).fontColor([COLOR_PRIMARY]);
      // str() 而不是 $r()：$r 返回的是 Resource 对象，插进模板串会渲染成
      // [object Object]。
      Text(`${str('cp_search_public_posts')} ${tag}`)
        .fontSize(14).fontColor(COLOR_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([COLOR_PRIMARY]);
    }
    .width('100%').height(40)
    .padding({ left: 20, right: 14 })
    .alignItems(VerticalAlign.Center)
    // 分隔线画在下边：上边那条由外层 Column 统一出，免得两条叠在一起。
    .border({ width: { bottom: 0.7 }, color: $r('app.color.divider') })
    .onClick((): void => { this.onPublicPosts(tag); });
  }

  // 一颗圆钮。两个翻页键长得一样，只有图标/可用性/回调不同。
  @Builder
  stepButton(icon: Resource, enabled: boolean, bounce: boolean, action: () => void) {
    Row() {
      if (bounce) {
        SymbolGlyph(icon).fontSize(22).fontColor([COLOR_TEXT_PRIMARY])
          .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), true);
      } else {
        SymbolGlyph(icon).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
    }
    .width(BOTTOM_PILL_HEIGHT).height(BOTTOM_PILL_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .borderRadius(bottomPillRadius())
    .backdropBlur(plainBackdropBlur('card'))
    .visualEffect(hdsVisualEffect('card'))
    .opacity(enabled ? 1 : 0.4)
    .onClick((): void => { action(); });
  }

  build() {
    Column({ space: BOTTOM_PILL_GAP }) {
      // 标签搜索那一行仍然是整条——它是一句可点的话，切成胶囊会很怪。
      if (hashtagQueryOf(this.search.query) !== '') {
        Row() {
          this.publicPostsRow(hashtagQueryOf(this.search.query));
        }
        .width('100%')
        .backgroundColor(plainGlassFill($r('app.color.surface')))
        .borderRadius(22)
        .backdropBlur(plainBackdropBlur('card'))
        .visualEffect(hdsVisualEffect('card'))
        .clip(true);
      }
      // 【为什么不再是一整条平板】原来计数和两个箭头共处一条铺满的控制栏里，
      // 视觉上是块"板"。改成**内容宽的计数胶囊 + 两颗独立圆钮**：胶囊只占它
      // 需要的宽度，右边两颗圆钮各自成形，中间留空让壁纸透出来
      // （用户 2026-09-08：「显示总结果数量和定位，右侧两个圆形按钮上下跳转」）。
      Row({ space: BOTTOM_PILL_GAP }) {
        Row() {
          this.label();
        }
        .height(BOTTOM_PILL_HEIGHT)
        .padding({ left: BOTTOM_PILL_PADDING, right: BOTTOM_PILL_PADDING })
        .backgroundColor(plainGlassFill($r('app.color.surface')))
        .borderRadius(bottomPillRadius())
        .backdropBlur(plainBackdropBlur('card'))
        .visualEffect(hdsVisualEffect('card'))
        .alignItems(VerticalAlign.Center);

        Blank().layoutWeight(1);

        if (this.search.results.length > 0) {
          this.stepButton($r('sys.symbol.chevron_up'),
            canStepOlder(this.search.results.length, this.search.idx, this.search.total),
            false, (): void => { this.onOlder(); });
          this.stepButton($r('sys.symbol.chevron_down'),
            canStepNewer(this.search.idx),
            true, (): void => { this.onNewer(); });
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);
    }
    // **不能写 width('100%') + 左右 margin**：ArkUI 先按父容器 100% 算宽再加
    // 外边距，整条会比可用宽度还宽、两侧顶死（GifPicker 的搜索框上踩过；
    // SearchHeader 也是用 calc 解决的）。
    .width('calc(100% - 28vp)')
    .margin({ left: 14, right: 14 })
    .padding({ bottom: this.bottomGap });
  }
}
