import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { getChatStore, getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { ChatEntry, effectiveMuted } from '../../store/ChatEntry';
import { setMute, MUTE_LONG } from '../../store/ChatActions';
import { ForumTopicsStore } from '../../store/ForumTopicsStore';
import { scopeMutedForKind, SCOPE_MUTE_EPOCH } from '../../store/ScopeMuteStore';
import { ForumTopicRow, startsWithEmojiSymbol } from '../../util/forumTopicModel';
import { CHATLIST_PREVIEW_THUMB_ENABLED, stripPreviewIcon } from '../../util/formatPreview';
import { formatTime } from '../../util/formatTime';
import { unreadBadgeText } from '../../util/unreadBadge';
import {
  closeForumDrawer, FORUM_DRAWER_CLOSE_MS, FORUM_DRAWER_OPEN_MS,
  KEY_ACTIVE_FORUM_CHAT_ID, KEY_ACTIVE_FORUM_NEW_TOPIC_EPOCH,
  KEY_ACTIVE_FORUM_OPEN, KEY_ACTIVE_FORUM_SEARCH_QUERY,
  requestForumNewTopic
} from '../../util/forumDrawerState';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { navigateToChatProfile } from '../../util/profileNav';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';
import { AvatarView } from './AvatarView';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import {
  COLOR_DIVIDER, COLOR_ICON_SECONDARY, COLOR_MUTED_BADGE, COLOR_ON_PRIMARY,
  COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayMaterial } from '../../util/overlayMaterial';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

export const FORUM_LEFT_RAIL_WIDTH: number = 72;
const DOCK_CLEARANCE_VP: number = 78;
const TOP_BAR_HEIGHT: number = 56;

export function forumTopicRowKey(row: ForumTopicRow): string {
  return `${row.threadId}_${row.name}_${row.iconColor}_${row.iconCustomEmojiId ?? ''}` +
    `_${row.iconCustomEmojiPath ?? ''}_${row.iconEmoji ?? ''}` +
    `_${row.isGeneral}_${row.isClosed}_${row.isPinned}_${row.unreadCount}` +
    `_${row.lastMessageDate ?? 0}_${row.lastSenderName ?? ''}` +
    `_${row.lastMessageThumb ?? ''}_${row.lastMessageText}_${row.isMuted ?? false}`;
}

// 超级群组专属顶栏内容：直接挂在 HdsNavigation 标题栏的 stackBuilder 内，
// 与首页 Petrel 顶栏共享同一个原生毛玻璃标题栏节点（从不触发 hideTitleBar 切换与重建），
// 打开时从右侧滑入、退出时向右滑出原路归位。
@Component
export struct ForumTopHeaderBar {
  @StorageProp(KEY_ACTIVE_FORUM_CHAT_ID) @Watch('onTargetChanged') chatId: number = 0;
  @StorageProp(KEY_ACTIVE_FORUM_OPEN) @Watch('onOpenChanged') drawerOpen: boolean = false;
  @StorageProp('navBarWidth') private navBarW: number = 0;
  @StorageProp('screenWidthVp') private screenW: number = 360;
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLangChanged') langEpoch: number = 0;
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(SCOPE_MUTE_EPOCH) @Watch('onScopeMuteChanged') scopeMuteEpoch: number = 0;

  @State private chatTitle: string = '';
  @State private chatAvatarPath: string = '';
  @State private chatInitials: string = '';
  @State private chatMuted: boolean = false;
  @State private memberCount: number = 0;
  @State private searching: boolean = false;
  @State private searchQuery: string = '';

  private unsubChatStore: (() => void) | null = null;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.unsubChatStore = getChatStore().subscribeChanges((): void => {
      if (!this.active || this.chatId === 0) {
        return;
      }
      this.refreshChatHeader();
    });
    if (this.chatId !== 0) {
      this.refreshChatHeader();
      this.ensureMemberCount(this.chatId);
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.unsubChatStore?.();
    this.unsubChatStore = null;
  }

  private slideWidth(): number {
    return this.navBarW > 0 ? this.navBarW : this.screenW;
  }

  private onTargetChanged(): void {
    this.searching = false;
    this.searchQuery = '';
    if (this.chatId === 0) {
      return;
    }
    this.refreshChatHeader();
    this.ensureMemberCount(this.chatId);
  }

  private onOpenChanged(): void {
    if (!this.drawerOpen && this.searching) {
      this.searching = false;
      this.searchQuery = '';
      AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_SEARCH_QUERY, '');
    }
  }

  private onLangChanged(): void {
    if (this.active && this.chatId !== 0) {
      this.refreshChatHeader();
    }
  }

  private onScopeMuteChanged(): void {
    if (this.active && this.chatId !== 0) {
      this.refreshChatHeader();
    }
  }

  private refreshChatHeader(): void {
    const store = getChatStore();
    const entry: ChatEntry | undefined = store.entryOf(this.chatId);
    if (entry !== undefined) {
      this.chatTitle = entry.title;
      this.chatAvatarPath = entry.avatarPath;
      this.chatInitials = entry.initials;
      this.chatMuted = effectiveMuted(entry, scopeMutedForKind(entry.kind));
    }
    const count: number = store.supergroupMemberCount(this.chatId);
    if (count > 0) {
      this.memberCount = count;
    }
  }

  private ensureMemberCount(targetChatId: number): void {
    const store = getChatStore();
    const cached: number = store.supergroupMemberCount(targetChatId);
    if (cached > 0) {
      this.memberCount = cached;
      return;
    }
    const sgId: number = store.supergroupIdOf(targetChatId);
    if (sgId <= 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getSupergroup' };
    req['supergroup_id'] = sgId;
    getTdClient().send(req).then((sg: TdObject): void => {
      if (!this.active || this.chatId !== targetChatId) {
        return;
      }
      const count: number = (sg['member_count'] as number | undefined) ?? 0;
      if (count > 0) {
        this.memberCount = count;
      }
    }).catch((): void => {});
  }

  private subtitleText(): string {
    if (this.memberCount > 0) {
      return str('subtitle_members_only', `${this.memberCount}`);
    }
    return '';
  }

  @Builder
  headerMoreMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_circle')),
        content: $r('app.string.ft_new_topic')
      })
        .onClick((): void => {
          requestForumNewTopic();
        });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r(this.chatMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash')),
        content: this.chatMuted ? $r('app.string.cp_unmute') : $r('app.string.cp_mute')
      })
        .onClick((): void => {
          if (this.chatId !== 0) {
            setMute(this.chatId, this.chatMuted ? 0 : MUTE_LONG);
          }
        });
    }
  }

  build() {
    Row({ space: 6 }) {
      if (this.chatId !== 0) {
        // 返回按钮（触发抽屉右滑退出动画回到常规会话列表）
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(22)
            .fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(42).height(42).borderRadius(21)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => {
          if (this.searching) {
            this.searching = false;
            this.searchQuery = '';
            AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_SEARCH_QUERY, '');
            return;
          }
          closeForumDrawer();
        });

        if (this.searching) {
          TextInput({ placeholder: $r('app.string.cp_search'), text: this.searchQuery })
            .fontSize(15)
            .height(38)
            .layoutWeight(1)
            .onChange((val: string): void => {
              this.searchQuery = val;
              AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_SEARCH_QUERY, val);
            });
        } else {
          // 群头像 + 群标题 + 静音图标 + 成员数副标题（点击进入群资料页）
          Row({ space: 10 }) {
            AvatarView({
              avatarSize: 40,
              avatarPath: this.chatAvatarPath,
              initials: this.chatInitials,
              colorSeed: this.chatId
            });
            Column({ space: 2 }) {
              Row({ space: 4 }) {
                Text(this.chatTitle)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_PRIMARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .flexShrink(1);
                if (this.chatMuted) {
                  SymbolGlyph($r('sys.symbol.bell_slash'))
                    .fontSize(14)
                    .fontColor([COLOR_ICON_SECONDARY])
                    .flexShrink(0);
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center);

              if (this.subtitleText() !== '') {
                Text(this.subtitleText())
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            if (this.chatId !== 0) {
              navigateToChatProfile({ 'chatId': this.chatId });
            }
          });
        }

        // 搜索按钮
        Row() {
          SymbolGlyph($r(this.searching ? 'sys.symbol.xmark' : 'sys.symbol.magnifyingglass'))
            .fontSize(21)
            .fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(40).height(40).borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => {
          if (this.searching) {
            this.searching = false;
            this.searchQuery = '';
            AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_SEARCH_QUERY, '');
          } else {
            this.searching = true;
          }
        });

        // 更多操作按钮（竖排三点 ⋮，与图 1 样式一致）
        Column({ space: 3.5 }) {
          Circle({ width: 3.6, height: 3.6 }).fill(COLOR_TEXT_PRIMARY);
          Circle({ width: 3.6, height: 3.6 }).fill(COLOR_TEXT_PRIMARY);
          Circle({ width: 3.6, height: 3.6 }).fill(COLOR_TEXT_PRIMARY);
        }
        .width(40).height(40).borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .bindMenu(this.headerMoreMenu(), { systemMaterial: overlayMaterial('menu') });
      }
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 6, right: 6 })
    .alignItems(VerticalAlign.Center)
    .enabled(this.drawerOpen)
    .hitTestBehavior(this.drawerOpen ? HitTestMode.Default : HitTestMode.None)
    .translate({ x: this.drawerOpen ? 0 : this.slideWidth() })
    .animation({
      duration: powerAnimationDuration(
        KEY_POWER_SMOOTH_TRANSITIONS,
        this.drawerOpen ? FORUM_DRAWER_OPEN_MS : FORUM_DRAWER_CLOSE_MS
      ),
      curve: Curve.FastOutSlowIn
    });
  }
}

