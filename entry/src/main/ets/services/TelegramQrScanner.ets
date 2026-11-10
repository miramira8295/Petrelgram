import { showDialog } from '../util/uiContext';
import { showToast } from '../util/toast';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { dispatchScannedQr } from '../util/qrScanFlow';
import { openTelegramLink } from '../util/openTelegramLink';
import { navigateToChatProfile } from '../util/profileNav';
import { str } from '../util/strings';

// 系统扫码只允许一份在途；实例代际用于页面销毁/换账号后丢弃结果。
let scanning: boolean = false;
export class TelegramQrScanner {
  private generation: number = 0;
  cancel(): void { this.generation++; }

  async start(context: common.UIAbilityContext): Promise<string> {
    if (scanning) { return 'cancelled'; }
    scanning = true;
    const generation = ++this.generation;
    const client = getTdClient();
    const current = (): boolean => generation === this.generation && getTdClient() === client;
    try {
      // 等菜单/二维码弹窗收起，避免系统界面与退出中的子窗口争用焦点。
      await new Promise<void>((resolve): void => { setTimeout(resolve, 180); });
      if (!current()) { return 'cancelled'; }
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: true
      });
      if (!current()) { return 'cancelled'; }
      const outcome = await dispatchScannedQr(result.originalValue, {
        current,
        send: (request: TdRequest): Promise<TdObject> => client.send(request, 15000),
        confirmLogin: async (): Promise<boolean> => {
          const answer = await showDialog({
            title: str('qr_login_title'), message: str('qr_login_body'),
            buttons: [{ text: str('cancel'), color: '#808080' },
              { text: str('qr_login_confirm'), color: '#2481CC' }]
          });
          return answer.index === 1;
        },
        openLink: (link: string): void => { openTelegramLink(context, link, false); },
        openInvite: (link: string): void => { navigateToChatProfile({ 'inviteLink': link }); }
      });
      if (current()) {
        if (outcome === 'loggedIn') { this.toast(str('as_desktop_connected')); }
        if (outcome === 'empty') { this.toast(str('as_no_qr')); }
        if (outcome === 'unsupported') { this.toast(str('qr_unsupported')); }
      }
      return outcome;
    } catch (caught) {
      if (current() && (caught as BusinessError).code !== 1000500002) {
        this.toast(str('qr_scan_failed'));
      }
      return 'failed';
    } finally {
      scanning = false;
    }
  }

  private toast(message: string): void {
    showToast(message, 2200);
  }
}
