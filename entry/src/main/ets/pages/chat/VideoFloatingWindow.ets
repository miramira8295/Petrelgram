import { common } from '@kit.AbilityKit';
import { ComponentContent, OverlayManager, UIContext } from '@kit.ArkUI';
import { VideoPlayerHost } from './VideoPlayerHost';
import { setMediaViewerOrientation } from './LiveViewerUi';
import {
  closeFloatingVideo, registerFloatingVideo, handoffVideoPlayback,
  VideoPlaybackControls, VideoPlaybackSnapshot
} from '../../util/floatingVideoRuntime';
import { clampFloatingTranslation } from '../../util/floatingDrag';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

export interface FloatingVideoSource {
  fileId: number;
  fileSize: number;
  mimeType: string;
  videoWidth: number;
  videoHeight: number;
  localPath: string;
  posterPath: string;
  title: string;
}

class FloatingVideoArgs {
  controller: VideoFloatingWindowController;
  source: FloatingVideoSource;
  snapshot: VideoPlaybackSnapshot;
  owner: number;
  constructor(controller: VideoFloatingWindowController, source: FloatingVideoSource, snapshot: VideoPlaybackSnapshot, owner: number) {
    this.controller = controller;
    this.source = source;
    this.snapshot = snapshot;
    this.owner = owner;
  }
}

export class VideoFloatingWindowController {
  private manager: OverlayManager | null = null;
  private generation: number = 0;
  private context: UIContext | null = null;
  private content: ComponentContent<FloatingVideoArgs> | null = null;
  private unregister: (() => void) | null = null;
  private controls: VideoPlaybackControls | null = null;
  private collapse: () => boolean = (): boolean => false;
  private activated: boolean = false;
  private onActivate: (() => void) | null = null;

  show(context: UIContext, source: FloatingVideoSource, playback: VideoPlaybackControls): boolean {
    try {
      return handoffVideoPlayback(playback, (snapshot: VideoPlaybackSnapshot): boolean => {
        closeFloatingVideo();
        this.context = context;
        this.manager = context.getOverlayManager();
        this.content = new ComponentContent<FloatingVideoArgs>(context, wrapBuilder(buildFloatingVideo),
          new FloatingVideoArgs(this, source, snapshot, ++this.generation));
        this.manager.addComponentContent(this.content);
        return true;
      }, (): void => {
        this.activated = true;
        this.onActivate?.();
        this.unregister = registerFloatingVideo((): void => { this.close(); }, (): boolean => this.collapse());
      });
    } catch (error) {
      logE(`VideoFloating.show failed: ${error}`);
      this.close();
      return false;
    }
  }

  isCurrent(owner: number): boolean { return owner === this.generation; }

  bindActivation(owner: number, callback: () => void): void {
    if (!this.isCurrent(owner)) { return; }
    this.onActivate = callback;
    if (this.activated) { callback(); }
  }

  bindControls(owner: number, controls: VideoPlaybackControls | null): void {
    if (this.isCurrent(owner)) { this.controls = controls; }
  }
  bindCollapse(owner: number, collapse: () => boolean): void {
    if (this.isCurrent(owner)) { this.collapse = collapse; }
  }

  close(): void {
    this.activated = false;
    this.onActivate = null;
    this.unregister?.();
    this.unregister = null;
    this.controls?.stop();
    this.controls = null;
    this.generation++;
    if (this.context !== null) {
      setMediaViewerOrientation(this.context.getHostContext() as common.UIAbilityContext, false);
      this.context = null;
    }
    this.collapse = (): boolean => false;
    const content = this.content;
    this.content = null;
    if (content !== null) {
      try { this.manager?.removeComponentContent(content); }
      catch (error) { logE(`VideoFloating.remove failed: ${error}`); }
      content.dispose();
    }
    this.manager = null;
  }
}

export const floatingVideoWindow: VideoFloatingWindowController = new VideoFloatingWindowController();

@Component
struct FloatingVideoOverlay {
  controller: VideoFloatingWindowController = floatingVideoWindow;
  source: FloatingVideoSource = {
    fileId: 0, fileSize: 0, mimeType: '', videoWidth: 0, videoHeight: 0,
    localPath: '', posterPath: '', title: ''
  };
  snapshot: VideoPlaybackSnapshot = { positionMs: 0, speedIndex: 1, playing: false };
  owner: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State expanded: boolean = false;
  @State landscape: boolean = false;
  @State playing: boolean = false;
  @State ready: boolean = false;
  @State large: boolean = false;
  @State rootWidth: number = 400;
  @State rootHeight: number = 800;
  @State x: number = 12;
  @State y: number = 100;
  private placed: boolean = false;
  private startX: number = 0;
  private startY: number = 0;
  private controls: VideoPlaybackControls | null = null;

  aboutToAppear(): void {
    this.controller.bindActivation(this.owner, (): void => { this.ready = true; });
    this.controller.bindCollapse(this.owner, (): boolean => {
      if (!this.expanded) { return false; }
      this.setExpanded(false);
      return true;
    });
  }

  aboutToDisappear(): void {
    if (this.landscape && this.controller.isCurrent(this.owner)) { this.setLandscape(false); }
    this.controller.bindCollapse(this.owner, (): boolean => false);
  }

  private setLandscape(value: boolean): void {
    this.landscape = value;
    setMediaViewerOrientation(this.getUIContext().getHostContext() as common.UIAbilityContext, value);
  }

