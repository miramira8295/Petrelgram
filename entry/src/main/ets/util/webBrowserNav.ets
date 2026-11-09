import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { normalizeExternalUrl, openUrl } from './openUrl';
import { KEY_EXTERNAL_LINK_ACTION, KEY_IN_APP_BROWSER } from '../store/AppSettings';
import {
  EXT_LINK_ASK, EXT_LINK_COPY, EXT_LINK_DEFAULT, externalLinkDecision
} from './externalLinkPolicy';
import { copyPlainText } from './clipboard';
import { endLinkNav } from './linkTapGuard';
import { str } from './strings';
import { logE } from './log';

// The URL the in-app browser should load for a tapped link: http/https URLs
// pass through, bare web addresses get an https:// scheme, and every other
// scheme ('' included) returns '' so callers fall back to the system handler.
export function webBrowserTarget(url: string): string {
  const target = normalizeExternalUrl(url);
  if (target === '') { return ''; }
  const lower = target.toLowerCase();
  return lower.startsWith('https://') || lower.startsWith('http://') ? target : '';
}

// 【链接忙碌态必须在这里收】消息里的链接点下去时，ChatPage 先 beginLinkNav：
// 那段文字换成高亮底色并无限呼吸，表示"正在打开"。它原本只靠会话页被盖住
// （打开了浏览器页）或站内解析完成来解除——可下面这几条结局都**不离开会话页**：
// 弹窗里取消、弹窗里选复制、「复制」档直接复制、交给系统应用却打开失败。
// 于是链接一直高亮在呼吸，看着像气泡卡在选中态（用户 2026-09-23 实报）。
// endLinkNav 对不是从消息里点进来的入口（资料页简介等）是空操作。
//
// 弹一层「打开 / 复制」，让用户在跳出去之前先看清真网址。
// 标题截断到 60 是给长网址留的：ActionMenu 的标题不换行，太长会把按钮挤没。
function askBeforeOpen(context: common.UIAbilityContext, url: string,
  onFailed: () => void): void {
  promptAction.showActionMenu({
    title: url.length > 60 ? url.substring(0, 57) + '…' : url,
    buttons: [
      { text: $r('app.string.lk_open'), color: '#3390EC' },
      { text: $r('app.string.mb_copy_url'), color: '#3390EC' }
    ]
  }).then((result: promptAction.ActionMenuSuccessResponse): void => {
    if (result.index === 0) {
      openResolvedWebUrl(context, url, onFailed);
      return;
    }
    copyPlainText(url, str('link_copied'));
    endLinkNav();
  }).catch((): void => {
    // 取消（点遮罩或返回）。
    endLinkNav();
  });
}

// Open a tapped content link: web pages go to the in-app browser page, other
// schemes (tel:, mailto:, geo:, …) keep their system-app routing via openUrl.
//
// 【外部链接三档】用户在「设置 → 交互」选的：直接打开 / 复制 / 弹窗选择
// （判据在 util/externalLinkPolicy，纯函数有单测）。挂在这一层是因为文件头那句
// 已经写了——这是所有入口唯一的分叉点，消息里的链接、资料页简介、深链接都从这儿过。
// deceptive 由调用方给：显示文字藏着另一个网址时强制走弹窗，设置覆盖不了它。
export function openWebUrl(
  context: common.UIAbilityContext,
  url: string,
  onFailed: () => void = (): void => {},
  deceptive: boolean = false
): void {
  const policy: string = AppStorage.get<string>(KEY_EXTERNAL_LINK_ACTION) ?? EXT_LINK_DEFAULT;
  const decision: string = externalLinkDecision(policy, deceptive);
  if (decision === EXT_LINK_COPY) {
    copyPlainText(url, str('link_copied'));
    endLinkNav();
    return;
  }
  if (decision === EXT_LINK_ASK) {
    askBeforeOpen(context, url, onFailed);
    return;
  }
  openResolvedWebUrl(context, url, onFailed);
}

// 真正把链接交出去的那一半。弹窗里选了「打开」也回到这里，所以它**不再**过
// 一遍档位判断——否则「弹窗选择」档下点了打开会再弹一次。
function openResolvedWebUrl(
  context: common.UIAbilityContext,
  url: string,
  onFailedOuter: () => void
): void {
  // 交出去失败时页面不会被盖住，忙碌态得自己收。
  const onFailed = (): void => {
    endLinkNav();
    onFailedOuter();
  };
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
    logE(`openWebUrl push failed for ${target}: ${JSON.stringify(e)}`);
    // The in-app page failing must never eat the tap — degrade to the browser.
    openUrl(context, target, onFailed);
  });
}
