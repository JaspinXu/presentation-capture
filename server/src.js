import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import express from 'express';
import cors from 'cors';
import { createRemoteJWKSet, jwtVerify } from 'jose';

const app = express();
const port = Number(process.env.PORT ?? 8080);
const dataRoot = path.resolve(process.env.DATA_DIR ?? './data');
const demoAccount = process.env.DEMO_ACCOUNT ?? 'demo@nus.edu.sg';
const demoPassword = process.env.DEMO_PASSWORD ?? 'demo1234';
const demoToken = process.env.DEMO_TOKEN ?? 'nus-demo-token-change-me';
const demoLoginEnabled = (process.env.ENABLE_DEMO_LOGIN ?? 'true') === 'true';
const authSecret = process.env.AUTH_SECRET ?? 'change-this-auth-secret-before-deployment';
const googleClientIds = (process.env.GOOGLE_CLIENT_IDS ?? '').split(',').map((value) => value.trim()).filter(Boolean);
const appleClientIds = (process.env.APPLE_CLIENT_IDS ?? '').split(',').map((value) => value.trim()).filter(Boolean);
const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

await fsp.mkdir(dataRoot, { recursive: true });
app.use(cors());
app.use(express.json({ limit: '1mb' }));

function requireAuth(req, res, next) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (token === demoToken) {
    req.userId = 'demo-user';
    return next();
  }
  const payload = verifySessionToken(token);
  if (!payload) return res.status(401).json({ error: 'unauthorized' });
  req.userId = payload.userId;
  return next();
}

function issueSessionToken(userId) {
  const body = Buffer.from(JSON.stringify({
    userId,
    expiresAt: Date.now() + (30 * 24 * 60 * 60 * 1000),
  })).toString('base64url');
  const signature = crypto.createHmac('sha256', authSecret).update(body).digest('base64url');
  return `${body}.${signature}`;
}

function verifySessionToken(token) {
  if (!token || !token.includes('.')) return null;
  const [body, signature] = token.split('.');
  const expected = crypto.createHmac('sha256', authSecret).update(body).digest('base64url');
  if (signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    return payload.expiresAt > Date.now() && typeof payload.userId === 'string' ? payload : null;
  } catch {
    return null;
  }
}

function videoDirectory(id) {
  if (!uuidPattern.test(id)) throw new Error('invalid video id');
  return path.join(dataRoot, id);
}

async function readMetadata(id) {
  return JSON.parse(await fsp.readFile(path.join(videoDirectory(id), 'metadata.json'), 'utf8'));
}

async function readOwnedMetadata(id, userId) {
  const metadata = await readMetadata(id);
  if (metadata.userId !== userId) {
    const error = new Error('forbidden');
    error.statusCode = 403;
    throw error;
  }
  return metadata;
}

async function writeMetadata(id, metadata) {
  await fsp.writeFile(
    path.join(videoDirectory(id), 'metadata.json'),
    JSON.stringify(metadata, null, 2),
  );
}

async function completedParts(id) {
  const directory = path.join(videoDirectory(id), 'parts');
  await fsp.mkdir(directory, { recursive: true });
  const names = await fsp.readdir(directory);
  return names
    .map((name) => /^part_(\d+)$/.exec(name))
    .filter(Boolean)
    .map((match) => Number(match[1]))
    .sort((a, b) => a - b);
}

app.get('/health', (_req, res) => res.json({ ok: true }));

app.post('/api/login', (req, res) => {
  if (!demoLoginEnabled) return res.status(404).json({ error: 'not_found' });
  const { account, password } = req.body ?? {};
  if (account !== demoAccount || password !== demoPassword) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  res.json({ token: demoToken, userId: 'demo-user' });
});

