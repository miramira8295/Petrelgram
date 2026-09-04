import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { GLASS_OUTLINE_COLOR } from '../../util/bubbleTail';
import { ChatEntry, ChatKind, effectiveMuted } from '../../store/ChatEntry';
import { scopeMutedForKind } from '../../store/ScopeMuteStore';
import { FOLDER_TAGS_ENABLED, FolderInfo } from '../../store/FolderStore';
import {
  MUTE_OPTIONS, MuteOption, togglePin, setMute, markAsRead, markUnread,
  setArchived, setInFolder, clearHistory, leaveOrDeleteChat, leaveLabel, leaveConfirmMessage,
  blockAndDeleteChat
} from '../../store/ChatActions';
import { ClearHistoryOption, clearHistoryOptions, canClearHistory } from '../../store/ClearHistoryOptions';
import { getChatStore, getFolderStore } from '../../tdkit/Globals';
import {
  KEY_POWER_ACTIVE, KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_THREE_LINES, powerAnimationDuration
} from '../../store/AppSettings';
import { CHAT_LIST_NOW, CHAT_MENU_OPEN } from './ChatListFreeze';
import { navigateToDirectMessagesTopics, navigateToForumTopics } from '../../util/profileNav';
import { AvatarView } from './AvatarView';
import { formatTime } from '../../util/formatTime';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY,
  COLOR_DIVIDER, COLOR_MUTED_BADGE, mainCardFill, ROW_PAD_H, ROW_PAD_V
} from '../../util/theme';
import { KEY_APP_BG_ON } from '../../store/AppSettings';
import { folderColor } from '../../util/FolderVisuals';
import { plural, str } from '../../util/strings';
import {
  overlayBackdropBlur, overlayBlur, overlayGlassFill, overlayMaterial, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import {
  KEY_SURFACE_GLASS_ON, SURFACE_GLASS_EPOCH, SURFACE_GLASS_ON_DEFAULT,
  surfaceGlassBlurStyle, surfaceGlassFill, surfaceGlassOn
} from '../../util/surfaceGlass';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logI } from '../../util/log';
import { APPEARANCE_EPOCH } from '../../util/appearance';

// 等上下文菜单收起再弹确认框。菜单是独立子窗口，收起过程中弹出的
// 对话框会挂死（Promise 既不 resolve 也不 reject）。
const MENU_DISMISS_MS: number = 150;
// 与首页 HDS 大标题的 12vp 起始线对齐；滑动操作背景也复用这一个值。
export const CHAT_ROW_SIDE_GUTTER: number = 12;

// Reused across list rows. Every chat row is the same shape, so there is no
// reuseId to split: one pool serves the whole list.
@Reusable
@Component
export struct ChatRow {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 全局界面模糊：开关和档位都要能立刻重绘（见 util/surfaceGlass）。
  @StorageProp(KEY_SURFACE_GLASS_ON) private surfaceGlass: boolean = SURFACE_GLASS_ON_DEFAULT;
  @StorageProp(SURFACE_GLASS_EPOCH) private surfaceGlassEpoch: number = 0;
  // 由 MainScreen 算好写进 AppStorage 的「APP 壁纸生效中」，见 store/AppSettings。
  @StorageProp(KEY_APP_BG_ON) private appWallpaperOn: boolean = false;
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
  // 长按落点相对行中心的水平偏移，交给 bindContextMenu 的 offset。
  @State menuOffsetX: number = 0;
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

  // 这一行到底静不静音。**不能直接读 chat.isMuted**：那是 TDLib 的
  // mute_for > 0，而 use_default_mute_for 为 true 时 mute_for 是无意义的，
  // 真实状态在分类默认里（issue #110：官版显示静音、我们显示没静音）。
  private muted(): boolean {
    return effectiveMuted(this.chat, scopeMutedForKind(this.chat.kind));
  }

