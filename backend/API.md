# MedPin API reference

Base URL `http://localhost:4000`. JSON in and out; uploads are `multipart/form-data`.
Errors: `{ "error": { "code", "message", "details?" } }` with 400 / 401 / 403 / 404 / 409 / 413 / 429.
Signed-in calls send `Authorization: Bearer <accessToken>`; staff calls may add `X-Practice-Id`.

## Auth — Auth-Login, Auth-OTP, Auth-Register
| Method | Path | Notes |
| --- | --- | --- |
| POST | `/api/auth/otp/request` | `{ phone }` → `{ maskedPhone, resendInSec, devCode? }` |
| POST | `/api/auth/otp/verify` | `{ phone, code }` → tokens + account + `landing` screen |
| POST | `/api/auth/refresh` | `{ refreshToken }` → new token pair (old one revoked) |
| POST | `/api/auth/logout` | `{ refreshToken, deviceToken? }` |
| GET | `/api/auth/session` | Account, memberships, `landing` |
| GET | `/api/auth/invites/:code` | Invite preview (practice, role, locations) |
| POST | `/api/auth/register` | `{ inviteCode, name, email?, language?, termsAccepted }` |

## Account, notifications, catalogs
| Method | Path | Notes |
| --- | --- | --- |
| GET / PATCH | `/api/me` | `name, email, language, appLock` |
| POST | `/api/me/active-practice` | `{ practiceId, locationId? }` |
| POST | `/api/me/devices` | `{ token, platform }` for push |
| POST | `/api/me/practices` | Doctor without an invite starts a practice (becomes owner) |
| GET | `/api/notifications` | `?unread=true` → `{ items, unread }` |
| POST | `/api/notifications/:id/read`, `/api/notifications/read-all` | |
| GET | `/api/catalog/specialties`, `/plans`, `/icd?q=`, `/medicines?q=`, `/lab-tests?q=`, `/enums` | |
| GET | `/files/<key>?exp&sig` | Signed file download |

## Practice — Practice, Clinics, Clinic-Editor, Departments, People*
| Method | Path | Notes |
| --- | --- | --- |
| GET / PATCH | `/api/practice` | Tiles, readiness checklist, role and permissions |
| POST | `/api/practice/logo` | file |
| GET / POST | `/api/locations` | List with today's status, doctors, upcoming bookings |
| GET / PATCH | `/api/locations/:id` | Hours, letterhead, map link, facilities, `lat`/`lng` |
| POST | `/api/locations/:id/deactivate` | 409 `HAS_UPCOMING` unless `{ confirm: true }` |
| POST | `/api/locations/:id/activate` | |
| POST / DELETE | `/api/locations/:id/closures[/:closureId]` | `{ startDate, endDate, reason }` |
| GET / POST / PATCH | `/api/departments[/:id]` | Practice + shared departments with panel usage |
| GET / POST | `/api/members` | Seats used/limit; add with role, department, locations |
| POST | `/api/members/phone-otp` | Verify the new member's phone |
| GET / PATCH | `/api/members/:id` | Role, department, locations, `{ suspended }` |
| GET / POST / DELETE | `/api/invites[/:id]` | Codes like `CCC-4821` |

## Doctor profile & schedule — Doctor-MyProfile, Profile-*
| Method | Path | Notes |
| --- | --- | --- |
| GET / PATCH | `/api/doctor/profile` | Completion %, next free slot, leave |
| POST | `/api/doctor/profile/photo`, `/api/doctor/profile/signature` | file |
| POST / DELETE | `/api/doctor/qualifications[/:qid]` | |
| POST | `/api/doctor/qualifications/:qid/proof` | file → "In review" |
| GET | `/api/doctor/locations` | Services/fees and schedule per location |
| PUT | `/api/doctor/locations/:locationId` | `{ services, schedule }` |
| POST | `/api/doctor/locations/:id/copy-from/:fromId`, `/api/doctor/locations/:id/stop` | |
| GET | `/api/doctors` | Practice doctors with their locations (booking pickers) |
| GET | `/api/doctors/:doctorId/slots?locationId&date` | Slots with booked/available/walk-in |
| GET / POST / DELETE | `/api/doctor/leaves[/:id]` | Affected-patient count |
| PUT | `/api/doctor/default-queue-location` | "Don't ask again today" |

