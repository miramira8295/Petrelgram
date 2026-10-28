// Exercise the real relay/handshake sources over actual localhost DNS + TCP.
// NetworkKit TCP and encoding are adapted to Node; empty encodeInto deliberately
// returns undefined as documented by HarmonyOS. Device routing/TLS still need
// device verification. Run with TYPESCRIPT_MODULE pointing to TypeScript if needed.
import fs from 'node:fs';
import net from 'node:net';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const base = new URL('../entry/src/main/ets/', import.meta.url);
const files = ['util/proxyCertificateName.ets', 'util/httpsProxyProtocol.ets', 'util/socksProxyProtocol.ets', 'services/HttpsProxyRelay.ets'];
const js = ts.transpileModule(files.map(p => fs.readFileSync(new URL(p, base), 'utf8').replace(/^import[\s\S]*?;\n/gm, '').replace(/\bexport /g, '')).join('\n') + '\nglobalThis.Tunnel=HttpsTunnel;', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const ab = b => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
let emptyEncodes = 0;
class Tcp {
    constructor() {
        this.s = new net.Socket();
        this.handlers = new Map();
        this.s.on('data', b => this.handlers.get('message')?.({ message: ab(b) }));
        this.s.on('close', () => this.handlers.get('close')?.());
        this.s.on('error', e => this.handlers.get('error')?.(e));
    }
    on(event, f) { this.handlers.set(event, f); }
    off(event) { this.handlers.delete(event); }
    async bind() { }
    connect({ address, timeout }) {
        assert.equal(address.address, 'localhost');
        return new Promise((resolve, reject) => {
            this.s.once('error', reject);
            this.s.setTimeout(timeout, () => reject(Error('timeout')));
            this.s.connect({ host: address.address, port: address.port, family: address.family === 2 ? 6 : 4 }, () => {
                this.s.setTimeout(0);
                resolve();
            });
        });
    }
    send({ data }) { return new Promise((resolve, reject) => this.s.write(Buffer.from(data), e => e ? reject(e) : resolve())); }
    async getState() { return {isBound:!this.s.destroyed,isClose:this.s.destroyed}; }
    async close() { this.s.destroy(); }
}
const env = vm.createContext({ Uint8Array, ArrayBuffer, setTimeout, clearTimeout, stripIpv6Brackets: s => s.replace(/^\[|\]$/g, ''),
    socket: { constructTCPSocketInstance: () => new Tcp() }, util: { TextEncoder: class {
            encodeInto(s) { if (s === '') {
                emptyEncodes++;
                return undefined;
            } return new TextEncoder().encode(s); }
        }, Base64Helper: class {
            encodeToStringSync(b) { return Buffer.from(b).toString('base64'); }
        } } });
vm.runInContext(js, env);
let count = 0;
for (const [type, user, password, method, httpOnly = false] of [
    ['proxyTypeSocks5', '', '', 0], ['proxyTypeSocks5', 'u', 'p', 0], ['proxyTypeSocks5', 'u', 'p', 2], ['proxyTypeSocks5', '用户', '密码🔑', 2], ['proxyTypeSocks5', 'u', '', 0], ['proxyTypeSocks5', '', 'p', 0],
    ['proxyTypeHttp', '', '', 0], ['proxyTypeHttp', 'u', 'p', 0], ['proxyTypeHttp', 'u', '', 0], ['proxyTypeHttp', '', 'p', 0], ['proxyTypeHttp', '用户', '密码🔑', 0], ['proxyTypeHttp', '', '', 0, true], ['proxyTypeHttp', 'u', 'p', 0, true]
]) {
    let doneResolve, doneReject;
    const done = new Promise((resolve, reject) => { doneResolve = resolve; doneReject = reject; });
    let stage = type === 'proxyTypeSocks5' ? 'method' : 'http', queue = Buffer.alloc(0), client;
    const server = net.createServer(s => {
        client = s;
        s.on('error', doneReject);
        s.on('data', b => {
            try {
                queue = Buffer.concat([queue, b]);
                while (queue.length) {
                    if (stage === 'method') {
                        if (queue.length < 2 || queue.length < 2 + queue[1])
                            return;
                        const n = 2 + queue[1];
                        assert.deepEqual([...queue.subarray(0, n)], user || password ? [5, 2, 0, 2] : [5, 1, 0]);
                        queue = queue.subarray(n);
                        stage = method === 2 ? 'auth' : 'connect';
                        s.write(Buffer.from([5, method]));
                    }
                    else if (stage === 'auth') {
                        if (queue.length < 2 || queue.length < 3 + queue[1])
                            return;
                        const n = 3 + queue[1] + queue[2 + queue[1]];
                        if (queue.length < n)
                            return;
                        assert.equal(queue.subarray(2, 2 + queue[1]).toString(), user);
                        assert.equal(queue.subarray(3 + queue[1], n).toString(), password);
                        queue = queue.subarray(n);
                        stage = 'connect';
                        s.write(Buffer.from([1, 0]));
                    }
                    else if (stage === 'connect') {
                        if (queue.length < 5)
                            return;
                        assert.equal(queue[3], 3);
                        const n = 7 + queue[4];
                        if (queue.length < n)
                            return;
                        assert.equal(queue.subarray(5, 5 + queue[4]).toString(), 'dc.example');
                        queue = queue.subarray(n);
                        stage = 'payload';
                        s.write(Buffer.concat([Buffer.from([5, 0, 0, 1, 127, 0, 0, 1, 0, 80]), Buffer.from('reply')]));
                    }
                    else if (stage === 'http') {
                        const end = queue.indexOf('\r\n\r\n');
                        if (end < 0)
                            return;
                        const head = queue.subarray(0, end).toString();
                        assert(head.startsWith(httpOnly ? 'POST HTTP://dc.example:80/api HTTP/1.1' : 'CONNECT dc.example:443 HTTP/1.1'));
                        if (user || password)
                            assert(head.includes('Proxy-Authorization: Basic ' + Buffer.from(user + ':' + password).toString('base64')));
                        else
                            assert(!head.includes('Authorization'));
                        assert(!head.includes('Basic local'));
                        queue = queue.subarray(end + 4);
                        stage = 'payload';
                        s.write('HTTP/1.1 200 OK\r\n\r\nreply');
                    }
                    else {
                        if (queue.length < 7)
                            return;
                        assert.equal(queue.toString(), 'payload');
                        queue = Buffer.alloc(0);
                        doneResolve();
                        return;
                    }
                }
            }
            catch (e) {
                doneReject(e);
            }
        });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    let replyResolve;
    const reply = new Promise(resolve => { replyResolve = resolve; });
    const local = {
        received: [],
        onData(f) { this.receive = f; },
        onEnd(f) { this.end = f; },
        async send(b) {
            this.received.push(Buffer.from(b));
            if (Buffer.concat(this.received).toString().endsWith('reply')) { replyResolve(); }
        },
        close() { }
    };
    const route = { key: 'test', type, server: 'localhost', port: server.address().port, username: user, password, httpOnly };
    const tunnel = new env.Tunnel(local, () => route, () => { }, () => { throw Error('unexpected TLS'); }, undefined, async () => false);
    let timer;
    try {
        tunnel.start();
        local.receive(ab(Buffer.from(httpOnly ? 'POST HTTP://dc.example:80/api HTTP/1.1\r\nProxy-Authorization: Basic local\r\nContent-Length: 7\r\n\r\npayload' : 'CONNECT dc.example:443 HTTP/1.1\r\nProxy-Authorization: Basic local\r\n\r\npayload')));
        await Promise.race([Promise.all([done, reply]), new Promise((_, reject) => {
            timer = setTimeout(() => reject(Error('network scenario timeout')), 3000);
        })]);
        assert(Buffer.concat(local.received).toString().endsWith('reply'));
        console.log('PASS', type, httpOnly ? 'HTTP-only' : 'tunnel', user || password ? (method === 0 ? 'saved credentials / no auth' : 'password auth') : 'empty credentials');
        count++;
    }
    finally {
        clearTimeout(timer);
        tunnel.close();
        client?.destroy();
        await new Promise(resolve => server.close(resolve));
    }
}
assert.equal(emptyEncodes, 0);
console.log(`Network relay: ${count} localhost DNS + TCP scenarios passed; empty encoder calls: ${emptyEncodes}`);
