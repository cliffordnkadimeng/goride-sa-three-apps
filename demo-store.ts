export type DemoRole = 'passenger' | 'driver' | 'admin';
export type RideCategory = 'GoRide' | 'Comfort' | 'XL';
export type RideStatus = 'requested' | 'accepted' | 'arriving' | 'in_progress' | 'completed' | 'cancelled';

export interface DemoDriver {
  id: string;
  name: string;
  rating: number;
  vehicle: string;
  registration: string;
  category: RideCategory;
  online: boolean;
  approved: boolean;
  trips: number;
  earnings: number;
  color: string;
  lat: number;
  lng: number;
}

export interface DemoRide {
  id: string;
  passengerId: string;
  passengerName: string;
  driverId: string | null;
  pickup: string;
  destination: string;
  pickupLat: number;
  pickupLng: number;
  destinationLat: number;
  destinationLng: number;
  category: RideCategory;
  paymentMethod: 'cash' | 'card';
  fare: number;
  distanceKm: number;
  durationMin: number;
  status: RideStatus;
  createdAt: string;
  review?: { score: number; comment: string };
}

export interface DemoSupportTicket {
  id: string;
  subject: string;
  message: string;
  status: 'open' | 'in_review' | 'resolved';
  createdAt: string;
}

interface DemoNotification {
  id: string;
  userId: string;
  type: string;
  payload: Record<string, unknown>;
  readAt: string | null;
  createdAt: string;
}

const now = Date.now();
const drivers: DemoDriver[] = [
  {
    id: 'driver-sipho', name: 'Sipho Mokoena', rating: 4.96, vehicle: 'Toyota Corolla Quest',
    registration: 'GP 482-913', category: 'GoRide', online: true, approved: true,
    trips: 248, earnings: 12840, color: '#d6e7dd', lat: -26.1911, lng: 28.0367,
  },
  {
    id: 'driver-lerato', name: 'Lerato Khumalo', rating: 4.91, vehicle: 'Volkswagen Polo Vivo',
    registration: 'GP 913-028', category: 'Comfort', online: true, approved: true,
    trips: 183, earnings: 9640, color: '#dbe5f0', lat: -26.1838, lng: 28.0473,
  },
  {
    id: 'driver-thabo', name: 'Thabo Ndlovu', rating: 4.88, vehicle: 'Toyota Avanza',
    registration: 'GP 302-748', category: 'XL', online: false, approved: false,
    trips: 311, earnings: 17680, color: '#f1e4ce', lat: -26.2048, lng: 28.0411,
  },
];

const users = [
  { id: 'demo-passenger', full_name: 'Amara Dlamini', phone: null, role: 'passenger' as const, suspended: false },
  { id: 'driver-sipho', full_name: 'Sipho Mokoena', phone: '+27 82 555 0182', role: 'driver' as const, suspended: false },
  { id: 'driver-lerato', full_name: 'Lerato Khumalo', phone: '+27 83 555 0148', role: 'driver' as const, suspended: false },
  { id: 'driver-thabo', full_name: 'Thabo Ndlovu', phone: '+27 84 555 0191', role: 'driver' as const, suspended: false },
  { id: 'demo-admin', full_name: 'Sibusiso Khumalo', phone: null, role: 'admin' as const, suspended: false },
];

const rides: DemoRide[] = [
  {
    id: 'ride-sample-01', passengerId: 'demo-passenger', passengerName: 'Amara Dlamini',
    driverId: 'driver-sipho', pickup: 'Rosebank Mall, Johannesburg', destination: 'Sandton City, Sandton',
    pickupLat: -26.1458, pickupLng: 28.0418, destinationLat: -26.1076, destinationLng: 28.0567,
    category: 'GoRide', paymentMethod: 'cash', fare: 128, distanceKm: 7.4, durationMin: 18,
    status: 'completed', createdAt: new Date(now - 86_400_000).toISOString(),
    review: { score: 5, comment: 'A smooth ride. Thank you!' },
  },
];

