import { describe, expect, it } from '@ohos/hypium';
import { DrawnFooterInput, placeDrawnFooter } from '../main/ets/util/drawnFooterPlacement';

function footerInput(): DrawnFooterInput {
  return { maxWidthPx: 280, bodyWidthPx: 200, bodyHeightPx: 40,
    lastLineRightPx: 60, lastLineTopPx: 20, chromeWidthPx: 0,
    footerWidthPx: 40, footerHeightPx: 12, gapPx: 8, bottomGapPx: 2 };
}

function rejectsFooterInput(input: DrawnFooterInput): boolean {
  try {
    placeDrawnFooter(input);
    return false;
  } catch (_error) {
    return true;
  }
}

export default function drawnFooterPlacementTest() {
  describe('DrawnFooterPlacement', () => {
    it('uses the remaining budget for time even when the body fills its natural width', 0, () => {
      const input = footerInput();
      input.bodyWidthPx = 120; input.bodyHeightPx = 20;
      input.lastLineRightPx = 120; input.lastLineTopPx = 0;
      const result = placeDrawnFooter(input);
      expect(result.widthPx).assertEqual(168);
      expect(result.inline).assertTrue();
      expect(result.footerYPx).assertEqual(6);
      expect(result.heightPx).assertEqual(20);
      expect(input.bodyWidthPx).assertEqual(120);
    });
    it('uses spare space beside the last line without changing the longest line width', 0, () => {
      const result = placeDrawnFooter(footerInput());
      expect(result.widthPx).assertEqual(200);
      expect(result.inline).assertTrue();
      expect(result.footerYPx).assertEqual(26);
      expect(result.heightPx).assertEqual(40);
    });
    it('accepts exact budget fit but moves a fractional overflow below', 0, () => {
      const input = footerInput();
      input.bodyWidthPx = 260; input.lastLineRightPx = 232;
      expect(placeDrawnFooter(input).inline).assertTrue();
      expect(placeDrawnFooter(input).widthPx).assertEqual(280);
      input.lastLineRightPx = 232.01;
      const result = placeDrawnFooter(input);
      expect(result.inline).assertFalse();
      expect(result.widthPx).assertEqual(260);
      expect(result.footerYPx).assertEqual(40);
      expect(result.heightPx).assertEqual(54);
    });
    it('a full-width last line never wraps or shrinks the body to make room for time', 0, () => {
      const input = footerInput();
      input.bodyWidthPx = 280; input.lastLineRightPx = 280;
      const result = placeDrawnFooter(input);
      expect(result.widthPx).assertEqual(280);
      expect(result.inline).assertFalse();
      expect(result.footerYPx).assertEqual(input.bodyHeightPx);
    });
    it('header or reply width can provide spare space without changing body metrics', 0, () => {
      const input = footerInput();
      input.bodyWidthPx = 120; input.bodyHeightPx = 20;
      input.lastLineRightPx = 120; input.lastLineTopPx = 0;
      input.chromeWidthPx = 180;
      const result = placeDrawnFooter(input);
      expect(result.widthPx).assertEqual(180);
      expect(result.inline).assertTrue();
      expect(result.heightPx).assertEqual(20);
      input.chromeWidthPx = 0;
      expect(placeDrawnFooter(input).inline).assertTrue();
      expect(placeDrawnFooter(input).widthPx).assertEqual(168);
    });
    it('a shorter body still reserves enough width for the time itself', 0, () => {
      const input = footerInput();
      input.bodyWidthPx = 10; input.bodyHeightPx = 20;
      input.lastLineRightPx = 10; input.lastLineTopPx = 0;
      input.maxWidthPx = 40;
      const result = placeDrawnFooter(input);
      expect(result.widthPx).assertEqual(40);
      expect(result.inline).assertFalse();
      expect(result.footerYPx).assertEqual(20);
    });
    it('a measured empty final line may contain the footer', 0, () => {
      const input = footerInput();
      input.lastLineRightPx = 0;
      const result = placeDrawnFooter(input);
      expect(result.inline).assertTrue();
      expect(result.footerYPx >= input.lastLineTopPx).assertTrue();
      expect(result.heightPx).assertEqual(40);
    });
    it('rounds natural widths up without exceeding a fractional width limit', 0, () => {
      const input = footerInput();
      input.bodyWidthPx = 199.2;
      expect(placeDrawnFooter(input).widthPx).assertEqual(200);
      input.maxWidthPx = 199.5;
      expect(placeDrawnFooter(input).widthPx).assertEqual(199.5);
      input.maxWidthPx = 280; input.chromeWidthPx = 280.00000000000006;
      expect(placeDrawnFooter(input).widthPx).assertEqual(280);
    });
    it('missing or invalid line metrics choose a separate footer instead of guessing', 0, () => {
      const inputs: DrawnFooterInput[] = [];
      const missingRight = footerInput(); missingRight.lastLineRightPx = Number.NaN; inputs.push(missingRight);
      const infiniteRight = footerInput(); infiniteRight.lastLineRightPx = Number.POSITIVE_INFINITY; inputs.push(infiniteRight);
      const negativeRight = footerInput(); negativeRight.lastLineRightPx = -1; inputs.push(negativeRight);
      const missingTop = footerInput(); missingTop.lastLineTopPx = Number.NaN; inputs.push(missingTop);
      const negativeTop = footerInput(); negativeTop.lastLineTopPx = -1; inputs.push(negativeTop);
      const outsideTop = footerInput(); outsideTop.lastLineTopPx = 40; inputs.push(outsideTop);
      for (const input of inputs) {
        const result = placeDrawnFooter(input);
        expect(result.inline).assertFalse();
        expect(result.footerYPx).assertEqual(input.bodyHeightPx);
        expect(result.heightPx).assertEqual(54);
      }
    });
    it('a tall footer extends below the final line without overlapping earlier lines', 0, () => {
      const input = footerInput();
      input.lastLineTopPx = 30; input.footerHeightPx = 24;
      const result = placeDrawnFooter(input);
      expect(result.inline).assertTrue();
      expect(result.footerYPx).assertEqual(30);
      expect(result.heightPx).assertEqual(56);
    });
    it('a tall emoji line keeps its body height when the footer fits beside it', 0, () => {
      const input = footerInput();
      input.bodyHeightPx = 72; input.lastLineTopPx = 20;
      const result = placeDrawnFooter(input);
      expect(result.inline).assertTrue();
      expect(result.footerYPx).assertEqual(58);
      expect(result.heightPx).assertEqual(72);
    });
    it('rejects invalid outer sizes and impossible footer or chrome widths', 0, () => {
      const inputs: DrawnFooterInput[] = [];
      const zeroMax = footerInput(); zeroMax.maxWidthPx = 0; inputs.push(zeroMax);
      const infiniteMax = footerInput(); infiniteMax.maxWidthPx = Number.POSITIVE_INFINITY; inputs.push(infiniteMax);
      const invalidBody = footerInput(); invalidBody.bodyWidthPx = Number.NaN; inputs.push(invalidBody);
      const negativeBody = footerInput(); negativeBody.bodyWidthPx = -1; inputs.push(negativeBody);
      const zeroHeight = footerInput(); zeroHeight.bodyHeightPx = 0; inputs.push(zeroHeight);
      const tooWideFooter = footerInput(); tooWideFooter.footerWidthPx = 281; inputs.push(tooWideFooter);
      const zeroFooter = footerInput(); zeroFooter.footerWidthPx = 0; inputs.push(zeroFooter);
      const invalidFooter = footerInput(); invalidFooter.footerHeightPx = Number.NaN; inputs.push(invalidFooter);
      const negativeFooter = footerInput(); negativeFooter.footerHeightPx = -1; inputs.push(negativeFooter);
      const tooWideChrome = footerInput(); tooWideChrome.chromeWidthPx = 281; inputs.push(tooWideChrome);
      const negativeChrome = footerInput(); negativeChrome.chromeWidthPx = -1; inputs.push(negativeChrome);
      const invalidGap = footerInput(); invalidGap.gapPx = Number.NaN; inputs.push(invalidGap);
      const negativeGap = footerInput(); negativeGap.gapPx = -1; inputs.push(negativeGap);
      const negativeBottom = footerInput(); negativeBottom.bottomGapPx = -1; inputs.push(negativeBottom);
      for (const input of inputs) { expect(rejectsFooterInput(input)).assertTrue(); }
    });
  });
}
