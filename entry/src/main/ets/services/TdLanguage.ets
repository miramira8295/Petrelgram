import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { TdLanguageSync } from '../util/tdLanguageSync';
import { logE } from '../util/log';

let context: common.ApplicationContext | undefined = undefined;
let languageSync: TdLanguageSync | null = null;
let generation: number = 0;
export function tdLanguageGeneration(): number { return generation; }

export function initTdLanguageContext(value: common.ApplicationContext): void { context = value; }

export function systemLanguageForTd(): string {
  try { return i18n.System.getSystemLanguage() || 'en'; }
  catch (_) { return 'en'; }
}

function effectiveLanguage(): string {
  // Read the live resource configuration, not a preference awaiting restart.
  let locale: string = '';
  try { locale = context?.resourceManager.getConfigurationSync().locale ?? ''; } catch (_) {}
  if (locale === '') {
    try { locale = i18n.System.getAppPreferredLanguage(); } catch (_) {}
  }
  if (locale === '' || locale === 'default') { locale = systemLanguageForTd(); }
  // Match the language actually supported by this app, including Chinese script.
  try {
    return i18n.I18NUtil.getBestMatchLocale(locale, ['zh-Hans', 'zh-Hant', 'en-US',
      'ru', 'uk', 'fa', 'ar', 'id', 'ms', 'tr', 'vi', 'th', 'ja', 'ko', 'de', 'fr', 'es', 'pt', 'it', 'hi']) || 'zh-Hans';
  } catch (_) { return 'zh-Hans'; }
}

export function attachTdLanguage(client: TdClient): void {
  detachTdLanguage();
  languageSync = new TdLanguageSync((request: TdRequest): Promise<TdObject> => client.send(request, 5000));
  syncTdLanguage();
}

export function detachTdLanguage(): void {
  generation++;
  languageSync?.stop();
  languageSync = null;
}

// Safe at startup/configuration changes; a language failure must not block login.
// The next trigger (including opening Report) retries failed options.
export async function syncTdLanguage(): Promise<void> {
  try { await languageSync?.sync(effectiveLanguage()); }
  catch (_) { logE('TDLib language synchronization failed'); }
}
