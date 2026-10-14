import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express, { type Request, type Response } from 'express';
import { applyDemoAction, calculateDemoFare, getDemoSnapshot, type DemoRole, type RideCategory } from './demo-store.js';
import { resolveSouthAfricanLocation, suggestSouthAfricanPlaces } from './maps.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const isProduction = process.env.NODE_ENV === 'production';
const projectRoot = isProduction ? path.resolve(here, '../..') : path.resolve(here, '..');
const demoEnabled = !isProduction || process.env.ENABLE_DEMO_MODE === 'true';
const allowedDocumentTypes = new Set(['identity', 'licence', 'professional_driving_permit', 'vehicle_registration', 'vehicle_insurance']);

app.disable('x-powered-by');
app.use((req, res, next) => {
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Permissions-Policy', 'geolocation=(self)');
  next();
});
app.use(express.json({ limit: '1mb' }));

function normalizedSupabaseUrl() {
  const value = process.env.SUPABASE_URL?.trim();
  if (!value) return null;
  try {
    const url = new URL(value);
    const validSupabaseHost = url.hostname.endsWith('.supabase.co') || url.hostname === 'localhost';
    if ((url.protocol !== 'https:' && url.hostname !== 'localhost') || !validSupabaseHost || url.username || url.password || url.pathname !== '/') return null;
    return url.origin;
  } catch {
    return null;
  }
}

function supabasePublicConfig() {
  const url = normalizedSupabaseUrl();
  const anonKey = process.env.SUPABASE_ANON_KEY?.trim() || null;
  return url && anonKey ? { url, anonKey } : null;
}

function publicConfig() {
  const sb = supabasePublicConfig();
  const mapsBase = process.env.MANUS_API_URL?.trim() || null;
  const mapsKey = process.env.MANUS_API_BROWSER_KEY?.trim() || null;
  const mapsReady = Boolean(mapsBase && mapsKey);
  const mapsRoutingReady = Boolean(mapsBase && process.env.MANUS_API_KEY?.trim());
  return {
    supabaseUrl: sb?.url ?? null,
    supabaseAnonKey: sb?.anonKey ?? null,
    supabaseReady: Boolean(sb),
    supabaseIssue: sb ? undefined : 'Supabase is not ready. Check the project URL and public anon key in secure settings.',
    mapsBaseUrl: mapsReady ? mapsBase : null,
    mapsBrowserKey: mapsReady ? mapsKey : null,
    mapsReady,
    mapsRoutingReady,
    demoMode: demoEnabled,
    cardPaymentsEnabled: false as const,
  };
}

function isDemoRole(value: unknown): value is DemoRole {
  return value === 'passenger' || value === 'driver' || value === 'admin';
}

function finiteCoordinate(value: unknown, min: number, max: number): number | null {
  const number = Number(value);
  return Number.isFinite(number) && number >= min && number <= max ? number : null;
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function getDirectionsDistance(origin: string, destination: string) {
  const base = process.env.MANUS_API_URL;
  const serverKey = process.env.MANUS_API_KEY;
  if (!base || !serverKey || !origin || !destination || origin.length > 180 || destination.length > 180) return null;
  try {
    const url = new URL('/v1/maps/proxy/maps/api/directions/json', base);
    url.searchParams.set('key', serverKey);
    url.searchParams.set('origin', origin);
    url.searchParams.set('destination', destination);
    url.searchParams.set('mode', 'driving');
    const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) return null;
    const data = await response.json() as {
      status?: string;
      routes?: Array<{ legs?: Array<{ distance?: { value?: number }; duration?: { value?: number } }> }>;
    };
    const leg = data.status === 'OK' ? data.routes?.[0]?.legs?.[0] : undefined;
    const meters = leg?.distance?.value;
    const seconds = leg?.duration?.value;
    if (!meters || !seconds) return null;
    return { distanceKm: meters / 1000, durationMin: Math.max(1, Math.round(seconds / 60)) };
  } catch {
    return null;
  }
}

function segmentPath(pathValue: string) {
  return pathValue.split('/').map((segment) => encodeURIComponent(segment)).join('/');
}

async function supabaseErrorText(response: globalThis.Response) {
  try {
    const body = await response.json() as { message?: string; error_description?: string; error?: string };
    return body.message || body.error_description || body.error || 'Supabase rejected the request.';
  } catch {
    return 'Supabase rejected the request.';
  }
}

app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'goridesa', demoMode: demoEnabled }));
app.get('/api/config', (_req, res) => res.json(publicConfig()));
app.get('/api/payment-methods', (_req, res) => res.json({ cash: true, card: false, cardStatus: 'provider_selection_required' }));

