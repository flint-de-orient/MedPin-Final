// Doctor proof checks: an uploaded degree / registration proof goes to the
// MedPin team (SUPPORT_EMAIL, or VERIFY_EMAIL) as a private link with
// Approve / Reject. The link is signed, so it needs no sign-in and can't be guessed.
const M = require('../models');
const env = require('../config/env');
const storage = require('./storage');
const { hmac, safeEqual } = require('../lib/security');
const { publicBase } = require('../lib/request-base');
const { sendEmail } = require('./email');
const { notify } = require('./notify');

const tokenFor = (userId, qid) => hmac(`proof:${userId}:${qid}`);
const validToken = (userId, qid, t) => Boolean(t) && safeEqual(tokenFor(userId, qid), String(t));
const reviewUrl = (userId, qid) => `${publicBase()}/review/proofs/${userId}/${qid}?t=${tokenFor(userId, qid)}`;
const reviewer = () => process.env.VERIFY_EMAIL || env.support.email;

async function requestReview(profile, q) {
  const url = reviewUrl(profile.userId, q._id);
  const to = reviewer();
  if (!to) {
    console.log(`[verify] no SUPPORT_EMAIL / VERIFY_EMAIL set; review link: ${url}`);
    return { url, sent: false };
  }
  const out = await sendEmail({
    to, subject: `Verify ${profile.displayName}: ${q.name}`,
    text: `${profile.displayName} uploaded proof for "${q.name}"${q.institution ? ` (${q.institution}${q.year ? `, ${q.year}` : ''})` : ''}.\nRegistration: ${profile.registration?.number || 'not given'} ${profile.registration?.council || ''}\n\nCheck and approve or reject:\n${url}`,
  }).catch((err) => ({ error: err.message }));
  return { url, sent: !out?.skipped && !out?.error };
}

const esc = (s) => String(s ?? '').replace(/[<>&"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' })[c]);

async function find(userId, qid) {
  const profile = /^[a-f\d]{24}$/i.test(userId) ? await M.DoctorProfile.findOne({ userId }) : null;
  const q = profile?.qualifications.id(qid);
  return q ? { profile, q } : null;
}

async function reviewPage(userId, qid, t) {
  if (!validToken(userId, qid, t)) return null;
  const found = await find(userId, qid);
  if (!found) return null;
  const { profile, q } = found;
  const proofUrl = q.proof?.key ? storage.signedUrl(q.proof.key, 3600) : null;
  const status = { review: 'Waiting for review', verified: 'Verified ✓', upload: 'No proof (or rejected)' }[q.proofStatus] || q.proofStatus;
  return `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Verify proof</title>
<body style="font-family:system-ui,sans-serif;max-width:520px;margin:32px auto;padding:0 16px;color:#111827">
<p style="color:#69738A;font-weight:600">MedPin · doctor verification</p>
<h2 style="margin:4px 0">${esc(profile.displayName)}</h2>
<p>${esc(q.name)}${q.institution ? ` · ${esc(q.institution)}` : ''}${q.year ? ` · ${esc(q.year)}` : ''}</p>
<p>Registration: <b>${esc(profile.registration?.number || 'not given')}</b> ${esc(profile.registration?.council || '')}</p>
<p>Status: <b>${esc(status)}</b></p>
${proofUrl ? `<p><a href="${esc(proofUrl)}" target="_blank" rel="noopener">Open the proof document</a></p>` : '<p>No document uploaded.</p>'}
<form method="post" style="margin-top:20px">
<input type="hidden" name="t" value="${esc(t)}">
<input name="note" placeholder="Reason, if rejecting" style="width:100%;box-sizing:border-box;height:44px;border:1px solid #C9D1DE;border-radius:12px;padding:0 12px">
<div style="display:flex;gap:12px;margin-top:12px">
<button name="decision" value="approve" style="flex:1;height:48px;border:0;border-radius:12px;background:#076B3C;color:#fff;font-size:16px;font-weight:600">Approve</button>
<button name="decision" value="reject" style="flex:1;height:48px;border:0;border-radius:12px;background:#B42318;color:#fff;font-size:16px;font-weight:600">Reject</button>
</div>
</form>
</body>`;
}

/** Approve or reject; tells the doctor. Returns the qualification or null. */
async function decide(userId, qid, t, decision, note) {
  if (!validToken(userId, qid, t) || !['approve', 'reject'].includes(decision)) return null;
  const found = await find(userId, qid);
  if (!found) return null;
  const { profile, q } = found;
  q.proofStatus = decision === 'approve' ? 'verified' : 'upload';
  q.proofNote = decision === 'reject' ? String(note || 'Please upload a clearer copy').slice(0, 300) : undefined;
  // "Verified" badge once every qualification is verified and a registration number is on file.
  profile.isVerified = Boolean(profile.registration?.number) && profile.qualifications.length > 0 && profile.qualifications.every((x) => x.proofStatus === 'verified');
  await profile.save();
  await notify([profile.userId], {
    type: 'proof_review', title: decision === 'approve' ? `${q.name} verified` : `${q.name}: proof not accepted`,
    body: decision === 'approve' ? (profile.isVerified ? 'Your profile now shows the Verified badge.' : 'Thank you. Your other proofs are still in review.') : q.proofNote,
    screen: 'Profile-Professional',
  }).catch(() => {});
  return q;
}

module.exports = { requestReview, reviewPage, decide, reviewUrl };
