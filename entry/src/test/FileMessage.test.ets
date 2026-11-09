import { describe, it, expect } from '@ohos/hypium';
import {
  displayFileName, fileExtension, fileOpenMimeType, fileStatusText, fileTypeVisual
} from '../main/ets/util/fileMessage';

export default function fileMessageTest() {
  describe('fileMessage', () => {
    it('classifies_common_document_types', 0, () => {
      expect(fileTypeVisual('manual.pdf', '').label).assertEqual('PDF');
      expect(fileTypeVisual('brief.docx', '').label).assertEqual('DOC');
      expect(fileTypeVisual('budget.xlsx', '').label).assertEqual('XLS');
      expect(fileTypeVisual('slides.pptx', '').label).assertEqual('PPT');
      expect(fileTypeVisual('source.zip', '').label).assertEqual('ZIP');
      expect(fileTypeVisual('main.ets', '').label).assertEqual('CODE');
    });
    it('falls_back_to_mime_and_safe_generic_labels', 0, () => {
      expect(fileExtension('', 'application/pdf')).assertEqual('pdf');
      expect(fileTypeVisual('', 'audio/ogg').label).assertEqual('AUDIO');
      expect(fileTypeVisual('backup.xyz', '').label).assertEqual('XYZ');
      expect(fileTypeVisual('', '').label).assertEqual('FILE');
      expect(displayFileName('')).assertEqual('file_unnamed');
      expect(fileOpenMimeType('manual.pdf', '')).assertEqual('application/pdf');
      expect(fileOpenMimeType('voice.mp3', 'application/octet-stream')).assertEqual('audio/mpeg');
      expect(fileOpenMimeType('anything.bin', 'application/x-custom'))
        .assertEqual('application/x-custom');
    });
    it('describes_every_download_state', 0, () => {
      expect(fileStatusText(0, '', 0, false, 0, false)).assertEqual('file_unavailable');
      expect(fileStatusText(7, '', 0, false, 0, false))
        .assertEqual('file_tap_download(file_unknown_size)');
      expect(fileStatusText(7, '', 1024, true, 0, false))
        .assertEqual('file_downloading(size_kb(1.0))');
      expect(fileStatusText(7, '', 1024, true, 53, false))
        .assertEqual('file_downloading_pct(size_kb(1.0),53)');
      expect(fileStatusText(7, '', 1024, false, 0, true))
        .assertEqual('file_download_failed');
      expect(fileStatusText(7, '/data/a.bin', 1024, false, 100, false))
        .assertEqual('file_tap_open(size_kb(1.0))');
    });
    // 出站文件（issue #201 第 6 条）：本地路径一直在，靠 uploading 区分"发送中"
    // 和"发完"；百分比复用 progress 形参（通道里此时装的是上传进度）。
    it('describes_upload_states', 0, () => {
      expect(fileStatusText(7, '/data/a.bin', 1024, false, 0, false, true))
        .assertEqual('file_uploading(size_kb(1.0))');
      expect(fileStatusText(7, '/data/a.bin', 1024, false, 45, false, true))
        .assertEqual('file_uploading_pct(size_kb(1.0),45)');
      // 上传结束后（uploading=false）回到"点击打开"，不会卡在上传态。
      expect(fileStatusText(7, '/data/a.bin', 1024, false, 100, false, false))
        .assertEqual('file_tap_open(size_kb(1.0))');
    });
  });
}
