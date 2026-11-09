import { common, Want } from '@kit.AbilityKit';
import { logE } from './log';

export function normalizeExternalUrl(url: string): string {
  const target = url.trim();
  if (target === '' || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(target)) {
    return target;
  }
  return `https://${target}`;
}

// Open a tapped link (web URL / mailto / tel / geo) in the appropriate system app.
export function openUrl(
  context: common.UIAbilityContext,
  url: string,
  onFailed: () => void = (): void => {}
): void {
  if (url.trim() === '' || context === undefined) {
    return;
  }
  // Bare web addresses (www.example.com / example.com, no scheme) can't be
  // opened by viewData as-is — prepend https:// so the browser recognizes them.
  // Any standards-compliant URI scheme (mailto:, tel:, geo:, tg:, …) is
  // already complete and must be left untouched.
  const target = normalizeExternalUrl(url);
  const want: Want = {
    action: 'ohos.want.action.viewData',
    uri: target
  };
  context.startAbility(want).catch((e: Object) => {
    logE(`openUrl failed for ${target}: ${JSON.stringify(e)}`);
    onFailed();
  });
}
