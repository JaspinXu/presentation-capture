import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const dataDirectory = await fsp.mkdtemp(path.join(os.tmpdir(), 'nus-upload-test-'));
process.env.NODE_ENV = 'test';
process.env.DATA_DIR = dataDirectory;
process.env.DEMO_TOKEN = 'test-token';
const { default: app } = await import('./src.js');
const server = app.listen(0, '127.0.0.1');
await new Promise((resolve) => server.once('listening', resolve));
const address = server.address();
const baseUrl = `http://127.0.0.1:${address.port}`;

test.after(async () => {
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  await fsp.rm(dataDirectory, { recursive: true, force: true });
});

test('accepts, resumes, and assembles a multipart video upload', async () => {
  const login = await fetch(`${baseUrl}/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ account: 'demo@nus.edu.sg', password: 'demo1234' }),
  });
  assert.equal(login.status, 200);

  const id = '2f4ba129-bd51-4d76-b43a-5978802b7cf4';
  const video = Buffer.from('continuous-presentation-video');
  const sha256 = crypto.createHash('sha256').update(video).digest('hex');
  const auth = { authorization: 'Bearer test-token' };

  const created = await fetch(`${baseUrl}/api/videos`, {
    method: 'POST',
    headers: { ...auth, 'content-type': 'application/json' },
    body: JSON.stringify({ id, fileSize: video.length, sha256 }),
  });
  assert.equal(created.status, 201);

  const initialized = await fetch(`${baseUrl}/api/videos/${id}/upload/init`, {
    method: 'POST',
    headers: { ...auth, 'content-type': 'application/json' },
    body: JSON.stringify({ partSize: 16, totalParts: 2 }),
  });
  assert.equal(initialized.status, 200);

  for (const [part, body] of [video.subarray(0, 16), video.subarray(16)].entries()) {
    const uploaded = await fetch(`${baseUrl}/api/videos/${id}/parts/${part}`, {
      method: 'PUT', headers: { ...auth, 'content-type': 'application/octet-stream' }, body,
    });
    assert.equal(uploaded.status, 201);
  }

  const parts = await fetch(`${baseUrl}/api/videos/${id}/parts`, { headers: auth });
  assert.deepEqual((await parts.json()).completedParts, [0, 1]);

  const completed = await fetch(`${baseUrl}/api/videos/${id}/upload/complete`, {
    method: 'POST',
    headers: { ...auth, 'content-type': 'application/json' },
    body: JSON.stringify({ totalParts: 2, sha256 }),
  });
  assert.equal(completed.status, 200);
  assert.deepEqual(await fsp.readFile(path.join(dataDirectory, id, 'final.mp4')), video);
});
