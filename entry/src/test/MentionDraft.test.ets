import { describe, it, expect } from '@ohos/hypium';
import { appendMention, mentionToken, mentionQueryOf } from '../main/ets/util/mentionDraft';

export default function mentionDraftTest() {
  describe('mentionDraft', () => {
    it('prefers the public username', 0, () => {
      expect(mentionToken('Alice Smith', 'alice')).assertEqual('@alice');
    });

    it('falls back to the display name when there is no username', 0, () => {
      expect(mentionToken('Alice Smith', '')).assertEqual('Alice Smith');
    });

    it('yields nothing when neither name nor username is known', 0, () => {
      expect(mentionToken('', '')).assertEqual('');
      expect(mentionToken('   ', '')).assertEqual('');
    });

    it('appends to an empty draft with a trailing space', 0, () => {
      expect(appendMention('', '@alice')).assertEqual('@alice ');
    });

    it('inserts a separating space when the draft has none', 0, () => {
      expect(appendMention('hi', '@alice')).assertEqual('hi @alice ');
    });

    it('reuses the draft\'s existing trailing space', 0, () => {
      expect(appendMention('hi ', '@alice')).assertEqual('hi @alice ');
    });

    it('keeps a trailing newline as the separator', 0, () => {
      expect(appendMention('hi\n', '@alice')).assertEqual('hi\n@alice ');
    });

    it('is a no-op when the same mention already trails the draft', 0, () => {
      expect(appendMention('hi @alice ', '@alice')).assertEqual('hi @alice ');
      expect(appendMention('hi @alice', '@alice')).assertEqual('hi @alice ');
    });

    it('still appends when the trailing token only shares a prefix', 0, () => {
      expect(appendMention('hi @alicia ', '@alice')).assertEqual('hi @alicia @alice ');
    });

    it('appends the same mention again once other text follows it', 0, () => {
      expect(appendMention('@alice hey', '@alice')).assertEqual('@alice hey @alice ');
    });

    it('handles display names containing spaces', 0, () => {
      expect(appendMention('hi', 'Alice Smith')).assertEqual('hi Alice Smith ');
      expect(appendMention('hi Alice Smith ', 'Alice Smith')).assertEqual('hi Alice Smith ');
    });

    it('leaves the draft untouched for an empty token', 0, () => {
      expect(appendMention('hi', '')).assertEqual('hi');
      expect(appendMention('', '')).assertEqual('');
    });

    // issue #95：@ 之后只认 ASCII，中文名根本触发不了候选面板。
    // 后端 searchChatMembers 本来就按名字匹配，卡的一直是客户端这个判定。
    it('accepts_non_ascii_names_after_at', 0, () => {
      expect(mentionQueryOf('@张')).assertEqual('张');
      expect(mentionQueryOf('@张三')).assertEqual('张三');
      expect(mentionQueryOf('嗨 @小明')).assertEqual('小明');
    });

    it('still_accepts_usernames_and_bare_at', 0, () => {
      expect(mentionQueryOf('@')).assertEqual('');
      expect(mentionQueryOf('@abc_1')).assertEqual('abc_1');
      expect(mentionQueryOf('hi @abc')).assertEqual('abc');
    });

    // @ 必须在开头或空格之后，否则邮箱地址会被当成提及。
    it('ignores_an_at_inside_a_word', 0, () => {
      expect(mentionQueryOf('a@b')).assertNull();
      expect(mentionQueryOf('mail@example.com')).assertNull();
    });

    // 后面又打了空格就不再是"正在输入的提及"，面板该收起来。
    it('ends_at_whitespace', 0, () => {
      expect(mentionQueryOf('@abc def')).assertNull();
      expect(mentionQueryOf('@张三 ')).assertNull();
    });

    // 第二个 @ 不该被吞进查询里。
    it('does_not_swallow_a_second_at', 0, () => {
      expect(mentionQueryOf('@ab@')).assertNull();
    });

    it('returns_null_without_an_at', 0, () => {
      expect(mentionQueryOf('')).assertNull();
      expect(mentionQueryOf('hello')).assertNull();
    });
  });
}
