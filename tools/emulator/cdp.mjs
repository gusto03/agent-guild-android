// Evaluates a JavaScript expression in the page of a debuggable WebView and prints the result as JSON.
// Usage: node tools/emulator/cdp.mjs <local port> <expression>
// First forward the WebView's DevTools socket, for example:
//   adb forward tcp:9333 localabstract:webview_devtools_remote_<pid>
const [port, expression] = process.argv.slice(2);
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const page = targets.find((target) => target.type === 'page');
if (!page) throw new Error('No WebView page is open.');
const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve) => socket.addEventListener('open', resolve, { once: true }));
socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, awaitPromise: true, returnByValue: true } }));
const reply = await new Promise((resolve) => socket.addEventListener('message', (event) => {
  const data = JSON.parse(event.data);
  if (data.id === 1) resolve(data);
}));
console.log(JSON.stringify(reply.result?.result?.value ?? reply.result ?? reply.error));
socket.close();
