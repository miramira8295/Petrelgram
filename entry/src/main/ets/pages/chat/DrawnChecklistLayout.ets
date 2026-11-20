import { UIContext } from '@kit.ArkUI';
import { ChecklistGeometry, ChecklistModel, ChecklistText } from '../../util/checklistModel';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { PollRichSource } from '../../util/pollRichSource';
import { DrawnRichSourceCache } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { TdObject } from '../../tdkit/TdTypes';

export interface DrawnChecklistTaskLayout {
  id: number;
  width: number;
  height: number;
  label: DrawnRichTextLayout;
  textX: number;
  textY: number;
  checkboxSize: number;
  checkboxY: number;
  checkboxHitWidth: number;
}
export interface DrawnChecklistLayout {
  width: number;
  height: number;
  title: DrawnRichTextLayout;
  rows: DrawnChecklistTaskLayout[];
  footerHeight: number;
  subtitle: DrawnTextLine;
  subtitleHeight: number;
}
const remembered: WeakMap<DrawnDocumentWidget, DrawnChecklistLayout> = new WeakMap<DrawnDocumentWidget, DrawnChecklistLayout>();
export function rememberChecklistLayout(widget: DrawnDocumentWidget, layout: DrawnChecklistLayout): void { remembered.set(widget, layout); }
export function checklistLayoutFor(widget: DrawnDocumentWidget): DrawnChecklistLayout | null { return remembered.get(widget) ?? null; }
const EMPTY_CHECKLIST_LAYOUT_ENTITIES: TdObject[] = [];

class ChecklistLabelLayouts {
  private sources: PollRichSource = new PollRichSource();
  private plain: DrawnRichSourceCache = new DrawnRichSourceCache();
  private layouts: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  prepare(ui: UIContext, label: ChecklistText, width: number, environment: string, title: boolean): DrawnRichTextLayout {
    const content = title && label.text === '' ? str('checklist_title') : label.text;
    let source = this.sources.prepare(content, content === label.text ? label.entities : EMPTY_CHECKLIST_LAYOUT_ENTITIES, title);
    // Future entity kinds may be unknown to this build. Keep all visible task
    // text and its checkbox instead of replacing the whole message renderer.
    if (source === null) { source = this.plain.prepare(content, EMPTY_CHECKLIST_LAYOUT_ENTITIES); }
    if (source === null) { throw new Error('invalid checklist label'); }
    return this.layouts.prepare(ui, { source, maxWidthVp: Math.max(1, width), minWidthVp: 0,
      fontSize: 16, foreground: COLOR_TEXT_PRIMARY, accent: COLOR_PRIMARY, environment, reserve: '' });
  }
}

// Text identities, not completion/permission/pending state, establish geometry.
// A warm retained source is O(1); a changed/reordered list is one O(N+E) pass.
export class DrawnChecklistLayouts {
  private title: ChecklistLabelLayouts = new ChecklistLabelLayouts();
  private labels: Map<number, ChecklistLabelLayouts> = new Map<number, ChecklistLabelLayouts>();
  private subtitle: DrawnTextLineCache = new DrawnTextLineCache();
  private footer: DrawnTextLineCache = new DrawnTextLineCache();
  private units: DrawnTextUnits = new DrawnTextUnits();
  private ui: UIContext | null = null;
  private environment: string = '';
  private geometry: ChecklistGeometry | null = null;
  private current: DrawnChecklistLayout | null = null;
  prepare(ui: UIContext, model: ChecklistModel, maxWidth: number, environment: string): DrawnChecklistLayout {
    const width = Math.max(1, Math.min(310, maxWidth));
    if (this.current !== null && this.current.width === width && this.ui === ui &&
      this.environment === environment && this.geometry === model.geometry) { return this.current; }
    const title = this.title.prepare(ui, model.geometry.title, width, environment, true);
    const rows: DrawnChecklistTaskLayout[] = [];
    const next: Map<number, ChecklistLabelLayouts> = new Map<number, ChecklistLabelLayouts>();
    let contentHeight = 0, changed = this.current?.rows.length !== model.geometry.tasks.length;
    const hitWidth = Math.min(36, width / 4, Math.max(0, width - 1)), textX = hitWidth;
    const checkboxSize = Math.max(0, Math.min(20, hitWidth - Math.min(4, hitWidth / 2)));
    let index = 0;
    for (const task of model.geometry.tasks) {
      const engine = this.labels.get(task.id) ?? new ChecklistLabelLayouts();
      next.set(task.id, engine);
      const rightPadding = Math.min(4, Math.max(0, width - textX - 1));
      const label = engine.prepare(ui, task.label, width - textX - rightPadding, environment, false);
      const height = Math.max(44, label.heightVp + 24), before = this.current?.rows[index];
      const row: DrawnChecklistTaskLayout = before !== undefined && before.id === task.id && before.label === label &&
        before.height === height && before.textX === textX && before.width === width ? before : { id: task.id, width, label, height, textX, textY: 12,
        checkboxSize, checkboxY: 12, checkboxHitWidth: hitWidth };
      if (before !== row) { changed = true; }
      rows.push(row); contentHeight += height; index++;
    }
    this.labels = next;
    const units = this.units.prepare(ui, environment);
    const subtitle = this.subtitle.prepare(str('checklist_type'), width * units.density,
      units.fp2px(12), drawnColor(COLOR_TEXT_SECONDARY), environment);
    const subtitleHeight = subtitle.heightPx / units.density + 12;
    const footerHeight = Math.max(30, this.footer.prepare(str('checklist_progress', '0', '0'),
      Math.max(1, width) * units.density, units.fp2px(10.5), drawnColor(COLOR_TEXT_SECONDARY), environment).heightPx / units.density + 10);
    const before = this.current;
    if (before !== null && before.width === width && before.title === title && !changed && before.footerHeight === footerHeight && before.subtitle === subtitle) {
      this.geometry = model.geometry; this.ui = ui; this.environment = environment; return before;
    }
    const height = title.heightVp + 4 + subtitleHeight + contentHeight + footerHeight;
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid checklist prelayout'); }
    this.geometry = model.geometry; this.ui = ui; this.environment = environment;
    this.current = { width, height, title, rows, footerHeight, subtitle, subtitleHeight }; return this.current;
  }
}