const tickets: DemoSupportTicket[] = [];
const notifications: DemoNotification[] = [
  { id: 'demo-notification-passenger', userId: 'demo-passenger', type: 'trip_completed', payload: { trip_id: 'ride-sample-01' }, readAt: null, createdAt: new Date(now - 86_000_000).toISOString() },
  { id: 'demo-notification-driver', userId: 'driver-sipho', type: 'ride_request', payload: { category: 'GoRide' }, readAt: null, createdAt: new Date(now - 60_000).toISOString() },
  { id: 'demo-notification-admin', userId: 'demo-admin', type: 'driver_application', payload: { driver_id: 'driver-thabo' }, readAt: null, createdAt: new Date(now - 5_400_000).toISOString() },
];
const documents: Array<{ id: string; driverId: string; documentType: string; storagePath: string; reviewStatus: 'pending' | 'approved' | 'rejected'; createdAt: string }> = [
  { id: 'demo-document-01', driverId: 'driver-thabo', documentType: 'professional_driving_permit', storagePath: 'demo-only', reviewStatus: 'pending' as const, createdAt: new Date(now - 5_400_000).toISOString() },
  { id: 'demo-document-02', driverId: 'driver-thabo', documentType: 'vehicle_insurance', storagePath: 'demo-only', reviewStatus: 'pending' as const, createdAt: new Date(now - 5_300_000).toISOString() },
];
const vehicles: Array<{ id: string; driverId: string; make: string; model: string; color: string; registrationNumber: string; category: RideCategory; approvalStatus: 'pending' | 'approved' | 'rejected'; createdAt: string }> = [
  { id: 'vehicle-sipho', driverId: 'driver-sipho', make: 'Toyota', model: 'Corolla Quest', color: 'White', registrationNumber: 'GP 482-913', category: 'GoRide', approvalStatus: 'approved', createdAt: new Date(now - 60_000_000).toISOString() },
  { id: 'vehicle-lerato', driverId: 'driver-lerato', make: 'Volkswagen', model: 'Polo Vivo', color: 'Silver', registrationNumber: 'GP 913-028', category: 'Comfort', approvalStatus: 'approved', createdAt: new Date(now - 48_000_000).toISOString() },
  { id: 'vehicle-thabo', driverId: 'driver-thabo', make: 'Toyota', model: 'Avanza', color: 'Blue', registrationNumber: 'GP 302-748', category: 'XL', approvalStatus: 'pending', createdAt: new Date(now - 2_700_000).toISOString() },
];
const rejectedRequests = new Map<string, Set<string>>();
const fareSettings: Record<RideCategory, { base: number; perKm: number; perMinute: number; minimum: number; commissionPct: number }> = {
  GoRide: { base: 18, perKm: 7.5, perMinute: 0.8, minimum: 35, commissionPct: 18 },
  Comfort: { base: 24, perKm: 9.5, perMinute: 1.0, minimum: 48, commissionPct: 18 },
  XL: { base: 32, perKm: 12, perMinute: 1.2, minimum: 64, commissionPct: 18 },
};

function createRideId(): string {
  return `ride-${crypto.randomUUID().slice(0, 8)}`;
}

function addNotification(userId: string, type: string, payload: Record<string, unknown>) {
  notifications.unshift({ id: `demo-notification-${crypto.randomUUID()}`, userId, type, payload, readAt: null, createdAt: new Date().toISOString() });
}

export function getDemoSnapshot(role?: DemoRole) {
  const rejected = role === 'driver' ? rejectedRequests.get('driver-sipho') ?? new Set<string>() : new Set<string>();
  const notificationUserId = role === 'driver' ? 'driver-sipho' : role === 'admin' ? 'demo-admin' : 'demo-passenger';
  return {
    users: users.map((user) => ({ ...user })),
    drivers: drivers.map((driver) => ({ ...driver })),
    vehicles: vehicles.map((vehicle) => ({ ...vehicle })),
    documents: documents.map((document) => ({ ...document })),
    rides: rides.filter((ride) => role !== 'driver' || ride.status !== 'requested' || !rejected.has(ride.id)).map((ride) => ({ ...ride })),
    tickets: tickets.map((ticket) => ({ ...ticket })),
    notifications: notifications.filter((item) => item.userId === notificationUserId)
      .map(({ userId: _userId, ...item }) => ({ ...item, payload: { ...item.payload } })),
    fareSettings: structuredClone(fareSettings),
    paymentMethods: { cash: true, card: false, cardNote: 'Card checkout is awaiting a supported South African provider.' },
  };
}

