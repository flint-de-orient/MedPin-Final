// GENERATED from design/canvas.json — one entry per design artboard.
import '../core/nav.dart';
import '../data/session.dart';
import '../widgets/payment_history.dart';

import '../screens/auth/auth_login.dart';
import '../screens/auth/auth_otp.dart';
import '../screens/auth/auth_clinic_setup.dart';
import '../screens/auth/auth_patient_register.dart';
import '../screens/auth/auth_patient_address.dart';
import '../screens/auth/auth_patient_setup.dart';
import '../screens/auth/auth_register.dart';
import '../screens/auth/auth_welcome.dart';
import '../screens/auth/legal.dart';
import '../screens/doctor/doctor_home.dart';
import '../screens/doctor/care.dart';
import '../screens/doctor/nutrition.dart';
import '../screens/doctor/profile.dart';
import '../screens/doctor/home_states.dart';
import '../screens/doctor/cards_clinical.dart';
import '../screens/doctor/cards_analytics.dart';
import '../screens/doctor/patient_profile.dart';
import '../screens/doctor/patient_profile_desk.dart';
import '../screens/doctor/consult_vitals.dart';
import '../screens/doctor/consult_diagnosis.dart';
import '../screens/doctor/consult_advice.dart';
import '../screens/doctor/prescriptions.dart';
import '../screens/doctor/patient_thread.dart';
import '../screens/doctor/add_patient.dart';
import '../screens/doctor/add_patient_existing.dart';
import '../screens/doctor/alerts.dart';
import '../screens/doctor/appointments.dart';
import '../screens/doctor/appointments_manage.dart';
import '../screens/doctor/clinics.dart';
import '../screens/doctor/clinic_editor.dart';
import '../screens/doctor/departments.dart';
import '../screens/doctor/practice.dart';
import '../screens/doctor/people.dart';
import '../screens/doctor/people_add.dart';
import '../screens/doctor/people_member.dart';
import '../screens/doctor/billing.dart';
import '../screens/doctor/export.dart';
import '../screens/doctor/daily_report.dart';
import '../screens/doctor/chat_review.dart';
import '../screens/doctor/chat_review_detail.dart';
import '../screens/doctor/chat_summaries.dart';
import '../screens/doctor/knowledge.dart';
import '../screens/doctor/knowledge_editor.dart';
import '../screens/doctor/knowledge_shared.dart';
import '../screens/doctor/feedback.dart';
import '../screens/doctor/pp_summary.dart';
import '../screens/doctor/pp_prescriptions.dart';
import '../screens/doctor/pp_tests.dart';
import '../screens/doctor/pp_treatment.dart';
import '../screens/doctor/queue_select.dart';
import '../screens/doctor/queue_list.dart';
import '../screens/doctor/consult_page.dart';
import '../screens/doctor/consult_voice.dart';
import '../screens/doctor/consult_dosage.dart';
import '../screens/doctor/consult_pick.dart';
import '../screens/doctor/consult_notfound.dart';
import '../screens/doctor/consult_quickadd.dart';
import '../screens/doctor/consult_blank.dart';
import '../screens/doctor/doctor_dashboard.dart';
import '../screens/doctor/doctor_ai.dart';
import '../screens/doctor/doctor_ai_chat.dart';
import '../screens/doctor/doctor_ai_voice.dart';
import '../screens/doctor/doctor_followups.dart';
import '../screens/doctor/doctor_patients.dart';
import '../screens/doctor/doctor_patients_search.dart';
import '../screens/doctor/doctor_messages.dart';
import '../screens/doctor/doctor_messages_new.dart';
import '../screens/doctor/doctor_reports.dart';
import '../screens/doctor/doctor_reports_filter.dart';
import '../screens/doctor/report_consultations.dart';
import '../screens/doctor/report_prescriptions.dart';
import '../screens/doctor/report_fees.dart';
import '../screens/doctor/report_followups.dart';
import '../screens/doctor/report_referrals.dart';
import '../screens/doctor/report_download.dart';
import '../screens/doctor/doctor_history.dart';
import '../screens/doctor/history_download.dart';
import '../screens/doctor/doctor_myprofile.dart';
import '../screens/doctor/profile_professional.dart';
import '../screens/doctor/profile_location.dart';
import '../screens/doctor/profile_schedule.dart';
import '../screens/doctor/doctor_ai_history.dart';
import '../screens/doctor/doctor_colleagues.dart';
import '../screens/doctor/profile_about.dart';
import '../screens/doctor/profile_chat.dart';
import '../screens/doctor/profile_notifications.dart';
import '../screens/doctor/profile_payouts.dart';
import '../screens/doctor/profile_signature.dart';
import '../screens/doctor/profile_privacy.dart';
import '../screens/doctor/profile_help.dart';
import '../screens/doctor/lab_report.dart';
import '../screens/doctor/notifications.dart';
import '../screens/doctor/knowledge_options.dart';
import '../screens/staff/staff_book.dart';
import '../screens/staff/staff_payments.dart';
import '../screens/staff/staff_today.dart';
import '../screens/staff/staff_vitals.dart';
import '../screens/staff/staff_patients.dart';
import '../screens/staff/staff_profile.dart';
import '../screens/patient/patient_home.dart';
import '../screens/patient/patient_askai.dart';
import '../screens/patient/patient_adherence.dart';
import '../screens/patient/patient_track.dart';
import '../screens/patient/patient_records.dart';
import '../screens/patient/records_add.dart';
import '../screens/patient/records_review.dart';
import '../screens/patient/patient_log.dart';
import '../screens/patient/hero_carousel.dart';
import '../screens/patient/patient_emergency.dart';
import '../screens/patient/patient_chat.dart';
import '../screens/patient/patient_me.dart';
import '../screens/patient/patient_doctors.dart';
import '../screens/patient/patient_doctordetail.dart';
import '../screens/patient/patient_doctorchat.dart';
import '../screens/patient/patient_finddoctor.dart';
import '../screens/patient/patient_medicines.dart';
import '../screens/patient/med_addtocart.dart';
import '../screens/patient/med_cart.dart';
import '../screens/patient/med_pharmacy.dart';

