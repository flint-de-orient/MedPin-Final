// Knowledge, Knowledge-Editor, Knowledge-Shared, Feedback.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const { requireAuth, staff, ownPractice } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, escapeRegex } = require('../lib/http');
const { careConversation, postMessage } = require('../services/care');

const r = Router();
r.use(requireAuth, staff());

const KB_FIELDS = ['title', 'summary', 'content', 'language', 'category', 'sourceCitation', 'tags'];
const cleanTags = (tags) => [...new Set((tags || []).map((t) => String(t).toLowerCase().trim()).filter(Boolean))];

r.get('/knowledge', async (req, res) => {
  const adopted = await M.KnowledgeAdoption.find({ practiceId: req.practiceId }).distinct('entryId');
  const q = { $or: [{ practiceId: req.practiceId }, { _id: { $in: adopted } }] };
  if (req.query.shared === 'true') {
    q.$or = [{ practiceId: null }];
  }
  let items = await M.KnowledgeEntry.find(q).sort({ updatedAt: -1 }).populate('updatedBy', 'name');
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    items = items.filter((e) => re.test(e.title) || re.test(e.content) || e.tags.some((t) => re.test(t)));
  }
  const counts = items.reduce((acc, e) => ({ ...acc, [e.status]: (acc[e.status] || 0) + 1 }), { all: items.length });
  if (req.query.status) items = items.filter((e) => e.status === req.query.status);
  const adoptedSet = new Set(adopted.map(String));
  res.json({ counts, items: items.map((e) => ({ ...e.toJSON(), shared: !e.practiceId, adopted: adoptedSet.has(String(e._id)) })) });
});

r.get('/knowledge/:id', async (req, res) => {
  const e = await M.KnowledgeEntry.findById(req.params.id);
  if (!e || (e.practiceId && String(e.practiceId) !== String(req.practiceId))) throw notFound('Entry');
  const adopted = await M.KnowledgeAdoption.exists({ practiceId: req.practiceId, entryId: e._id });
  res.json({ ...e.toJSON(), shared: !e.practiceId, adopted: Boolean(adopted), editable: Boolean(e.practiceId) && ['draft', 'pending'].includes(e.status) });
});

r.post('/knowledge', async (req, res) => {
  const body = pick(req.body, KB_FIELDS);
  if (!body.title || !body.content) throw badRequest('Add a title and the content');
  const e = await M.KnowledgeEntry.create({ ...body, tags: cleanTags(body.tags), practiceId: req.practiceId, status: 'draft', createdBy: req.user._id, updatedBy: req.user._id });
  res.status(201).json(e);
});

const ownEntry = async (req) => {
  const e = await M.KnowledgeEntry.findById(req.params.id);
  if (!e || !e.practiceId) throw notFound('Entry'); // shared entries are read-only
  return ownPractice(req, e, 'Entry');
};

r.patch('/knowledge/:id', async (req, res) => {
  const e = await ownEntry(req);
  if (!['draft', 'pending'].includes(e.status)) throw conflict('Approved entries can only be retired, not edited', 'NOT_EDITABLE');
  Object.assign(e, pick(req.body, KB_FIELDS));
  if (req.body.tags) e.tags = cleanTags(req.body.tags);
  e.updatedBy = req.user._id;
  e.status = 'draft'; // edits go back through approval
  await e.save();
  res.json(e);
});

r.post('/knowledge/:id/submit', async (req, res) => {
  const e = await ownEntry(req);
  if (e.status !== 'draft') throw conflict('Only drafts can be submitted');
  e.status = 'pending';
  e.submittedAt = new Date();
  await e.save();
  res.json(e);
});

r.post('/knowledge/:id/approve', staff({ roles: ['doctor'] }), async (req, res) => {
  const e = await ownEntry(req);
  if (e.status !== 'pending') throw conflict('Only pending entries can be approved');
  e.status = 'approved';
  e.approved = { by: req.user._id, at: new Date() };
  await e.save();
  res.json(e);
});

