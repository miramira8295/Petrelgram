import { thumbBackdropColor } from '../../util/thumbBackdrop';
import { miniPlaceholderOf } from '../../util/miniThumbPlaceholder';
import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { LiveThumbImage, LiveThumbSpec } from './LiveThumbImage';
import { LiveProgressRing } from './LiveProgressRing';
import { ThumbReadyGate } from './ThumbReadyGate';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO } from './playSlot';
import { formatFileSize } from '../../util/formatFileSize';
import { formatMediaDuration } from '../../util/mediaDuration';
import { str } from '../../util/strings';
import { chatEnv } from '../../util/chatEnvMirror';

// 相册里的一格。
//
// 【为什么必须是组件，不能是 @Builder —— 2026-09-11 真机实证】
// 格子的宽高来自 packAlbumRows，多选、转屏、平板分栏都会让它变。原来这段是
// MessageBubble 里的 `@Builder albumCellSlot(cell)`，实测结论是：
//
//   **带参 @Builder 会重新执行，但它的参数是首次挂载时按值捕获的，之后永不
//   更新——传对象也一样。**
//
// 证据是同一条日志里并排的两个数：`this.albumW()` 已经是 251（多选后的新宽），
// 而参数 `cell.width` 还停在 91（277 态的值）。当时的表现就是"气泡缩了、相册
// 的图还是原来那么大，溢出到屏幕外"。
//
// V2 组件的 @Param 不走那一套：父组件重新求值构造表达式，@Param 就跟着更新，
// 而且只重渲染受影响的绑定。所以格子必须是组件，**且它的构造表达式必须写在
// 零参的 albumGrid() 里**——写在带参 builder 里一样送不进去。
//
// 同理，本组件**内部**的 @Builder 也一律零参、直接读 this.cell。
//
// 换来三件事：几何变化能被 animateTo 插值（多选进出不再硬切）、每格各自的勾选
// 状态能实时刷新、以及不再需要把几何塞进 ForEach 的键（那是"配图配错文"的老
// 解法，连同 util/albumCellKey 一起删掉了）。
export interface AlbumCellHooks {
  // 视频格上报中心 y，供播放位竞选（表住在 MessageBubble 那边）。
  onCenterY: (index: number, centerY: number) => void;
  centerYOf: (index: number) => number;
  // 手势是否已被左滑/右滑认领——认领了就别把这一下当点击。
  isClaimed: () => boolean;
  // 多选态下点这一格：只切这一张，不动整行。
  onToggleMember: (messageId: number) => void;
}

@ComponentV2
export struct AlbumCellView {
  @Require @Param cell: AlbumCellRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param hooks: AlbumCellHooks;
  // 多选态、勾选和媒体标量均由单格输入提供；不再读取整组的并行数组。
  private cachedThumbSpec: LiveThumbSpec | null = null;
  private metaBytes: number = -1;
  private metaDuration: number = -1;
  private metaWide: boolean = false;
  private metaLangEpoch: number = -1;
  private metaText: string = '';

  // 每格只保留一份输入。勾选/进度/播放角标变化不再制造新 spec，避免下层
  // Monitor 和图片属性无效刷新；命中前不创建临时对象，也不持有整条消息。
  private thumbSpec(): LiveThumbSpec {
    const cell: AlbumCellRenderData = this.cell;
    const backdrop: string = thumbBackdropColor(cell.isVideo);
    const mini: string = miniPlaceholderOf(cell.mini);
    const previous: LiveThumbSpec | null = this.cachedThumbSpec;
    if (previous !== null && previous.fileId === cell.thumbFileId &&
      previous.initialPath === cell.thumbPath && previous.boxWidth === cell.width &&
      previous.boxHeight === cell.height && previous.backdrop === backdrop && previous.mini === mini) {
      return previous;
    }
    const next: LiveThumbSpec = {
      syncDisplay: true, fileId: cell.thumbFileId, initialPath: cell.thumbPath,
      boxWidth: cell.width, boxHeight: cell.height, radius: 6, fit: ImageFit.Cover,
      // 一行 6–9 格保留 RGB_565；底色与下载占位同源，mini 仍在滚动时停用。
      opaque: true, backdrop, mini, deferMiniOnScroll: true
    };
    this.cachedThumbSpec = next;
    return next;
  }

  // 【这三个必须是**成员** @Builder，不能提成全局函数】
  // 2026-09-11 试过提到 pages/chat/mediaBadges.ets 做全局 @Builder，真机一进会话
  // 就崩：
  //     TypeError: Cannot read property observeComponentCreation2 of undefined
  //     #09 at playBadge (mediaBadges.ets:46)
  //     #10 at content   (AlbumCellView.ets:198)
  //     #15 at anonymous (ThumbReadyGate.ets:73)
  // 因为它们是从传给 ThumbReadyGate / LiveThumbImage 的**闭包**里调的，那时"当前
  // 视图"是那两个组件，全局 builder 生成的代码拿不到它需要的 this。
  // 成员 builder 走 `this.` 就没有这个问题。代价是消息气泡与相册格子各存一份。

