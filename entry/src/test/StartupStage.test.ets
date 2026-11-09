import { describe, expect, it } from '@ohos/hypium';
import { AuthStage } from '../main/ets/tdkit/AuthService';
import { isStartupStage } from '../main/ets/util/startupStage';

export default function startupStageTest() {
  describe('startupStage', () => {
    it('Init 就是启动画面那一段', 0, () => {
      expect(isStartupStage(AuthStage.Init, false)).assertTrue();
    });

    it('切账号不算启动画面', 0, () => {
      // 切账号时 stage 也会被打回 Init（bindAuthService 那一行），但那时窗口
      // 已经在前台、系统启动窗早就没了。这时候铺一张全屏启动图是错的。
      expect(isStartupStage(AuthStage.Init, true)).assertFalse();
    });

    it('所有有界面的阶段都不算', 0, () => {
      const staged: AuthStage[] = [
        AuthStage.WaitPhone, AuthStage.WaitQrCode, AuthStage.WaitCode,
        AuthStage.WaitPassword, AuthStage.WaitRegistration,
        AuthStage.Ready, AuthStage.LoggedOut
      ];
      for (let i = 0; i < staged.length; i++) {
        expect(isStartupStage(staged[i], false)).assertFalse();
      }
    });

    it('切账号时这些阶段也一样不算', 0, () => {
      expect(isStartupStage(AuthStage.Ready, true)).assertFalse();
      expect(isStartupStage(AuthStage.WaitPhone, true)).assertFalse();
    });
  });
}
