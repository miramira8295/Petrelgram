import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { BUBBLE_AVATAR_GUTTER_VP, bubbleMaxWidth } from '../../util/mediaBox';
import { AvLoopVideo } from '../common/AvLoopVideo';
import { VoiceBubble } from './VoiceBubble';
import { MusicBubble } from './MusicBubble';
import { FileBubble } from './FileBubble';
import { ContactBubble } from './ContactBubble';
import { LocationBubble } from './LocationBubble';
import { PollBubble } from './PollBubble';
import { DiceBubble } from './DiceBubble';
import { GameBubble } from './GameBubble';
import { PaidMediaBubble } from './PaidMediaBubble';
import { GiftBubble } from './GiftBubble';
import { GiveawayBubble } from './GiveawayBubble';
import { formatClockTime } from '../../util/formatTime';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY, bubbleTextFor } from '../../util/theme';
import { str } from '../../util/strings';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { viewsReserve } from '../../util/viewCountChannel';
import { translationReplacesOriginal } from '../../util/translationMode';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { MessageBubbleContext, MessageBubbleShell } from './MessageBubbleShell';
import { MessageBubbleText } from './MessageBubbleText';

const VIDEO_NOTE_SIDE: number = 180;
interface RichContentBuilderParams {
  text: string;
  entities: TdObject[];
  maxWidth: number;
}
// 其余消息类型的兼容内容入口（语音、文件、特殊卡片等）。
// 行布局/材质/菜单/手势由公共壳负责，相册、单媒体、贴纸与正文直接绕过此入口。
@ComponentV2
export struct MessageBubble {
  private context: MessageBubbleContext = new MessageBubbleContext();
  private env: ChatEnvMirror = chatEnv;

  @Require @Param msg: MessageEntry;

  private attachedRowId: number = 0;
  private attachedPhotoFileId: number = 0;
  private attachedVideoFileId: number = 0;

  @Param nowSec: number = 0;

  @Param jumpFocus: number = 0;

  @Param leaving: number = 0;

  @Require @Param group: AlbumGroup;

  @Require @Param data: MessageBubbleRenderData;

  @Require @Param actions: MessageBubbleActions;

  @Local private livePhotoProgress: number = 0;

  @Local private liveVideoProgress: number = 0;

  private unsubPhotoProgress: (() => void) | null = null;

  private unsubVideoProgress: (() => void) | null = null;

  @Local private videoNotePlaying: boolean = false;

  private accent(): ResourceColor {
    return this.env.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private attachMessageChannels(message: MessageEntry): void {
    this.detachMessageChannels();
    this.seedProgress(message);
    if (message.photoFileId !== 0) {
      this.unsubPhotoProgress = subscribeProgress(message.photoFileId,
        (percent: number): void => { this.livePhotoProgress = percent; });
    }
    if (message.videoFileId !== 0) {
      this.unsubVideoProgress = subscribeProgress(message.videoFileId,
        (percent: number): void => { this.liveVideoProgress = percent; });
    }
    // 原地替换媒体可能只换 fileId；保留精确的通道身份，普通正文/状态更新不重挂。
    this.attachedRowId = message.rowId;
    this.attachedPhotoFileId = message.photoFileId;
    this.attachedVideoFileId = message.videoFileId;
  }

  private seedProgress(message: MessageEntry): void {
    this.livePhotoProgress = progressForOr(message.photoFileId, message.photoProgress);
    this.liveVideoProgress = progressForOr(message.videoFileId, message.videoProgress);
  }

  private detachMessageChannels(): void {
    if (this.unsubPhotoProgress !== null) {
      this.unsubPhotoProgress();
      this.unsubPhotoProgress = null;
    }
    if (this.unsubVideoProgress !== null) {
      this.unsubVideoProgress();
      this.unsubVideoProgress = null;
    }
    this.attachedRowId = 0;
  }

  aboutToAppear(): void { this.attachMessageChannels(this.msg); }

  aboutToDisappear(): void { this.detachMessageChannels(); }

  aboutToRecycle(): void { this.detachMessageChannels(); }

  aboutToReuse(): void { this.attachMessageChannels(this.msg); }

  @Monitor('msg')
  onMsgPropChanged(): void {
    if (this.attachedRowId !== this.msg.rowId) {
      // 非媒体类型的参数重绑仍需清自身的圆形视频状态。
      if (this.videoNotePlaying) { this.videoNotePlaying = false; }
    }
    if (this.attachedRowId !== this.msg.rowId ||
      this.attachedPhotoFileId !== this.msg.photoFileId ||
      this.attachedVideoFileId !== this.msg.videoFileId) {
      this.attachMessageChannels(this.msg);
    } else {
      this.seedProgress(this.msg);
    }
  }

  private bubbleMaxW(): number {
    // 只有群聊来信才有头像位；发出的消息和私聊来信按 0 算，能宽出 44vp。
    return bubbleMaxWidth(this.data.contentWidth, this.avatarReserve());
  }

  private inlineMaxW(): number {
    return this.bubbleMaxW() - 16;
  }

  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }

