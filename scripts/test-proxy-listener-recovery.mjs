// Actual relay + accepted/outbound adapters over localhost SOCKS5 TCP.
// Inject only the platform's server-only accepted-client error notification.
import fs from 'node:fs';
import net from 'node:net';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {once} from 'node:events';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root=new URL('../entry/src/main/ets/',import.meta.url);
const source=['util/proxyCertificateName.ets','util/httpsProxyProtocol.ets','util/socksProxyProtocol.ets','services/HttpsProxyRelay.ets'].map(p=>
 fs.readFileSync(p==='services/HttpsProxyRelay.ets'&&process.env.RELAY_SOURCE?process.env.RELAY_SOURCE:new URL(p,root),'utf8').replace(/^import[\s\S]*?;\n/gm,'').replace(/\bexport /g,'')).join('\n');
const ab=b=>b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength);
const tick=()=>new Promise(r=>setImmediate(r));
async function until(predicate){for(let i=0;i<200;i++){if(predicate())return;await new Promise(r=>setTimeout(r,5));}assert.fail('condition timed out');}
const sockets=new Set();
class NativeSocket {
 constructor(s=new net.Socket()){
  this.s=s;sockets.add(s);s.on('close',()=>sockets.delete(s));this.handlers=new Map();this.silentClose=false;this.closes=0;
  s.on('data',b=>this.handlers.get('message')?.({message:ab(b)}));
  s.on('close',()=>{if(!this.silentClose)this.handlers.get('close')?.();});
  s.on('error',e=>this.handlers.get('error')?.(e));
 }
 on(k,f){this.handlers.set(k,f);}off(k){this.handlers.delete(k);}
 async bind(){}
 connect({address,timeout}){return new Promise((resolve,reject)=>{
  this.s.once('error',reject);this.s.setTimeout(timeout,()=>reject(Error('timeout')));
  this.s.connect({host:address.address,port:address.port,family:address.family===2?6:4},()=>{this.s.setTimeout(0);resolve();});
 });}
 send(arg){const data=arg.data??arg;return new Promise((resolve,reject)=>this.s.write(Buffer.from(data),e=>e?reject(e):resolve()));}
 async getState(){return {isBound:!this.s.destroyed,isClose:this.s.destroyed};}
 async getRemoteAddress(){if(this.s.destroyed||!this.s.remoteAddress)throw Error('client fd is invalid');return {address:this.s.remoteAddress,port:this.s.remotePort};}
 async close(){this.closes++;this.s.destroy();}
}
let latest;
class NativeServer {
 constructor(){this.handlers=new Map();this.clients=[];this.closes=0;this.s=net.createServer(s=>{
  const client=new NativeSocket(s);this.clients.push(client);this.handlers.get('connect')?.(client);
 });this.s.on('error',e=>this.handlers.get('error')?.(e));latest=this;}
 on(k,f){this.handlers.set(k,f);}off(k){this.handlers.delete(k);}
 async listen(a){this.s.listen(a.port,a.address);await once(this.s,'listening');}
 async getLocalAddress(){const a=this.s.address();return {address:a.address,port:a.port};}
 async getState(){return {isBound:this.s.listening,isClose:!this.s.listening};}
 async close(){this.closes++;this.s.close();}
 async failClientOnly(client){client.silentClose=true;client.s.destroy();await tick();this.handlers.get('error')?.({code:2303104});}
}
const ctx=vm.createContext({Uint8Array,ArrayBuffer,setTimeout,clearTimeout,
 stripIpv6Brackets:s=>s.replace(/^\[|\]$/g,''),resolvePreferIpv6:async()=>false,logW:()=>{},
 util:{TextEncoder:class{encodeInto(s){return new TextEncoder().encode(s);}},Base64Helper:class{encodeToStringSync(b){return Buffer.from(b).toString('base64');}}},
 socket:{constructTCPSocketInstance:()=>new NativeSocket(),constructTCPSocketServerInstance:()=>new NativeServer()}});
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Relay=HttpsProxyRelay;globalThis.marker=HTTPS_PROXY_MARKER;globalThis.retained=localRelayEndpoints;',
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const upstream=net.createServer(s=>{
 sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});let stage=0,q=Buffer.alloc(0);
 s.on('data',data=>{q=Buffer.concat([q,data]);
  while(q.length){
   if(stage===0){if(q.length<2||q.length<q[1]+2)return;const n=q[1]+2;q=q.subarray(n);s.write(Buffer.from([5,0]));stage=1;}
   else if(stage===1){if(q.length<5)return;assert.equal(q[3],3);const n=7+q[4];if(q.length<n)return;q=q.subarray(n);s.write(Buffer.from([5,0,0,1,127,0,0,1,0,80]));stage=2;}
   else{s.write(q);q=Buffer.alloc(0);}
  }
 });
});
let relay;let scenarioFailed=false;const peers=[];
try{
 upstream.listen(0,'127.0.0.1');await once(upstream,'listening');let restarts=0;
 relay=new ctx.Relay(()=>restarts++);
 const record={type:'proxyTypeSocks5',server:'127.0.0.1',port:upstream.address().port,username:'',password:'',key:'route',token:'secret'};
 relay.register(record);const port=await relay.start(),server=latest;
 const auth=Buffer.from(ctx.marker+record.key+':'+record.token).toString('base64');
 const request=`CONNECT dc.example:443 HTTP/1.1\r\nHost: dc.example:443\r\nProxy-Authorization: Basic ${auth}\r\n\r\n`;
 async function open(){const s=net.connect(port,'127.0.0.1');peers.push(s);s.on('error',()=>{});let data='';s.on('data',b=>data+=b.toString());await once(s,'connect');s.write(request);await until(()=>data.includes('200 Connection Established'));return {s,read:()=>data};}
 const main=await open();for(let i=0;i<31;i++)await open();assert.equal(relay.tunnels.size,32);
 // Saturation must not tear down established channels.
 const overflow=net.connect(port,'127.0.0.1');peers.push(overflow);overflow.on('error',()=>{});await once(overflow,'connect');const closed=new Promise(resolve=>overflow.once('close',resolve));overflow.write(request);await closed;
 assert.equal(relay.tunnels.size,32);assert.equal(server.closes,0);
 // Simulate a media channel failing while the home-page channel remains live.
 await server.failClientOnly(server.clients[1]);await until(()=>relay.tunnels.size!==32);
 assert.equal(relay.tunnels.size,31);assert.equal(server.closes,0);assert.equal(restarts,0);assert.equal(await relay.start(),port);
 main.s.write('main-after-chat-return');await until(()=>main.read().includes('main-after-chat-return'));
 const replacement=await open();replacement.s.write('replacement-works');await until(()=>replacement.read().includes('replacement-works'));
 assert.equal(relay.tunnels.size,32);assert.equal(restarts,0);
 // Repeated media channel removal/admission must not progressively fill slots.
 for(let i=0;i<12;i++){
  const latestLive=[...server.clients].reverse().find(c=>!c.s.destroyed);
  await server.failClientOnly(latestLive);await until(()=>relay.tunnels.size===31);await open();assert.equal(relay.tunnels.size,32);
 }
 main.s.write('main-still-alive');await until(()=>main.read().includes('main-still-alive'));
 console.log('Listener recovery: SOCKS5 handshake/echo, 32 active + overflow, server-only client failure, main continuity, 12 slot recovery cycles passed');
} catch(error){scenarioFailed=true;throw error;} finally {
 for(const s of peers)s.destroy();relay?.close();for(const s of sockets)s.destroy();upstream.close();
 if(!scenarioFailed)await until(()=>ctx.retained.size===0);
}
