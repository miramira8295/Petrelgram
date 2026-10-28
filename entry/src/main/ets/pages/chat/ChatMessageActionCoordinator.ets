import { common } from '@kit.AbilityKit';
import { LINK_COMMAND, LINK_COPY, LINK_HASHTAG, LINK_NONE, LINK_USER, LinkAction, linkActionOf } from '../../util/messageLinkAction';
import { KEY_EXTERNAL_LINK_ACTION } from '../../store/AppSettings';
import {
  normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf,
  chatFolderInviteLinkOf, isTelegramInternalUrl, stickerSetLinkOf
} from '../../util/linkNav';
import {
  openTelegramLink, openInviteLink, openChatLinkAction, openChatFolderInviteLink, openStickerSetLink
} from '../../util/openTelegramLink';
import { beginLinkNav, endLinkNavIf } from '../../util/linkTapGuard';
import { EXT_LINK_DEFAULT, EXT_LINK_OPEN, normalizeExternalLinkPolicy } from '../../util/externalLinkPolicy';
import { copyPlainText } from '../../util/clipboard';
import { navigateToProfile } from '../../util/profileNav';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import { TdClient } from '../../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { promptAction } from '@kit.ArkUI';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { forwardDirect } from '../../store/ForwardDirect';
import { requestOutcomeUncertain } from '../../util/tdRequestTimeout';
import { str } from '../../util/strings';

export interface ChatMessageActionHost {
  client: () => TdClient;
  chatId: () => number;
  store: () => MessageStore | null;
  entryById: (messageId: number) => MessageEntry | null;
  pollVotersEntry: (messageId: number) => MessageEntry | null;
  displayUserName: (userId: number) => string;
  ensureUser: (userId: number) => void;
  currentUserId: () => number;
  threadRootId: () => number;
  forwardIds: (ids: number[]) => number[];
  openForwardPicker: (messageIds: number[]) => void;
  closeContextMenu: () => void;
  translateInline: (messageId: number) => void;
  context: () => common.UIAbilityContext;
  sendBotCommand: (command: string) => void;
  searchForQuery: (query: string) => void;
  jumpToLinkedMessage: (messageId: number) => void;
  actionMenu: (options: promptAction.ActionMenuOptions) => Promise<promptAction.ActionMenuSuccessResponse>;
  toast: (options: promptAction.ShowToastOptions) => void;
  dialog: (options: promptAction.ShowDialogOptions) => Promise<promptAction.ShowDialogSuccessResponse>;
  confirmMenu: (options: promptAction.ShowDialogOptions, what: string) => Promise<promptAction.ShowDialogSuccessResponse>;
  openPaymentUrl: (url: string) => void;
  logError: (message: string) => void;
}

/** Coordinates message operations; rendering and existing session implementations stay with their owners. */
@ObservedV2
export class ChatMessageActionCoordinator {
  private botCallbackPending: Set<string> = new Set<string>();
  @Trace paidMediaPendingIds: number[] = [];
  private sessionEpoch: number = 0;
  private host: ChatMessageActionHost | null = null;

  bind(host: ChatMessageActionHost): void { this.host = host; }

  private get actions(): ChatMessageActionHost {
    if (this.host === null) { throw new Error('ChatMessageActionCoordinator is not bound'); }
    return this.host;
  }

  reset(): void {
    this.sessionEpoch++;
    this.botCallbackPending.clear();
    this.paidMediaPendingIds = [];
  }

  beginBotCallback(key: string): boolean {
    if (this.botCallbackPending.has(key)) { return false; }
    this.botCallbackPending.add(key);
    return true;
  }

  finishBotCallback(key: string): void {
    this.botCallbackPending.delete(key);
  }

  paidMediaPending(messageId: number): boolean {
    return this.paidMediaPendingIds.indexOf(messageId) >= 0;
  }

  beginPaidMedia(messageId: number): boolean {
    if (this.paidMediaPending(messageId)) { return false; }
    this.paidMediaPendingIds = [...this.paidMediaPendingIds, messageId];
    return true;
  }

  finishPaidMedia(messageId: number): void {
    this.paidMediaPendingIds = this.paidMediaPendingIds.filter(
      (id: number): boolean => id !== messageId);
  }

  private isCurrent(epoch: number, chatId: number, client: TdClient): boolean {
    return epoch === this.sessionEpoch && chatId === this.actions.chatId() && client === this.actions.client();
  }

  onBotCallback(messageId: number, data: string): void {
    const payload: TdObject = { '@type': 'callbackQueryPayloadData' };
    payload['data'] = data;
    this.requestBotCallback(messageId, payload, `data_${data}`);
  }

