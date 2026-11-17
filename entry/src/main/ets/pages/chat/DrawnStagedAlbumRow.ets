import { COLOR_TEXT_SECONDARY } from '../../util/theme';
import { DrawnRowLayoutEngine, takeDrawnWarmLayout } from './DrawnLayoutWarmCache';
import { takeDrawnRecycledLayout } from './DrawnRecycledLayouts';
import { UIContext } from '@kit.ArkUI';
import { drawnRowRetention } from '../../util/drawnRowRetention';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnMessageRow } from './DrawnMessageRow';
import { DrawnAlbumLayouts } from './DrawnAlbumLayout';
import { DrawnAlbumPublication, DrawnPreparedAlbum } from './DrawnPreparedAlbum';
import { DrawnBubbleStyle } from './DrawnBubblePlan';
import { DrawnRowWork } from '../../util/drawnRowAdmissionQueue';
import { drawnRowAdmission, enqueueDrawnRow } from '../../util/drawnRowAdmission';
import { drawnAlbumEligible } from '../../util/drawnAlbumPolicy';
import { drawnRowChromeReason } from '../../util/drawnRowChromePolicy';
import { DrawnRouteReason } from '../../util/drawnRouteMetrics';
import { DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { chatEnv } from '../../util/chatEnvMirror';
import { a11yRuntimeState } from '../../util/a11yState';
import { translationStatusFor } from '../../util/translationChannel';
import { viewCountLabelFor } from '../../util/viewCountChannel';
import { senderRoleFor, senderRoleKey } from '../../util/senderRoleChannel';
import { getTdClient } from '../../tdkit/Globals';
import { logW } from '../../util/log';

// Geometry stays synchronous on a cold miss: guessing caption/quote/reaction
// heights would move the scroll anchor. Heavy child construction and *new row
// inputs* are published by the process-wide frame gate. Prepared geometry is
// handed to the child, so publication does not prepare it for a second time.
@ComponentV2
export struct DrawnStagedAlbumRow {
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  @Local private suspended: boolean = false;
  private env = chatEnv;
  private a11y = a11yRuntimeState;
  private layouts: DrawnRowLayoutEngine | null = null;
  private prepared: DrawnPreparedAlbum | null = null;
  private preparedUi: UIContext | null = null;
  // One context per physical host/window lifetime. getUIContext() may return
  // a fresh JS wrapper; wrapper identity is not a layout change. Configuration
  // and density still invalidate via textMeasureEnvironment. Never global.
  private hostUi: UIContext | null = null;
  private rowContext(): UIContext {
    if (!this.hostUi) { this.hostUi = this.getUIContext(); }
    return this.hostUi;
  }
  private publication: DrawnAlbumPublication = new DrawnAlbumPublication();
  private owner: Object | undefined;
  private work: DrawnRowWork | null = null;
  private requested: DrawnPreparedAlbum | null = null;
  private generation: number = 0;
  private active: boolean = false;
  private warned: boolean = false;
  private visible: boolean = false;
  private recycledPrepared: DrawnPreparedAlbum | null = null;
  private dropRetained = (): void => {
    if (!this.active) {
      this.publication.packet = null;
      // V2 may already have prepared the next input before aboutToReuse claims
      // an expired ticket. Drop the old packet without discarding that new work.
      if (this.prepared === this.recycledPrepared) {
        this.suspended = true; this.prepared = null; this.preparedUi = null; this.layouts = null; this.owner = undefined; this.hostUi = null;
      }
      this.recycledPrepared = null;
    }
  };

  @Computed
  private get target(): DrawnPreparedAlbum | null {
    const traced = drawnStageMetrics.begin(DrawnStage.RowTarget);
    try { return this.resolveTarget(); } finally { drawnStageMetrics.end(traced); }
  }
  private resolveTarget(): DrawnPreparedAlbum | null {
    // The date is measured separately by the native header, outside plan.height.
    // Unread/keyboard heights still belong to the unsplit compatibility row.
    if (this.suspended) { return null; }
    const m = this.group.head;
    if (this.env.drawnAlbumStaging === false || this.env.drawnEnabled === false || this.env.drawnAlbum === false ||
      this.data.showUnreadDivider || m.inlineButtons.length > 0 ||
      !drawnAlbumEligible(this.group, this.data, this.env.bubbleMaterialOn, this.a11y.active)) { return null; }
    if (this.group.caption !== '' && (this.data.lightweightPlainText ? this.env.drawnPlain === false : this.env.drawnRich === false)) { return null; }
    const textEnvironment = `${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
    const role = m.senderTag || (this.data.isGroup && !m.isOutgoing && this.group.showSenderName
      ? senderRoleFor(senderRoleKey(this.data.chatId, m.senderId)) : '');
    const style: DrawnBubbleStyle = { translationStatus: translationStatusFor(m.id),
      replaceTranslation: this.env.translateReplaceOriginal, radius: this.env.bubbleRadius, fontSize: this.env.msgTextSize,
      environment: `${this.env.appearanceEpoch}:${textEnvironment}`, textEnvironment, role,
      views: viewCountLabelFor(this.data.chatId, m.id) };
    if (this.owner !== getTdClient()) {
      this.layouts = null; this.prepared = null; this.preparedUi = null; this.hostUi = null; this.owner = getTdClient();
    }
    const ui = this.rowContext();
    if (this.preparedUi === ui && this.prepared?.matches(this.group, this.data, style)) {
      drawnStageMetrics.markRoute('PG/row-target-hit'); return this.prepared;
    }
    drawnStageMetrics.markRoute(this.prepared === null ? 'PG/row-target-initial'
      : this.preparedUi !== ui ? 'PG/row-target-context'
      : this.prepared.group !== this.group ? 'PG/row-target-group'
      : this.prepared.data !== this.data ? 'PG/row-target-data' : 'PG/row-target-style');
    if (this.preparedUi === ui && this.prepared?.sameGeometry(this.group, this.data, style)) {
      drawnStageMetrics.markRoute('PG/row-geometry-reused');
      this.prepared = new DrawnPreparedAlbum(this.group, this.data, style, this.prepared.plan, this.layouts, ui);
      return this.prepared;
    }
    if (drawnRowChromeReason(this.group, this.data, role) !== DrawnRouteReason.Drawn) { return null; }
    const traced = drawnStageMetrics.begin(DrawnStage.RowGeometry);
    try {
      if (this.layouts === null) {
        this.layouts = takeDrawnRecycledLayout(this.data.chatId, m.rowId, 'album') ??
          takeDrawnWarmLayout(this.data.chatId, m.id, 'album') ?? new DrawnAlbumLayouts();
      }
      const plan = this.layouts.prepare(ui, this.group, this.data, style);
      if (plan === null) { return null; }
      this.preparedUi = ui;
      this.prepared = new DrawnPreparedAlbum(this.group, this.data, style, plan, this.layouts, ui);
      return this.prepared;
    } catch (error) {
      if (!this.warned) { this.warned = true; logW(`DrawnStagedAlbumRow: ${(error as Error).message}`); }
      return null;
    } finally { drawnStageMetrics.end(traced); }
  }

  @Computed
  private get hasPublished(): boolean { return this.publication.packet !== null; }
  @Computed
  private get pending(): boolean { return this.target !== null && this.publication.packet !== this.target; }
  private cancel(): void {
    this.generation++;
    if (this.work !== null) { drawnRowAdmission.cancel(this.work); this.work = null; }
    this.requested = null;
  }
  @Monitor('target', 'leaving')
  private request(): void {
    if (!this.active) { return; }
    const target = this.target;
    if (target === null) { this.cancel(); this.publication.packet = null; return; }
    if (this.publication.packet === target || this.requested === target) { return; }
    this.cancel();
    const old = this.publication.packet;
    // In-place edits/progress/selection are not entering heavy rows. Do not
    // delay interactions or hide a visible message when its metadata changes.
    if (this.leaving > 0 || (old !== null && old.data.chatId === target.data.chatId && old.group.head.rowId === target.group.head.rowId)) {
      drawnStageMetrics.markRoute('PG/row-publish-inline');
      this.publication.packet = target; return;
    }
    this.requested = target;
    const generation = this.generation;
    this.work = enqueueDrawnRow(this.rowContext(), (): void => {
      if (!this.active || generation !== this.generation || this.target !== target) { return; }
      this.work = null; this.requested = null; this.publication.packet = target;
    }, this.visible);
    if (this.work === null) {
      // Bounded overflow preserves content; explicitly counted instead of
      // pretending this exceptional synchronous path obeys the frame cap.
      drawnStageMetrics.markRoute('PG/row-admit-overflow');
      this.requested = null; this.publication.packet = target;
    }
  }
  aboutToAppear(): void { drawnRowRetention.take(this.dropRetained); this.suspended = false; this.active = true; this.publication.activate(); this.request(); }
  aboutToReuse(): void { drawnRowRetention.take(this.dropRetained); this.suspended = false; this.active = true; this.publication.activate(); this.request(); }
  aboutToRecycle(): void {
    this.active = false; this.publication.deactivate(); this.visible = false; this.cancel();
    this.recycledPrepared = this.prepared; drawnRowRetention.hold(this.dropRetained);
    // Preserve one packet per physical host, not per message in chat history.
    // Existing child lifecycle releases images/players. Retaining the branch
    // avoids tearing down all nodes merely to wait for the next publication.
  }
  aboutToDisappear(): void {
    this.active = false; this.publication.deactivate(); this.cancel(); drawnRowRetention.take(this.dropRetained);
    this.recycledPrepared = this.prepared; this.dropRetained();
  }

  private visibilityChanged(): (visible: boolean, ratio: number) => void {
    const chatId = this.data.chatId, rowId = this.group.head.rowId, generation = this.generation;
    return (_visible: boolean, ratio: number): void => {
      if (!this.active || generation !== this.generation || chatId !== this.data.chatId || rowId !== this.group.head.rowId) { return; }
      this.visible = ratio > 0;
      if (this.work !== null) { drawnRowAdmission.priority(this.work, this.visible); }
    };
  }

  @Builder
  stagedBody() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.hasPublished) {
        DrawnMessageRow({ kind: 'album', group: this.group,
          data: this.data, publication: this.publication,
          presentationActive: !this.pending, dateInHost: true, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.pending ? 0 : this.jumpFocus, leaving: this.leaving })
          // Keep the child instance, but exclude its old layout while the
          // exact-height placeholder owns this frame. Hidden still occupies.
          .visibility(this.pending ? Visibility.None : Visibility.Visible)
          .hitTestBehavior(this.pending ? HitTestMode.None : HitTestMode.Default);
      }
      if (this.pending) {
        // A short, static silhouette at the exact measured position. Actual
        // per-image progress/retry UI mounts unchanged when the row is admitted.
        Row().width(this.target!.plan.grid.width).height(this.target!.plan.grid.height)
          .backgroundColor('#247F8790').borderRadius(6)
          .position({ x: this.group.head.isOutgoing
            ? this.data.contentWidth - 4 - this.target!.plan.width + this.target!.plan.grid.x
            : 4 + this.target!.plan.grid.x,
            y: (this.group.showSenderName ? 3 : 1) + this.target!.plan.grid.y })
          .hitTestBehavior(HitTestMode.None);
      }
    }.width('100%').height(this.pending ? this.target!.height() : undefined)
    .clip(this.pending)
    .onVisibleAreaApproximateChange({ ratios: [0], expectedUpdateInterval: 16 }, this.visibilityChanged());
  }

  build() {
    if (this.suspended) {
      Row().height(0);
    } else if (this.target === null) {
      DrawnMessageRow({ kind: 'album', group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    } else {
      if (this.group.dateLabel !== '') {
        // Native text owns its actual font-scaled height. The staged body owns
        // only the bubble height; no onAreaChange/state write or guessed offset.
        Column() {
          Text(this.group.dateLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 }).margin({ top: 5, bottom: 3 });
          this.stagedBody();
        }.width('100%');
      } else {
        this.stagedBody();
      }
    }
  }
}
