import { describe, expect, it } from '@ohos/hypium';
import { adminLabelOf } from '../main/ets/util/adminLabel';

export default function adminLabelTest() {
  describe('adminLabel', () => {
    it('有自定义头衔就用头衔', 0, () => {
      expect(adminLabelOf(true, '打工皇帝')).assertEqual('打工皇帝');
      expect(adminLabelOf(false, '值班')).assertEqual('值班');
    });

    it('没有头衔时按身份给默认词', 0, () => {
      expect(adminLabelOf(true, '')).assertEqual('ga_creator');
      expect(adminLabelOf(false, '')).assertEqual('ga_admin');
    });

    it('全是空白的头衔当作没有', 0, () => {
      // 服务端允许把头衔设成空格串，直接用会显示成一枚空标签。
      expect(adminLabelOf(false, '   ')).assertEqual('ga_admin');
      expect(adminLabelOf(true, '  ')).assertEqual('ga_creator');
    });

    it('头衔两端的空白要去掉', 0, () => {
      expect(adminLabelOf(false, '  值班  ')).assertEqual('值班');
    });
  });
}
