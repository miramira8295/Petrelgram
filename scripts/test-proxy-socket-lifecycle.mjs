// Exercises real ArkTS relay adapters with controllable NetworkKit boundaries.
// This verifies ordering/ownership, not the device's native scheduler or heap.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const root = new URL('../entry/src/main/ets/', import.meta.url);
const sources = ['util/httpsProxyProtocol.ets', 'util/socksProxyProtocol.ets', 'services/HttpsProxyRelay.ets'];
const code = sources.map(p => fs.readFileSync(p === 'services/HttpsProxyRelay.ets' && process.env.RELAY_SOURCE ? process.env.RELAY_SOURCE : new URL(p, root), 'utf8')
  .replace(/^import[\s\S]*?;\n/gm, '').replace(/\bexport /g, '')).join('\n') +
  '\nglobalThis.subject = { LocalRelayEndpoint, TcpRelayEndpoint, TlsRelayEndpoint, HttpsProxyRelay, retained: localRelayEndpoints };';
const settle = async () => { for (let i = 0; i < 40; i++) await Promise.resolve(); };
const barrier = () => { let resolve; const promise = new Promise(r => resolve = r); return {promise, resolve}; };
class FakeSocket {
  listeners = new Map(); closes = 0; closeRequested = false;
  bindBarrier; connectBarrier; sendBarrier; stateBarrier;
  fdAlive=true; bound=true; receiverReady=false; probes=0;
  on(event, callback) { this.listeners.set(event, callback); }
  off(event) { this.listeners.delete(event); }
  async bind() { await this.bindBarrier; }
  async connect() { await this.connectBarrier; }
  async send() { await this.sendBarrier; }
  async getState() { await this.stateBarrier; return {isBound:this.bound,isClose:!this.fdAlive}; }
  async getRemoteAddress() { this.probes++; if(!this.fdAlive)throw Error("client fd is invalid");return {address:"127.0.0.1",port:12345}; }
  async close() { this.closes++; this.closeRequested = true; this.fdAlive=false; }
  emit(event, value) { if(event==='message')this.receiverReady=true;this.listeners.get(event)?.(value); }
  nativeClose() {
    // Deliberately acknowledge close() before letting ClientHandler run.
    // The old rejected path had no message listener at this point.
    assert(this.listeners.has('message'), 'native receiver lost its message gate');
    this.fdAlive=false;this.emit('close');
  }
}
class FakeServer extends FakeSocket {
  async listen() {}
  async getLocalAddress() { return {address: '127.0.0.1', port: 12345}; }
}
let nextSocket, latestServer;
const warnings = [];
const env = vm.createContext({ Uint8Array, ArrayBuffer, setTimeout, clearTimeout,
  stripIpv6Brackets: s => s.replace(/^\[|\]$/g, ''), resolvePreferIpv6: async () => false,
  verifyProxyCertificateName: async () => {}, logW: text => warnings.push(text),
  util: { TextEncoder, Base64Helper: class { encodeToStringSync(b) { return Buffer.from(b).toString('base64'); } } },
  socket: {
    constructTCPSocketInstance: () => nextSocket,
    constructTLSSocketInstance: () => nextSocket,
    constructTCPSocketServerInstance: () => latestServer = new FakeServer(),
    Protocol: {TLSv12: 'TLSv12', TLSv13: 'TLSv13'}
  }
});
vm.runInContext(ts.transpileModule(code, {compilerOptions: {target: ts.ScriptTarget.ES2020}}).outputText, env);
const {LocalRelayEndpoint, TcpRelayEndpoint, TlsRelayEndpoint, HttpsProxyRelay, retained} = env.subject;
let count = 0;
const test = async (name, run) => { await run(); assert.equal(retained.size, 0, 'unretired local endpoints'); console.log('PASS', name); count++; };
await test('early rejection cannot erase fd before the native receiver reads its map entry', async () => {
  const s = new FakeSocket(), e = new LocalRelayEndpoint(s);
  e.close(); e.close(); await settle();
  assert.equal(s.closes, 0); assert.equal(retained.size, 1);
  assert(s.listeners.has('message')); assert(s.listeners.has('close'));
  s.emit('message',{message:new ArrayBuffer(1)});await settle();
  assert.equal(s.closes,1);assert.equal(retained.size,1);
  s.nativeClose(); assert.equal(s.listeners.size, 0);
});
await test('peer close ends business exactly once without closing native twice', async () => {
  const s = new FakeSocket(), e = new LocalRelayEndpoint(s); let ends = 0;
  e.onEnd(() => { ends++; e.close(); });
  s.nativeClose(); s.emit('close');
  assert.equal(ends, 1); assert.equal(s.closes, 0);
});
await test('error stops forwarding and drains through native close', async () => {
  const s = new FakeSocket(), e = new LocalRelayEndpoint(s); let ends = 0, messages = 0;
  e.onEnd(() => { ends++; e.close(); }); e.onData(() => messages++);
  s.emit('error'); s.emit('error'); s.emit('message', {message: new ArrayBuffer(1)});
  assert.equal(ends, 1); assert.equal(messages, 0); assert.equal(s.closes, 1);
  await assert.rejects(e.send(new ArrayBuffer(1))); s.nativeClose();
});
await test('32 business tunnels survive 1000 rejected connections; rejected clients retire', async () => {
  const relay = new HttpsProxyRelay(); await relay.start(); const server = latestServer;
  const active = Array.from({length: 32}, () => new FakeSocket());
  active.forEach(s => server.emit('connect', s));
  for (let i = 0; i < 1000; i++) {
    const s = new FakeSocket(); server.emit('connect', s);
    assert.equal(s.closes, 0);s.emit('message',{message:new ArrayBuffer(1)});await settle();
    assert.equal(s.closes, 1);s.nativeClose();
  }
  assert.equal(relay.tunnels.size, 32); assert.equal(retained.size, 32);
  active.forEach(s => assert.equal(s.closes, 0));
  relay.close(); active.forEach(s => s.nativeClose());
});
await test('listener replacement safely drains late accept without attaching to new generation', async () => {
  const relay = new HttpsProxyRelay(); await relay.start(); const old = latestServer;
  old.fdAlive=false;old.emit('error');await settle();await relay.start(); const current = latestServer;
  assert.notEqual(old, current); assert(old.listeners.has('connect'));
  const late = new FakeSocket(); old.emit('connect', late);
  assert.equal(late.closes, 0);late.emit('message',{message:new ArrayBuffer(1)});
  assert.equal(late.closes,1);assert.equal(relay.tunnels.size, 0);late.nativeClose();
  const live = new FakeSocket(); current.emit('connect', live); assert.equal(live.closes, 0);
  relay.close(); live.nativeClose();
});
await test('late accept after entire relay closes still initializes and retires native client', async () => {
  const relay = new HttpsProxyRelay(); await relay.start(); const server = latestServer;
  relay.close(); const late = new FakeSocket(); server.emit('connect', late);
  assert.equal(late.closes, 0);late.emit('message',{message:new ArrayBuffer(1)});
  assert.equal(late.closes,1);late.nativeClose();
});
for (const Adapter of [TcpRelayEndpoint, TlsRelayEndpoint]) {
  for (const phase of ['bind', 'connect', 'send']) {
    await test(`${Adapter.name} reclaims late ${phase} completion after cancellation`, async () => {
      const s = new FakeSocket(); nextSocket = s; const gate = barrier();
      s[`${phase}Barrier`] = gate.promise;
      const e = new Adapter();
      const pending = phase === 'bind' ? e.bind(1) : phase === 'send' ? e.send(new ArrayBuffer(1)) : e.connect('proxy.example', 1080, 1, 15000);
      e.close();e.close();assert.equal(s.closes,0);
      gate.resolve();await pending;await settle();assert.equal(s.closes,1);
      e.close();assert.equal(s.closes,1);
      await assert.rejects(e.bind(1)); await assert.rejects(e.connect('proxy.example', 1080, 1, 15000));
    });
  }
}
await test('closed-before-data client can retire on peer close without ever calling close',async()=>{
 const s=new FakeSocket(),e=new LocalRelayEndpoint(s);e.close();s.nativeClose();assert.equal(s.closes,0);
});
await test('local cancellation waits for an in-flight send',async()=>{
 const s=new FakeSocket(),e=new LocalRelayEndpoint(s);s.emit('message',{message:new ArrayBuffer(1)});
 const gate=barrier();s.sendBarrier=gate.promise;const pending=e.send(new ArrayBuffer(1));e.close();assert.equal(s.closes,0);
 gate.resolve();await pending;assert.equal(s.closes,1);s.nativeClose();
});
await test('accepted-client server error frees only dead slots and preserves listener and other tunnels',async()=>{
 let restarted=0;const relay=new HttpsProxyRelay(()=>restarted++);const port=await relay.start();const server=latestServer;
 const healthy=new FakeSocket(),dead=new FakeSocket();server.emit('connect',healthy);server.emit('connect',dead);
 // Native RecvInErrorCondition removes the client and reports on the server;
 // no client close callback is required for this path.
 dead.fdAlive=false;server.emit('error');await settle();
 assert.equal(restarted,0);assert.equal(server.closes,0);assert.equal(healthy.closes,0);
 assert.equal(relay.tunnels.size,1);assert.equal(retained.size,1);assert.equal(dead.closes,0);assert.equal(await relay.start(),port);
 const next=new FakeSocket();server.emit('connect',next);assert.equal(relay.tunnels.size,2);
 relay.close();healthy.nativeClose();next.nativeClose();
});
await test('full capacity audit recovers slots whose native close event was lost',async()=>{
 const relay=new HttpsProxyRelay();await relay.start();const server=latestServer;
 const active=Array.from({length:32},()=>new FakeSocket());active.forEach(s=>server.emit('connect',s));
 active[0].fdAlive=false;const rejected=new FakeSocket();server.emit('connect',rejected);await settle();
 assert.equal(relay.tunnels.size,31);rejected.nativeClose();
 const replacement=new FakeSocket();server.emit('connect',replacement);assert.equal(replacement.closes,0);assert.equal(relay.tunnels.size,32);
 relay.close();active.slice(1).forEach(s=>s.nativeClose());replacement.nativeClose();
});
await test('stale listener state completion cannot restart a replacement or closed runtime',async()=>{
 let restarted=0;const relay=new HttpsProxyRelay(()=>restarted++);await relay.start();const server=latestServer;
 const gate=barrier();server.stateBarrier=gate.promise;server.emit('error');relay.close();gate.resolve();await settle();assert.equal(restarted,0);
});
for(const Adapter of [TcpRelayEndpoint,TlsRelayEndpoint]){
 await test(`${Adapter.name} never closes an untouched or already dead native socket`,async()=>{
  let s=new FakeSocket();nextSocket=s;let e=new Adapter();e.close();await settle();assert.equal(s.closes,0);
  s=new FakeSocket();nextSocket=s;e=new Adapter();await e.bind(1);s.fdAlive=false;e.close();await settle();assert.equal(s.closes,0);
 });
 await test(`${Adapter.name} bind rejection cleans up once after completion`,async()=>{
  const s=new FakeSocket();s.bind=async()=>{throw Error('bind failed');};nextSocket=s;const e=new Adapter();
  await assert.rejects(e.bind(1));e.close();e.close();await settle();assert.equal(s.closes,1);
 });
}
console.log(`Socket lifecycle: ${count}/${count} scenarios passed; device native cleanup still requires verification.`);