  private messageTimeText(): string {
    return formatClockTime(this.msg.date);
  }

  private timeReserve(): string {
    const editReserve = this.msg.editDate > 0 ? '         ' : '';
    return `${viewsReserve(this.context.liveViews)}${editReserve}  ${this.messageTimeText()}${this.msg.isOutgoing ? '   ' : ''}`;
  }

  private toggleVideoNote(): void {
    if (this.msg.videoPath === '') {
      this.actions.onVideoNoteDownload(this.msg.id);
      return;
    }
    this.videoNotePlaying = !this.videoNotePlaying;
  }

  private videoNoteDuration(): string {
    const total: number = Math.max(0, this.msg.videoDuration);
    const m: number = Math.floor(total / 60);
    const sec: number = total % 60;
    return `${m}:${`${sec}`.padStart(2, '0')}`;
  }

  private fallbackLabel(): string {
    const label = this.msg.placeholderLabel.trim();
    return label !== '' ? label : str('mb_unsupported');
  }

  private replacementTranslationShown(): boolean {
    return translationReplacesOriginal(
      this.env.translateReplaceOriginal,
      this.msg.translatedText,
      this.msg.translationHidden
    );
  }

  private displayedMessageText(original: string): string {
    return this.replacementTranslationShown() ? this.msg.translatedText : original;
  }

  private displayedMessageEntities(original: TdObject[]): TdObject[] {
    // TDLib 的实体偏移属于原文，不能套到另一段译文上——译文用译文自己那份。
    // 这里曾经返回一个**恒为空**的数组，于是译文一上屏就丢掉全部格式：加粗、
    // 代码块，以及撑着"展开引用"的 textEntityTypeExpandableBlockQuote。
    // 用户 2026-09-10 报的「翻译后被强制展开、样式被破坏」就是它。
    // 服务端没给实体时这里仍是空数组，渲染层照旧自动识别链接（richText 的
    // AUTO_LINK_RE 只在 entities 为空时才上场），和从前一致。
    // 数组身份稳定（挂在 MessageEntry 上，每条消息一份），parseFormattedText
    // 的按身份缓存不会串槽。
    return this.replacementTranslationShown() ? this.msg.translatedEntities : original;
  }

  @Builder
  richContent(params: RichContentBuilderParams) {
    MessageBubbleText({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
      context: this.context, text: params.text, entities: params.entities, maxWidth: params.maxWidth });
  }

  @Builder
  translationBlock() {
    if (this.msg.translatedText !== '' || this.context.translationStatus !== null) {
      MessageBubbleText({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
        context: this.context, mode: 'translation' });
    }
  }

