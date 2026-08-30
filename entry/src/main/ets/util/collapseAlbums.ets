import { isLivePhotoVideo } from './livePhoto';
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
  // parallel to photoPaths — true for PG 发的实况照片（见 util/livePhoto）。
  // 和 photoIsVideo 同源同处派生：都是成员消息的静态属性，一次算好，
  // 免得渲染侧各写一份判据、还得再多背两条并行数组（文件名 + 时长）。
  photoIsLive: boolean[];
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
  // Present only during ChatPage's first-frame staging. The data source keeps
  // the full logical row count while the builder substitutes a fixed-height,
  // node-light placeholder for this row; the marker goes away when the
  // unstaged snapshot is published on a following frame.
  //
  // 这个标记**故意不进行 key**——占位和真身是同一行，key 不该变。LazyForEach
  // 时代这曾是个用户可见的 bug：RELOAD 的契约是「key 没变就沿用原来的子组件」，
  // 于是在 RELOAD 那一批里翻成真身的行会被默默留在占位状态，而数据源已经换成
  // 真快照、此后任何差分都不会再点到它的名——屏幕上就是一条满高的空白行，只有
  // 滚出缓存区重建才自愈。当时的兜法是 RELOAD 之后补发一次不带 key 的 CHANGE。
  //
  // **Repeat 之下不需要那条补发路径，已经上机确认**（2026-08-29，报告人原话：
  // 「之前见过，现在没发现了」）。Repeat 的更新判据是 item 变没变、key 只用来
  // 配对（官方《Repeat：可复用的循环渲染》：「仅改变键值不改变 item 的情况不会
  // 触发刷新」），而占位→真身正是「key 不变、item 换了新对象」，落在**刷新**那
  // 一侧；咬人的那个前提在 Repeat 上不成立。
  //
  // 为验证这件事留的 [BlankRow] 探针（countDeferredFlips）已随结论一起删除。
  // 别再给这里加补发逻辑——要加之前先回头读这段。
  initialDeferred?: boolean;
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

// Signature of structural/content fields rendered by a bubble. High-frequency
// transfer state and translation presentation deliberately stay out: progress
// goes through mediaProgressChannel, while completion/failure/active state and
// translation snapshots go through messageRowPresentationChannel. Putting any
// of those here renames the LazyForEach item and rebuilds the whole ListItem.
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
  //
  // m.id 进**内容签名**（不是行身份）。行身份用 rowId，发送成功时它跨过临时
  // id → 真实 id 的替换保持不变，行才不会被销毁重建。可 id 本身是气泡要用的
  // 数据：编辑、删除、复制链接、回复全按 m.id 定位。id 不进任何 key 时，纯文本
  // 消息发送成功前后这一行的 key 逐字节相同，数据源判定"没变"、不发 CHANGE，
  // LazyForEach 于是不再重读这一格——气泡里的 @Prop msg 一直揣着那个已经作废
  // 的临时 id，直到别的字段碰巧改动或退出重进（issue #66「刚发的消息无法编辑」）。
  //
  // 放进内容签名而不是行身份，得到的是 CHANGE 而非 RELOAD：sameIdentity 只看
  // rowId，仍然判同一个 item，行不重建，只是就地拿到新数据。每条发出的消息
  // 多一次 CHANGE，代价可以忽略。
  let s = `${m.id}_${m.commentCount}_${m.forwardFrom}_${m.senderName}_${m.contentType}_${m.stickerFormat}` +
    `_${m.placeholderLabel}_${m.systemKind}_${m.isUnsupportedMessage}` +
    `_${m.linkPreviewType}_${m.linkUrl}_${m.linkSiteName}_${m.linkTitle}_${m.linkDescription}` +
    `_${m.linkPhotoFileId}_${m.linkPhotoWidth}_${m.linkPhotoHeight}` +
    `_${m.photoFileId}_${m.videoFileId}_${m.videoDuration}_${m.isEmojiSticker}` +
    `_${m.editDate}` +
    `_${m.inlineCustomEmojiPaths.join('|')}_${m.voiceListened}_${m.voiceWaveform}` +
    `_${m.audioTitle}_${m.audioPerformer}` +
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
      s += `#${b.text}:${b.url}:${b.callbackData}:${b.isGame}:${b.style}`;
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
      const photoIsLive: boolean[] = [];
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
        photoIsLive.push(list[j].contentType === 'video' &&
          isLivePhotoVideo(list[j].videoFileName, list[j].videoDuration));
        photoProgress.push(list[j].photoProgress);
        photoFailed.push(list[j].photoFailed);
        videoFileIds.push(list[j].videoFileId);
        videoFileSizes.push(list[j].videoFileSize);
        videoMimeTypes.push(list[j].videoMimeType);
        // **取第一条带文字的成员，不是最后一条。**
        //
        // 相册的配文在 TDLib 里挂在某一条成员消息上，Telegram 各端都挂在第一条。
        // 而 albumHead() 克隆的正是第一条——配文和"整行的那条消息"因此天然是
        // 同一条，译文、翻译状态、行签名三者才对得上（见下面 translationBlock
        // 在相册分支上的挂载）。原来取最后一条，一旦哪天真出现多条带文字的
        // 相册，配文来自 A、译文取自 B，页面上就是"翻译了却不显示"。
        if (caption === '' && list[j].text !== '') {
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
        // 行身份用 rowId / rowMemberIds 而不是真实 id：发送成功时 TDLib 把临时 id
        // 换成真实 id，拿 id 当行身份会让这一行被当成新 item 销毁重建。
        // 但 memberIds（真实 id）仍要进内容签名——相册每一格的点击、下载、
        // 转发都按真实 id 定位，见 mutableSig 里 m.id 那段。
        // sendState 经 sendStateChannel 直达状态图标；完成/失败和翻译展示经
        // messageRowPresentationChannel 直达行包装器，都不必重建整行。
        key: `a_${m.albumId}_${m.rowId}_${rowMemberIds.join(',')}_${memberIds.join(',')}_${photoFileIds.join(',')}_${videoFileIds.join(',')}_${caption}_${captionEntities.map((entity: TdObject): string => JSON.stringify(entity)).join('|')}_${dateLabel}_${mutableSig(displayHead)}`,
        head: displayHead,
        memberIds,
        rowMemberIds,
        photoPaths,
        photoFileIds,
        photoRatios,
        photoIsVideo,
        photoIsLive,
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
        // sendState、下载展示态和翻译走旁路通道而不进 key。
        key: `${m.rowId}_${m.text}_${m.replyText}_${dateLabel}_${mutableSig(m)}`,
        head: m,
        memberIds: [m.id],
        rowMemberIds: [m.rowId],
        photoPaths: [],
        photoFileIds: [],
        photoRatios: [],
        photoIsVideo: [],
        photoIsLive: [],
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
