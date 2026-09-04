import crypto from 'node:crypto';

const baseUrl = process.env.SMOKE_BASE_URL ?? 'http://127.0.0.1:8080';
const authSecret = process.env.AUTH_SECRET;
if (!authSecret) throw new Error('AUTH_SECRET is required');

function sessionToken() {
  const body = Buffer.from(JSON.stringify({
    userId: 'deployment-smoke-test',
    expiresAt: Date.now() + 300_000,
  })).toString('base64url');
  const signature = crypto.createHmac('sha256', authSecret).update(body).digest('base64url');
  return `${body}.${signature}`;
}

function silentWav() {
  const sampleRate = 48_000;
  const sampleCount = 4_800;
  const dataSize = sampleCount * 2;
  const wav = Buffer.alloc(44 + dataSize);
  wav.write('RIFF', 0);
  wav.writeUInt32LE(36 + dataSize, 4);
  wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write('data', 36);
  wav.writeUInt32LE(dataSize, 40);
  return wav;
}

const id = crypto.randomUUID();
const files = {
  video: {
    fileName: 'smoke.mp4',
    body: Buffer.concat([
      Buffer.from('000000186674797069736f6d0000020069736f6d6d703431', 'hex'),
      Buffer.alloc(1024),
    ]),
  },
  audio: { fileName: 'smoke.wav', body: silentWav() },
  presentation: {
    fileName: 'smoke.pdf',
    body: Buffer.from('%PDF-1.4\n% presentation-capture deployment smoke test\n%%EOF\n'),
  },
};
const assets = Object.fromEntries(Object.entries(files).map(([type, file]) => [
  type,
  {
    fileName: file.fileName,
    fileSize: file.body.length,
    sha256: crypto.createHash('sha256').update(file.body).digest('hex'),
  },
]));
const headers = { authorization: `Bearer ${sessionToken()}` };

async function expect(response, expected, operation) {
  if (response.status !== expected) {
    throw new Error(`${operation} failed (${response.status}): ${await response.text()}`);
  }
  return response;
}

await expect(await fetch(`${baseUrl}/api/videos`, {
  method: 'POST',
  headers: { ...headers, 'content-type': 'application/json' },
  body: JSON.stringify({ id, title: 'Production deployment smoke test', assets }),
}), 201, 'create bundle');

for (const [type, file] of Object.entries(files)) {
  await expect(await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/upload/init`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify({
      uploadSessionId: `${id}:${type}`,
      partSize: 1024,
      totalParts: Math.ceil(file.body.length / 1024),
      fileSize: file.body.length,
    }),
  }), 200, `initialize ${type}`);

  for (let part = 0; part < Math.ceil(file.body.length / 1024); part += 1) {
    const chunk = file.body.subarray(part * 1024, (part + 1) * 1024);
    await expect(await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/parts/${part}`, {
      method: 'PUT',
      headers: {
        ...headers,
        'content-type': 'application/octet-stream',
        'x-part-sha256': crypto.createHash('sha256').update(chunk).digest('hex'),
      },
      body: chunk,
    }), 201, `upload ${type} part ${part}`);
  }

  await expect(await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/upload/complete`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify({
      totalParts: Math.ceil(file.body.length / 1024),
      sha256: assets[type].sha256,
    }),
  }), 200, `complete ${type}`);
}

const status = await expect(
  await fetch(`${baseUrl}/api/videos/${id}/status`, { headers }),
  200,
  'read bundle status',
);
console.log(JSON.stringify({ id, ...(await status.json()), assets }, null, 2));
