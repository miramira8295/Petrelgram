import { TdObject, TdRequest } from '../tdkit/TdTypes';

// These are Telegram language-pack identifiers, not HarmonyOS locale tags.
export function telegramLanguageId(locale: string): string {
  const tag: string = locale.toLowerCase().replace(/_/g, '-');
  if (tag === 'zh' || tag.startsWith('zh-')) {
    const parts: string[] = tag.split('-');
    if (parts.includes('hant')) { return 'zh-hant'; }
    if (parts.includes('hans')) { return 'zh-hans'; }
    return parts.includes('tw') || parts.includes('hk') || parts.includes('mo') ? 'zh-hant' : 'zh-hans';
  }
  const code: string = tag.split('-')[0];
  return ['en', 'ru', 'uk', 'fa', 'ar', 'id', 'ms', 'tr', 'vi', 'th', 'ja', 'ko',
    'de', 'fr', 'es', 'pt', 'it', 'hi'].includes(code) ? code : 'en';
}

function languageOption(name: string, value: string): TdRequest {
  const req: TdRequest = { '@type': 'setOption' };
  req['name'] = name;
  req['value'] = { '@type': 'optionValueString', 'value': value } as TdObject;
  return req;
}

// One instance per TD runtime. Serialize changes so rapid language switches
// cannot let a late acknowledgement put the server back on an older language.
export class TdLanguageSync {
  private desired: string = '';
  private applied: string = '';
  private targetSet: boolean = false;
  private stopped: boolean = false;
  private pending: Promise<void> | null = null;
  private send: (req: TdRequest) => Promise<TdObject>;

  constructor(send: (req: TdRequest) => Promise<TdObject>) { this.send = send; }

  async sync(locale: string): Promise<void> {
    if (this.stopped) { return; }
    this.desired = telegramLanguageId(locale);
    while (!this.stopped && (!this.targetSet || this.applied !== this.desired)) {
      if (this.pending === null) {
        this.pending = this.flush().finally((): void => { this.pending = null; });
      }
      await this.pending;
    }
  }

  stop(): void { this.stopped = true; }

  private async flush(): Promise<void> {
    if (!this.targetSet) {
      await this.send(languageOption('localization_target', 'tdesktop'));
      if (this.stopped) { return; }
      this.targetSet = true;
    }
    while (!this.stopped && this.applied !== this.desired) {
      const language: string = this.desired;
      await this.send(languageOption('language_pack_id', language));
      if (this.stopped) { return; }
      this.applied = language;
    }
  }
}
