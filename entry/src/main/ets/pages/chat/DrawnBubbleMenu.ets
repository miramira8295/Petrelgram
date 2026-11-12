import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { MessageEntry } from '../../store/MessageEntry';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { editableCached, ensureEditable } from '../../util/messageEditable';
import { deletableCached, ensureDeletable } from '../../util/messageDeletable';
import { getTdClient } from '../../tdkit/Globals';
import { messageUrls } from '../../util/richText';
import { reactionKeyFrom } from '../../util/reactions';
import { showToast } from '../../util/toast';
import { str } from '../../util/strings';
import { COLOR_ICON_SECONDARY } from '../../util/theme';
import { canBackgroundCache } from '../../util/backgroundCacheEligibility';
import { isFavoriteSticker } from '../../store/FavoriteStickers';
import { stickerSourceFileId } from '../../util/stickerSetItems';
import { chatEnv } from '../../util/chatEnvMirror';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
const QUICK_REACTIONS: string[] = ['❤️', '👍', '👎', '🔥', '🥰', '👏'];
const EDITABLE_CAPTION_TYPES: string[] = ['photo', 'video', 'audio', 'voice', 'file', 'animation'];
@Styles
function msgMenuActionNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }
@Styles
function msgMenuActionPressedStyle() { .opacity(0.72).scale({ x: 0.97, y: 0.94 }) }

// Lazy menu only. No MessageBubbleShell instance or menu subtree is created
// while an album is simply scrolling; behavior follows the existing shell.
@ComponentV2
export struct DrawnBubbleMenu {
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Local private editableTick: number = 0;
  @Local private deletableTick: number = 0;
  private env = chatEnv;
  private active: boolean = false;
  private generation: number = 0;
  aboutToAppear(): void { this.active = true; this.askEditable(); this.askDeletable(); }
  aboutToDisappear(): void { this.active = false; this.generation++; }
  @Computed
  private get urls(): string[] { return messageUrls(this.msg.text, this.msg.textEntities); }
  private reactionDuration(ms: number): number {
    return animationDurationFor(this.env.chatEffects && this.env.reactionEffects &&
      this.env.animatedEmoji && this.env.emojiReactions && !this.env.powerSaving, scrollActiveNow(), ms);
  }
  private stickerFileForFavorite(): number {
    return stickerSourceFileId(this.msg.contentType, this.msg.stickerFileId, this.msg.photoFileId, this.msg.stickerFormat);
  }
  private canEditNow(): boolean {
    // editableTick 必须在这一支里被**读到**，否则 V2 不会把它登记成依赖，
    // 答案到货时菜单就不会重绘。它自身不参与判断，只当"缓存可能变了"的信号。
    const known: boolean | undefined =
      this.editableTick >= 0 ? editableCached(this.msg.id) : undefined;
    if (known !== undefined) {
      return known;
    }
    return this.msg.isOutgoing && this.nowSec - this.msg.date < 172800;
  }

  private askEditable(): void {
    const generation = this.generation;
    ensureEditable(this.data.chatId, this.msg.id, (): void => {
      if (!this.active || this.generation !== generation) { return; }
      this.editableTick = this.editableTick + 1;
    });
  }

  private canDeleteNow(): boolean {
    // 和 canEditNow 一样：deletableTick 必须在这一支里被**读到**，否则 V2 不会
    // 把它登记成依赖，答案到货时菜单就不会重绘。它自身不参与判断。
    const known: boolean | undefined =
      this.deletableTick >= 0 ? deletableCached(this.msg.id) : undefined;
    // **未知时按能删显示。** 查询没回来、失败、或者 TDLib 返回了认不出来的结构，
    // 都退回修之前的样子——点了才发现删不了，绝不能因为没答案就把「删除」藏掉。
    return known !== false;
  }

  private askDeletable(): void {
    const generation = this.generation;
    ensureDeletable(getTdClient(), this.data.chatId, this.msg.id, (): void => {
      if (!this.active || this.generation !== generation) { return; }
      this.deletableTick = this.deletableTick + 1;
    });
  }

  private reactionChosen(reactionKey: string): boolean {
    for (const r of this.msg.reactions) {
      if (reactionKeyFrom(r.emoji, r.customEmojiId) === reactionKey) {
        return r.isChosen;
      }
    }
    return false;
  }

