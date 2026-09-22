import { promptAction } from '@kit.ArkUI';
import { getChatStore, getTdClient, getUserStore } from '../../tdkit/Globals';
import { MessageStore } from '../../store/MessageStore';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { monthDayTime } from '../../util/intlFormat';
import { PinnedEntry, pinnedCountLabel } from '../../util/pinnedEntry';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { pushSheetDismiss } from '../../util/sheetDismissStack';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 「全部置顶消息」面板。置顶条右边那个图标按钮打开它。
//
// 【为什么数据不自己拉】MessageStore.resolvePinned 已经按当前作用域（会话 /
// 论坛话题 / 频道私信 topic）取过一页置顶，并且挂在 updateMessageIsPinned 上
// 随时更新。面板再发一次 searchChatMessages 就要把那段话题过滤逻辑抄第二份——
// 两份迟早会分叉，而分叉的后果是"面板里列出的和取消全部置顶实际删掉的不是同
// 一批"。这里只订阅 store，取消置顶之后列表自己就更新了。
//
// 【为什么要单独问一次 can_be_pinned】管理动作（单条取消置顶、取消全部置顶）
// 只对有权限的人显示。本仓没有现成的"我在这个会话能不能置顶"信号：
// MembershipSession 只解析出输入框能不能用，不看 can_pin_messages。td 给了权威
// 答案——getMessageProperties.can_be_pinned，它算的就是会话级的置顶权
// （创建者/管理员权限/群默认权限/被限制成员各自那份都在里面）。**这是本地
// 计算的一次 IPC 往返，不是网络请求**（同 util/messageEditable 那次的结论）。
// 问任意一条置顶消息都行，这里问最新的那条。
//
// 【默认不给权限】答案没回来之前 canManage 保持 false：多显示一个按钮再报
// "没有置顶权限"，比误把不可撤销的批量操作摆在普通成员面前要好。
@Component
export struct PinnedListSheet {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // 单向入 + 回调出，不用 @Link：@Link 只能被 V1 状态变量初始化，而宿主
  // ChatOverlayHost 是 @ComponentV2（同 ScheduledSheet 的做法）。
  @Prop show: boolean;
  onShowChange: (show: boolean) => void = (): void => {};
  chatId: number = 0;
  store: MessageStore | null = null;
  // 点一条 → 关面板并把定位交回页面（页面拥有 scroller 与 pendingJumpId）。
  onJump: (messageId: number) => void = (): void => {};

  @State entries: PinnedEntry[] = [];
  // 与 entries 逐位对齐的发送者名字。UserStore 是异步补全的，名字缺的那几个
  // 单独补一次 getUser，回来再按下标填进去。
  @State names: string[] = [];
  @State loadState: string = 'loading';
  @State canManage: boolean = false;

  // 进/出场动画。面板自己驱动，不靠 .transition()：宿主是用 `if` 挂载的，
  // 退场动画要求框架在组件已经被卸载之后还留着节点播完，这件事在自定义组件
  // 这一层不成立。改成"先把位移动完，onFinish 里才真的通知宿主卸载"。
  //
  // panelH 由 onAreaChange 量出来：位移量必须**正好等于面板高度**，猜一个大值
  // 会让大半段时间花在屏幕外面，看上去就是「弹了一下才出现」。
  @State private panelH: number = 320;
  @State private shown: boolean = false;

  private entered: boolean = false;
  private closing: boolean = false;
  private unsubPinned: (() => void) | null = null;
  // 返回键登记（util/sheetDismissStack）。本面板是自绘浮层而不是 bindSheet，
  // 不登记的话按返回会直接把整个会话页出栈（用户 2026-09-22：「这个抽屉不受
  // 返回控制」）。登记在这里而不是往 ChatPage.handleBackPressed 里再加一个
  // if，正是这个登记处存在的理由。
  private unregisterBack: (() => void) | null = null;
  // 面板关掉之后回来的异步响应一律丢弃。
  private seq: number = 0;

