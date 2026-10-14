export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface LocationSuggestion {
  label: string;
  placeId: string;
}

export interface ResolvedLocation {
  label: string;
  point: GeoPoint;
}

const explicitForeignCountry = /(?:^|[,\s])(?:united states(?: of america)?|u\.?s\.?a?\.?|canada|united kingdom|u\.?k\.?|england|scotland|wales|australia|new zealand|ireland|germany|france|netherlands|india|china|japan|singapore|united arab emirates|u\.?a\.?e\.?|botswana|namibia|mozambique|zimbabwe|lesotho|eswatini|swaziland|zambia|malawi|kenya|tanzania|nigeria|ghana|egypt|mexico|brazil|argentina|chile|russia|south korea|turkey|thailand|indonesia|italy|spain|portugal|switzerland|austria|belgium|norway|sweden|denmark|finland|poland|greece|israel|saudi arabia|qatar|pakistan|bangladesh|sri lanka|nepal|vietnam|philippines)\s*$/i;

interface GoogleAddressComponent {
  short_name?: string;
  types?: string[];
}

interface GoogleLocationResult {
  formatted_address?: string;
  name?: string;
  address_components?: GoogleAddressComponent[];
  geometry?: { location?: { lat?: number; lng?: number } };
}

function mapsUrl(path: string, params: Record<string, string>): URL | null {
  const base = process.env.MANUS_API_URL?.trim();
  const key = process.env.MANUS_API_KEY?.trim();
  if (!base || !key) return null;
  try {
    const url = new URL(`/v1/maps/proxy/maps/api/${path}`, base);
    url.searchParams.set('key', key);
    Object.entries(params).forEach(([name, value]) => url.searchParams.set(name, value));
    return url;
  } catch {
    return null;
  }
}

async function mapsJson(path: string, params: Record<string, string>): Promise<Record<string, unknown> | null> {
  const url = mapsUrl(path, params);
  if (!url) return null;
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) return null;
    const data: unknown = await response.json();
    return data && typeof data === 'object' ? data as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

export async function suggestSouthAfricanPlaces(input: string): Promise<LocationSuggestion[]> {
  const query = input.trim().slice(0, 120);
  if (query.length < 2) return [];
  const data = await mapsJson('place/autocomplete/json', {
    input: query,
    components: 'country:za',
    region: 'za',
    language: 'en',
  });
  if (data?.status !== 'OK' || !Array.isArray(data.predictions)) return [];
  return data.predictions.flatMap((prediction: unknown) => {
    if (!prediction || typeof prediction !== 'object') return [];
    const row = prediction as { description?: unknown; place_id?: unknown };
    return typeof row.description === 'string' && typeof row.place_id === 'string'
      ? [{ label: row.description, placeId: row.place_id }]
      : [];
  }).slice(0, 6);
}

function asSouthAfricanLocation(result: GoogleLocationResult | undefined): ResolvedLocation | null {
  if (!result) return null;
  const country = result.address_components?.find((item) => item.types?.includes('country'))?.short_name;
  const lat = result.geometry?.location?.lat;
  const lng = result.geometry?.location?.lng;
  if (country !== 'ZA' || typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const label = result.formatted_address?.trim() || result.name?.trim();
  if (!label) return null;
  return { label, point: { lat, lng } };
}

export async function resolveSouthAfricanLocation(input: { placeId?: string; address?: string; point?: GeoPoint }): Promise<ResolvedLocation | null> {
  const placeId = input.placeId?.trim().slice(0, 256);
  const point = input.point;
  if (point && Number.isFinite(point.lat) && Number.isFinite(point.lng) && point.lat >= -90 && point.lat <= 90 && point.lng >= -180 && point.lng <= 180) {
    const data = await mapsJson('geocode/json', { latlng: `${point.lat},${point.lng}`, language: 'en' });
    if (data?.status !== 'OK' || !Array.isArray(data.results)) return null;
    const location = asSouthAfricanLocation(data.results[0] as GoogleLocationResult | undefined);
    return location ? { label: location.label, point } : null;
  }
  if (placeId) {
    const data = await mapsJson('place/details/json', {
      place_id: placeId,
      fields: 'geometry,formatted_address,name,address_component',
      language: 'en',
    });
    if (data?.status !== 'OK') return null;
    return asSouthAfricanLocation(data.result as GoogleLocationResult | undefined);
  }

  const address = input.address?.trim().slice(0, 180);
  if (!address || address.length < 3) return null;
  if (explicitForeignCountry.test(address)) return null;
  const scopedAddress = /\bsouth africa\b/i.test(address) ? address : `${address}, South Africa`;
  const data = await mapsJson('geocode/json', {
    address: scopedAddress,
    components: 'country:za',
    region: 'za',
    language: 'en',
  });
  if (data?.status !== 'OK' || !Array.isArray(data.results)) return null;
  return asSouthAfricanLocation(data.results[0] as GoogleLocationResult | undefined);
}
