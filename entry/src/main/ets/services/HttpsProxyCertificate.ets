import { cert } from '@kit.DeviceCertificateKit';
import { socket } from '@kit.NetworkKit';
import { proxyDnsNameMatches, proxyGeneralNameDer, proxyIpBytes } from '../util/proxyCertificateName';

export async function verifyProxyCertificateName(tls: socket.TLSSocket, host: string): Promise<void> {
  // The TLS handshake verifies the chain. Independently enforce endpoint identity before
  // sending CONNECT/authentication, rather than depending on platform-version differences.
  const certificate = await cert.createX509Cert(await tls.getRemoteCertificate());
  const ip = proxyIpBytes(host);
  if (ip !== undefined) {
    if (certificate.match({ subjectAlternativeNames: [{ type: cert.GeneralNameType.GENERAL_NAME_TYPE_IP_ADDRESS,
      name: proxyGeneralNameDer(0x87, ip) }], matchAllSubjectAltNames: false })) { return; }
  } else if (host.indexOf(':') < 0 && !/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    for (const bytes of certificate.getSubjectAltNames().data) {
      // This API includes a trailing NUL and may erase SAN types. Recheck the exact typed
      // DER value with match() so a URI SAN or embedded-NUL name cannot impersonate DNS.
      const length = bytes.length > 0 && bytes[bytes.length - 1] === 0 ? bytes.length - 1 : bytes.length;
      if (length === 0 || length > 253) { continue; }
      let name = '';
      for (let i = 0; i < length; i++) { name += String.fromCharCode(bytes[i]); }
      if (proxyDnsNameMatches(host, name) && certificate.match({
        subjectAlternativeNames: [{ type: cert.GeneralNameType.GENERAL_NAME_TYPE_DNS_NAME,
          name: proxyGeneralNameDer(0x82, bytes.slice(0, length)) }], matchAllSubjectAltNames: false
      })) { return; }
    }
  }
  throw new Error('proxy certificate hostname mismatch');
}
