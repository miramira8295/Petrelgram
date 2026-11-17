import { TdObject } from '../tdkit/TdTypes';

export type DrawnPageButtonKind = 'switch-inline' | 'login' | 'url' | 'copy' | 'callback' | 'webapp' | 'profile' | 'game' | 'disabled' | 'unsupported';
export interface DrawnPageButtonAction {
  buttonId?: number;
  kind: DrawnPageButtonKind;
  value: string;
  userId: number;
}
export function drawnPageButtonAction(node: TdObject | undefined): DrawnPageButtonAction {
  const type = ((node?.['@type'] as string | undefined) ?? '').replace(/^inlineKeyboardButtonType|^inlineButtonType/, '');
  let kind: DrawnPageButtonKind = 'unsupported';
  let value: string = '';
  if (type === 'UrlAuth' || type === 'LoginUrl') { kind = 'login'; value = (node?.['url'] as string | undefined) ?? ''; }
  else if (type === 'SwitchInline' && (node?.['same_peer'] === true ||
    (node?.['target_chat'] as TdObject | undefined)?.['@type'] === 'targetChatCurrent')) {
    kind = 'switch-inline'; value = (node?.['query'] as string | undefined) ?? '';
  }
  else if (type === 'Url') { kind = 'url'; value = (node?.['url'] as string | undefined) ?? ''; }
  else if (type === 'WebView' || type === 'WebApp') { kind = 'webapp'; value = (node?.['url'] as string | undefined) ?? ''; }
  else if (type === 'Copy' || type === 'CopyText') { kind = 'copy'; value = (node?.['copy_text'] ?? node?.['text'] ?? '') as string; }
  else if (type === 'Callback') { kind = 'callback'; value = (node?.['data'] as string | undefined) ?? ''; }
  else if (type === 'Game' || type === 'CallbackGame') { kind = 'game'; }
  else if (type === 'UserProfile' || type === 'User') { kind = 'profile'; }
  else if (type === 'Disabled') { kind = 'disabled'; }
  return { kind, value, buttonId: (node?.['button_id'] ?? node?.['id'] ?? 0) as number, userId: (node?.['user_id'] as number | undefined) ?? 0 };
}
export function drawnPageButtonStyle(node: TdObject | undefined): string {
  const type = (node?.['@type'] as string | undefined) ?? '';
  if (node?.['bg_primary'] === true || type === 'buttonStylePrimary') { return 'primary'; }
  if (node?.['bg_success'] === true || type === 'buttonStyleSuccess') { return 'success'; }
  if (node?.['bg_danger'] === true || type === 'buttonStyleDanger') { return 'danger'; }
  return node?.['link'] === true ? 'link' : '';
}

// Android's stretch is a repeated scan of the unfixed buttons. Sorting once
// finds the same water level in O(B log B), then positions are emitted in O(B).
// When minimum hit targets cannot fit, continue on another row instead of
// allowing controls to spill outside the bubble on a narrow window.
export interface DrawnPageButtonBox { x: number; y: number; width: number; height: number; }
export function drawnPageButtonBoxes(preferred: number[], maxWidth: number, align: string): DrawnPageButtonBox[] {
  const result: DrawnPageButtonBox[] = [];
  if (!(maxWidth > 0) || !Number.isFinite(maxWidth)) { return result; }
  const columns = Math.max(1, Math.floor((maxWidth + 7) / 55));
  for (let start: number = 0, row: number = 0; start < preferred.length; start += columns, row++) {
    const count = Math.min(columns, preferred.length - start);
    const available = Math.max(1, maxWidth - 7 * (count - 1));
    const widths: number[] = [];
    let total: number = 0;
    const minimum = Math.min(48, available / count);
    for (let i: number = 0; i < count; i++) {
      const width = Math.max(minimum, Math.min(maxWidth, preferred[start + i])); widths.push(width); total += width;
    }
    if (total > available) {
      const room = total - minimum * count;
      for (let i: number = 0; i < count; i++) {
        widths[i] = room > 0 ? widths[i] - (total - available) * (widths[i] - minimum) / room : available / count;
      }
    } else if (align === 'fill') {
      const sorted = widths.slice().sort((a: number, b: number): number => b - a);
      let rest = available, flexible = count;
      for (const width of sorted) {
        if (width <= rest / flexible) { break; }
        rest -= width; flexible--;
      }
      const share = flexible > 0 ? rest / flexible : 0;
      for (let i: number = 0; i < count; i++) { widths[i] = Math.max(widths[i], share); }
    }
    let used: number = 7 * (count - 1);
    for (const width of widths) { used += width; }
    let x = align === 'right' ? maxWidth - used : align === 'center' ? (maxWidth - used) / 2 : 0;
    for (const width of widths) { result.push({ x, y: row * 43, width, height: 36 }); x += width + 7; }
  }
  return result;
}
