import { getConnectionState, getTdClient } from '../../tdkit/Globals';
import { TdObject } from '../../tdkit/TdTypes';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { INITIAL_HINT_DELAY_MS, initialHintLabelKey } from '../../util/initialLoadingHint';
import { BUBBLE_AVATAR_GAP_VP, BUBBLE_AVATAR_GUTTER_VP, BUBBLE_ROW_SIDE_VP } from '../../util/mediaBox';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { bubbleGlassBlurStyle, bubbleGlassFill } from '../../util/surfaceGlass';
import { str } from '../../util/strings';

interface SkeletonBubbleSpec {
  id: string;
  isOut: boolean;
  widthRatio: number;
  lineRatios: number[];
  showAvatar: boolean;
  showSender: boolean;
  senderWidth: number;
  hasTail: boolean;
  hasQuote: boolean;
  showDateChipBefore: boolean;
  waveGroup: number;
}

const CHAT_SKELETON_SPECS: SkeletonBubbleSpec[] = [
  {
    id: 'sk_0',
    isOut: false,
    widthRatio: 0.56,
    lineRatios: [0.88, 0.54],
    showAvatar: false,
    showSender: true,
    senderWidth: 84,
    hasTail: false,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 0
  },
  {
    id: 'sk_1',
    isOut: false,
    widthRatio: 0.68,
    lineRatios: [0.94, 0.82, 0.46],
    showAvatar: true,
    showSender: false,
    senderWidth: 0,
    hasTail: true,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 1
  },
  {
    id: 'sk_2',
    isOut: true,
    widthRatio: 0.46,
    lineRatios: [0.76],
    showAvatar: false,
    showSender: false,
    senderWidth: 0,
    hasTail: true,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 2
  },
  {
    id: 'sk_3',
    isOut: false,
    widthRatio: 0.64,
    lineRatios: [0.90, 0.58],
    showAvatar: true,
    showSender: true,
    senderWidth: 96,
    hasTail: true,
    hasQuote: true,
    showDateChipBefore: true,
    waveGroup: 0
  },
  {
    id: 'sk_4',
    isOut: true,
    widthRatio: 0.58,
    lineRatios: [0.92, 0.50],
    showAvatar: false,
    showSender: false,
    senderWidth: 0,
    hasTail: false,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 1
  },
  {
    id: 'sk_5',
    isOut: true,
    widthRatio: 0.38,
    lineRatios: [0.68],
    showAvatar: false,
    showSender: false,
    senderWidth: 0,
    hasTail: true,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 2
  },
  {
    id: 'sk_6',
    isOut: false,
    widthRatio: 0.62,
    lineRatios: [0.92, 0.62],
    showAvatar: true,
    showSender: true,
    senderWidth: 76,
    hasTail: true,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 0
  },
  {
    id: 'sk_7',
    isOut: true,
    widthRatio: 0.52,
    lineRatios: [0.86, 0.44],
    showAvatar: false,
    showSender: false,
    senderWidth: 0,
    hasTail: true,
    hasQuote: false,
    showDateChipBefore: false,
    waveGroup: 1
  }
];

const PULSE_INTERVAL_MS: number = 640;
const STAGED_REVEAL_DELAY_MS: number = 90;

// 会话首屏加载时的 Telegram 风格气泡骨架屏占位（#219-10）。
// 底部对齐模拟真实消息流（区分私聊、群聊/话题头像列、频道宽卡片），带柔和波浪呼吸动画，
// 真实消息准备就绪后平滑淡出交接。
@ComponentV2
export struct InitialLoadingHint {
  @Param immediate: boolean = true;
  @Param isGroup: boolean = false;
  @Param isChannel: boolean = false;
  @Param screenW: number = 360;
  @Param topInset: number = 56;
  @Param bottomInset: number = 56;
  @Param materialEpoch: number = 0;

  @Local private bubbleVisible: boolean = false;
  @Local private statusHintShown: boolean = false;
  @Local private waveStep: number = 0;
  @Local private connectionState: string = '';

  private stageTimer: number = -1;
  private statusTimer: number = -1;
  private pulseTimer: number = -1;
  private unsubConn: (() => void) | null = null;

  @Monitor('immediate')
  onImmediateChanged(): void {
    if (this.immediate && !this.bubbleVisible) {
      if (this.stageTimer !== -1) {
        clearTimeout(this.stageTimer);
        this.stageTimer = -1;
      }
      this.bubbleVisible = true;
      this.startPulse();
    }
  }

