import { UIContext } from '@kit.ArkUI';
import {
  shatterClose,
  shatterStageAdd,
  shatterStageBegin,
  shatterStageClose,
  shatterStageOpen,
  shatterStageRemove
} from 'libentry.so';
import { ShatterStageHost, ShatterStageLayerRequest } from '../../util/rowLeaveChannel';
import { logI, logW } from '../../util/log';

let nextStageAnchorId: number = 1;
const STAGE_MAX_BUFFER_PIXELS: number = 1048576;
const STAGE_IDLE_COOLDOWN_MS: number = 250;

interface ActiveStageLayer {
  handle: number;
  stageX: number;
  stageY: number;
  onFirstFrame: () => void;
  onFinish: () => void;
  onFail: (reason: string) => void;
  submitted: boolean;
}

// ChatPage 级共享删除粒子舞台：单 XComponent / 单 EGLSurface 批渲染 1~N 个正在消散的气泡。
// 空闲时 XComponent 完全卸载（零 GPU 表面常驻），批量删除时把 N 次 eglSwapBuffers 与
// N 次 RenderService 透明合成合并为 1 次，且粒子飘出 ListItem 边界不再被裁切。
@ObservedV2
export class ShatterStageController implements ShatterStageHost {
  readonly anchorId: string = `shatter-stage-anchor-${nextStageAnchorId++}`;
  @Trace mounted: boolean = false;
  @Trace stageRevision: number = 0;
  @Trace boxLeftVp: number = 0;
  @Trace boxTopVp: number = 0;
  @Trace boxWidthVp: number = 0;
  @Trace boxHeightVp: number = 0;
  @Trace fullViewport: boolean = true;

  private nativeStageId: number = 0;
  private openedW: number = 0;
  private openedH: number = 0;
  private boxLeft: number = 0;
  private boxTop: number = 0;
  private targetW: number = 0;
  private targetH: number = 0;
  private targetBufW: number = 0;
  private targetBufH: number = 0;
  private layers: Map<number, ActiveStageLayer> = new Map();
  private pending: ActiveStageLayer[] = [];
  private cooldownTimer: number = -1;
  private disposed: boolean = false;

