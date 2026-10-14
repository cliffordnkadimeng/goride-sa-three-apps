# GoRide SA — three Supabase-connected web applications

**Connected database:** [GoRide SA on Supabase](https://supabase.com/dashboard/project/eihcsvgajcjykpwbblhz) (`eihcsvgajcjykpwbblhz`).

All three browser applications now use `shared/live.js` to authenticate users through Supabase Auth and make authenticated calls to the existing PostgreSQL database and protected RPC functions. The Passenger, Driver and Admin interfaces have been converted from demo-role requests to live authenticated database access. Each uses its own `/passenger/`, `/driver/`, or `/admin/` entry point.

### Operational status and limitations

- **Database:** confirmed existing with 12 public tables, RLS enabled and trip/approval RPC functions; no new database was created, and uploaded SQL migrations were NOT rerun.
- **Authentication:** live email signup/signin available; users must confirm email if enabled in their Supabase project. Passenger accounts can request driver onboarding using the Driver app. Admin signup is disabled; grant admin only in the Supabase SQL Editor after registering a designated administrator.
- **Bookings:** live database requests require server-side Maps Geocoding and Directions to be configured; bookings are intentionally blocked when routing is only an approximation. This avoids charging incorrect commercial fares.
- **Driver approvals:** uploaded vehicle data and driver applications go into Supabase. Admin dashboard reviews driver accounts and vehicles. Document uploads require backend env values and the original secure upload API; documents must be verified manually in private Supabase Storage before approval (the browser does not expose private documents).
- **Live data:** refreshed every 5 seconds via Supabase REST. This is polling, not push Realtime. Only cash rides are supported; card checkout, live GPS streaming and push notifications are NOT operational.
- **Hosting:** Supabase is the database/auth/storage backend, not the public hosting for these Express applications. Deploy the code to a Node.js host (for example Render) with the `.env.example` variables and `NODE_ENV=production`.
- **Security:** no browser-side admin selector and no service-role secret. The project security advisor still warns about privileged functions and leaked-password protection; review before a production launch.

**Run:** Node.js 22+, `npm install`, `npm run dev`, then `/passenger/`, `/driver/`, and `/admin/` on port 3000. A deployed backend needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` set to the public values in `.env.example`. The browser references these same public settings in `shared/live.js`. Keep `ENABLE_DEMO_MODE=false` when deployed.

**Admin onboarding:** sign up for an ordinary passenger account, confirm its email, then *from the Supabase SQL Editor* run a role update for that exact, trusted account ID after verifying ownership: `update public.profiles set role='admin' where id='<verified-user-uuid>'::uuid;`. Never allow clients to self-select admin roles.

---

## Original demo package notes (superseded by the live frontends above)

# GoRide SA — Three Separate Apps (Demo MVP)

This project separates the uploaded GoRide SA code into three independent, responsive **web-app entry points** with one shared Express demo backend. It preserves the original GoRide, Comfort, XL, ZAR fare and ride-state logic from the supplied `demo-store.ts` and country-restricted Maps service from `maps.ts`.

## The three apps

| App | URL | Includes |
|---|---|---|
| Passenger | `http://localhost:3000/passenger/` | Pickup/destination, SA city presets, fare estimates, cash ride requests, cancellations, ride status/history, reviews and support |
| Driver | `http://localhost:3000/driver/` | Availability, incoming GoRide requests, accept/reject, trip progress, earnings, history and rating |
| Admin | `http://localhost:3000/admin/` | Activity dashboard, trip monitor, driver/vehicle/document approval demo, user suspension demo, fare/commission updates and support cases |

The frontends are separate folders, so they can evolve into separate web deployments or native apps. The backend stays shared for consistent trips and driver matching. **They are not native Android/iOS APK/IPA apps.**

## Run locally

Requires Node.js 22+, npm and network access to install dependencies. In the project root:

```bash
npm install
npm run dev
```

Visit each URL above in separate browser tabs. Open Passenger and Driver simultaneously: create a request in Passenger, accept and progress it in Driver, monitor it in Admin. The apps refresh shared in-memory data approximately every 4 seconds.

To build and run the server:

```bash
npm run check
npm run test
npm run build
npm start
```

**Do not deploy these demo endpoints publicly for real customers.** `x-demo-role` is a selector, *not* authentication; when `ENABLE_DEMO_MODE=true`, anyone could invoke simulated admin actions. The server disables demo operations when `NODE_ENV=production` unless expressly re-enabled.

## Environment setup

See `.env.example`. The `MANUS_API_URL` and `MANUS_API_KEY` values are platform-specific; they are not included. If Maps is absent, Passenger can request a **demo** trip using listed city presets, with approximate crow-flies-derived fares. Typed custom addresses must be verified through the configured provider. The illustrated route is *not* a live map. Preset coordinates are illustrative city centers, not precise street pickup addresses. Never dispatch a real driver from them.

## Production requirements (not implemented in this three-app demo)

- Replace role-selector demo API calls with properly authenticated Supabase Auth accounts and strict server-side role authorization.
- Apply and test the three supplied SQL migrations *in order*, after reviewing them in your Supabase SQL Editor. They are included under `supabase/migrations/` but have **not** been executed.
- Connect the real database-backed ride APIs and Realtime subscriptions to **each** frontend. Their current actions operate only on shared **in-memory** sample data, and reset after restart.
- Configure browser-safe Google Maps plus server-side SA geocoding, routing and GPS, and test nationwide coverage and accuracy.
- Choose and integrate Paystack/PayFast or another eligible SA card provider with server-created checkout, signatures/webhooks and idempotent payment processing. Card checkout is **disabled** here; demo payments are cash only.
- Driver document uploads and genuine admin login need Supabase Auth, restricted Storage and the existing secure API paths; the Admin demo displays placeholders only.
- Native mobile distribution would require React Native/Expo or a secure mobile wrapper, mobile API authentication, and app-store builds.

## Project structure

```
apps/passenger/    standalone Passenger frontend
apps/driver/       standalone Driver frontend
apps/admin/        standalone Admin frontend
shared/            styling and shared API helpers
server/            copied original Express API, fare/matching demo and Maps logic
supabase/migrations/ original PostgreSQL/RLS migration SQL
```

## Original source preservation

The supplied `demo-store.ts`, `maps.ts`, `demo-store.test.ts`, database migrations and server API form the backend baseline. The original combined React components are not embedded in these new standalone vanilla-JS demo frontends, but are reflected in their workflows. This deliberately avoids missing imports: the original uploaded frontend lacked `Workspace.tsx`, `lib/types.ts`, `lib/api.ts`, `lib/supabase.ts`, and other referenced source files.

## Known limitations

- Driver demo represents only the provided Sipho driver profile, while the backend has other sample drivers. The separate driver UI is easily adaptable to authenticated drivers.
- Login/signup, live tracking, driver document upload, true admin protection and live payments are **not enabled** for these three demo frontends.
- Long-distance estimates in demo mode are illustrative and the original demo fare model caps distance for the simulated booking. Do not use these as commercial quotes.
- Tests were carried over from the supplied project; actual runtime installation/integration verification depends on installing packages.

## Render public deployment

The included `render.yaml` defines one Node web service serving three separate web apps:
`/passenger/`, `/driver/`, and `/admin/`. Demo mode is disabled in production.

1. Create a GitHub repository named `goride-sa-three-apps` and push these project files.
2. In Render, select **New > Blueprint** and point it at your new repository. Confirm the `goride-sa` service settings and any plan costs shown by Render.
3. After deployment, use the Render service hostname followed by `/passenger/`, `/driver/`, or `/admin/`.
4. Configure the Supabase Auth site URL and allowed redirect URLs for the actual Render hostname. Create a trusted admin user by updating their `public.profiles.role` to `admin` in the Supabase SQL Editor, after verifying the user's identity.
5. Add a compatible, functioning South African routing/maps provider before taking real bookings. Google Maps proxy variables from Manus may not be available outside Manus. Card checkout remains inactive.
6. Review Supabase Security Advisor warnings, role permissions, and RLS tests before onboarding real users.

Supabase stores backend data but does **not** host these Express-powered web apps. Do not place service-role/secret keys in `render.yaml` or browser code.
