import { router, promptAction } from '@kit.ArkUI';
import { ContactsStore, ContactItem } from '../../store/ContactsStore';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { AvatarView } from '../chatlist/AvatarView';
import {
  PublicUserSearchResult, searchPublicUsersDetailed
} from '../../store/PublicUserSearch';
import { parseOptionInteger } from '../../store/FolderApi';
import {
  NewBasicGroupResult, maxSelectableBasicGroupMembers, newGroupCreationErrorText,
  newGroupCreationOutcomeUncertain, newGroupTitleError, parseNewBasicGroupResult
} from '../../util/newGroupLogic';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logW } from '../../util/log';
import { navigateToChat } from '../../util/chatNav';
import { contentSideGutter, readableContentWidth } from '../../util/contentWidth';

const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const SEARCH_DELAY_MS: number = 350;
const DEFAULT_BASIC_GROUP_SIZE_MAX: number = 200;
const SKELETON_ROWS: number[] = [0, 1, 2, 3, 4];
// 选人屏那几张卡片左右各让出的边距，跟它们 width 里扣掉的 24vp 是同一个数。
const CARD_SIDE_MARGIN: number = 12;

@Entry
@Component
struct NewGroupPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State contacts: ContactItem[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State query: string = '';
  @State remoteUsers: ContactItem[] = [];
  @State knownRemoteUsers: ContactItem[] = [];
  @State remoteState: string = 'idle'; // idle | loading | ready | empty | error | timeout
  @State searchFocused: boolean = false;
  @State selectedIds: number[] = [];
  @State naming: boolean = false;
  // 'group'（基础群）| 'channel'（createNewSupergroupChat is_channel）。
  @State kind: string = 'group';
  @State channelDescription: string = '';
  @State title: string = '';
  @State titleError: string = '';
  @State createError: string = '';
  @State creating: boolean = false;
  @State openingCreatedChat: boolean = false;
  @State createdChatId: number = 0;
  @State creationOutcomeUnknown: boolean = false;
  @State maxSelectableMembers: number = DEFAULT_BASIC_GROUP_SIZE_MAX - 1;
  @State skeletonBright: boolean = false;
  private store: ContactsStore | null = null;
  private unsubscribe: (() => void) | null = null;
  private searchTimer: number = -1;
  private skeletonTimer: number = -1;
  private searchSequence: number = 0;
  private creationSequence: number = 0;
  private active: boolean = false;

  @Styles
  topActionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.74)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(CARD_BG)
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  @Styles
  primaryActionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  primaryActionPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.95, y: 0.95 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.loadBasicGroupLimit();
    const store = new ContactsStore(getTdClient());
    this.store = store;
    this.unsubscribe = store.subscribe((): void => {
      this.contacts = store.contacts;
      this.loading = store.loading;
      this.loadError = store.errorMessage;
      if (store.loading && store.contacts.length === 0) {
        this.startSkeletonPulse();
      } else {
        this.stopSkeletonPulse();
      }
    });
    store.open();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.searchSequence++;
    this.creationSequence++;
    this.stopSkeletonPulse();
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.store !== null) {
      this.store.close();
      this.store = null;
    }
  }

  onBackPress(): boolean {
    if (this.creating || this.openingCreatedChat) { return true; }
    if (this.naming) {
      this.back();
      return true;
    }
    return false;
  }

  private animationDuration(fallback: number): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, fallback);
  }

  private startSkeletonPulse(): void {
    if (this.skeletonTimer !== -1 || this.animationDuration(1) === 0) { return; }
    this.skeletonTimer = setInterval((): void => {
      this.skeletonBright = !this.skeletonBright;
    }, 680);
  }

  private stopSkeletonPulse(): void {
    if (this.skeletonTimer !== -1) {
      clearInterval(this.skeletonTimer);
      this.skeletonTimer = -1;
    }
    this.skeletonBright = false;
  }

  private loadBasicGroupLimit(): void {
    const request: TdRequest = { '@type': 'getOption' };
    request['name'] = 'basic_group_size_max';
    getTdClient().send(request).then((result: TdObject): void => {
      if (!this.active) { return; }
      // optionValueInteger 的 value 是 int64，TDLib 编码成字符串。
      const sizeMax = parseOptionInteger(result['value'], DEFAULT_BASIC_GROUP_SIZE_MAX);
      this.maxSelectableMembers = maxSelectableBasicGroupMembers(sizeMax);
    }).catch((error: TdError): void => {
      logW(`NewGroupPage basic_group_size_max failed: ${error.message}`);
    });
  }

  private retryContacts(): void {
    if (this.store !== null && !this.loading) { this.store.reload(); }
  }

  private onQueryChanged(value: string): void {
    this.query = value;
    this.scheduleRemoteSearch(value, SEARCH_DELAY_MS);
  }

  private scheduleRemoteSearch(value: string, delayMs: number): void {
    const sequence = ++this.searchSequence;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    const normalized = value.trim().replace(/^@/, '');
    if (normalized.length < 2) {
      this.remoteUsers = [];
      this.remoteState = 'idle';
      return;
    }
    this.remoteState = 'loading';
    const run = (): void => {
      this.searchTimer = -1;
      searchPublicUsersDetailed(getTdClient(), value).then(
        (result: PublicUserSearchResult): void => {
          if (!this.active || sequence !== this.searchSequence) { return; }
          this.remoteUsers = result.users;
          const known = [...this.knownRemoteUsers];
          for (const user of result.users) {
            if (!known.some((item: ContactItem): boolean => item.id === user.id)) {
              known.push(user);
            }
          }
          this.knownRemoteUsers = known;
          this.remoteState = result.state;
        }
      ).catch((error: TdError): void => {
        if (!this.active || sequence !== this.searchSequence) { return; }
        logW(`NewGroupPage.searchPublicUsers failed: ${error.message}`);
        this.remoteUsers = [];
        this.remoteState = 'error';
      });
    };
    if (delayMs <= 0) { run(); } else { this.searchTimer = setTimeout(run, delayMs); }
  }

  private retryRemoteSearch(): void {
    if (this.query.trim().replace(/^@/, '').length >= 2) {
      this.scheduleRemoteSearch(this.query, 0);
    }
  }

  private clearSearch(): void {
    this.onQueryChanged('');
  }

  private filteredContacts(): ContactItem[] {
    const value = this.query.trim().toLowerCase();
    if (value === '') { return this.contacts; }
    const localQuery = value.replace(/^@/, '');
    const result = this.contacts.filter((contact: ContactItem): boolean =>
      contact.name.toLowerCase().indexOf(localQuery) >= 0 ||
        contact.statusText.toLowerCase().indexOf(value) >= 0
    );
    for (const user of this.remoteUsers) {
      if (!result.some((item: ContactItem): boolean => item.id === user.id)) {
        result.push(user);
      }
    }
    return result;
  }

  private selected(userId: number): boolean {
    return this.selectedIds.indexOf(userId) >= 0;
  }

  private toggle(userId: number): void {
    if (this.creating || this.openingCreatedChat) { return; }
    let next: number[];
    if (this.selected(userId)) {
      next = this.selectedIds.filter((id: number): boolean => id !== userId);
    } else {
      if (this.selectedIds.length >= this.maxSelectableMembers) {
        promptAction.showToast({
          message: plural('ng_max_members', this.maxSelectableMembers, this.maxSelectableMembers), duration: 1800
        });
        return;
      }
      next = [...this.selectedIds, userId];
    }
    animateTo({ duration: this.animationDuration(170), curve: Curve.EaseOut }, (): void => {
      this.selectedIds = next;
    });
  }

  private contactFor(userId: number): ContactItem {
    const contact = [...this.contacts, ...this.knownRemoteUsers]
      .find((item: ContactItem): boolean => item.id === userId);
    if (contact !== undefined) { return contact; }
    return {
      id: userId, name: str('tab_contacts'), initials: '?', avatarPath: '', statusText: '',
      online: false, sortKey: 0
    };
  }

  private goNext(): void {
    if (this.selectedIds.length === 0) { return; }
    this.titleError = '';
    this.createError = '';
    animateTo({ duration: this.animationDuration(220), curve: Curve.EaseOut }, (): void => {
      this.naming = true;
    });
    setTimeout((): void => {
      if (this.active && this.naming) { focusControl.requestFocus('new_group_title'); }
    }, this.animationDuration(220) + 20);
  }

  private createActionEnabled(): boolean {
    if (!this.naming) { return this.selectedIds.length > 0 && !this.loading; }
    if (this.creating || this.openingCreatedChat || this.creationOutcomeUnknown) { return false; }
    if (this.createdChatId > 0) { return true; }
    // 频道不要求成员（创建后可选拉人）。
    return newGroupTitleError(this.title) === '' &&
      (this.kind === 'channel' || this.selectedIds.length > 0);
  }

  private headerActionText(): string {
    if (!this.naming) { return str('next'); }
    if (this.openingCreatedChat) { return str('opening'); }
    if (this.creating) { return str('creating'); }
    if (this.createdChatId > 0) { return str('open'); }
    return str('create');
  }

  private createGroup(): void {
    if (this.createdChatId > 0) {
      this.openCreatedGroup();
      return;
    }
    if (this.creating || this.openingCreatedChat || this.creationOutcomeUnknown) { return; }
    const validation = newGroupTitleError(this.title);
    if (validation !== '') {
      this.titleError = validation;
      return;
    }
    if (this.kind === 'channel') {
      this.createChannel();
      return;
    }
    if (this.selectedIds.length === 0 || this.selectedIds.length > this.maxSelectableMembers) {
      this.createError = str('ng_reselect_members');
      return;
    }
    const groupTitle = this.title.trim();
    const selectedSnapshot = this.selectedIds.slice();
    const sequence = ++this.creationSequence;
    this.titleError = '';
    this.createError = '';
    this.creating = true;
    const request: TdRequest = { '@type': 'createNewBasicGroupChat' };
    request['user_ids'] = selectedSnapshot;
    request['title'] = groupTitle;
    request['message_auto_delete_time'] = 0;
    getTdClient().send(request, 20000).then((result: TdObject): void => {
      if (!this.active || sequence !== this.creationSequence) { return; }
      this.creating = false;
      const parsed: NewBasicGroupResult = parseNewBasicGroupResult(result);
      if (parsed.chatId <= 0) {
        // A malformed success must never turn the Create button back into a
        // second create request; the first group may already exist remotely.
        this.creationOutcomeUnknown = true;
        this.createError = str('ng_result_unknown');
        return;
      }
      this.createdChatId = parsed.chatId;
      if (parsed.failedUserIds.length > 0) {
        const names = parsed.failedUserIds.slice(0, 2).map(
          (userId: number): string => this.contactFor(userId).name
        ).join('、');
        const suffix = parsed.failedUserIds.length > 2
          ? str('ng_and_others', names, parsed.failedUserIds.length) : names;
        promptAction.showToast({
          message: str('ng_created_partial', suffix), duration: 2600
        });
      }
      this.openCreatedGroup();
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.creationSequence) { return; }
      this.creating = false;
      if (newGroupCreationOutcomeUncertain(error.message)) {
        this.creationOutcomeUnknown = true;
        this.createError = str('ng_timeout');
      } else {
        this.createError = newGroupCreationErrorText(error.message);
      }
      logE(`NewGroupPage.createNewBasicGroupChat failed: ${error.message}`);
    });
  }

  // 频道：createNewSupergroupChat(is_channel) → 可选 addChatMembers。
  private createChannel(): void {
    const channelTitle = this.title.trim();
    const selectedSnapshot = this.selectedIds.slice();
    const sequence = ++this.creationSequence;
    this.titleError = '';
    this.createError = '';
    this.creating = true;
    const request: TdRequest = { '@type': 'createNewSupergroupChat' };
    request['title'] = channelTitle;
    request['is_channel'] = true;
    request['is_forum'] = false;
    request['description'] = this.channelDescription.trim();
    getTdClient().send(request, 20000).then((result: TdObject): void => {
      if (!this.active || sequence !== this.creationSequence) { return; }
      this.creating = false;
      const chatId: number = (result['id'] as number | undefined) ?? 0;
      if (chatId <= 0) {
        this.creationOutcomeUnknown = true;
        this.createError = str('ng_result_unknown');
        return;
      }
      this.createdChatId = chatId;
      if (selectedSnapshot.length > 0) {
        const invite: TdRequest = { '@type': 'addChatMembers' };
        invite['chat_id'] = chatId;
        invite['user_ids'] = selectedSnapshot;
        getTdClient().send(invite).catch((error: TdError): void => {
          logE(`NewGroupPage.addChatMembers failed: ${error.message}`);
          promptAction.showToast({
            message: $r('app.string.ng_channel_created_partial'), duration: 2600
          });
        });
      }
      this.openCreatedGroup();
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.creationSequence) { return; }
      this.creating = false;
      if (newGroupCreationOutcomeUncertain(error.message)) {
        this.creationOutcomeUnknown = true;
        this.createError = str('ng_timeout');
      } else {
        this.createError = newGroupCreationErrorText(error.message);
      }
      logE(`NewGroupPage.createNewSupergroupChat failed: ${error.message}`);
    });
  }

  private openCreatedGroup(): void {
    const chatId = this.createdChatId;
    if (chatId <= 0 || this.openingCreatedChat) { return; }
    this.openingCreatedChat = true;
    this.createError = '';
    const params: Record<string, Object> = { 'chatId': chatId };
    // 曾经是 router.replaceUrl('pages/chat/ChatPage')——ChatPage 迁成
    // HdsNavDestination 后已从 main_pages.json 摘掉，直连 router 会跳不动。
    // replaceUrl 的语义（用会话页顶掉本页）拆成两步：漏斗把会话推进聊天栈
    // 并把聊天页签选中，成功之后再把本页弹掉，露出下面的会话。
    //
    // 两步必须串起来而不是并排写：router.back() 是同步 void，正常失败不抛，
    // 把它包进 try/catch 只会让下面这段错误处理永远不可达（spinner 一直转）。
    // 真正会失败的是 navigateToChat，所以错误处理挂在它的 Promise 上。
    navigateToChat(params).then((): void => {
      router.back();
    }).catch((e: Error): void => {
      if (!this.active) { return; }
      this.openingCreatedChat = false;
      this.createError = str('ng_created_cannot_open');
      logE(`NewGroupPage.openCreatedGroup failed: ${e.message}`);
    });
  }

  private back(): void {
    if (this.creating || this.openingCreatedChat) { return; }
    if (this.naming) {
      animateTo({ duration: this.animationDuration(210), curve: Curve.EaseOut }, (): void => {
        this.naming = false;
        this.titleError = '';
        this.createError = '';
      });
      return;
    }
    router.back();
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .enabled(!this.creating && !this.openingCreatedChat)
      .opacity(this.creating || this.openingCreatedChat ? 0.42 : 1)
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .accessibilityText(this.naming ? $r('app.string.ng_back_to_members') : $r('app.string.back'))
      .onClick((): void => this.back());

      Column({ space: 1 }) {
        Text(this.naming ? $r('app.string.ct_new_group') : $r('app.string.ng_add_members'))
          .fontSize(21).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.naming ? plural('ng_member_count', this.selectedIds.length, this.selectedIds.length) :
          (this.selectedIds.length > 0
            ? str('ng_selected_of', this.selectedIds.length, this.maxSelectableMembers)
            : $r('app.string.ng_pick_members')))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);

      Row({ space: 5 }) {
        if (this.creating || this.openingCreatedChat) {
          LoadingProgress().width(16).height(16).color(COLOR_PRIMARY);
        }
        Text(this.headerActionText())
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.createActionEnabled() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      }
      .height(44).padding({ left: 10, right: 8 }).borderRadius(22)
      .enabled(this.createActionEnabled())
      .opacity(this.createActionEnabled() || this.creating || this.openingCreatedChat ? 1 : 0.48)
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .accessibilityText(this.headerActionText())
      .onClick((): void => {
        if (this.naming) { this.createGroup(); } else { this.goNext(); }
      });
    }
    .width('100%').height(58).padding({ left: 6, right: 8 })
    .alignItems(VerticalAlign.Center).backgroundColor(PAGE_BG);
  }

  // 选人那一屏的卡片（搜索框 / 联系人列表 / 空态）宽度上限。
  // 这几张卡片本来就是 width('calc(100% - 24vp)') + margin 左右各 12 —— 那个
  // 写法是对的，宽度里先把两侧 margin 扣掉了，不是 width('100%') 加 margin 的
  // 溢出写法。限宽因此只能顺着它做：上限同样要扣掉那 24，不然卡片宽度加上
  // margin 会超出限宽后的内容列。
  // 手机上 readableContentWidth 原样返回窗口宽，上限正好等于 calc 算出来的值，
  // 约束不生效，逐像素等于改动前。
  private pickerCardMaxWidth(): number {
    return readableContentWidth(this.screenW) - CARD_SIDE_MARGIN * 2;
  }

  @Builder
  searchBox() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18).fontColor([this.searchFocused ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
        .animation({ duration: this.animationDuration(150), curve: Curve.EaseOut });
      TextInput({ text: this.query, placeholder: $r('app.string.ct_search_hint') })
        .layoutWeight(1).height(38).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY).caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .onFocus((): void => { this.searchFocused = true; })
        .onBlur((): void => { this.searchFocused = false; })
        .onSubmit((): void => this.retryRemoteSearch())
        .onChange((value: string): void => this.onQueryChanged(value));
      if (this.remoteState === 'loading') {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY)
          .transition(TransitionEffect.OPACITY.combine(
            TransitionEffect.scale({ x: 0.75, y: 0.75 })
          ).animation({ duration: this.animationDuration(150), curve: Curve.EaseOut }));
      } else if (this.query !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle')).fontSize(19).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(32).height(32).borderRadius(16).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
        .accessibilityText($r('app.string.clear_search')).onClick((): void => this.clearSearch());
      }
    }
    .width('calc(100% - 24vp)').constraintSize({ maxWidth: this.pickerCardMaxWidth() })
    .height(46).padding({ left: 13, right: 9 })
    .margin({ left: 12, right: 12, top: 4, bottom: 8 })
    .backgroundColor(CARD_BG).borderRadius(23)
    .border({ width: 1, color: this.searchFocused ? COLOR_PRIMARY : Color.Transparent })
    .animation({ duration: this.animationDuration(150), curve: Curve.EaseOut });
  }

  @Builder
  selectedChip(contact: ContactItem) {
    Column({ space: 3 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        AvatarView({
          avatarPath: contact.avatarPath, initials: contact.initials,
          colorSeed: contact.id, avatarSize: 46
        });
        Row() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(10).fontColor([Color.White]);
        }
        .width(18).height(18).borderRadius(9).backgroundColor('#8E8E93')
        .justifyContent(FlexAlign.Center).offset({ x: 4, y: -4 });
      }
      Text(contact.name).fontSize(11).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
        .width(62).textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .padding({ top: 2, bottom: 2 }).borderRadius(12)
    .stateStyles({ normal: this.primaryActionNormalStyle, pressed: this.primaryActionPressedStyle })
    .accessibilityText(str('ng_remove_member', contact.name))
    .onClick((): void => this.toggle(contact.id))
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.scale({ x: 0.78, y: 0.78 })
    ).animation({ duration: this.animationDuration(180), curve: Curve.EaseOut }));
  }

  @Builder
  selectedSummary() {
    if (this.selectedIds.length > 0) {
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.selectedIds, (userId: number) => {
            this.selectedChip(this.contactFor(userId));
          }, (userId: number): string => `${userId}`);
        }
        // 横滑条本身保持满宽（留白里照样能横滑），只把里面的头像行推到内容列
        // 边缘上，免得平板上一排头像贴着屏幕左沿、跟下面的卡片对不齐。
        // 手机上 contentSideGutter 恒为 0，逐像素等于改动前的 16。
        .padding({
          left: 16 + contentSideGutter(this.screenW),
          right: 16 + contentSideGutter(this.screenW),
          top: 5, bottom: 9
        });
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      .transition(TransitionEffect.OPACITY.combine(
        TransitionEffect.translate({ y: -8 })
      ).animation({ duration: this.animationDuration(190), curve: Curve.EaseOut }));
    }
  }

  @Builder
  contactRow(contact: ContactItem) {
    Row({ space: 13 }) {
      AvatarView({
        avatarPath: contact.avatarPath, initials: contact.initials,
        colorSeed: contact.id, avatarSize: 48
      });
      Column({ space: 2 }) {
        Text(contact.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(contact.statusText).fontSize(13)
          .fontColor(contact.online ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row() {
        if (this.selected(contact.id)) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(15).fontColor([Color.White])
            .transition(TransitionEffect.OPACITY.combine(
              TransitionEffect.scale({ x: 0.55, y: 0.55 })
            ).animation({ duration: this.animationDuration(150), curve: Curve.EaseOut }));
        }
      }
      .width(24).height(24).borderRadius(12)
      .border({ width: this.selected(contact.id) ? 0 : 1.5, color: '#C7C7CC' })
      .backgroundColor(this.selected(contact.id) ? COLOR_PRIMARY : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .animation({ duration: this.animationDuration(150), curve: Curve.EaseOut });
    }
    .width('100%').padding({ left: 12, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .accessibilityText(str('a11y_labeled_state', contact.name, this.selected(contact.id) ? str('ng_selected') : str('ng_not_selected')))
    .onClick((): void => this.toggle(contact.id));
  }

  @Builder
  skeletonRow(index: number) {
    Row({ space: 13 }) {
      Circle({ width: 48, height: 48 }).fill($r('app.color.surface_alt'));
      Column({ space: 7 }) {
        Row().width(index % 2 === 0 ? '48%' : '58%').height(13)
          .borderRadius(7).backgroundColor($r('app.color.surface_alt'));
        Row().width(index % 2 === 0 ? '68%' : '43%').height(10)
          .borderRadius(5).backgroundColor($r('app.color.surface_alt'));
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Circle({ width: 24, height: 24 }).fill($r('app.color.surface_alt'));
    }
    .width('100%').height(64).padding({ left: 12, right: 14 });
  }

  @Builder
  loadingState() {
    Column() {
      ForEach(SKELETON_ROWS, (index: number): void => this.skeletonRow(index),
        (index: number): string => `${index}`);
    }
    .width('calc(100% - 24vp)').constraintSize({ maxWidth: this.pickerCardMaxWidth() })
    .margin({ left: 12, right: 12, top: 4 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .opacity(this.skeletonBright ? 0.56 : 0.94)
    .animation({ duration: this.animationDuration(640), curve: Curve.EaseInOut })
    .transition(TransitionEffect.OPACITY.animation({
      duration: this.animationDuration(160), curve: Curve.EaseOut
    }));
  }

  @Builder
  centeredState(icon: Resource, title: ResourceStr, detail: ResourceStr, retryKind: string) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
        SymbolGlyph(icon).fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
      }
      Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(detail).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).constraintSize({ maxWidth: 280 });
      if (retryKind !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text($r('app.string.settings_reload')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .height(38).padding({ left: 15, right: 16 }).borderRadius(19)
        .backgroundColor(COLOR_PRIMARY)
        .stateStyles({ normal: this.primaryActionNormalStyle, pressed: this.primaryActionPressedStyle })
        .onClick((): void => {
          if (retryKind === 'contacts') { this.retryContacts(); } else { this.retryRemoteSearch(); }
        });
      }
    }
    .layoutWeight(1).width('calc(100% - 24vp)')
    .constraintSize({ maxWidth: this.pickerCardMaxWidth() })
    .margin({ left: 12, right: 12, top: 4, bottom: this.bottomSafe + 12 })
    .justifyContent(FlexAlign.Center).backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.scale({ x: 0.97, y: 0.97 })
    ).animation({ duration: this.animationDuration(180), curve: Curve.EaseOut }));
  }

  private shouldShowRemoteError(): boolean {
    return this.remoteState === 'error' || this.remoteState === 'timeout';
  }

  private isShortRemoteQuery(): boolean {
    return this.query.trim().replace(/^@/, '').length < 2;
  }

  @Builder
  searchStatusRow() {
    if (this.remoteState === 'loading') {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        Text($r('app.string.ct_searching_global')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%').height(50).justifyContent(FlexAlign.Center);
    } else if (this.shouldShowRemoteError()) {
      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(14).fontColor([COLOR_PRIMARY]);
        Text(this.remoteState === 'timeout' ? $r('app.string.search_timeout') : $r('app.string.ng_global_search_failed'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        Text($r('app.string.settings_retry')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
      }
      .width('100%').height(46).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
      .onClick((): void => this.retryRemoteSearch());
    }
  }

  @Builder
  contactList() {
    List() {
      ForEach(this.filteredContacts(), (contact: ContactItem) => {
        ListItem() {
          Column() {
            this.contactRow(contact);
            Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 73 });
          }
        }
        .transition(TransitionEffect.OPACITY.combine(
          TransitionEffect.translate({ x: 10 })
        ).animation({ duration: this.animationDuration(170), curve: Curve.EaseOut }));
      }, (contact: ContactItem): string =>
        `${contact.id}_${contact.avatarPath}_${this.selected(contact.id)}`
      );
      if (this.remoteState === 'loading' || this.shouldShowRemoteError()) {
        ListItem() { this.searchStatusRow(); }
      }
    }
    .layoutWeight(1).width('calc(100% - 24vp)')
    // 这张卡片本身就是滚动容器（List 既是卡片又是滚动体），限宽后两侧留白
    // 不在它的命中区里、滑不动列表——这一点跟改动前的 12vp 边距同性质，只是
    // 平板上更宽。要让留白也能滑，得把卡片背景从 List 挪到 ListItem 上，那是
    // 另一回事，不在限宽这一轮里做。
    .constraintSize({ maxWidth: this.pickerCardMaxWidth() })
    .margin({ left: 12, right: 12, top: 4 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(this.bottomSafe + 12);
  }

  @Builder
  memberContent() {
    if (this.loading && this.contacts.length === 0 && this.query.trim() === '') {
      this.loadingState();
    } else if (this.filteredContacts().length > 0) {
      this.contactList();
    } else if (this.query.trim() === '' && this.loadError !== '') {
      this.centeredState(
        $r('sys.symbol.exclamationmark_circle'), $r('app.string.contacts_load_failed'),
        $r('app.string.ng_contacts_unreadable'), 'contacts'
      );
    } else if (this.query.trim() === '') {
      this.centeredState(
        $r('sys.symbol.person_2'), $r('app.string.ct_empty'),
        $r('app.string.ng_search_by_username'), ''
      );
    } else if (this.remoteState === 'loading') {
      this.centeredState(
        $r('sys.symbol.magnifyingglass'), $r('app.string.ng_searching'),
        $r('app.string.ng_searching_sub'), ''
      );
    } else if (this.shouldShowRemoteError()) {
      this.centeredState(
        $r('sys.symbol.exclamationmark_circle'),
        this.remoteState === 'timeout' ? $r('app.string.search_timeout') : $r('app.string.search_failed'),
        $r('app.string.ng_search_failed_sub'), 'search'
      );
    } else {
      this.centeredState(
        $r('sys.symbol.person_2'), this.isShortRemoteQuery() ? $r('app.string.keep_typing') : $r('app.string.ng_no_users'),
        this.isShortRemoteQuery()
          ? $r('app.string.ng_min_chars') : $r('app.string.ct_no_results_sub'), ''
      );
    }
  }

  @Builder
  memberPicker() {
    Column() {
      this.searchBox();
      this.selectedSummary();
      this.memberContent();
    }
    .layoutWeight(1).width('100%')
    // 限了宽不居中就是把卡片全堆在屏幕左边，比不限还难看。手机上卡片宽度
    // 加左右 margin 正好铺满，居中与否没有区别。
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.translate({ x: -18 })
    ).animation({ duration: this.animationDuration(210), curve: Curve.EaseOut }));
  }

  @Builder
  namingMember(contact: ContactItem, index: number) {
    if (index > 0) {
      Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 68 });
    }
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: contact.avatarPath, initials: contact.initials,
        colorSeed: contact.id, avatarSize: 44
      });
      Text(contact.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([COLOR_PRIMARY]);
    }
    .width('100%').padding({ left: 12, right: 14, top: 8, bottom: 8 });
  }

  @Builder
  kindSegment() {
    Row() {
      ForEach(['group', 'channel'], (value: string) => {
        Text(value === 'group' ? $r('app.string.gn_group') : $r('app.string.gn_channel'))
          .fontSize(14)
          .fontWeight(this.kind === value ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.kind === value ? Color.White : COLOR_TEXT_PRIMARY)
          .padding({ left: 18, right: 18, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(this.kind === value ? COLOR_PRIMARY : Color.Transparent)
          .onClick((): void => {
            if (!this.creating && this.createdChatId === 0) {
              this.kind = value;
            }
          });
      }, (value: string): string => `kind_${value}`);
    }
    .borderRadius(18)
    .padding(2)
    .backgroundColor(CARD_BG);
  }

  @Builder
  namingPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.kindSegment();
        Row({ space: 14 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 70, height: 70 }).fill(COLOR_PRIMARY);
            SymbolGlyph($r(this.kind === 'channel'
              ? 'sys.symbol.speaker' : 'sys.symbol.person_3_fill'))
              .fontSize(32).fontColor([Color.White]);
          }
          Column({ space: 5 }) {
            TextInput({ text: this.title, placeholder: this.kind === 'channel' ? $r('app.string.ng_channel_name') : $r('app.string.ng_group_name') })
              .id('new_group_title').width('100%').height(42).fontSize(18)
              .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
              .placeholderColor(COLOR_TEXT_SECONDARY).caretColor(COLOR_PRIMARY)
              .maxLength(128).enterKeyType(EnterKeyType.Done)
              .enabled(!this.creating && !this.openingCreatedChat && this.createdChatId === 0)
              .onChange((value: string): void => {
                this.title = value;
                this.titleError = '';
                if (this.createdChatId === 0) { this.createError = ''; }
              })
              .onSubmit((): void => {
                if (this.createActionEnabled()) { this.createGroup(); }
              });
            Divider().strokeWidth(1)
              .color(this.titleError !== '' ? '#E64646' : COLOR_PRIMARY);
            Row() {
              Text(this.titleError).fontSize(11).fontColor('#E64646')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
              Text(`${this.title.length}/128`).fontSize(10).fontColor(COLOR_TEXT_SECONDARY);
            }.width('100%');
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start);
        }
        .width('100%').padding({ left: 14, right: 14, top: 16, bottom: 14 })
        .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

        if (this.kind === 'channel') {
          Column({ space: 4 }) {
            TextInput({ text: this.channelDescription, placeholder: $r('app.string.ng_channel_bio') })
              .width('100%').fontSize(14)
              .backgroundColor(Color.Transparent).padding({ top: 4, bottom: 4 })
              .maxLength(255)
              .enabled(!this.creating && !this.openingCreatedChat && this.createdChatId === 0)
              .onChange((value: string): void => {
                this.channelDescription = value;
              });
            Text($r('app.string.ng_channel_bio_sub'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
          }
          .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
        }

        if (this.createError !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(15).fontColor(['#E64646']);
            Text(this.createError).fontSize(12).fontColor('#E64646')
              .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .width('100%').padding({ left: 13, right: 13, top: 10, bottom: 10 })
          .backgroundColor('#14E64646').borderRadius(12)
          .transition(TransitionEffect.OPACITY.combine(
            TransitionEffect.translate({ y: -6 })
          ).animation({ duration: this.animationDuration(160), curve: Curve.EaseOut }));
        }

        Column() {
          Row() {
            Text($r('app.string.ng_members')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
            Blank();
            Text(plural('ng_people_count', this.selectedIds.length, this.selectedIds.length)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(42).padding({ left: 14, right: 14 });
          ForEach(this.selectedIds, (userId: number, index: number) => {
            this.namingMember(this.contactFor(userId), index);
          }, (userId: number): string => `selected_${userId}`);
        }
        .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
      }
      .width('100%')
      // 限宽做在内容列的内边距上而不是 Scroll 的宽度上：Scroll 仍铺满窗口，
      // 两侧让出来的留白因此还在它的命中区里，手指按在留白上照样能滚页面。
      // 手机上 contentSideGutter 恒为 0，两个值逐像素等于改动前的 12。
      .padding({
        left: 12 + contentSideGutter(this.screenW),
        right: 12 + contentSideGutter(this.screenW),
        top: 4, bottom: this.bottomSafe + 24
      });
    }
    .align(Alignment.Top)
    .layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.translate({ x: 18 })
    ).animation({ duration: this.animationDuration(210), curve: Curve.EaseOut }));
  }

  build() {
    Column() {
      this.header();
      if (this.naming) { this.namingPage(); } else { this.memberPicker(); }
    }
    .width('100%').height('100%').padding({ top: this.topSafe })
    .backgroundColor(PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