  attachLayer(ui: object, req: ShatterStageLayerRequest): boolean {
    if (this.disposed) {
      return false;
    }
    const uiCtx: UIContext = ui as UIContext;
    let fullLayerX: number = 0;
    let fullLayerY: number = 0;
    let fullW: number = 0;
    let fullH: number = 0;
    try {
      const utils = uiCtx.getComponentUtils();
      const stageRect = utils.getRectangleById(this.anchorId);
      const nodeRect = utils.getRectangleById(req.nodeId);
      if (!(stageRect.size.width > 0) || !(stageRect.size.height > 0) ||
        !(nodeRect.size.width > 0) || !(nodeRect.size.height > 0)) {
        return false;
      }
      fullW = Math.max(1, Math.round(stageRect.size.width * req.snapScale));
      fullH = Math.max(1, Math.round(stageRect.size.height * req.snapScale));
      fullLayerX = (nodeRect.windowOffset.x - stageRect.windowOffset.x) * req.snapScale + req.offsetX;
      fullLayerY = (nodeRect.windowOffset.y - stageRect.windowOffset.y) * req.snapScale + req.offsetY;
    } catch (_e) {
      return false;
    }
    this.clearCooldown();

    // 单气泡模式：用紧致框只包住当前气泡及飘散余量，既避免全屏 100 万像素 RS 合成、
    // 又保持在 ChatPage 顶层舞台里不被 ListItem 裁切；批量删除模式直接铺满整个列表区。
    let wantLeft: number = 0;
    let wantTop: number = 0;
    let wantW: number = fullW;
    let wantH: number = fullH;
    let wantFull: boolean = true;
    if (req.singleMode && req.surfaceWidth > 0 && req.surfaceHeight > 0) {
      const bLeft: number = Math.max(0, Math.floor(fullLayerX));
      const bTop: number = Math.max(0, Math.floor(fullLayerY - req.top));
      const bRight: number = Math.min(fullW, Math.ceil(fullLayerX + req.surfaceWidth));
      const bBottom: number = Math.min(fullH, Math.ceil(fullLayerY - req.top + req.surfaceHeight));
      if (bRight > bLeft && bBottom > bTop) {
        wantLeft = bLeft;
        wantTop = bTop;
        wantW = bRight - bLeft;
        wantH = bBottom - bTop;
        wantFull = false;
      }
    }

    const fitsCurrent = (): boolean => {
      if (!this.mounted) { return false; }
      const reqMinX: number = fullLayerX;
      const reqMinY: number = fullLayerY - req.top;
      const reqMaxX: number = fullLayerX + req.surfaceWidth;
      const reqMaxY: number = fullLayerY - req.top + req.surfaceHeight;
      return reqMinX >= this.boxLeft - 1 && reqMinY >= this.boxTop - 1 &&
        reqMaxX <= this.boxLeft + this.targetW + 1 && reqMaxY <= this.boxTop + this.targetH + 1;
    };

    if (this.mounted && !fitsCurrent()) {
      if (this.layers.size > 0 || this.pending.length > 0) {
        // 已有另一处气泡正在紧致舞台内播完：不打断现有表面，当前层退回独立覆盖层。
        return false;
      }
      if (this.nativeStageId > 0) {
        shatterStageClose(this.nativeStageId);
        this.nativeStageId = 0;
      }
      this.mounted = false;
    }

    if (!this.mounted) {
      const area: number = wantW * wantH;
      const bufScale: number = area > STAGE_MAX_BUFFER_PIXELS
        ? Math.sqrt(STAGE_MAX_BUFFER_PIXELS / area) : 1.0;
      const invScale: number = 1.0 / req.snapScale;
      this.boxLeft = wantLeft;
      this.boxTop = wantTop;
      this.targetW = wantW;
      this.targetH = wantH;
      this.targetBufW = Math.max(1, Math.floor(wantW * bufScale));
      this.targetBufH = Math.max(1, Math.floor(wantH * bufScale));
      this.boxLeftVp = uiCtx.px2vp(wantLeft) * invScale;
      this.boxTopVp = uiCtx.px2vp(wantTop) * invScale;
      this.boxWidthVp = uiCtx.px2vp(wantW) * invScale;
      this.boxHeightVp = uiCtx.px2vp(wantH) * invScale;
      this.fullViewport = wantFull;
      this.stageRevision++;
      this.mounted = true;
    }

    const layer: ActiveStageLayer = {
      handle: req.handle,
      stageX: fullLayerX - this.boxLeft,
      stageY: fullLayerY - this.boxTop,
      onFirstFrame: req.onFirstFrame,
      onFinish: req.onFinish,
      onFail: req.onFail,
      submitted: false
    };
    this.layers.set(req.handle, layer);
    if (this.nativeStageId > 0 && this.openedW === this.targetW && this.openedH === this.targetH) {
      if (shatterStageAdd(this.nativeStageId, layer.handle, layer.stageX, layer.stageY)) {
        layer.submitted = true;
        return true;
      }
      this.layers.delete(req.handle);
      return false;
    }
    this.pending.push(layer);
    return true;
  }

  beginLayer(handle: number, durationMs: number): void {
    if (this.nativeStageId <= 0 || !this.layers.has(handle)) {
      return;
    }
    shatterStageBegin(this.nativeStageId, handle, durationMs);
  }

  detachLayer(handle: number): void {
    const layer = this.layers.get(handle);
    if (layer === undefined) {
      return;
    }
    this.layers.delete(handle);
    const pendingIdx = this.pending.indexOf(layer);
    if (pendingIdx >= 0) {
      this.pending.splice(pendingIdx, 1);
    }
    if (layer.submitted && this.nativeStageId > 0) {
      shatterStageRemove(this.nativeStageId, handle);
    } else {
      shatterClose(handle);
    }
    this.scheduleIdleTeardownIfEmpty();
  }

  onSurfaceLoaded(surfaceId: string, revision: number): void {
    if (this.disposed || !this.mounted || revision !== this.stageRevision) {
      return;
    }
    const stageId = shatterStageOpen(
      surfaceId, this.targetW, this.targetH, this.targetBufW, this.targetBufH,
      (layerHandle: number, event: number): void => {
        this.onNativeEvent(stageId, layerHandle, event);
      }
    );
    if (stageId <= 0) {
      logW('[ShatterStage] open failed');
      this.failAll('stage-open');
      return;
    }
    this.nativeStageId = stageId;
    this.openedW = this.targetW;
    this.openedH = this.targetH;
    logI(`[ShatterStage] opened id=${stageId} logical=${this.targetW}x${this.targetH} buf=${this.targetBufW}x${this.targetBufH} queued=${this.pending.length}`);
    const batch = this.pending.splice(0, this.pending.length);
    for (const layer of batch) {
      if (!this.layers.has(layer.handle)) {
        shatterClose(layer.handle);
        continue;
      }
      if (shatterStageAdd(stageId, layer.handle, layer.stageX, layer.stageY)) {
        layer.submitted = true;
      } else {
        this.layers.delete(layer.handle);
        shatterClose(layer.handle);
        layer.onFail('stage-add');
      }
    }
    this.scheduleIdleTeardownIfEmpty();
  }

