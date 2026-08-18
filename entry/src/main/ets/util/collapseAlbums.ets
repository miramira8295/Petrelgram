import { MessageEntry, cloneMessage } from '../store/MessageEntry';
import { TdObject } from '../tdkit/TdTypes';
import { formatDateSeparator, sameDay } from './formatDateSeparator';

// A display row: a single message, or a collapsed run of album (media group)
// photos rendered as one grid bubble.
export interface AlbumGroup {
  key: string;
  head: MessageEntry;      // carries sender/name/time/status for the row
  memberIds: number[];     // message ids in this row (1 for a normal message)
  // 与 memberIds 平行的行身份 id，只给行 key 用（见 MessageEntry.rowId）。
  // memberIds 仍是真实的 message id，回复/选择/播放位等一切按 id 定位的
  // 逻辑不受影响。
  rowMemberIds: number[];
  photoPaths: string[];    // album photo/video-thumbnail paths (empty for a non-album row)
  photoFileIds: number[];  // thumbnail file ids; 0 means the media has no downloadable cover
  photoRatios: number[];   // width/height per photo, parallel to photoPaths (masonry layout)
  photoIsVideo: boolean[]; // parallel to photoPaths — true for video members (play icon overlay)
  photoProgress: number[]; // parallel to photoPaths — thumbnail download progress (0-100)
  photoFailed: boolean[];  // parallel to photoPaths — tap the failed cell to retry
  // Full-resolution video source, parallel to photoPaths. 0/'' for photo
  // members. Needed to mount a play-slot player in a grid cell (see
  // VideoBubbleSurface) — the thumbnail file above is never enough to stream.
  videoFileIds: number[];
  videoFileSizes: number[];
  videoMimeTypes: string[];
  caption: string;         // album caption (from whichever member carries text)
  captionEntities: TdObject[]; // the caption's TDLib entities (links/mentions/hashtags)
  dateLabel: string;       // date pill shown above this row when the day changes ('' = none)
  showAvatar: boolean;     // last row of a same-sender run — the only one with the avatar
  showSenderName: boolean; // first row of a same-sender run — the only one with the name
}

// Consecutive rows by the same sender form a "run": the sender name renders only
// on the first row and the avatar only on the last (Telegram style).
function sameRun(a: MessageEntry, b: MessageEntry): boolean {
  return a.senderId !== 0 && a.senderId === b.senderId
    && a.isOutgoing === b.isOutgoing
    // A sender returning much later is a new visual run even on the same day.
    // Without the time bound, messages hours apart lose their name/avatar and
    // are incorrectly drawn as one continuous bubble stack.
    && Math.abs(a.date - b.date) <= 300
    && a.contentType !== 'system' && b.contentType !== 'system';
}

function aspectRatio(m: MessageEntry): number {
  if (m.photoWidth <= 0 || m.photoHeight <= 0) {
    return 1;
  }
  return m.photoWidth / m.photoHeight;
}

function albumHead(members: MessageEntry[]): MessageEntry {
  const head = cloneMessage(members[0]);
  const last = members[members.length - 1];
  // The first message remains the album's stable action/reply target, while
  // the visible time and delivery state describe the whole album.
  head.date = last.date;
  for (const member of members) {
    head.editDate = Math.max(head.editDate, member.editDate);
  }
  if (!head.isOutgoing) {
    return head;
  }
  if (members.some((m: MessageEntry): boolean => m.sendState === 'failed')) {
    head.sendState = 'failed';
  } else if (members.some((m: MessageEntry): boolean => m.sendState === 'sending')) {
    head.sendState = 'sending';
  } else if (members.every((m: MessageEntry): boolean => m.sendState === 'read')) {
    head.sendState = 'read';
  } else {
    head.sendState = 'sent';
  }
  return head;
}

// Download progress lands in the key at 5% steps, not per byte.
//
// TDLib emits updateFile many times a second. At full resolution every one of
// them changed the row key, so the data source raised CHANGE, LazyForEach
// rebuilt the row's subtree, and the thumbnail Image came back as a NEW node —
// replaying its appear transition. That is the "preview flickers while a video
// downloads" bug: the flicker rate was the updateFile rate. Bucketing keeps the
// progress ring moving (20 steps is finer than the ring reads) while cutting
// the rebuilds by an order of magnitude. 100 stays its own bucket so arriving
// at "done" is never merged into the 95% step.
function progressBucket(percent: number): number {
  return percent >= 100 ? 100 : Math.floor(percent / 5);
}

