import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { normalizeExternalUrl, openUrl } from './openUrl';
import { KEY_IN_APP_BROWSER } from '../store/AppSettings';

// The URL the in-app browser should load for a tapped link: http/https URLs
// pass through, bare web addresses get an https:// scheme, and every other
// scheme ('' included) returns '' so callers fall back to the system handler.
export function webBrowserTarget(url: string): string {
  const target = normalizeExternalUrl(url);
  if (target === '') { return ''; }
  const lower = target.toLowerCase();
  return lower.startsWith('https://') || lower.startsWith('http://') ? target : '';
}

// Open a tapped content link: web pages go to the in-app browser page, other
// schemes (tel:, mailto:, geo:, …) keep their system-app routing via openUrl.
export function openWebUrl(
  context: common.UIAbilityContext,
  url: string,
  onFailed: () => void = (): void => {}
): void {
  const target = webBrowserTarget(url);
  if (target === '') {
    openUrl(context, url, onFailed);
    return;
  }
  // 设置里选了系统浏览器就直接交出去。这是唯一的分叉点，所以所有入口
  // （消息里的链接、资料页、Telegram 深链接…）都跟着这一个开关走。
  if (!(AppStorage.get<boolean>(KEY_IN_APP_BROWSER) ?? true)) {
    openUrl(context, target, onFailed);
    return;
  }
  const params: Record<string, Object> = { 'url': target };
  router.pushUrl({ url: 'pages/web/InAppBrowserPage', params }).catch((e: Object): void => {
    console.error(`openWebUrl push failed for ${target}: ${JSON.stringify(e)}`);
    // The in-app page failing must never eat the tap — degrade to the browser.
    openUrl(context, target, onFailed);
  });
}
