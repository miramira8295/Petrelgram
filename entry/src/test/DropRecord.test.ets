import { describe, expect, it } from '@ohos/hypium';
import { normalizeDropRecord } from '../main/ets/util/dropRecord';
import { itemOf } from '../main/ets/util/sharedContent';

export default function dropRecordTest() {
  describe('DropRecord', (): void => {
    it('modern_file_uri_uses_original_uri_and_media_type', 0, (): void => {
      const record = normalizeDropRecord('general.file-uri', '', { oriUri: 'file://media/photo.jpg', fileType: 'general.jpeg' });
      expect(record.uri).assertEqual('file://media/photo.jpg');
      expect(itemOf(record)?.kind).assertEqual('image');
    });
    it('file_uri_without_type_is_document', 0, (): void => {
      const record = normalizeDropRecord('general.file-uri', '', { oriUri: 'file://docs/report.pdf' });
      expect(record.utd).assertEqual('general.file'); expect(itemOf(record)?.kind).assertEqual('file');
    });
    it('legacy_image_reads_image_uri', 0, (): void => {
      expect(normalizeDropRecord('general.image', 'general.image', { imageUri: 'file://image' }).uri).assertEqual('file://image');
    });
    it('legacy_video_reads_video_uri', 0, (): void => {
      expect(normalizeDropRecord('general.video', 'general.video', { videoUri: 'file://video' }).uri).assertEqual('file://video');
    });
    it('legacy_audio_reads_audio_uri', 0, (): void => {
      expect(normalizeDropRecord('general.audio', 'general.audio', { audioUri: 'file://audio' }).uri).assertEqual('file://audio');
    });
    it('legacy_file_keeps_uri', 0, (): void => {
      expect(normalizeDropRecord('general.file', 'general.file', { uri: 'file://document' }).uri).assertEqual('file://document');
    });
    it('text_link_and_html_keep_textual_payload', 0, (): void => {
      expect(normalizeDropRecord('general.plain-text', '', { textContent: 'hello' }).content).assertEqual('hello');
      expect(normalizeDropRecord('general.hyperlink', '', { url: 'https://example.com' }).content).assertEqual('https://example.com');
      expect(normalizeDropRecord('general.html', '', { plainContent: 'plain' }).content).assertEqual('plain');
    });
    it('empty_uri_is_not_mistaken_for_text', 0, (): void => {
      expect(itemOf(normalizeDropRecord('general.file-uri', '', {})) === null).assertTrue();
    });
  });
}
