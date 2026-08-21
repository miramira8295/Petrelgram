import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE } from './log';

// Localized string lookup for code with no UI context.
//
// Most of the text in this app is produced outside components: stores build
// chat previews, services build notifications, util/ formats status lines. None
// of them can use $r(), which yields a Resource and needs a UI context, so they
// go through str() instead.
//
// Why a module-level accessor rather than a parameter threaded through every
// function: the alternative infects hundreds of call sites with a parameter
// that only the leaf uses. The official guidance against global interfaces
// targets UI-instance-dependent ones (vp2px, animateTo, getContext) — pixel
// density and animation belong to a window, so a global cannot tell which. A
// string does not have that ambiguity: locale is application-level
// configuration, so every caller resolves the same value. That is exactly the
// boundary of this design — media and dimension resources vary per window and
// must NOT be fetched this way.

export interface StringSource {
  get(key: string, args: Array<string | number>): string;
  // Count-dependent wording. Chinese has one form, English has two, Arabic six
  // — so "3 分钟前" cannot simply be a placeholder string, or English gets
  // "1 minutes ago". The platform picks the form from plural.json.
  plural(key: string, count: number, args: Array<string | number>): string;
}

// Backed by the application-level resource manager. ApplicationContext is the
// context the platform provides for non-UI code; it is not tied to any Ability
// or window, so it survives the UI being torn down and rebuilt.
//
// The context is held, not the ResourceManager: the app can change its
// preferred language at runtime, and a manager captured once at startup is a
// reference to whatever configuration was current then. Re-reading the property
// per call costs nothing next to the lookup itself and removes the question of
// whether that reference stays valid across a language change.
class ResourceStrings implements StringSource {
  private context: common.ApplicationContext;

  constructor(context: common.ApplicationContext) {
    this.context = context;
  }

  private res(): resourceManager.ResourceManager {
    return this.context.resourceManager;
  }

  get(key: string, args: Array<string | number>): string {
    try {
      const res = this.res();
      return args.length === 0
        ? res.getStringByNameSync(key)
        : res.getStringByNameSync(key, ...args);
    } catch (e) {
      // 9001004 = no resource by that name. A wrong key must not take down the
      // whole formatting path, so degrade to the key: it is visibly wrong in
      // the UI and greppable in a bug report, which a blank string is not.
      const err = e as BusinessError;
      logE(`strings: '${key}' unavailable (${err.code}) ${err.message}`);
      return key;
    }
  }

  plural(key: string, count: number, args: Array<string | number>): string {
    try {
      return this.res().getIntPluralStringByNameSync(key, count, ...args);
    } catch (e) {
      const err = e as BusinessError;
      logE(`strings: plural '${key}' unavailable (${err.code}) ${err.message}`);
      return key;
    }
  }
}

let source: StringSource | null = null;

// Called once during app startup, before any store is built.
export function installStrings(next: StringSource): void {
  source = next;
}

export function installStringsFromContext(context: common.ApplicationContext): void {
  installStrings(new ResourceStrings(context));
}

// Discards the installed source. Only for tests that need a clean slate.
export function resetStrings(): void {
  source = null;
}

// The one call the rest of the app makes. Returns the key itself when no source
// is installed — which happens in host unit tests, and is what lets those tests
// assert on the key (i.e. on which message was chosen) rather than on copy.
export function str(key: string, ...args: Array<string | number>): string {
  if (source === null) {
    return args.length === 0 ? key : `${key}(${args.join(',')})`;
  }
  return source.get(key, args);
}

// Count-dependent wording; `count` selects the plural form and is also the
// usual first placeholder value.
export function plural(key: string, count: number, ...args: Array<string | number>): string {
  if (source === null) {
    const parts: Array<string | number> = [count];
    for (const a of args) {
      parts.push(a);
    }
    return `${key}(${parts.join(',')})`;
  }
  return source.plural(key, count, args);
}
