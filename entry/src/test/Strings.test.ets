import { describe, it, expect } from '@ohos/hypium';
import {
  installStrings, invalidateStringCache, paramStringCacheSize, plural, resetStrings, str, StringSource
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
    it('param_cache_is_bounded_and_evicts_oldest_first', 0, () => {
      const source = new CountingStrings();
      installStrings(source);
      for (let i = 0; i < 1024; i++) {
        str('n', i);
      }
      expect(paramStringCacheSize()).assertEqual(1024);
      expect(source.gets).assertEqual(1024);
      // 第 1025 条挤掉最老的 n(0)，其余仍命中。
      str('n', 1024);
      expect(paramStringCacheSize()).assertEqual(1024);
      str('n', 1);
      expect(source.gets).assertEqual(1025);
      str('n', 0);
      expect(source.gets).assertEqual(1026);
      expect(str('n', 0)).assertEqual('1:n:0');
    });

    it('param_cache_keeps_adjacent_args_apart_and_clears_on_locale', 0, () => {
      const source = new CountingStrings();
      installStrings(source);
      expect(str('k', 'a', 'bc')).assertEqual('1:k:a,bc');
      expect(str('k', 'ab', 'c')).assertEqual('1:k:ab,c');
      expect(source.gets).assertEqual(2);
      source.generation = 2;
      invalidateStringCache();
      expect(str('k', 'a', 'bc')).assertEqual('2:k:a,bc');
      expect(paramStringCacheSize()).assertEqual(1);
    });

    it('caches_only_static_labels_and_invalidates_with_locale', 0, () => {
      const source = new CountingStrings();
      installStrings(source);
      expect(str('title')).assertEqual('1:title:');
      expect(str('title')).assertEqual('1:title:');
      expect(source.gets).assertEqual(1);

      // 带参数的现在也缓存：同 key 同参数第二次不再回源。
      str('welcome', 'Alice');
      str('welcome', 'Alice');
      expect(source.gets).assertEqual(2);
      // 参数不同是不同的条目。
      str('welcome', 'Bob');
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
