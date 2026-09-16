import { describe, expect, it } from '@ohos/hypium';
import {
  DOWNLOAD_DIR_CANCELLED, DOWNLOAD_DIR_CHANGED, DOWNLOAD_DIR_EMPTY, DOWNLOAD_DIR_UNSUPPORTED, downloadDirToast
} from '../main/ets/util/downloadDirOutcome';

// 「默认下载路径」点完之后该不该弹提示。2026-09-16（「有些人点了没反应」）。
export default function downloadDirOutcomeTest() {
  describe('downloadDirOutcome', () => {
    it('选成功报「已修改」，用户自己取消不弹', 0, (): void => {
      expect(downloadDirToast(DOWNLOAD_DIR_CHANGED)).assertEqual('ds_download_path_changed');
      expect(downloadDirToast(DOWNLOAD_DIR_CANCELLED)).assertEqual('');
    });

    it('选择器回空或不可用都要明说不支持——这两条以前是静默的', 0, (): void => {
      expect(downloadDirToast(DOWNLOAD_DIR_EMPTY)).assertEqual('ds_download_picker_unsupported');
      expect(downloadDirToast(DOWNLOAD_DIR_UNSUPPORTED)).assertEqual('ds_download_picker_unsupported');
    });

    it('没认出来的状态也要弹一句，别让点击落空', 0, (): void => {
      expect(downloadDirToast('')).assertEqual('media_cannot_open_location');
      expect(downloadDirToast('whatever')).assertEqual('media_cannot_open_location');
    });
  });
}