/// Every screen of the MedPin design (plus the patient Profile tab and Find a
/// doctor), doctor panel first, then front desk, then patient app.
final Map<String, ScreenSpec> screenRegistry = {
  'Auth-Login': ScreenSpec(stem: 'Auth-Login', title: 'Login', group: 'Sign in', panel: 'doctor', builder: (_) => const AuthLoginScreen()),
  'Auth-OTP': ScreenSpec(stem: 'Auth-OTP', title: 'Login · code', group: 'Sign in', panel: 'doctor', builder: (_) => const AuthOtpScreen()),
  'Auth-Register': ScreenSpec(stem: 'Auth-Register', title: 'Register', group: 'Sign in', panel: 'doctor', builder: (_) => const AuthRegisterScreen()),
  'Auth-Welcome': ScreenSpec(stem: 'Auth-Welcome', title: 'Welcome · doctor or patient', group: 'Sign in', panel: 'doctor', builder: (_) => const AuthWelcomeScreen()),
  'Auth-Clinic-Setup': ScreenSpec(stem: 'Auth-Clinic-Setup', title: 'Start your clinic', group: 'Sign in', panel: 'doctor', builder: (_) => const AuthClinicSetupScreen()),
  'Auth-Patient-Register': ScreenSpec(stem: 'Auth-Patient-Register', title: 'Register · patient', group: 'Sign in', panel: 'patient', builder: (_) => const AuthPatientRegisterScreen()),
  'Auth-Patient-Setup': ScreenSpec(stem: 'Auth-Patient-Setup', title: 'Patient sign-up', group: 'Sign in', panel: 'patient', builder: (_) => const AuthPatientSetupScreen()),
  'Auth-Patient-Address': ScreenSpec(stem: 'Auth-Patient-Address', title: 'Patient sign-up · address', group: 'Sign in', panel: 'patient', builder: (_) => const AuthPatientAddressScreen()),
  'Legal': ScreenSpec(stem: 'Legal', title: 'Terms of Use · Privacy Policy', group: 'Sign in', panel: 'doctor', builder: (_) => const LegalScreen()),
  'Doctor-Home': ScreenSpec(stem: 'Doctor-Home', title: 'Home', group: 'Clinician · tabs', panel: 'doctor', builder: (_) => const DoctorHomeScreen()),
  'Care': ScreenSpec(stem: 'Care', title: 'Care', group: 'Clinician · tabs', panel: 'doctor', builder: (_) => const CareScreen()),
  'Nutrition': ScreenSpec(stem: 'Nutrition', title: 'Nutrition', group: 'Clinician · tabs', panel: 'doctor', builder: (_) => const NutritionScreen()),
  'Profile': ScreenSpec(stem: 'Profile', title: 'Profile', group: 'Clinician · tabs', panel: 'doctor', builder: (_) => const ProfileScreen()),
  'Home-States': ScreenSpec(stem: 'Home-States', title: 'Home · states', group: 'Clinician · tabs', panel: 'doctor', builder: (_) => const HomeStatesScreen()),
  'Cards-Clinical': ScreenSpec(stem: 'Cards-Clinical', title: 'Cards · queue & clinical', group: 'Dashboard cards', panel: 'doctor', builder: (_) => const CardsClinicalScreen()),
  'Cards-Analytics': ScreenSpec(stem: 'Cards-Analytics', title: 'Cards · analytics', group: 'Dashboard cards', panel: 'doctor', builder: (_) => const CardsAnalyticsScreen()),
  'Patient-Profile': ScreenSpec(stem: 'Patient-Profile', title: 'Patient profile', group: 'Patient care', panel: 'doctor', builder: (_) => Session.I.role == null || Session.I.can('clinical') ? const PatientProfileScreen() : const PatientProfileDeskScreen()),
  'Patient-Profile-Desk': ScreenSpec(stem: 'Patient-Profile-Desk', title: 'Patient profile · front desk', group: 'Patient care', panel: 'doctor', builder: (_) => const PatientProfileDeskScreen()),
  'Consult-Vitals': ScreenSpec(stem: 'Consult-Vitals', title: 'Consult 1 · Vitals', group: 'Patient care', panel: 'doctor', builder: (_) => const ConsultVitalsScreen()),
  'Consult-Diagnosis': ScreenSpec(stem: 'Consult-Diagnosis', title: 'Consult 2 · Diagnosis', group: 'Patient care', panel: 'doctor', builder: (_) => const ConsultDiagnosisScreen()),
  'Consult-Advice': ScreenSpec(stem: 'Consult-Advice', title: 'Consult 3 · Advice', group: 'Patient care', panel: 'doctor', builder: (_) => const ConsultAdviceScreen()),
  'Prescriptions': ScreenSpec(stem: 'Prescriptions', title: 'Prescriptions', group: 'Patient care', panel: 'doctor', builder: (_) => const PrescriptionsScreen()),
  'Patient-Thread': ScreenSpec(stem: 'Patient-Thread', title: 'Patient thread', group: 'Patient care', panel: 'doctor', builder: (_) => const PatientThreadScreen()),
  'Add-Patient': ScreenSpec(stem: 'Add-Patient', title: 'Add patient', group: 'Patient care', panel: 'doctor', builder: (_) => const AddPatientScreen()),
  'Add-Patient-Existing': ScreenSpec(stem: 'Add-Patient-Existing', title: 'Add patient · existing account', group: 'Patient care', panel: 'doctor', builder: (_) => const AddPatientExistingSheet(), sheet: true, parent: 'Add-Patient'),
  'Alerts': ScreenSpec(stem: 'Alerts', title: 'Alerts', group: 'Clinic operations', panel: 'doctor', builder: (_) => const AlertsScreen()),
  'Appointments': ScreenSpec(stem: 'Appointments', title: 'Appointments', group: 'Clinic operations', panel: 'doctor', builder: (_) => const AppointmentsScreen()),
  'Appointments-Manage': ScreenSpec(stem: 'Appointments-Manage', title: 'Appointments · manage', group: 'Clinic operations', panel: 'doctor', builder: (_) => const AppointmentsManageSheet(), sheet: true, parent: 'Appointments'),
  'Clinics': ScreenSpec(stem: 'Clinics', title: 'Locations', group: 'Clinic operations', panel: 'doctor', builder: (_) => const ClinicsScreen()),
  'Clinic-Editor': ScreenSpec(stem: 'Clinic-Editor', title: 'Location editor', group: 'Clinic operations', panel: 'doctor', builder: (_) => const ClinicEditorScreen()),
  'Departments': ScreenSpec(stem: 'Departments', title: 'Departments', group: 'Clinic operations', panel: 'doctor', builder: (_) => const DepartmentsScreen()),
  'Practice': ScreenSpec(stem: 'Practice', title: 'Practice', group: 'Clinic operations', panel: 'doctor', builder: (_) => const PracticeScreen()),
  'People': ScreenSpec(stem: 'People', title: 'People', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const PeopleScreen()),
  'People-Add': ScreenSpec(stem: 'People-Add', title: 'People · add', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const PeopleAddScreen()),
  'People-Member': ScreenSpec(stem: 'People-Member', title: 'People · member', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const PeopleMemberScreen()),
  'Billing': ScreenSpec(stem: 'Billing', title: 'Plan & billing', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const BillingScreen()),
  'Export': ScreenSpec(stem: 'Export', title: 'Export', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const ExportScreen()),
  'Daily-Report': ScreenSpec(stem: 'Daily-Report', title: 'Daily report', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const DailyReportScreen()),
  'Chat-Review': ScreenSpec(stem: 'Chat-Review', title: 'Chat review', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const ChatReviewScreen()),
  'Chat-Review-Detail': ScreenSpec(stem: 'Chat-Review-Detail', title: 'Chat review · detail', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const ChatReviewDetailScreen()),
  'Chat-Summaries': ScreenSpec(stem: 'Chat-Summaries', title: 'Chat summaries', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const ChatSummariesScreen()),
  'Knowledge': ScreenSpec(stem: 'Knowledge', title: 'Knowledge base', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const KnowledgeScreen()),
  'Knowledge-Editor': ScreenSpec(stem: 'Knowledge-Editor', title: 'Knowledge · edit', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const KnowledgeEditorScreen()),
  'Knowledge-Shared': ScreenSpec(stem: 'Knowledge-Shared', title: 'Knowledge · shared', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const KnowledgeSharedScreen()),
  'Feedback': ScreenSpec(stem: 'Feedback', title: 'Feedback', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const FeedbackScreen()),
  'PP-Summary': ScreenSpec(stem: 'PP-Summary', title: 'Patient profile · Summary', group: 'Patient profile · tabs (doctor view)', panel: 'doctor', builder: (_) => const PpSummaryScreen()),
  'PP-Prescriptions': ScreenSpec(stem: 'PP-Prescriptions', title: 'Patient profile · Prescriptions', group: 'Patient profile · tabs (doctor view)', panel: 'doctor', builder: (_) => const PpPrescriptionsScreen()),
  'PP-Tests': ScreenSpec(stem: 'PP-Tests', title: 'Patient profile · Test results', group: 'Patient profile · tabs (doctor view)', panel: 'doctor', builder: (_) => const PpTestsScreen()),
  'PP-Treatment': ScreenSpec(stem: 'PP-Treatment', title: 'Patient profile · Treatment plan', group: 'Patient profile · tabs (doctor view)', panel: 'doctor', builder: (_) => const PpTreatmentScreen()),
  'Queue-Select': ScreenSpec(stem: 'Queue-Select', title: 'Patient queue · choose location', group: 'Patient queue', panel: 'doctor', builder: (_) => const QueueSelectSheet(), sheet: true, parent: 'Doctor-Dashboard'),
  'Queue-List': ScreenSpec(stem: 'Queue-List', title: 'Patient queue', group: 'Patient queue', panel: 'doctor', builder: (_) => const QueueListScreen()),
  'Consult-Page': ScreenSpec(stem: 'Consult-Page', title: 'Consultation · from patient (auto-filled)', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultPageScreen()),
  'Consult-Voice': ScreenSpec(stem: 'Consult-Voice', title: 'Consultation · medicine by voice', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultVoiceSheet(), sheet: true, parent: 'Consult-Page'),
  'Consult-Dosage': ScreenSpec(stem: 'Consult-Dosage', title: 'Consultation · set dosage', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultDosageSheet(), sheet: true, parent: 'Consult-Page'),
  'Consult-Pick': ScreenSpec(stem: 'Consult-Pick', title: 'Consultation · not from a patient: search', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultPickScreen()),
  'Consult-NotFound': ScreenSpec(stem: 'Consult-NotFound', title: 'Consultation · patient not found', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultNotfoundScreen()),
  'Consult-QuickAdd': ScreenSpec(stem: 'Consult-QuickAdd', title: 'Consultation · add new patient', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultQuickaddSheet(), sheet: true, parent: 'Consult-NotFound'),
  'Consult-Blank': ScreenSpec(stem: 'Consult-Blank', title: 'Consultation · fresh start, no records', group: 'Consultation', panel: 'doctor', builder: (_) => const ConsultBlankScreen()),
  'Doctor-Dashboard': ScreenSpec(stem: 'Doctor-Dashboard', title: 'Doctor · dashboard (redesign)', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const DoctorDashboardScreen()),
  'Doctor-AI': ScreenSpec(stem: 'Doctor-AI', title: 'Doctor · AI Assistant (landing)', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const DoctorAiScreen()),
  'Doctor-AI-Chat': ScreenSpec(stem: 'Doctor-AI-Chat', title: 'Doctor · AI Assistant · answers with Listen', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const DoctorAiChatScreen()),
  'Doctor-AI-Voice': ScreenSpec(stem: 'Doctor-AI-Voice', title: 'Doctor · AI Assistant · voice', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const DoctorAiVoiceSheet(), sheet: true, parent: 'Doctor-AI'),
  'Doctor-FollowUps': ScreenSpec(stem: 'Doctor-FollowUps', title: 'Doctor · Follow-ups (quick action)', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const DoctorFollowupsScreen()),
  'Doctor-Patients': ScreenSpec(stem: 'Doctor-Patients', title: 'Doctor · Patients tab', group: 'Doctor · Patients tab', panel: 'doctor', builder: (_) => const DoctorPatientsScreen()),
  'Doctor-Patients-Search': ScreenSpec(stem: 'Doctor-Patients-Search', title: 'Doctor · Patients · search by name or mobile', group: 'Doctor · Patients tab', panel: 'doctor', builder: (_) => const DoctorPatientsSearchScreen()),
  'Doctor-Messages': ScreenSpec(stem: 'Doctor-Messages', title: 'Doctor · Messages tab', group: 'Doctor · Messages tab', panel: 'doctor', builder: (_) => const DoctorMessagesScreen()),
  'Doctor-Messages-New': ScreenSpec(stem: 'Doctor-Messages-New', title: 'Doctor · Messages · start a new chat', group: 'Doctor · Messages tab', panel: 'doctor', builder: (_) => const DoctorMessagesNewSheet(), sheet: true, parent: 'Doctor-Messages'),
  'Doctor-Reports': ScreenSpec(stem: 'Doctor-Reports', title: 'Doctor · Reports (consultation MIS)', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const DoctorReportsScreen()),
  'Doctor-Reports-Filter': ScreenSpec(stem: 'Doctor-Reports-Filter', title: 'Doctor · Reports · filters', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const DoctorReportsFilterSheet(), sheet: true, parent: 'Doctor-Reports'),
  'Report-Consultations': ScreenSpec(stem: 'Report-Consultations', title: 'Report · Consultation register', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const ReportConsultationsScreen()),
  'Report-Prescriptions': ScreenSpec(stem: 'Report-Prescriptions', title: 'Report · Prescription register', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const ReportPrescriptionsScreen()),
  'Report-Fees': ScreenSpec(stem: 'Report-Fees', title: 'Report · Fees and collections', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const ReportFeesScreen()),
  'Report-FollowUps': ScreenSpec(stem: 'Report-FollowUps', title: 'Report · Follow-up compliance', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const ReportFollowupsScreen()),
  'Report-Referrals': ScreenSpec(stem: 'Report-Referrals', title: 'Report · Referrals', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const ReportReferralsScreen()),
  'Report-Download': ScreenSpec(stem: 'Report-Download', title: 'Report · download options', group: 'Doctor · Reports tab', panel: 'doctor', builder: (_) => const ReportDownloadSheet(), sheet: true, parent: 'Doctor-Reports'),
  'Doctor-History': ScreenSpec(stem: 'Doctor-History', title: 'Doctor · History (all appointments)', group: 'Doctor · History tab', panel: 'doctor', builder: (_) => const DoctorHistoryScreen()),
  'History-Download': ScreenSpec(stem: 'History-Download', title: 'Doctor · History · download', group: 'Doctor · History tab', panel: 'doctor', builder: (_) => const HistoryDownloadSheet(), sheet: true, parent: 'Doctor-History'),
  'Doctor-MyProfile': ScreenSpec(stem: 'Doctor-MyProfile', title: 'Doctor · My profile (settings hub)', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const DoctorMyprofileScreen()),
  'Profile-Professional': ScreenSpec(stem: 'Profile-Professional', title: 'Profile · professional details', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileProfessionalScreen()),
  'Profile-Location': ScreenSpec(stem: 'Profile-Location', title: 'Profile · location: map, address, fees', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileLocationScreen()),
  'Profile-Schedule': ScreenSpec(stem: 'Profile-Schedule', title: 'Profile · schedules and slots', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileScheduleScreen()),
  // Added after the design, in the same style (were "coming soon" in the design).
  'Profile-About': ScreenSpec(stem: 'Profile-About', title: 'Profile · about and photo', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileAboutScreen()),
  'Profile-Chat': ScreenSpec(stem: 'Profile-Chat', title: 'Profile · chat and urgent messages', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileChatScreen()),
  'Profile-Notifications': ScreenSpec(stem: 'Profile-Notifications', title: 'Profile · notifications', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileNotificationsScreen()),
  'Profile-Signature': ScreenSpec(stem: 'Profile-Signature', title: 'Profile · letterhead and signature', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileSignatureScreen()),
  'Profile-Payouts': ScreenSpec(stem: 'Profile-Payouts', title: 'Profile · payouts and bank account', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfilePayoutsScreen()),
  'Profile-Privacy': ScreenSpec(stem: 'Profile-Privacy', title: 'Profile · privacy and data', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfilePrivacyScreen()),
  'Profile-Help': ScreenSpec(stem: 'Profile-Help', title: 'Profile · help and support', group: 'Doctor · My profile & settings', panel: 'doctor', builder: (_) => const ProfileHelpScreen()),
  'Doctor-Colleagues': ScreenSpec(stem: 'Doctor-Colleagues', title: 'Doctor · Colleagues you work with', group: 'Team, billing & reports', panel: 'doctor', builder: (_) => const DoctorColleaguesScreen()),
  'Doctor-AI-History': ScreenSpec(stem: 'Doctor-AI-History', title: 'Doctor · AI Assistant · history', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const DoctorAiHistoryScreen()),
  'Notifications': ScreenSpec(stem: 'Notifications', title: 'Notifications (staff)', group: 'Doctor dashboard & AI Assistant', panel: 'doctor', builder: (_) => const NotificationsScreen()),
  'Lab-Report': ScreenSpec(stem: 'Lab-Report', title: 'Patient profile · lab report', group: 'Patient profile · tabs (doctor view)', panel: 'doctor', builder: (_) => const LabReportScreen()),
  'Knowledge-Options': ScreenSpec(stem: 'Knowledge-Options', title: 'Knowledge · entry options', group: 'AI assistant & feedback', panel: 'doctor', builder: (_) => const KnowledgeOptionsSheet(), sheet: true, parent: 'Knowledge-Editor'),
  'Staff-Book': ScreenSpec(stem: 'Staff-Book', title: 'Book appointment', group: 'Front desk', panel: 'staff', builder: (_) => const StaffBookScreen()),
  'Staff-Today': ScreenSpec(stem: 'Staff-Today', title: 'Today', group: 'Front desk', panel: 'staff', builder: (_) => const StaffTodayScreen()),
  'Staff-Patients': ScreenSpec(stem: 'Staff-Patients', title: 'Patients', group: 'Front desk', panel: 'staff', builder: (_) => const StaffPatientsScreen()),
  'Staff-Profile': ScreenSpec(stem: 'Staff-Profile', title: 'Profile', group: 'Front desk', panel: 'staff', builder: (_) => const StaffProfileScreen()),
  'Staff-Payments': ScreenSpec(stem: 'Staff-Payments', title: 'Payments', group: 'Front desk', panel: 'staff', builder: (_) => const StaffPaymentsScreen()),
  'Staff-Vitals': ScreenSpec(stem: 'Staff-Vitals', title: 'Record vitals', group: 'Front desk', panel: 'staff', builder: (_) => const StaffVitalsScreen()),
  'Main': ScreenSpec(stem: 'Main', title: 'Patient · Home', group: 'Patient app', panel: 'patient', builder: (_) => const PatientHomeScreen()),
  'Patient-AskAI': ScreenSpec(stem: 'Patient-AskAI', title: 'Patient · Ask MedPin AI', group: 'Patient app', panel: 'patient', builder: (_) => const PatientAskaiSheet(), sheet: true, parent: 'Main'),
  'Patient-Adherence': ScreenSpec(stem: 'Patient-Adherence', title: 'Patient · adherence by doctor', group: 'Patient app', panel: 'patient', builder: (_) => const PatientAdherenceSheet(), sheet: true, parent: 'Main'),
  'Patient-Track': ScreenSpec(stem: 'Patient-Track', title: 'Patient · choose what to track', group: 'Patient app', panel: 'patient', builder: (_) => const PatientTrackSheet(), sheet: true, parent: 'Main'),
  'Patient-Records': ScreenSpec(stem: 'Patient-Records', title: 'Patient · Health records', group: 'Patient app', panel: 'patient', builder: (_) => const PatientRecordsScreen()),
  'Records-Add': ScreenSpec(stem: 'Records-Add', title: 'Records · add a record', group: 'Patient app', panel: 'patient', builder: (_) => const RecordsAddSheet(), sheet: true, parent: 'Patient-Records'),
  'Records-Review': ScreenSpec(stem: 'Records-Review', title: 'Records · check and save (multi-test file)', group: 'Patient app', panel: 'patient', builder: (_) => const RecordsReviewScreen()),
  'Patient-Log': ScreenSpec(stem: 'Patient-Log', title: 'Patient · log meal, exercise, steps', group: 'Patient app', panel: 'patient', builder: (_) => const PatientLogSheet(), sheet: true, parent: 'Main'),
  'Hero-Carousel': ScreenSpec(stem: 'Hero-Carousel', title: 'Patient · home carousel slides', group: 'Patient app', panel: 'patient', builder: (_) => const HeroCarouselScreen()),
  'Patient-Emergency': ScreenSpec(stem: 'Patient-Emergency', title: 'Patient · emergency: choose doctor', group: 'Patient app', panel: 'patient', builder: (_) => const PatientEmergencySheet(), sheet: true, parent: 'Main'),
  'Patient-Chat': ScreenSpec(stem: 'Patient-Chat', title: 'Patient · urgent chat with doctor', group: 'Patient app', panel: 'patient', builder: (_) => const PatientChatScreen()),
  // Not an artboard in the design canvas: the patient app's Profile tab.
  'Patient-Payments': ScreenSpec(stem: 'Patient-Payments', title: 'Patient · Payments and receipts', group: 'Patient app', panel: 'patient', builder: (_) => const PatientPaymentsScreen()),
  'Patient-Me': ScreenSpec(stem: 'Patient-Me', title: 'Patient · My profile', group: 'Patient app', panel: 'patient', builder: (_) => const PatientMeScreen()),
  'Patient-Doctors': ScreenSpec(stem: 'Patient-Doctors', title: 'Patient · Doctor tab: my doctors', group: 'Patient app · Doctor tab', panel: 'patient', builder: (_) => const PatientDoctorsScreen()),
  'Patient-DoctorDetail': ScreenSpec(stem: 'Patient-DoctorDetail', title: 'Patient · doctor page (Dr. Sen)', group: 'Patient app · Doctor tab', panel: 'patient', builder: (_) => const PatientDoctordetailScreen()),
  'Patient-DoctorChat': ScreenSpec(stem: 'Patient-DoctorChat', title: 'Patient · chat with doctor', group: 'Patient app · Doctor tab', panel: 'patient', builder: (_) => const PatientDoctorchatScreen()),
  // Not an artboard in the design canvas: opened from the Doctor tab banner.
  'Patient-FindDoctor': ScreenSpec(stem: 'Patient-FindDoctor', title: 'Patient · Find a doctor (MedPin AI)', group: 'Patient app · Doctor tab', panel: 'patient', builder: (_) => const PatientFinddoctorScreen()),
  'Patient-Medicines': ScreenSpec(stem: 'Patient-Medicines', title: 'Patient · Medicines tab', group: 'Patient app · Medicines tab', panel: 'patient', builder: (_) => const PatientMedicinesScreen()),
  'Med-AddToCart': ScreenSpec(stem: 'Med-AddToCart', title: 'Medicines · add to cart', group: 'Patient app · Medicines tab', panel: 'patient', builder: (_) => const MedAddtocartSheet(), sheet: true, parent: 'Patient-Medicines'),
  'Med-Cart': ScreenSpec(stem: 'Med-Cart', title: 'Medicines · cart', group: 'Patient app · Medicines tab', panel: 'patient', builder: (_) => const MedCartScreen()),
  'Med-Pharmacy': ScreenSpec(stem: 'Med-Pharmacy', title: 'Medicines · choose pharmacy', group: 'Patient app · Medicines tab', panel: 'patient', builder: (_) => const MedPharmacyScreen()),
};
