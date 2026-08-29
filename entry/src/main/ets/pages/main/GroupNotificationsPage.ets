import { router, promptAction } from '@kit.ArkUI';
import { ChatEntry, effectiveMuted } from '../../store/ChatEntry';
import { getChatStore } from '../../tdkit/Globals';
import { MUTE_LONG, setMute, useDefaultMute } from '../../store/ChatActions';
import {
  SCOPE_CHANNEL, SCOPE_GROUP, ScopeSettings, getScopeSettings
} from '../../store/NotificationApi';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { contentSideGutter } from '../../util/contentWidth';

const CARD_RADIUS: number = 14;
const UNDO_VISIBLE_MS: number = 10000;
const SIDE_PADDING: number = 12;
// 服务端对通知设置变更有限流：短时间内连续改多个会话会被拒，TDLib 先本地
// 生效、约 400ms 后回退。回退是静默的（没有错误回传给调用方），所以这里
// 自己核对结果，超时仍未生效就明确告诉用户，而不是让行莫名其妙弹回去。
const MUTE_VERIFY_MS: number = 2500;

// 撤销一次静音切换所需的全部信息。usedDefault 必须记 —— 原本"跟随默认"的会话
// 直接回写 setMute 会留下一条显式设置，和撤销前并不等价。
interface UndoTarget {
  chatId: number;
  title: string;
  usedDefault: boolean;
  wasMuted: boolean;
  nowMuted: boolean;
}

