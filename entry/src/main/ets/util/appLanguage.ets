import { i18n } from '@kit.LocalizationKit';
import { mirrorChatEnvKey } from './chatEnvMirror';
import { refreshLocale } from './intlFormat';
import { invalidateStringCache, str } from './strings';
import { logE } from './log';

// The platform owns the app's language: setAppPreferredLanguage() switches the
// resource lookup and survives restarts, so nothing here re-applies anything on
// startup. What this module adds is the list to choose from, the bookkeeping
// needed to render which row is selected, and the cache invalidation Intl needs.

export const LANGUAGE_SYSTEM = 'default';

// Bumped whenever the language changes. $r() text re-resolves itself on a
// configuration change, but text built with str() is already a plain string
// inside the built UI and would stay in the old language until something else
// happened to rebuild that component. A page whose displayed text comes from
// str() — because it also has to filter or compare it, which a Resource cannot
// do — observes this with @StorageProp and rebuilds.
export const LANGUAGE_EPOCH = 'languageEpoch';

export function bumpLanguageEpoch(): void {
  const next: number = (AppStorage.get<number>(LANGUAGE_EPOCH) ?? 0) + 1;
  AppStorage.setOrCreate(LANGUAGE_EPOCH, next);
  mirrorChatEnvKey(LANGUAGE_EPOCH, next);
}

export interface AppLanguage {
  tag: string;
  label: string;
}

// A function, not a const: the "跟随系统" label is itself translated, so it has
// to resolve at call time rather than when this module is first imported.
//
// The other labels are endonyms and deliberately stay untranslated. That is the
// convention, and it is also the only thing that works: a user who has landed
// in a language they cannot read needs to recognise their own language's name
// in this list.
export function appLanguages(): AppLanguage[] {
  return [
    { tag: LANGUAGE_SYSTEM, label: str('language_system') },
    { tag: 'zh-Hans', label: '简体中文' }, // i18n-exempt: endonym, never translated
    { tag: 'zh-Hant', label: '繁體中文' }, // i18n-exempt: endonym, never translated
    { tag: 'en-US', label: 'English' },
    { tag: 'ru', label: 'Русский' }, // i18n-exempt: endonym, never translated
    { tag: 'uk', label: 'Українська' }, // i18n-exempt: endonym, never translated
    { tag: 'fa', label: 'فارسی' }, // i18n-exempt: endonym, never translated
    { tag: 'ar', label: 'العربية' }, // i18n-exempt: endonym, never translated
    { tag: 'id', label: 'Indonesia' }, // i18n-exempt: endonym, never translated
    { tag: 'ms', label: 'Melayu' }, // i18n-exempt: endonym, never translated
    { tag: 'tr', label: 'Türkçe' }, // i18n-exempt: endonym, never translated
    { tag: 'vi', label: 'Tiếng Việt' }, // i18n-exempt: endonym, never translated
    { tag: 'th', label: 'ไทย' }, // i18n-exempt: endonym, never translated
    { tag: 'ja', label: '日本語' }, // i18n-exempt: endonym, never translated
    { tag: 'ko', label: '한국어' }, // i18n-exempt: endonym, never translated
    { tag: 'de', label: 'Deutsch' }, // i18n-exempt: endonym, never translated
    { tag: 'fr', label: 'Français' }, // i18n-exempt: endonym, never translated
    { tag: 'es', label: 'Español' }, // i18n-exempt: endonym, never translated
    { tag: 'pt', label: 'Português' }, // i18n-exempt: endonym, never translated
    { tag: 'it', label: 'Italiano' }, // i18n-exempt: endonym, never translated
    { tag: 'hi', label: 'हिन्दी' } // i18n-exempt: endonym, never translated
  ];
}

export function supportedLanguageTags(): string[] {
  return appLanguages()
    .filter((item: AppLanguage): boolean => item.tag !== LANGUAGE_SYSTEM)
    .map((item: AppLanguage): string => item.tag);
}

// Which of the listed languages the system language actually resolves to. Used
// to tell the user what "跟随系统" will give them. Note the comparison is done
// by the platform matcher, never by comparing language codes by hand — the
// official guidance forbids that, and zh-Hans / zh-CN / zh-Hans-CN would all
// have to be special-cased if it were done here.
export function systemMatchedLanguage(): string {
  try {
    const system = i18n.System.getSystemLanguage();
    return i18n.I18NUtil.getBestMatchLocale(system, supportedLanguageTags());
  } catch (e) {
    logE(`appLanguage.systemMatched failed: ${e}`);
    return '';
  }
}

export function labelForTag(tag: string): string {
  for (const item of appLanguages()) {
    if (item.tag === tag) {
      return item.label;
    }
  }
  return tag;
}

// Setting a concrete language takes effect immediately; clearing back to
// 'default' is documented as taking effect only after a restart. Callers must
// tell the user which of the two just happened, or the switch looks broken.
export function requiresRestart(tag: string): boolean {
  return tag === LANGUAGE_SYSTEM;
}

export function applyAppLanguage(tag: string): boolean {
  try {
    i18n.System.setAppPreferredLanguage(tag);
  } catch (e) {
    logE(`appLanguage.apply ${tag} failed: ${e}`);
    return false;
  }
  // Resources reload themselves; the Intl formatters do not, and would keep
  // rendering dates in the language the user just left.
  invalidateStringCache();
  refreshLocale();
  bumpLanguageEpoch();
  return true;
}
