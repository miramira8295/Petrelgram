import { MessageEntry } from '../../store/MessageEntry';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { TgsStickerView } from './TgsStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { stickerFramesCached } from '../../services/stickerFrameIndex';
import { MessageBubbleContext, MessageBubbleShell } from './MessageBubbleShell';

const STICKER_MAX: number = 160;

// 贴纸与独立表情的完整行入口：下载、播放回退和省电策略在此归属。
@ComponentV2
export struct StickerMessageBubble {
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private context: MessageBubbleContext = new MessageBubbleContext();
  private env: ChatEnvMirror = chatEnv;
  @Local private stickerPlaybackFailed: boolean = false;
  private contentRowId: number = 0;
  private contentType: string = '';
  private contentFileId: number = 0;
  private contentFormat: string = '';
  private contentPath: string = '';

  private syncContentIdentity(): void {
    if (this.contentRowId !== this.msg.rowId || this.contentType !== this.msg.contentType ||
      this.contentFileId !== this.msg.stickerFileId || this.contentFormat !== this.msg.stickerFormat ||
      this.contentPath !== this.msg.stickerPath) {
      this.contentRowId = this.msg.rowId;
      this.contentType = this.msg.contentType;
      this.contentFileId = this.msg.stickerFileId;
      this.contentFormat = this.msg.stickerFormat;
      this.contentPath = this.msg.stickerPath;
      if (this.stickerPlaybackFailed) { this.stickerPlaybackFailed = false; }
    }
  }

  private releaseContent(): void {
    this.detachMessageChannels();
  }

  private attachedRowId: number = 0;
  private attachedPhotoFileId: number = 0;
  @Local private livePhotoProgress: number = 0;
  private unsubPhotoProgress: (() => void) | null = null;
  private attachedStickerFileId: number = 0;
  @Local private liveStickerProgress: number = 0;
  private unsubStickerProgress: (() => void) | null = null;

  private attachMessageChannels(message: MessageEntry): void {
    this.syncContentIdentity();
    this.detachMessageChannels();
    this.seedProgress(message);
    if (message.photoFileId !== 0) {
      this.unsubPhotoProgress = subscribeProgress(message.photoFileId,
        (percent: number): void => { this.livePhotoProgress = percent; });
    }
    if (message.stickerFileId !== 0) {
      this.unsubStickerProgress = subscribeProgress(message.stickerFileId,
        (percent: number): void => { this.liveStickerProgress = percent; });
    }
    // 原地替换媒体可能只换 fileId；保留精确的通道身份，普通正文/状态更新不重挂。
    this.attachedRowId = message.rowId;
    this.attachedPhotoFileId = message.photoFileId;
    this.attachedStickerFileId = message.stickerFileId;
  }

  private seedProgress(message: MessageEntry): void {
    this.livePhotoProgress = progressForOr(message.photoFileId, message.photoProgress);
    this.liveStickerProgress = progressForOr(message.stickerFileId, message.stickerProgress);
  }

  private detachMessageChannels(): void {
    if (this.unsubPhotoProgress !== null) {
      this.unsubPhotoProgress();
      this.unsubPhotoProgress = null;
    }
    if (this.unsubStickerProgress !== null) {
      this.unsubStickerProgress();
      this.unsubStickerProgress = null;
    }
    this.attachedRowId = 0;
  }

  @Monitor('msg')
  onMsgPropChanged(): void {
    this.syncContentIdentity();
    if (this.attachedRowId !== this.msg.rowId ||
      this.attachedPhotoFileId !== this.msg.photoFileId ||
      this.attachedStickerFileId !== this.msg.stickerFileId) {
      this.attachMessageChannels(this.msg);
    } else {
      this.seedProgress(this.msg);
    }
  }

  aboutToAppear(): void { this.attachMessageChannels(this.msg); }
  aboutToReuse(): void { this.attachMessageChannels(this.msg); }
  aboutToDisappear(): void { this.releaseContent(); }
  aboutToRecycle(): void { this.releaseContent(); }