  // 量到高度之后才起步（onAppear 可能早于第一次 onAreaChange）。只做一次。
  private enter(): void {
    if (this.entered) {
      return;
    }
    this.entered = true;
    const duration: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240);
    if (duration <= 0) {
      this.shown = true;
      return;
    }
    animateTo({ duration, curve: Curve.Friction }, (): void => { this.shown = true; });
  }

  aboutToAppear(): void {
    const store: MessageStore | null = this.store;
    if (store === null) {
      this.loadState = 'error';
      return;
    }
    // subscribePinned 会立即回调一次，首屏数据也由它给。
    this.unsubPinned = store.subscribePinned((): void => { this.readFromStore(); });
    this.unregisterBack = pushSheetDismiss((): void => { this.close(); });
    this.probeCanManage();
  }

  aboutToDisappear(): void {
    this.seq++;
    if (this.unsubPinned !== null) {
      this.unsubPinned();
      this.unsubPinned = null;
    }
    // 走返回键关的那一次，登记项已经被 dismissTopSheet() 弹掉了；这里再注销
    // 一次按 id 过滤，落空无害。反过来（点遮罩关）不注销就会留下一个指向已
    // 卸载组件的回调——下一次返回键"按了没反应"。
    if (this.unregisterBack !== null) {
      this.unregisterBack();
      this.unregisterBack = null;
    }
  }

  // 连点保护走 closing：退场期间遮罩还在，再点一下不该叠第二次动画。
  private close(): void {
    if (this.closing) {
      return;
    }
    const duration: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180);
    if (duration <= 0) {
      this.show = false;
      this.onShowChange(false);
      return;
    }
    this.closing = true;
    animateTo({
      duration, curve: Curve.Friction,
      onFinish: (): void => {
        this.show = false;
        this.onShowChange(false);
      }
    }, (): void => { this.shown = false; });
  }

  private readFromStore(): void {
    const store: MessageStore | null = this.store;
    if (store === null) {
      return;
    }
    const entries: PinnedEntry[] = store.getPinnedEntries();
    this.entries = entries;
    this.names = entries.map((e: PinnedEntry): string => this.resolveName(e.senderId));
    this.loadState = store.getPinnedLoadState();
    this.fillMissingNames(entries);
  }

  // 已知的名字；不知道就空串，界面回落到会话名。
  private resolveName(senderId: number): string {
    if (senderId === 0) {
      return '';
    }
    return getUserStore().displayName(senderId);
  }

  // 名字还没到的发送者各补一次 getUser。回包就是 user 对象本身，直接拼名字；
  // 同一次推送也会喂给 UserStore，所以别处的头像/昵称一起受益。
  private fillMissingNames(entries: PinnedEntry[]): void {
    const seq: number = this.seq;
    const pending: Set<number> = new Set<number>();
    for (let i = 0; i < entries.length; i++) {
      const id: number = entries[i].senderId;
      if (id > 0 && this.resolveName(id) === '') {
        pending.add(id);
      }
    }
    pending.forEach((userId: number): void => {
      getUserStore().ensure(userId);
      const req: TdRequest = { '@type': 'getUser' };
      req['user_id'] = userId;
      getTdClient().send(req).then((user: TdObject): void => {
        if (seq !== this.seq) {
          return;
        }
        const first: string = (user['first_name'] as string | undefined) ?? '';
        const last: string = (user['last_name'] as string | undefined) ?? '';
        const name: string = `${first} ${last}`.trim();
        if (name === '') {
          return;
        }
        this.names = this.entries.map((e: PinnedEntry, i: number): string =>
          e.senderId === userId ? name : (this.names[i] ?? ''));
      }).catch((e: TdError): void => {
        logE(`PinnedListSheet.getUser(${userId}) failed: ${e.message}`);
      });
    });
  }

  // 「我在这个会话能不能置顶」。见文件头。
  private probeCanManage(): void {
    const seq: number = this.seq;
    const entries: PinnedEntry[] = this.store?.getPinnedEntries() ?? [];
    if (entries.length === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getMessageProperties' };
    req['chat_id'] = this.chatId;
    req['message_id'] = entries[0].id;
    getTdClient().send(req).then((props: TdObject): void => {
      if (seq === this.seq) {
        this.canManage = (props['can_be_pinned'] as boolean | undefined) ?? false;
      }
    }).catch((e: TdError): void => {
      logE(`PinnedListSheet.getMessageProperties failed: ${e.message}`);
    });
  }

  private senderLabel(index: number): string {
    const name: string = this.names[index] ?? '';
    if (name !== '') {
      return name;
    }
    // 频道帖子和匿名管理员没有用户 id——显示会话名比显示一个陌生的 id 有意义。
    return getChatStore().entryOf(this.chatId)?.title ?? '';
  }

  private timeLabel(index: number): string {
    const date: number = this.entries[index]?.date ?? 0;
    return date > 0 ? monthDayTime(new Date(date * 1000)) : '';
  }

  private unpinOne(messageId: number): void {
    const store: MessageStore | null = this.store;
    if (store === null) {
      return;
    }
    store.unpinAsync(messageId).then((): void => {
      promptAction.showToast({ message: $r('app.string.cp_unpinned'), duration: 1400 });
    }).catch((e: TdError): void => {
      logE(`PinnedListSheet.unpinOne failed: ${e.message}`);
      promptAction.showToast({ message: this.rightsMessage(e, $r('app.string.cp_unpin_failed')), duration: 1700 });
    });
  }

  private unpinAll(): void {
    const store: MessageStore | null = this.store;
    if (store === null) {
      return;
    }
    promptAction.showDialog({
      title: $r('app.string.cp_unpin_all'),
      message: $r('app.string.cp_unpin_all_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_unpin_all'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) {
        return;
      }
      store.unpinAllAsync().then((): void => {
        promptAction.showToast({ message: $r('app.string.cp_unpin_all_done'), duration: 1400 });
        this.close();
      }).catch((e: TdError): void => {
        logE(`PinnedListSheet.unpinAll failed: ${e.message}`);
        promptAction.showToast({
          message: this.rightsMessage(e, $r('app.string.cp_unpin_all_failed')), duration: 1700
        });
      });
    }).catch((e: Object): void => {
      logE(`PinnedListSheet.unpinAll dialog failed: ${JSON.stringify(e)}`);
    });
  }

  // 权限不足单独给一句人话——同 ChatPage.togglePinMessage 的判据。
  private rightsMessage(e: TdError, fallback: Resource): Resource {
    return e.message.indexOf('not enough rights') >= 0 || e.message.indexOf('ADMIN') >= 0
      ? $r('app.string.cp_no_pin_permission') : fallback;
  }

  // 【为什么取消置顶是行尾一个按钮，不是长按菜单】长按菜单要 bindContextMenu，
  // 而它的两个重载是 (content, responseType) 与 (isShown, content, options)——
  // 没有"按长按触发、但只在有权限时才挂"的那一档；用 if 分两支写，整条属性链
  // 就得抄两份。行尾按钮既解决了这个问题，也与同一宿主里的 ScheduledSheet
  // （行尾一个删除图标）保持一致，而且不用靠长按才能被发现。
  //
  // 命中区同置顶条：跳转的点击落在左边 layoutWeight(1) 的那一列上，按钮是它的
  // 兄弟节点，两者物理上不相交。
  @Builder
  listBody() {
    List({ space: 2 }) {
      ForEach(this.entries, (entry: PinnedEntry, index: number) => {
        ListItem() {
          Row({ space: 4 }) {
            Column({ space: 3 }) {
              Row({ space: 8 }) {
                Text(this.senderLabel(index)).fontSize(12).fontColor(COLOR_PRIMARY)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1);
                Text(this.timeLabel(index)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width('100%');
              Text(entry.preview).fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%');
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .onClick((): void => {
              this.close();
              this.onJump(entry.id);
            });
            if (this.canManage) {
              Row() {
                SymbolGlyph($r('sys.symbol.pin_slash')).fontSize(17)
                  .fontColor([COLOR_TEXT_SECONDARY]);
              }
              .width(34).height(34).borderRadius(17)
              .justifyContent(FlexAlign.Center)
              .accessibilityText(str('ft_unpin'))
              .onClick((): void => { this.unpinOne(entry.id); });
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 12, right: 8, top: 9, bottom: 9 })
          .borderRadius(10)
          .backgroundColor($r('app.color.surface_alt'));
        }
      }, (entry: PinnedEntry): string => `pinned_${entry.id}`);
    }
    .constraintSize({ maxHeight: 360 })
    .width('100%');
  }

  build() {
    Column() {
      Column().layoutWeight(1).onClick((): void => { this.close(); });
      Column({ space: 10 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Row({ space: 6 }) {
          Text($r('app.string.cp_pinned_list_title')).fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY);
          if (this.entries.length > 0) {
            Text(pinnedCountLabel(this.entries.length)).fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        if (this.loadState === 'loading' && this.entries.length === 0) {
          LoadingProgress().width(28).height(28).margin({ top: 24, bottom: 24 });
        } else if (this.loadState === 'error') {
          Text($r('app.string.cp_pinned_list_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 24, bottom: 24 });
        } else if (this.entries.length === 0) {
          Text($r('app.string.cp_pinned_list_empty')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 24, bottom: 24 });
        } else {
          this.listBody();
        }
        if (this.canManage && this.entries.length > 0) {
          Button($r('app.string.cp_unpin_all'))
            .fontSize(15).fontColor('#E5484D')
            .backgroundColor(Color.Transparent)
            .width('100%').height(44)
            .onClick((): void => { this.unpinAll(); });
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 24 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 16, topRight: 16 })
      .translate({ y: this.shown ? 0 : this.panelH })
      .onAreaChange((_old: Area, area: Area): void => {
        const h: number = Number(area.height);
        if (h > 0 && Math.abs(h - this.panelH) > 0.5 && !this.shown) {
          this.panelH = h;
        }
        this.enter();
      });
    }
    .width('100%').height('100%')
    .backgroundColor(this.shown ? '#66000000' : '#00000000');
  }
}
