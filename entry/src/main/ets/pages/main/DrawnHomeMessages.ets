import { UIContext } from '@kit.ArkUI';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { TdClient } from '../../tdkit/TdClient';
import { getTdClient, getChatStore, getUserStore } from '../../tdkit/Globals';
import { recentChatHistory } from '../../services/RecentChatHistoryService';
import { ChatEntry } from '../../store/ChatEntry';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import { prefetchInitialPage } from '../../util/chatPrefetch';
import { drawnHomeMessages } from '../../util/drawnHomeMessagePlan';
import { AlbumGroup, collapseAlbums } from '../../util/collapseAlbums';
import { chatEnv } from '../../util/chatEnvMirror';
import { chatContentWidth } from '../../util/chatContentWidth';
import { a11yRuntimeState } from '../../util/a11yState';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { drawnTextRowEligible } from '../../util/drawnTextRowPolicy';
import { drawnSingleMediaEligible } from '../../util/drawnSingleMediaPolicy';
import { drawnAlbumEligible } from '../../util/drawnAlbumPolicy';
import { canRenderLightweightPlainTextRow } from '../../util/messageBubbleReuse';
import { drawnTextUsesRtlLayout } from '../chat/DrawnPlainTextLayout';
import { DrawnTextLayouts } from '../chat/DrawnTextLayout';
import { DrawnAlbumLayouts } from '../chat/DrawnAlbumLayout';
import { DrawnSingleMediaLayouts } from '../chat/DrawnSingleMediaLayout';
import { drawnLayoutWarmCache, DrawnRowLayoutEngine } from '../chat/DrawnLayoutWarmCache';
import { MessageBubbleRenderData } from '../chat/ReusableMessageBubble';
import { DrawnBubblePlan } from '../chat/DrawnBubblePlan';
import { PixelRequest, PixelHandle, cachedPixelMap, loadPixelMap } from '../../util/pixelCache';
import { logW } from '../../util/log';

// Diagnostics are scalars, never observed or written once per live row.
let preparedRows = 0, decoded = 0, alreadyDecoded = 0, decodeFailed = 0;
export function drawnHomeMessageSummary(): string {
  return `${drawnLayoutWarmCache.summary()}\nhome media: layouts=${preparedRows} decoded=${decoded} cached=${alreadyDecoded} failed=${decodeFailed}`;
}

function warmData(group: AlbumGroup, chat: ChatEntry): MessageBubbleRenderData {
  return {
    contentWidth: chatContentWidth(), isGroup: chat.kind === 'basicGroup' || chat.kind === 'supergroup' || chat.kind === 'channel',
    isChannel: chat.kind === 'channel', canReply: false, canReport: false,
    selectionActive: false, selectedMemberIds: [], chatId: chat.id, liveSharingId: 0,
    themeBubbleOut: '', showUnreadDivider: false, paidMediaPending: false,
    audioQueuePosition: 0, audioQueueLength: 0, audioHasPrevious: false, audioHasNext: false,
    playSlotKey: '', autoplayMuted: true, playSlotStartMs: 0, animationPaused: true,
    animationForcePlay: false, animationPlaybackFailed: false, editingActive: false,
    isPinnedMsg: false, liveGroupCallId: 0, animateIn: false,
    lightweightPlainText: canRenderLightweightPlainTextRow(group.head, group.memberIds.length, group.photoRatios.length)
  };
}

// One job for one recently opened ordinary chat, local history only. No
// MessageStore/openChat/viewMessages/subscriptions/media download/player is used.
// Parsing one entry, grouping the bounded window, preparing one row and issuing
// one decode occupy separate idle callbacks. At most two engines/eight images.
export class DrawnHomeMessages {
  private client: TdClient;
  private valid: (() => boolean) | undefined;
  private chat: ChatEntry | undefined;
  private raw: TdObject[] = [];
  private entries: MessageEntry[] = [];
  private groups: AlbumGroup[] | undefined;
  private requests: PixelRequest[] = [];
  private imageKeys: Set<string> = new Set();
  private pixelBudget: number = 1572864; // <=6 MiB RGBA requested pixels, not exact native allocation.
  private cursor: number = 0;
  private groupCursor: number = 0;
  private rows: number = 0;
  private waiting: boolean = true;
  private stopped: boolean = false;

  constructor(valid: () => boolean) { this.client = getTdClient(); this.valid = valid; }
  private live(): boolean { return !this.stopped && this.valid !== undefined && this.valid() && getTdClient() === this.client; }
  pending(): boolean { return !this.stopped; }

  async begin(): Promise<void> {
    try {
      const request: TdRequest = { '@type': 'getRecentlyOpenedChats' };
      request['limit'] = 1;
      const result = await this.client.send(request);
      if (!this.live()) { this.cancel(); return; }
      const ids = recentChatHistory(this.client).filter((result['chat_ids'] as number[] | undefined) ?? []);
      const id = ids[0];
      const store = getChatStore();
      const chat = id !== undefined ? store.entryOf(id) : undefined;
      if (chat === undefined || store.isForum(chat.id) || store.isAdministeredDirectMessagesGroup(chat.id)) { this.cancel(); return; }
      this.chat = chat;
      const promise = prefetchInitialPage(chat.id, chat.unreadCount, chat.lastReadInboxId, true);
      const page = await promise;
      if (!this.live()) { this.cancel(); return; }
      this.raw = drawnHomeMessages((page['messages'] as TdObject[] | undefined) ?? [],
        chat.unreadCount > 0 ? chat.lastReadInboxId : 0);
      this.waiting = false;
    } catch (error) {
      if (this.live()) { logW(`DrawnHomeMessages: local history unavailable: ${(error as Error).message}`); }
      this.cancel();
    }
  }

