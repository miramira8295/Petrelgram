import { HdsNavDestination } from '@kit.UIDesignKit';
import { DirectMessagesTopicRow, DirectMessagesTopicStore } from '../../store/DirectMessagesTopicStore';
import { getTdClient } from '../../tdkit/Globals';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { formatTime } from '../../util/formatTime';
import { logE } from '../../util/log';
import {
  COLOR_DIVIDER, COLOR_MUTED_BADGE, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const AVATAR_COLORS: string[] = [
  '#4A90E2', '#2F9E76', '#D16B5B', '#8B63C7', '#C58A22', '#3E8E99'
];

function avatarColor(senderId: number): string {
  const index = Math.abs(senderId) % AVATAR_COLORS.length;
  return AVATAR_COLORS[index];
}

@Builder
export function DirectMessagesTopicsPageBuilder(): void {
  DirectMessagesTopicsPage();
}

@Component
export struct DirectMessagesTopicsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State title: string = '';
  @State rows: DirectMessagesTopicRow[] = [];
  @State loadState: string = 'loading';
  @State query: string = '';
  @State nowSec: number = Math.floor(Date.now() / 1000);
  private navStack: NavPathStack | undefined = undefined;
  private navParams: Record<string, Object> | undefined = undefined;
  private paramsApplied: boolean = false;
  private chatId: number = 0;
  private openedTopicId: number = 0;
  private store: DirectMessagesTopicStore | null = null;
  private unsubscribeStore: (() => void) | null = null;
  private nowTimer: number = -1;

  aboutToAppear(): void {
    this.armClock();
    this.bindStore();
    this.store?.open(this.chatId);
  }

  aboutToDisappear(): void {
    if (this.nowTimer !== -1) {
      clearInterval(this.nowTimer);
      this.nowTimer = -1;
    }
    this.store?.close();
    this.unsubscribeStore?.();
    this.unsubscribeStore = null;
  }

  private applyRouteParams(): void {
    if (this.paramsApplied) {
      return;
    }
    this.paramsApplied = true;
    const params = this.navParams;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    this.title = params !== undefined ? ((params['title'] as string | undefined) ?? '') : '';
    const store = new DirectMessagesTopicStore(getTdClient());
    this.store = store;
    this.bindStore();
    store.open(this.chatId);
  }

  private bindStore(): void {
    const store = this.store;
    if (store === null || this.unsubscribeStore !== null) {
      return;
    }
    this.unsubscribeStore = store.subscribe(
      (rows: DirectMessagesTopicRow[], state: string): void => {
        this.rows = rows;
        this.loadState = state;
      });
  }

  private armClock(): void {
    if (this.nowTimer !== -1) {
      return;
    }
    this.nowSec = Math.floor(Date.now() / 1000);
    this.nowTimer = setInterval((): void => {
      this.nowSec = Math.floor(Date.now() / 1000);
    }, 30000);
  }

  private goBack(): void {
    if (this.navStack === undefined) {
      logE('DirectMessagesTopicsPage.goBack: navStack missing, back ignored');
      return;
    }
    this.navStack.pop();
  }

  private filteredRows(): DirectMessagesTopicRow[] {
    const needle = this.query.trim().toLowerCase();
    if (needle === '') {
      return this.rows;
    }
    return this.rows.filter((row: DirectMessagesTopicRow): boolean =>
      row.title.toLowerCase().indexOf(needle) >= 0 ||
      row.lastMessageText.toLowerCase().indexOf(needle) >= 0);
  }

  private openTopic(row: DirectMessagesTopicRow): void {
    this.openedTopicId = row.id;
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'directMessagesTopicId': row.id,
      'topicName': row.title
    };
    navigateToChat(params, 'content').catch(logChatNavFailure);
  }

  @Builder
  private avatar(row: DirectMessagesTopicRow) {
    Stack() {
      if (row.avatarPath !== '') {
        Image(row.avatarPath)
          .width(48).height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover);
      } else {
        Text(row.initials)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White);
      }
    }
    .width(48).height(48)
    .borderRadius(24)
    .backgroundColor(avatarColor(row.senderId))
    .alignContent(Alignment.Center);
  }

  @Builder
  private topicRow(row: DirectMessagesTopicRow) {
    Row({ space: 12 }) {
      this.avatar(row);
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text(row.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (row.lastMessageDate > 0) {
            Text(formatTime(row.lastMessageDate, this.nowSec))
              .fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        .width('100%');
        Row({ space: 8 }) {
          Text(row.lastMessageText !== '' ? row.lastMessageText : $r('app.string.ft_no_messages'))
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (row.unreadCount > 0) {
            Text(row.unreadCount > 99 ? '99+' : `${row.unreadCount}`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .constraintSize({ minWidth: 22 })
              .height(22)
              .padding({ left: 7, right: 7 })
              .borderRadius(11)
              .backgroundColor(COLOR_PRIMARY)
              .textAlign(TextAlign.Center);
          } else if (row.isMarkedUnread) {
            Circle({ width: 10, height: 10 }).fill(COLOR_MUTED_BADGE);
          }
        }
        .width('100%');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(COLOR_SURFACE)
    .border({ width: 0.5, color: COLOR_DIVIDER })
    .borderRadius(14)
    .onClick((): void => this.openTopic(row));
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 6 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(25)
              .fontColor([COLOR_TEXT_PRIMARY]);
          }
          .width(44).height(44)
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .onClick((): void => this.goBack());
          Text(this.title)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
        }
        .width('100%')
        .padding({ left: 8, right: 12, top: this.topSafe + 6, bottom: 6 });

        TextInput({ placeholder: $r('app.string.search_contacts'), text: this.query })
          .height(42)
          .margin({ left: 12, right: 12, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(COLOR_SURFACE)
          .onChange((value: string): void => { this.query = value; });

        if (this.loadState === 'loading' && this.rows.length === 0) {
          Column() {
            LoadingProgress().width(34).height(34);
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
        } else if (this.loadState === 'error' && this.rows.length === 0) {
          Column({ space: 10 }) {
            Text($r('app.string.ft_load_failed'))
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY);
            Button($r('app.string.settings_retry'))
              .onClick((): void => this.store?.open(this.chatId));
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
        } else if (this.filteredRows().length === 0) {
          Column() {
            Text($r('app.string.no_results'))
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
        } else {
          List({ space: 8 }) {
            ForEach(this.filteredRows(), (row: DirectMessagesTopicRow) => {
              ListItem() {
                this.topicRow(row);
              }
            }, (row: DirectMessagesTopicRow): string => `direct_${row.id}_${row.revision}`);
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: this.bottomSafe + 12 })
          .onReachEnd((): void => this.store?.loadMore());
        }
      }
      .width('100%').height('100%')
      .backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext): void => {
      this.navStack = context.pathStack;
      this.navParams = context.pathInfo.param as Record<string, Object> | undefined;
      this.applyRouteParams();
    })
    .onShown((): void => {
      this.armClock();
      this.bindStore();
      this.store?.open(this.chatId);
      if (this.openedTopicId > 0) {
        this.store?.refreshTopic(this.openedTopicId);
      }
    })
    .width('100%').height('100%');
  }
}