  private setExpanded(value: boolean): void {
    if (!value && this.landscape) { this.setLandscape(false); }
    this.expanded = value;
    this.clampPosition();
  }

  private panelWidth(): number {
    return Math.max(120, Math.min(this.large ? 360 : 240, this.rootWidth - 24));
  }

  private panelHeight(): number {
    const ratio = this.source.videoWidth > 0 && this.source.videoHeight > 0
      ? this.source.videoWidth / this.source.videoHeight : 16 / 9;
    return Math.min(Math.max(120, this.panelWidth() / ratio) + 40,
      Math.max(120, this.rootHeight - this.topSafe - this.bottomSafe - 24));
  }

  private clampPosition(): void {
    const point = clampFloatingTranslation(this.x, this.y - this.topSafe,
      { x: 0, y: 0, width: this.panelWidth(), height: this.panelHeight() },
      { width: this.rootWidth, height: this.rootHeight - this.topSafe - this.bottomSafe, margin: 8 });
    this.x = point.x;
    this.y = point.y + this.topSafe;
  }

  @Builder
  action(icon: Resource, label: string, callback: () => void) {
    Button() {
      SymbolGlyph(icon).fontSize(18).fontColor([Color.White]);
    }.width(36).height(36).backgroundColor(Color.Transparent)
      .accessibilityText(label).onClick(callback);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          if (this.expanded) {
            Text(this.source.title).fontSize(14).fontColor(Color.White).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          } else {
            SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(16).fontColor([Color.White])
              .layoutWeight(1).height(36)
              .gesture(PanGesture()
                .onActionStart((): void => { this.startX = this.x; this.startY = this.y; })
                .onActionUpdate((event: GestureEvent): void => {
                  this.x = this.startX + event.offsetX;
                  this.y = this.startY + event.offsetY;
                  this.clampPosition();
                }));
          }
          this.action($r(this.playing ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'),
            str(this.playing ? 'vf_pause' : 'vf_play'), (): void => { this.controls?.toggle(); });
          if (!this.expanded) {
            this.action($r('sys.symbol.arrow_up_left_and_arrow_down_right'), str('vf_resize'), (): void => {
              this.large = !this.large;
              this.clampPosition();
            });
          }
          this.action($r(this.expanded ? 'sys.symbol.arrow_down_right_and_arrow_up_left' : 'sys.symbol.arrow_up_left_and_arrow_down_right'),
            str(this.expanded ? 'vf_minimize' : 'lv_enter_fullscreen'), (): void => { this.setExpanded(!this.expanded); });
          this.action($r('sys.symbol.xmark'), str('close'), (): void => { this.controller.close(); });
        }.height(40).width('100%').padding({ left: 8, right: 4 }).backgroundColor('#E6101820');
        Stack() {
          // Stable node across expand/resize: neither decoder nor stream restarts.
          if (this.ready) {
          VideoPlayerHost({
            fileId: this.source.fileId, fileSize: this.source.fileSize, mimeType: this.source.mimeType,
            videoWidth: this.source.videoWidth, videoHeight: this.source.videoHeight,
            localPath: this.source.localPath, posterPath: this.source.posterPath,
            startPositionMs: this.snapshot.positionMs, startSpeedIndex: this.snapshot.speedIndex,
            startPaused: !this.snapshot.playing, appOnly: true,
            showControls: this.expanded, compactMode: !this.expanded, landscape: this.landscape,
            onPlaybackControls: (controls: VideoPlaybackControls | null): void => {
              this.controls = controls;
              this.controller.bindControls(this.owner, controls);
            },
            onPlayStateChanged: (playing: boolean): void => { this.playing = playing; },
            onOrientationChange: (value: boolean): void => { this.setLandscape(value); }
          });
          }
          if (!this.expanded) {
            Row().width('100%').height('100%').backgroundColor(Color.Transparent)
              .onClick((): void => { this.setExpanded(true); })
              .gesture(PanGesture()
                .onActionStart((): void => { this.startX = this.x; this.startY = this.y; })
                .onActionUpdate((event: GestureEvent): void => {
                  this.x = this.startX + event.offsetX;
                  this.y = this.startY + event.offsetY;
                  this.clampPosition();
                }));
          }
        }.width('100%').layoutWeight(1);
      }
      .width(this.expanded ? this.rootWidth : this.panelWidth())
      .height(this.expanded ? Math.max(1, this.rootHeight - this.topSafe - this.bottomSafe) : this.panelHeight())
      .position({ x: this.expanded ? 0 : this.x, y: this.expanded ? this.topSafe : this.y })
      .backgroundColor(Color.Black).borderRadius(this.expanded ? 0 : 14).clip(true);
    }
    .width('100%').height('100%')
    .backgroundColor(this.expanded ? Color.Black : Color.Transparent)
    .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.Transparent)
    .onAreaChange((_old: Area, area: Area): void => {
      this.rootWidth = Number(area.width);
      this.rootHeight = Number(area.height);
      if (!this.placed) {
        this.placed = true;
        this.x = this.rootWidth - this.panelWidth() - 12;
        this.y = this.rootHeight - this.panelHeight() - this.bottomSafe - 82;
      }
      this.clampPosition();
    });
  }
}

@Builder
function buildFloatingVideo(args: FloatingVideoArgs) {
  Stack() {
    FloatingVideoOverlay({ controller: args.controller, source: args.source, snapshot: args.snapshot, owner: args.owner });
  }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent);
}