export function calculateDemoFare(category: RideCategory, distanceKm: number, durationMin: number) {
  const settings = fareSettings[category];
  const total = settings.base + distanceKm * settings.perKm + durationMin * settings.perMinute;
  return Math.round(Math.max(settings.minimum, total));
}

export function applyDemoAction(role: DemoRole, payload: Record<string, unknown>) {
  const action = String(payload.action ?? '');
  const rideId = String(payload.rideId ?? '');
  const ride = rides.find((item) => item.id === rideId);

  if (action === 'request_ride' && role === 'passenger') {
    const category = (['GoRide', 'Comfort', 'XL'].includes(String(payload.category)) ? payload.category : 'GoRide') as RideCategory;
    const distanceKm = Math.max(1, Math.min(80, Number(payload.distanceKm) || 6.4));
    const durationMin = Math.max(5, Math.min(150, Number(payload.durationMin) || Math.round(distanceKm * 2.4)));
    const newRide: DemoRide = {
      id: createRideId(), passengerId: 'demo-passenger', passengerName: 'Amara Dlamini', driverId: null,
      pickup: String(payload.pickup || 'Rosebank, Johannesburg').slice(0, 180),
      destination: String(payload.destination || 'Sandton, Johannesburg').slice(0, 180),
      pickupLat: Number(payload.pickupLat) || -26.1458, pickupLng: Number(payload.pickupLng) || 28.0418,
      destinationLat: Number(payload.destinationLat) || -26.1076, destinationLng: Number(payload.destinationLng) || 28.0567,
      category, paymentMethod: 'cash', fare: calculateDemoFare(category, distanceKm, durationMin),
      distanceKm, durationMin, status: 'requested', createdAt: new Date().toISOString(),
    };
    rides.unshift(newRide);
    for (const driver of drivers.filter((item) => item.online && item.approved && (item.category === category || item.category === 'XL'))) {
      const hasVehicle = vehicles.some((vehicle) => vehicle.driverId === driver.id && vehicle.approvalStatus === 'approved' && (vehicle.category === category || vehicle.category === 'XL'));
      if (hasVehicle) addNotification(driver.id, 'ride_request', { trip_id: newRide.id, category });
    }
    return { ok: true, message: 'Ride request sent to available demo drivers.', ride: newRide };
  }

  if (action === 'toggle_online' && role === 'driver') {
    const driver = drivers.find((item) => item.id === String(payload.driverId || 'driver-sipho'));
    if (!driver) return { ok: false, error: 'Driver account not found.' };
    driver.online = Boolean(payload.online);
    return { ok: true, driver };
  }

  if (action === 'accept_ride' && role === 'driver') {
    const driverId = String(payload.driverId || 'driver-sipho');
    const driver = drivers.find((item) => item.id === driverId);
    if (!driver || !driver.approved) return { ok: false, error: 'This driver is not approved.' };
    if (!driver.online) return { ok: false, error: 'Go online before accepting a request.' };
    if (!ride || ride.status !== 'requested') return { ok: false, error: 'This request is no longer available.' };
    const alreadyBusy = rides.some((item) => item.driverId === driverId && ['accepted', 'arriving', 'in_progress'].includes(item.status));
    if (alreadyBusy) return { ok: false, error: 'This driver already has an active trip.' };
    const approvedVehicle = vehicles.some((vehicle) => vehicle.driverId === driverId && vehicle.approvalStatus === 'approved' && (vehicle.category === ride.category || vehicle.category === 'XL'));
    if (!approvedVehicle) return { ok: false, error: 'An approved matching vehicle is required for this ride category.' };
    if (ride.category !== 'GoRide' && driver.category !== ride.category && driver.category !== 'XL') {
      return { ok: false, error: 'This vehicle category cannot serve the requested ride.' };
    }
    ride.driverId = driverId;
    ride.status = 'accepted';
    addNotification(ride.passengerId, 'driver_matched', { trip_id: ride.id, driver_id: driverId });
    return { ok: true, message: 'Ride accepted. The passenger has been updated.', ride };
  }

  if (action === 'reject_ride' && role === 'driver') {
    if (!ride || ride.status !== 'requested') return { ok: false, error: 'This request is no longer available.' };
    const driverId = String(payload.driverId || 'driver-sipho');
    const driver = drivers.find((item) => item.id === driverId);
    if (!driver || !driver.approved) return { ok: false, error: 'This driver is not approved.' };
    const rejected = rejectedRequests.get(driverId) ?? new Set<string>();
    rejected.add(ride.id);
    rejectedRequests.set(driverId, rejected);
    return { ok: true, message: 'Request passed. It remains available to other drivers.', ride };
  }

  if (action === 'cancel_ride' && role === 'passenger') {
    if (!ride || ride.passengerId !== 'demo-passenger') return { ok: false, error: 'Ride not found.' };
    if (!['requested', 'accepted', 'arriving'].includes(ride.status)) return { ok: false, error: 'This trip can no longer be cancelled.' };
    ride.status = 'cancelled';
    if (ride.driverId) addNotification(ride.driverId, 'trip_cancelled', { trip_id: ride.id });
    return { ok: true, message: 'Ride cancelled.', ride };
  }

  if (action === 'advance_trip' && role === 'driver') {
    if (!ride || ride.driverId !== String(payload.driverId || 'driver-sipho')) return { ok: false, error: 'Trip not assigned to this driver.' };
    const next: Partial<Record<RideStatus, RideStatus>> = { accepted: 'arriving', arriving: 'in_progress', in_progress: 'completed' };
    const status = next[ride.status];
    if (!status) return { ok: false, error: 'Trip cannot advance from its current state.' };
    ride.status = status;
    addNotification(ride.passengerId, status === 'completed' ? 'trip_completed' : 'trip_updated', { trip_id: ride.id, status });
    if (status === 'completed') {
      const driver = drivers.find((item) => item.id === ride.driverId);
      if (driver) {
        driver.trips += 1;
        driver.earnings += ride.fare;
      }
    }
    return { ok: true, message: `Trip marked ${status.replace('_', ' ')}.`, ride };
  }

  if (action === 'review_ride' && role === 'passenger') {
    if (!ride || ride.status !== 'completed') return { ok: false, error: 'Only completed rides can be reviewed.' };
    const score = Math.max(1, Math.min(5, Number(payload.score) || 5));
    ride.review = { score, comment: String(payload.comment || '').slice(0, 240) };
    return { ok: true, message: 'Thanks for sharing your feedback.', ride };
  }

  if (action === 'create_ticket' && role === 'passenger') {
    const ticket: DemoSupportTicket = {
      id: `ticket-${crypto.randomUUID().slice(0, 7)}`, subject: String(payload.subject || 'Ride support').slice(0, 100),
      message: String(payload.message || '').slice(0, 500), status: 'open', createdAt: new Date().toISOString(),
    };
    if (!ticket.message) return { ok: false, error: 'Add a short description so support can help.' };
    tickets.unshift(ticket);
    addNotification('demo-admin', 'support_ticket', { subject: ticket.subject });
    return { ok: true, message: 'Your demo support request has been recorded.', ticket };
  }

  if (action === 'update_profile') {
    const userId = role === 'driver' ? 'driver-sipho' : role === 'admin' ? 'demo-admin' : 'demo-passenger';
    const user = users.find((item) => item.id === userId);
    if (!user) return { ok: false, error: 'Demo profile not found.' };
    const fullName = String(payload.full_name ?? '').trim();
    const phone = String(payload.phone ?? '').trim();
    if (fullName.length < 2 || fullName.length > 80) return { ok: false, error: 'Enter a name between 2 and 80 characters.' };
    if (phone.length > 24 || (phone && !/^\+?[0-9][0-9 ()-]{5,23}$/.test(phone))) return { ok: false, error: 'Enter a valid contact phone number.' };
    user.full_name = fullName;
    user.phone = phone || null;
    const driver = drivers.find((item) => item.id === userId);
    if (driver) driver.name = fullName;
    return { ok: true, message: 'Demo profile details updated.' };
  }

  if (action === 'mark_notification_read') {
    const userId = role === 'driver' ? 'driver-sipho' : role === 'admin' ? 'demo-admin' : 'demo-passenger';
    const notification = notifications.find((item) => item.id === String(payload.notificationId) && item.userId === userId);
    if (!notification) return { ok: false, error: 'Notification not found.' };
    notification.readAt = new Date().toISOString();
    return { ok: true, message: 'Notification marked as read.' };
  }

  if (action === 'approve_driver' && role === 'admin') {
    const driver = drivers.find((item) => item.id === String(payload.driverId));
    if (!driver) return { ok: false, error: 'Driver not found.' };
    driver.approved = Boolean(payload.approved);
    return { ok: true, message: driver.approved ? 'Driver approved.' : 'Driver approval paused.', driver };
  }

  if (action === 'admin_suspend_user' && role === 'admin') {
    const user = users.find((item) => item.id === String(payload.userId));
    if (!user || user.role === 'admin') return { ok: false, error: 'That account cannot be suspended in this demo.' };
    user.suspended = Boolean(payload.suspended);
    if (user.suspended) {
      const driver = drivers.find((item) => item.id === user.id);
      if (driver) driver.online = false;
    }
    return { ok: true, message: user.suspended ? 'Demo account suspended.' : 'Demo account restored.' };
  }

  if (action === 'review_document' && role === 'admin') {
    const document = documents.find((item) => item.id === String(payload.documentId));
    if (!document) return { ok: false, error: 'Document not found.' };
    document.reviewStatus = payload.approved ? 'approved' : 'rejected';
    return { ok: true, message: `Demo document ${document.reviewStatus}.` };
  }

  if (action === 'review_vehicle' && role === 'admin') {
    const vehicle = vehicles.find((item) => item.id === String(payload.vehicleId));
    if (!vehicle) return { ok: false, error: 'Vehicle not found.' };
    vehicle.approvalStatus = payload.approved ? 'approved' : 'rejected';
    return { ok: true, message: `Demo vehicle ${vehicle.approvalStatus}.` };
  }

  if (action === 'set_fare' && role === 'admin') {
    const category = String(payload.category) as RideCategory;
    if (!fareSettings[category]) return { ok: false, error: 'Unknown ride category.' };
    const key = String(payload.key) as keyof typeof fareSettings.GoRide;
    if (!(key in fareSettings[category])) return { ok: false, error: 'Unknown fare setting.' };
    const value = Number(payload.value);
    if (!Number.isFinite(value) || value < 0 || value > 1000) return { ok: false, error: 'Enter a valid amount.' };
    fareSettings[category][key] = value;
    return { ok: true, message: 'Demo fare settings updated.' };
  }

  if (action === 'set_ticket_status' && role === 'admin') {
    const ticket = tickets.find((item) => item.id === String(payload.ticketId));
    if (!ticket) return { ok: false, error: 'Support request not found.' };
    const status = String(payload.status) as DemoSupportTicket['status'];
    if (!['open', 'in_review', 'resolved'].includes(status)) return { ok: false, error: 'Unknown ticket status.' };
    ticket.status = status;
    return { ok: true, message: 'Support request updated.' };
  }

  return { ok: false, error: 'That action is not available for this demo role.' };
}