app.get('/api/locations/suggest', async (req, res) => {
  const query = typeof req.query.q === 'string' ? req.query.q.trim().slice(0, 120) : '';
  if (query.length < 2) return res.json({ suggestions: [] });
  return res.json({ suggestions: await suggestSouthAfricanPlaces(query) });
});

app.post('/api/locations/resolve', async (req, res) => {
  const placeId = typeof req.body?.placeId === 'string' ? req.body.placeId.trim().slice(0, 256) : undefined;
  const address = typeof req.body?.address === 'string' ? req.body.address.trim().slice(0, 180) : undefined;
  const point = req.body?.point && typeof req.body.point === 'object' ? {
    lat: finiteCoordinate(req.body.point.lat, -90, 90),
    lng: finiteCoordinate(req.body.point.lng, -180, 180),
  } : undefined;
  const choices = [Boolean(placeId), Boolean(address), Boolean(point?.lat !== null && point?.lat !== undefined && point?.lng !== null && point?.lng !== undefined)].filter(Boolean).length;
  if (choices !== 1 || (point && (point.lat === null || point.lng === null))) return res.status(400).json({ error: 'Choose one South African place, address or current location to resolve.' });
  const location = await resolveSouthAfricanLocation({ placeId, address, point: point ? { lat: point.lat!, lng: point.lng! } : undefined });
  if (!location) return res.status(422).json({ error: 'This location could not be resolved within South Africa. Check the address and try again.' });
  return res.json(location);
});

app.get('/api/demo/state', (_req, res) => {
  if (!demoEnabled) return res.status(404).json({ error: 'Demo mode is disabled.' });
  const role = _req.header('x-demo-role');
  if (role && !isDemoRole(role)) return res.status(400).json({ error: 'Choose a valid demo workspace.' });
  return res.json(getDemoSnapshot(isDemoRole(role) ? role : undefined));
});

app.post('/api/demo/action', (req: Request, res: Response) => {
  if (!demoEnabled) return res.status(404).json({ error: 'Demo mode is disabled.' });
  const role = req.header('x-demo-role');
  if (!isDemoRole(role)) return res.status(400).json({ error: 'Choose a demo workspace first.' });
  const result = applyDemoAction(role, req.body ?? {});
  if (!result.ok) return res.status(409).json({ error: result.error, state: getDemoSnapshot(role) });
  return res.json({ ...result, state: getDemoSnapshot(role) });
});

app.post('/api/fare/estimate', async (req, res) => {
  const category = (['GoRide', 'Comfort', 'XL'].includes(req.body?.category) ? req.body.category : 'GoRide') as RideCategory;
  const fromLat = finiteCoordinate(req.body?.originLat, -90, 90);
  const fromLng = finiteCoordinate(req.body?.originLng, -180, 180);
  const toLat = finiteCoordinate(req.body?.destinationLat, -90, 90);
  const toLng = finiteCoordinate(req.body?.destinationLng, -180, 180);
  let distanceKm = 0;
  let durationMin = 0;
  let estimateMode: 'maps' | 'demo' = 'demo';

  if (fromLat !== null && fromLng !== null && toLat !== null && toLng !== null) {
    distanceKm = Math.max(1, haversineKm(fromLat, fromLng, toLat, toLng) * 1.24);
    durationMin = Math.max(5, Math.round((distanceKm / 24) * 60 + 5));
    const directions = await getDirectionsDistance(`${fromLat},${fromLng}`, `${toLat},${toLng}`);
    if (directions) { distanceKm = directions.distanceKm; durationMin = directions.durationMin; estimateMode = 'maps'; }
  } else {
    const origin = String(req.body?.origin || '').trim().slice(0, 180);
    const destination = String(req.body?.destination || '').trim().slice(0, 180);
    const directions = await getDirectionsDistance(origin, destination);
    if (directions) { distanceKm = directions.distanceKm; durationMin = directions.durationMin; estimateMode = 'maps'; }
    else { distanceKm = 7.8; durationMin = 19; }
  }
  return res.json({ fare: calculateDemoFare(category, distanceKm, durationMin), distanceKm, durationMin, estimateMode });
});

