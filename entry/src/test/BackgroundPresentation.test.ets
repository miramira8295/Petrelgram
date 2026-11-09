import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  backgroundPreviewOf, backgroundThumbnailFile, fillColorsOf, intToHexColor
} from '../main/ets/util/backgroundPresentation';

function fillSolid(color: number): TdObject {
  return { '@type': 'backgroundFillSolid', 'color': color } as TdObject;
}

function background(type: TdObject, id: string = '100'): TdObject {
  const value: TdObject = { '@type': 'background' };
  value['id'] = id;
  value['name'] = 'test';
  value['is_dark'] = false;
  value['type'] = type;
  return value;
}

export default function backgroundPresentationTest() {
  describe('BackgroundPresentation', (): void => {
    it('formats_int_colors_as_hex', 0, (): void => {
      expect(intToHexColor(0xFF0000)).assertEqual('#FF0000');
      expect(intToHexColor(0x00FF7F)).assertEqual('#00FF7F');
      expect(intToHexColor(5)).assertEqual('#000005');
    });
    it('maps_solid_fill_to_single_color', 0, (): void => {
      expect(fillColorsOf(fillSolid(0x336699)).join(',')).assertEqual('#336699');
    });
    it('maps_gradient_fill_to_two_colors', 0, (): void => {
      const fill: TdObject = { '@type': 'backgroundFillGradient' };
      fill['top_color'] = 0x111111;
      fill['bottom_color'] = 0x222222;
      expect(fillColorsOf(fill).join(',')).assertEqual('#111111,#222222');
    });
    it('maps_freeform_fill_to_all_colors', 0, (): void => {
      const fill: TdObject = { '@type': 'backgroundFillFreeformGradient' };
      fill['colors'] = [0xAA0000, 0x00BB00, 0x0000CC];
      expect(fillColorsOf(fill).join(',')).assertEqual('#AA0000,#00BB00,#0000CC');
    });
    it('previews_fill_background_with_colors_and_angle', 0, (): void => {
      const type: TdObject = { '@type': 'backgroundTypeFill' };
      const fill: TdObject = { '@type': 'backgroundFillGradient' };
      fill['top_color'] = 0x111111;
      fill['bottom_color'] = 0x222222;
      fill['rotation_angle'] = 45;
      type['fill'] = fill;
      const preview = backgroundPreviewOf(background(type, '42'));
      expect(preview !== null).assertTrue();
      expect(preview?.backgroundId).assertEqual('42');
      expect(preview?.kind).assertEqual('fill');
      expect(preview?.colors.length).assertEqual(2);
      expect(preview?.angle).assertEqual(45);
    });
    it('previews_pattern_background_with_underlying_fill', 0, (): void => {
      const type: TdObject = { '@type': 'backgroundTypePattern' };
      type['fill'] = fillSolid(0x336699);
      const preview = backgroundPreviewOf(background(type));
      expect(preview?.kind).assertEqual('pattern');
      expect(preview?.colors.join(',')).assertEqual('#336699');
    });
    it('previews_photo_wallpaper_without_colors', 0, (): void => {
      const type: TdObject = { '@type': 'backgroundTypeWallpaper' };
      const preview = backgroundPreviewOf(background(type));
      expect(preview?.kind).assertEqual('wallpaper');
      expect(preview?.colors.length).assertEqual(0);
    });
    it('extracts_document_thumbnail_file', 0, (): void => {
      const file: TdObject = { '@type': 'file' };
      file['id'] = 77;
      const thumbnail: TdObject = { '@type': 'thumbnail' };
      thumbnail['file'] = file;
      const document: TdObject = { '@type': 'document' };
      document['thumbnail'] = thumbnail;
      const value: TdObject = { '@type': 'background' };
      value['document'] = document;
      const extracted = backgroundThumbnailFile(value);
      expect(extracted !== null).assertTrue();
      expect((extracted?.['id'] as number)).assertEqual(77);
    });
    it('returns_null_thumbnail_for_fill_background', 0, (): void => {
      const value: TdObject = { '@type': 'background' };
      expect(backgroundThumbnailFile(value) === null).assertTrue();
    });
    it('rejects_background_without_type', 0, (): void => {
      const value: TdObject = { '@type': 'background' };
      value['id'] = '9';
      expect(backgroundPreviewOf(value) === null).assertTrue();
    });
  });
}
