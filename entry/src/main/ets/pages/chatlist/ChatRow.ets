import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { ChatEntry, ChatKind } from '../../store/ChatEntry';
import { FOLDER_TAGS_ENABLED, FolderInfo } from '../../store/FolderStore';
import {
  MUTE_OPTIONS, MuteOption, togglePin, setMute, markAsRead, markUnread,
  setArchived, setInFolder, clearHistory, leaveOrDeleteChat, leaveLabel, leaveConfirmMessage,
  blockAndDeleteChat
} from '../../store/ChatActions';
import { getChatStore, getFolderStore } from '../../tdkit/Globals';
import {
  KEY_POWER_ACTIVE, KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_THREE_LINES, powerAnimationDuration
} from '../../store/AppSettings';
import { CHAT_LIST_NOW, CHAT_MENU_OPEN } from './ChatListFreeze';
import { AvatarView } from './AvatarView';
import { formatTime } from '../../util/formatTime';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_MUTED_BADGE, ROW_PAD_H, ROW_PAD_V } from '../../util/theme';
import { folderColor } from '../../util/FolderVisuals';
import { plural, str } from '../../util/strings';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { navigateToChat } from '../../util/chatNav';
import { logI } from '../../util/log';

// 等上下文菜单收起再弹确认框。菜单是独立子窗口，收起过程中弹出的
// 对话框会挂死（Promise 既不 resolve 也不 reject）。
const MENU_DISMISS_MS: number = 150;

