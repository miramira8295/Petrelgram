import abilityTest from './Ability.test';
import tdBridgeTest from './TdBridge.test';
import tdClientLocalTestOnDevice from './TdClientLocal.test';

export default function testsuite() {
  abilityTest();
  tdBridgeTest();
  tdClientLocalTestOnDevice();
}