  // Loading ring shown centered on a media placeholder while its thumbnail
  // downloads — same style as the fullscreen viewer's (percent inside the ring).
  @Builder
  mediaLoadState(size: number, fileId: number, initialPercent: number, failed: boolean) {
    if (failed) {
      Column({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(Math.max(17, size * 0.5))
          .fontColor([Color.White]);
        Text($r('app.string.settings_retry')).fontSize(11).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor('#80000000').borderRadius(18);
    } else {
      // 进度不进 key，环自己订阅自己更新（见 LiveProgressRing / collapseAlbums）。
      LiveProgressRing({ fileId: fileId, initialPercent: initialPercent, ringSize: size });
    }
  }

  // 实况角标。缩略图上（单图与相册格子都用它）标出「这条是实况」——和查看器
  // 左下角那枚胶囊同一套元素：同心圆的 sys.symbol.livephoto + LIVE 文案。
  //
  // 位置固定在左上角：左下角被时长/大小那条 meta 占着（单图），中心是播放钮，
  // 只有左上角是空的，相册格子同理。
  @Builder
  liveChip() {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.livephoto')).fontSize(12).fontColor([Color.White]);
      Text($r('app.string.cp_live_photo'))
        .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
    }
    .height(18)
    .padding({ left: 5, right: 6 })
    .backgroundColor('#66000000')
    .borderRadius(9)
    .position({ x: 6, y: 6 });
  }

  // Centered play-triangle badge, overlaid on video thumbnails.
  @Builder
  playBadge(size: number) {
    Stack() {
      Circle({ width: size, height: size }).fill('#73000000')
        .stroke('#24FFFFFF').strokeWidth(1);
      SymbolGlyph($r('sys.symbol.play_fill')).fontSize(size * 0.42).fontColor([Color.White]).margin({ left: 2 });
    }.width(size).height(size);
  }

  private idx(): number {
    return this.cell.idx;
  }

  private pathAt(): string {
    return this.cell.thumbPath;
  }

  private isVideo(): boolean {
    return this.cell.isVideo;
  }

  private isLive(): boolean {
    return this.cell.isLive;
  }

  private memberId(): number {
    return this.cell.messageId;
  }

  private fileId(): number {
    return this.cell.thumbFileId;
  }

  private failed(): boolean {
    return this.cell.failed;
  }

  private retryable(): boolean {
    return this.pathAt() === '' && this.failed() && this.fileId() !== 0;
  }

  private videoFileId(): number {
    return this.cell.videoFileId;
  }

  // 与 isPlaySlot() 同一道 !isAnimation 兜底：动图不参加竞选（spec §3.3），
  // 相册格子也不例外，否则相册里的动图会错挂流式播放器。
  private isPlaySlot(): boolean {
    return this.cell.isPlaySlot;
  }

  private videoMetaText(): string {
    const bytes: number = this.cell.videoFileSize;
    const durationSec: number = this.cell.videoDuration;
    const wide: boolean = this.cell.width >= 112;
    // Read every input before the hit, including the observed language epoch.
    // The condition and Text share one result without retaining a message.
    const langEpoch: number = chatEnv.langEpoch;
    if (this.metaBytes === bytes && this.metaDuration === durationSec &&
      this.metaWide === wide && this.metaLangEpoch === langEpoch) {
      return this.metaText;
    }
    const size: string = bytes > 0 ? formatFileSize(bytes) : '';
    const duration: string = durationSec <= 0 ? '' : formatMediaDuration(durationSec);
    // 三列等窄格优先保证 issue #93 要求的文件大小可见；宽格与单视频一致。
    const text: string = durationSec <= 0 ? size : (size !== '' && wide
      ? `${duration} · ${size}` : (size !== '' ? size : duration));
    this.metaBytes = bytes;
    this.metaDuration = durationSec;
    this.metaWide = wide;
    this.metaLangEpoch = langEpoch;
    this.metaText = text;
    return text;
  }

  // 占位底。两个变体只差 hasFile 一个条件，但**必须各自是零参 @Builder**——
  // 带参 builder 的参数不更新（见文件头），格子一缩它就停在旧尺寸上。
  // 相册整组一起发，头条的发送态就是整组的。
  private uploading(): boolean {
    return this.cell.uploading;
  }

  @Builder
  placeholderWithFile() {
    Stack() {
      if (!this.failed()) {
        this.mediaLoadState(
          Math.min(34, Math.min(this.cell.width, this.cell.height) * 0.4),
          this.fileId(),
          this.cell.progress,
          false
        );
      } else if (!this.isVideo()) {
        this.mediaLoadState(
          Math.min(34, Math.min(this.cell.width, this.cell.height) * 0.4), 0, 0, true);
      }
    }.width(this.cell.width).height(this.cell.height).borderRadius(6)
      .backgroundColor(thumbBackdropColor(this.isVideo()));
  }

  @Builder
  placeholderNoFile() {
    Stack() {
      if (!this.isVideo()) {
        this.mediaLoadState(
          Math.min(34, Math.min(this.cell.width, this.cell.height) * 0.4), 0, 0, true);
      }
    }.width(this.cell.width).height(this.cell.height).borderRadius(6)
      .backgroundColor(thumbBackdropColor(this.isVideo()));
  }

  @Builder
  cellBody() {
    if (this.isPlaySlot() && this.videoFileId() !== 0) {
      // 播放位选中这一格：挂播放器而不是静态封面。
      // 小窗播低清那一档（多清晰度，见 util/entryVideoVariant.entryInlineFile）。
      VideoBubbleSurface({
        fileId: this.cell.inlineFileId || this.videoFileId(),
        fileSize: this.cell.inlineFileId !== 0
          ? this.cell.inlineFileSize : this.cell.videoFileSize,
        mimeType: this.cell.videoMimeType,
        posterPath: this.pathAt(),
        muted: this.cell.autoplayMuted,
        startPositionMs: this.cell.playSlotStartMs,
        onPositionChanged: (positionMs: number): void => {
          this.actions.onPlaySlotPositionChanged(this.memberId(), this.idx(), positionMs);
        },
        onEnded: (): void => {
          this.actions.onPlaySlotEnded(this.memberId(), this.idx());
        }
      })
        .width(this.cell.width).height(this.cell.height).clip(true)
        .borderRadius(6)
        // 同理：交给格子自己的 onClick 打开全屏查看器。
        .hitTestBehavior(HitTestMode.None);
    } else if (this.fileId() !== 0 || this.pathAt() !== '') {
      // 不加入场动画：行重建会重新创建这个节点，每次都会重放一遍淡入。
      // desiredSize 在这里最要紧：一格只有几十 vp 宽，而它背后的文件是整个
      // 会话宽度的尺寸。
      // 自订阅：行 key 里不带路径，缩略图到货要靠这个节点自己反应。
      // 条件不能只看 fileId：MessageStore 会用原图下载回填 photoPath，而那一条
      // 的 fileId 可能仍是 0，丢了路径就把一张已下载的图退化成死的"重试"块。
      LiveThumbImage({
        spec: this.thumbSpec(),
        placeholder: (): void => { this.placeholderWithFile(); }
      });
    } else {
      // 没有可下载缩略图的视频照样能播；别在那上面留一个永远 0% 的转圈。
      this.placeholderNoFile();
    }
    // 出站发送中：每格叠一个上传环（同 MessageBubble 的单媒体分支）。
    if (this.uploading()) {
      this.mediaLoadState(
        Math.min(34, Math.min(this.cell.width, this.cell.height) * 0.4),
        this.isVideo() ? this.videoFileId() : this.fileId(), 0, false);
    }
    // 相册格同理：实况格已经有 liveChip，不画播放钮。
    if (this.isVideo() && !this.isLive() && !this.uploading() &&
      !(this.isPlaySlot() && this.videoFileId() !== 0)) {
      // 同单图那处：缩略图到没到要问通道，pathAt 在旁路化之后不再回填。
      ThumbReadyGate({
        fileId: this.fileId(),
        initialPath: this.pathAt(),
        ready: this.fileId() === 0 || this.failed(),
        content: (): void => {
          this.playBadge(Math.min(40, Math.min(this.cell.width, this.cell.height) * 0.46));
        }
      })
    }
    if (this.isLive()) {
      this.liveChip();
    }
    if (this.isVideo() && this.videoMetaText() !== '') {
      Text(this.metaText)
        .fontSize(10.5)
        .fontColor(Color.White)
        .backgroundColor('#66000000')
        .borderRadius(6)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: Math.max(24, this.cell.width - 12) })
        .position({ x: 6, y: Math.max(6, this.cell.height - 23) });
    }
  }

  // 勾选标记的定位层。
  //
  // 【为什么要单独套一层，而不是把外层 Stack 设成 TopEnd】(2026-09-11 用户报)
  // 外层 Stack 的 alignContent 作用在**每一个**没有显式定位的孩子身上。设成
  // TopEnd 之后，播放钮（ThumbReadyGate 里那枚，本该居中）也被一起甩到了右上角。
  // liveChip 和时长角标用的是 .position()，所以当时没露馅。
  // 外层保持默认居中，勾单独放进一个填满格子的 Stack 里去贴右上。
  @Builder
  selectionOverlay() {
    if (this.cell.selectionActive) {
      Stack({ alignContent: Alignment.TopEnd }) {
        this.selectionMark();
      }
      .width(this.cell.width).height(this.cell.height)
      // 只是个定位容器，别把格子的点击吃掉。
      .hitTestBehavior(HitTestMode.None);
    }
  }

  // 多选态下每格右上角那枚勾。**图标名照抄整行让位栏那枚**
  // （sys.symbol.checkmark_circle），不另猜名字。
  @Builder
  selectionMark() {
    Stack() {
      if (this.cell.selected) {
        Circle({ width: 20, height: 20 }).fill(Color.White);
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(22).fontColor([$r('app.color.primary')]);
      } else {
        Circle({ width: 19, height: 19 }).fill('#4D000000')
          .stroke(Color.White).strokeWidth(1.5);
      }
    }
    .width(22).height(22)
    .margin({ top: 5, right: 5 });
  }

  private onCellTap(e: ClickEvent): void {
    if (this.hooks.isClaimed()) {
      return;
    }
    // 多选态下点一格 = 只切这一张。此时不打开查看器、也不触发重试。
    if (this.cell.selectionActive) {
      this.hooks.onToggleMember(this.memberId());
      return;
    }
    // 失败的格子提供重试（与单图一致）。
    if (this.retryable()) {
      this.actions.onSpecialPhotoRetry(this.memberId());
      return;
    }
    this.actions.onMediaTap(this.memberId(), e.windowX, e.windowY);
  }

  // 哨兵格子（albumCellAt 越界时返回的 {idx:-1,width:0,height:0}）一律不画。
  // 画成 0×0 看着也"没有"，但它仍然占 Row 的一档 space，相册的宽高会抖一下。
  // AlbumRowView 已经在行级挡了一层，这里是双保险，也挡住别的越界来路。
  private isSentinel(): boolean {
    return this.cell.idx < 0 || this.cell.width <= 0 || this.cell.height <= 0;
  }

  build() {
    // 哨兵格子（越界时 albumCellAt 返回的 0×0）整段不画：画成 0×0 看着也
    // "没有"，但它仍然占父 Row 的一档 space，相册的宽高会因此抖一下。
    if (!this.isSentinel()) {
      if (this.isVideo()) {
        // 只有视频格参与播放位的中心 y 竞选，所以 onAreaChange 只挂在这一支上——
        // 无条件挂的时候实测每秒 2100-2300 次上报，而图片格从来不消费这个数据。
        Stack() {
          this.cellBody();
          this.selectionOverlay();
        }
        .width(this.cell.width).height(this.cell.height)
        .accessibilityText(str('mb_album_item_video', this.idx() + 1))
        .onVisibleAreaApproximateChange(
          { ratios: [0.0, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, 0.9],
            expectedUpdateInterval: 200 },
          (_visible: boolean, ratio: number): void => {
            if (ratio <= 0) {
              this.actions.onMediaGone(this.memberId(), this.idx());
            } else {
              this.actions.onMediaRatio(this.memberId(), this.idx(), ratio,
                this.hooks.centerYOf(this.idx()));
            }
          })
        .onAreaChange((_old: Area, area: Area): void => {
          this.hooks.onCenterY(this.idx(),
            (area.globalPosition.y as number) + (area.height as number) / 2);
        })
        .onClick((e: ClickEvent): void => { this.onCellTap(e); });
      } else {
        Stack() {
          this.cellBody();
          this.selectionOverlay();
        }
        .width(this.cell.width).height(this.cell.height)
        // 见单图分支：按被点的那一格的消息 id 绑定，相册里每格各自成对。
        .geometryTransition(`media_${this.cell.chatId}_${this.memberId()}`)
        .accessibilityText(this.failed() ? str('mb_photo_failed')
          : str('mb_album_item', this.idx() + 1))
        // **图片格不挂 onVisibleAreaApproximateChange。**
        // 这里原来挂着一个空回调——注释自己写着"图片格不上报"，可空回调照样把这个
        // 节点注册进全局可见区派发表，成本在注册不在回调。一行 6–9 格、窗口里几十
        // 行，全相册会话里就是两三百个白注册：09-03 的真机 trace 里
        // HandleVisibleAreaChangeEvent 的 nodeCount 峰值 134、稳态还在以 3.49
        // 节点/秒增长，而同一份录制里 379 行全是图片行。
        .onClick((e: ClickEvent): void => { this.onCellTap(e); });
      }
    }
  }
}