## Patients (staff) — Doctor-Patients, Add-Patient*, Patient-Profile, PP-*
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/patients` | `?q&filter=all/today/follow_up_due/abnormal&sort=recent/name` |
| GET | `/api/patients/lookup?phone` | Exists / linked |
| POST | `/api/patients/phone-otp` | Verify the patient's phone |
| POST | `/api/patients` | Register (409 `PATIENT_EXISTS` → use consent code) |
| POST | `/api/patients/link` | `{ phone, consentCode }` |
| GET / PATCH | `/api/patients/:id` | Full summary, adherence, care team, plan |
| POST / DELETE | `/api/patients/:id/conditions[/:cid]`, `/api/patients/:id/allergies[/:aid]` | allergies: `"Penicillin, peanuts"` |
| GET / POST | `/api/patients/:id/vitals` | Readings outside limits raise alerts |
| GET / POST | `/api/patients/:id/records` | Upload files (+ AI extraction of test reports) |
| GET / POST | `/api/patients/:id/lab-results` | `?filter=abnormal/normal` |
| POST | `/api/lab-results/:id/reviewed` | |
| GET | `/api/patients/:id/trends/:analyte` | e.g. `HbA1c` |
| GET | `/api/patients/:id/prescriptions` | `?filter=all/this_clinic/shared` |
| GET | `/api/patients/:id/adherence` | 30-day %, previous period, weekly grid |
| GET | `/api/patients/:id/health-logs`, POST `/api/health-logs/:id/review` | Dietician review |
| GET | `/api/patients/:id/visits` | Past consultations |
| PUT | `/api/patients/:id/treatment-plan` | Diet / activity / monitoring / … |

## Appointments & queue — Appointments*, Queue-*, Staff-Today, Doctor-History
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/appointments` | `?view=today/upcoming/past&date&locationId&doctorId=me&status` |
| POST | `/api/appointments` | Book a slot (`walkIn: true` for walk-ins) |
| GET | `/api/appointments/:id` | |
| POST | `/api/appointments/:id/status` | `confirmed / waiting (check in) / in_consultation / completed / missed` |
| POST | `/api/appointments/:id/reschedule` | `{ startAt }` |
| POST | `/api/appointments/:id/cancel` | `{ reason }` — patient is notified |
| GET | `/api/appointment-requests?status=pending` | "Requests waiting for a time" |
| POST | `/api/appointment-requests/:id/assign`, `/decline` | |
| GET | `/api/queue/locations` | Queue-Select cards |
| GET | `/api/queue?locationId&date` | Tokens, waiting time, vitals/docs/AI brief flags, stats |
| GET | `/api/staff/today` | Front desk day: summary, requests, list |
| GET | `/api/history?period=this_month/last_3_months/this_year` | |
| GET | `/api/payments?status=pending` | |
| POST | `/api/payments/:id/mark-paid` | `{ method: upi/cash/card }` |
| POST | `/api/payments/:id/link` | Razorpay payment link (dev link without keys) |

## Consultation — Consult-*, Prescriptions
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/consultations/pick?q` | Waiting now, recent, search |
| POST | `/api/consultations` | `{ appointmentId }` or `{ patientId }` — doctors only |
| GET / PATCH | `/api/consultations/:id` | Draft: complaint, diagnoses, medications, labOrders, advice, validity, followUp |
| GET | `/api/consultations/:id/checks` | Allergy clashes, catalog strengths |
| GET | `/api/consultations/:id/suggestions` | Past prescriptions, for this diagnosis, tests |
| POST | `/api/consultations/:id/vitals` | |
| POST | `/api/consultations/:id/issue` | Rx number, PDF, medicine courses, follow-up, record |
| POST | `/api/prescriptions/:id/send` | Needs the doctor's signature; posts to the patient chat |
| GET | `/api/prescriptions/:id` | With signed PDF link |

## Follow-ups, referrals, alerts
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/follow-ups` | `?tab=not_booked/booked&locationId&condition` → overdue / this week / later |
| POST | `/api/follow-ups/:id/remind`, `/api/follow-ups/remind` | `{ ids? }` |
| PATCH | `/api/follow-ups/:id` | |
| GET / POST | `/api/referrals` | `?direction=sent/received` with counts by specialty |
| POST | `/api/referrals/:id/seen` | |
| GET / POST | `/api/alerts` | `?status=open/acknowledged/resolved/all&severity&q` |
| POST | `/api/alerts/:id/acknowledge`, `/resolve`, `/note` | `{ note? }` |

## Chat & AI — Care, Nutrition, Patient-Thread, Doctor-Messages*, Chat-Review*, Chat-Summaries, Doctor-AI*
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/inbox` | `?type=care/nutrition/direct/all&tab=unread&q` |
| POST | `/api/inbox` | `{ patientId }` (care thread) or `{ userId }` (colleague) |
| GET | `/api/inbox/contacts?q` | Recent patients + team |
| GET | `/api/inbox/reviews?status=needs_review` | Flagged AI answers |
| POST | `/api/inbox/reviews/:id/reviewed` | |
| GET | `/api/inbox/summaries?date=today/yesterday&scope=mine` | AI daily digest |
| GET | `/api/conversations/:id/messages?before` | Thread, pinned message, next visit (staff + patient) |
| POST | `/api/conversations/:id/messages` | `{ text, replyToId?, recordId? }` or file (photo / PDF / audio) |
| POST | `/api/conversations/:id/read`, `/pin` | |
| POST | `/api/conversations/:id/messages/:mid/hide` · DELETE `/api/conversations/:id/messages/:mid` | |
| GET / POST | `/api/ai/sessions` | Doctor assistant, optional `patientId` |
| PATCH | `/api/ai/sessions/:id` | Change the "Talking about" patient |
| GET / POST | `/api/ai/sessions/:id/messages` | `{ text, inputMode, voiceLanguage }` |
| POST | `/api/ai/messages/:id/vote` | `{ vote: 1 / -1 }` (same again clears) |
| POST | `/api/ai/patients/:patientId/brief` | Pre-visit AI brief |

## Knowledge base & feedback
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/knowledge` | `?status&q&shared=true` with counts |
| GET / POST / PATCH | `/api/knowledge[/:id]` | Max 2000 characters |
| POST | `/api/knowledge/:id/submit`, `/approve` (doctor), `/retire` (doctor) | |
| POST / DELETE | `/api/knowledge/:id/adopt` | Shared MedPin entries |
| GET | `/api/feedback?category=care/app` | Average rating |
| POST | `/api/feedback/:id/read`, `/reply` | Reply is also sent in chat |