r.post('/knowledge/:id/retire', staff({ roles: ['doctor'] }), async (req, res) => {
  const e = await ownEntry(req);
  e.status = 'retired';
  e.retiredAt = new Date();
  e.retiredNote = req.body.note;
  if (req.body.supersededById) e.supersededById = req.body.supersededById;
  await e.save();
  res.json(e);
});

// Knowledge-Options: copy an entry (own or shared) into a new draft.
r.post('/knowledge/:id/duplicate', async (req, res) => {
  const e = await M.KnowledgeEntry.findById(req.params.id);
  if (!e || (e.practiceId && String(e.practiceId) !== String(req.practiceId))) throw notFound('Entry');
  const copy = await M.KnowledgeEntry.create({
    ...pick(e.toObject(), KB_FIELDS), title: `${e.title} (copy)`, practiceId: req.practiceId, status: 'draft', createdBy: req.user._id, updatedBy: req.user._id,
  });
  res.status(201).json(copy);
});

// Only drafts and entries waiting for approval can be deleted; approved ones are retired.
r.delete('/knowledge/:id', async (req, res) => {
  const e = await ownEntry(req);
  if (!['draft', 'pending'].includes(e.status)) throw conflict('Approved entries can be retired, not deleted', 'NOT_DELETABLE');
  await e.deleteOne();
  res.json({ ok: true });
});

r.post('/knowledge/:id/adopt', async (req, res) => {
  const e = await M.KnowledgeEntry.findOne({ _id: req.params.id, practiceId: null, status: 'approved' });
  if (!e) throw notFound('Shared entry');
  await M.KnowledgeAdoption.updateOne({ practiceId: req.practiceId, entryId: e._id }, { $setOnInsert: { adoptedBy: req.user._id, adoptedAt: new Date() } }, { upsert: true });
  res.json({ ok: true, adopted: true });
});

r.delete('/knowledge/:id/adopt', async (req, res) => {
  await M.KnowledgeAdoption.deleteOne({ practiceId: req.practiceId, entryId: req.params.id });
  res.json({ ok: true, adopted: false });
});

// ── Feedback ──
r.get('/feedback', async (req, res) => {
  const q = { practiceId: req.practiceId };
  const all = await M.Feedback.find(q).sort({ createdAt: -1 }).limit(300).populate('patientId', 'name').populate('readBy.userId', 'name').populate('reply.by', 'name');
  const items = req.query.category ? all.filter((f) => f.category === req.query.category) : all;
  const avg = all.length ? +(all.reduce((s, f) => s + f.rating, 0) / all.length).toFixed(1) : null;
  res.json({
    counts: { all: all.length, ...Object.fromEntries(E.FEEDBACK_CATEGORIES.map((c) => [c, all.filter((f) => f.category === c).length])) },
    averageRating: avg,
    items,
  });
});

r.post('/feedback/:id/read', async (req, res) => {
  const f = ownPractice(req, await M.Feedback.findById(req.params.id), 'Feedback');
  if (!f.readBy.some((x) => String(x.userId) === String(req.user._id))) f.readBy.push({ userId: req.user._id, at: new Date() });
  await f.save();
  res.json(f);
});

// The reply is posted in the patient's chat and kept on the feedback.
r.post('/feedback/:id/reply', staff({ perm: 'chats' }), async (req, res) => {
  const f = ownPractice(req, await M.Feedback.findById(req.params.id), 'Feedback');
  const text = String(req.body.text || '').trim();
  if (!text) throw badRequest('Write a reply');
  f.reply = { text, by: req.user._id, at: new Date() };
  await f.save();
  const convo = await careConversation(f.patientId, req.practiceId);
  await postMessage(convo, { sender: req.user, senderType: req.member.role === 'doctor' ? 'doctor' : 'staff', text });
  res.json(f);
});

module.exports = r;
