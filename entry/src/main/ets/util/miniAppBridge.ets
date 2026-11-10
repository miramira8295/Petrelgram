import { miniAppOrigin } from './miniAppModel';

export interface MiniAppEvent {
  name: string;
  data: Record<string, Object>;
}

export function parseMiniAppEvent(name: string, raw: string): MiniAppEvent | null {
  if (typeof name !== 'string' || typeof raw !== 'string' ||
    !/^web_app_[a-z_]+$/.test(name) || name.length > 100 || raw.length > 32768) { return null; }
  try {
    const parsed: Object | null = JSON.parse(raw === '' ? '{}' : raw);
    // The official SDK JSON-encodes an empty string for parameterless events.
    if (parsed === null || parsed === '') { return { name, data: {} }; }
    const data = parsed as Record<string, Object>;
    if (typeof data !== 'object' || Array.isArray(data)) { return null; }
    return { name, data };
  } catch (_) { return null; }
}

export class MiniAppBridge {
  private receive: (event: MiniAppEvent) => void;
  constructor(receive: (event: MiniAppEvent) => void) { this.receive = receive; }
  postEvent(name: string, raw: string): void {
    const event = parseMiniAppEvent(name, raw);
    if (event !== null) { this.receive(event); }
  }
  dispose(): void { this.receive = (_event: MiniAppEvent): void => {}; }
}

export function miniAppBridgePermission(url: string): string {
  const origin = miniAppOrigin(url);
  const match = /^https:\/\/(\[[^\]]+\]|[^:]+)(?::([0-9]+))?$/.exec(origin);
  const rule: Record<string, string> = {
    'scheme': 'https', 'host': match === null ? 'invalid.invalid' : match[1],
    // 官方示例里默认端口写的是空串（不是 '443'）。写 '443' 匹配不上不带端口的
    // URL，整条规则失效 → 页面对 PetrelMiniApp.postEvent 的调用被拒成
    // "Jsb Permission Denied"，Mini App 的握手（ready/expand/theme/登录态）全断。
    'port': match === null ? '' : (match[2] ?? ''),
    'path': ''
  };;
  const permission: Record<string, Object> = { 'urlPermissionList': [rule] };
  const root: Record<string, Object> = { 'javascriptProxyPermission': permission };
  return JSON.stringify(root);
}

// Installed before the site's scripts, using the transport recognized by
// Telegram's official SDK. No initData is constructed or changed here.
export function miniAppBootstrap(): string {
  return `(function(){
    if(window.top!==window)return;
    window.TelegramWebviewProxy={postEvent:function(name,data){
      window.PetrelMiniApp.postEvent(name,typeof data==='string'?data:JSON.stringify(data||{}));
    }};
  })();`;
}

export function miniAppReceiveScript(event: string, data: Record<string, Object>): string {
  const name = JSON.stringify(event);
  const payload = JSON.stringify(data).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  return `if(window.Telegram&&window.Telegram.WebView){window.Telegram.WebView.receiveEvent(${name},${payload});}`;
}

export function miniAppString(data: Record<string, Object>, key: string): string {
  return typeof data[key] === 'string' ? data[key] as string : '';
}

export function miniAppColor(value: string, fallback: string): string {
  return /^#[0-9a-f]{6}$/i.test(value) ? value : fallback;
}

export interface MiniAppButton {
  text: string;
  visible: boolean;
  active: boolean;
  progress: boolean;
  color: string;
  textColor: string;
}

export function miniAppButton(data: Record<string, Object>): MiniAppButton {
  const text = miniAppString(data, 'text').trim().substring(0, 128);
  return { text, visible: data['is_visible'] === true && text !== '',
    active: data['is_active'] !== false, progress: data['is_progress_visible'] === true,
    color: miniAppColor(miniAppString(data, 'color'), '#3390ec'),
    textColor: miniAppColor(miniAppString(data, 'text_color'), '#ffffff') };
}
