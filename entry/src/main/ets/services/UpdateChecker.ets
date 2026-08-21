import { http } from '@kit.NetworkKit';
import { bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logE } from '../util/log';

// 版本检查。数据源直接用 GitHub Releases —— 发版时打的 tag 本身就是版本号，
// 不额外维护一个 version.json：多一个文件就多一处"忘了同步"的地方。
const RELEASE_API: string =
  'https://api.github.com/repos/miramira8295/TelegramForHarmony/releases/latest';
const RELEASE_PAGE: string =
  'https://github.com/miramira8295/TelegramForHarmony/releases/latest';
// 国内直连 api.github.com 经常超时。给一个短超时，失败就静默 —— 转圈半天
// 再报错比不查更烦人。
const REQUEST_TIMEOUT_MS: number = 8000;
const CHECK_INTERVAL_MS: number = 6 * 3600 * 1000;
const STORE_NAME: string = 'update_check';
const KEY_LAST_CHECK: string = 'last_check_ms';
const KEY_LATEST_TAG: string = 'latest_tag';
const KEY_LATEST_NOTES: string = 'latest_notes';

// 供 UI 订阅：设置入口的红点直接绑这个。
export const STORAGE_UPDATE_AVAILABLE: string = 'updateAvailable';
export const STORAGE_LATEST_VERSION: string = 'latestVersion';
export const STORAGE_LATEST_NOTES: string = 'latestNotes';

export interface UpdateInfo {
  currentVersion: string;
  latestVersion: string;
  notes: string;
  hasUpdate: boolean;
  releaseUrl: string;
}

// "v1.2.10" -> [1, 2, 10]。非数字段按 0 处理，避免预发布后缀（-beta 等）
// 让比较直接抛出。
function parseVersion(raw: string): number[] {
  const cleaned: string = raw.trim().replace(/^v/i, '');
  const head: string = cleaned.split('-')[0];
  return head.split('.').map((part: string): number => {
    const value: number = Number(part);
    return Number.isFinite(value) ? value : 0;
  });
}

// 逐段比较，段数不同时缺失段视为 0（1.2 < 1.2.1）。
export function isNewerVersion(latest: string, current: string): boolean {
  if (latest === '' || current === '') {
    return false;
  }
  const a: number[] = parseVersion(latest);
  const b: number[] = parseVersion(current);
  const len: number = Math.max(a.length, b.length);
  for (let i = 0; i < len; i++) {
    const left: number = i < a.length ? a[i] : 0;
    const right: number = i < b.length ? b[i] : 0;
    if (left !== right) {
      return left > right;
    }
  }
  return false;
}

class UpdateChecker {
  private prefs: preferences.Preferences | null = null;
  private currentVersion: string = '';
  private inFlight: boolean = false;

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      this.currentVersion = info.versionName;
    } catch (e) {
      logE(`UpdateChecker.getBundleInfo failed: ${JSON.stringify(e)}`);
    }
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME);
      this.restoreCached();
    } catch (e) {
      logE(`UpdateChecker.getPreferences failed: ${JSON.stringify(e)}`);
    }
  }

  getCurrentVersion(): string {
    return this.currentVersion;
  }

  getReleaseUrl(): string {
    return RELEASE_PAGE;
  }

  snapshot(): UpdateInfo {
    const latest: string = (AppStorage.get(STORAGE_LATEST_VERSION) as string | undefined) ?? '';
    return {
      currentVersion: this.currentVersion,
      latestVersion: latest,
      notes: (AppStorage.get(STORAGE_LATEST_NOTES) as string | undefined) ?? '',
      hasUpdate: (AppStorage.get(STORAGE_UPDATE_AVAILABLE) as boolean | undefined) ?? false,
      releaseUrl: RELEASE_PAGE
    };
  }

  // 上次的结果先铺上去，这样红点在网络请求回来之前就是对的。
  private restoreCached(): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    const tag: string = String(p.getSync(KEY_LATEST_TAG, ''));
    const notes: string = String(p.getSync(KEY_LATEST_NOTES, ''));
    if (tag !== '') {
      this.publish(tag, notes);
    }
  }

  private publish(tag: string, notes: string): void {
    AppStorage.setOrCreate(STORAGE_LATEST_VERSION, tag);
    AppStorage.setOrCreate(STORAGE_LATEST_NOTES, notes);
    AppStorage.setOrCreate(STORAGE_UPDATE_AVAILABLE,
      isNewerVersion(tag, this.currentVersion));
  }

  private throttled(): boolean {
    const p = this.prefs;
    if (p === null) {
      return false;
    }
    const last: number = Number(p.getSync(KEY_LAST_CHECK, 0));
    return Number.isFinite(last) && Date.now() - last < CHECK_INTERVAL_MS;
  }

  // force=true 是"关于"页里的手动检查，忽略节流。
  async check(force: boolean): Promise<UpdateInfo> {
    if (this.inFlight || (!force && this.throttled())) {
      return this.snapshot();
    }
    this.inFlight = true;
    const request = http.createHttp();
    try {
      const response = await request.request(RELEASE_API, {
        method: http.RequestMethod.GET,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        header: { 'Accept': 'application/vnd.github+json' } as Record<string, string>
      });
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      const body = JSON.parse(String(response.result)) as Record<string, Object>;
      const tag: string = (body['tag_name'] as string | undefined) ?? '';
      const notes: string = (body['body'] as string | undefined) ?? '';
      if (tag !== '') {
        this.publish(tag, notes);
        const p = this.prefs;
        if (p !== null) {
          p.putSync(KEY_LATEST_TAG, tag);
          p.putSync(KEY_LATEST_NOTES, notes);
          p.putSync(KEY_LAST_CHECK, Date.now());
          await p.flush();
        }
      }
    } catch (e) {
      // 静默失败：查不到就当没有更新，不打扰用户。
      logE(`UpdateChecker.check failed: ${JSON.stringify(e)}`);
    } finally {
      request.destroy();
      this.inFlight = false;
    }
    return this.snapshot();
  }
}

export const updateChecker: UpdateChecker = new UpdateChecker();
