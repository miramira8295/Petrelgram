import { describe, expect, it } from '@ohos/hypium';
import { DrawnSenderRoleBinding } from '../main/ets/util/drawnSenderRoleBinding';
import { clearSenderRoles, publishSenderRole, senderRoleKey } from '../main/ets/util/senderRoleChannel';

export default function drawnSenderRoleBindingTest() {
  describe('DrawnSenderRoleBinding', () => {
    it('seeds a previously received role before the first draw', 0, () => {
      const binding = new DrawnSenderRoleBinding();
      publishSenderRole(senderRoleKey(-901, 1), 'admin');
      expect(binding.attach(-901, 1, (_label: string): void => {})).assertEqual('admin');
      binding.detach(); clearSenderRoles(-901);
    });
    it('receives a late role without replacing the message', 0, () => {
      const binding = new DrawnSenderRoleBinding();
      let label: string = '';
      binding.attach(-902, 1, (next: string): void => { label = next; });
      publishSenderRole(senderRoleKey(-902, 1), 'owner');
      expect(label).assertEqual('owner');
      binding.detach(); clearSenderRoles(-902);
    });
    it('keeps the same user in two groups isolated during reuse', 0, () => {
      const binding = new DrawnSenderRoleBinding();
      let label: string = '';
      const changed = (next: string): void => { label = next; };
      binding.attach(-903, 1, changed);
      label = binding.attach(-904, 1, changed);
      publishSenderRole(senderRoleKey(-903, 1), 'wrong group');
      expect(label).assertEqual('');
      publishSenderRole(senderRoleKey(-904, 1), 'right group');
      expect(label).assertEqual('right group');
      binding.detach(); clearSenderRoles(-903); clearSenderRoles(-904);
    });
    it('unsubscribes the previous sender on row rebind', 0, () => {
      const binding = new DrawnSenderRoleBinding();
      let label: string = '';
      const changed = (next: string): void => { label = next; };
      binding.attach(-905, 1, changed);
      label = binding.attach(-905, 2, changed);
      publishSenderRole(senderRoleKey(-905, 1), 'previous');
      expect(label).assertEqual('');
      publishSenderRole(senderRoleKey(-905, 2), 'current');
      expect(label).assertEqual('current');
      binding.detach(); clearSenderRoles(-905);
    });
    it('same-key reattach seeds state without duplicate notifications', 0, () => {
      const binding = new DrawnSenderRoleBinding();
      let calls: number = 0;
      const changed = (_label: string): void => { calls++; };
      binding.attach(-906, 1, changed);
      publishSenderRole(senderRoleKey(-906, 1), 'one');
      expect(binding.attach(-906, 1, changed)).assertEqual('one');
      publishSenderRole(senderRoleKey(-906, 1), 'two');
      expect(calls).assertEqual(2);
      binding.detach(); clearSenderRoles(-906);
    });
    it('recycle detaches and reuse seeds the current role', 0, () => {
      const binding = new DrawnSenderRoleBinding();
      let calls: number = 0;
      const changed = (_label: string): void => { calls++; };
      binding.attach(-907, 1, changed);
      binding.detach(); binding.detach();
      publishSenderRole(senderRoleKey(-907, 1), 'after recycle');
      expect(calls).assertEqual(0);
      expect(binding.attach(-907, 1, changed)).assertEqual('after recycle');
      clearSenderRoles(-907);
      expect(calls).assertEqual(1);
      binding.detach();
    });
  });
}