  private copyUrlToPasteboard(url: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      showToast($r('app.string.link_copied'), 1300);
    }).catch((): void => {
      showToast($r('app.string.copy_failed'), 1300);
    });
  }

  private copyMessageUrls(): void {
    const urls: string[] = this.urls;
    if (urls.length === 0) {
      return;
    }
    if (urls.length === 1) {
      this.copyUrlToPasteboard(urls[0]);
      return;
    }
    // 多条链接：弹菜单挑一条。showActionMenu 最多 6 个按钮，超出的截断——
    // 一条消息塞六条以上链接的场景，逐条挑本来也没有意义。
    const shown: string[] = urls.slice(0, 6);
    this.getUIContext().getPromptAction().showActionMenu({
      title: str('mb_copy_url'),
      buttons: shown.map((u: string): promptAction.Button => ({
        text: u.length > 40 ? u.substring(0, 37) + '…' : u,
        color: '#3390EC'
      })) as [promptAction.Button]
    }).then((result: promptAction.ActionMenuSuccessResponse): void => {
      const picked: string = shown[result.index] ?? '';
      if (picked !== '') {
        this.copyUrlToPasteboard(picked);
      }
    }).catch((): void => {});
  }

  @Builder
  messageReactionMenuItem() {
    Row({ space: 2 }) {
      ForEach(QUICK_REACTIONS, (e: string) => {
        Row() {
          Text(e).fontSize(23);
        }
        .width(32).height(34).borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.reactionChosen(e) ? '#263391E8' : Color.Transparent)
        .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
        .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
        .onClick((): void => { this.actions.onSetReaction(this.msg.id, e, this.reactionChosen(e)); })
        .gesture(LongPressGesture().onAction((): void => { this.actions.onSetDefaultReaction(e); }));
      }, (e: string): string => e);
      Blank();
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
      .animation({ duration: this.reactionDuration(110), curve: Curve.EaseOut })
      .onClick((): void => { this.actions.onOpenReactions(this.msg.id); });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Menu() {
      MenuItem(this.messageReactionMenuItem);
      if (this.data.canReply && !this.data.editingActive &&
        this.msg.contentType !== 'system' && this.msg.contentType !== 'hidden') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_turn_up_left')),
          content: $r('app.string.mb_reply')
        }).onClick((): void => { this.actions.onReplyTo(this.msg.id); });
      }
      if (this.canEditNow() &&
        (this.msg.contentType === 'text' || EDITABLE_CAPTION_TYPES.indexOf(this.msg.contentType) >= 0)) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
          content: this.msg.contentType === 'text' ? $r('app.string.edit') : $r('app.string.mb_edit_caption')
        }).onClick((): void => { this.actions.onEditMsg(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
        content: $r('app.string.mb_copy_text')
      }).onClick((): void => { this.actions.onCopyText(this.msg.id); });
      // 「复制消息链接」。TDLib 的 getMessageLink 只对**服务端已存在**的消息有效，
      // 本地待发（id <= 0）和系统消息不出现；拿不到链接（私密聊天等）由
      // ChatPage.copyMessageLink 兜底提示 cp_no_link。
      if (this.msg.id > 0 && this.msg.contentType !== 'system' && this.msg.contentType !== 'hidden') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.link')),
          content: $r('app.string.mb_copy_message_link')
        }).onClick((): void => { this.actions.onCopyLink(this.msg.id); });
      }
      // 「复制文本」是整条全选，这一项是 issue #94 要的"只copy其中一段"。
      if (this.msg.text !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.character_textbox')),
          content: $r('app.string.mb_select_text')
        }).onClick((): void => { this.actions.onSelectText(this.msg.id); });
      }
      if (this.msg.text !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.translate')),
          content: $r('app.string.mb_translate')
        }).onClick((): void => { this.actions.onTranslateMsg(this.msg.id); });
      }
      if (this.urls.length > 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.paperclip')),
          content: $r('app.string.mb_copy_url')
        }).onClick((): void => { this.copyMessageUrls(); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_turn_up_right')),
        content: $r('app.string.mb_forward')
      }).onClick((): void => { this.actions.onForwardMessages(this.group.memberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark')),
        content: $r('app.string.mb_save_to_saved')
      }).onClick((): void => { this.actions.onSaveMessages(this.group.memberIds); });
      // 视频专有：后台缓存（不存相册，进度在通知栏和「设置 › 下载中心」）。
      if (canBackgroundCache(this.msg)) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_circle')),
          content: $r('app.string.dc_background_cache')
        }).onClick((): void => { this.actions.onBackgroundCache(this.group.memberIds); });
      }
      // 动图专有：存进账号的 saved animations，之后从输入栏的 GIF 面板取用。
      // 判据用 isAnimation 而不是 contentType——GIF 在本应用里 contentType 就是
      // 'video'（messageAnimation 走视频管线，见 util/formatMsgContent），
      // 只有这个标志能把动图和普通视频分开。
      // 贴纸专有两项（issue 反馈①②）：看合集、收藏/取消收藏。
      if (this.msg.contentType === 'sticker' && this.msg.stickerSetId !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2')),
          content: $r('app.string.mb_view_sticker_set')
        }).onClick((): void => { this.actions.onViewStickerSet(this.msg.id); });
      }
      if (this.stickerFileForFavorite() !== 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier(isFavoriteSticker(this.stickerFileForFavorite())
            ? $r('sys.symbol.star_fill') : $r('sys.symbol.star')),
          content: isFavoriteSticker(this.stickerFileForFavorite())
            ? $r('app.string.mb_remove_favorite_sticker') : $r('app.string.mb_add_favorite_sticker')
        }).onClick((): void => { this.actions.onToggleFavoriteSticker(this.msg.id); });
      }
      if (this.msg.isAnimation && this.msg.videoFileId !== 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
          content: $r('app.string.mb_add_to_gifs')
        }).onClick((): void => { this.actions.onAddToGifs(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.repeat')),
        content: $r('app.string.mb_repeat')
      }).onClick((): void => { this.actions.onRepeatMessages(this.group.memberIds); });
      if (this.data.isGroup && this.msg.senderIsUser && this.msg.senderId > 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person')),
          content: $r('app.string.mb_view_history')
        }).onClick((): void => { this.actions.onViewSenderHistory(this.msg.senderId); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        content: this.data.isPinnedMsg ? $r('app.string.ft_unpin') : $r('app.string.ft_pin')
      }).onClick((): void => { this.actions.onPinMsg(this.msg.id, this.data.isPinnedMsg); });
      if (this.canEditNow() &&
        (this.msg.contentType === 'photo' || this.msg.contentType === 'video')) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.picture')),
          content: $r('app.string.mb_replace_media')
        }).onClick((): void => { this.actions.onReplaceMedia(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && this.msg.isOutgoing && !this.msg.pollIsClosed) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
          content: $r('app.string.mb_stop_poll')
        }).onClick((): void => { this.actions.onStopPoll(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && !this.msg.pollIsAnonymous) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person_2')),
          content: $r('app.string.mb_view_voters')
        }).onClick((): void => { this.actions.onPollVoters(this.msg.id); });
      }
      // 自己发的、密聊、我的收藏：没有可举报对象，不出这一项。
      if (this.data.canReport && !this.msg.isOutgoing) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.exclamationmark_circle')).fontColor([Color.Red]),
          content: $r('app.string.mb_report')
        }).onClick((): void => { this.actions.onReportMsg(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
        content: $r('app.string.mb_select')
      }).onClick((): void => { this.actions.onSelectMessages(this.group.memberIds); });
      // 不可删的消息（典型是频道里别人发的帖子、而你不是管理员）不出这一项：
      // 原来它照样出现，点下去要等一次查询、发现两个范围都不给，再弹一句
      // 「无法确认所选消息的可用删除范围」——等于点了个寂寞。
      if (this.canDeleteNow()) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Color.Red]),
          content: $r('app.string.delete')
        }).onClick((): void => { this.actions.onDeleteMsg(this.msg.id); });
      }
    }
    // 百分比宽度的表情行会让未定宽的 Menu 采用整屏约束，随后屏幕边界夹取会
    // 吞掉手指落点带来的横向偏移。固定回原菜单宽度，菜单才能继续贴近落点。
    .width(262)
  }

}