  onGameOpen(messageId: number): void {
    this.requestBotCallback(messageId, { '@type': 'callbackQueryPayloadGame' }, 'game');
  }

  onPollVote(messageId: number, optionIds: number[]): void {
    const store: MessageStore | null = this.actions.store();
    if (store === null) {
      this.actions.toast({ message: $r('app.string.cp_poll_unavailable'), duration: 1500 });
      return;
    }
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    // MessageStore owns vote validation, deduplication, optimistic updates and rollback.
    store.votePoll(messageId, optionIds, (ok: boolean, error: string): void => {
      if (this.isCurrent(epoch, chatId, client) && !ok && error.trim() !== '') {
        this.actions.toast({ message: error, duration: 1800 });
      }
    });
  }

  togglePinMessage(messageId: number, unpin: boolean): void {
    const store: MessageStore | null = this.actions.store();
    if (store === null) { return; }
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    const task: Promise<void> = unpin ? store.unpinAsync(messageId) : store.pinAsync(messageId);
    task.then((): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.actions.toast({
        message: unpin ? $r('app.string.cp_unpinned') : $r('app.string.cp_pinned'), duration: 1400
      });
    }).catch((e: TdError): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.actions.logError(`ChatPage.togglePin failed: ${e.message}`);
      this.actions.toast({
        message: e.message.indexOf('not enough rights') >= 0 || e.message.indexOf('ADMIN') >= 0
          ? $r('app.string.cp_no_pin_permission') : (unpin ? $r('app.string.cp_unpin_failed') : $r('app.string.cp_pin_failed')),
        duration: 1700
      });
    });
  }

  translateMessage(messageId: number): void {
    const entry: MessageEntry | null = this.actions.entryById(messageId);
    if (entry === null || entry.text.trim() === '') {
      this.actions.toast({ message: $r('app.string.cp_nothing_to_translate'), duration: 1600 });
      return;
    }
    // TranslationDriver owns inline progress, failures and the shared translation cache.
    this.actions.translateInline(messageId);
  }

  stopPoll(messageId: number): void {
    const options: promptAction.ShowDialogOptions = {
      title: $r('app.string.mb_stop_poll'), message: $r('app.string.cp_stop_poll_body'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_stop'), color: '#E5484D' }
      ]
    };
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    this.actions.confirmMenu(options, 'stopPoll').then((result): void => {
      if (!this.isCurrent(epoch, chatId, client) || result.index !== 1) { return; }
      const store: MessageStore | null = this.actions.store();
      if (store === null) { return; }
      store.stopPollAsync(messageId).then((): void => {
        if (this.isCurrent(epoch, chatId, client)) {
          this.actions.toast({ message: $r('app.string.cp_poll_stopped'), duration: 1500 });
        }
      }).catch((e: TdError): void => {
        if (!this.isCurrent(epoch, chatId, client)) { return; }
        this.actions.logError(`ChatPage.stopPoll failed: ${e.message}`);
        this.actions.toast({ message: $r('app.string.cp_stop_poll_failed'), duration: 1600 });
      });
    }).catch((): void => {});
  }

  showPollVoters(messageId: number): void {
    const entry: MessageEntry | null = this.actions.pollVotersEntry(messageId);
    const store: MessageStore | null = this.actions.store();
    if (entry === null || store === null) { return; }
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    const lines: string[] = [];
    const tasks: Promise<void>[] = [];
    entry.pollOptions.forEach((option: PollOptionInfo, index: number): void => {
      tasks.push(store.pollVotersAsync(messageId, index).then((result: TdObject): void => {
        const senders: TdObject[] = (result['senders'] as TdObject[] | undefined) ?? [];
        const names: string[] = [];
        for (const sender of senders) {
          if (sender['@type'] === 'messageSenderUser') {
            const uid: number = (sender['user_id'] as number | undefined) ?? 0;
            const name: string = this.actions.displayUserName(uid);
            if (name === '') { this.actions.ensureUser(uid); }
            names.push(name !== '' ? name : str('cp_user_id', uid));
          }
        }
        if (names.length > 0) { lines.push(`${option.text}：${names.join('、')}`); }
      }).catch((): void => {}));
    });
    Promise.all(tasks).then((): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.actions.dialog({
        title: $r('app.string.cp_voters'),
        message: lines.length > 0 ? lines.join('\n\n') : $r('app.string.cp_no_public_votes'),
        buttons: [{ text: $r('app.string.close'), color: '#3390EC' }]
      }).catch((): void => {});
    }).catch((): void => {});
  }

  // SelectionSession owns retained selection entries; ForwardSheet owns target picking and sending.
  openForwardPicker(ids: number[]): void {
    const validIds: number[] = this.actions.forwardIds(ids);
    this.actions.closeContextMenu();
    if (validIds.length === 0) {
      this.actions.toast({ message: $r('app.string.cp_cannot_forward'), duration: 1500 });
      return;
    }
    this.actions.openForwardPicker(validIds);
  }

  // Saved Messages keeps the source header. forwardDirect owns sorting, deduplication and topic scope.
  saveToSavedMessages(messageIds: number[]): void {
    const me: number = this.actions.currentUserId();
    if (me === 0) {
      this.actions.toast({ message: $r('app.string.mb_forward_failed'), duration: 1800 });
      return;
    }
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    forwardDirect(client, chatId, me, messageIds, this.actions.threadRootId(), false).then((sent: number): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.actions.toast({
        message: sent > 0 ? $r('app.string.mb_saved_done') : $r('app.string.mb_forward_failed'), duration: 1600
      });
    });
  }

  // Repeat sends a copy back to the current chat, retaining its current topic.
  repeatMessages(messageIds: number[]): void {
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    forwardDirect(client, chatId, chatId, messageIds, this.actions.threadRootId(), true).then((sent: number): void => {
      if (sent === 0 && this.isCurrent(epoch, chatId, client)) {
        this.actions.toast({ message: $r('app.string.mb_forward_failed'), duration: 1800 });
      }
    });
  }

  // 点了消息里的链接。分派本身（走哪一路、载荷是什么）在
  // util/messageLinkAction，有单测；这里只负责执行。
  // 「打开 / 复制」这一层只给 askFirst 的链接（2026-09-17，issue #169 第 6 条）：
  // 显示文字藏着另一个网址的文字链接、Bot 的网址按钮。普通链接点了直接开，复制与
  // 外部打开在内置浏览器的「⋯」里。机器人命令、话题标签、号码等本地伪链接在
  // onLinkTap 的前几条分支直接处理，不会走到这里。
  private offerLinkAction(url: string): void {
    this.actions.actionMenu({
      title: url.length > 60 ? url.substring(0, 57) + '…' : url,
      buttons: [
        { text: $r('app.string.lk_open'), color: '#3390EC' },
        { text: $r('app.string.mb_copy_url'), color: '#3390EC' }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse): void => {
      if (result.index === 0) {
        this.onLinkTap(url);
        return;
      }
      copyPlainText(url, str('link_copied'));
    }).catch((): void => {});
  }

  onLinkTap(url: string, askFirst: boolean = false): void {
    const action: LinkAction = linkActionOf(url);
    if (this.handleLocalLinkAction(action)) {
      return;
    }
    // Telegram 内链（t.me/@名/tg://）应用内直接解析，不弹「打开/复制」层
    // ——那层是给外部网页链接的（用户反馈 t.me 被当浏览器链接多问了一道）。
    //
    // 只在「直接打开」档才由本页弹：另外两档（复制 / 弹窗选择）已经由
    // util/webBrowserNav 那个唯一分叉点接管，本页再弹一次就是两层窗
    // （2026-09-18 新增的外部链接三档，判据见 util/externalLinkPolicy）。
    const linkPolicy: string =
      AppStorage.get<string>(KEY_EXTERNAL_LINK_ACTION) ?? EXT_LINK_DEFAULT;
    if (askFirst && !isTelegramInternalUrl(url)
      && normalizeExternalLinkPolicy(linkPolicy) === EXT_LINK_OPEN) {
      this.offerLinkAction(url);
      return;
    }
    // 从这里往下每一条分支都要往返一次服务器才知道该开哪一页。网络一慢，
    // 用户看不到反馈就会再点，同一个群于是被开出好几层。闸门放行一次、
    // 挡住其余，并把这个 url 广播出去让那段文字自己表现成加载中。
    if (!beginLinkNav(url)) {
      return;
    }
    if (this.openKnownTelegramLink(url)) {
      return;
    }
    this.resolveMessageLink(url);
  }

  private handleLocalLinkAction(action: LinkAction): boolean {
    if (action.kind === LINK_NONE) {
      return true;
    }
    if (action.kind === LINK_COMMAND) {
      this.actions.sendBotCommand(action.text);
      return true;
    }
    if (action.kind === LINK_COPY) {
      copyPlainText(action.text, str('cp_number_copied'));
      return true;
    }
    if (action.kind === LINK_HASHTAG) {
      // 先搜**本会话**，不再整页跳全局：用户点标签的意图基本是"这儿还有哪些
      // 这个标签的"，而跳走要付出丢失阅读位置的代价。全网那条从搜索底栏的
      // 「在公开帖子中搜索」进（见 ChatSearchBars.publicPostsRow）。
      // 逻辑在 SearchSession.enterForQuery，本页只接线。
      this.actions.searchForQuery(action.text);
      return true;
    }
    if (action.kind === LINK_USER) {
      const params: Record<string, Object> = { 'userId': action.userId };
      // 曾经是 router.pushUrl('pages/profile/ProfilePage')——ProfilePage 迁成
      // NavDestination 并从 main_pages.json 摘出后整页路由跳不动，走漏斗。
      navigateToProfile(params);
      return true;
    }
    return false;
  }

  private openKnownTelegramLink(url: string): boolean {
    const folderInvite = chatFolderInviteLinkOf(url);
    if (folderInvite !== '') {
      openChatFolderInviteLink(folderInvite);
      return true;
    }
    const stickerSet = stickerSetLinkOf(url);
    if (stickerSet !== null) {
      openStickerSetLink(stickerSet);
      return true;
    }
    // Private invite link: preview → confirm → join in-app.
    const invite = inviteLinkOf(url);
    if (invite !== '') {
      openInviteLink(this.actions.context(), invite, url);
      return true;
    }
    const linkAction = chatLinkActionOf(url);
    if (linkAction !== null) {
      openChatLinkAction(this.actions.context(), linkAction, url, true);
      return true;
    }
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      openTelegramLink(this.actions.context(), url, true);
      return true;
    }
    return false;
  }

  private resolveMessageLink(url: string): void {
    const tgUrl = normalizeTelegramLink(url);
    if (tgUrl === '') {
      openTelegramLink(this.actions.context(), url, true);
      return;
    }
    const req: TdRequest = { '@type': 'getMessageLinkInfo' };
    req['url'] = tgUrl;
    this.actions.client().send(req).then((info: TdObject) => {
      const chatId = info['chat_id'] as number | undefined;
      if (chatId === undefined || chatId === 0) {
        openTelegramLink(this.actions.context(), url, true);
        return;
      }
      const msg = info['message'] as TdObject | undefined;
      const msgId = msg !== undefined ? (msg['id'] as number | undefined) : undefined;
      // A link to a message already in this chat: scroll in place (same as the
      // pinned-message jump) instead of pushing a duplicate ChatPage instance —
      // that duplication was why repeat taps looked like they did nothing.
      if (chatId === this.actions.chatId()) {
        if (msgId !== undefined && msgId > 0) {
          this.actions.jumpToLinkedMessage(msgId);
        }
        endLinkNavIf(url);
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      if (msgId !== undefined && msgId > 0) {
        params['jumpTo'] = msgId;
      }
      navigateToChat(params, 'content').catch(logChatNavFailure);
      endLinkNavIf(url);
    }).catch((e: TdError) => {
      this.actions.logError(`ChatPage.getMessageLinkInfo failed: ${e.message}`);
      openTelegramLink(this.actions.context(), url, true);
    });
  }

  private requestBotCallback(messageId: number, payload: TdObject, suffix: string): void {
    const key: string = `${messageId}_${suffix}`;
    if (!this.beginBotCallback(key)) { return; }
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    const req: TdRequest = { '@type': 'getCallbackQueryAnswer' };
    req['chat_id'] = chatId;
    req['message_id'] = messageId;
    req['payload'] = payload;
    client.send(req).then((answer: TdObject): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.finishBotCallback(key);
      const answerUrl: string = ((answer['url'] as string | undefined) ?? '').trim();
      if (answerUrl !== '') { this.onLinkTap(answerUrl, true); }
      const text: string = (answer['text'] as string | undefined) ?? '';
      if (text.trim() === '') { return; }
      if ((answer['show_alert'] as boolean | undefined) ?? false) {
        this.actions.dialog({
          title: $r('app.string.cp_notice'), message: text,
          buttons: [{ text: $r('app.string.cp_got_it'), color: '#3390EC' }]
        });
      } else {
        this.actions.toast({ message: text, duration: 1800 });
      }
    }).catch((e: TdError): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.finishBotCallback(key);
      this.actions.logError(`ChatPage.getCallbackQueryAnswer failed: ${e.message}`);
      if (requestOutcomeUncertain(e.message)) { return; }
      this.actions.toast({
        message: suffix === 'game' ? $r('app.string.cp_game_cannot_open') : $r('app.string.action_failed_retry'),
        duration: 1800
      });
    });
  }

  onPaidMediaUnlock(messageId: number): void {
    const entry: MessageEntry | null = this.actions.entryById(messageId);
    if (entry === null || entry.contentType !== 'paidMedia' || !entry.paidMediaLocked ||
      entry.paidMediaStarCount <= 0 || !this.beginPaidMedia(messageId)) { return; }
    const epoch: number = this.sessionEpoch;
    const chatId: number = this.actions.chatId();
    const client: TdClient = this.actions.client();
    const propertiesReq: TdRequest = { '@type': 'getMessageProperties' };
    propertiesReq['chat_id'] = chatId;
    propertiesReq['message_id'] = messageId;
    client.send(propertiesReq).then((properties: TdObject): Promise<TdObject> => {
      if (!this.isCurrent(epoch, chatId, client)) { throw new Error('stale message action'); }
      if (!((properties['can_be_paid'] as boolean | undefined) ?? false)) {
        throw new TdError(400, str('cp_paid_cannot_buy'));
      }
      const formReq: TdRequest = { '@type': 'getPaymentForm' };
      formReq['input_invoice'] = this.paidMediaInvoice(chatId, messageId);
      return client.send(formReq);
    }).then((form: TdObject): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      const formTypeValue: Object | undefined = form['type'];
      const formType: TdObject | undefined = formTypeValue as TdObject | undefined;
      if (formType === undefined || (formType['@type'] as string | undefined) !== 'paymentFormTypeStars') {
        this.finishPaidMedia(messageId);
        this.actions.toast({ message: $r('app.string.cp_payment_unsupported'), duration: 1800 });
        return;
      }
      const formStars: number = Math.max(0,
        (formType['star_count'] as number | undefined) ?? entry.paidMediaStarCount);
      const formId: number = (form['id'] as number | undefined) ?? 0;
      if (formStars <= 0 || formId === 0) {
        this.finishPaidMedia(messageId);
        this.actions.toast({ message: $r('app.string.cp_payment_incomplete'), duration: 1800 });
        return;
      }
      this.actions.dialog({
        title: $r('app.string.cp_unlock_paid'), message: str('cp_pay_stars_body', formStars),
        buttons: [
          { text: $r('app.string.cancel'), color: '#8E8E93' },
          { text: str('cp_pay_stars_button', formStars), color: '#3390EC' }
        ]
      }).then((result): void => {
        if (!this.isCurrent(epoch, chatId, client)) { return; }
        if (result.index !== 1) { this.finishPaidMedia(messageId); return; }
        const paymentReq: TdRequest = { '@type': 'sendPaymentForm' };
        paymentReq['input_invoice'] = this.paidMediaInvoice(chatId, messageId);
        paymentReq['payment_form_id'] = formId;
        paymentReq['order_info_id'] = '';
        paymentReq['shipping_option_id'] = '';
        paymentReq['tip_amount'] = 0;
        client.send(paymentReq).then((paymentResult: TdObject): void => {
          if (!this.isCurrent(epoch, chatId, client)) { return; }
          this.finishPaidMedia(messageId);
          if ((paymentResult['success'] as boolean | undefined) ?? false) {
            this.actions.toast({ message: $r('app.string.cp_paid_unlocked'), duration: 1600 });
            return;
          }
          const verificationUrl: string = (paymentResult['verification_url'] as string | undefined) ?? '';
          if (verificationUrl !== '') {
            this.actions.openPaymentUrl(verificationUrl);
            return;
          }
          this.actions.toast({ message: $r('app.string.cp_payment_incomplete_short'), duration: 1600 });
        }).catch((e: TdError): void => {
          if (!this.isCurrent(epoch, chatId, client)) { return; }
          this.finishPaidMedia(messageId);
          this.actions.logError(`ChatPage.sendPaymentForm failed: ${e.message}`);
          this.actions.toast({ message: $r('app.string.cp_payment_failed'), duration: 1800 });
        });
      }).catch((): void => {
        if (this.isCurrent(epoch, chatId, client)) { this.finishPaidMedia(messageId); }
      });
    }).catch((e: TdError): void => {
      if (!this.isCurrent(epoch, chatId, client)) { return; }
      this.finishPaidMedia(messageId);
      this.actions.logError(`ChatPage.get paid media payment form failed: ${e.message}`);
      this.actions.toast({ message: e.message !== '' ? e.message : $r('app.string.cp_no_payment_info'), duration: 1800 });
    });
  }

  private paidMediaInvoice(chatId: number, messageId: number): TdObject {
    const invoice: TdObject = { '@type': 'inputInvoiceMessage' };
    invoice['chat_id'] = chatId;
    invoice['message_id'] = messageId;
    return invoice;
  }
}
