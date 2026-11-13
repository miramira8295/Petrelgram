import { drawnRecycledLayouts } from '../chat/DrawnRecycledLayouts';
import { drawnMediaActivation } from '../../util/drawnMediaActivation';
import { drawnStageMetrics } from '../../util/drawnStageMetrics';
import { drawnPainterReserve } from '../chat/DrawnPainterReserve';
import { drawnHomeMessageSummary } from './DrawnHomeMessages';
import { KEY_DEBUG_DRAWN_HOME_WARMUP } from '../../util/debugDrawnRenderer';
import { drawnRouteMetrics } from '../../util/drawnRouteMetrics';
import { KEY_DEBUG_DRAWN_TRACE, KEY_DEBUG_DRAWN_ENABLED, KEY_DEBUG_DRAWN_TEXT, KEY_DEBUG_DRAWN_SINGLE, KEY_DEBUG_DRAWN_ALBUM, KEY_DEBUG_DRAWN_PLAIN, KEY_DEBUG_DRAWN_RICH } from '../../util/debugDrawnRenderer';
import { setBoolean } from '../../store/AppSettings';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_SURFACE } from '../../util/theme';

interface DrawnRendererToggleArgs { label: Resource; key: string; checked: boolean; }

@Component
export struct DrawnRendererDiagnostics {
  @State private routeSummary: string = (drawnRouteMetrics.summary() + drawnStageMetrics.summary() + drawnPainterReserve.summary() + drawnHomeMessageSummary() + drawnMediaActivation.summary() + drawnRecycledLayouts.summary());
  aboutToAppear(): void { this.routeSummary = (drawnRouteMetrics.summary() + drawnStageMetrics.summary() + drawnPainterReserve.summary() + drawnHomeMessageSummary() + drawnMediaActivation.summary() + drawnRecycledLayouts.summary()); }
  @StorageProp(KEY_DEBUG_DRAWN_TRACE) private stageTrace: boolean = false;
  @StorageProp(KEY_DEBUG_DRAWN_HOME_WARMUP) private homeWarmupOn: boolean = true;
  @StorageProp(KEY_DEBUG_DRAWN_ENABLED) private masterOn: boolean = true;
  @StorageProp(KEY_DEBUG_DRAWN_TEXT) private text: boolean = true;
  @StorageProp(KEY_DEBUG_DRAWN_SINGLE) private single: boolean = true;
  @StorageProp(KEY_DEBUG_DRAWN_ALBUM) private album: boolean = true;
  @StorageProp(KEY_DEBUG_DRAWN_PLAIN) private plain: boolean = true;
  @StorageProp(KEY_DEBUG_DRAWN_RICH) private rich: boolean = true;
  @Builder
  toggleRow($$: DrawnRendererToggleArgs) {
    Row() {
      Text($$.label).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: $$.checked })
        .accessibilityText($$.label).onChange((on: boolean): void => { setBoolean($$.key, on); });
    }.width('100%');
  }
  build() {
    Column({ space: 8 }) {
      Text($r('app.string.diag_drawn_title')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.diag_drawn_hint')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      Text($r('app.string.diag_drawn_routes_hint')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      Text(this.routeSummary).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      Button($r('app.string.diag_drawn_refresh')).onClick((): void => { this.routeSummary = (drawnRouteMetrics.summary() + drawnStageMetrics.summary() + drawnPainterReserve.summary() + drawnHomeMessageSummary() + drawnMediaActivation.summary() + drawnRecycledLayouts.summary()); });
      this.toggleRow({ label: $r('app.string.diag_drawn_enabled'), key: KEY_DEBUG_DRAWN_ENABLED, checked: this.masterOn });
      this.toggleRow({ label: $r('app.string.diag_drawn_text'), key: KEY_DEBUG_DRAWN_TEXT, checked: this.text });
      this.toggleRow({ label: $r('app.string.diag_drawn_single'), key: KEY_DEBUG_DRAWN_SINGLE, checked: this.single });
      this.toggleRow({ label: $r('app.string.diag_drawn_album'), key: KEY_DEBUG_DRAWN_ALBUM, checked: this.album });
      this.toggleRow({ label: $r('app.string.diag_drawn_plain'), key: KEY_DEBUG_DRAWN_PLAIN, checked: this.plain });
      this.toggleRow({ label: $r('app.string.diag_drawn_rich'), key: KEY_DEBUG_DRAWN_RICH, checked: this.rich });
      this.toggleRow({ label: $r('app.string.diag_drawn_trace'), key: KEY_DEBUG_DRAWN_TRACE, checked: this.stageTrace });
      this.toggleRow({ label: $r('app.string.diag_drawn_home_warmup'), key: KEY_DEBUG_DRAWN_HOME_WARMUP, checked: this.homeWarmupOn });
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(COLOR_SURFACE).borderRadius(16);
  }
}