  private accessibilitySummary(): string {
    const parts: string[] = [this.chat.title];
    if (this.isPinned()) {
      parts.push(str('cl_pinned'));
    }
    if (this.muted()) {
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

  // 记下长按落点相对行中心的水平偏移。在手势回调里记而不是在 onTouch 的 Down 里：
  // 实测行右半边的按下到不了 onTouch（被行内子元素吃掉），放在那儿会让菜单沿用
  // 上一次按压的旧偏移。
  private recordMenuOffset(event: GestureEvent): void {
    const fingers = event.fingerList;
    const rowWidth: number = event.target.area.width as number;
    if (fingers.length === 0 || rowWidth <= 0) {
      this.menuOffsetX = 0;
      return;
    }
    this.menuOffsetX = fingers[0].localX - rowWidth / 2;
  }

  private openContextMenuIfCurrent(event: GestureEvent): void {
    this.recordMenuOffset(event);
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

  // 能不能清、能怎么清完全由 chat 的两个能力位决定（见 ClearHistoryOptions）。
  // 老逻辑对任何会话都硬给 revoke=false，超级群/频道因此必然报
  // "Can't delete history of X only for self"（issue: 老张观影群）。
  private clearOptions(): ClearHistoryOption[] {
    return clearHistoryOptions(
      this.chat.canDeleteOnlyForSelf, this.chat.canDeleteForAllUsers, this.chat.kind);
  }

  private canClear(): boolean {
    return canClearHistory(this.chat.canDeleteOnlyForSelf, this.chat.canDeleteForAllUsers);
  }

  private confirmClearHistory(): void {
    const options: ClearHistoryOption[] = this.clearOptions();
    if (options.length === 0) {
      // 菜单项本来就不该出现；这里兜一道，避免弹一个只有取消的空对话框。
      return;
    }
    const buttons: promptAction.Button[] = [{ text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string }];
    for (const opt of options) {
      // 用 str() 而不是 $r()：$r 的 key 必须是编译期字面量，这里是按能力位选出来的。
      buttons.push({ text: str(opt.labelKey), color: '#E64646' });
    }
    const chatId: number = this.chat.id;
    this.showConfirm({
      title: $r('app.string.cp_clear_history'),
      message: str('cl_clear_confirm', this.chat.title),
      buttons: buttons
    }, 'confirmClearHistory', (index: number): void => {
      // index 0 是取消，其余按钮与 options 一一对应。
      const picked: ClearHistoryOption | undefined =
        index >= 1 && index <= options.length ? options[index - 1] : undefined;
      if (picked !== undefined) {
        clearHistory(chatId, picked.revoke);
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
    const canOnlyForSelf: boolean = this.chat.canDeleteOnlyForSelf;
    const canForAllUsers: boolean = this.chat.canDeleteForAllUsers;
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
        leaveOrDeleteChat(chatId, kind, canOnlyForSelf, canForAllUsers);
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
  // 只有 APP 壁纸生效时才给每一行挂玻璃：普通纯色页面继续走实色 surface，
  // 避免在没有视觉收益时给滚动列表增加合成层。materialEpoch 虽然不参与数值
  // 计算，但必须在这里读到，用户改厚度/光感后可复用行才会重新应用材质修饰器。
  // **只看「界面模糊质感」这一个开关。**
  //
  // 原来的判据是「应用壁纸开着」——那是把两件事绑在了一起：铺壁纸和要玻璃。
  // 全局开关存在的意义就是让它成为唯一真相，所以壁纸那条不再单独开玻璃。
  //
  // 后果说清楚：**开着壁纸、但没打开新开关的用户，行会从玻璃变回实底。**
  // 新开关默认关，所以升级后要自己去 设置 → 聊天 → 界面模糊质感 打开。
  private rowGlassEnabled(): boolean {
    // `this.surfaceGlassEpoch >= 0` 恒真，**但不能删**：@StorageProp 只有在
    // build 链路里被真正读到才建立依赖，光声明不读，改设置时这一行不会重绘
    // （用户实测"开关打开了，不重建页面不生效"）。原来 materialEpoch 那一处
    // 也是同一个套路，我把它删了才踩出这个坑。
    return this.surfaceGlass && this.surfaceGlassEpoch >= 0;
  }

  private rowFill(pressed: boolean): ResourceColor {
    if (!this.rowGlassEnabled()) {
      // **不走玻璃就是实底。**
      //
      // 这里不能再用 mainCardFill(wallpaperOn, ...)：壁纸档那对颜色
      // （card_on_wallpaper = #CCFFFFFF，80% 不透明）**是为玻璃配的**——半透是
      // 为了让底下的 backdropBlur 透出来。开关关掉之后模糊没了，颜色还留在半透
      // 档，壁纸上就是一层灰蒙蒙的纱（用户实测）。要么两样都有，要么两样都没有。
      return pressed ? $r('app.color.surface_alt') : $r('app.color.surface');
    }
    // 玻璃档的底色由 surfaceGlass 统一决定，与传进去的实色无关
    // （不透明底色会把 backdropBlur 完全盖住）。
    return surfaceGlassFill(mainCardFill(this.appWallpaperOn, pressed));
  }

  private rowBlurStyle(): BlurStyle | undefined {
    return this.rowGlassEnabled() ? surfaceGlassBlurStyle() : undefined;
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(this.rowFill(false))
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor(this.rowFill(true))
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

      if (this.muted()) {
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

      if (this.canClear()) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
          content: $r('app.string.cp_clear_history')
        })
          .onClick(() => { this.confirmClearHistory(); });
      }

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
      // 标题与预览之间 6：4 太挤（用户实测）。行的 minHeight 是 72，而
      // 17 号标题 + 14 号预览 + 6 + 上下各 8 的内边距 ≈ 64，仍在 72 以内，
      // 所以这一档不会把行撑高，只是把两行分开。
      Column({ space: 6 }) {
        Row() {
          Text(this.chat.isSavedMessages
            ? $r('app.string.cl_saved_messages') : this.chat.title)
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1);
          if (this.muted()) {
            SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(13).fontColor([COLOR_ICON_SECONDARY]).margin({ left: 4 }).flexShrink(0);
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
              .fontSize(14).fontColor(this.accent())
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
            SymbolGlyph($r('sys.symbol.pin')).fontSize(11).fontColor([COLOR_ICON_SECONDARY]);
          }
          Text(formatTime(this.chat.lastMessageDate, this.nowSec))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        if (this.chat.unreadCount > 0) {
          // 单 Text 画角标胶囊，不再套 Row（无属性容器精简，同 AvatarView
          // 的字母头像）。居中靠 align/textAlign。
          Text(this.unreadLabel())
            .fontSize(12).fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .constraintSize({ minWidth: 22 })
            .height(22).padding({ left: 7, right: 7 })
            .align(Alignment.Center).textAlign(TextAlign.Center)
            .backgroundColor(this.muted() ? COLOR_MUTED_BADGE : this.accent())
            .borderRadius(11);
        } else if (this.chat.isMarkedUnread) {
          // Manually flagged unread — a plain dot, like the official clients.
          Circle({ width: 10, height: 10 })
            .fill(this.muted() ? COLOR_MUTED_BADGE : this.accent());
        }
      }.alignItems(HorizontalAlign.End);
    }
    // 真卡片左边沿与首页大标题的起始线对齐。壁纸生效时卡片交给现有 'card'
    // 稳定玻璃：所有 API 都随“材质厚度”改变锁定的模糊半径；用户关闭材质时
    // overlayGlassFill 会自然退回原来的可读性实底。
    .width(`calc(100% - ${CHAT_ROW_SIDE_GUTTER * 2}vp)`)
    .margin({ left: CHAT_ROW_SIDE_GUTTER, right: CHAT_ROW_SIDE_GUTTER, top: 3, bottom: 3 })
    .borderRadius(16)
    // 描边跟着玻璃走，**颜色也要跟着换**。
    //
    // 原来是 `COLOR_DIVIDER`：行是不透明白卡片时它就是一条正常的灰细线；换成
    // 半透玻璃之后，它在壁纸上成了一圈发暗的框，圆角处两条边的抗锯齿叠在一起
    // 四角最明显（用户实测"四角黑边"）。而 divider 在**深色模式下是 #101921**，
    // 几乎全黑，那一档更糟。
    // GLASS_OUTLINE_COLOR（#4DFFFFFF，30% 白）是玻璃气泡描边用的同一个色，
    // 专门为"玻璃边缘"配的，深浅两种模式下都是提亮而不是压暗。
    .border({
      width: this.rowGlassEnabled() ? 0.5 : (this.appWallpaperOn ? 0.5 : 0),
      color: this.rowGlassEnabled() ? GLASS_OUTLINE_COLOR : COLOR_DIVIDER
    })
    // 用框架容器材质而不是 backdropBlur：后者在节点边缘有采样衰减，四角最明显
    // （见 util/surfaceGlass.surfaceGlassBlurStyle 的说明）。
    .backgroundBlurStyle(this.rowBlurStyle())
    .attributeModifier(materialModifierWhen('card', this.rowGlassEnabled()))
    .clip(true)
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
        // 曾经是 router.pushUrl('pages/chat/ForumTopicsPage')——话题列表已迁成
        // HdsNavDestination 并从 main_pages.json 摘出，整页路由跳不动，走漏斗。
        // 同一段代码跑在两个上下文里：会话列表（左栏）和归档页（栈里的一层）。
        // 从归档进话题列表要**叠**在归档之上，否则返回时归档页已被清掉
        // （issue #117）。listKey 正好能区分。
        navigateToForumTopics(forumParams, this.listKey === 'archive' ? 'content' : 'navbar');
        return;
      }
      if (getChatStore().isAdministeredDirectMessagesGroup(this.chat.id)) {
        const directParams: Record<string, Object> = {
          'chatId': this.chat.id, 'title': this.chat.title
        };
        navigateToDirectMessagesTopics(
          directParams, this.listKey === 'archive' ? 'content' : 'navbar');
        return;
      }
      const params: Record<string, Object> = { 'chatId': this.chat.id };
      navigateToChat(params).catch(logChatNavFailure);
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
        .onAction((event: GestureEvent): void => { this.openContextMenuIfCurrent(event); })
        .onActionCancel((): void => { this.endPress(); })
    )
    // While the menu is open the list must not rebuild: an incoming message
    // increments the row revision and would otherwise take the menu down.
    // The flag freezes the list (see CHAT_MENU_OPEN).
    .bindContextMenu(this.contextMenuShown, this.contextMenu, {
      // 钉死 placement：不指定时 ArkUI 按可用空间自己挑锚定角，锚点一换偏移的
      // 参照就变了。钉死之后 offset 才是一个稳定的水平平移。
      placement: Placement.BottomLeft,
      // **符号取反，这里必须解释清楚。**
      //
      // 实测（平板，同一行两次长按，日志记的 offset 与截图量的菜单左缘）：
      //   不取反   offset −110 -> 菜单左缘 418 ； offset +110 -> 176   （反向）
      //   取反后   offset −110 -> 菜单左缘 176 ； offset +110 -> 418   （正向）
      // 取反之后单调且方向正确：按行左侧菜单在左，按右侧在右。
      //
      // **我解释不了为什么这里要取反而 MessageBubble 不用**——那边同样是
      // bindContextMenu + preview: IMAGE，用未取反的 offset 方向就是对的
      // （左缘长按菜单左缘 521、右缘 827）。两处唯一的结构差别是预览的宽度：
      // 这里的预览是整行满宽，那边是一个小气泡。先按实测结果写，别按推测写；
      // 哪天 ArkUI 这块行为变了，上面那四组数字就是重新验证的基准。
      offset: { x: -this.menuOffsetX, y: 0 },
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
