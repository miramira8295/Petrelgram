import { describe, it, expect } from '@ohos/hypium';
import {
  VIDEO_POSTER_DIR, posterEligible, posterPathFor, posterSignature
} from '../main/ets/util/videoPoster';
import {
  DC_KIND_PHOTO, DC_KIND_VIDEO, DC_STATE_COMPLETE, DC_STATE_DOWNLOADING
} from '../main/ets/util/downloadCenterModel';

// 下载中心视频的首帧海报（2026-09-16）。
//
// 【为什么要自己生成】用户报「视频不显示缩略图」。DC 条目模型里根本没有缩略图：
// `preview` 是**来源消息摘要文本**，磁盘扫出来的条目连 fileId 都是 0（TDLib 没有
// 「路径 → fileId」接口），所以 mediaThumbChannel 那条通道也够不着。唯一的来源是
// 本地文件自己——用 util/livePhotoSave 里现成的 extractFirstFrame 抽首帧。
//
// 抽帧是解码，贵；所以文件名必须**完全由签名决定**，这样上次启动写下的那张这次
// 直接命中（配方与 util/chatBackgroundRaster 的 rasterPathFor 一致）。

export default function videoPosterTest() {
  describe('videoPoster', () => {
    it('same_input_same_signature', 0, () => {
      const a: string = posterSignature('/data/cache/videos/a.mp4', 1234, 1700);
      const b: string = posterSignature('/data/cache/videos/a.mp4', 1234, 1700);
      expect(a).assertEqual(b);
    });

    // 同名不同内容（重新下载、被覆盖）必须换一张海报：大小或修改时间任一不同即可。
    it('size_or_mtime_changes_the_signature', 0, () => {
      const base: string = posterSignature('/v/a.mp4', 1234, 1700);
      expect(posterSignature('/v/a.mp4', 9999, 1700) === base).assertFalse();
      expect(posterSignature('/v/a.mp4', 1234, 1800) === base).assertFalse();
      expect(posterSignature('/v/b.mp4', 1234, 1700) === base).assertFalse();
    });

    // 签名要能安全地当文件名：路径里有 / . 空格 中文，都不能漏进去。
    it('signature_is_filename_safe', 0, () => {
      const sig: string = posterSignature('/data/我的 视频/a b.mp4', 12, 34);
      expect(/^[A-Za-z0-9_]+$/.test(sig)).assertTrue();
    });

    it('poster_path_lives_in_its_own_dir', 0, () => {
      const sig: string = posterSignature('/v/a.mp4', 1, 2);
      expect(posterPathFor('/cache', sig)).assertEqual(`/cache/${VIDEO_POSTER_DIR}/${sig}.jpg`);
    });

    // 只给「完整的本地视频」抽帧：没下完的抽不出首帧，图片本身就是自己的缩略图。
    it('only_complete_local_videos_qualify', 0, () => {
      expect(posterEligible(DC_KIND_VIDEO, DC_STATE_COMPLETE, '/v/a.mp4')).assertTrue();
      expect(posterEligible(DC_KIND_VIDEO, DC_STATE_COMPLETE, '')).assertFalse();
      expect(posterEligible(DC_KIND_VIDEO, DC_STATE_DOWNLOADING, '/v/a.mp4')).assertFalse();
      expect(posterEligible(DC_KIND_PHOTO, DC_STATE_COMPLETE, '/p/a.jpg')).assertFalse();
    });
  });
}
