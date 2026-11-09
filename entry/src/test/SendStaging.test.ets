import { describe, it, expect } from '@ohos/hypium';
import {
  SEND_STAGING_DIR, SHARE_STAGING_DIR, STAGING_TTL_MS, expiredStagingDirs,
  flatStagedPath, stagedFilePath, stagingDirName, stagingStampOf
} from '../main/ets/util/sendStaging';

export default function sendStagingTest() {
  describe('sendStaging', () => {
    // 这一条就是本次修复的全部意义：发出去的文件名 = 用户自己那份文件的名字。
    // TDLib 的 document.file_name 取的是本地文件 basename（同一条事实支撑着
    // util/livePhoto 的 PGLIVE_ 约定），所以去重只能放在**目录**上。
    it('keeps_the_picked_file_name_verbatim', 0, () => {
      expect(stagedFilePath('/cache', SEND_STAGING_DIR, 1700, 3, '财务报表.xlsx'))
        .assertEqual('/cache/send/1700_3/财务报表.xlsx');
      expect(stagedFilePath('/cache', SHARE_STAGING_DIR, 1700, 1, 'IMG_0042.jpg'))
        .assertEqual('/cache/share/1700_1/IMG_0042.jpg');
    });

    // 一次选九张就是同一毫秒九个文件：序号仍要把它们分开，只是分在目录上。
    it('same_millisecond_picks_land_in_different_dirs', 0, () => {
      const first: string = stagedFilePath('/cache', SEND_STAGING_DIR, 1700, 1, 'a.jpg');
      const second: string = stagedFilePath('/cache', SEND_STAGING_DIR, 1700, 2, 'a.jpg');
      expect(first === second).assertFalse();
      expect(stagingDirName(1700, 2)).assertEqual('1700_2');
    });

    // 建目录失败时的退路：名字难看，但一定发得出去。
    it('flat_fallback_still_disambiguates', 0, () => {
      expect(flatStagedPath('/cache', SEND_STAGING_DIR, 1700, 3, 'a.mp4'))
        .assertEqual('/cache/send_1700_3_a.mp4');
    });

    it('reads_the_timestamp_back_out_of_a_dir_name', 0, () => {
      expect(stagingStampOf('1700_3')).assertEqual(1700);
      expect(stagingStampOf('1700')).assertEqual(-1);
      expect(stagingStampOf('junk_3')).assertEqual(-1);
      expect(stagingStampOf('')).assertEqual(-1);
    });

    // 清理只认自己写出来的目录名。认不出来的一律不动——cacheDir 是公共地界，
    // 删别人的东西比留一坨垃圾严重得多。
    it('expires_only_its_own_old_dirs', 0, () => {
      const names: string[] = ['1000_1', '9000_1', 'junk', 'chatbg_x.jpg'];
      const out: string[] = expiredStagingDirs(names, 9000, 1000);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('1000_1');
    });

    // 刚写下的那一份绝不能被同一次清理扫掉。
    it('never_expires_the_batch_being_written', 0, () => {
      expect(expiredStagingDirs(['9000_1'], 9000, 1000).length).assertEqual(0);
    });

    // TTL 不能短：TDLib 是从这个路径上传的，发送失败后用户还可能重试。
    it('ttl_outlives_an_upload', 0, () => {
      expect(STAGING_TTL_MS >= 60 * 60 * 1000).assertTrue();
    });
  });
}