// 右侧话题主面板（挂载于 x = 72vp..100%，左侧 0..72vp 直接露出真实的 ChatRow 头像列）：
// 打开时从右侧滑入，退出时向右滑出原路退回，全程无需隐藏或重建底层 Tabs 会话列表。
@Component
export struct ForumSplitView {
  @StorageProp(KEY_ACTIVE_FORUM_CHAT_ID) @Watch('onTargetChanged') chatId: number = 0;
  @StorageProp(KEY_ACTIVE_FORUM_OPEN) @Watch('onOpenChanged') drawerOpen: boolean = false;
  @StorageProp(KEY_ACTIVE_FORUM_SEARCH_QUERY) @Watch('onSearchQueryChanged') searchQuery: string = '';
  @StorageProp(KEY_ACTIVE_FORUM_NEW_TOPIC_EPOCH) @Watch('onNewTopicRequested') newTopicEpoch: number = 0;
  @Prop @Watch('onNavBarVisibleChanged') navBarVisible: boolean = true;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('navBarWidth') private navBarW: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLangChanged') langEpoch: number = 0;
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(SCOPE_MUTE_EPOCH) @Watch('onScopeMuteChanged') scopeMuteEpoch: number = 0;
  @StorageProp(CHAT_LIST_NOW) nowSec: number = Math.floor(Date.now() / 1000);