// Signature of the mutable fields a bubble renders that aren't already part of
// the key. Keys MUST change whenever rendered content changes: the LazyForEach
// data source diffs by key and skips notifications for key-equal rows.
//
// Deliberately NOT memoised per entry object. Caching on identity assumes the
// store only ever replaces entries via cloneMessage(), and entries are also
// mutated in place (see the sticker_state_changes test) — a stale signature
// there means the row silently stops updating, which is worse than the cost of
// rebuilding it. The rebuild frequency is bounded by coalescing notifies in
// MessageStore instead.
function mutableSig(m: MessageEntry): string {
  // videoPath: voice/file/video rows change rendering once the file lands.
  // senderName: chat-sender (posting-as-channel) names resolve async.
  let s = `${m.commentCount}_${m.forwardFrom}_${m.senderName}_${m.contentType}_${m.stickerFormat}` +
    `_${m.placeholderLabel}_${m.systemKind}_${m.isUnsupportedMessage}` +
    `_${m.linkPreviewType}_${m.linkUrl}_${m.linkSiteName}_${m.linkTitle}_${m.linkDescription}` +
    `_${m.linkPhotoFileId}_${m.linkPhotoPath !== '' ? 'lp' : ''}_${m.linkPhotoWidth}_${m.linkPhotoHeight}` +
    `_${progressBucket(m.linkPhotoProgress)}_${m.linkPhotoFailed}_${m.linkPhotoDownloadActive}` +
    `_${m.photoFileId}_${m.videoFileId}_${m.videoDuration}_${progressBucket(m.videoProgress)}_${m.videoFailed}` +
    `_${m.videoPath !== '' ? 'v' : ''}_${m.stickerPath !== '' ? 's' : ''}` +
    `_${progressBucket(m.stickerProgress)}_${m.stickerFailed}_${m.stickerDownloadActive}_${m.isEmojiSticker}` +
    `_${m.editDate}` +
    // 译文长度 + 语言 + 折叠态足以表达"这行的翻译展示变了"；全文进签名徒增
    // 每次 diff 的字符串比较成本。
    `_${m.translatedText.length}_${m.translatedLang}_${m.translationHidden}` +
    `_${m.inlineCustomEmojiPaths.join('|')}_${m.voiceListened}_${m.voiceWaveform}` +
    `_${m.mediaDownloadActive}_${m.audioTitle}_${m.audioPerformer}` +
    `_${m.contactPhone}_${m.contactFirstName}_${m.contactLastName}_${m.contactUserId}` +
    `_${m.contactAvatarPath !== '' ? 'ca' : ''}_${m.locationLatitude}_${m.locationLongitude}` +
    `_${m.locationValid}_${m.locationLivePeriod}_${m.locationExpiresIn}` +
    `_${m.venueTitle}_${m.venueAddress}_${m.pollId}_${m.pollQuestion}` +
    `_${m.pollTotalVoterCount}_${m.pollIsClosed}_${m.pollVotePending}_${m.pollVoteError}` +
    `_${m.pollCorrectOptionId}_${m.pollExplanation}_${m.pollCloseDate}` +
    `_${m.diceEmoji}_${m.diceValue}_${m.diceHasFinalState}` +
    `_${m.diceLayerPaths.filter((p: string): boolean => p !== '').length}` +
    `_${m.gameId}_${m.gameTitle}_${m.gameDescription}_${m.gameText}` +
    `_${m.paidMediaLocked}_${m.paidMediaStarCount}_${m.paidMediaCount}_${m.paidMediaKind}` +
    `_${m.giftKind}_${m.giftTitle}_${m.giftValue}_${m.giftStatus}_${m.giftRefunded}` +
    `_${m.giveawayState}_${m.giveawayWinnerCount}_${m.giveawayPrize}` +
    `_${m.giveawayDescription}_${m.giveawaySelectionDate}_${m.giveawayUnclaimedCount}` +
    `_${m.giveawayMessageId}_${m.giveawayRefunded}_${m.giveawayOnlyNewMembers}`;
  for (const option of m.pollOptions) {
    s += `~${option.text}:${option.voterCount}:${option.votePercentage}` +
      `:${option.isChosen ? 'c' : ''}:${option.isBeingChosen ? 'p' : ''}`;
  }
  for (const r of m.reactions) {
    // 自定义 emoji 的位图路径要进指纹，否则下载完成后气泡不会重建。
    s += `|${r.emoji}${r.customEmojiId}${r.customEmojiPath}${r.count}${r.isChosen ? 'c' : ''}`;
  }
  for (const row of m.inlineButtons) {
    for (const b of row) {
      s += `#${b.text}:${b.url}:${b.callbackData}:${b.isGame}`;
    }
  }
  for (const entity of m.textEntities) {
    const type = entity['type'] as TdObject | undefined;
    const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
    const url = type !== undefined ? ((type['url'] as string | undefined) ?? '') : '';
    const customEmojiId = type !== undefined ? `${type['custom_emoji_id'] ?? ''}` : '';
    s += `@${(entity['offset'] as number | undefined) ?? 0}` +
      `:${(entity['length'] as number | undefined) ?? 0}:${typeName}:${url}:${customEmojiId}`;
  }
  return s;
}

