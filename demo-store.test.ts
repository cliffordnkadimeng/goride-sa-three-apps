import { describe, expect, it } from 'vitest';
import {
  applyDemoAction,
  calculateDemoFare,
  getDemoSnapshot,
  type DemoRide,
} from './demo-store.js';

function requestRide(category: 'GoRide' | 'Comfort' | 'XL' = 'GoRide'): DemoRide {
  const result = applyDemoAction('passenger', {
    action: 'request_ride',
    category,
    pickup: 'Rosebank, Johannesburg',
    destination: 'Sandton City, Johannesburg',
    pickupLat: -26.1458,
    pickupLng: 28.0418,
    destinationLat: -26.1076,
    destinationLng: 28.0567,
    distanceKm: 7.4,
    durationMin: 18,
  });
  if (!result.ok || !('ride' in result) || !result.ride) throw new Error('Demo ride request failed.');
  return result.ride as DemoRide;
}

describe('GoRide SA demo core', () => {
  it('estimates ZAR fares from the configured category rates', () => {
    expect(calculateDemoFare('GoRide', 6.4, 18)).toBe(80);
    expect(calculateDemoFare('Comfort', 0.4, 5)).toBe(48);
    expect(calculateDemoFare('XL', 7.4, 18)).toBe(142);
  });

  it('lets a driver pass on a request without cancelling the passenger trip', () => {
    const ride = requestRide('GoRide');
    const result = applyDemoAction('driver', { action: 'reject_ride', rideId: ride.id, driverId: 'driver-sipho' });
    expect(result.ok).toBe(true);
    expect(getDemoSnapshot('driver').rides.some((item) => item.id === ride.id)).toBe(false);
    expect(getDemoSnapshot('passenger').rides.find((item) => item.id === ride.id)?.status).toBe('requested');
  });

  it('prevents one driver from accepting overlapping trips and advances a trip through valid states', () => {
    const first = requestRide('GoRide');
    const accepted = applyDemoAction('driver', { action: 'accept_ride', rideId: first.id, driverId: 'driver-sipho' });
    expect(accepted.ok).toBe(true);

    const second = requestRide('GoRide');
    const conflict = applyDemoAction('driver', { action: 'accept_ride', rideId: second.id, driverId: 'driver-sipho' });
    expect(conflict.ok).toBe(false);
    expect('error' in conflict ? conflict.error : '').toContain('active trip');

    const comfortRide = requestRide('Comfort');
    expect(applyDemoAction('driver', { action: 'accept_ride', rideId: comfortRide.id, driverId: 'driver-lerato' }).ok).toBe(true);
    for (const expected of ['arriving', 'in_progress', 'completed']) {
      const transition = applyDemoAction('driver', { action: 'advance_trip', rideId: comfortRide.id, driverId: 'driver-lerato' });
      expect(transition.ok).toBe(true);
      expect(getDemoSnapshot('passenger').rides.find((item) => item.id === comfortRide.id)?.status).toBe(expected);
    }
  });
});