app.post('/api/auth/social', async (req, res, next) => {
  try {
    const { provider, idToken } = req.body ?? {};
    if (typeof idToken !== 'string' || idToken.length > 10000) {
      return res.status(400).json({ error: 'invalid_identity_token' });
    }
    let identity;
    if (provider === 'google') {
      if (googleClientIds.length === 0) return res.status(503).json({ error: 'google_not_configured' });
      const verified = await jwtVerify(idToken, googleKeys, {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience: googleClientIds,
      });
      identity = { subject: verified.payload.sub, email: verified.payload.email };
    } else if (provider === 'apple') {
      if (appleClientIds.length === 0) return res.status(503).json({ error: 'apple_not_configured' });
      const verified = await jwtVerify(idToken, appleKeys, {
        issuer: 'https://appleid.apple.com',
        audience: appleClientIds,
      });
      identity = { subject: verified.payload.sub, email: verified.payload.email ?? req.body.email };
    } else {
      return res.status(400).json({ error: 'unsupported_provider' });
    }
    if (!identity.subject) return res.status(401).json({ error: 'invalid_identity_token' });
    const userId = crypto.createHash('sha256').update(`${provider}:${identity.subject}`).digest('hex').slice(0, 32);
    return res.json({ token: issueSessionToken(userId), userId, email: identity.email ?? null });
  } catch (error) {
    if (error?.code?.startsWith('ERR_JWT') || error?.code?.startsWith('ERR_JWS')) {
      return res.status(401).json({ error: 'invalid_identity_token' });
    }
    return next(error);
  }
});

app.use('/api', requireAuth);

app.post('/api/videos', async (req, res, next) => {
  try {
    const id = req.body?.id;
    const directory = videoDirectory(id);
    if (fs.existsSync(directory)) {
      const existing = await readOwnedMetadata(id, req.userId);
      if (existing.fileSize !== req.body.fileSize || existing.sha256 !== req.body.sha256) {
        return res.status(409).json({ error: 'idempotency_conflict' });
      }
      return res.status(200).json({ id, status: existing.status });
    }
    await fsp.mkdir(path.join(directory, 'parts'), { recursive: true });
    await writeMetadata(id, {
      ...req.body,
      userId: req.userId,
      status: 'created',
      createdAt: new Date().toISOString(),
    });
    res.status(201).json({ id, status: 'created' });
  } catch (error) { next(error); }
});

app.post('/api/videos/:id/upload/init', async (req, res, next) => {
  try {
    const metadata = await readOwnedMetadata(req.params.id, req.userId);
    const nextPartSize = Number(req.body.partSize);
    const nextTotalParts = Number(req.body.totalParts);
    const nextFileSize = Number(req.body.fileSize);
    if (!Number.isSafeInteger(nextPartSize) || nextPartSize < 1024 || nextPartSize > 64 * 1024 * 1024 ||
        !Number.isSafeInteger(nextTotalParts) || nextTotalParts < 1 ||
        nextFileSize !== metadata.fileSize || Math.ceil(nextFileSize / nextPartSize) !== nextTotalParts) {
      return res.status(400).json({ error: 'invalid_upload_plan' });
    }
    if (metadata.partSize && (metadata.partSize !== nextPartSize || metadata.totalParts !== nextTotalParts)) {
      return res.status(409).json({ error: 'upload_plan_changed' });
    }
    metadata.uploadSessionId = req.body.uploadSessionId;
    metadata.partSize = nextPartSize;
    metadata.totalParts = nextTotalParts;
    metadata.status = 'uploading';
    await writeMetadata(req.params.id, metadata);
    res.json({ completedParts: await completedParts(req.params.id) });
  } catch (error) { next(error); }
});

