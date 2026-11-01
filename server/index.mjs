import {pathToFileURL} from 'node:url';

// A dependency-free stdio bridge for Claude Desktop. No file or shell access.
// The remote endpoint is fixed; redirects cannot forward the credential elsewhere.
export function createBridge(token, request = fetch) {
  if (!/^vkh_[A-Za-z0-9_-]{43}$/.test(token ?? '')) throw new Error('Configure your Vekha key in extension settings.');
  let protocol;
  return async message => {
    if (!message || message.jsonrpc !== '2.0' || typeof message.method !== 'string') return undefined;
    const hasId = Object.hasOwn(message, 'id');
    try {
      const response = await request('https://vekha.synapsea.agency/api/v1/ai/mcp', {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45000),
        headers: {'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', Authorization: `Bearer ${token}`, ...(protocol ? {'MCP-Protocol-Version': protocol} : {})},
        body: JSON.stringify(message),
      });
      if (!response.ok) throw new Error(response.status === 401 ? 'Vekha key expired or revoked. Replace it in extension settings.' : response.status === 429 ? 'Vekha request limit reached. Try again shortly.' : 'Vekha is temporarily unavailable.');
      if (!hasId || response.status === 202 || response.status === 204) { await response.body?.cancel(); return undefined; }
      const reader = response.body.getReader(); let size = 0; const chunks = [];
      for (;;) { const {done, value} = await reader.read(); if (done) break; size += value.byteLength; if (size > 8 * 1024 * 1024) { await reader.cancel(); throw new Error('Vekha response too large. Read one day at a time.'); } chunks.push(value); }
      const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (data.id !== message.id) throw new Error('Invalid response.');
      if (message.method === 'initialize' && typeof data.result?.protocolVersion === 'string') protocol = data.result.protocolVersion;
      return data;
    } catch (error) {
      if (!hasId) return undefined;
      // Never echo provider bodies, input, headers, token or network stack traces.
      const safe = ['Vekha key expired or revoked. Replace it in extension settings.', 'Vekha request limit reached. Try again shortly.', 'Vekha response too large. Read one day at a time.'];
      return {jsonrpc: '2.0', id: message.id, error: {code: -32000, message: safe.includes(error?.message) ? error.message : 'Vekha is temporarily unavailable. Retry the same request; do not assume a write failed.'}};
    }
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let bridge;
  try { bridge = createBridge(process.env.VEKHA_API_KEY); } catch (e) { process.stderr.write(`${e.message}\n`); process.exit(1); }
  let buffer = '', queue = Promise.resolve(), queued = 0;
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => {
    buffer += chunk;
    if (Buffer.byteLength(buffer) > 512 * 1024) process.exit(1);
    for (;;) {
      const end = buffer.indexOf('\n'); if (end < 0) break;
      const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
      if (!line.trim()) continue;
      if (++queued > 32) process.exit(1);
      queue = queue.then(async () => {
        try { const result = await bridge(JSON.parse(line)); if (result) process.stdout.write(`${JSON.stringify(result)}\n`); } catch { process.stdout.write(`${JSON.stringify({jsonrpc:'2.0',id:null,error:{code:-32700,message:'Invalid JSON request'}})}\n`); }
        finally { queued--; }
      });
    }
  });
  process.stdin.on('end', () => { void queue.then(() => process.exit(0)); });
}
