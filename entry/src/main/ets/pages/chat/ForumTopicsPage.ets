import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { formatPreview } from '../../util/formatPreview';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logE } from '../../util/log';
import { HdsNavDestination } from '@kit.UIDesignKit';

const CARD_RADIUS: number = 14;
// forumTopicIcon.color 的取值集合（TDLib 固定的六色）。
const TOPIC_COLORS: Map<number, string> = new Map([
  [0x6FB9F0, '#6FB9F0'], [0xFFD67E, '#FFD67E'], [0xCB86DB, '#CB86DB'],
  [0x8EEE98, '#8EEE98'], [0xFF93B2, '#FF93B2'], [0xFB6F5F, '#FB6F5F']
]);

interface TopicRow {
  threadId: number;
  name: string;
  iconColor: string;
  isGeneral: boolean;
  isClosed: boolean;
  isPinned: boolean;
  unreadCount: number;
  lastMessageText: string;
}

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再需要进 main_pages.json。
@Builder
export function ForumTopicsPageBuilder(): void {
  ForumTopicsPage();
}

// 话题群（forum）的话题列表页。点话题 → ChatPage(threadRootId)。
@Component
export struct ForumTopicsPage {
  // 本页所在的 Navigation 栈，onReady 时拿到。返回按钮靠它出栈——本页已不是
  // router 页，router.back() 弹不到自己。
  private navStack: NavPathStack | undefined = undefined;
  // 路由参数。router 时代靠 router.getParams() 现取，NavDestination 要在
  // onReady 里从 NavDestinationContext 拿，而 onReady 实测晚于 aboutToAppear
  // （平板 API 26，见 ChatPage 的同名注释），所以吃参数的那一段整体挪进了
  // applyRouteParams()。
  private navParams: Record<string, Object> | undefined = undefined;
  // applyRouteParams() 的一次性守卫：那段里 push 了两个 TDLib 订阅，重入会把
  // 同一个订阅叠两份，而 aboutToDisappear 只退订它当时看到的那一份。
  private paramsApplied: boolean = false;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State title: string = str('ft_topics');
  @State rows: TopicRow[] = [];
  @State loadState: string = 'loading'; // loading | ready | error
  @State creating: boolean = false;
  private chatId: number = 0;
  private active: boolean = false;

  private unsubs: Array<() => void> = [];

  aboutToAppear(): void {
    // 留在这里的只有这一行：它与路由参数无关，且必须早于任何 load() 的回调
    // 落地（onTopicUpdate/load 都用 this.active 判断本页是否还在）。
    this.active = true;
    // 下面原本还有一段（读 params → 定 chatId/title → 两个 TDLib 订阅 → load()）。
    // 实测 onReady 晚于 aboutToAppear，在这里读 navParams 只会读到 undefined、
    // chatId 落成 0、页面静默停在 error 态，所以那段整体搬进了 applyRouteParams()。
  }

  // 路由参数就绪后的初始化。就是迁移前 aboutToAppear 的后半段，顺序一字未改。
  private applyRouteParams(): void {
    if (this.paramsApplied) {
      return;
    }
    this.paramsApplied = true;
    const params = this.navParams;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    const title = params !== undefined ? ((params['title'] as string | undefined) ?? '') : '';
    if (title !== '') {
      this.title = title;
    }
    // 实时刷新：名称/关闭状态变化（updateForumTopicInfo）与
    // 置顶/未读变化（updateForumTopic）就地更新对应行。
    this.unsubs.push(getTdClient().onUpdate('updateForumTopicInfo',
      (u: TdObject): void => this.onTopicInfoUpdate(u)));
    this.unsubs.push(getTdClient().onUpdate('updateForumTopic',
      (u: TdObject): void => this.onTopicUpdate(u)));
    this.load();
  }

