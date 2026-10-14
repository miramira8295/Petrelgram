import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { webAppUrlOf } from './webAppUrl';

export interface MiniAppLaunch {
  kind: string; // web (message/menu), main, link
  chatId: number;
  botUserId: number;
  title: string;
  url?: string;
  shortName?: string;
  startParameter?: string;
}

export interface MiniAppResult {
  url: string;
  launchId: string;
}

// Only HTTPS Mini Apps receive the native bridge. Do not accept credentials,
// escaped hosts or browser-normalized backslashes in a trust boundary.
export function miniAppOrigin(value: string): string {
  if (/[\\\s\u0000-\u001f]/.test(value)) { return ''; }
  const match = /^https:\/\/([a-z0-9.-]+|\[[0-9a-f:]+\])(:[0-9]+)?(?=[/?#]|$)/i.exec(value);
  if (match === null) { return ''; }
  const port = match[2] ?? '';
  if (port !== '' && (Number(port.substring(1)) < 1 || Number(port.substring(1)) > 65535)) { return ''; }
  return `https://${match[1].toLowerCase()}${port === ':443' ? '' : port}`;
}

export function miniAppTheme(dark: boolean): Record<string, string> {
  return {
    'bg_color': dark ? '#18222d' : '#ffffff', 'text_color': dark ? '#ffffff' : '#17212b',
    'hint_color': dark ? '#a3abb4' : '#707579', 'link_color': '#3390ec',
    'button_color': '#3390ec', 'button_text_color': '#ffffff',
    'secondary_bg_color': dark ? '#111921' : '#f1f3f5',
    'header_bg_color': dark ? '#18222d' : '#ffffff',
    'bottom_bar_bg_color': dark ? '#18222d' : '#ffffff',
    'accent_text_color': '#3390ec', 'section_bg_color': dark ? '#18222d' : '#ffffff',
    'section_header_text_color': '#3390ec', 'subtitle_text_color': dark ? '#a3abb4' : '#707579',
    'destructive_text_color': '#e53935', 'section_separator_color': dark ? '#283440' : '#e5e7eb'
  };
}

export function miniAppRequest(launch: MiniAppLaunch, dark: boolean): TdRequest {
  if (launch.botUserId <= 0 || launch.chatId === 0) { throw new Error('Invalid Mini App peer'); }
  const request: TdRequest = { '@type': 'openWebApp' };
  if (launch.kind === 'main') { request['@type'] = 'getMainWebApp'; }
  else if (launch.kind === 'link') {
    request['@type'] = 'getWebAppLinkUrl';
    request['web_app_short_name'] = launch.shortName ?? '';
    request['allow_write_access'] = false;
  } else if (launch.kind !== 'web' || miniAppOrigin(launch.url ?? '') === '') {
    throw new Error('Invalid Mini App launch');
  }
  request['chat_id'] = launch.chatId;
  request['bot_user_id'] = launch.botUserId;
  if (launch.kind === 'web') { request['url'] = launch.url ?? ''; }
  else { request['start_parameter'] = launch.startParameter ?? ''; }
  const colors = miniAppTheme(dark);
  const names: Record<string, string> = {
    'bg_color': 'background_color', 'secondary_bg_color': 'secondary_background_color',
    'header_bg_color': 'header_background_color', 'bottom_bar_bg_color': 'bottom_bar_background_color',
    'section_bg_color': 'section_background_color'
  };
  const theme: TdObject = { '@type': 'themeParameters' };
  for (const key of Object.keys(colors)) {
    theme[names[key] ?? key] = parseInt(colors[key].substring(1), 16);
  }
  const mode: TdObject = { '@type': 'webAppOpenModeFullSize' };
  const parameters: TdObject = { '@type': 'webAppOpenParameters',
    'application_name': 'Petrelgram', 'theme': theme, 'mode': mode };
  request['parameters'] = parameters;
  return request;
}

export function miniAppResult(info: TdObject): MiniAppResult {
  // getWebAppLinkUrl returns WebAppUrl directly; other methods wrap it in url.
  const url = webAppUrlOf(info['url']);
  return { url, launchId: `${info['launch_id'] ?? ''}` };
}

// Own the launch id even if the page closes while openWebApp is in flight.
export class MiniAppSession {
  private generation: number = 0;
  private launchId: string = '';
  private send: (request: TdRequest) => Promise<TdObject>;
  private release: (id: string) => void;
  constructor(send: (request: TdRequest) => Promise<TdObject>, release: (id: string) => void) {
    this.send = send;
    this.release = release;
  }

  async open(launch: MiniAppLaunch, dark: boolean): Promise<MiniAppResult | null> {
    this.close();
    const generation = this.generation;
    const result = miniAppResult(await this.send(miniAppRequest(launch, dark)));
    if (generation !== this.generation || miniAppOrigin(result.url) === '') {
      if (result.launchId !== '' && result.launchId !== '0') { this.release(result.launchId); }
      if (generation !== this.generation) { return null; }
      throw new Error('Invalid Mini App response');
    }
    this.launchId = result.launchId;
    return result;
  }

  close(): void {
    this.generation++;
    const id = this.launchId;
    this.launchId = '';
    if (id !== '' && id !== '0') { this.release(id); }
  }
}