  @State private chatMuted: boolean = false;
  @State @Watch('syncRowsData') private rows: ForumTopicRow[] = [];
  @State private loadState: string = 'loading';
  @State private showNameInput: boolean = false;
  @State private pendingTopicName: string = '';
  @State private creating: boolean = false;
  @State private rightPaneW: number = 0;
  @State private topicsSwitchOpacity: number = 1;
  @State private topicsSwitchOffsetY: number = 0;

  private renameTarget: ForumTopicRow | null = null;
  private topicsStore: ForumTopicsStore = new ForumTopicsStore(getTdClient());
  private rowsData: KeyedListDataSource<ForumTopicRow> = new KeyedListDataSource<ForumTopicRow>('forum-split-topics');
  private unsubTopics: (() => void) | null = null;
  private unsubChatStore: (() => void) | null = null;
  private active: boolean = false;
  private needsReloadOnReopen: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.unsubTopics = this.topicsStore.subscribe((): void => {
      if (!this.active) {
        return;
      }
      this.rows = this.topicsStore.getRows();
      this.loadState = this.topicsStore.getState();
    });
    this.unsubChatStore = getChatStore().subscribeChanges((): void => {
      if (!this.active || this.chatId === 0) {
        return;
      }
      this.refreshMuteState();
    });
    if (this.chatId !== 0) {
      this.bindChat();
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.unsubTopics?.();
    this.unsubTopics = null;
    this.unsubChatStore?.();
    this.unsubChatStore = null;
    this.topicsStore.close();
  }

