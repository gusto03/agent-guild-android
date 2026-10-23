// A DNS forwarder for the emulator on 127.0.0.1:53: names under ts.net go to Tailscale's MagicDNS resolver,
// everything else to a public resolver. The emulator does not resolve tailnet names by itself, and pointing
// its -dns-server at 100.100.100.100 directly breaks every lookup. start.ps1 -Tailnet runs this.
import dgram from 'node:dgram';

const MAGIC_DNS = '100.100.100.100';
const PUBLIC = '1.1.1.1';
// The wire form of a name's last labels: "ts", "net", root.
const TAILNET = Buffer.from([2, 0x74, 0x73, 3, 0x6e, 0x65, 0x74, 0]);

const server = dgram.createSocket('udp4');
server.on('message', (query, client) => {
  const upstream = dgram.createSocket('udp4');
  const timer = setTimeout(() => upstream.close(), 5000);
  upstream.on('message', (answer) => {
    clearTimeout(timer);
    server.send(answer, client.port, client.address);
    upstream.close();
  });
  upstream.send(query, 53, query.includes(TAILNET) ? MAGIC_DNS : PUBLIC);
});
server.bind(53, '127.0.0.1', () => console.log(`127.0.0.1:53 forwards ts.net to ${MAGIC_DNS} and other names to ${PUBLIC}`));