// 群组/频道的通知总览：按「会响」和「已静音」分两组，点一下即切换，
// 行会立刻移动到另一组，底部浮出可撤销的提示。
@Entry
@Component
struct GroupNotificationsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 分组结果直接存成状态，而不是渲染时现算 —— @Builder 的值参数不会随数据
  // 变化重新求值，把数组当参数传进去点了不会重排（这一版的真正病根）。
  @State openRows: ChatEntry[] = [];
  @State mutedRows: ChatEntry[] = [];
  private chats: ChatEntry[] = [];
  @State groupScopeMuted: boolean = false;
  @State channelScopeMuted: boolean = false;
  @State scopesLoaded: boolean = false;
  @State query: string = '';
  @State undoTarget: UndoTarget | null = null;
  private unsubscribe: (() => void) | null = null;
  private undoTimer: number = -1;
  private verifyTimer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.unsubscribe = getChatStore().subscribeChanges((): void => this.refresh());
    this.loadScopes();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    this.clearUndoTimer();
    if (this.verifyTimer !== -1) {
      clearTimeout(this.verifyTimer);
      this.verifyTimer = -1;
    }
  }

  private clearUndoTimer(): void {
    if (this.undoTimer !== -1) {
      clearTimeout(this.undoTimer);
      this.undoTimer = -1;
    }
  }

  private loadScopes(): void {
    Promise.all([getScopeSettings(SCOPE_GROUP), getScopeSettings(SCOPE_CHANNEL)])
      .then((values: ScopeSettings[]): void => {
        this.groupScopeMuted = values[0].muted;
        this.channelScopeMuted = values[1].muted;
        this.scopesLoaded = true;
        this.regroup();
      })
      .catch((): void => {
        // 读不到默认值就按"未静音"处理：宁可把跟随默认的会话显示在"会响"里，
        // 也好过反过来让用户以为自己已经静音了。
        this.scopesLoaded = true;
      });
  }

  private refresh(): void {
    this.chats = getChatStore().allEntries().filter((e: ChatEntry): boolean =>
      e.kind === 'basicGroup' || e.kind === 'supergroup' || e.kind === 'channel');
    this.regroup();
  }

  private regroup(): void {
    const q = this.query.trim().toLowerCase();
    const open: ChatEntry[] = [];
    const muted: ChatEntry[] = [];
    for (const e of this.chats) {
      if (q !== '' && !e.title.toLowerCase().includes(q)) {
        continue;
      }
      if (this.isMuted(e)) {
        muted.push(e);
      } else {
        open.push(e);
      }
    }
    const byTitle = (a: ChatEntry, b: ChatEntry): number => a.title.localeCompare(b.title);
    this.openRows = open.sort(byTitle);
    this.mutedRows = muted.sort(byTitle);
  }

  private isMuted(entry: ChatEntry): boolean {
    const scopeMuted: boolean =
      entry.kind === 'channel' ? this.channelScopeMuted : this.groupScopeMuted;
    return effectiveMuted(entry, scopeMuted);
  }

  private toggle(entry: ChatEntry): void {
    const wasMuted: boolean = this.isMuted(entry);
    const target: UndoTarget = {
      chatId: entry.id, title: entry.title,
      usedDefault: entry.usesDefaultMute, wasMuted, nowMuted: !wasMuted
    };
    setMute(entry.id, wasMuted ? 0 : MUTE_LONG);
    this.verifyApplied(entry.id, !wasMuted);
    this.showUndo(target);
  }

  // 核对设置是否真的落地。没落地的唯一已知原因是服务端限流，隔一会儿重试即可。
  private verifyApplied(chatId: number, expectMuted: boolean): void {
    if (this.verifyTimer !== -1) {
      clearTimeout(this.verifyTimer);
    }
    this.verifyTimer = setTimeout((): void => {
      this.verifyTimer = -1;
      const entry = this.chats.find((e: ChatEntry): boolean => e.id === chatId);
      if (entry === undefined || this.isMuted(entry) === expectMuted) {
        return;
      }
      promptAction.showToast({
        message: $r('app.string.gn_rate_limited'), duration: 2600
      });
    }, MUTE_VERIFY_MS);
  }

  private showUndo(target: UndoTarget): void {
    this.clearUndoTimer();
    animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.undoTarget = target;
    });
    this.undoTimer = setTimeout((): void => {
      this.undoTimer = -1;
      animateTo({ duration: 180, curve: Curve.EaseIn }, (): void => {
        this.undoTarget = null;
      });
    }, UNDO_VISIBLE_MS);
  }

  private undo(): void {
    const target = this.undoTarget;
    if (target === null) {
      return;
    }
    this.clearUndoTimer();
    if (target.usedDefault) {
      useDefaultMute(target.chatId);
    } else {
      setMute(target.chatId, target.wasMuted ? MUTE_LONG : 0);
    }
    animateTo({ duration: 180, curve: Curve.EaseIn }, (): void => {
      this.undoTarget = null;
    });
  }

  @Builder
  chatRow(entry: ChatEntry, muted: boolean) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: entry.avatarPath, initials: entry.initials,
        colorSeed: entry.id, avatarSize: 40
      });
      Column({ space: 3 }) {
        Text(entry.title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(entry.kind === 'channel' ? $r('app.string.gn_channel') : $r('app.string.gn_group'))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      // 图标带底色圆角块，点击目标更明确，也让两种状态一眼可分。
      Row() {
        SymbolGlyph($r(muted ? 'sys.symbol.bell_slash_fill' : 'sys.symbol.bell_fill'))
          .fontSize(17)
          .fontColor([muted ? COLOR_ICON_SECONDARY : Color.White]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(muted ? COLOR_PAGE_BG : COLOR_PRIMARY);
    }
    .width('100%').height(62).padding({ left: 14, right: 14 })
    .accessibilityText(str('a11y_labeled_state', entry.title, muted ? str('gn_muted_tap_unmute') : str('gn_unmuted_tap_mute')))
    .onClick((): void => this.toggle(entry));
  }

  // 两个分组都是无参 @Builder，直接读 @State —— 一旦把数组当参数传进 @Builder，
  // 值参数就不会随数据变化重新求值，点击后列表不重排（"点了没反应"的病根）。
  // 所以这里宁可重复一遍结构，也不抽公共的带参 builder。
  @Builder
  openSection() {
    Column() {
      Row() {
        Text($r('app.string.gn_notifications_on')).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(`${this.openRows.length}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%').padding({ left: 14, right: 14, top: 14, bottom: 6 });
      if (this.openRows.length === 0) {
        Text($r('app.string.gn_none_unmuted')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 14, right: 14, top: 4, bottom: 14 });
      } else {
        ForEach(this.openRows, (entry: ChatEntry) => {
          this.chatRow(entry, false);
        }, (entry: ChatEntry) => `open_${entry.id}_${entry.revision}`);
      }
    }
    .width('100%').padding({ bottom: 6 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  mutedSection() {
    Column() {
      Row() {
        Text($r('app.string.gn_muted')).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(`${this.mutedRows.length}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%').padding({ left: 14, right: 14, top: 14, bottom: 6 });
      if (this.mutedRows.length === 0) {
        Text($r('app.string.gn_none_muted')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 14, right: 14, top: 4, bottom: 14 });
      } else {
        ForEach(this.mutedRows, (entry: ChatEntry) => {
          this.chatRow(entry, true);
        }, (entry: ChatEntry) => `muted_${entry.id}_${entry.revision}`);
      }
    }
    .width('100%').padding({ bottom: 6 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  undoBar() {
    Row({ space: 12 }) {
      Text(this.undoTarget!.nowMuted
        ? str('gn_muted_toast', this.undoTarget!.title)
        : str('gn_unmuted_toast', this.undoTarget!.title))
        .fontSize(14).fontColor(Color.White).layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      Text($r('app.string.undo')).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#5AC8FA')
        .padding({ left: 8, right: 4, top: 6, bottom: 6 })
        .onClick((): void => this.undo());
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#E6202020')
    .borderRadius(12)
    .transition(TransitionEffect.translate({ y: 40 }).combine(TransitionEffect.OPACITY));
  }

  build() {
    // 外层 Stack 让撤销条浮在列表之上；容器用 Transparent 命中模式，
    // 这样浮条以外的区域照常可以滚动和点击，不打断正在进行的操作。
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
          }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
          .onClick((): void => { router.back(); });
          Text($r('app.string.gn_title')).fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        }.width('100%').height(52).padding({ left: 8, right: 16 })
        .alignItems(VerticalAlign.Center);

        // 搜索框宽度交给外层 padding 决定，自己不再同时设 width('100%') 和
        // margin —— 两者叠加会超出父容器宽度，右边被裁掉。
        Row() {
          Search({ value: this.query, placeholder: $r('app.string.gn_search') })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(COLOR_SURFACE)
            .borderRadius(20)
            .onChange((value: string): void => { this.query = value; this.regroup(); });
        }
        .width('100%')
        // 搜索框在 Scroll 外面，得自己吃同一份留白，否则内容列收窄了它还
        // 通栏，两者左右对不齐。手机上 contentSideGutter 恒为 0。
        .padding({
          left: SIDE_PADDING + contentSideGutter(this.screenW),
          right: SIDE_PADDING + contentSideGutter(this.screenW),
          bottom: 10
        });

        if (!this.scopesLoaded) {
          Column({ space: 9 }) {
            LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
            Text($r('app.string.gn_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          Scroll() {
            Column({ space: 12 }) {
              this.openSection();
              this.mutedSection();
              // One key, not two joined: the split was a source-line wrap, and
              // a sentence assembled from fragments cannot be translated.
              Text($r('app.string.gn_note'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
            }
            .width('100%')
            // 限宽做在内容列的内边距上而不是 Scroll 的宽度上：Scroll 仍铺满
            // 窗口，两侧留白还在它的命中区里，按在留白上照样能滚列表。
            .padding({
              left: SIDE_PADDING + contentSideGutter(this.screenW),
              right: SIDE_PADDING + contentSideGutter(this.screenW),
              bottom: this.bottomSafe + 90
            });
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top);
        }
      }
      .width('100%').height('100%')
      // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
      // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe })
      .backgroundColor(COLOR_PAGE_BG);

      if (this.undoTarget !== null) {
        Column() {
          this.undoBar();
        }
        .width('100%')
        // 撤销条浮在列表之上，同样跟着内容列收窄，否则它比正在撤销的那一行还宽。
        .padding({
          left: SIDE_PADDING + contentSideGutter(this.screenW),
          right: SIDE_PADDING + contentSideGutter(this.screenW),
          bottom: this.bottomSafe + 12
        })
        .hitTestBehavior(HitTestMode.Transparent);
      }
    }
    .width('100%').height('100%');
  }
}
