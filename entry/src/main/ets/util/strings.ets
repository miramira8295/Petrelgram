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
const STATIC_STRING_CACHE_LIMIT: number = 512;
const staticStringCache: Map<string, string> = new Map();
// 带参数的字符串也缓存，但有上限、FIFO 淘汰。真机 CPU profile 里
// getStringByNameSync 累计约 698ms，其中大头是 str('xxx', name, count) 这类
// 每行都要格式化一遍的参数串——同一条会话里同一个人、同一个计数会反复出现，
// 命中率并不低。value 空间无界（实时计数、名字），所以不能像静态串那样只
// 「满了清空」——那会在滚动热路径上周期性地全量失效；改成插入序 FIFO，
// 每次只挤掉最老的一条。key 里不带语言纪元：切语言时 invalidateStringCache()
// 和静态缓存一起清，效果等价且省掉每次拼 key 的开销。
const PARAM_STRING_CACHE_LIMIT: number = 1024;
const paramStringCache: Map<string, string> = new Map();
// 参数之间的分隔符：控制字符，不会出现在任何名字或数字里，'a'+'bc' 与 'ab'+'c'
// 才分得开。
const PARAM_KEY_SEP: string = '\u001f';

function paramCacheKey(key: string, args: Array<string | number>): string {
  return `${key}${PARAM_KEY_SEP}${args.join(PARAM_KEY_SEP)}`;
}

function rememberParamString(cacheKey: string, value: string): void {
  if (paramStringCache.size >= PARAM_STRING_CACHE_LIMIT) {
    // Map 按插入序迭代，第一个就是最老的。
    const oldest: IteratorResult<string> = paramStringCache.keys().next();
    if (!oldest.done) {
      paramStringCache.delete(oldest.value);
    }
  }
  paramStringCache.set(cacheKey, value);
}

// 单测用：当前参数缓存条数。
export function paramStringCacheSize(): number {
  return paramStringCache.size;
}

// Called once during app startup, before any store is built.
export function installStrings(next: StringSource): void {
  source = next;
  staticStringCache.clear();
  paramStringCache.clear();
}

export function installStringsFromContext(context: common.ApplicationContext): void {
  installStrings(new ResourceStrings(context));
}

// Discards the installed source. Only for tests that need a clean slate.
export function resetStrings(): void {
  source = null;
  staticStringCache.clear();
  paramStringCache.clear();
}

// The platform resource manager switches locale in place. Plain strings that
// were already resolved do not, so appLanguage calls this in the same commit as
// refreshLocale()/LANGUAGE_EPOCH.
export function invalidateStringCache(): void {
  staticStringCache.clear();
  paramStringCache.clear();
}

// The one call the rest of the app makes. Returns the key itself when no source
// is installed — which happens in host unit tests, and is what lets those tests
// assert on the key (i.e. on which message was chosen) rather than on copy.
export function str(key: string, ...args: Array<string | number>): string {
  if (source === null) {
    return args.length === 0 ? key : `${key}(${args.join(',')})`;
  }
  // Static labels dominate row construction and are safe to share until the
  // locale epoch changes. Parameterized strings go through a bounded FIFO
  // cache (see paramStringCache) — their value space is unbounded, but the
  // working set of one chat is small and repeats a lot.
  if (args.length === 0) {
    const cached = staticStringCache.get(key);
    if (cached !== undefined) {
      return cached;
    }
    const value = source.get(key, args);
    if (staticStringCache.size >= STATIC_STRING_CACHE_LIMIT) {
      staticStringCache.clear();
    }
    staticStringCache.set(key, value);
    return value;
  }
  const cacheKey: string = paramCacheKey(key, args);
  const hit = paramStringCache.get(cacheKey);
  if (hit !== undefined) {
    return hit;
  }
  const formatted = source.get(key, args);
  rememberParamString(cacheKey, formatted);
  return formatted;
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
