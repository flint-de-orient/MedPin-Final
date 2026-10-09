// Accounts, sign-in and invites (Auth-Login, Auth-OTP, Auth-Register,
// Profile / Staff-Profile / Patient-Me settings).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, phone, enumOf, baseOptions } = require('./common');

// One account per phone number. The same person can be a team member of
// several practices (Member) and/or a patient (Patient.userId).
const userSchema = new Schema(
  {
    phone: { ...phone(true), unique: true },
    phoneVerifiedAt: Date,
    name: { type: String, trim: true, maxlength: 120 },
    email: { type: String, trim: true, lowercase: true, match: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ },
    avatarUrl: String,
    language: enumOf(E.LANGUAGES, { default: 'en' }), // "App language"
    appLock: { type: Boolean, default: true }, // "Fingerprint or PIN to open"
    termsAcceptedAt: Date, // Register: "agree to the Terms of Use and Privacy Policy"
    activePracticeId: ref('Practice'), // context line on Doctor-Dashboard
    activeLocationId: ref('Location'),
    lastLoginAt: Date,
    disabledAt: Date,
  },
  baseOptions,
);

// 6-digit SMS codes. Codes are stored hashed and expire automatically.
const otpRequestSchema = new Schema(
  {
    phone: { ...phone(true), index: true },
    purpose: enumOf(E.OTP_PURPOSES, { required: true }),
    codeHash: { type: String, required: true },
    attempts: { type: Number, default: 0, max: 5 },
    resendCount: { type: Number, default: 0 },
    expiresAt: { type: Date, required: true },
    consumedAt: Date,
  },
  baseOptions,
);
otpRequestSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// Refresh tokens, one per signed-in device. Revoked on log out or suspension.
const authSessionSchema = new Schema(
  {
    userId: ref('User', true),
    tokenHash: { type: String, required: true, unique: true },
    platform: enumOf(E.PLATFORMS),
    deviceName: String,
    ip: String,
    expiresAt: { type: Date, required: true },
    revokedAt: Date,
  },
  baseOptions,
);
authSessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// Firebase push tokens.
const deviceTokenSchema = new Schema(
  {
    userId: ref('User', true),
    token: { type: String, required: true, unique: true },
    platform: enumOf(E.PLATFORMS, { required: true }),
    lastSeenAt: Date,
  },
  baseOptions,
);

// Register step 2: "Invite from City Care Clinic · Role: Front desk · Location: Salt Lake".
const inviteSchema = new Schema(
  {
    code: { type: String, required: true, unique: true, uppercase: true, match: /^[A-Z]{3}-\d{4}$/ },
    practiceId: ref('Practice', true),
    role: enumOf(E.MEMBER_ROLES, { required: true }),
    departmentId: ref('Department'),
    locationIds: [{ type: Schema.Types.ObjectId, ref: 'Location' }],
    phone: phone(), // optional: lock the invite to one number
    name: String,
    createdBy: ref('User', true),
    expiresAt: Date,
    usedBy: ref('User'),
    usedAt: Date,
    revokedAt: Date,
  },
  baseOptions,
);

module.exports = {
  User: model('User', userSchema),
  OtpRequest: model('OtpRequest', otpRequestSchema),
  AuthSession: model('AuthSession', authSessionSchema),
  DeviceToken: model('DeviceToken', deviceTokenSchema),
  Invite: model('Invite', inviteSchema),
};