  onSurfaceDestroyed(revision: number): void {
    if (revision !== this.stageRevision) {
      return;
    }
    if (this.nativeStageId > 0) {
      shatterStageClose(this.nativeStageId);
      this.nativeStageId = 0;
    }
    if (this.layers.size > 0) {
      this.failAll('stage-destroyed');
    }
  }

  reset(): void {
    this.clearCooldown();
    if (this.nativeStageId > 0) {
      shatterStageClose(this.nativeStageId);
      this.nativeStageId = 0;
    }
    const pending = this.pending.splice(0, this.pending.length);
    for (const layer of pending) {
      shatterClose(layer.handle);
    }
    this.layers.clear();
    this.mounted = false;
  }

  dispose(): void {
    this.disposed = true;
    this.reset();
  }

  private onNativeEvent(stageId: number, layerHandle: number, event: number): void {
    if (this.disposed || stageId !== this.nativeStageId) {
      return;
    }
    if (event === 0) {
      const layer = this.layers.get(layerHandle);
      if (layer !== undefined) {
        layer.onFirstFrame();
      }
      return;
    }
    if (event === 1) {
      const layer = this.layers.get(layerHandle);
      if (layer !== undefined) {
        this.layers.delete(layerHandle);
        layer.onFinish();
      }
      this.scheduleIdleTeardownIfEmpty();
      return;
    }
    if (layerHandle === 0) {
      this.failAll('stage-render');
      return;
    }
    const layer = this.layers.get(layerHandle);
    if (layer !== undefined) {
      this.layers.delete(layerHandle);
      layer.onFail('stage-layer');
    }
    this.scheduleIdleTeardownIfEmpty();
  }

  private failAll(reason: string): void {
    this.clearCooldown();
    if (this.nativeStageId > 0) {
      shatterStageClose(this.nativeStageId);
      this.nativeStageId = 0;
    }
    const pending = this.pending.splice(0, this.pending.length);
    for (const layer of pending) {
      if (!layer.submitted) {
        shatterClose(layer.handle);
      }
    }
    const active = Array.from(this.layers.values());
    this.layers.clear();
    this.mounted = false;
    for (const layer of active) {
      layer.onFail(reason);
    }
  }

  private clearCooldown(): void {
    if (this.cooldownTimer !== -1) {
      clearTimeout(this.cooldownTimer);
      this.cooldownTimer = -1;
    }
  }

  private scheduleIdleTeardownIfEmpty(): void {
    if (this.layers.size > 0 || this.pending.length > 0 || !this.mounted) {
      return;
    }
    this.clearCooldown();
    const expectedRevision: number = this.stageRevision;
    this.cooldownTimer = setTimeout((): void => {
      this.cooldownTimer = -1;
      if (this.layers.size === 0 && this.pending.length === 0 && this.stageRevision === expectedRevision) {
        if (this.nativeStageId > 0) {
          shatterStageClose(this.nativeStageId);
          this.nativeStageId = 0;
        }
        this.mounted = false;
      }
    }, STAGE_IDLE_COOLDOWN_MS);
  }
}

@ComponentV2
export struct ShatterStageOverlay {
  @Require @Param stage: ShatterStageController;
  private controller: XComponentController = new XComponentController();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.stage.mounted) {
        XComponent({
          id: `${this.stage.anchorId}_${this.stage.stageRevision}`,
          type: XComponentType.TEXTURE,
          controller: this.controller
        })
          .width(this.stage.fullViewport ? '100%' : this.stage.boxWidthVp)
          .height(this.stage.fullViewport ? '100%' : this.stage.boxHeightVp)
          .position(this.stage.fullViewport ? { x: 0, y: 0 } : { x: this.stage.boxLeftVp, y: this.stage.boxTopVp })
          .backgroundColor(Color.Transparent)
          .onLoad((): void => {
            this.stage.onSurfaceLoaded(this.controller.getXComponentSurfaceId(), this.stage.stageRevision);
          })
          .onDestroy((): void => {
            this.stage.onSurfaceDestroyed(this.stage.stageRevision);
          });
      }
    }
    .id(this.stage.anchorId)
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no');
  }
}
