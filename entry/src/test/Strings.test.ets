import { describe, it, expect } from '@ohos/hypium';
import {
  installStrings, invalidateStringCache, plural, resetStrings, str, StringSource
} from '../main/ets/util/strings';

class CountingStrings implements StringSource {
  gets: number = 0;
  plurals: number = 0;
  generation: number = 1;

  get(key: string, args: Array<string | number>): string {
    this.gets++;
    return `${this.generation}:${key}:${args.join(',')}`;
  }

  plural(key: string, count: number, args: Array<string | number>): string {
    this.plurals++;
    return `${this.generation}:${key}:${count}:${args.join(',')}`;
  }
}

export default function stringsTest() {
  describe('Strings', () => {
    it('caches_only_static_labels_and_invalidates_with_locale', 0, () => {
      const source = new CountingStrings();
      installStrings(source);
      expect(str('title')).assertEqual('1:title:');
      expect(str('title')).assertEqual('1:title:');
      expect(source.gets).assertEqual(1);

      str('welcome', 'Alice');
      str('welcome', 'Alice');
      expect(source.gets).assertEqual(3);
      plural('members', 2, 2);
      plural('members', 2, 2);
      expect(source.plurals).assertEqual(2);

      source.generation = 2;
      invalidateStringCache();
      expect(str('title')).assertEqual('2:title:');
      expect(source.gets).assertEqual(4);
      resetStrings();
    });
  });
}
