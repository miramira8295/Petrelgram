import { describe, expect, it } from '@ohos/hypium';
import { animationShapeRejected } from '../main/ets/util/animationShape';

export default function animationShapeTest() {
  describe('animationShapeRejected', () => {
    it('形状类报错要认出来', 0, (): void => {
      expect(animationShapeRejected('Unknown class "inputAnimation"')).assertTrue();
      expect(animationShapeRejected('InputFile is not specified')).assertTrue();
      expect(animationShapeRejected('Unexpected field "animation"')).assertTrue();
    });
    it('别的失败不重试', 0, (): void => {
      expect(animationShapeRejected('CHAT_WRITE_FORBIDDEN')).assertFalse();
      expect(animationShapeRejected('Request timeout')).assertFalse();
      expect(animationShapeRejected('')).assertFalse();
    });
  });
}
