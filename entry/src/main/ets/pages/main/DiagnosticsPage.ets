import { promptAction } from '@kit.ArkUI';
import { HdsSubDestination } from '../common/HdsSubDestination';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { KEY_CRASH_UPLOAD, setBoolean, setNumber } from '../../store/AppSettings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { str } from '../../util/strings';
import { diagLogSize } from '../../util/log';
import { DiagUploadResult, diagUploadConfigured, uploadDiagLog } from '../../services/diagLog';
import { common } from '@kit.AbilityKit';
import { exportDiagLog, diagLogStamp } from '../../util/diagLogExport';
// ⚠️ 临时：Repeat 渲染验证页的入口，验完连同本行 import 一起删除（见
// pages/chat/RepeatSpikePage.ets 文件头的删除清单）。
import { navigateToSetting } from '../../util/settingsNav';
// ⚠️ 临时（P6 标定）：cachedCount 档位切换器，标定结束后连同本行 import 一起
// 删除（清单见 util/debugListPerf.ets 文件末尾）。
import {
  KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT, LIST_CACHED_COUNT_OPTIONS
} from '../../util/debugListPerf';

const CARD_RADIUS: number = 14;

// 设置 → 日志与诊断。
//
// 两件事在这里，而且**性质完全不同**，页面上也要让用户看得出区别：
//
//   崩溃上报  自动。崩了下次启动补发；起不来时系统在 30 分钟后单独唤起
//             FaultLogExtensionAbility 上报。载荷里没有任何聊天内容，所以
//             默认开、用户不必操心。
//   运行日志  **只有用户点这个按钮才发**。它含 [StoreDiag] 那类消息编号，属于
//             使用痕迹，不能自动上传。
//
// 备注框比日志本身更值钱："我点了转发之后就白屏了"这一句，往往一眼就把范围
// 缩到几十行代码；而没有它，几万行日志只能从头看。

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function DiagnosticsPageBuilder(): void {
  DiagnosticsPage();
}