// Reused across list rows. Every chat row is the same shape, so there is no
// reuseId to split: one pool serves the whole list.
@Reusable
@Component
export struct ChatRow {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @Prop chat: ChatEntry;
  // The list this row is being shown in — pinning is per-list, and the menu
  // offers 取消归档 instead of 归档 inside the archive.
  @Prop listKey: string;
  @StorageProp(CHAT_LIST_NOW) nowSec: number = Math.floor(Date.now() / 1000);
  // 聊天设置 → 聊天列表视图: the preview line wraps to two lines in 三行 mode.
  @StorageProp(KEY_THREE_LINES) threeLines: boolean = false;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) particlesEnabled: boolean = true;
  @StorageProp(FOLDER_TAGS_ENABLED) folderTagsEnabled: boolean = false;
  @State livePulseExpanded: boolean = false;
  @State contextMenuShown: boolean = false;
  private livePulseTimer: number = -1;
  // A long press is only valid for the exact row snapshot that was under the
  // finger on TouchType.Down. A new message can update the row revision or
  // reorder it while the recognition timer is running.
  private pressActive: boolean = false;
  private pressRevision: number = -1;
  private pressIndex: number = -1;
  // A successful long press and the row click share the same pointer
  // sequence. Keep the click from navigating when release follows the menu.
  private pressConsumedByMenu: boolean = false;

  aboutToAppear(): void {
    this.startLivePulse(this.chat.isLive);
  }

  // Recycling is NOT destruction: a reused row goes to the pool and
  // aboutToDisappear never runs for it. Without this the live pulse interval
  // would outlive the row and keep ticking for every row the list ever showed.
  aboutToRecycle(): void {
    this.teardown();
  }

  aboutToReuse(params: Record<string, Object>): void {
    // Only this row's own state is re-seeded — @Prop is refreshed by the
    // framework, and assigning it here is what tore MessageBubble's parallel
    // arrays apart.
    this.livePulseExpanded = false;
    this.contextMenuShown = false;
    this.pressActive = false;
    this.pressRevision = -1;
    this.pressIndex = -1;
    this.pressConsumedByMenu = false;
    // isLive comes from params, not this.chat: that refresh lands after this
    // callback, so reading the field here would arm the pulse from the row
    // being replaced rather than the one arriving.
    const next = params.chat as ChatEntry | undefined;
    this.startLivePulse(next !== undefined && next.isLive);
  }

  aboutToDisappear(): void {
    this.teardown();
  }

  private startLivePulse(isLive: boolean): void {
    if (this.livePulseTimer !== -1 || !isLive) {
      return;
    }
    this.livePulseTimer = setInterval((): void => {
      if (this.powerSaving || !this.particlesEnabled) {
        this.livePulseExpanded = false;
        return;
      }
      this.livePulseExpanded = !this.livePulseExpanded;
    }, 760);
  }

  private teardown(): void {
    if (this.livePulseTimer !== -1) {
      clearInterval(this.livePulseTimer);
      this.livePulseTimer = -1;
    }
    if (this.contextMenuShown) {
      this.contextMenuShown = false;
      AppStorage.setOrCreate(CHAT_MENU_OPEN, false);
    }
  }

  private folders(): FolderInfo[] {
    return getFolderStore().getFolders();
  }

  private matchingFolders(): FolderInfo[] {
    if (!this.folderTagsEnabled) { return []; }
    return this.folders().filter((folder: FolderInfo): boolean =>
      getChatStore().isInFolder(folder.id, this.chat.id));
  }

  private isPinned(): boolean {
    return getChatStore().isPinned(this.listKey, this.chat.id);
  }

  private isArchived(): boolean {
    return getChatStore().isArchived(this.chat.id);
  }

  // Unread by count OR by the manual flag — either state offers 标记为已读.
  private isUnread(): boolean {
    return this.chat.unreadCount > 0 || this.chat.isMarkedUnread;
  }

  private unreadLabel(): string {
    return this.chat.unreadCount > 999 ? '999+' : `${this.chat.unreadCount}`;
  }

  private accessibilitySummary(): string {
    const parts: string[] = [this.chat.title];
    if (this.isPinned()) {
      parts.push(str('cl_pinned'));
    }
    if (this.chat.isMuted) {
      parts.push(str('cl_muted'));
    }
    if (this.isUnread()) {
      parts.push(this.chat.unreadCount > 0 ? plural('cl_unread_n', this.chat.unreadCount, this.chat.unreadCount) : str('cl_mark_unread'));
    }
    if (this.chat.lastMessageText !== '') {
      parts.push(this.chat.lastMessageText);
    }
    return parts.join('，');
  }

  private currentIndex(): number {
    return getChatStore().getChats(this.listKey)
      .findIndex((entry: ChatEntry): boolean => entry.id === this.chat.id);
  }

  private beginPress(): void {
    const current = getChatStore().entryOf(this.chat.id);
    this.pressConsumedByMenu = false;
    this.pressActive = current !== undefined;
    this.pressRevision = current?.revision ?? -1;
    this.pressIndex = this.currentIndex();
  }

  private endPress(): void {
    this.pressActive = false;
  }

  private openContextMenuIfCurrent(): void {
    const current = getChatStore().entryOf(this.chat.id);
    const unchanged = this.pressActive && current !== undefined
      && current.revision === this.pressRevision
      && this.currentIndex() === this.pressIndex;
    this.pressActive = false;
    if (!unchanged) {
      // The row was refreshed or moved before recognition completed. Ignore
      // this long press instead of opening a menu for stale screen content.
      return;
    }
    this.pressConsumedByMenu = true;
    this.contextMenuShown = true;
  }

  private confirmClearHistory(): void {
    const isPrivate = this.chat.kind === 'private' || this.chat.kind === 'secret';
    const buttons: promptAction.Button[] = [{ text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string }];
    buttons.push({ text: $r('app.string.clear_all'), color: '#E64646' });
    if (isPrivate) {
      buttons.push({ text: $r('app.string.cl_clear_for_both'), color: '#E64646' });
    }
    const chatId: number = this.chat.id;
    this.showConfirm({
      title: $r('app.string.cp_clear_history'),
      message: str('cl_clear_confirm', this.chat.title),
      buttons: buttons
    }, 'confirmClearHistory', (index: number): void => {
      if (index === 1) {
        clearHistory(chatId, false);
      } else if (index === 2) {
        clearHistory(chatId, true);
      }
    });
  }

  // 上下文菜单的 onClick 里直接调全局 promptAction.showDialog 会静默挂死：
  // 菜单是独立子窗口，收起过程中弹出的对话框没有可依附的 UI 上下文，Promise
  // 既不 resolve 也不 reject，界面上什么都不发生（排查时极难定位）。
  // 两处修正：用 UIContext 作用域的 promptAction，并延后到菜单收起动画之后。
  private showConfirm(
    options: promptAction.ShowDialogOptions, what: string,
    onConfirm: (index: number) => void
  ): void {
    const prompt = this.getUIContext().getPromptAction();
    setTimeout((): void => {
      prompt.showDialog(options).then((res: promptAction.ShowDialogSuccessResponse): void => {
        onConfirm(res.index);
      }).catch((e: Object): void => {
        // 点击遮罩关闭也会走到这里，所以只记录不打扰用户。
        logI(`ChatRow.${what} dialog dismissed: ${JSON.stringify(e)}`);
      });
    }, MENU_DISMISS_MS);
  }

  private confirmLeave(): void {
    const label = leaveLabel(this.chat.kind);
    const chatId: number = this.chat.id;
    const kind: ChatKind = this.chat.kind;
    const title: string = this.chat.title;
    // 只有私聊能屏蔽：私聊的 chat_id 就是对方 user_id；密聊的 chat_id 是会话
    // id，群和频道也没有单一发送者可屏蔽。
    const canBlock: boolean = kind === 'private';
    const buttons: promptAction.Button[] = canBlock
      ? [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.ca_delete_chat'), color: '#E64646' },
        { text: $r('app.string.cl_delete_and_block'), color: '#E64646' }
      ]
      : [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: label, color: '#E64646' }
      ];
    this.showConfirm({
      title: label,
      message: canBlock
        ? str('cl_delete_block_confirm', title)
        : leaveConfirmMessage(kind, title),
      buttons: buttons
    }, 'confirmLeave', (index: number): void => {
      if (index === 1) {
        leaveOrDeleteChat(chatId, kind);
        return;
      }
      if (index === 2 && canBlock) {
        blockAndDeleteChat(chatId);
        promptAction.showToast({ message: str('cl_deleted_blocked', title), duration: 1800 });
      }
    });
  }

  // Native pressed feedback starts as soon as the finger goes down. Besides
  // making ordinary taps feel responsive, it also makes the long-press wait
  // visible before the context menu appears.
  @Styles
  rowNormalStyle() {
    .backgroundColor($r('app.color.surface'))
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  @Builder
  muteSubMenu() {
    Menu() {
      ForEach(MUTE_OPTIONS, (opt: MuteOption) => {
        MenuItem({ content: opt.label })
          .onClick(() => { setMute(this.chat.id, opt.seconds); });
      }, (opt: MuteOption) => `${opt.seconds}`);
    }
  }

  @Builder
  folderSubMenu() {
    Menu() {
      if (this.folders().length === 0) {
        MenuItem({ content: $r('app.string.cl_no_folders') }).enabled(false);
      } else {
        ForEach(this.folders(), (f: FolderInfo) => {
          // Tapping a folder the chat already belongs to removes it again.
          MenuItem({
            content: getChatStore().isInFolder(f.id, this.chat.id) ? `${f.title}  ✓` : f.title
          })
            .onClick(() => {
              setInFolder(f.id, this.chat.id, !getChatStore().isInFolder(f.id, this.chat.id));
            });
        }, (f: FolderInfo) => `${f.id}`);
      }
    }
  }

  @Builder
  contextMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        content: this.isPinned() ? $r('app.string.ft_unpin') : $r('app.string.ft_pin')
      })
        .onClick(() => { togglePin(this.listKey, this.chat.id, !this.isPinned()); });

      if (this.chat.isMuted) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bell')),
          content: $r('app.string.cp_unmute')
        })
          .onClick(() => { setMute(this.chat.id, 0); });
      } else {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bell_slash')),
          content: $r('app.string.cp_mute'),
          builder: (): void => { this.muteSubMenu(); }
        });
      }

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
        content: this.isUnread() ? $r('app.string.cl_mark_read') : $r('app.string.cl_mark_unread')
      })
        .onClick(() => {
          if (this.isUnread()) {
            markAsRead(this.chat.id, this.chat.lastMessageId);
          } else {
            markUnread(this.chat.id, true);
          }
        });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.archivebox')),
        content: this.isArchived() ? $r('app.string.cl_unarchive') : $r('app.string.cl_archive')
      })
        .onClick(() => { setArchived(this.chat.id, !this.isArchived()); });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder_badge_plus')),
        content: $r('app.string.cl_add_to_folder'),
        builder: (): void => { this.folderSubMenu(); }
      });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: $r('app.string.cp_clear_history')
      })
        .onClick(() => { this.confirmClearHistory(); });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.xmark_circle')).fontColor([Color.Red]),
        content: leaveLabel(this.chat.kind)
      })
        .onClick(() => { this.confirmLeave(); });
    }
  }

  build() {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: this.chat.avatarPath,
        initials: this.chat.initials,
        colorSeed: this.chat.id,
        autoDeleteTime: this.chat.autoDeleteTime,
        isLive: this.chat.isLive,
        livePulseExpanded: this.livePulseExpanded,
        savedMessages: this.chat.isSavedMessages
      });
      Column({ space: 4 }) {
        Row() {
          Text(this.chat.isSavedMessages
            ? $r('app.string.cl_saved_messages') : this.chat.title)
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1);
          if (this.chat.isMuted) {
            SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]).margin({ left: 4 }).flexShrink(0);
          }
          if (this.matchingFolders().length > 0) {
            Text(this.matchingFolders()[0].title)
              .fontSize(9).fontWeight(FontWeight.Medium)
              .fontColor(folderColor(this.matchingFolders()[0].colorId))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 58 })
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .margin({ left: 5 })
              .backgroundColor(`${folderColor(this.matchingFolders()[0].colorId)}18`)
              .borderRadius(7).flexShrink(0);
            if (this.matchingFolders().length > 1) {
              Text(`+${this.matchingFolders().length - 1}`).fontSize(9)
                .fontColor(COLOR_TEXT_SECONDARY).margin({ left: 3 }).flexShrink(0);
            }
          }
        }.width('100%');
        Row() {
          if (this.chat.lastSenderName !== '') {
            Text(`${this.chat.lastSenderName}: `)
              .fontSize(14).fontColor(COLOR_PRIMARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 112 });
          }
          Text(this.chat.lastMessageText)
            .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(this.threeLines ? 2 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Top);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Column({ space: 6 }) {
        Row({ space: 3 }) {
          if (this.isPinned()) {
            SymbolGlyph($r('sys.symbol.pin')).fontSize(11).fontColor([COLOR_TEXT_SECONDARY]);
          }
          Text(formatTime(this.chat.lastMessageDate, this.nowSec))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        if (this.chat.unreadCount > 0) {
          Row() {
            Text(this.unreadLabel())
              .fontSize(12).fontColor(Color.White)
              .fontWeight(FontWeight.Medium);
          }
            .constraintSize({ minWidth: 22 })
            .height(22).padding({ left: 7, right: 7 })
            .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .backgroundColor(this.chat.isMuted ? COLOR_MUTED_BADGE : COLOR_PRIMARY)
            .borderRadius(11);
        } else if (this.chat.isMarkedUnread) {
          // Manually flagged unread — a plain dot, like the official clients.
          Circle({ width: 10, height: 10 })
            .fill(this.chat.isMuted ? COLOR_MUTED_BADGE : COLOR_PRIMARY);
        }
      }.alignItems(HorizontalAlign.End);
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: ROW_PAD_V, bottom: ROW_PAD_V })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.rowNormalStyle,
      pressed: this.rowPressedStyle
    })
    .accessibilityText(this.accessibilitySummary())
    .onClick(() => {
      if (this.pressConsumedByMenu || this.contextMenuShown) {
        this.pressConsumedByMenu = false;
        return;
      }
      // 话题群进话题列表，普通聊天进消息流。
      if (getChatStore().isForum(this.chat.id)) {
        const forumParams: Record<string, Object> = {
          'chatId': this.chat.id, 'title': this.chat.title
        };
        router.pushUrl({ url: 'pages/chat/ForumTopicsPage', params: forumParams });
        return;
      }
      const params: Record<string, Object> = { 'chatId': this.chat.id };
      navigateToChat(params);
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.beginPress();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.endPress();
      }
    })
    // Keep List's pan recognizer active. Movement cancels this recognizer,
    // while a stationary hold reaches the data-consistency check above.
    .parallelGesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
        .onAction((): void => { this.openContextMenuIfCurrent(); })
        .onActionCancel((): void => { this.endPress(); })
    )
    // While the menu is open the list must not rebuild: an incoming message
    // increments the row revision and would otherwise take the menu down.
    // The flag freezes the list (see CHAT_MENU_OPEN).
    .bindContextMenu(this.contextMenuShown, this.contextMenu, {
      // IMAGE captures this exact chat strip. The framework then lifts that
      // snapshot above the mask, so list inertia can no longer move the
      // focused item away from the menu.
      preview: MenuPreviewMode.IMAGE,
      previewBorderRadius: 14,
      previewAnimationOptions: {
        scale: [0.98, 1.035],
        transition: TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.FastOutSlowIn
          })
      },
      borderRadius: 16,
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: overlayBlur('menu'),
      systemMaterial: overlayMaterial('menu'),
      transition: TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
          curve: Curve.FastOutSlowIn
        }),
      // A modal blurred mask keeps the page visually behind the lifted row
      // and absorbs taps until the operation panel is dismissed.
      mask: {
        color: '#52000000',
        backgroundBlurStyle: BlurStyle.BACKGROUND_THIN
      },
      modalMode: ModalMode.TARGET_WINDOW,
      hapticFeedbackMode: HapticFeedbackMode.AUTO,
      aboutToAppear: (): void => {
        AppStorage.setOrCreate(CHAT_MENU_OPEN, true);
      },
      onDisappear: (): void => {
        this.contextMenuShown = false;
        AppStorage.setOrCreate(CHAT_MENU_OPEN, false);
      }
    });
  }
}
