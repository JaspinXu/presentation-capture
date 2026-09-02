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

test('accepts, resumes, and assembles video, audio, and presentation assets', async () => {
  const login = await fetch(`${baseUrl}/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ account: 'demo@nus.edu.sg', password: 'demo1234' }),
  });
  assert.equal(login.status, 200);

  const id = '2f4ba129-bd51-4d76-b43a-5978802b7cf4';
  const video = Buffer.concat([
    Buffer.alloc(1024, 7),
    Buffer.from('continuous-presentation-video'),
  ]);
  const sha256 = crypto.createHash('sha256').update(video).digest('hex');
  const audio = Buffer.from('presentation-audio-track');
  const presentation = Buffer.from('%PDF-presentation');
  const assets = {
    video: { fileName: 'capture.mp4', fileSize: video.length, sha256 },
    audio: {
      fileName: 'audio.wav',
      fileSize: audio.length,
      sha256: crypto.createHash('sha256').update(audio).digest('hex'),
    },
    presentation: {
      fileName: 'slides.pdf',
      fileSize: presentation.length,
      sha256: crypto.createHash('sha256').update(presentation).digest('hex'),
    },
  };
  const auth = { authorization: 'Bearer test-token' };

  const created = await fetch(`${baseUrl}/api/videos`, {
    method: 'POST',
    headers: { ...auth, 'content-type': 'application/json' },
    body: JSON.stringify({ id, fileSize: video.length, sha256, assets }),
  });
  assert.equal(created.status, 201);

  async function uploadAsset(type, body, partSize) {
    const totalParts = Math.ceil(body.length / partSize);
    const initialized = await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/upload/init`, {
      method: 'POST',
      headers: { ...auth, 'content-type': 'application/json' },
      body: JSON.stringify({
        uploadSessionId: `${id}:${type}`,
        partSize,
        totalParts,
        fileSize: body.length,
      }),
    });
    assert.equal(initialized.status, 200);
    for (let part = 0; part < totalParts; part += 1) {
      const chunk = body.subarray(part * partSize, (part + 1) * partSize);
      const uploaded = await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/parts/${part}`, {
        method: 'PUT',
        headers: {
          ...auth,
          'content-type': 'application/octet-stream',
          'x-part-sha256': crypto.createHash('sha256').update(chunk).digest('hex'),
        },
        body: chunk,
      });
      assert.equal(uploaded.status, 201);
    }
    const parts = await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/parts`, { headers: auth });
    assert.deepEqual((await parts.json()).completedParts, [...Array(totalParts).keys()]);
    const completed = await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/upload/complete`, {
      method: 'POST',
      headers: { ...auth, 'content-type': 'application/json' },
      body: JSON.stringify({ totalParts, sha256: assets[type].sha256 }),
    });
    assert.equal(completed.status, 200);
    const completedAgain = await fetch(`${baseUrl}/api/videos/${id}/assets/${type}/upload/complete`, {
      method: 'POST',
      headers: { ...auth, 'content-type': 'application/json' },
      body: JSON.stringify({ totalParts, sha256: assets[type].sha256 }),
    });
    assert.equal(completedAgain.status, 200);
  }

  await Promise.all([
    uploadAsset('video', video, 1024),
    uploadAsset('audio', audio, 1024),
    uploadAsset('presentation', presentation, 1024),
  ]);
  assert.deepEqual(await fsp.readFile(path.join(dataDirectory, id, 'final.mp4')), video);
  assert.deepEqual(await fsp.readFile(path.join(dataDirectory, id, 'audio.wav')), audio);
  assert.deepEqual(await fsp.readFile(path.join(dataDirectory, id, 'presentation.pdf')), presentation);
  assert.equal((await (await fetch(`${baseUrl}/api/videos/${id}/status`, { headers: auth })).json()).status, 'uploaded');
});

test('does not accept social tokens when the provider is unconfigured', async () => {
  const response = await fetch(`${baseUrl}/api/auth/social`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ provider: 'google', idToken: 'not-a-real-token' }),
  });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, 'google_not_configured');
});

test('rejects audio assets that are not WAV files', async () => {
  const body = Buffer.from('asset');
  const hash = crypto.createHash('sha256').update(body).digest('hex');
  const response = await fetch(`${baseUrl}/api/videos`, {
    method: 'POST',
    headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
    body: JSON.stringify({
      id: '36f6f381-3d91-4a46-97ac-511ed2056424',
      assets: {
        video: { fileName: 'final.mp4', fileSize: body.length, sha256: hash },
        audio: { fileName: 'audio.m4a', fileSize: body.length, sha256: hash },
        presentation: { fileName: 'slides.pdf', fileSize: body.length, sha256: hash },
      },
    }),
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, 'invalid_audio_type');
});
