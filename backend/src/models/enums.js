// Every fixed option set used by the MedPin UI, in one place.
// Stored values are snake_case; the app maps them to the labels it shows.

module.exports = {
  // People
  LANGUAGES: ['en', 'bn', 'hi'], // English · বাংলা · हिन्दी
  SPOKEN_LANGUAGES: ['English', 'Bengali', 'Hindi', 'Urdu', 'Odia', 'Assamese'],
  GENDERS: ['female', 'male', 'other'],
  BLOOD_GROUPS: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'not_sure'],
  RISK_LEVELS: ['low', 'moderate', 'high', 'critical'],

  // Practice and team (People / People-Add, common_d9 role table)
  MEMBER_ROLES: [
    'doctor',
    'front_desk',
    'doctor_assistant',
    'dietician',
    'lab_manager',
    'lab_technician',
    'practice_manager',
  ],
  MEMBER_STATUSES: ['active', 'suspended'],
  PROFESSIONS: ['doctor', 'psychologist', 'physiotherapist', 'dietician', 'fitness_coach', 'other'],
  LOCATION_TYPES: ['clinic', 'chamber', 'hospital', 'nursing_home', 'diagnostic_centre', 'video'],
  LOCATION_STATUSES: ['active', 'inactive', 'view_only'],
  FOOD_LOG_REVIEW_CADENCES: ['daily', 'every_3_days', 'weekly'],
  PAYMENT_METHODS: ['upi', 'cash', 'card', 'net_banking', 'online'],
  VERIFICATION_STATUSES: ['not_submitted', 'in_review', 'verified', 'rejected'],
  PROOF_STATUSES: ['upload', 'review', 'verified'],
  // auto: worked out live (services/presence.js); away: the doctor's own "don't show me available".
  DOCTOR_PRESENCE: ['auto', 'available', 'in_clinic', 'away'],
  REMINDER_CHANNELS: ['app', 'whatsapp', 'sms'],

  // Patient ↔ care team (Patient-Me "Who can see your record")
  ACCESS_LEVELS: ['full_with_logs', 'full_record', 'prescriptions_and_tests', 'daily_log_only', 'not_shared'],
  ENROLMENT_STATUSES: ['pending_code', 'linked', 'revoked'],
  SHARE_SCOPES: ['full', 'partial'],
  TRACKED_MEASURES: ['blood_sugar', 'blood_pressure', 'hba1c', 'heart_rate', 'weight', 'spo2', 'ldl', 'creatinine'],

  // Appointments (Appointments, Queue-List, Staff-Today, Doctor-History)
  VISIT_TYPES: ['new', 'follow_up', 'report_review'],
  VISIT_MODES: ['in_clinic', 'video'],
  APPOINTMENT_STATUSES: [
    'booked',
    'confirmed',
    'waiting', // checked in
    'in_consultation',
    'completed',
    'missed',
    'cancelled',
    'rescheduled',
  ],
  CANCELLED_BY: ['patient', 'desk', 'doctor', 'system'],
  REQUEST_CHANNELS: ['app', 'whatsapp', 'phone', 'desk'],
  REQUEST_STATUSES: ['pending', 'scheduling', 'scheduled', 'declined', 'cancelled'], // scheduling: being booked (a moment)
  FEE_STATUSES: ['pending', 'paid', 'free', 'waived', 'refunded'],

  // Consultation (Consult-*, Prescriptions)
  CONSULT_STATUSES: ['draft', 'issued', 'sent'],
  DIAGNOSIS_SOURCES: ['catalog', 'reused', 'custom', 'ai'],
  RX_KINDS: ['digital', 'scanned'],
  RX_SOURCES: ['this_clinic', 'shared_by_patient', 'uploaded_by_patient'],
  FOOD_RELATIONS: ['before_food', 'after_food', 'with_food', 'empty_stomach', 'bedtime'],
  FREQUENCIES: ['daily', 'weekly', 'as_needed', 'custom'],
  WEEKDAYS: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'],
  DURATION_UNITS: ['days', 'weeks', 'months', 'ongoing'],
  RX_CHANGE: ['new', 'continued', 'changed', 'stopped'],
  ENTRY_SOURCES: ['typed', 'voice', 'suggestion'],
  VALIDITY_PRESETS: ['15_days', '1_month', '3_months', 'custom'],
  FOLLOW_UP_PRESETS: ['1_week', '2_weeks', '1_month', '3_months', 'custom', 'sos'],
  ADVICE_CATEGORIES: ['general', 'diet', 'activity', 'monitoring', 'before_next_visit', 'come_in_immediately'],

  // Vitals and readings
  VITAL_SOURCES: ['clinic', 'home', 'device', 'lab'],
  SUGAR_TYPES: ['fasting', 'random', 'post_meal'],
  DOSE_SLOTS: ['morning', 'afternoon', 'night'],
  DOSE_STATUSES: ['due', 'taken', 'skipped', 'missed'],
  COURSE_STATUSES: ['active', 'completed', 'stopped'],

  // Records and labs
  RECORD_KINDS: ['prescription', 'test_result', 'ecg', 'other'],
  RECORD_ORIGINS: ['from_doctor', 'shared_by_patient', 'uploaded_by_patient'],
  RECORD_STATUSES: ['processing', 'ready', 'failed'],
  UPLOAD_SOURCES: ['camera', 'gallery', 'pdf'],
  RESULT_FLAGS: ['critical', 'high', 'low', 'normal'],
  ECG_INTERPRETATIONS: ['normal', 'borderline', 'abnormal', 'unread'],

  // Patient health log (Patient-Log)
  LOG_TYPES: ['meal', 'exercise', 'steps'],
  MEAL_TYPES: ['breakfast', 'lunch', 'snack', 'dinner'],
  EXERCISE_TYPES: ['walk', 'yoga', 'cycling', 'other'],

  // Follow-ups and referrals
  FOLLOW_UP_STATUSES: ['not_booked', 'no_reply', 'booked', 'reports_in', 'completed', 'missed', 'cancelled'],
  FOLLOW_UP_OUTCOMES: ['on_time', 'late', 'missed'],
  REFERRAL_DIRECTIONS: ['sent', 'received'],
  REFERRAL_STATUSES: ['awaiting', 'seen', 'cancelled'],

  // Alerts (Alerts screen, home review queue)
  ALERT_SEVERITIES: ['emergency', 'urgent', 'watch'],
  ALERT_STATUSES: ['open', 'acknowledged', 'resolved'],
  ALERT_KINDS: ['urgent_chat', 'message', 'reading', 'lab', 'chat_flag', 'adherence', 'follow_up'],

  // Messaging
  CONVERSATION_TYPES: ['care', 'nutrition', 'direct'],
  PARTICIPANT_ROLES: ['patient', 'doctor', 'staff', 'dietician', 'colleague'],
  SENDER_TYPES: ['patient', 'doctor', 'staff', 'ai', 'system'],
  MESSAGE_KINDS: ['text', 'voice', 'attachment', 'record'],
  DELIVERY_STATUSES: ['sent', 'delivered', 'seen'],
  TRIAGE_CHIPS: ['needs_attention', 'check_in_due', 'review_due'],

  // AI
  AI_OWNER_TYPES: ['doctor', 'patient'],
  AI_ROLES: ['user', 'assistant'],
  INPUT_MODES: ['typed', 'spoken'],
  AI_RESPONSE_SOURCES: ['model', 'scripted'],
  REVIEW_URGENCIES: ['high', 'medium', 'low'],
  REVIEW_REASONS: ['symptom_question', 'dosage_question', 'low_confidence', 'outside_knowledge_base', 'other'],
  REVIEW_STATUSES: ['needs_review', 'reviewed'],
  SUMMARY_AUDIENCES: ['doctor', 'patient'],

  // Knowledge base
  KB_STATUSES: ['draft', 'pending', 'approved', 'retired'],
  KB_CATEGORIES: ['medicines', 'diabetes', 'hypertension', 'diet', 'infections', 'thyroid', 'other'],

  // Feedback
  FEEDBACK_CATEGORIES: ['care', 'app'],

  // Billing (Billing screen)
  PLAN_KEYS: ['starter', 'clinic', 'hospital'],
  SUBSCRIPTION_STATUSES: ['trialing', 'active', 'past_due', 'cancelled'],
  BILLING_INTERVALS: ['monthly', 'yearly'],
  INVOICE_STATUSES: ['due', 'paid', 'failed', 'refunded'],

  // Pharmacy (Med-Cart, Med-Pharmacy)
  PHARMACY_TYPES: ['online', 'nearby', 'clinic'],
  ORDER_MODES: ['delivery', 'pickup'],
  ORDER_STATUSES: [
    'placed',
    'confirmed',
    'packed',
    'out_for_delivery',
    'ready_for_pickup',
    'delivered',
    'picked_up',
    'cancelled',
  ],

  // System
  OTP_PURPOSES: ['login', 'register', 'verify_patient_phone', 'verify_member_phone'],
  NOTIFICATION_CHANNELS: ['in_app', 'push', 'sms', 'whatsapp', 'email'],
  EXPORT_KINDS: ['appointment_history', 'report', 'data_export'],
  EXPORT_FORMATS: ['pdf', 'xlsx', 'csv', 'json'],
  JOB_STATUSES: ['queued', 'running', 'done', 'failed'],
  PLATFORMS: ['android', 'ios', 'web', 'windows'],
};