// Trusted upload boundary: verify the Supabase user and driver role, enforce MIME/signature/size,
// then use that user's JWT so Supabase RLS remains authoritative for both Storage and metadata.
app.post('/api/driver-documents', express.raw({ type: ['application/pdf', 'image/jpeg', 'image/png'], limit: '10mb' }), async (req, res) => {
  const sb = supabasePublicConfig();
  if (!sb) return res.status(503).json({ error: 'Supabase is not configured. Document upload is unavailable.' });
  const token = req.header('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return res.status(401).json({ error: 'Sign in to upload a driver document.' });
  if (!Buffer.isBuffer(req.body) || req.body.length === 0) return res.status(400).json({ error: 'Select a non-empty PDF, JPG or PNG document.' });
  const contentType = (req.header('content-type') || '').split(';')[0].trim().toLowerCase();
  const typeByMime: Record<string, { extension: string; signatureOk: (bytes: Buffer) => boolean }> = {
    'application/pdf': { extension: 'pdf', signatureOk: (bytes) => bytes.subarray(0, 5).toString('ascii') === '%PDF-' },
    'image/jpeg': { extension: 'jpg', signatureOk: (bytes) => bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff },
    'image/png': { extension: 'png', signatureOk: (bytes) => bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) },
  };
  const mime = typeByMime[contentType];
  if (!mime || !mime.signatureOk(req.body)) return res.status(415).json({ error: 'Upload a valid PDF, JPG or PNG file.' });
  const documentType = req.header('x-goride-document-type') || '';
  if (!allowedDocumentTypes.has(documentType)) return res.status(400).json({ error: 'Choose a valid driver document type.' });

  try {
    const userResponse = await fetch(`${sb.url}/auth/v1/user`, {
      headers: { apikey: sb.anonKey, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(8000),
    });
    if (!userResponse.ok) return res.status(401).json({ error: 'Your session is invalid or expired. Sign in again.' });
    const user = await userResponse.json() as { id?: string };
    if (!user.id) return res.status(401).json({ error: 'Your session could not be verified.' });

    const profileUrl = new URL(`${sb.url}/rest/v1/profiles`);
    profileUrl.searchParams.set('id', `eq.${user.id}`);
    profileUrl.searchParams.set('select', 'role,suspended');
    const profileResponse = await fetch(profileUrl, {
      headers: { apikey: sb.anonKey, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(8000),
    });
    if (!profileResponse.ok) return res.status(403).json({ error: 'Could not verify driver access.' });
    const profiles = await profileResponse.json() as Array<{ role?: string; suspended?: boolean }>;
    if (profiles[0]?.role !== 'driver' || profiles[0]?.suspended) return res.status(403).json({ error: 'An active driver account is required to upload documents.' });

    const storagePath = `${user.id}/${crypto.randomUUID()}.${mime.extension}`;
    const storageUrl = `${sb.url}/storage/v1/object/driver-documents/${segmentPath(storagePath)}`;
    const fileBytes = new Uint8Array(req.body.length);
    fileBytes.set(req.body);
    const fileBody = new Blob([fileBytes.buffer], { type: contentType });
    const uploadResponse = await fetch(storageUrl, {
      method: 'POST',
      headers: { apikey: sb.anonKey, Authorization: `Bearer ${token}`, 'Content-Type': contentType, 'x-upsert': 'false' },
      body: fileBody, signal: AbortSignal.timeout(20_000),
    });
    if (!uploadResponse.ok) return res.status(uploadResponse.status === 401 ? 401 : 403).json({ error: await supabaseErrorText(uploadResponse) });

    const metadataResponse = await fetch(`${sb.url}/rest/v1/driver_documents`, {
      method: 'POST',
      headers: { apikey: sb.anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({ driver_id: user.id, document_type: documentType, storage_path: storagePath }),
      signal: AbortSignal.timeout(8000),
    });
    if (!metadataResponse.ok) {
      await fetch(storageUrl, { method: 'DELETE', headers: { apikey: sb.anonKey, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(8000) }).catch(() => undefined);
      return res.status(403).json({ error: await supabaseErrorText(metadataResponse) });
    }
    const rows = await metadataResponse.json() as Array<{ id?: string }>;
    return res.status(201).json({ id: rows[0]?.id ?? null, reviewStatus: 'pending' });
  } catch {
    return res.status(502).json({ error: 'The document service could not complete the upload. Try again after checking Supabase connectivity.' });
  }
});

const applicationsRoot = path.join(projectRoot, 'apps');
const sharedRoot = path.join(projectRoot, 'shared');
app.use('/shared', express.static(sharedRoot, { index: false }));
for (const role of ['passenger', 'driver', 'admin'] as const) {
  app.use(`/${role}`, express.static(path.join(applicationsRoot, role)));
}
app.get('/', (_req, res) => res.redirect('/passenger/'));
const port = Number(process.env.PORT || 3000);
app.listen(port, '0.0.0.0', () => console.log(`GoRide SA three apps: http://localhost:${port}/passenger/ | /driver/ | /admin/`));