## Reports & dashboards
Range params for all reports: `range=today/7_days/30_days/this_month/this_year` or `from&to`;
filters `locationIds, visitTypes, modes, ageGroups (under_18,18_40,41_60,over_60), doctorId`.

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/dashboard` | Today counts, action queue, alerts, last 7 days, AI chats |
| GET | `/api/dashboard/cards` | Lab flags, BP control, condition registry, LDL, ECG, heart rate |
| GET | `/api/reports/summary` | KPIs vs previous period, splits, per-day |
| GET | `/api/reports/filter-counts` | Counts for the filter sheet |
| GET | `/api/reports/consultations`, `/prescriptions`, `/fees`, `/follow-ups`, `/daily?date` | |
| GET | `/api/referrals` | Referral report |

## Billing & exports
| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/billing` | Plan, usage meters, invoices (`?invoices=n`) |
| POST | `/api/billing/switch` | `{ planKey }` — owner only; seat check |
| GET | `/api/billing/invoices/:id/download` | Signed PDF link |
| POST | `/api/billing/webhook` | Razorpay (signature-verified) |
| POST | `/api/exports` | `{ kind: appointment_history/report/data_export, format: pdf/xlsx/csv/json, reportType?, datasets?, filters, includeMobiles, emailCopy }` |
| GET | `/api/exports` | My recent exports |

## Patient app — `/api/patient/*`
| Method | Path | Notes |
| --- | --- | --- |
| POST | `/register` | First sign-up when no record exists |
| GET / PATCH | `/me` | Profile, settings, `language`, `appLock`, BMI |
| POST | `/addresses` | |
| POST | `/consent-code` | 6-digit code valid 60 s |
| GET | `/care-team` · PATCH `/care-team/:userId` | `{ accessLevel }` |
| POST | `/clinics/:practiceId/revoke` | Stop sharing with a clinic |
| GET | `/home` | Slides, today's tasks, steps, refills, next visit, AI summary |
| GET | `/doctors/search` | `?specialty&q&today&video&female&language&withinKm&area&sort=soonest&lat&lng` |
| GET | `/doctors/:doctorId` · `/doctors/:doctorId/slots?locationId&date` | |
| GET | `/my-doctors` | Next visit, unread, medicines, adherence |
| POST | `/visit-requests` | Instant booking with `slot` unless the doctor approves each booking |
| GET | `/appointments?view=past` | |
| POST | `/appointments/:id/todos/:todoId`, `/cancel`, `/reschedule` | |
| GET / POST | `/medicines` · PATCH `/medicines/:id` | Stock, tracking, `{ stop: true }` |
| GET | `/doses?date` · POST `/doses/:id` | `{ status: taken / skipped / due }` |
| GET | `/adherence?days=30` | |
| GET / POST / DELETE | `/logs[/:id]` | Meal / exercise / steps (+ photo) |
| GET / POST | `/activity-plans` · POST `/activity-plans/:id/done` | |
| GET / POST | `/readings` | Home BP / sugar / weight / pulse / SpO₂ (alerts the clinic) |
| GET / POST | `/records` · GET `/records/:id` | Upload (+ AI test extraction) |
| POST | `/records/:id/split`, `/records/:id/share` · DELETE `/records/:id` | Records-Review |
| GET | `/cart` · POST `/cart/items` · PATCH / DELETE `/cart/items/:itemId` | `packOption: till_next_visit / 1_month / 3_months` |
| GET | `/pharmacies/quotes?mode=delivery/pickup` | |
| GET / POST | `/orders` | |
| GET / POST | `/conversations` | Chat opens once a visit is booked |
| POST | `/urgent` | `{ doctorId, text }` — urgent chat + emergency alert |
| GET | `/ai/session` · POST `/ai/ask` | Ask MedPin AI |
| POST | `/feedback` | `{ practiceId, rating, category, comment }` |
| GET | `/summary` | |
