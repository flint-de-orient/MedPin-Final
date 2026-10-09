# MedPin backend

Node.js (Express 5) API and MongoDB (Mongoose) database for the MedPin Flutter
app: doctor panel, front desk and patient app. The Flutter app talks to this
API; it never connects to MongoDB directly.

## Run locally

Needs Node.js 20+ and MongoDB running on `127.0.0.1:27017` (the Windows
`MongoDB` service, or `mongod --dbpath <folder>`). Browse the data with MongoDB
Compass at `mongodb://127.0.0.1:27017`, database `medpin`.

```sh
cd backend
npm install
npm run db:sync    # create the 59 collections and their indexes
npm run db:seed    # catalogs + demo practice (safe to run again)
npm run dev        # API on http://localhost:4000, restarts on file changes
```

Check it: `GET http://localhost:4000/health` lists which services are live and
which are in dev mode.

### Tests

```sh
npm run db:test    # schema rules (unique, enums, ranges) in a throwaway DB
npm run test:api   # 21 end-to-end flows over HTTP in a throwaway DB (no SMS, no AI)
npm run test:ai    # live AI behaviour checks with your AI key (makes real AI calls)
```

Both create `medpin_schema_test` / `medpin_api_test` and drop them at the end;
your `medpin` data is not touched.

### Signing in without SMS

Outside production, the numbers in `DEV_OTP_PHONES` (default: the front desk and
patient demo accounts below) never get an SMS: `POST /api/auth/otp/request` returns their
code as `devCode`, and the app shows it as "Test code: …". Every other number
gets a real SMS through MSG91 (or, with no MSG91 key, the code is returned too).
Demo accounts from `db:seed`:

| Phone | Who | Lands on |
| --- | --- | --- |
| 9330414463 | Dr. Arjun Sen, owner of City Care Clinic (real SMS) | Doctor-Dashboard |
| 9876518210 | Tania Ghosh, front desk | Staff-Today |
| 9876543210 | Priya Sharma, patient | Main (patient home) |

Invite code `CCC-4821` registers a new front-desk member.

## Configuration (`.env`)

All keys are in [.env.example](.env.example); `.env` is git-ignored. Every
empty value falls back to a safe local default:

| Service | When empty |
| --- | --- |
| `MONGODB_URI`, `MONGODB_DB_NAME` | `mongodb://127.0.0.1:27017`, `medpin` |
| `JWT_*`, `OTP_HASH_SECRET` | fixed dev secrets — **the server refuses to start in production without them** |
| `MSG91_*` (SMS OTP) | code returned as `devCode` and logged |
| `S3_*` (files) | stored in `./uploads`, served through signed `/files/...` links |
| `ANTHROPIC_API_KEY` (AI) | AI features answer with a "not set up" message; chat auto-replies, briefs and report reading are skipped |
| `FCM_*`, `WHATSAPP_*`, `SMTP_*` | logged instead of sent |
| `RAZORPAY_*` | payment links point to `POST /dev/pay/:paymentId`, which marks the fee paid |

AI runs on Gemini when `GEMINI_API_KEY` is set (`GEMINI_CHAT_MODEL` for chat,
`GEMINI_VISION_MODEL` for reading reports, `GEMINI_EMBED_MODEL` for knowledge
search), or on Claude with `ANTHROPIC_API_KEY`; `AI_PROVIDER` picks one.

- **Doctor assistant** answers from the doctor's specialty and department
  (profile headline, specialisations, department) and the patient's record.
- **MedPin AI for patients** (Ask AI and chat replies) never diagnoses, never
  names or doses a medicine, never orders tests and never says to stop a
  medicine; it explains the patient's own record, gives general guidance,
  suggests the kind of specialist, and sends emergencies to 108. Every answer
  carries a self-check; a draft that breaks the rules is replaced with a safe
  reply. Risky chat answers are flagged for doctor review.

## How it works

- **Auth**: phone + 6-digit OTP → short-lived access JWT (`Authorization: Bearer`) and a rotating refresh token. `GET /api/auth/session` returns the account and the screen to land on.
- **Practice context**: staff endpoints use the caller's active practice, or `X-Practice-Id` for a specific one. Role permissions (view, edit records, chats, prescribe) are fixed per role, as on the People screen.
- **Patient privacy**: one patient record per phone across MedPin. A clinic sees a patient only after linking — by registering them, or with the patient's rotating 6-digit consent code. The patient controls each care-team member's access.
- **Files**: never public. API responses carry signed links that expire after an hour.
- **Computed, not stored**: dashboards, reports, queue stats, adherence, slots and refill dates are calculated from the source collections on each request.
- Times are stored in UTC; days are computed in IST (UTC+5:30).

See [API.md](API.md) for every endpoint, grouped by screen.

## Layout

| Path | What |
| --- | --- |
| `src/models/` | Mongoose schemas (59 collections) and enums |
| `src/routes/` | HTTP endpoints, one file per area |
| `src/services/` | Scheduling, clinical, care (alerts/chat/adherence), AI, storage, SMS, push, email |
| `src/middleware/auth.js` | Sign-in, practice context, role checks |
| `scripts/` | `sync-indexes`, `seed`, `test-schema`, `test-api` |