// Collapse consecutive photo messages that share a non-empty media_album_id into
// one AlbumGroup. Everything else passes through as a single-member group.
export function collapseAlbums(list: MessageEntry[]): AlbumGroup[] {
  const groups: AlbumGroup[] = [];
  let i = 0;
  let prevDate = 0;
  while (i < list.length) {
    const m = list[i];
    // Hidden TDLib notices have no visual row. Excluding them here (rather
    // than rendering a zero-height bubble later) keeps the next visible
    // message's date separator and run-boundary calculations correct.
    if (m.contentType === 'hidden') {
      i += 1;
      continue;
    }
    // Date pill above the first row of each calendar day (and the window's first row).
    const dateLabel: string = (prevDate === 0 || !sameDay(m.date, prevDate)) ? formatDateSeparator(m.date) : '';
    prevDate = m.date;
    if (m.albumId !== '' && (m.contentType === 'photo' || m.contentType === 'video')) {
      const memberIds: number[] = [];
      const rowMemberIds: number[] = [];
      const photoPaths: string[] = [];
      const photoFileIds: number[] = [];
      const photoRatios: number[] = [];
      const photoIsVideo: boolean[] = [];
      const photoProgress: number[] = [];
      const photoFailed: boolean[] = [];
      const videoFileIds: number[] = [];
      const videoFileSizes: number[] = [];
      const videoMimeTypes: string[] = [];
      const albumMembers: MessageEntry[] = [];
      let caption = '';
      let captionEntities: TdObject[] = [];
      let j = i;
      while (j < list.length && list[j].albumId === m.albumId && (list[j].contentType === 'photo' || list[j].contentType === 'video')) {
        memberIds.push(list[j].id);
        rowMemberIds.push(list[j].rowId);
        albumMembers.push(list[j]);
        photoPaths.push(list[j].photoPath);
        photoFileIds.push(list[j].photoFileId);
        photoRatios.push(aspectRatio(list[j]));
        photoIsVideo.push(list[j].contentType === 'video');
        photoProgress.push(list[j].photoProgress);
        photoFailed.push(list[j].photoFailed);
        videoFileIds.push(list[j].videoFileId);
        videoFileSizes.push(list[j].videoFileSize);
        videoMimeTypes.push(list[j].videoMimeType);
        if (list[j].text !== '') {
          caption = list[j].text;
          captionEntities = list[j].textEntities;
        }
        j += 1;
      }
      const displayHead = albumHead(albumMembers);
      groups.push({
        // videoFileIds 进 key：视频文件 id 迟到（TDLib 异步补上）时这一格
        // 得跟着重建，否则播放位选中它也挂不上播放器（videoFileId 还是 0）。
        // photoPaths 刻意不进 key：缩略图路径经 mediaThumbChannel 旁路直达
        // LiveThumbImage，进 key 意味着相册里任一张缩略图落地都会拖着整行重建。
        // photoProgress 同样不进 key，而且这一条是前一条的必要条件：缩略图很小，
        // 进度只在下载完成那一刻从 0 跳到 100，和路径落地是**同一个事件**。
        // 只把路径摘出去、把进度留下，重建照旧发生，只是触发字段换了个名字——
        // 真机实测净效果为零。等待中的进度环由 LiveProgressRing 自订阅刷新。
        // photoFileIds 仍然留着——fileId 变了说明换了另一份媒体（编辑替换、
        // 相册成员变动），那时确实该重建，LiveThumbImage 也需要重建才能订阅新的 fileId。
        // rowId 而不是 id、rowMemberIds 而不是 memberIds：发送成功时 TDLib 把
        // 临时 id 换成真实 id，用 id 做 key 会让这一行被当成新 item 重建。
        // sendState 也不进 key——它经 sendStateChannel 直达气泡里的状态图标，
        // 就地把时钟换成对号，不必重建整行。
        key: `a_${m.albumId}_${m.rowId}_${rowMemberIds.join(',')}_${photoFileIds.join(',')}_${photoFailed.join(',')}_${videoFileIds.join(',')}_${caption}_${captionEntities.map((entity: TdObject): string => JSON.stringify(entity)).join('|')}_${dateLabel}_${mutableSig(displayHead)}`,
        head: displayHead,
        memberIds,
        rowMemberIds,
        photoPaths,
        photoFileIds,
        photoRatios,
        photoIsVideo,
        photoProgress,
        photoFailed,
        videoFileIds,
        videoFileSizes,
        videoMimeTypes,
        caption,
        captionEntities,
        dateLabel,
        showAvatar: true,
        showSenderName: true
      });
      i = j;
    } else {
      groups.push({
        // senderAvatarPath 刻意不进 key：头像路径经 senderAvatarChannel 旁路
        // 直达气泡里的头像组件，进 key 意味着整群头像解析完的那一刻全页行
        // 重建（实测 change×31 + 掉帧）。photoPath 同理：经 mediaThumbChannel
        // 旁路直达 LiveThumbImage，进 key 会让缩略图落地拖着整行重建。
        // photoProgress 同理且与之同源：它和路径在同一个事件里一起变，留下
        // 任何一个，另一个的旁路化就白做（见相册分支的详细注释）。
        // 见相册分支的注释：rowId 让行身份跨过"临时 id → 真实 id"，
        // sendState 走旁路通道而不进 key。
        key: `${m.rowId}_${m.photoFailed}_${m.text}_${m.replyText}_${dateLabel}_${mutableSig(m)}`,
        head: m,
        memberIds: [m.id],
        rowMemberIds: [m.rowId],
        photoPaths: [],
        photoFileIds: [],
        photoRatios: [],
        photoIsVideo: [],
        photoProgress: [],
        photoFailed: [],
        videoFileIds: [],
        videoFileSizes: [],
        videoMimeTypes: [],
        caption: '',
        captionEntities: [],
        dateLabel,
        showAvatar: true,
        showSenderName: true
      });
      i += 1;
    }
  }
  // Second pass: mark run boundaries (a date pill between rows breaks the run).
  // The flags join the key so a row re-renders when a same-sender neighbor
  // arrives and its avatar/name visibility flips.
  for (let k = 0; k < groups.length; k++) {
    const next = k + 1 < groups.length ? groups[k + 1] : null;
    const prev = k - 1 >= 0 ? groups[k - 1] : null;
    groups[k].showAvatar = !(next !== null && next.dateLabel === '' && sameRun(groups[k].head, next.head));
    groups[k].showSenderName = !(prev !== null && groups[k].dateLabel === '' && sameRun(prev.head, groups[k].head));
    groups[k].key += `_${groups[k].showAvatar ? 'A' : 'a'}${groups[k].showSenderName ? 'N' : 'n'}`;
  }
  return groups;
}

// Display-row index containing a given message id (-1 if not present).
export function groupIndexOf(groups: AlbumGroup[], messageId: number): number {
  for (let i = 0; i < groups.length; i++) {
    if (groups[i].memberIds.indexOf(messageId) >= 0) {
      return i;
    }
  }
  return -1;
}
