import { getTdClient } from '../../tdkit/Globals';
import { ContactsStore, ContactItem } from '../../store/ContactsStore';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { TdRequest, TdObject, TdError } from '../../tdkit/TdTypes';
import { promptAction, router, SymbolGlyphModifier } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { searchPublicUsers } from '../../store/PublicUserSearch';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { navigateToChat } from '../../util/chatNav';
import { logE, logW } from '../../util/log';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const TOP_BAR_HEIGHT: number = 56;
const TOP_ACTION_SIZE: number = 44;
const SEARCH_BAR_HEIGHT: number = 46;
const SEARCH_DELAY_MS: number = 350;
const CONTACT_LONG_PRESS_MS: number = 500;
const SKELETON_ROWS: number[] = [0, 1, 2, 3, 4];

// The contacts tab: search box, recent-calls shortcut, and the contact
// list sorted by last-seen. Title shows 正在刷新... until getContacts resolves.
@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct ContactsPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  private contactsScroller: Scroller = new Scroller();
  // ⋮ 的菜单。HDS 标题栏的菜单项只给 action 回调、挂不了 bindMenu，所以由它
  // 翻这个开关，菜单本体绑在右上角一个零尺寸锚点上（见 build）。
  @State private topMenuShown: boolean = false;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State contacts: ContactItem[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State query: string = '';
  @State remoteUsers: ContactItem[] = [];
  @State remoteLoading: boolean = false;
  @State searchFocused: boolean = false;
  // Keyed by the icon name, not the label: a label is display text and
  // changes with the language, so it cannot serve as an identity.
  @State pressedAction: string = '';
  @State pressedContactId: number = 0;
  @State openingContactId: number = 0;
  @State deletingContactId: number = 0;
  @State contextMenuShown: boolean = false;
  @State menuContactId: number = 0;
  @State menuContactName: string = '';
  @State skeletonBright: boolean = false;
  @State fabPressed: boolean = false;
  @State addContactSheetOpen: boolean = false;
  @State addFirstName: string = '';
  @State addLastName: string = '';
  @State addPhone: string = '';
  @State addContactError: string = '';
  @State addContactSaving: boolean = false;
  private store: ContactsStore | null = null;
  private unsub: (() => void) | null = null;
  private searchTimer: number = -1;
  private searchSequence: number = 0;
  private actionUnlockTimer: number = -1;
  private actionNavigationLocked: boolean = false;
  private chatOpenSequence: number = 0;
  private deleteSequence: number = 0;
  private addContactSequence: number = 0;
  private skeletonTimer: number = -1;
  private contactPressActive: boolean = false;
  private contactPressId: number = 0;
  private contactPressIndex: number = -1;
  private contactPressVersion: string = '';
  private contactPressConsumedByMenu: boolean = false;
  private pendingContacts: ContactItem[] | null = null;
  private pendingLoading: boolean = false;
  private pendingLoadError: string = '';

  @Styles
  topActionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  retryNormalStyle() {
    .backgroundColor($r('app.color.selected_pill'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  retryPressedStyle() {
    .backgroundColor($r('app.color.selected_pill'))
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  aboutToAppear(): void {
    this.releaseActionLock();
    const store = new ContactsStore(getTdClient());
    this.store = store;
    this.unsub = store.subscribe(() => {
      this.applyContacts(store.contacts, store.loading, store.errorMessage);
    });
    store.open();
  }

  aboutToDisappear(): void {
    this.stopSkeletonPulse();
    this.releaseActionLock();
    this.pressedAction = '';
    this.pressedContactId = 0;
    this.openingContactId = 0;
    this.deletingContactId = 0;
    this.fabPressed = false;
    this.addContactSheetOpen = false;
    this.addContactSaving = false;
    this.contextMenuShown = false;
    this.menuContactId = 0;
    this.contactPressActive = false;
    this.pendingContacts = null;
    this.chatOpenSequence++;
    this.deleteSequence++;
    this.addContactSequence++;
    this.searchSequence++;
    this.remoteLoading = false;
    this.searchFocused = false;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
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
      this.remoteLoading = false;
      return;
    }
    this.remoteLoading = true;
    const run = (): void => {
      this.searchTimer = -1;
      searchPublicUsers(getTdClient(), value).then((users: ContactItem[]): void => {
        if (sequence !== this.searchSequence) {
          return;
        }
        this.remoteUsers = users;
        this.remoteLoading = false;
      }).catch((error: TdError): void => {
        if (sequence !== this.searchSequence) {
          return;
        }
        logW(`ContactsPage.searchPublicUsers failed: ${error.message}`);
        this.remoteUsers = [];
        this.remoteLoading = false;
      });
    };
    if (delayMs <= 0) {
      run();
    } else {
      this.searchTimer = setTimeout(run, delayMs);
    }
  }

  private submitSearch(): void {
    if (this.query.trim().replace(/^@/, '').length < 2) {
      return;
    }
    this.scheduleRemoteSearch(this.query, 0);
  }

  private clearSearch(): void {
    this.onQueryChanged('');
  }

  private startSkeletonPulse(): void {
    if (this.skeletonTimer !== -1 ||
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1) === 0) {
      return;
    }
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

  private applyContacts(next: ContactItem[], nextLoading: boolean, nextError: string): void {
    if (this.contextMenuShown) {
      this.pendingContacts = next;
      this.pendingLoading = nextLoading;
      this.pendingLoadError = nextError;
      return;
    }
    if (nextLoading && next.length === 0) {
      this.startSkeletonPulse();
    } else {
      this.stopSkeletonPulse();
    }
    const structureChanged = this.contacts.length !== next.length ||
      this.contacts.some((item: ContactItem, index: number): boolean => item.id !== next[index]?.id);
    if (structureChanged) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => {
        this.contacts = next;
        this.loading = nextLoading;
        this.loadError = nextError;
      });
      return;
    }
    this.contacts = next;
    this.loading = nextLoading;
    this.loadError = nextError;
  }

  private flushPendingContacts(): void {
    const pending = this.pendingContacts;
    if (pending === null) {
      return;
    }
    const loading = this.pendingLoading;
    const error = this.pendingLoadError;
    this.pendingContacts = null;
    this.applyContacts(pending, loading, error);
  }

  private retryContacts(): void {
    if (this.store !== null && !this.loading) {
      this.store.reload();
    }
  }

  private openAddContactSheet(): void {
    if (this.contextMenuShown || this.addContactSaving) {
      return;
    }
    this.fabPressed = false;
    this.addFirstName = '';
    this.addLastName = '';
    this.addPhone = '';
    this.addContactError = '';
    this.addContactSheetOpen = true;
  }

  private phoneDigits(value: string): string {
    let digits = '';
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code >= 48 && code <= 57) {
        digits += value.charAt(index);
      }
    }
    return digits;
  }

  private addContactFailureMessage(error: TdError): string {
    const message = error.message.toUpperCase();
    if (message.includes('PHONE_NUMBER_INVALID')) {
      return str('ct_bad_phone');
    }
    if (message.includes('USER_NOT_FOUND') || message.includes('PHONE_NUMBER_NOT_OCCUPIED')) {
      return str('ct_no_user');
    }
    if (message.includes('NETWORK') || message.includes('TIMEOUT')) {
      return str('network_failed_retry');
    }
    return str('ct_add_failed');
  }

  private submitNewContact(): void {
    if (this.addContactSaving) {
      return;
    }
    const firstName = this.addFirstName.trim();
    const lastName = this.addLastName.trim();
    const phone = this.phoneDigits(this.addPhone);
    if (firstName === '') {
      this.addContactError = str('ct_enter_first_name');
      return;
    }
    if (phone.length < 6 || phone.length > 15) {
      this.addContactError = str('ct_enter_phone');
      return;
    }
    this.addContactError = '';
    this.addContactSaving = true;
    const sequence = ++this.addContactSequence;
    const contact: TdObject = { '@type': 'contact' };
    contact['phone_number'] = phone;
    contact['first_name'] = firstName;
    contact['last_name'] = lastName;
    contact['vcard'] = '';
    contact['user_id'] = 0;
    const request: TdRequest = { '@type': 'addContact' };
    request['contact'] = contact;
    request['share_phone_number'] = false;
    getTdClient().send(request, 10000).then((): void => {
      if (sequence !== this.addContactSequence) {
        return;
      }
      this.addContactSaving = false;
      this.addContactSheetOpen = false;
      promptAction.showToast({ message: str('ct_added', firstName + (lastName !== '' ? ' ' + lastName : '')), duration: 1800 });
      if (this.store !== null) {
        this.store.reload();
      }
    }).catch((error: TdError): void => {
      if (sequence !== this.addContactSequence) {
        return;
      }
      this.addContactSaving = false;
      this.addContactError = this.addContactFailureMessage(error);
      logE(`ContactsPage.addContact failed: ${error.message}`);
    });
  }

  private releaseActionLock(): void {
    if (this.actionUnlockTimer !== -1) {
      clearTimeout(this.actionUnlockTimer);
      this.actionUnlockTimer = -1;
    }
    this.actionNavigationLocked = false;
  }

  private openRecentCalls(): void {
    if (this.actionNavigationLocked) {
      return;
    }
    this.actionNavigationLocked = true;
    // Guard the current page against a rapid double tap. The lock is also
    // released when this page disappears, so returning never leaves it stuck.
    this.actionUnlockTimer = setTimeout((): void => {
      this.actionUnlockTimer = -1;
      this.actionNavigationLocked = false;
    }, 500);
    router.pushUrl({ url: 'pages/main/CallsPage' }).catch((error: Error): void => {
      logE(`ContactsPage.openRecentCalls failed: ${error.message}`);
      this.releaseActionLock();
    });
  }

  // Ensure the private chat exists (TDLib may not have it loaded yet), then
  // navigate into it — same pattern as ProfilePage.sendMessage.
  private openChatWith(userId: number): void {
    if (this.openingContactId !== 0 || this.deletingContactId !== 0) {
      return;
    }
    const sequence = ++this.chatOpenSequence;
    this.openingContactId = userId;
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = userId;
    req['force'] = false;
    getTdClient().send(req, 8000).then((chat: TdObject): void => {
      if (sequence !== this.chatOpenSequence) {
        return;
      }
      this.openingContactId = 0;
      const id = chat['id'] as number | undefined;
      if (id !== undefined) {
        const params: Record<string, Object> = { 'chatId': id };
        navigateToChat(params);
      }
    }).catch((e: TdError): void => {
      if (sequence !== this.chatOpenSequence) {
        return;
      }
      this.openingContactId = 0;
      logE(`ContactsPage.createPrivateChat failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.open_chat_failed'), duration: 1800 });
    });
  }

  private contactVersion(contact: ContactItem): string {
    return `${contact.id}_${contact.avatarPath}_${contact.name}_${contact.statusText}_${contact.online ? 1 : 0}`;
  }

  private visibleContactIndex(userId: number): number {
    return this.filtered().findIndex((contact: ContactItem): boolean => contact.id === userId);
  }

  private beginContactPress(contact: ContactItem): void {
    const local = this.contacts.find((item: ContactItem): boolean => item.id === contact.id);
    this.contactPressConsumedByMenu = false;
    this.contactPressActive = local !== undefined && this.deletingContactId === 0;
    this.contactPressId = contact.id;
    this.contactPressIndex = this.visibleContactIndex(contact.id);
    this.contactPressVersion = local !== undefined ? this.contactVersion(local) : '';
  }

  private endContactPress(): void {
    this.contactPressActive = false;
  }

  private openContactMenuIfCurrent(contact: ContactItem): void {
    const current = this.contacts.find((item: ContactItem): boolean => item.id === contact.id);
    const unchanged = this.contactPressActive
      && this.contactPressId === contact.id
      && current !== undefined
      && this.contactVersion(current) === this.contactPressVersion
      && this.visibleContactIndex(contact.id) === this.contactPressIndex;
    this.contactPressActive = false;
    this.pressedContactId = 0;
    if (!unchanged) {
      // A status/avatar/search refresh moved or rebuilt the row while the
      // recognizer was waiting. Ignore this hold instead of lifting stale UI.
      return;
    }
    this.contactPressConsumedByMenu = true;
    this.menuContactId = contact.id;
    this.menuContactName = current !== undefined ? current.name : contact.name;
    this.contextMenuShown = true;
  }

  private onContactMenuDisappear(): void {
    this.contextMenuShown = false;
    this.menuContactId = 0;
    this.menuContactName = '';
    this.pressedContactId = 0;
    this.contactPressActive = false;
    this.flushPendingContacts();
  }

  private confirmDeleteContact(): void {
    const userId = this.menuContactId;
    const name = this.menuContactName;
    if (userId <= 0 || name === '') {
      return;
    }
    promptAction.showDialog({
      title: $r('app.string.ct_delete'),
      message: str('ct_delete_confirm', name),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.delete'), color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) {
        this.deleteContact(userId, name);
      }
    }).catch((): void => {});
  }

  private deleteContact(userId: number, name: string): void {
    if (this.store === null || this.deletingContactId !== 0) {
      return;
    }
    this.deletingContactId = userId;
    const sequence = ++this.deleteSequence;
    const store = this.store;
    store.removeContact(userId).then((): void => {
      if (sequence !== this.deleteSequence) {
        return;
      }
      this.deletingContactId = 0;
      promptAction.showToast({ message: str('ct_deleted', name), duration: 1600 });
    }).catch((error: TdError): void => {
      if (sequence !== this.deleteSequence) {
        return;
      }
      this.deletingContactId = 0;
      logE(`ContactsPage.removeContact failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.ct_delete_failed'), duration: 1800 });
    });
  }

  private filtered(): ContactItem[] {
    const q = this.query.trim().toLowerCase();
    if (q === '') {
      return this.contacts;
    }
    const localQuery = q.replace(/^@/, '');
    const result = this.contacts.filter((c: ContactItem): boolean =>
      c.name.toLowerCase().includes(localQuery) ||
        c.statusText.toLowerCase().includes(q)
    );
    for (const user of this.remoteUsers) {
      if (!result.some((item: ContactItem): boolean => item.id === user.id)) {
        result.push(user);
      }
    }
    return result;
  }

  @Builder
  topMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.ct_new_group') })
        .onClick((): void => {
          router.pushUrl({ url: 'pages/main/NewGroupPage' });
        });
      MenuItem({ content: $r('app.string.ct_recent_calls') })
        .onClick((): void => {
          router.pushUrl({ url: 'pages/main/CallsPage' });
        });
    }
  }

  @Builder
  topBar() {
    Row({ space: 4 }) {
      Column() {
        Text($r('app.string.tab_contacts'))
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .translate({ y: this.loading ? 0 : 7 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          });
        Text($r('app.string.refreshing'))
          .height(14).fontSize(11).lineHeight(14)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .opacity(this.loading ? 1 : 0)
          .translate({ y: this.loading ? 0 : -3 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          });
      }
      .height(TOP_BAR_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Row() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(23).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(TOP_ACTION_SIZE).height(TOP_ACTION_SIZE)
      .borderRadius(TOP_ACTION_SIZE / 2)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.topActionNormalStyle,
        pressed: this.topActionPressedStyle
      })
      .accessibilityText($r('app.string.ct_more_actions'))
      .bindMenu(this.topMenu(), { systemMaterial: overlayMaterial('menu') });
    }
    .width('100%').height(TOP_BAR_HEIGHT)
    .padding({ left: 16, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(PAGE_BG);
  }

  @Builder
  searchBox() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([this.searchFocused ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
          curve: Curve.EaseOut
        });
      TextInput({ text: this.query, placeholder: $r('app.string.ct_search_hint') })
        .layoutWeight(1).height(38).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .onFocus((): void => { this.searchFocused = true; })
        .onBlur((): void => { this.searchFocused = false; })
        .onSubmit((): void => { this.submitSearch(); })
        .onChange((v: string): void => { this.onQueryChanged(v); });
      if (this.remoteLoading) {
        LoadingProgress()
          .width(18).height(18)
          .color(COLOR_PRIMARY)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
              curve: Curve.EaseOut
            }));
      } else if (this.query !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(19).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(32).height(32)
        .borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.topActionNormalStyle,
          pressed: this.topActionPressedStyle
        })
        .accessibilityText($r('app.string.clear_search'))
        .onClick((): void => { this.clearSearch(); })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
            curve: Curve.EaseOut
          }));
      }
    }
    .width('calc(100% - 24vp)')
    .height(SEARCH_BAR_HEIGHT)
    .padding({ left: 13, right: 9 })
    .backgroundColor(CARD_BG)
    .borderRadius(SEARCH_BAR_HEIGHT / 2)
    .border({
      width: this.searchFocused ? 1.5 : 0.5,
      color: this.searchFocused ? COLOR_PRIMARY : COLOR_DIVIDER
    })
    .alignItems(VerticalAlign.Center)
    .margin({ left: 12, right: 12, top: 4 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    });
  }

  @Builder
  actionRow(icon: string, bg: string, label: ResourceStr, detail: ResourceStr, onTap: () => void) {
    Row({ space: 14 }) {
      Row() {
        SymbolGlyph($r(icon))
          .fontSize(20)
          .fontColor([Color.White])
          .scale({
            x: this.pressedAction === icon ? 0.9 : 1,
            y: this.pressedAction === icon ? 0.9 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
            curve: Curve.EaseOut
          });
      }
      .width(40).height(40).borderRadius(20).backgroundColor(bg)
      .justifyContent(FlexAlign.Center);
      Column({ space: 2 }) {
        Text(label)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1);
        Text(detail)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([COLOR_TEXT_SECONDARY])
        .translate({ x: this.pressedAction === icon ? 2 : 0 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
          curve: Curve.EaseOut
        });
    }
    .width('100%')
    .height(62)
    .padding({ left: 12, right: 14 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(CARD_RADIUS - 4)
    .backgroundColor(this.pressedAction === icon ? $r('app.color.surface_alt') : Color.Transparent)
    .scale({
      x: this.pressedAction === icon ? 0.986 : 1,
      y: this.pressedAction === icon ? 0.97 : 1
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .accessibilityText(`${label}，${detail}`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedAction = icon;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedAction = '';
      }
    })
    .onClick((): void => {
      this.pressedAction = '';
      onTap();
    });
  }

  @Builder
  actionCard() {
    Column() {
      Column() {
        this.actionRow(
          'sys.symbol.phone_fill',
          '#34C759',
          $r('app.string.ct_recent_calls'),
          str('ct_recent_calls_sub'),
          (): void => { this.openRecentCalls(); }
        );
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .padding(4)
      .clip(true);
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  contactContextMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Color.Red]),
        content: $r('app.string.ct_delete')
      })
        .onClick((): void => { this.confirmDeleteContact(); });
    }
  }

  @Builder
  contactRow(c: ContactItem) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AvatarView({ avatarPath: c.avatarPath, initials: c.initials, colorSeed: c.id, avatarSize: 46 });
        if (c.online) {
          Circle({ width: 12, height: 12 })
            .fill('#34C759')
            .border({ width: 2, color: CARD_BG })
            .translate({ x: 1, y: 1 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.5, y: 0.5 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
                curve: Curve.EaseOut
              }));
        }
      }
      .width(46)
      .height(46);
      Column({ space: 3 }) {
        Text(c.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(c.statusText)
          .fontSize(13)
          .fontColor(c.online ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.openingContactId === c.id || this.deletingContactId === c.id) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(COLOR_PRIMARY)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.65, y: 0.65 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
              curve: Curve.EaseOut
            }));
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 60 })
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(CARD_RADIUS - 4)
    .backgroundColor(this.pressedContactId === c.id ? $r('app.color.surface_alt') : CARD_BG)
    .scale({
      x: this.pressedContactId === c.id ? 0.99 : 1,
      y: this.pressedContactId === c.id ? 0.985 : 1
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
      curve: Curve.EaseOut
    })
    .accessibilityText(`${c.name}，${c.statusText}`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedContactId = c.id;
        this.beginContactPress(c);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedContactId === c.id) {
          this.pressedContactId = 0;
        }
        this.endContactPress();
      }
    })
    .onClick((): void => {
      this.pressedContactId = 0;
      if (this.contactPressConsumedByMenu || this.contextMenuShown) {
        this.contactPressConsumedByMenu = false;
        return;
      }
      this.openChatWith(c.id);
    })
    .parallelGesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: CONTACT_LONG_PRESS_MS })
        .onAction((): void => { this.openContactMenuIfCurrent(c); })
        .onActionCancel((): void => { this.endContactPress(); })
    )
    .bindContextMenu(
      this.contextMenuShown && this.menuContactId === c.id,
      this.contactContextMenu,
      {
        preview: MenuPreviewMode.IMAGE,
        previewBorderRadius: CARD_RADIUS - 2,
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
        mask: {
          color: '#52000000',
          backgroundBlurStyle: BlurStyle.BACKGROUND_THIN
        },
        modalMode: ModalMode.TARGET_WINDOW,
        hapticFeedbackMode: HapticFeedbackMode.AUTO,
        onDisappear: (): void => { this.onContactMenuDisappear(); }
      }
    );
  }

  @Builder
  skeletonRow(index: number) {
    Row({ space: 12 }) {
      Circle({ width: 46, height: 46 })
        .fill($r('app.color.surface_alt'));
      Column({ space: 8 }) {
        Rect({ width: index % 2 === 0 ? 142 : 108, height: 12, radius: 6 })
          .fill($r('app.color.surface_alt'));
        Rect({ width: index % 3 === 0 ? 196 : 158, height: 9, radius: 4.5 })
          .fill($r('app.color.surface_alt'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .height(60)
    .padding({ left: 10, right: 10 });
  }

  @Builder
  loadingCard() {
    Column() {
      Row({ space: 6 }) {
        Circle({ width: 13, height: 13 }).fill($r('app.color.surface_alt'));
        Rect({ width: 118, height: 10, radius: 5 }).fill($r('app.color.surface_alt'));
      }
      .width('100%')
      .height(36)
      .padding({ left: 10, right: 10 });
      Divider().color(COLOR_DIVIDER).strokeWidth(0.7).margin({ left: 10, right: 10 });
      ForEach(SKELETON_ROWS, (index: number): void => {
        if (index > 0) {
          Divider().color(COLOR_DIVIDER).strokeWidth(0.7).margin({ left: 68, right: 10 });
        }
        this.skeletonRow(index);
      }, (index: number): string => `${index}`);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 12 })
    .padding({ left: 4, right: 4, bottom: 4 })
    .backgroundColor(CARD_BG)
    .borderRadius(CARD_RADIUS)
    .opacity(this.skeletonBright ? 0.56 : 0.92)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 640),
      curve: Curve.EaseInOut
    })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  emptyContactsCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
        SymbolGlyph($r('sys.symbol.person_2'))
          .fontSize(28)
          .fontColor([COLOR_TEXT_SECONDARY]);
      }
      Text($r('app.string.ct_empty'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_empty_sub'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center);
    }
    .width('calc(100% - 24vp)')
    .height(190)
    .margin({ left: 12, right: 12, top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG)
    .borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  errorContactsCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28)
          .fontColor(['#E64646']);
      }
      Text(this.loadError !== '' ? this.loadError : $r('app.string.contacts_load_failed'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_service_unavailable'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_reload'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(38)
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })
      .borderRadius(19)
      .stateStyles({
        normal: this.retryNormalStyle,
        pressed: this.retryPressedStyle
      })
      .accessibilityText($r('app.string.ct_reload_contacts'))
      .onClick((): void => { this.retryContacts(); });
    }
    .width('calc(100% - 24vp)')
    .height(220)
    .margin({ left: 12, right: 12, top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG)
    .borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  searchEmptyState() {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(26)
        .fontColor([COLOR_TEXT_SECONDARY]);
      Text($r('app.string.ct_no_results'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_no_results_sub'))
        .fontSize(12)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .height(116)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  listCard() {
    Column() {
      Column() {
        Row({ space: 6 }) {
          SymbolGlyph(this.query.trim() === ''
            ? $r('sys.symbol.clock')
            : $r('sys.symbol.magnifyingglass'))
            .fontSize(13)
            .fontColor([COLOR_PRIMARY]);
          Text(this.query.trim() === '' ? $r('app.string.ct_sort_by_last_seen') : $r('app.string.ct_contacts_and_global'))
            .fontSize(13)
            .fontColor(COLOR_PRIMARY)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1);
          Text(this.remoteLoading
            ? $r('app.string.searching')
            : plural('ct_result_count', this.filtered().length, this.filtered().length))
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%')
        .height(36)
        .padding({ left: 10, right: 10 })
        .alignItems(VerticalAlign.Center);
        Divider()
          .color(COLOR_DIVIDER)
          .strokeWidth(0.7)
          .margin({ left: 10, right: 10 });
        ForEach(this.filtered(), (c: ContactItem, index: number) => {
          if (index > 0) {
            Divider().color(COLOR_DIVIDER).strokeWidth(0.7).margin({ left: 68, right: 10 });
          }
          this.contactRow(c);
        // ArkUI reuses an unchanged ForEach key without rebuilding the row.
        // Include visible user data so an asynchronously downloaded avatar or
        // live status update reaches AvatarView/Text, while keeping geometry
        // stable to avoid a visible row insertion animation.
        }, (c: ContactItem) =>
          `${c.id}_${c.avatarPath}_${c.name}_${c.statusText}_${c.online ? 1 : 0}`);
        if (this.remoteLoading) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text($r('app.string.ct_searching_global')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center);
        } else if (this.query.trim() !== '' && this.filtered().length === 0) {
          this.searchEmptyState();
        }
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 4, right: 4, bottom: 4 })
      .clip(true);
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  addContactSheet() {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.ct_new_contact'))
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.ct_new_contact_sub'))
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.topActionNormalStyle,
          pressed: this.topActionPressedStyle
        })
        .enabled(!this.addContactSaving)
        .accessibilityText($r('app.string.ct_close_new_contact'))
        .onClick((): void => { this.addContactSheetOpen = false; });
      }
      .width('100%')
      .height(54)
      .alignItems(VerticalAlign.Center);

      Column({ space: 6 }) {
        Text($r('app.string.ct_name'))
          .width('100%')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 4 });
        TextInput({ text: this.addFirstName, placeholder: $r('app.string.ct_first_name') })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(COLOR_PRIMARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .maxLength(64)
          .enabled(!this.addContactSaving)
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string): void => {
            this.addFirstName = value;
            this.addContactError = '';
          });
        TextInput({ text: this.addLastName, placeholder: $r('app.string.ct_last_name') })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(COLOR_PRIMARY)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .maxLength(64)
          .enabled(!this.addContactSaving)
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string): void => {
            this.addLastName = value;
            this.addContactError = '';
          });
      }
      .width('100%')
      .margin({ top: 12 });

      Column({ space: 6 }) {
        Text($r('app.string.ct_phone'))
          .width('100%')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 4 });
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.phone_fill'))
            .fontSize(17)
            .fontColor([COLOR_PRIMARY]);
          TextInput({ text: this.addPhone, placeholder: '+86 138 0000 0000' })
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontColor(COLOR_TEXT_PRIMARY)
            .placeholderColor(COLOR_TEXT_SECONDARY)
            .caretColor(COLOR_PRIMARY)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .type(InputType.PhoneNumber)
            .maxLength(24)
            .enabled(!this.addContactSaving)
            .enterKeyType(EnterKeyType.Done)
            .onSubmit((): void => { this.submitNewContact(); })
            .onChange((value: string): void => {
              this.addPhone = value;
              this.addContactError = '';
            });
        }
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 12 })
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .border({
          width: this.addContactError !== '' ? 1 : 0,
          color: this.addContactError !== '' ? '#E64646' : Color.Transparent
        });
      }
      .width('100%')
      .margin({ top: 12 });

      if (this.addContactError !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(13)
            .fontColor(['#E64646']);
          Text(this.addContactError)
            .fontSize(12)
            .fontColor('#E64646')
            .layoutWeight(1);
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 8 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: -4 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
            curve: Curve.EaseOut
          }));
      }

      Button() {
        Row({ space: 8 }) {
          if (this.addContactSaving) {
            LoadingProgress().width(18).height(18).color(Color.White);
          } else {
            SymbolGlyph($r('sys.symbol.person_badge_plus'))
              .fontSize(18)
              .fontColor([Color.White]);
          }
          Text(this.addContactSaving ? $r('app.string.adding') : $r('app.string.ct_add_contact'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White);
        }
      }
      .width('100%')
      .height(50)
      .margin({ top: 18 })
      .backgroundColor(COLOR_PRIMARY)
      .borderRadius(14)
      .enabled(!this.addContactSaving)
      .onClick((): void => { this.submitNewContact(); });
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 6,
      bottom: Math.max(18, this.bottomSafe + 10)
    })
    .backgroundColor(CARD_BG);
  }

  @Builder
  fab() {
    Row() {
      SymbolGlyph($r('sys.symbol.person_badge_plus'))
        .fontSize(24)
        .fontColor([Color.White])
        .scale({
          x: this.fabPressed ? 0.88 : 1,
          y: this.fabPressed ? 0.88 : 1
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        });
    }
    .width(56).height(56).borderRadius(28)
    .backgroundColor(COLOR_PRIMARY)
    .justifyContent(FlexAlign.Center)
    .shadow({
      radius: this.fabPressed ? 4 : 10,
      color: this.fabPressed ? '#22000000' : '#33000000',
      offsetX: 0,
      offsetY: this.fabPressed ? 1 : 3
    })
    .scale({
      x: this.addContactSheetOpen ? 0.78 : (this.fabPressed ? 0.9 : 1),
      y: this.addContactSheetOpen ? 0.78 : (this.fabPressed ? 0.9 : 1)
    })
    .opacity(this.addContactSheetOpen ? 0 : 1)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
      curve: Curve.EaseOut
    })
    .enabled(!this.addContactSheetOpen && !this.contextMenuShown)
    .accessibilityText($r('app.string.ct_new_contact'))
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.fabPressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.fabPressed = false;
      }
    })
    .onClick((): void => { this.openAddContactSheet(); })
    .margin({ right: 18, bottom: this.bottomSafe + 88 });
  }

  // 标题栏内容：大标题 +「刷新中」副标题 + 右上角 ⋮。
  private titleBarContent(): TitleBarContentOptions {
    const moreIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.more'),
      label: $r('app.string.ct_more_actions'),
      action: (): void => { this.topMenuShown = true; }
    };
    const moreItem: HdsNavigationMenuItemOptions = { content: moreIcon };
    return {
      title: {
        mainTitle: $r('app.string.tab_contacts'),
        // 加载中才有副标题。原来那一版是两行文字各自做位移动画来"挤"出副标题，
        // HDS 的标题栏自己管这个位置，交给它即可。
        subTitle: this.loading ? $r('app.string.refreshing') : ''
      },
      menu: { value: [moreItem] }
    };
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      HdsNavigation() {
        Scroll(this.contactsScroller) {
          Column() {
            this.searchBox();
            this.actionCard();
            if (this.query.trim() === '' && this.loading && this.contacts.length === 0) {
              this.loadingCard();
            } else if (this.query.trim() === '' && this.loadError !== '' && this.contacts.length === 0) {
              this.errorContactsCard();
            } else if (this.query.trim() === '' && !this.loading && this.contacts.length === 0) {
              this.emptyContactsCard();
            } else {
              this.listCard();
            }
          }
          .width('100%')
          .padding({ bottom: this.bottomSafe + 88 });
        }
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
        .enableScrollInteraction(!this.contextMenuShown)
        // 不裁剪，内容才能穿透到标题栏下方——渐变模糊模糊的正是穿过去的这部分。
        .clip(false);
      }
      .titleBar({
        // 两个都要，各管一头：
        //
        //   avoidLayoutSafeArea     标题栏**自己**避让系统安全区
        //   enableComponentSafeArea 标题栏成为**内容区**的安全区，内容避让它
        //
        // 官方示例里只有后者，因为那是个普通非全屏窗口。**本应用整体是全屏沉浸
        // 布局**（EntryAbility 调了 setWindowLayoutFullScreen(true)），页面的布局区
        // 本来就覆盖状态栏——这也是全应用每个页面都要手动 padding(topSafe) 的原因。
        // 所以这里必须自己避让，少了它标题栏就顶进状态栏（真机两次实测）。
        //
        // 但**不要**再在 HdsNavigation 根上加 expandSafeArea：那会把标题栏往状态栏
        // 里推，和这一行正好对着干，两者抵消之后渐变模糊的合成也跟着废掉。状态栏
        // 那条的底色由 HdsNavigation 自己的 backgroundColor 铺——全屏布局下它本来
        // 就盖到那儿。
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        style: titleBarStyle(PAGE_BG),
        content: this.titleBarContent()
      })
      .hideBackButton(true)
      // 强制单栏：HdsNavigation 在宽屏（平板/横屏）会自动进分栏模式，我们只拿
      // 它当标题栏容器、不用 NavDestination——分栏的结果是整页内容挤进左列、
      // 右边一片空白（平板用户报"没法用了"）。
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.FREE)
      .bindToScrollable([this.contactsScroller])
      .width('100%').height('100%');

      // ⋮ 菜单的锚点：零尺寸，只为让菜单弹在右上角。HDS 的菜单项给不了
      // bindMenu，只能这样把两者接起来。
      Row()
        .width(1).height(1)
        .position({ x: '100%', y: this.topSafe + 44 })
        .bindMenu(this.topMenuShown, this.topMenu, {
          systemMaterial: overlayMaterial('menu'),
          onDisappear: (): void => { this.topMenuShown = false; }
        });

      this.fab();
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .bindSheet($$this.addContactSheetOpen, this.addContactSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: CARD_BG,
      dragBar: true,
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
  }
}
