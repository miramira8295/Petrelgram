#!/usr/bin/env node
// Generate obfuscated (packed) build parameters for ApiCredentials.ets from a
// plaintext Telegram api_id / api_hash.
//
//   node scripts/gen-creds.mjs <api_id> <api_hash>
//
// Prints the three constants (_n / _r / _s) to paste into ApiCredentials.ets.
// This is lightweight obfuscation (rolling XOR keystream), not encryption — it
// only keeps the values from being lifted out of the package by string scanning.
// The matching decoder is entry/src/main/ets/tdkit/credCodec.ets.

const [, , idArg, hashArg] = process.argv;
if (idArg === undefined || hashArg === undefined) {
  console.error('Usage: node scripts/gen-creds.mjs <api_id> <api_hash>');
  process.exit(1);
}

const id = Number(idArg);
const hash = hashArg.trim();
if (!Number.isInteger(id) || id <= 0 || !/^[0-9a-fA-F]+$/.test(hash)) {
  console.error('api_id must be a positive integer and api_hash a hex string.');
  process.exit(1);
}

const nonce = Math.floor(Math.random() * 0x7fffffff);
const packed = (id ^ nonce) >>> 0;
let blob = '';
for (let k = 0; k < hash.length; k++) {
  const ks = (nonce + k * 131) & 0xff;
  const enc = (hash.charCodeAt(k) ^ ks) & 0xff;
  blob += enc.toString(16).padStart(2, '0');
}

console.log('// Paste these into ApiCredentials.ets:');
console.log(`const _n: number = ${nonce};`);
console.log(`const _r: number = ${packed};`);
console.log(`const _s: string = '${blob}';`);