  private accent(): ResourceColor {
    return this.env.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  @Builder
  stickerStatusBadge(failed: boolean, percent: number) {
    Stack() {
      Circle({ width: 30, height: 30 }).fill('#78000000')
        .stroke('#20FFFFFF').strokeWidth(0.7);
      if (failed) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([Color.White]);
      } else if (percent > 0) {
        Progress({ value: percent, total: 100, type: ProgressType.Ring })
          .width(20).height(20).color(Color.White);
      } else {
        LoadingProgress().width(17).height(17).color(Color.White);
      }
    }
    .width(30).height(30)
    .accessibilityText(failed ? $r('app.string.mb_sticker_failed') : $r('app.string.mb_sticker_loading'));
  }

  @Builder
  stickerUnavailable() {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(24).fontColor([COLOR_ICON_SECONDARY]);
      Text($r('app.string.mb_sticker_unavailable'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
    }
    .width(this.stickerW()).height(this.stickerH())
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#12000000')
    .borderRadius(18);
  }

  @Builder
  stickerPausedFallback() {
    if (this.msg.text !== '') {
      Text(this.msg.text)
        .fontSize(this.msg.isEmojiSticker ? 52 : 42)
        .textAlign(TextAlign.Center)
        .width(this.stickerW()).height(this.stickerH());
    } else {
      Column({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.pause')).fontSize(21).fontColor([COLOR_ICON_SECONDARY]);
        Text($r('app.string.mb_animation_paused')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width(this.stickerW()).height(this.stickerH())
      .justifyContent(FlexAlign.Center);
    }
  }

  private stickerW(): number {
    const w = this.msg.photoWidth > 0 ? this.msg.photoWidth : 512;
    const h = this.msg.photoHeight > 0 ? this.msg.photoHeight : 512;
    return w >= h ? STICKER_MAX : Math.round(STICKER_MAX * (w / h));
  }

  private stickerH(): number {
    const w = this.msg.photoWidth > 0 ? this.msg.photoWidth : 512;
    const h = this.msg.photoHeight > 0 ? this.msg.photoHeight : 512;
    return h >= w ? STICKER_MAX : Math.round(STICKER_MAX * (h / w));
  }

  private webmFramesCached(): boolean {
    return stickerFramesCached(this.msg.stickerUniqueId,
      Math.max(vp2px(this.stickerW()), vp2px(this.stickerH())), this.msg.isEmojiSticker);
  }

  private stickerAnimationSuspended(): boolean {
    if (this.msg.stickerFormat !== 'tgs' && this.msg.stickerFormat !== 'webm') {
      return false;
    }
    if (this.env.powerSaving || this.env.reduceAnim) {
      return true;
    }
    if (this.msg.isEmojiSticker) {
      return !this.env.animatedEmoji || !this.env.emojiChat;
    }
    return !this.env.stickers || !this.env.stickerAutoplay;
  }

  @Builder
  content() {
    if (this.msg.contentType === 'emoji' || this.msg.contentType === 'customEmoji') {
      // Keep the Unicode alternative visible while a custom emoji resolves;
      // a small corner state communicates loading without replacing it.
      Stack() {
        if (this.msg.text !== '') {
          Text(this.msg.text)
            .fontSize(this.msg.contentType === 'customEmoji' ? 52 : 56)
            .textAlign(TextAlign.Center);
        } else {
          Text($r('app.string.mb_emoji_unavailable'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
        }
        if (this.msg.contentType === 'customEmoji') {
          Column() {
            if (this.msg.photoFailed) {
              this.stickerStatusBadge(true, 0);
            } else {
              LoadingProgress().width(14).height(14).color(this.accent())
                .backgroundColor('#CCFFFFFF').borderRadius(9).padding(2);
            }
          }
          .width('100%').height('100%')
          .padding({ right: 1, top: 1 })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End);
        }
      }
      .width(72).height(68)
      .alignContent(Alignment.Center)
      .onClick(() => {
        if (this.context.gestureClaimed) { return; }
        if (this.msg.contentType === 'customEmoji' && this.msg.photoFailed) {
          this.actions.onStickerRetry(this.msg.id);
        }
      })
      .accessibilityText(this.msg.contentType === 'customEmoji'
        ? (this.msg.photoFailed ? str('mb_custom_emoji_failed') : str('mb_custom_emoji_loading'))
        : this.msg.text);
    } else if (this.msg.contentType === 'sticker') {
      Stack() {
        if (this.stickerAnimationSuspended() && this.msg.photoPath === '') {
          this.stickerPausedFallback();
        } else if (this.stickerPlaybackFailed && this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath).draggable(false)
            .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain);
        } else if (this.stickerAnimationSuspended() && this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath).draggable(false)
            .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain);
        } else if (!this.stickerPlaybackFailed &&
          this.msg.stickerFormat === 'tgs' && this.msg.stickerPath !== '') {
          TgsStickerView({ tgsPath: this.msg.stickerPath, thumbPath: this.msg.photoPath,
            boxWidth: this.stickerW(), boxHeight: this.stickerH(),
            powerCategory: this.msg.isEmojiSticker ? 'emojiChat' : 'sticker',
            chatTimeline: true,
            onFailed: (): void => { this.stickerPlaybackFailed = true; } })
            .hitTestBehavior(HitTestMode.None);
        } else if (!this.stickerPlaybackFailed &&
          this.msg.stickerFormat === 'webm' && (this.msg.stickerPath !== '' || this.webmFramesCached())) {
          SmartLoopVideo({ videoPath: this.msg.stickerPath, thumbPath: this.msg.photoPath,
            stickerUid: this.msg.stickerUniqueId,
            boxWidth: this.stickerW(), boxHeight: this.stickerH(),
            powerCategory: this.msg.isEmojiSticker ? 'emojiChat' : 'sticker',
            // 会话里的 webm 贴纸跟 TGS 一样吃滑动闸。以前没传：那时它们全走
            // ijkplayer（独立 surface，不占 UI 线程），而现在走帧序列，一屏
            // 十几张同时往 Canvas 上画，滑动必卡。
            scrollGated: true,
            onPlaybackFailed: (): void => { this.stickerPlaybackFailed = true; } })
            .hitTestBehavior(HitTestMode.None);
        } else if (this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath).draggable(false)
            .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain)
            .transition(TransitionEffect.OPACITY.animation({
              duration: this.effectDuration(180), curve: Curve.EaseOut
            }));
        } else if (this.msg.photoFileId === 0 && this.msg.stickerFileId === 0) {
          this.stickerUnavailable();
        } else {
          Stack()
            .width(this.stickerW()).height(this.stickerH())
            .backgroundColor('#10000000').borderRadius(18);
        }

        if (this.msg.stickerPath === '' && this.msg.stickerFileId !== 0) {
          Column() {
            this.stickerStatusBadge(this.msg.stickerFailed,
              this.liveStickerProgress > 0 ? this.liveStickerProgress : this.livePhotoProgress);
          }
          .width('100%').height('100%')
          .padding({ right: 7, top: 7 })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End);
        } else if (this.msg.photoPath === '' && this.msg.photoFileId !== 0) {
          Column() {
            this.stickerStatusBadge(this.msg.photoFailed, this.livePhotoProgress);
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center);
        } else if (this.stickerPlaybackFailed) {
          Column() {
            this.stickerStatusBadge(true, 0);
          }
          .width('100%').height('100%')
          .padding({ right: 7, top: 7 })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End);
        }
      }
      .width(this.stickerW()).height(this.stickerH())
      .onClick(() => {
        if (this.context.gestureClaimed) { return; }
        if (this.stickerPlaybackFailed) {
          this.stickerPlaybackFailed = false;
          return;
        }
        if (this.msg.stickerFailed || this.msg.photoFailed) {
          this.actions.onStickerRetry(this.msg.id);
          return;
        }
        // 正常状态下点贴纸 = 看它属于哪个合集（官方端的行为）。不属于任何
        // 合集的贴纸（set_id 为 0）点了没有面板可开，保持原来的"无反应"。
        if (this.msg.stickerSetId !== '') {
          this.actions.onViewStickerSet(this.msg.id);
        }
      })
      .accessibilityText(this.msg.stickerFailed || this.msg.photoFailed || this.stickerPlaybackFailed
        ? $r('app.string.mb_sticker_failed') : $r('app.string.sticker_tab'));

    }
  }

  build() {
    MessageBubbleShell({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
