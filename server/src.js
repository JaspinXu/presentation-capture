import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import express from 'express';
import cors from 'cors';

const app = express();
const port = Number(process.env.PORT ?? 8080);
const dataRoot = path.resolve(process.env.DATA_DIR ?? './data');
const demoAccount = process.env.DEMO_ACCOUNT ?? 'demo@nus.edu.sg';
const demoPassword = process.env.DEMO_PASSWORD ?? 'demo1234';
const demoToken = process.env.DEMO_TOKEN ?? 'nus-demo-token-change-me';
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

await fsp.mkdir(dataRoot, { recursive: true });
app.use(cors());
app.use(express.json({ limit: '1mb' }));

function requireAuth(req, res, next) {
  if (req.headers.authorization !== `Bearer ${demoToken}`) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  next();
}

function videoDirectory(id) {
  if (!uuidPattern.test(id)) throw new Error('invalid video id');
  return path.join(dataRoot, id);
}

async function readMetadata(id) {
  return JSON.parse(await fsp.readFile(path.join(videoDirectory(id), 'metadata.json'), 'utf8'));
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
  const { account, password } = req.body ?? {};
  if (account !== demoAccount || password !== demoPassword) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  res.json({ token: demoToken, userId: 'demo-user' });
});

app.use('/api', requireAuth);

app.post('/api/videos', async (req, res, next) => {
  try {
    const id = req.body?.id;
    const directory = videoDirectory(id);
    if (fs.existsSync(directory)) return res.status(409).json({ id, status: 'exists' });
    await fsp.mkdir(path.join(directory, 'parts'), { recursive: true });
    await writeMetadata(id, {
      ...req.body,
      userId: 'demo-user',
      status: 'created',
      createdAt: new Date().toISOString(),
    });
    res.status(201).json({ id, status: 'created' });
  } catch (error) { next(error); }
});

app.post('/api/videos/:id/upload/init', async (req, res, next) => {
  try {
    const metadata = await readMetadata(req.params.id);
    metadata.partSize = Number(req.body.partSize);
    metadata.totalParts = Number(req.body.totalParts);
    metadata.status = 'uploading';
    await writeMetadata(req.params.id, metadata);
    res.json({ completedParts: await completedParts(req.params.id) });
  } catch (error) { next(error); }
});

app.put(
  '/api/videos/:id/parts/:partNumber',
  express.raw({ type: 'application/octet-stream', limit: '16mb' }),
  async (req, res, next) => {
    try {
      const metadata = await readMetadata(req.params.id);
      const partNumber = Number(req.params.partNumber);
      if (!Number.isInteger(partNumber) || partNumber < 0 || partNumber >= metadata.totalParts) {
        return res.status(400).json({ error: 'invalid_part_number' });
      }
      if (!Buffer.isBuffer(req.body) || req.body.length === 0 || req.body.length > metadata.partSize) {
        return res.status(400).json({ error: 'invalid_part' });
      }
      const destination = path.join(videoDirectory(req.params.id), 'parts', `part_${partNumber}`);
      const temporary = `${destination}.${crypto.randomUUID()}.tmp`;
      await fsp.writeFile(temporary, req.body);
      await fsp.rename(temporary, destination);
      res.status(201).json({ partNumber, size: req.body.length });
    } catch (error) { next(error); }
  },
);

app.get('/api/videos/:id/parts', async (req, res, next) => {
  try {
    await readMetadata(req.params.id);
    res.json({ completedParts: await completedParts(req.params.id) });
  } catch (error) { next(error); }
});

app.post('/api/videos/:id/upload/complete', async (req, res, next) => {
  try {
    const id = req.params.id;
    const metadata = await readMetadata(id);
    const totalParts = Number(req.body.totalParts);
    const parts = await completedParts(id);
    if (totalParts !== metadata.totalParts || parts.length !== totalParts ||
        !parts.every((part, index) => part === index)) {
      return res.status(409).json({ error: 'missing_parts', completedParts: parts });
    }
    const finalPath = path.join(videoDirectory(id), 'final.mp4');
    const temporary = `${finalPath}.tmp`;
    await fsp.writeFile(temporary, Buffer.alloc(0));
    for (let part = 0; part < totalParts; part += 1) {
      await fsp.appendFile(temporary, await fsp.readFile(path.join(videoDirectory(id), 'parts', `part_${part}`)));
    }
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
    const metadata = await readMetadata(req.params.id);
    res.json({ id: req.params.id, status: metadata.status });
  } catch (error) { next(error); }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  if (error?.message === 'invalid video id') return res.status(400).json({ error: error.message });
  if (error?.code === 'ENOENT') return res.status(404).json({ error: 'not_found' });
  res.status(500).json({ error: 'server_error' });
});

if (process.env.NODE_ENV !== 'test') {
  app.listen(port, '0.0.0.0', () => console.log(`Upload server listening on :${port}`));
}

export default app;