app.put(
  '/api/videos/:id/parts/:partNumber',
  express.raw({ type: 'application/octet-stream', limit: '65mb' }),
  async (req, res, next) => {
    try {
      const metadata = await readOwnedMetadata(req.params.id, req.userId);
      const partNumber = Number(req.params.partNumber);
      if (!Number.isInteger(partNumber) || partNumber < 0 || partNumber >= metadata.totalParts) {
        return res.status(400).json({ error: 'invalid_part_number' });
      }
      const expectedSize = Math.min(metadata.partSize, metadata.fileSize - (partNumber * metadata.partSize));
      if (!Buffer.isBuffer(req.body) || req.body.length !== expectedSize) {
        return res.status(400).json({ error: 'invalid_part' });
      }
      const actualPartHash = crypto.createHash('sha256').update(req.body).digest('hex');
      if (req.headers['x-part-sha256'] && req.headers['x-part-sha256'] !== actualPartHash) {
        return res.status(422).json({ error: 'part_checksum_mismatch' });
      }
      const destination = path.join(videoDirectory(req.params.id), 'parts', `part_${partNumber}`);
      const temporary = `${destination}.${crypto.randomUUID()}.tmp`;
      await fsp.writeFile(temporary, req.body);
      await fsp.rename(temporary, destination);
      res.status(201).json({ partNumber, size: req.body.length, sha256: actualPartHash });
    } catch (error) { next(error); }
  },
);

app.get('/api/videos/:id/parts', async (req, res, next) => {
  try {
    await readOwnedMetadata(req.params.id, req.userId);
    res.json({ completedParts: await completedParts(req.params.id) });
  } catch (error) { next(error); }
});

app.post('/api/videos/:id/upload/complete', async (req, res, next) => {
  try {
    const id = req.params.id;
    const metadata = await readOwnedMetadata(id, req.userId);
    const finalPath = path.join(videoDirectory(id), 'final.mp4');
    if (metadata.status === 'uploaded' && fs.existsSync(finalPath)) {
      return res.json({ id, status: 'uploaded', sha256: metadata.sha256 });
    }
    const totalParts = Number(req.body.totalParts);
    const parts = await completedParts(id);
    if (totalParts !== metadata.totalParts || parts.length !== totalParts ||
        !parts.every((part, index) => part === index)) {
      return res.status(409).json({ error: 'missing_parts', completedParts: parts });
    }
    const temporary = `${finalPath}.tmp`;
    async function* assembledChunks() {
      for (let part = 0; part < totalParts; part += 1) {
        yield* fs.createReadStream(path.join(videoDirectory(id), 'parts', `part_${part}`));
      }
    }
    await pipeline(Readable.from(assembledChunks()), fs.createWriteStream(temporary, { flags: 'w' }));
    const hash = crypto.createHash('sha256');
    await new Promise((resolve, reject) => {
      const stream = fs.createReadStream(temporary);
      stream.on('data', (chunk) => hash.update(chunk));
      stream.on('end', resolve);
      stream.on('error', reject);
    });
    const actualHash = hash.digest('hex');
    if (actualHash !== req.body.sha256 || actualHash !== metadata.sha256) {
      await fsp.unlink(temporary);
      return res.status(422).json({ error: 'checksum_mismatch', actualHash });
    }
    await fsp.rename(temporary, finalPath);
    metadata.status = 'uploaded';
    metadata.completedAt = new Date().toISOString();
    await writeMetadata(id, metadata);
    res.json({ id, status: 'uploaded', sha256: actualHash });
  } catch (error) { next(error); }
});

app.get('/api/videos/:id/status', async (req, res, next) => {
  try {
    const metadata = await readOwnedMetadata(req.params.id, req.userId);
    res.json({ id: req.params.id, status: metadata.status });
  } catch (error) { next(error); }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  if (error?.message === 'invalid video id') return res.status(400).json({ error: error.message });
  if (error?.statusCode === 403) return res.status(403).json({ error: 'forbidden' });
  if (error?.code === 'ENOENT') return res.status(404).json({ error: 'not_found' });
  res.status(500).json({ error: 'server_error' });
});

if (process.env.NODE_ENV !== 'test') {
  app.listen(port, '0.0.0.0', () => console.log(`Upload server listening on :${port}`));
}

export default app;
