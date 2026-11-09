import { common } from '@kit.AbilityKit';
import { saveMediaToGallery } from '../../util/mediaSaver';

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;

// 头像点击放大：全屏黑底查看器，支持缩放、拖动、下滑关闭和保存到相册。
// 独立于聊天页的媒体查看器 —— 那个和消息列表/相册强耦合，头像只需要
// 单张静态图，复用它会把整套消息态一起拖进资料页。
@Component
export struct AvatarViewer {
  @Prop imagePath: string;
  onClose: () => void = (): void => {};
  // 全屏浮层要自己避让状态栏，否则关闭按钮会被压在状态栏下点不到。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // 打开/关闭动画的缩放中心，取头像被点击时的屏幕坐标。不传就退化成从
  // 屏幕中心放大，观感上仍然连贯。
  @Prop originX: number = 0;
  @Prop originY: number = 0;
  @State private zoom: number = MIN_SCALE;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private saving: boolean = false;
  // 手势起始基准：pinch/pan 的增量都相对手势开始时的值，避免累积漂移。
  private baseScale: number = MIN_SCALE;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;

  private clampScale(value: number): number {
    return Math.min(MAX_SCALE, Math.max(MIN_SCALE, value));
  }

  private resetTransform(): void {
    this.zoom = MIN_SCALE;
    this.offsetX = 0;
    this.offsetY = 0;
  }

  private imageSource(): string {
    return this.imagePath.startsWith('/') ? `file://${this.imagePath}` : this.imagePath;
  }

  private async saveImage(): Promise<void> {
    if (this.saving || this.imagePath === '') {
      return;
    }
    this.saving = true;
    try {
      // 资料页传入的是已下载头像的本地路径，沿用媒体查看器的系统相册确认流程。
      await saveMediaToGallery(getContext(this) as common.UIAbilityContext, this.imagePath, false);
    } finally {
      this.saving = false;
    }
  }

  // 未传点击坐标时不指定中心，ArkUI 会退回元素中心——比固定成左上角(0,0)
  // 自然得多（下载列表预览就是这种没有明确来源点的场景）。
  private openTransition(): TransitionEffect {
    const scaled: ScaleOptions = this.originX > 0 || this.originY > 0
      ? { x: 0.25, y: 0.25, centerX: this.originX, centerY: this.originY }
      : { x: 0.25, y: 0.25 };
    return TransitionEffect.scale(scaled)
      .combine(TransitionEffect.OPACITY)
      .animation({ duration: 300, curve: Curve.Friction });
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(Color.Black)
        // 未放大时下滑关闭；放大后该手势让位给拖动。
        // 淡出交给根节点的 transition，这里不再单独改透明度，否则黑底会先
        // 于图片瞬间消失。
      Image(this.imageSource()).draggable(false)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .scale({ x: this.zoom, y: this.zoom })
        .translate({ x: this.offsetX, y: this.offsetY })
        .animation({ duration: 160, curve: Curve.EaseOut })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart((): void => {
                this.baseScale = this.zoom;
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.zoom = this.clampScale(this.baseScale * event.scale);
              })
              .onActionEnd((): void => {
                if (this.zoom <= MIN_SCALE + 0.01) {
                  this.resetTransform();
                }
              }),
            PanGesture({ fingers: 1 })
              .onActionStart((): void => {
                this.baseOffsetX = this.offsetX;
                this.baseOffsetY = this.offsetY;
              })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.zoom > MIN_SCALE + 0.01) {
                  this.offsetX = this.baseOffsetX + event.offsetX;
                  this.offsetY = this.baseOffsetY + event.offsetY;
                  return;
                }
                // 原始比例下只跟随竖直位移，作为下滑关闭的视觉反馈。
                this.offsetY = this.baseOffsetY + Math.max(0, event.offsetY);
              })
              .onActionEnd((): void => {
                if (this.zoom <= MIN_SCALE + 0.01 && this.offsetY > 120) {
                  this.onClose();
                  return;
                }
                if (this.zoom <= MIN_SCALE + 0.01) {
                  this.resetTransform();
                }
              })
          )
        );
      // 双击缩放：与单击关闭互斥，单击需等双击判定窗口过去。
      Column()
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction((): void => {
                if (this.zoom > MIN_SCALE + 0.01) {
                  this.resetTransform();
                } else {
                  this.zoom = 2.5;
                }
              }),
            TapGesture({ count: 1 })
              .onAction((): void => {
                if (this.zoom > MIN_SCALE + 0.01) {
                  this.resetTransform();
                  return;
                }
                this.onClose();
              })
          )
        );
      Row({ space: 12 }) {
        Button(this.saving ? $r('app.string.saving') : $r('app.string.ms_save_to_gallery'))
          .id('avatarViewerSave')
          .height(40)
          .padding({ left: 16, right: 16 })
          .fontSize(14).fontColor(Color.White)
          .backgroundColor('#4D000000')
          .enabled(!this.saving && this.imagePath !== '')
          .onClick((): void => { this.saveImage(); });
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(22).fontColor([Color.White]);
        }
        .width(40).height(40)
        .backgroundColor('#4D000000')
        .accessibilityText($r('app.string.close'))
        .onClick((): void => this.onClose());
      }
      .margin({ top: this.topSafe + 12, right: 12 });
    }
    .width('100%').height('100%')
    // 和聊天页媒体查看器同一套过渡：从点击处放大 + 淡入，关闭时原路缩回。
    // 时长与曲线保持一致，两个入口的观感才统一。
    .transition(this.openTransition());
  }
}
