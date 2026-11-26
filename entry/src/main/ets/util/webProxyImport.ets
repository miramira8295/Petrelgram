// 浏览器一键导入 WEB 代理的「可重放」信号。
//
// 为什么不能只靠导航参数：navigateToSetting('ProxyPage', params) 的去重按
// (页面名, frameKey) 判，而 WEB 表单没有端口，util/settingsNav.ets 的
// settingFrameKey 对 webproxy 参数恒返回空串（它要求 server!='' && port>0）。
// 于是「代理页已经在右栏」时，新链接有被判成 skip 的风险：不重建页面、
// onRouteParams 不触发，表单一个字段都不填（2026-11-25 真机复现用户报障
// 「应用在后台时从浏览器点一键导入无效」时，页面被切出来但没有弹表单）。
// 这条推理是从 settingFrameKey / decidePush 的代码读出来的，没有逐帧日志佐证；
// 但下面这个信号与导航去重无关，所以不管 skip 是否真的发生都能弹表单——
// 修完后同一手势真机复测通过，这一点是验证过的。
//
// 所以真正的触发器是这里这条 AppStorage 信号：写草稿 + 纪元 +1。代理页无论是
// 新建（aboutToAppear）还是已存在（@StorageLink @Watch），都会取走草稿并弹表单，
// 与导航栈的去重结果无关。
export interface WebProxyDraft {
  host: string;
  path: string;
  secret: string;
}

export const KEY_WEB_PROXY_IMPORT_EPOCH: string = 'webProxyImportEpoch';
const KEY_WEB_PROXY_IMPORT_DRAFT: string = 'webProxyImportDraft';
const EMPTY_DRAFT: WebProxyDraft = { host: '', path: '', secret: '' };

export function postWebProxyDraft(host: string, path: string, secret: string): void {
  if (host === '') {
    return;
  }
  const draft: WebProxyDraft = { host: host, path: path, secret: secret };
  AppStorage.setOrCreate<WebProxyDraft>(KEY_WEB_PROXY_IMPORT_DRAFT, draft);
  const epoch: number = (AppStorage.get<number>(KEY_WEB_PROXY_IMPORT_EPOCH) ?? 0) + 1;
  AppStorage.setOrCreate<number>(KEY_WEB_PROXY_IMPORT_EPOCH, epoch);
}

// 取走即清空：同一条链接不会在下次进代理页时又弹一遍表单。
export function takeWebProxyDraft(): WebProxyDraft | null {
  const draft: WebProxyDraft | undefined = AppStorage.get<WebProxyDraft>(KEY_WEB_PROXY_IMPORT_DRAFT);
  if (draft === undefined || draft === null || draft.host === '') {
    return null;
  }
  AppStorage.setOrCreate<WebProxyDraft>(KEY_WEB_PROXY_IMPORT_DRAFT, EMPTY_DRAFT);
  return draft;
}