  step(ui: UIContext): void {
    if (!this.live()) { this.cancel(); return; }
    if (this.waiting) { return; }
    if (this.cursor < this.raw.length) {
      this.entries.push(buildMessageEntry(this.raw[this.cursor++], getUserStore(), false));
      return;
    }
    if (this.groups === undefined) {
      this.groups = collapseAlbums(this.entries); this.entries = []; this.raw = [];
      // Latest route starts at the bottom; around-unread selection is bounded
      // already, but candidate order should also start nearest the anchor.
      this.groupCursor = this.groups.length - 1;
      if (this.chat !== undefined && this.chat.unreadCount > 0) {
        let distance = Number.POSITIVE_INFINITY;
        for (let i = 0; i < this.groups.length; i++) {
          const d = Math.abs(this.groups[i].head.id - this.chat.lastReadInboxId);
          if (d < distance) { distance = d; this.groupCursor = i; }
        }
      }
      return;
    }
    if (this.rows < 2 && this.groupCursor >= 0 && this.chat !== undefined) {
      const group = this.groups[this.groupCursor--];
      this.prepare(ui, group, this.chat); return;
    }
    const req = this.requests.shift(); // <=8 items, fixed bound; no history scan.
    if (req === undefined) { this.cancel(); return; }
    if (cachedPixelMap(req) !== undefined) { alreadyDecoded++; return; }
    this.waiting = true;
    loadPixelMap(req).then((handle: PixelHandle | undefined): void => {
      if (handle !== undefined) { decoded++; } else { decodeFailed++; }
      this.waiting = false;
    }).catch((error: Error): void => {
      decodeFailed++; this.waiting = false;
      if (this.live()) { logW(`DrawnHomeMessages: thumbnail decode unavailable: ${error.message}`); }
    });
  }

  private prepare(ui: UIContext, group: AlbumGroup, chat: ChatEntry): void {
    const data = warmData(group, chat);
    const kind = group.memberIds.length > 1 ? 'album' : group.head.contentType === 'text' ? 'text' : 'single';
    if (chatEnv.drawnEnabled === false || chatEnv.bubbleMaterialOn || a11yRuntimeState.active ||
      chatEnv.msgTextSize <= 0 || data.contentWidth <= 0) { return; }
    const textEnv = `${chatEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
    if (drawnTextUsesRtlLayout(textEnv)) { return; }
    const body = kind === 'album' ? group.caption : group.head.text;
    if (body !== '' && (data.lightweightPlainText ? !chatEnv.drawnPlain : !chatEnv.drawnRich)) { return; }
    if (kind === 'text' ? !chatEnv.drawnText || !drawnTextRowEligible(group, data, false, false)
      : kind === 'album' ? !chatEnv.drawnAlbum || !drawnAlbumEligible(group, data, false, false)
      : !chatEnv.drawnSingle || !drawnSingleMediaEligible(group, false, false)) { return; }
    const engine: DrawnRowLayoutEngine = kind === 'text' ? new DrawnTextLayouts()
      : kind === 'album' ? new DrawnAlbumLayouts() : new DrawnSingleMediaLayouts();
    const plan = engine.prepare(ui, group, data, { radius: chatEnv.bubbleRadius,
      fontSize: chatEnv.msgTextSize, environment: `${chatEnv.appearanceEpoch}:${textEnv}`,
      textEnvironment: textEnv, role: group.head.senderTag, views: '' });
    if (plan === null) { return; }
    drawnLayoutWarmCache.put(this.client, chat.id, group.head.id, kind, engine);
    this.rows++; preparedRows++;
    this.queueImages(ui, plan);
  }

  private queueImages(ui: UIContext, plan: DrawnBubblePlan): void {
    for (const tile of plan.nativeTiles) {
      if (this.requests.length >= 8) { break; }
      // Match CachedImageSession's actual per-dimension conversion, including
      // fractional pixel rounding at cache bucket boundaries.
      const width = ui.vp2px(tile.width), height = ui.vp2px(tile.height);
      const path = tile.cell.thumbPath;
      const pixels = Math.ceil(width) * Math.ceil(height);
      if (path === '' || !Number.isFinite(pixels) || pixels <= 0 || pixels > this.pixelBudget) { continue; }
      const opaque = tile.opaque ?? true;
      const key = `${path}:${width}:${height}:${opaque}`;
      if (this.imageKeys.has(key)) { continue; }
      this.imageKeys.add(key); this.pixelBudget -= pixels;
      this.requests.push({ path, width, height, opaque });
    }
  }

  cancel(): void {
    this.stopped = true; this.valid = undefined; this.chat = undefined;
    this.raw = []; this.entries = []; this.groups = undefined; this.requests = []; this.imageKeys.clear();
    // An in-flight shared pixelCache decode is allowed to finish; cancelling it
    // would also abort a newly visible row waiting for the same cache key.
  }
}
