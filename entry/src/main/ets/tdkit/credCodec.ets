// Decoder for packed build parameters embedded at compile time.
//
// This is intentionally lightweight obfuscation — a rolling XOR keystream keyed
// by a per-build nonce — NOT cryptography. Its only purpose is to keep embedded
// identifiers from being lifted out of the packaged app by trivial string
// scanning; a determined reverse-engineer can still recover them. Regenerate the
// packed values with scripts/gen-creds.mjs.
export interface RuntimeEnv {
  id: number;
  token: string;
}

// Undo the pack: `rev` is the id XOR-masked with the nonce; `sig` is the token
// hex-encoded after a per-position XOR keystream derived from the same nonce.
export function decodeEnv(nonce: number, rev: number, sig: string): RuntimeEnv {
  const id = (rev ^ nonce) >>> 0;
  let token = '';
  for (let k = 0; k < sig.length; k += 2) {
    const byte = parseInt(sig.substring(k, k + 2), 16);
    const ks = (nonce + (k / 2) * 131) & 0xFF;
    token += String.fromCharCode((byte ^ ks) & 0xFF);
  }
  return { id, token };
}