  aboutToAppear(): void {
    this.connectionState = getConnectionState();
    this.unsubConn = getTdClient().onUpdate('updateConnectionState', (u: TdObject): void => {
      const st = u['state'] as TdObject | undefined;
      this.connectionState = st !== undefined ? ((st['@type'] as string | undefined) ?? '') : '';
    });
    if (this.immediate) {
      this.bubbleVisible = true;
      this.startPulse();
    } else {
      this.stageTimer = setTimeout((): void => {
        this.stageTimer = -1;
        this.bubbleVisible = true;
        this.startPulse();
      }, STAGED_REVEAL_DELAY_MS);
    }
    this.statusTimer = setTimeout((): void => {
      this.statusTimer = -1;
      this.statusHintShown = true;
    }, INITIAL_HINT_DELAY_MS);
  }

  aboutToDisappear(): void {
    if (this.stageTimer !== -1) {
      clearTimeout(this.stageTimer);
      this.stageTimer = -1;
    }
    if (this.statusTimer !== -1) {
      clearTimeout(this.statusTimer);
      this.statusTimer = -1;
    }
    this.stopPulse();
    if (this.unsubConn !== null) {
      this.unsubConn();
      this.unsubConn = null;
    }
  }

  private startPulse(): void {
    if (this.pulseTimer !== -1) {
      return;
    }
    const dur: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, PULSE_INTERVAL_MS);
    if (dur <= 0) {
      return;
    }
    this.pulseTimer = setInterval((): void => {
      this.waveStep = (this.waveStep + 1) % 3;
    }, PULSE_INTERVAL_MS);
  }

  private stopPulse(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
  }

  private effectiveIsOut(spec: SkeletonBubbleSpec): boolean {
    return this.isChannel ? false : spec.isOut;
  }

  private showGroupAvatarColumn(): boolean {
    return this.isGroup && !this.isChannel;
  }

  private bubbleWidthVp(spec: SkeletonBubbleSpec): number {
    const availW: number = Math.max(240, this.screenW - BUBBLE_ROW_SIDE_VP * 2 -
      (this.showGroupAvatarColumn() ? BUBBLE_AVATAR_GUTTER_VP : 0));
    const ratio: number = this.isChannel ? Math.min(0.84, spec.widthRatio + 0.14) : spec.widthRatio;
    return Math.round(availW * ratio);
  }

  private rowOpacity(waveGroup: number): number {
    const delta: number = (this.waveStep - waveGroup + 3) % 3;
    if (delta === 0) {
      return 0.96;
    }
    if (delta === 1) {
      return 0.72;
    }
    return 0.52;
  }

  private bubbleRadius(spec: SkeletonBubbleSpec): BorderRadiuses {
    const isOut: boolean = this.effectiveIsOut(spec);
    if (!spec.hasTail) {
      return { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 };
    }
    if (isOut) {
      return { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 5 };
    }
    return { topLeft: 18, topRight: 18, bottomLeft: 5, bottomRight: 18 };
  }

  @Builder
  private dateChipSkeleton() {
    Row() {
      Row()
        .width(56)
        .height(9)
        .borderRadius(4.5)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.22);
    }
    .height(26)
    .padding({ left: 12, right: 12 })
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .backdropBlur(this.materialEpoch >= 0 ? plainBackdropBlur('bar') : 0)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(13)
    .margin({ top: 4, bottom: 4 });
  }

  @Builder
  private bubbleCard(spec: SkeletonBubbleSpec) {
    Column({ space: 7 }) {
      if ((this.showGroupAvatarColumn() || this.isChannel) && spec.showSender && !this.effectiveIsOut(spec)) {
        Row()
          .width(spec.senderWidth)
          .height(10)
          .borderRadius(5)
          .backgroundColor(COLOR_PRIMARY)
          .opacity(0.24);
      }

      if (spec.hasQuote) {
        Row({ space: 8 }) {
          Row()
            .width(2.5)
            .height(26)
            .borderRadius(1.25)
            .backgroundColor(COLOR_PRIMARY)
            .opacity(0.45);
          Column({ space: 5 }) {
            Row()
              .width(64)
              .height(8)
              .borderRadius(4)
              .backgroundColor(COLOR_PRIMARY)
              .opacity(0.24);
            Row()
              .width(Math.max(80, Math.round((this.bubbleWidthVp(spec) - 36) * 0.65)))
              .height(8)
              .borderRadius(4)
              .backgroundColor(COLOR_TEXT_SECONDARY)
              .opacity(0.18);
          }
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .padding({ left: 7, right: 8, top: 5, bottom: 5 })
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(7);
      }

      ForEach(spec.lineRatios, (ratio: number, idx: number) => {
        if (idx === spec.lineRatios.length - 1) {
          Row({ space: 8 }) {
            Row()
              .width(Math.max(48, Math.round((this.bubbleWidthVp(spec) - 68) * ratio)))
              .height(10)
              .borderRadius(5)
              .backgroundColor(COLOR_TEXT_SECONDARY)
              .opacity(this.effectiveIsOut(spec) ? 0.22 : 0.17);
            Blank();
            Row()
              .width(28)
              .height(7)
              .borderRadius(3.5)
              .backgroundColor(COLOR_TEXT_SECONDARY)
              .opacity(0.13)
              .margin({ top: 3 });
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom);
        } else {
          Row()
            .width(Math.max(64, Math.round((this.bubbleWidthVp(spec) - 24) * ratio)))
            .height(10)
            .borderRadius(5)
            .backgroundColor(COLOR_TEXT_SECONDARY)
            .opacity(this.effectiveIsOut(spec) ? 0.22 : 0.17);
        }
      }, (_ratio: number, idx: number): string => `${spec.id}_line_${idx}`);
    }
    .width(this.bubbleWidthVp(spec))
    .padding({ left: 12, right: 11, top: 9, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.materialEpoch >= 0
      ? bubbleGlassFill(this.effectiveIsOut(spec) ? COLOR_BUBBLE_OUT : COLOR_BUBBLE_IN)
      : (this.effectiveIsOut(spec) ? COLOR_BUBBLE_OUT : COLOR_BUBBLE_IN))
    .backgroundBlurStyle(bubbleGlassBlurStyle())
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(this.bubbleRadius(spec));
  }

  @Builder
  private skeletonRow(spec: SkeletonBubbleSpec) {
    Column() {
      if (spec.showDateChipBefore) {
        Row() {
          this.dateChipSkeleton();
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);
      }

      Row() {
        if (!this.effectiveIsOut(spec) && this.showGroupAvatarColumn()) {
          if (spec.showAvatar) {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 38, height: 38 })
                .fill(bubbleGlassFill(COLOR_BUBBLE_IN));
              Circle({ width: 38, height: 38 })
                .fill(COLOR_TEXT_SECONDARY)
                .opacity(0.10);
            }
            .width(38)
            .height(38)
            .margin({ right: BUBBLE_AVATAR_GAP_VP });
          } else {
            Row().width(BUBBLE_AVATAR_GUTTER_VP).height(1);
          }
        }

        this.bubbleCard(spec);
      }
      .width('100%')
      .justifyContent(this.effectiveIsOut(spec) ? FlexAlign.End : FlexAlign.Start)
      .alignItems(VerticalAlign.Bottom);
    }
    .width('100%')
    .opacity(this.rowOpacity(spec.waveGroup))
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, PULSE_INTERVAL_MS),
      curve: Curve.EaseInOut
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.bubbleVisible) {
        Column({ space: 6 }) {
          ForEach(CHAT_SKELETON_SPECS, (spec: SkeletonBubbleSpec) => {
            this.skeletonRow(spec);
          }, (spec: SkeletonBubbleSpec): string => spec.id);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({
          left: BUBBLE_ROW_SIDE_VP,
          right: BUBBLE_ROW_SIDE_VP,
          top: Math.max(56, this.topInset) + 8,
          bottom: Math.max(56, this.bottomInset) + 10
        })
        .clip(true)
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
          curve: Curve.EaseOut
        }));
      }

      if (this.statusHintShown && initialHintLabelKey(this.connectionState) !== '') {
        Row() {
          Row({ space: 6 }) {
            Text(str(initialHintLabelKey(this.connectionState)))
              .fontSize(12.5)
              .fontColor(COLOR_TEXT_PRIMARY)
              .fontWeight(FontWeight.Medium);
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor(plainGlassFill($r('app.color.surface')))
          .backdropBlur(this.materialEpoch >= 0 ? plainBackdropBlur('bar') : 0)
          .border({ width: 0.5, color: $r('app.color.divider') })
          .borderRadius(15);
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: Math.max(56, this.topInset) + 8 });
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None);
  }
}