  // 返回上一层。**不能用 router.back()**：本页是 HdsNavDestination，router 页栈里
  // 只剩 Index 一层，router.back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  private goBack(): void {
    const stack = this.navStack;
    if (stack === undefined) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 router.back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ForumTopicsPage.goBack: navStack missing, back ignored');
      return;
    }
    // pop() 弹的就是本页这一层。栈空时它返回 undefined，但那意味着"本页正显示
    // 却不在栈里"，不可能发生，故不另做处理。
    stack.pop();
  }

  aboutToDisappear(): void {
    this.active = false;
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
  }

  private onTopicInfoUpdate(u: TdObject): void {
    const info = u['info'] as TdObject | undefined;
    if (info === undefined ||
      ((info['chat_id'] as number | undefined) ?? 0) !== this.chatId) {
      return;
    }
    const topicId: number = (info['forum_topic_id'] as number | undefined) ?? 0;
    this.rows = this.sortRows(this.rows.map((row: TopicRow): TopicRow => {
      if (row.threadId !== topicId) {
        return row;
      }
      const next: TopicRow = {
        threadId: row.threadId,
        name: (info['name'] as string | undefined) ?? row.name,
        iconColor: row.iconColor,
        isGeneral: row.isGeneral,
        isClosed: (info['is_closed'] as boolean | undefined) ?? row.isClosed,
        isPinned: row.isPinned,
        unreadCount: row.unreadCount,
        lastMessageText: row.lastMessageText
      };
      return next;
    }));
  }

  private onTopicUpdate(u: TdObject): void {
    if (((u['chat_id'] as number | undefined) ?? 0) !== this.chatId) {
      return;
    }
    const topicId: number = (u['forum_topic_id'] as number | undefined) ?? 0;
    const isPinned: boolean = (u['is_pinned'] as boolean | undefined) ?? false;
    this.rows = this.sortRows(this.rows.map((row: TopicRow): TopicRow => {
      if (row.threadId !== topicId) {
        return row;
      }
      const next: TopicRow = {
        threadId: row.threadId, name: row.name, iconColor: row.iconColor,
        isGeneral: row.isGeneral, isClosed: row.isClosed,
        isPinned: isPinned,
        unreadCount: row.unreadCount, lastMessageText: row.lastMessageText
      };
      return next;
    }));
  }

  // 置顶话题排前（服务器 order 之上的本地稳定排序）。
  private sortRows(rows: TopicRow[]): TopicRow[] {
    const pinned: TopicRow[] = rows.filter((row: TopicRow): boolean => row.isPinned);
    const rest: TopicRow[] = rows.filter((row: TopicRow): boolean => !row.isPinned);
    return [...pinned, ...rest];
  }

  // 迁移前是 onPageShow，方法体一字未动，改由 HdsNavDestination.onShown() 触发。
  private handleShown(): void {
    // 从话题内返回时刷新未读数/最后消息。
    if (this.loadState === 'ready') {
      this.load();
    }
  }

  private load(): void {
    if (this.chatId === 0) {
      this.loadState = 'error';
      return;
    }
    const req: TdRequest = { '@type': 'getForumTopics' };
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['offset_date'] = 0;
    req['offset_message_id'] = 0;
    req['offset_forum_topic_id'] = 0;
    req['limit'] = 100;
    getTdClient().send(req).then((res: TdObject): void => {
      if (!this.active) {
        return;
      }
      const topics: TdObject[] = (res['topics'] as TdObject[] | undefined) ?? [];
      this.rows = this.sortRows(topics.map((topic: TdObject): TopicRow => this.parseTopic(topic))
        .filter((row: TopicRow): boolean => row.threadId > 0));
      this.loadState = 'ready';
    }).catch((e: TdError): void => {
      if (!this.active) {
        return;
      }
      logE(`ForumTopicsPage.getForumTopics failed: ${e.message}`);
      this.loadState = 'error';
    });
  }

  private parseTopic(topic: TdObject): TopicRow {
    const info = topic['info'] as TdObject | undefined;
    const threadId: number = info !== undefined
      ? ((info['forum_topic_id'] as number | undefined) ?? 0) : 0;
    const name: string = info !== undefined
      ? ((info['name'] as string | undefined) ?? '') : '';
    const icon = info !== undefined ? info['icon'] as TdObject | undefined : undefined;
    const colorValue: number = icon !== undefined
      ? ((icon['color'] as number | undefined) ?? 0) : 0;
    const lastMessage = topic['last_message'] as TdObject | undefined;
    return {
      threadId: threadId,
      name: name !== '' ? name : str('ft_topics'),
      iconColor: TOPIC_COLORS.get(colorValue) ?? '#6FB9F0',
      isGeneral: info !== undefined
        ? ((info['is_general'] as boolean | undefined) ?? false) : false,
      isClosed: info !== undefined
        ? ((info['is_closed'] as boolean | undefined) ?? false) : false,
      isPinned: (topic['is_pinned'] as boolean | undefined) ?? false,
      unreadCount: (topic['unread_count'] as number | undefined) ?? 0,
      lastMessageText: formatPreview(lastMessage ?? null)
    };
  }

  // --- 话题管理（长按菜单） ---

  private topicRequest(type: string, topicId: number): TdRequest {
    const req: TdRequest = { '@type': type };
    req['chat_id'] = this.chatId;
    req['forum_topic_id'] = topicId;
    return req;
  }

  private manageFailed(action: string, e: TdError): void {
    logE(`ForumTopicsPage.${action} failed: ${e.message}`);
    promptAction.showToast({ message: str('ft_action_failed', action === 'delete' ? str('delete') : str('ft_action_word')), duration: 2000 });
  }

  private togglePinned(row: TopicRow): void {
    const req = this.topicRequest('toggleForumTopicIsPinned', row.threadId);
    req['is_pinned'] = !row.isPinned;
    getTdClient().send(req).catch((e: TdError): void => this.manageFailed('pin', e));
  }

  private toggleClosed(row: TopicRow): void {
    const req = this.topicRequest('toggleForumTopicIsClosed', row.threadId);
    req['is_closed'] = !row.isClosed;
    getTdClient().send(req).catch((e: TdError): void => this.manageFailed('close', e));
  }

  private renameTopic(row: TopicRow, name: string): void {
    if (name.trim() === '' || name.trim() === row.name) {
      return;
    }
    const req = this.topicRequest('editForumTopic', row.threadId);
    req['name'] = name.trim();
    req['edit_icon_custom_emoji'] = false;
    getTdClient().send(req).catch((e: TdError): void => this.manageFailed('rename', e));
  }

  private confirmDelete(row: TopicRow): void {
    promptAction.showDialog({
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
          this.rows = this.rows.filter((item: TopicRow): boolean =>
            item.threadId !== row.threadId);
        })
        .catch((e: TdError): void => this.manageFailed('delete', e));
    });
  }

  private showTopicMenu(row: TopicRow): void {
    if (row.isGeneral) {
      // General 话题不可删除/重命名，只支持置顶与隐藏（隐藏暂不做）。
      promptAction.showActionMenu({
        title: row.name,
        buttons: [{ text: row.isPinned ? $r('app.string.ft_unpin') : $r('app.string.ft_pin'), color: '#007AFF' }]
      }).then((result): void => {
        if (result.index === 0) {
          this.togglePinned(row);
        }
      }).catch((): void => {});
      return;
    }
    promptAction.showActionMenu({
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

  private renameTarget: TopicRow | null = null;

  private openTopic(row: TopicRow): void {
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'forumTopicId': row.threadId,
      'topicName': row.name
    };
    navigateToChat(params, 'content').catch(logChatNavFailure);
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
        this.load();
        this.openTopic({
          threadId: threadId, name: name.trim(), iconColor: '#6FB9F0',
          isGeneral: false, isClosed: false, isPinned: false,
          unreadCount: 0, lastMessageText: ''
        });
      }
    }).catch((e: TdError): void => {
      this.creating = false;
      logE(`ForumTopicsPage.createForumTopic failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.ft_create_failed'), duration: 2000 });
    });
  }

  @State showNameInput: boolean = false;
  @State pendingTopicName: string = '';

  @Builder
  topicRowView(row: TopicRow) {
    Row({ space: 12 }) {
      Row() {
        Text(row.isGeneral ? '#' : row.name.substring(0, 1).toUpperCase())
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White);
      }
      .width(44).height(44).borderRadius(12)
      .backgroundColor(row.iconColor)
      .justifyContent(FlexAlign.Center);
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(row.name).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          if (row.isPinned) {
            SymbolGlyph($r('sys.symbol.pin_fill')).fontSize(12).fontColor([COLOR_TEXT_SECONDARY]);
          }
          if (row.isClosed) {
            SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
          }
        }
        .width('100%');
        Text(row.lastMessageText !== '' ? row.lastMessageText : $r('app.string.ft_no_messages'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (row.unreadCount > 0) {
        Text(row.unreadCount > 99 ? '99+' : `${row.unreadCount}`)
          .fontSize(12).fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(10).backgroundColor(COLOR_PRIMARY);
      }
    }
    .width('100%').padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .onClick((): void => this.openTopic(row))
    .gesture(LongPressGesture({ fingers: 1, repeat: false })
      .onAction((): void => this.showTopicMenu(row)));
  }

  build() {
    HdsNavDestination() {
    Column() {
      Row({ space: 6 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .onClick((): void => this.goBack());
        Column({ space: 1 }) {
          Text(this.title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(plural('ft_topic_count', this.rows.length, this.rows.length)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .onClick((): void => {
          this.showNameInput = true;
        });
      }
      .width('100%').padding({ left: 8, right: 8, top: this.topSafe + 6, bottom: 6 });
      if (this.loadState === 'loading') {
        Column() {
          LoadingProgress().width(34).height(34);
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.ft_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          Button($r('app.string.settings_retry')).onClick((): void => {
            this.loadState = 'loading';
            this.load();
          });
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else {
        List({ space: 8 }) {
          ForEach(this.rows, (row: TopicRow) => {
            ListItem() {
              this.topicRowView(row);
            }
          }, (row: TopicRow): string =>
            `topic_${row.threadId}_${row.unreadCount}_${row.lastMessageText}`);
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: this.bottomSafe + 12 });
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
            Button(this.renameTarget !== null ? $r('app.string.save') : (this.creating ? $r('app.string.creating_dots') : $r('app.string.create')))
              .backgroundColor(COLOR_PRIMARY).layoutWeight(1)
              .enabled(!this.creating && this.pendingTopicName.trim() !== '')
              .onClick((): void => {
                const name: string = this.pendingTopicName;
                const target: TopicRow | null = this.renameTarget;
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
        .padding({ left: 16, right: 16, top: 12, bottom: this.bottomSafe + 16 })
        .backgroundColor(COLOR_SURFACE)
        .borderRadius({ topLeft: 16, topRight: 16 });
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
    // 本页自绘标题栏（返回键 + 群名 + 话题数那一条），不要 HDS 的。
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
      this.navParams = ctx.pathInfo.param as Record<string, Object> | undefined;
      // 必须在这里调而不是等 aboutToAppear：实测 onReady 晚于 aboutToAppear。
      this.applyRouteParams();
    })
    .onShown((): void => { this.handleShown(); })
    .width('100%').height('100%');
  }
}
