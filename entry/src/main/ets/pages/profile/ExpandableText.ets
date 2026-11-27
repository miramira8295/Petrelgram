import { MeasureText } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { TdObject } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY } from '../../util/theme';
import { linkifyRuns } from '../../util/linkify';
import { RichRun } from '../../util/richText';
import { openTelegramLink } from '../../util/openTelegramLink';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

const MAX_LINES: number = 4;
const FONT_SIZE: number = 15;

// Long text (bio / group description) clamped to 4 lines with a 展开 control
// at the bottom-right; expands/collapses with an animated height change.
@Component
export struct ExpandableText {
  @Prop content: string = '';
  entities: TdObject[] = []; // TDLib formattedText entities (empty → regex linkify)
  @State expanded: boolean = false;
  @State needsExpand: boolean = false;
  private measuredW: number = 0;

  // Compare the text's natural height at the available width against 4 lines.
  private checkOverflow(): void {
    if (this.measuredW <= 0 || this.content === '') {
      return;
    }
    const full = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: this.content,
      fontSize: `${FONT_SIZE}vp`,
      constraintWidth: `${this.measuredW}vp`
    });
    const oneLine = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: '简', // i18n-exempt: measurement sample glyph, not shown
      fontSize: `${FONT_SIZE}vp`
    });
    const fullH = full.height as number;
    const lineH = oneLine.height as number;
    this.needsExpand = lineH > 0 && fullH > lineH * (MAX_LINES + 0.5);
  }

  build() {
    // 展开/收起独立排在正文下方且透明底，不再叠一块不透明 surface 色块在正文右下角，
    // 确保半透明玻璃卡片与纯色卡片下材质完全统一，也不遮挡末行文字。
    Column({ space: 4 }) {
      // Spans instead of a plain string so links/@mentions are tappable.
      Text() {
        ForEach(linkifyRuns(this.content, this.entities), (r: RichRun) => {
          Span(r.text)
            .fontColor(r.link ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY)
            .fontWeight(r.bold ? FontWeight.Bold : FontWeight.Normal)
            .onClick((): void => {
              if (r.link && r.url !== '') {
                openTelegramLink(this.getUIContext().getHostContext() as common.UIAbilityContext, r.url);
              }
            });
        }, (r: RichRun, i: number) => `${i}_${r.text}`);
      }
      .fontSize(FONT_SIZE)
      .maxLines(this.expanded ? 100000 : MAX_LINES)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .copyOption(CopyOptions.LocalDevice)
      .width('100%')
      .onAreaChange((_old: Area, area: Area) => {
        if (this.measuredW === 0) {
          this.measuredW = area.width as number;
          this.checkOverflow();
        }
      });
      if (this.needsExpand) {
        Row() {
          Text(this.expanded ? $r('app.string.et_collapse') : $r('app.string.et_expand'))
            .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
            .backgroundColor(Color.Transparent)
            .padding({ top: 2, bottom: 2 })
            .onClick(() => {
              this.getUIContext().animateTo({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 250), curve: Curve.EaseInOut
              }, () => {
                this.expanded = !this.expanded;
              });
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.End);
      }
    }
    .width('100%');
  }
}