  private effectiveRightPaneW(): number {
    if (this.rightPaneW > 0) {
      return this.rightPaneW;
    }
    const totalW: number = this.navBarW > 0 ? this.navBarW : this.screenW;
    return Math.max(240, totalW - FORUM_LEFT_RAIL_WIDTH);
  }

  private onTargetChanged(): void {
    if (!this.active) {
      return;
    }
    this.showNameInput = false;
    this.pendingTopicName = '';
    this.renameTarget = null;
    if (this.chatId === 0) {
      return;
    }
    const wasAlreadyOpen: boolean = this.drawerOpen && this.topicsStore.getChatId() !== 0;
    this.bindChat();
    const dur: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180);
    if (dur > 0 && wasAlreadyOpen) {
      this.topicsSwitchOpacity = 0.35;
      this.topicsSwitchOffsetY = 6;
      animateTo({
        duration: dur,
        curve: Curve.FastOutSlowIn
      }, (): void => {
        this.topicsSwitchOpacity = 1;
        this.topicsSwitchOffsetY = 0;
      });
    }
  }

  private onOpenChanged(): void {
    if (!this.active) {
      return;
    }
    if (!this.drawerOpen) {
      this.showNameInput = false;
      this.pendingTopicName = '';
      this.renameTarget = null;
      this.needsReloadOnReopen = true;
      return;
    }
    if (this.chatId !== 0 && (this.topicsStore.getChatId() !== this.chatId || this.needsReloadOnReopen)) {
      this.bindChat();
    }
  }

  private onSearchQueryChanged(): void {
    if (this.active && this.chatId !== 0) {
      this.topicsStore.setQuery(this.searchQuery);
    }
  }

  private onNewTopicRequested(): void {
    if (this.active && this.chatId !== 0 && this.drawerOpen) {
      this.renameTarget = null;
      this.pendingTopicName = '';
      this.showNameInput = true;
    }
  }

  private onNavBarVisibleChanged(): void {
    if (this.active && this.navBarVisible && this.chatId !== 0) {
      this.topicsStore.reload();
      this.refreshMuteState();
    }
  }

  private onLangChanged(): void {
    if (this.active && this.chatId !== 0) {
      this.topicsStore.reload();
    }
  }

  private onScopeMuteChanged(): void {
    if (this.active && this.chatId !== 0) {
      this.refreshMuteState();
    }
  }

  private bindChat(): void {
    if (this.chatId === 0) {
      return;
    }
    this.needsReloadOnReopen = false;
    this.refreshMuteState();
    this.topicsStore.open(this.chatId);
    this.rows = this.topicsStore.getRows();
    this.loadState = this.topicsStore.getState();
  }

  private refreshMuteState(): void {
    const entry: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (entry !== undefined) {
      this.chatMuted = effectiveMuted(entry, scopeMutedForKind(entry.kind));
    }
  }

  private syncRowsData(): void {
    const activeChatId: number = this.topicsStore.getChatId();
    this.rowsData.update(
      this.rows,
      this.rows.map((row: ForumTopicRow): string => `${activeChatId}_${row.threadId}`),
      this.rows.map((row: ForumTopicRow): string => `${activeChatId}_${forumTopicRowKey(row)}`)
    );
  }

  private openTopic(row: ForumTopicRow): void {
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'forumTopicId': row.threadId,
      'topicName': row.name
    };
    navigateToChat(params, 'navbar').catch(logChatNavFailure);
  }

  private topicRequest(type: string, topicId: number): TdRequest {
    const req: TdRequest = { '@type': type };
    req['chat_id'] = this.chatId;
    req['forum_topic_id'] = topicId;
    return req;
  }

  private manageFailed(action: string, e: TdError): void {
    logE(`ForumSplitView.${action} failed: ${e.message}`);
    promptAction.showToast({
      message: str('ft_action_failed', action === 'delete' ? str('delete') : str('ft_action_word')),
      duration: 2000
    });
  }

  private togglePinned(row: ForumTopicRow): void {
    const req = this.topicRequest('toggleForumTopicIsPinned', row.threadId);
    req['is_pinned'] = !row.isPinned;
    getTdClient().send(req).catch((e: TdError): void => this.manageFailed('pin', e));
  }

  private toggleClosed(row: ForumTopicRow): void {
    const req = this.topicRequest('toggleForumTopicIsClosed', row.threadId);
    req['is_closed'] = !row.isClosed;
    getTdClient().send(req).catch((e: TdError): void => this.manageFailed('close', e));
  }

  private renameTopic(row: ForumTopicRow, name: string): void {
    if (name.trim() === '' || name.trim() === row.name) {
      return;
    }
    const req = this.topicRequest('editForumTopic', row.threadId);
    req['name'] = name.trim();
    req['edit_icon_custom_emoji'] = false;
    getTdClient().send(req).catch((e: TdError): void => this.manageFailed('rename', e));
  }

  private confirmDelete(row: ForumTopicRow): void {
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.ft_delete_topic'),
      message: str('ft_delete_confirm', row.name),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.delete'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) {
        return;
      }
      getTdClient().send(this.topicRequest('deleteForumTopic', row.threadId))
        .then((): void => {
          this.topicsStore.reload();
        })
        .catch((e: TdError): void => this.manageFailed('delete', e));
    }).catch((): void => {});
  }

  private showTopicMenu(row: ForumTopicRow): void {
    const prompt = this.getUIContext().getPromptAction();
    if (row.isGeneral) {
      prompt.showActionMenu({
        title: row.name,
        buttons: [{ text: row.isPinned ? $r('app.string.ft_unpin') : $r('app.string.ft_pin'), color: '#007AFF' }]
      }).then((result): void => {
        if (result.index === 0) {
          this.togglePinned(row);
        }
      }).catch((): void => {});
      return;
    }
    prompt.showActionMenu({
      title: row.name,
      buttons: [
        { text: row.isPinned ? $r('app.string.ft_unpin') : $r('app.string.ft_pin'), color: '#007AFF' },
        { text: row.isClosed ? $r('app.string.ft_reopen') : $r('app.string.ft_close_topic'), color: '#007AFF' },
        { text: $r('app.string.ft_rename'), color: '#007AFF' },
        { text: $r('app.string.ft_delete_topic'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index === 0) {
        this.togglePinned(row);
      } else if (result.index === 1) {
        this.toggleClosed(row);
      } else if (result.index === 2) {
        this.renameTarget = row;
        this.pendingTopicName = row.name;
        this.showNameInput = true;
      } else if (result.index === 3) {
        this.confirmDelete(row);
      }
    }).catch((): void => {});
  }

  private createTopic(name: string): void {
    if (this.creating || name.trim() === '') {
      return;
    }
    this.creating = true;
    const req: TdRequest = { '@type': 'createForumTopic' };
    req['chat_id'] = this.chatId;
    req['name'] = name.trim();
    getTdClient().send(req).then((info: TdObject): void => {
      this.creating = false;
      const threadId: number = (info['forum_topic_id'] as number | undefined) ?? 0;
      if (threadId > 0) {
        this.topicsStore.reload();
        this.openTopic({
          threadId: threadId, name: name.trim(), iconColor: '#6FB9F0',
          isGeneral: false, isClosed: false, isPinned: false,
          unreadCount: 0, lastMessageText: ''
        });
      }
    }).catch((e: TdError): void => {
      this.creating = false;
      logE(`ForumSplitView.createForumTopic failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.ft_create_failed'), duration: 2000 });
    });
  }

  build() {
    Column() {
      if (this.loadState === 'loading' && this.rows.length === 0) {
        Column() {
          LoadingProgress().width(34).height(34);
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error' && this.rows.length === 0) {
        Column({ space: 10 }) {
          Text($r('app.string.ft_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          Button($r('app.string.settings_retry')).onClick((): void => {
            this.topicsStore.reload();
          });
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else {
        List() {
          LazyForEach(this.rowsData, (row: ForumTopicRow) => {
            ListItem() {
              ForumSplitTopicRow({
                name: row.name,
                iconColor: row.iconColor,
                iconCustomEmojiPath: row.iconCustomEmojiPath ?? '',
                iconEmoji: row.iconEmoji ?? '',
                isGeneral: row.isGeneral,
                isClosed: row.isClosed,
                isPinned: row.isPinned,
                unreadCount: row.unreadCount,
                lastMessageText: row.lastMessageText,
                lastMessageDate: row.lastMessageDate ?? 0,
                lastSenderName: row.lastSenderName ?? '',
                lastMessageThumb: row.lastMessageThumb ?? '',
                topicMuted: (row.isMuted ?? false) || this.chatMuted,
                nowSec: this.nowSec
              });
            }
            .onClick((): void => this.openTopic(row))
            .gesture(LongPressGesture({ fingers: 1, repeat: false })
              .onAction((): void => this.showTopicMenu(row)));
          }, (row: ForumTopicRow, index: number): string =>
            guardKey(this.rowsData.keyTableId, index, `${this.topicsStore.getChatId()}_${forumTopicRowKey(row)}`));
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        .cachedCount(6)
        .scrollBar(BarState.Off)
        .contentEndOffset(this.bottomSafe + DOCK_CLEARANCE_VP)
        .opacity(this.topicsSwitchOpacity)
        .translate({ y: this.topicsSwitchOffsetY });
      }

      if (this.showNameInput) {
        Column({ space: 10 }) {
          Text(this.renameTarget !== null ? $r('app.string.ft_rename_topic') : $r('app.string.ft_new_topic'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          TextInput({ placeholder: $r('app.string.ft_topic_name'), text: this.pendingTopicName })
            .fontSize(15).height(42)
            .onChange((value: string): void => {
              this.pendingTopicName = value;
            });
          Row({ space: 12 }) {
            Button($r('app.string.cancel')).buttonStyle(ButtonStyleMode.NORMAL).layoutWeight(1)
              .onClick((): void => {
                this.showNameInput = false;
                this.pendingTopicName = '';
                this.renameTarget = null;
              });
            Button(this.renameTarget !== null ? $r('app.string.save')
              : (this.creating ? $r('app.string.creating_dots') : $r('app.string.create')))
              .backgroundColor(COLOR_PRIMARY).layoutWeight(1)
              .enabled(!this.creating && this.pendingTopicName.trim() !== '')
              .onClick((): void => {
                const name: string = this.pendingTopicName;
                const target: ForumTopicRow | null = this.renameTarget;
                this.showNameInput = false;
                this.pendingTopicName = '';
                this.renameTarget = null;
                if (target !== null) {
                  this.renameTopic(target, name);
                } else {
                  this.createTopic(name);
                }
              });
          }
          .width('100%');
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: this.bottomSafe + DOCK_CLEARANCE_VP })
        .backgroundColor(COLOR_SURFACE)
        .border({ width: { top: 0.5 }, color: COLOR_DIVIDER });
      }
    }
    .width(`calc(100% - ${FORUM_LEFT_RAIL_WIDTH}vp)`)
    .height('100%')
    .margin({ left: FORUM_LEFT_RAIL_WIDTH })
    .backgroundColor(COLOR_SURFACE)
    .border({ width: { left: 0.5, top: 0.5 }, color: COLOR_DIVIDER })
    .shadow({ radius: 14, color: '#14000000', offsetX: -3, offsetY: 0 })
    .enabled(this.drawerOpen)
    .hitTestBehavior(this.drawerOpen ? HitTestMode.Default : HitTestMode.None)
    .onAreaChange((_old: Area, area: Area): void => {
      const w: number = area.width as number;
      if (w > 0 && w !== this.rightPaneW) {
        this.rightPaneW = w;
      }
    })
    .translate({ x: this.drawerOpen ? 0 : this.effectiveRightPaneW() + 24 })
    .animation({
      duration: powerAnimationDuration(
        KEY_POWER_SMOOTH_TRANSITIONS,
        this.drawerOpen ? FORUM_DRAWER_OPEN_MS : FORUM_DRAWER_CLOSE_MS
      ),
      curve: Curve.FastOutSlowIn
    });
  }
}

@Reusable
@Component
export struct ForumSplitTopicRow {
  @Prop name: string = '';
  @Prop iconColor: string = '#6FB9F0';
  @Prop iconCustomEmojiPath: string = '';
  @Prop iconEmoji: string = '';
  @Prop isGeneral: boolean = false;
  @Prop isClosed: boolean = false;
  @Prop isPinned: boolean = false;
  @Prop unreadCount: number = 0;
  @Prop lastMessageText: string = '';
  @Prop lastMessageDate: number = 0;
  @Prop lastSenderName: string = '';
  @Prop lastMessageThumb: string = '';
  @Prop topicMuted: boolean = false;
  @Prop nowSec: number = 0;

  @Builder
  topicIcon() {
    if (this.iconCustomEmojiPath !== '') {
      Image('file://' + this.iconCustomEmojiPath)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .flexShrink(0);
    } else if (this.iconEmoji !== '') {
      Text(this.iconEmoji)
        .fontSize(17)
        .flexShrink(0);
    } else if (this.isGeneral) {
      Text('#')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_ICON_SECONDARY)
        .flexShrink(0);
    } else if (!startsWithEmojiSymbol(this.name)) {
      Row() {
        Text(this.name.substring(0, 1).toUpperCase())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White);
      }
      .width(20)
      .height(20)
      .borderRadius(6)
      .backgroundColor(this.iconColor)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0);
    }
  }

  build() {
    Column({ space: 6 }) {
      // 第一行：话题图标 + 话题标题 + 右侧锁定/置顶图标与时间
      Row({ space: 6 }) {
        this.topicIcon();
        Text(this.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
        Row({ space: 4 }) {
          if (this.isClosed) {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(13)
              .fontColor([COLOR_ICON_SECONDARY]);
          }
          if (this.isPinned) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(13)
              .fontColor([COLOR_ICON_SECONDARY]);
          }
          if (this.lastMessageDate > 0) {
            Text(formatTime(this.lastMessageDate, this.nowSec))
              .fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        .alignItems(VerticalAlign.Center)
        .flexShrink(0);
      }
      .width('100%')
      .alignItems(VerticalAlign.Top);

      // 第二行：发送者蓝字 + 媒体缩略图 + 消息预览 + 右侧未读胶囊
      Row({ space: 8 }) {
        Row() {
          if (this.lastSenderName !== '') {
            Text(`${this.lastSenderName}: `)
              .fontSize(14)
              .fontColor(COLOR_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 118 })
              .flexShrink(0);
          }
          if (CHATLIST_PREVIEW_THUMB_ENABLED && this.lastMessageThumb !== '') {
            Image(this.lastMessageThumb)
              .draggable(false)
              .width(18)
              .height(18)
              .borderRadius(3)
              .objectFit(ImageFit.Cover)
              .sourceSize({ width: 54, height: 54 })
              .autoResize(true)
              .margin({ right: 5 })
              .flexShrink(0);
          }
          Text(this.lastMessageText !== ''
            ? (CHATLIST_PREVIEW_THUMB_ENABLED && this.lastMessageThumb !== ''
              ? stripPreviewIcon(this.lastMessageText)
              : this.lastMessageText)
            : $r('app.string.ft_no_messages'))
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center);

        if (this.unreadCount > 0) {
          Text(unreadBadgeText(this.unreadCount))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_ON_PRIMARY)
            .constraintSize({ minWidth: 22 })
            .height(22)
            .padding({ left: 7, right: 7 })
            .textAlign(TextAlign.Center)
            .backgroundColor(this.topicMuted ? COLOR_MUTED_BADGE : COLOR_PRIMARY)
            .borderRadius(11)
            .flexShrink(0);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .backgroundColor(COLOR_SURFACE)
    .border({ width: { bottom: 0.5 }, color: COLOR_DIVIDER });
  }
}