@Component
export struct DiagnosticsPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(LANGUAGE_EPOCH) languageEpoch: number = 0;
  @StorageProp(KEY_CRASH_UPLOAD) crashUpload: boolean = true;
  // ⚠️ 临时（P6 标定）：当前 cachedCount 档位。@StorageProp 而不是 @State ——
  // 写入方是 AppSettings.setNumber，界面上的选中态必须跟着 AppStorage 走。
  @StorageProp(KEY_DEBUG_LIST_CACHED) listCached: number = LIST_CACHED_COUNT_DEFAULT;
  @State private note: string = '';
  @State private sending: boolean = false;
  // 日志体积只在进页面时算一次：collectAll 会把内存里的部分刷进磁盘再整份读
  // 回来，挂在 build 上等于每帧读一次文件。
  @State private logBytes: number = 0;

  aboutToAppear(): void {
    this.logBytes = diagLogSize();
  }

  private sizeText(): string {
    const kb: number = Math.round(this.logBytes / 1024);
    return kb >= 1024 ? `${(kb / 1024).toFixed(1)} MB` : `${kb} KB`;
  }

  private sendLog(): void {
    if (this.sending) {
      return;
    }
    if (!diagUploadConfigured()) {
      promptAction.showToast({ message: $r('app.string.diag_not_configured'), duration: 2000 });
      return;
    }
    this.sending = true;
    uploadDiagLog(this.note.trim(), '').then((result: DiagUploadResult): void => {
      this.sending = false;
      if (result.ok) {
        this.note = '';
        promptAction.showToast({ message: $r('app.string.diag_sent'), duration: 1800 });
      } else {
        promptAction.showToast({
          message: str('diag_send_failed', result.reason), duration: 2400
        });
      }
    });
  }

  @Builder
  crashCard() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text($r('app.string.diag_crash_upload'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.diag_crash_upload_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: this.crashUpload })
        .selectedColor(COLOR_PRIMARY)
        .onChange((next: boolean): void => { setBoolean(KEY_CRASH_UPLOAD, next); });
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  logCard() {
    Column() {
      TextArea({ text: this.note, placeholder: $r('app.string.diag_note_hint') })
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .backgroundColor(Color.Transparent)
        .constraintSize({ minHeight: 76, maxHeight: 140 })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .onChange((value: string): void => { this.note = value; });
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text($r('app.string.diag_send_log'))
            .fontSize(16).fontColor(this.sending ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY)
            .fontWeight(FontWeight.Medium);
          // 把体积摆出来：用户按下之前有权知道要发多少东西出去。
          Text(this.sizeText()).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (this.sending) {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
          Text($r('app.string.diag_sending')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        } else {
          SymbolGlyph($r('sys.symbol.arrow_up_circle'))
            .fontSize(21).fontColor([COLOR_PRIMARY]);
        }
      }
      .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .enabled(!this.sending)
      .onClick((): void => { this.sendLog(); });

      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      // 导出到本地。上传依赖网络，用户反馈网络差时反复失败，而那正是最需要
      // 看日志的时候（issue #89）。导出之后用他自己顺手的方式发出来即可。
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text($r('app.string.diag_export'))
            .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          Text($r('app.string.diag_export_sub'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(21).fontColor([COLOR_PRIMARY]);
      }
      .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        exportDiagLog(getContext(this) as common.UIAbilityContext, diagLogStamp(new Date()));
      });
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  // ⚠️ 临时（P6 标定）：聊天详情页 List 的 cachedCount 档位切换器。
  //
  // 存在的理由：在它之前，换一档 = 改常量 → 编译 → 装机 → 应用回到会话列表 →
  // 重新进会话 → 抓 trace，一轮十几分钟且极易操作失误。标定结束后删除。
  //
  // 立即生效的链路：这里 setNumber → AppStorage → ChatPageChrome 的
  // @StorageProp → ChatPage 的 @Param listCachedCount → .cachedCount() 重新
  // 求值。会话页在导航栈里活着也照样收到，不需要重进会话、更不需要重启。
  @Builder
  listCachedCard() {
    Column({ space: 8 }) {
      Column({ space: 3 }) {
        Text($r('app.string.diag_list_cached'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.diag_list_cached_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start).width('100%');
      Row({ space: 8 }) {
        ForEach(LIST_CACHED_COUNT_OPTIONS, (option: number): void => {
          Text(`${option}`) // i18n-exempt: numeric debug value, not copy
            .fontSize(15)
            .fontColor(this.listCached === option ? Color.White : COLOR_TEXT_PRIMARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.listCached === option ? COLOR_PRIMARY : COLOR_PAGE_BG)
            .borderRadius(10)
            .onClick((): void => { setNumber(KEY_DEBUG_LIST_CACHED, option); });
        }, (option: number): string => `${option}`);
      }
      .width('100%');
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  // ⚠️ 临时：Repeat 渲染验证页的入口，验完删除（P4 / R1）。
  @Builder
  repeatSpikeCard() {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text($r('app.string.diag_repeat_spike'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.diag_repeat_spike_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    // 设置栈的推进漏斗。origin 恒为 'navbar' ⇒ clearAndPush，所以从验证页
    // 返回时回到的是设置列表而不是诊断页——临时页面，不为它改路由语义。
    .onClick((): void => { navigateToSetting('RepeatSpikePage'); });
  }

  build() {
    // @Entry 的 build 根节点必须是容器组件，自定义组件不行。
    // 【迁移后】@Entry 已经摘掉，这条约束对本页不再成立；外层 Column 仍然留着，
    // 因为它不带任何样式，删不删对渲染没有区别，留着可以让 diff 只有必须的几行。
    Column() {
      HdsSubDestination({
        title: $r('app.string.diag_title'),
        pageBackground: COLOR_PAGE_BG,
        scroller: this.hdsScroller
      }) {
        Scroll(this.hdsScroller) {
          Column({ space: 12 }) {
            this.crashCard();
            this.logCard();
            Text($r('app.string.diag_privacy_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
              .width('100%').padding({ left: 14, right: 14 });
            // ⚠️ 临时调试入口 —— **验完删除**。挂在诊断页最底下而不是设置页，
            // 是因为这里本来就是这个应用的调试角落。
            this.repeatSpikeCard();
            // ⚠️ 临时调试项 —— 标定完删除。同一个调试角落。
            this.listCachedCard();
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
        }
        .align(Alignment.Top)
        .width('100%').scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 不裁剪，内容才能穿到标题栏底下。
        .clip(false);
      }
    }.width('100%').height('100%');
  }
}
