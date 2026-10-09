const { Schema } = require('mongoose');

const { ObjectId } = Schema.Types;

/** Required/optional reference to another collection. */
const ref = (model, required = false) => ({ type: ObjectId, ref: model, required, index: true });

/** Indian mobile number, stored as 10 digits without +91 or spaces. */
const phone = (required = false) => ({
  type: String,
  required,
  trim: true,
  match: [/^[6-9]\d{9}$/, 'Enter a 10-digit mobile number'],
});

/** Landline or mobile as typed, e.g. "033 4012 5678" or "+91 33 4000 1234". */
const anyPhone = { type: String, trim: true, maxlength: 20 };

/** Whole rupees (the UI never shows paise). */
const rupees = { type: Number, min: 0, validate: Number.isInteger };

/** Minutes since midnight, e.g. 9:00 AM = 540. */
const minuteOfDay = { type: Number, min: 0, max: 1440 };

const enumOf = (values, extra = {}) => ({ type: String, enum: values, ...extra });

/** A stored file (S3 key plus what the UI shows about it). */
const fileSchema = new Schema(
  {
    key: { type: String, required: true }, // storage object key
    url: String,
    name: String, // "Lipid profile.pdf"
    mimeType: String,
    sizeBytes: Number,
    pages: Number,
  },
  { _id: false },
);

/** GeoJSON point for clinic pins and "near me" doctor search. */
const pointSchema = new Schema(
  {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], required: true }, // [lng, lat]
  },
  { _id: false },
);

/** Who did something and when (acknowledge, resolve, review, reply…). */
const actionStamp = new Schema(
  {
    by: { type: ObjectId, ref: 'User' },
    at: Date,
  },
  { _id: false },
);

const baseOptions = {
  timestamps: true,
  toJSON: {
    virtuals: true,
    versionKey: false,
    transform(_doc, ret) {
      ret.id = ret._id;
      delete ret._id;
      return ret;
    },
  },
};

module.exports = {
  ObjectId,
  ref,
  phone,
  anyPhone,
  rupees,
  minuteOfDay,
  enumOf,
  fileSchema,
  pointSchema,
  actionStamp,
  baseOptions,
};
