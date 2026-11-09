import { describe, expect, it } from '@ohos/hypium';
import {
  StatsRow, VideoStatsSnapshot, emptyVideoStats, formatBitrate, formatBytes, hdrLabel, videoStatsRows
} from '../main/ets/util/videoStats';

function rowValue(rows: StatsRow[], label: string): string {
  const r: StatsRow | undefined = rows.find((x: StatsRow): boolean => x.label === label);
  return r !== undefined ? r.value : '<missing>';
}

const JSON_4K: string = '{"format":"mov,mp4,m4a,3gp,3g2,mj2","duration_ms":83000,"bitrate":12345678,' +
  '"video":{"codec":"hevc","decoder":"hevc_ohcodec","profile":"Main 10","level":150,"width":3840,' +
  '"height":1632,"pix_fmt":"yuv420p10le","bit_depth":10,"fps":59.94,"bitrate":11800000,' +
  '"color_primaries":"bt2020","color_trc":"smpte2084","color_space":"bt2020nc","color_range":"tv"},' +
  '"audio":{"codec":"aac","decoder":"aac","profile":"LC","sample_rate":48000,"channels":2,' +
  '"layout":"stereo","sample_fmt":"fltp","bitrate":128000}}';

export default function videoStatsTest() {
  describe('videoStats', () => {
    it('码率与字节的单位', 0, (): void => {
      expect(formatBitrate(128000)).assertEqual('128 kbps');
      expect(formatBitrate(11800000)).assertEqual('11.8 Mbps');
      expect(formatBitrate(0)).assertEqual('—');
      expect(formatBytes(4_300_000)).assertEqual('4.1 MB');
      expect(formatBytes(900)).assertEqual('900 B');
    });

    it('HDR 判定：PQ / HLG / 其余 SDR', 0, (): void => {
      expect(hdrLabel('smpte2084')).assertEqual('HDR10 (PQ)');
      expect(hdrLabel('arib-std-b67')).assertEqual('HLG');
      expect(hdrLabel('bt709')).assertEqual('SDR');
      expect(hdrLabel('')).assertEqual('SDR');
    });

    it('4K HEVC 10-bit 硬解的一组行', 0, (): void => {
      const s: VideoStatsSnapshot = emptyVideoStats();
      s.statsJson = JSON_4K;
      s.decoderKind = 2;
      s.outputFps = 59.9;
      s.decodeFps = 60;
      const rows: StatsRow[] = videoStatsRows(s);
      expect(rowValue(rows, 'Decoder')).assertEqual('hevc_ohcodec · Hardware');
      expect(rowValue(rows, 'Codecs')).assertEqual('hevc (Main 10, L5.0) / aac (LC)');
      expect(rowValue(rows, 'Resolution')).assertEqual('3840x1632 @ 59.94 fps');
      expect(rowValue(rows, 'Color')).assertEqual('HDR10 (PQ) · bt2020 / smpte2084 / tv');
      expect(rowValue(rows, 'Pixel format')).assertEqual('yuv420p10le · 10-bit');
      expect(rowValue(rows, 'Audio')).assertEqual('48 kHz · stereo · fltp · 128 kbps');
    });

    it('统计 JSON 坏了或还没有：不崩，只少几行', 0, (): void => {
      const s: VideoStatsSnapshot = emptyVideoStats();
      s.statsJson = '{oops';
      const rows: StatsRow[] = videoStatsRows(s);
      expect(rowValue(rows, 'Codecs')).assertEqual('<missing>');
      expect(rowValue(rows, 'Frames') !== '<missing>').assertTrue();
    });
  });
}
