import { describe, expect, it } from '@ohos/hypium';
import {
  isLocalWallpaperFile, localWallpaperFileName, localWallpaperWins
} from '../main/ets/util/localWallpaper';

export default function localWallpaperTest() {
  describe('localWallpaper', () => {
    // 深浅色各一张，互不覆盖。
    it('light_and_dark_are_separate_files', 0, (): void => {
      const l: string = localWallpaperFileName(false, 1000);
      const d: string = localWallpaperFileName(true, 1000);
      expect(l === d).assertFalse();
      expect(isLocalWallpaperFile(l)).assertTrue();
      expect(isLocalWallpaperFile(d)).assertTrue();
    });

    // 换图必须换路径：固定名会被 Image 的解码缓存卡住，屏幕上还是旧图。
    it('a_new_pick_gets_a_new_path', 0, (): void => {
      expect(localWallpaperFileName(false, 1000) === localWallpaperFileName(false, 2000))
        .assertFalse();
    });

    // 脏时间戳不能造出重名或带非法字符的文件名。
    it('bad_stamps_degrade_to_zero', 0, (): void => {
      expect(localWallpaperFileName(false, -5)).assertEqual('local_bg_light_0.jpg');
      expect(localWallpaperFileName(false, Number.NaN)).assertEqual('local_bg_light_0.jpg');
    });

    it('other_files_are_not_wallpapers', 0, (): void => {
      expect(isLocalWallpaperFile('avatar_1.jpg')).assertFalse();
      expect(isLocalWallpaperFile('')).assertFalse();
    });

    // 优先级：会话自己的背景压过本地壁纸；没有本地图时什么都不做。
    it('chat_specific_background_beats_local', 0, (): void => {
      expect(localWallpaperWins(true, '/data/x/local_bg_dark_1.jpg')).assertFalse();
    });

    it('local_wins_over_account_default', 0, (): void => {
      expect(localWallpaperWins(false, '/data/x/local_bg_dark_1.jpg')).assertTrue();
    });

    it('no_local_picture_means_no_override', 0, (): void => {
      expect(localWallpaperWins(false, '')).assertFalse();
    });
  });
}