  @Builder
  content() {
    if (this.msg.contentType === 'videoNote') {
      // 圆形视频：点一下原地播放，不进全屏——它本来就是个小圆，放大到全屏
      // 既没有更多信息，还要处理旋转元数据（ijk 不读，会转 90 度）。
      Stack({ alignContent: Alignment.Center }) {
        // 封面始终垫在底下，播放器叠上去。做成 if/else 的话切换瞬间封面已经
        // 卸载、首帧还没到，中间会空一帧——表现就是点下去闪一下。
        if (this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/')
            ? `file://${this.msg.photoPath}` : this.msg.photoPath)
            .width(VIDEO_NOTE_SIDE).height(VIDEO_NOTE_SIDE)
            .objectFit(ImageFit.Cover)
            .draggable(false);
        } else {
          Column()
            .width(VIDEO_NOTE_SIDE).height(VIDEO_NOTE_SIDE)
            .backgroundColor($r('app.color.surface_alt'));
        }
        if (this.videoNotePlaying && this.msg.videoPath !== '') {
          AvLoopVideo({
            videoPath: this.msg.videoPath,
            boxWidth: VIDEO_NOTE_SIDE,
            boxHeight: VIDEO_NOTE_SIDE,
            loop: false,
            muted: false,
            onFinished: (): void => { this.videoNotePlaying = false; },
            onFailed: (): void => { this.videoNotePlaying = false; }
          });
        }
        if (!this.videoNotePlaying) {
          Row() {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(22).fontColor([Color.White]);
          }
          .width(46).height(46).borderRadius(23)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000');
        }
        // 时长压在圆底，和 Telegram 一致。
        Text(this.videoNoteDuration())
          .fontSize(11).fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor('#66000000').borderRadius(9)
          .offset({ y: VIDEO_NOTE_SIDE / 2 - 18 });
      }
      .width(VIDEO_NOTE_SIDE).height(VIDEO_NOTE_SIDE)
      .borderRadius(VIDEO_NOTE_SIDE / 2)
      .clip(true)
      .accessibilityText(this.videoNotePlaying
        ? str('mb_video_note_playing') : str('mb_video_note', this.videoNoteDuration()))
      .onClick((): void => {
        if (this.context.gestureClaimed) { return; }
        this.toggleVideoNote(); });
    } else if (this.msg.contentType === 'voice') {
      // Voice note with live playback progress — VoiceBubble subscribes to the
      // shared player itself, so ticks don't depend on this row re-rendering.
      VoiceBubble({
        msgId: this.msg.id,
        durationSec: this.msg.videoDuration,
        isOutgoing: this.msg.isOutgoing,
        voiceFileId: this.msg.videoFileId,
        voicePath: this.msg.videoPath,
        downloadProgress: this.liveVideoProgress,
        downloadFailed: this.msg.videoFailed,
        waveform: this.msg.voiceWaveform,
        listened: this.msg.voiceListened,
        speechState: this.msg.speechState,
        speechText: this.msg.speechText,
        onNeedDownload: (): void => { this.actions.onVoiceTap(this.msg.id); },
        onPlaybackStarted: (): void => { this.actions.onVoicePlaybackStarted(this.msg.id); },
        onRecognizeTap: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onRecognizeSpeech(this.msg.id); }
      });
    } else if (this.msg.contentType === 'audio') {
      // Music is intentionally distinct from a voice note: album artwork and
      // metadata lead the card, while the shared player guarantees that only
      // one voice/music item owns audio focus at a time.
      MusicBubble({
        msgId: this.msg.id,
        durationSec: this.msg.videoDuration,
        isOutgoing: this.msg.isOutgoing,
        audioFileId: this.msg.videoFileId,
        audioPath: this.msg.videoPath,
        fileSize: this.msg.videoFileSize,
        fileName: this.msg.videoFileName,
        title: this.msg.audioTitle,
        performer: this.msg.audioPerformer,
        coverPath: this.msg.photoPath,
        coverMini: this.msg.audioCoverMini,
        coverFailed: this.msg.photoFailed,
        downloadProgress: this.liveVideoProgress,
        downloadFailed: this.msg.videoFailed,
        downloadActive: this.msg.mediaDownloadActive,
        queuePosition: this.data.audioQueuePosition,
        queueLength: this.data.audioQueueLength,
        hasPrevious: this.data.audioHasPrevious,
        hasNext: this.data.audioHasNext,
        maxWidth: this.inlineMaxW(),
        onToggle: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onAudioTap(this.msg.id); },
        onPrevious: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onAudioPrevious(this.msg.id); },
        onNext: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onAudioNext(this.msg.id); },
        onSeek: (fraction: number): void => { this.actions.onAudioSeek(this.msg.id, fraction); },
        chatId: this.data.chatId,
        mimeType: this.msg.videoMimeType,
        onSave: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onAudioSave(this.msg.id); },
        onFavorite: (): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onAudioFavorite(this.msg.id);
        }
      });
      if (this.displayedMessageText(this.msg.text) !== '') {
        Column() {
          this.richContent({
            text: this.displayedMessageText(this.msg.text),
            entities: this.displayedMessageEntities(this.msg.textEntities),
            maxWidth: this.inlineMaxW()
          });
          // 见上：配文的译文原来无处可显示。
          this.translationBlock();
        }.margin({ top: 5 });
      }
    } else if (this.msg.contentType === 'file') {
      FileBubble({
        fileId: this.msg.videoFileId,
        fileName: this.msg.videoFileName,
        mimeType: this.msg.videoMimeType,
        fileSize: this.msg.videoFileSize,
        filePath: this.msg.videoPath,
        downloadProgress: this.liveVideoProgress,
        downloadFailed: this.msg.videoFailed,
        downloadActive: this.msg.mediaDownloadActive,
        uploading: this.context.liveSendState === 'sending',
        maxWidth: this.inlineMaxW(),
        // 长按弹菜单/左滑回复会认领手势；FileBubble 是子组件、看不到认领标记，
        // 早退只能在这层闭包里做——否则长按文件消息弹菜单的同时把下载也触发了。
        onOpen: (): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onFileTap(this.msg.id);
        },
        onSave: (): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onFileSave(this.msg.id);
        },
        onPause: (): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onFilePause(this.msg.id);
        }
      });
      if (this.displayedMessageText(this.msg.text) !== '') {
        Column() {
          this.richContent({
            text: this.displayedMessageText(this.msg.text),
            entities: this.displayedMessageEntities(this.msg.textEntities),
            maxWidth: this.inlineMaxW()
          });
          // 见上：配文的译文原来无处可显示。
          this.translationBlock();
        }.margin({ top: 5 });
      }
    } else if (this.msg.contentType === 'contact') {
      ContactBubble({
        firstName: this.msg.contactFirstName,
        lastName: this.msg.contactLastName,
        phone: this.msg.contactPhone,
        vcard: this.msg.contactVcard,
        userId: this.msg.contactUserId,
        avatarPath: this.msg.contactAvatarPath,
        maxWidth: this.inlineMaxW(),
        onOpen: (): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onContactOpen(
            this.msg.contactUserId,
            this.msg.contactPhone,
            this.msg.contactVcard
          );
        },
        onCall: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onPhoneOpen(this.msg.contactPhone); }
      });
    } else if (this.msg.contentType === 'location' || this.msg.contentType === 'venue') {
      LocationBubble({
        latitude: this.msg.locationLatitude,
        longitude: this.msg.locationLongitude,
        accuracy: this.msg.locationAccuracy,
        valid: this.msg.locationValid,
        livePeriod: this.msg.locationLivePeriod,
        expiresIn: this.msg.locationExpiresIn,
        messageDate: this.msg.date,
        nowSec: this.nowSec,
        venueTitle: this.msg.venueTitle,
        venueAddress: this.msg.venueAddress,
        venueProvider: this.msg.venueProvider,
        proximityRadius: this.msg.locationProximityRadius,
        maxWidth: this.inlineMaxW(),
        sharing: this.data.liveSharingId !== 0 && this.data.liveSharingId === this.msg.id,
        onStopLive: (): void => { if (this.context.gestureClaimed) { return; } this.actions.onStopLiveLocation(); },
        onOpen: (): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onLocationOpen(
            this.msg.locationLatitude,
            this.msg.locationLongitude,
            this.locationLabel(),
            this.msg.locationValid
          );
        }
      });
    } else if (this.msg.contentType === 'poll') {
      PollBubble({
        messageId: this.msg.id,
        question: this.msg.pollQuestion,
        options: this.msg.pollOptions,
        totalVoterCount: this.msg.pollTotalVoterCount,
        isAnonymous: this.msg.pollIsAnonymous,
        isQuiz: this.msg.pollIsQuiz,
        allowMultiple: this.msg.pollAllowMultiple,
        correctOptionId: this.msg.pollCorrectOptionId,
        explanation: this.msg.pollExplanation,
        closeDate: this.msg.pollCloseDate,
        isClosed: this.msg.pollIsClosed,
        pending: this.msg.pollVotePending,
        errorText: this.msg.pollVoteError,
        nowSec: this.nowSec,
        revision: this.pollRevision(),
        maxWidth: this.inlineMaxW(),
        onVote: (messageId: number, optionIds: number[]): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onPollVote(messageId, optionIds);
        }
      });
    } else if (this.msg.contentType === 'dice') {
      DiceBubble({
        emoji: this.msg.diceEmoji,
        value: this.msg.diceValue,
        hasFinalState: this.msg.diceHasFinalState,
        successFrame: this.msg.diceSuccessFrame,
        stickerPath: this.msg.stickerPath,
        layerPaths: this.msg.diceLayerPaths,
        playKey: `${this.data.chatId}:${this.msg.id}`,
        canInteract: (): boolean => !this.context.gestureClaimed && !this.data.selectionActive,
        onSendSame: (emoji: string): void => { this.actions.onSendDice(emoji); }
      });
    } else if (this.msg.contentType === 'game') {
      GameBubble({
        messageId: this.msg.id,
        title: this.msg.gameTitle,
        shortName: this.msg.gameShortName,
        description: this.msg.gameDescription,
        gameText: this.msg.gameText,
        photoPath: this.msg.photoPath,
        photoFileId: this.msg.photoFileId,
        photoProgress: this.livePhotoProgress,
        photoFailed: this.msg.photoFailed,
        maxWidth: this.inlineMaxW(),
        onOpen: (messageId: number): void => { if (this.context.gestureClaimed) { return; } this.actions.onGameOpen(messageId); },
        onRetryPhoto: (messageId: number): void => { if (this.context.gestureClaimed) { return; } this.actions.onGamePhotoRetry(messageId); }
      });
    } else if (this.msg.contentType === 'paidMedia') {
      PaidMediaBubble({
        messageId: this.msg.id,
        locked: this.msg.paidMediaLocked,
        starCount: this.msg.paidMediaStarCount,
        mediaCount: this.msg.paidMediaCount,
        mediaKind: this.msg.paidMediaKind,
        caption: this.displayedMessageText(this.msg.text),
        photoPath: this.msg.photoPath,
        photoFileId: this.msg.photoFileId,
        photoProgress: this.livePhotoProgress,
        photoFailed: this.msg.photoFailed,
        pending: this.data.paidMediaPending,
        maxWidth: this.inlineMaxW(),
        onUnlock: (messageId: number): void => { if (this.context.gestureClaimed) { return; } this.actions.onPaidMediaUnlock(messageId); },
        onOpen: (messageId: number): void => { if (this.context.gestureClaimed) { return; } this.actions.onPaidMediaOpen(messageId); },
        onRetryPhoto: (messageId: number): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onSpecialPhotoRetry(messageId);
        }
      });
      this.translationBlock();
    } else if (this.msg.contentType === 'gift') {
      GiftBubble({
        messageId: this.msg.id,
        kind: this.msg.giftKind,
        title: this.msg.giftTitle,
        value: this.msg.giftValue,
        status: this.msg.giftStatus,
        text: this.displayedMessageText(this.msg.text),
        code: this.msg.giftCode,
        refunded: this.msg.giftRefunded,
        photoPath: this.msg.photoPath,
        photoFileId: this.msg.photoFileId,
        photoProgress: this.livePhotoProgress,
        photoFailed: this.msg.photoFailed,
        maxWidth: this.inlineMaxW(),
        onRetryPhoto: (messageId: number): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onSpecialPhotoRetry(messageId);
        },
        onCopyCode: (code: string): void => { if (this.context.gestureClaimed) { return; } this.actions.onGiftCodeCopy(code); }
      });
      this.translationBlock();
    } else if (this.msg.contentType === 'giveaway') {
      GiveawayBubble({
        messageId: this.msg.id,
        state: this.msg.giveawayState,
        winnerCount: this.msg.giveawayWinnerCount,
        prize: this.msg.giveawayPrize,
        description: this.msg.giveawayDescription,
        selectionDate: this.msg.giveawaySelectionDate,
        unclaimedCount: this.msg.giveawayUnclaimedCount,
        originalMessageId: this.msg.giveawayMessageId,
        boostedChatId: this.msg.giveawayBoostedChatId,
        refunded: this.msg.giveawayRefunded,
        onlyNewMembers: this.msg.giveawayOnlyNewMembers,
        photoPath: this.msg.photoPath,
        maxWidth: this.inlineMaxW(),
        onOpenOriginal: (chatId: number, messageId: number): void => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onGiveawayOpen(chatId, messageId);
        }
      });
    } else if (this.msg.isUnsupportedMessage) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20).fontColor([this.accent()]).width(22);
        Column({ space: 1 }) {
          Text(this.fallbackLabel())
            .fontSize(13).fontColor(bubbleTextFor(this.msg.isOutgoing)).fontWeight(FontWeight.Medium)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text() {
            Span($r('app.string.mb_partial_content')).fontColor(COLOR_TEXT_SECONDARY);
            Span(this.timeReserve()).fontSize(12).fontColor(Color.Transparent);
          }.fontSize(11);
        }.alignItems(HorizontalAlign.Start);
      }
      .constraintSize({ maxWidth: this.inlineMaxW() })
      .padding({ top: 2, bottom: 2 })
      .accessibilityText(str('mb_fallback_partial', this.fallbackLabel()));
    } else {
      Text() {
        Span(this.fallbackLabel()).fontColor(COLOR_TEXT_SECONDARY);
        Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
      }.fontSize(this.env.msgTextSize);
    }
  }

  private pollRevision(): string {
    let revision = `${this.msg.pollId}_${this.msg.pollIsClosed}_${this.msg.pollTotalVoterCount}` +
      `_${this.msg.pollVotePending}_${this.msg.pollCorrectOptionId}`;
    this.msg.pollOptions.forEach((option, index: number): void => {
      revision += `_${index}_${option.voterCount}_${option.votePercentage}` +
        `_${option.isChosen}_${option.isBeingChosen}`;
    });
    return revision;
  }

  private locationLabel(): string {
    const title = this.msg.venueTitle.trim();
    const address = this.msg.venueAddress.trim();
    if (title !== '' && address !== '') {
      return `${title}，${address}`;
    }
    return title !== '' ? title : address;
  }

  build() {
    MessageBubbleShell({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
