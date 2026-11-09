import { describe, expect, it } from '@ohos/hypium';
import { contactNameKey, compareContactNames } from '../main/ets/util/contactAlphabet';

function unchanged(text: string): string { return text; }
export default function contactAlphabetTest() {
  describe('ContactAlphabet', (): void => {
    it('latin_is_case_insensitive', 0, (): void => {
      expect(contactNameKey('  alice  ', unchanged).letter).assertEqual('A');
      expect(contactNameKey('ALICE', unchanged).value).assertEqual('ALICE');
    });
    it('chinese_uses_transliterated_initial', 0, (): void => {
      const key = contactNameKey('张三', (_text: string): string => 'zhang san');
      expect(key.letter).assertEqual('Z'); expect(key.value).assertEqual('ZHANG SAN');
    });
    it('accent_conversion_uses_ascii_initial', 0, (): void => {
      expect(contactNameKey('Émile', (_text: string): string => 'Emile').letter).assertEqual('E');
    });
    it('empty_name_goes_to_hash', 0, (): void => {
      expect(contactNameKey('  ', unchanged).letter).assertEqual('#');
    });
    it('numbers_and_symbols_go_to_hash', 0, (): void => {
      expect(contactNameKey('123', unchanged).letter).assertEqual('#');
      expect(contactNameKey('😀 Alice', unchanged).letter).assertEqual('#');
      expect(contactNameKey('_Bob', unchanged).letter).assertEqual('#');
    });
    it('native_failure_keeps_original', 0, (): void => {
      const key = contactNameKey('王五', (_text: string): string => { throw new Error('unavailable'); });
      expect(key.letter).assertEqual('#'); expect(key.value).assertEqual('王五');
    });
    it('other_scripts_can_use_transliteration', 0, (): void => {
      expect(contactNameKey('Анна', (_text: string): string => 'Anna').letter).assertEqual('A');
    });
    it('hash_follows_letters', 0, (): void => {
      expect(compareContactNames(contactNameKey('123', unchanged), contactNameKey('Zoe', unchanged), 1, 2) > 0).assertTrue();
    });
    it('equal_names_have_stable_id_order', 0, (): void => {
      const a = contactNameKey('Alice', unchanged); const b = contactNameKey('alice', unchanged);
      expect(compareContactNames(a, b, 7, 9) < 0).assertTrue();
      expect(compareContactNames(a, b, 7, 7)).assertEqual(0);
    });
    it('compares_full_name_inside_section', 0, (): void => {
      expect(compareContactNames(contactNameKey('Amy', unchanged), contactNameKey('Alice', unchanged), 1, 2) > 0).assertTrue();
    });
  });
}
