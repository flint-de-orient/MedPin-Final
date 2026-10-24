// Notifications in the reader's language. Every notification is written in English
// where it is raised (services/notify.js callers); notify() stores and pushes it in
// each recipient's app language (User.language: en | bn | hi) using these templates.
//
// Each template: { en: /^English with (.+)$/, bn, hi } — bn / hi are strings (or
// functions of the match) where a capture is put back as:
//   $1  as it is (names, amounts, times, medicine names)
//   %1  translated when it is one of the fixed words below ("the doctor", "Front desk",
//       "cash"…), else as it is
//   &1  Bengali possessive ("…-এর"; "the doctor" → "ডাক্তারের"); elsewhere like %1
//   ~1  Bengali object ("…-কে"; "the patient" → "রোগীকে"); elsewhere like %1
//   #1  dates: weekday / month names, today / tomorrow translated
//   @1  translated again with these templates (an alert's detail inside a title, a reason…)
// A template with `inner: [n]` only applies when capture n itself translates.
// Text no template matches is tried part by part (split at " · "); anything still
// unknown (a patient's own message, a free-text reason) stays as it is.
// Keep the order: more specific templates first. New English notification text needs a
// template here — scripts/test-notify-i18n.js fails for text in notify() calls that has none.

const LANGS = ['bn', 'hi'];

/** Fixed words that appear inside notification text (fallback names, labels, statuses). */
const WORDS = {
  bn: {
    'A patient': 'একজন রোগী', 'a patient': 'একজন রোগী', Patient: 'রোগী', patient: 'রোগী', 'the patient': 'রোগী',
    'Your doctor': 'আপনার ডাক্তার', 'your doctor': 'আপনার ডাক্তার', 'The doctor': 'ডাক্তার', 'the doctor': 'ডাক্তার',
    Clinic: 'ক্লিনিক', clinic: 'ক্লিনিক', 'the clinic': 'ক্লিনিক', 'Your care team': 'আপনার চিকিৎসক দল',
    Doctor: 'ডাক্তার', 'Front desk': 'রিসেপশন', "Doctor's assistant": 'ডাক্তারের সহকারী', Dietician: 'ডায়েটিশিয়ান',
    'Lab manager': 'ল্যাব ম্যানেজার', 'Lab technician': 'ল্যাব টেকনিশিয়ান', 'Practice manager': 'প্র্যাকটিস ম্যানেজার',
    'All locations': 'সব লোকেশন',
    'full with logs': 'সম্পূর্ণ রেকর্ড, দৈনিক লগ ও ভাইটালস', 'full record': 'সম্পূর্ণ রেকর্ড', 'prescriptions and tests': 'প্রেসক্রিপশন ও টেস্ট',
    'daily log only': 'শুধু দৈনিক লগ', 'not shared': 'শেয়ার করা নেই',
    Placed: 'দেওয়া হয়েছে', Confirmed: 'নিশ্চিত', Packed: 'প্যাক হয়েছে', 'Out for delivery': 'ডেলিভারির পথে', 'Ready for pick-up': 'নেওয়ার জন্য তৈরি',
    Delivered: 'পৌঁছেছে', 'Picked up': 'নেওয়া হয়েছে', Cancelled: 'বাতিল',
    cash: 'নগদ', card: 'কার্ড', UPI: 'UPI',
    'Closed all day': 'সারা দিন বন্ধ', 'Closed part of the day': 'দিনের কিছু সময় বন্ধ',
    Photo: 'ছবি', 'Urgent message': 'জরুরি মেসেজ', 'Voice message': 'ভয়েস মেসেজ', 'Photo or file': 'ছবি বা ফাইল', 'Message deleted': 'মেসেজ মুছে ফেলা হয়েছে',
  },
  hi: {
    'A patient': 'एक मरीज़', 'a patient': 'एक मरीज़', Patient: 'मरीज़', patient: 'मरीज़', 'the patient': 'मरीज़',
    'Your doctor': 'आपके डॉक्टर', 'your doctor': 'आपके डॉक्टर', 'The doctor': 'डॉक्टर', 'the doctor': 'डॉक्टर',
    Clinic: 'क्लिनिक', clinic: 'क्लिनिक', 'the clinic': 'क्लिनिक', 'Your care team': 'आपकी देखभाल टीम',
    Doctor: 'डॉक्टर', 'Front desk': 'रिसेप्शन', "Doctor's assistant": 'डॉक्टर के सहायक', Dietician: 'डायटीशियन',
    'Lab manager': 'लैब मैनेजर', 'Lab technician': 'लैब टेक्नीशियन', 'Practice manager': 'प्रैक्टिस मैनेजर',
    'All locations': 'सभी लोकेशन',
    'full with logs': 'पूरा रिकॉर्ड, रोज़ का लॉग और वाइटल्स', 'full record': 'पूरा रिकॉर्ड', 'prescriptions and tests': 'पर्चे और टेस्ट',
    'daily log only': 'सिर्फ़ रोज़ का लॉग', 'not shared': 'शेयर नहीं किया',
    Placed: 'दिया गया', Confirmed: 'पक्का', Packed: 'पैक हुआ', 'Out for delivery': 'डिलीवरी के रास्ते में', 'Ready for pick-up': 'लेने के लिए तैयार',
    Delivered: 'पहुंच गया', 'Picked up': 'ले लिया गया', Cancelled: 'रद्द',
    cash: 'नकद', card: 'कार्ड', UPI: 'UPI',
    'Closed all day': 'पूरे दिन बंद', 'Closed part of the day': 'दिन के कुछ समय बंद',
    Photo: 'फ़ोटो', 'Urgent message': 'ज़रूरी संदेश', 'Voice message': 'वॉइस संदेश', 'Photo or file': 'फ़ोटो या फ़ाइल', 'Message deleted': 'संदेश हटा दिया गया',
  },
};

/** Bengali possessive / object forms of the fixed words; anything else gets "-এর" / "-কে". */
const BN_OF = {
  'A patient': 'একজন রোগীর', 'a patient': 'একজন রোগীর', Patient: 'রোগীর', patient: 'রোগীর', 'the patient': 'রোগীর',
  'Your doctor': 'আপনার ডাক্তারের', 'your doctor': 'আপনার ডাক্তারের', 'The doctor': 'ডাক্তারের', 'the doctor': 'ডাক্তারের',
  Clinic: 'ক্লিনিকের', clinic: 'ক্লিনিকের', 'the clinic': 'ক্লিনিকের',
};
const BN_TO = {
  'A patient': 'একজন রোগীকে', 'a patient': 'একজন রোগীকে', Patient: 'রোগীকে', patient: 'রোগীকে', 'the patient': 'রোগীকে',
  'The doctor': 'ডাক্তারকে', 'the doctor': 'ডাক্তারকে',
};

/** Date words: weekdays, months (full and short), today / tomorrow. */
const DATE_WORDS = {
  bn: {
    today: 'আজ', Today: 'আজ', tomorrow: 'আগামীকাল', Tomorrow: 'আগামীকাল',
    Monday: 'সোমবার', Tuesday: 'মঙ্গলবার', Wednesday: 'বুধবার', Thursday: 'বৃহস্পতিবার', Friday: 'শুক্রবার', Saturday: 'শনিবার', Sunday: 'রবিবার',
    Mon: 'সোম', Tue: 'মঙ্গল', Wed: 'বুধ', Thu: 'বৃহস্পতি', Fri: 'শুক্র', Sat: 'শনি', Sun: 'রবি',
    January: 'জানুয়ারি', February: 'ফেব্রুয়ারি', March: 'মার্চ', April: 'এপ্রিল', May: 'মে', June: 'জুন', July: 'জুলাই',
    August: 'আগস্ট', September: 'সেপ্টেম্বর', October: 'অক্টোবর', November: 'নভেম্বর', December: 'ডিসেম্বর',
    Jan: 'জানু', Feb: 'ফেব্রু', Mar: 'মার্চ', Apr: 'এপ্রিল', Jun: 'জুন', Jul: 'জুলাই', Aug: 'আগ', Sep: 'সেপ্টে', Oct: 'অক্টো', Nov: 'নভে', Dec: 'ডিসে',
  },
  hi: {
    today: 'आज', Today: 'आज', tomorrow: 'कल', Tomorrow: 'कल',
    Monday: 'सोमवार', Tuesday: 'मंगलवार', Wednesday: 'बुधवार', Thursday: 'गुरुवार', Friday: 'शुक्रवार', Saturday: 'शनिवार', Sunday: 'रविवार',
    Mon: 'सोम', Tue: 'मंगल', Wed: 'बुध', Thu: 'गुरु', Fri: 'शुक्र', Sat: 'शनि', Sun: 'रवि',
    January: 'जनवरी', February: 'फ़रवरी', March: 'मार्च', April: 'अप्रैल', May: 'मई', June: 'जून', July: 'जुलाई',
    August: 'अगस्त', September: 'सितंबर', October: 'अक्टूबर', November: 'नवंबर', December: 'दिसंबर',
    Jan: 'जन', Feb: 'फ़र', Mar: 'मार्च', Apr: 'अप्रैल', Jun: 'जून', Jul: 'जुलाई', Aug: 'अग', Sep: 'सित', Oct: 'अक्टू', Nov: 'नव', Dec: 'दिस',
  },
};
const DATE_WORD_RE = new RegExp(`\\b(${Object.keys(DATE_WORDS.bn).sort((a, b) => b.length - a.length).join('|')})\\b`, 'g');

// A calendar day as the server writes it: 2026-10-19, or "Mon 19 Oct" style.
const DAY = '(?:\\d{4}-\\d{2}-\\d{2}|(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),? )?\\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*(?: \\d{4})?|[Tt]oday|[Tt]omorrow)';
const re = (src) => new RegExp(`^${src}$`);

const TEMPLATES = [
  // ── Visits (booking, reminders, cancellations) ──
  { en: /^Visit confirmed$/, bn: 'ভিজিট নিশ্চিত', hi: 'विज़िट पक्की' },
  { en: /^Visit booked$/, bn: 'ভিজিট বুক হয়েছে', hi: 'विज़िट बुक हुई' },
  { en: /^Visit cancelled$/, bn: 'ভিজিট বাতিল হয়েছে', hi: 'विज़िट रद्द हुई' },
  { en: /^Visit moved$/, bn: 'ভিজিটের সময় বদলেছে', hi: 'विज़िट का समय बदला' },
  { en: /^(Visit confirmed|Visit booked|Visit cancelled|Visit moved) — (.+)$/, bn: '@1 — @2', hi: '@1 — @2' },
  { en: /^Token (\S+)$/i, bn: 'টোকেন $1', hi: 'टोकन $1' },
  { en: /^(\d{1,2}:\d{2} [AP]M), ([^·]+)$/, bn: '$1, #2', hi: '$1, #2' },
  { en: /^Please book another time$/, bn: 'অন্য একটি সময় বুক করুন', hi: 'कृपया कोई दूसरा समय बुक करें' },
  { en: /^(.+) cancelled a visit$/, bn: '%1 একটি ভিজিট বাতিল করেছেন', hi: '%1 ने एक विज़िट रद्द की' },
  { en: /^(.+) booked a visit$/, bn: '%1 একটি ভিজিট বুক করেছেন', hi: '%1 ने एक विज़िट बुक की' },
  { en: /^(.+) asked for a visit$/, bn: '%1 ভিজিটের অনুরোধ করেছেন', hi: '%1 ने विज़िट का अनुरोध किया' },
  { en: /^(.+) moved their visit$/, bn: '%1 ভিজিটের সময় বদলেছেন', hi: '%1 ने अपनी विज़िट का समय बदला' },
  { en: /^Walk-in: (.+)$/, bn: 'ওয়াক-ইন: %1', hi: 'वॉक-इन: %1' },
  { en: /^Waiting at (.+)$/, bn: '$1-এ অপেক্ষা করছেন', hi: '$1 पर इंतज़ार कर रहे हैं' },
  { en: /^Your visit request was declined$/, bn: 'আপনার ভিজিটের অনুরোধ গ্রহণ করা যায়নি', hi: 'आपका विज़िट अनुरोध स्वीकार नहीं हुआ' },
  { en: /^Your visit is (?:today|Today)$/, bn: 'আপনার ভিজিট আজ', hi: 'आपकी विज़िट आज है' },
  { en: /^Your visit is (?:tomorrow|Tomorrow)$/, bn: 'আপনার ভিজিট আগামীকাল', hi: 'आपकी विज़िट कल है' },
  { en: /^Your visit is in (\d+) minutes$/, bn: '$1 মিনিট পরে আপনার ভিজিট', hi: '$1 मिनट में आपकी विज़िट है' },
  { en: /^Your visit is in about 2 hours$/, bn: 'প্রায় 2 ঘণ্টা পরে আপনার ভিজিট', hi: 'क़रीब 2 घंटे में आपकी विज़िट है' },
  { en: /^(\d{1,2}:\d{2} [AP]M) with (.+)$/, bn: '$1, &2 সঙ্গে', hi: '$1, %2 के साथ' },
  { en: /^Your visit with (.+)$/, bn: '&1 সঙ্গে আপনার ভিজিট', hi: '%1 के साथ आपकी विज़िट' },

  // ── Fees and refunds ──
  { en: /^No fee for your visit$/, bn: 'আপনার ভিজিটে কোনো ফি লাগবে না', hi: 'आपकी विज़िट की कोई फ़ीस नहीं लगेगी' },
  { en: /^The ₹(\S+) fee has been waived\.$/, bn: '₹$1 ফি মকুব করা হয়েছে।', hi: '₹$1 की फ़ीस माफ़ कर दी गई है।' },
  { en: /^Pay ₹(\S+) for your visit$/, bn: 'আপনার ভিজিটের জন্য ₹$1 দিন', hi: 'अपनी विज़िट के लिए ₹$1 दें' },
  { en: /^Paid ₹(\S+) online$/, bn: '₹$1 অনলাইনে পেমেন্ট হয়েছে', hi: '₹$1 का ऑनलाइन भुगतान हुआ' },
  { en: /^Paid ₹(\S+) at the clinic$/, bn: 'ক্লিনিকে ₹$1 পেমেন্ট হয়েছে', hi: 'क्लिनिक में ₹$1 का भुगतान हुआ' },
  { en: /^Paid ₹(\S+) for your medicines$/, bn: 'ওষুধের জন্য ₹$1 পেমেন্ট হয়েছে', hi: 'दवाओं के लिए ₹$1 का भुगतान हुआ' },
  { en: /^reference (\S+)$/i, bn: 'রেফারেন্স $1', hi: 'रेफ़रेंस $1' },
  { en: /^(.+) paid ₹(\S+) online$/, bn: '%1 অনলাইনে ₹$2 দিয়েছেন', hi: '%1 ने ₹$2 ऑनलाइन चुकाए' },
  { en: /^(.+) paid ₹(\S+) at the clinic \((.+)\)$/, bn: '%1 ক্লিনিকে ₹$2 দিয়েছেন (%3)', hi: '%1 ने क्लिनिक में ₹$2 चुकाए (%3)' },
  { en: /^(.+) will pay ₹(\S+) at the clinic$/, bn: '%1 ক্লিনিকে ₹$2 দেবেন', hi: '%1 क्लिनिक में ₹$2 देंगे' },
  { en: /^The pharmacy can see it is paid\.$/, bn: 'ফার্মেসি দেখতে পাচ্ছে যে পেমেন্ট হয়ে গেছে।', hi: 'फ़ार्मेसी देख सकती है कि भुगतान हो गया है।' },
  { en: /^Refund of ₹(\S+) to (.+) didn't go through$/, bn: '~2 ₹$1 ফেরত দেওয়া যায়নি', hi: '%2 को ₹$1 का रिफ़ंड नहीं हो पाया' },
  { en: /^Retry it from Fees, or hand it back at the desk\.$/, bn: 'ফি থেকে আবার চেষ্টা করুন, অথবা রিসেপশনে টাকা ফেরত দিন।', hi: 'फ़ीस से फिर कोशिश करें, या रिसेप्शन पर पैसे लौटा दें।' },
  { en: /^Refund due: ₹(\S+) to (.+)$/, bn: 'ফেরত বাকি: ~2 ₹$1', hi: 'लौटाना बाकी: %2 को ₹$1' },
  { en: /^The visit was cancelled\. Hand it back, then mark it in Fees\.$/, bn: 'ভিজিট বাতিল হয়েছে। টাকা ফেরত দিয়ে ফি-তে চিহ্নিত করুন।', hi: 'विज़िट रद्द हुई। पैसे लौटाएं, फिर फ़ीस में दर्ज करें।' },
  { en: /^₹(\S+) refunded online to (.+)$/, bn: '~2 অনলাইনে ₹$1 ফেরত দেওয়া হয়েছে', hi: '%2 को ₹$1 ऑनलाइन लौटा दिए गए' },
  { en: /^₹(\S+) refunded$/, bn: '₹$1 ফেরত দেওয়া হয়েছে', hi: '₹$1 लौटा दिए गए' },
  { en: /^₹(\S+) will be given back$/, bn: '₹$1 ফেরত দেওয়া হবে', hi: '₹$1 लौटा दिए जाएँगे' },
  { en: /^This was already paid, so the extra payment goes back to how you paid \(usually 5–7 working days\)\.$/, bn: 'এটা আগেই পেমেন্ট করা ছিল, তাই বাড়তি টাকা যেভাবে দিয়েছিলেন সেভাবেই ফেরত যাবে (সাধারণত ৫–৭ কাজের দিন)।', hi: 'इसका भुगतान पहले ही हो चुका था, इसलिए ज़्यादा पैसे उसी तरीके से लौटेंगे जिससे आपने दिए थे (आमतौर पर 5–7 कामकाजी दिन)।' },
  { en: /^This was already paid\. The clinic will give the extra payment back\.$/, bn: 'এটা আগেই পেমেন্ট করা ছিল। ক্লিনিক বাড়তি টাকা ফেরত দেবে।', hi: 'इसका भुगतान पहले ही हो चुका था। क्लिनिक ज़्यादा पैसे लौटा देगा।' },
  { en: /^₹(\S+) paid twice by (.+) — refunded online$/, bn: '%2 দু’বার ₹$1 দিয়েছেন — অনলাইনে ফেরত দেওয়া হয়েছে', hi: '%2 ने ₹$1 दो बार दिए — ऑनलाइन लौटा दिए गए' },
  { en: /^Refund due: ₹(\S+) paid twice by (.+)$/, bn: 'ফেরত দিতে হবে: %2 দু’বার ₹$1 দিয়েছেন', hi: 'लौटाना है: %2 ने ₹$1 दो बार दिए' },
  { en: /^Razorpay couldn't refund it\. Hand it back at the desk\.$/, bn: 'Razorpay ফেরত দিতে পারেনি। কাউন্টারে ফেরত দিন।', hi: 'Razorpay इसे नहीं लौटा सका। काउंटर पर लौटा दें।' },
  { en: /^Back to how you paid, usually in 5–7 working days\.$/, bn: 'যেভাবে পেমেন্ট করেছিলেন সেখানেই ফেরত যাবে, সাধারণত 5–7 কাজের দিনে।', hi: 'जिस तरीके से भुगतान किया था उसी में वापस आएगा, आमतौर पर 5–7 कार्यदिवस में।' },
  { en: /^Handed back at the clinic\.$/, bn: 'ক্লিনিকে ফেরত দেওয়া হয়েছে।', hi: 'क्लिनिक पर लौटा दिए गए।' },

  // ── Doctor's payouts ──
  { en: /^₹(\S+) on its way to you$/, bn: '₹$1 আপনার কাছে আসছে', hi: '₹$1 आपके पास आ रहे हैं' },
  { en: /^₹(\S+) in online fees$/, bn: 'অনলাইন ফি-তে ₹$1', hi: 'ऑनलाइन फ़ीस में ₹$1' },
  { en: /^₹(\S+) paid to (.+)$/, bn: '$2-এ ₹$1 পাঠানো হয়েছে', hi: '$2 पर ₹$1 भेजे गए' },
  { en: /^(\d+) online fees?$/, bn: '$1টি অনলাইন ফি', hi: '$1 ऑनलाइन फ़ीस' },
  { en: /^to (.+)$/, bn: 'যাচ্ছে: $1', hi: 'भेजा जा रहा है: $1' },
  { en: /^Add your UPI ID or bank account in Payouts to receive this\.$/, bn: 'এটি পেতে পেমেন্ট সেটিংসে আপনার UPI ID বা ব্যাংক অ্যাকাউন্ট যোগ করুন।', hi: 'इसे पाने के लिए भुगतान सेटिंग में अपनी UPI ID या बैंक खाता जोड़ें।' },
  { en: /^Payouts are being set up\. Your balance is safe and will be paid\.$/, bn: 'পেমেন্ট চালু করা হচ্ছে। আপনার টাকা নিরাপদে আছে, পরে দেওয়া হবে।', hi: 'भुगतान शुरू किया जा रहा है। आपकी राशि सुरक्षित है और दी जाएगी।' },
  { en: /^Re-enter your bank account in Payouts so it can be verified\.$/, bn: 'যাচাইয়ের জন্য পেমেন্ট সেটিংসে আবার ব্যাংক অ্যাকাউন্ট দিন।', hi: 'सत्यापन के लिए भुगतान सेटिंग में अपना बैंक खाता फिर से डालें।' },

  // ── Leave, closures, hours ──
  { en: re(`(${DAY}) to (${DAY})`), bn: '#1 থেকে #2', hi: '#1 से #2 तक' },
  { span: true, en: /^(.+)\. Please choose another time for your visit\.$/, bn: '@1। আপনার ভিজিটের জন্য অন্য সময় বেছে নিন।', hi: '@1। अपनी विज़िट के लिए कोई दूसरा समय चुनें।' },
  { en: /^Please choose another time for your visit\.$/, bn: 'আপনার ভিজিটের জন্য অন্য সময় বেছে নিন।', hi: 'अपनी विज़िट के लिए कोई दूसरा समय चुनें।' },
  { en: /^(.+) is on leave (.+)$/, bn: '%1 #2 ছুটিতে আছেন', hi: '%1 #2 छुट्टी पर हैं' },
  { en: /^(.+) is on leave$/, bn: '%1 ছুটিতে আছেন', hi: '%1 छुट्टी पर हैं' },
  { en: /^(.+) changed (.+?)'s (.+)$/, bn: '%1 %2-এর %3 বদলেছেন', hi: '%1 ने %2 की %3 बदली' },
  { en: /^Their new prescription replaces yours for this medicine\.$/, bn: 'এই ওষুধে তাঁর নতুন প্রেসক্রিপশন আপনারটির জায়গা নিয়েছে।', hi: 'इस दवा के लिए उनका नया पर्चा आपके पर्चे की जगह लेता है।' },
  { en: /^(.+) is running about (\d+) minutes late$/, bn: '%1 প্রায় $2 মিনিট দেরিতে চলছেন', hi: '%1 लगभग $2 मिनट देर से चल रहे हैं' },
  { en: /^Your visit at (.+?) may start later\. You can come a little later\.$/, bn: '$1-এর ভিজিট একটু দেরিতে শুরু হতে পারে। একটু পরে আসতে পারেন।', hi: '$1 की विज़िट थोड़ी देर से शुरू हो सकती है। आप थोड़ा बाद में आ सकते हैं।' },
  { en: /^It's your turn$/, bn: 'আপনার পালা এসেছে', hi: 'आपकी बारी आ गई है' },
  { en: /^Please go in to see (.+?) · token (\d+)$/, bn: '%1-এর কাছে ভেতরে যান · টোকেন $2', hi: '%1 के पास अंदर जाएँ · टोकन $2' },
  { en: /^Please go in to see (.+)$/, bn: '%1-এর কাছে ভেতরে যান', hi: '%1 के पास अंदर जाएँ' },
  { en: /^(.+) is available after all$/, bn: '%1 ছুটি বাতিল করেছেন, আপনাকে দেখবেন', hi: '%1 ने छुट्टी रद्द कर दी है, वे आपको देखेंगे' },
  { en: re(`Your visit on (${DAY}) at (.+) stands\\.`), bn: '#1 তারিখে #2-এ আপনার ভিজিট বহাল আছে।', hi: '#1 को #2 की आपकी विज़िट बनी रहेगी।' },
  { span: true, en: /^(.+) is closed\. Please book at another branch\.$/, bn: '%1 বন্ধ। অন্য শাখায় বুক করুন।', hi: '%1 बंद है। किसी दूसरी शाखा में बुक करें।' },
  { en: /^(\d+) visits? to move$/, bn: '$1টি ভিজিটের সময় বদলাতে হবে', hi: '$1 विज़िट का समय बदलना है' },
  { en: re(`(.+?) is closed (${DAY}.*)`), bn: '%1 বন্ধ থাকবে: @2', hi: '%1 बंद रहेगा: @2' },
  { en: /^(.+) is closed$/, bn: '%1 বন্ধ', hi: '%1 बंद है' },
  { en: /^(.+) closed · (.+)$/, bn: '%1 বন্ধ · @2', hi: '%1 बंद · @2' },
  { en: /^Closed all day$/, bn: 'সারা দিন বন্ধ', hi: 'पूरे दिन बंद' },
  { en: /^Closed part of the day$/, bn: 'দিনের কিছু সময় বন্ধ', hi: 'दिन के कुछ समय बंद' },
  { en: /^added by (.+)$/i, bn: '%1 যোগ করেছেন', hi: '%1 ने जोड़ा' },
  { en: /^(.+) is open again$/, bn: '%1 আবার খোলা', hi: '%1 फिर से खुला है' },
  { en: /^your booked visit stands\.$/i, bn: 'আপনার বুক করা ভিজিট বহাল আছে।', hi: 'आपकी बुक की गई विज़िट बनी रहेगी।' },
  { en: /^(\d+) visits? outside the new hours$/, bn: 'নতুন সময়ের বাইরে $1টি ভিজিট', hi: 'नए समय के बाहर $1 विज़िट' },
  { en: /^(\d+) visits? outside (.+)'s new hours$/, bn: '&2 নতুন সময়ের বাইরে $1টি ভিজিট', hi: '%2 के नए समय के बाहर $1 विज़िट' },
  { en: /^weekly hours changed$/i, bn: 'সাপ্তাহিক সময় বদলেছে', hi: 'साप्ताहिक समय बदला' },
  { en: /^Your hours at (.+) changed$/, bn: '%1-এ আপনার সময় বদলেছে', hi: '%1 पर आपका समय बदला' },
  { en: /^Changed by (.+)$/, bn: '%1 বদলেছেন', hi: '%1 ने बदला' },

  // ── Follow-ups ──
  { en: /^Follow-up due$/, bn: 'ফলো-আপ বাকি', hi: 'फ़ॉलो-अप बाकी' },
  { en: /^Follow-up due (?:today|Today)$/, bn: 'আজ ফলো-আপ', hi: 'आज फ़ॉलो-अप है' },
  { en: /^Follow-up due (?:tomorrow|Tomorrow)$/, bn: 'আগামীকাল ফলো-আপ', hi: 'कल फ़ॉलो-अप है' },
  { en: /^Follow-up due in (\d+) days$/, bn: '$1 দিন পরে ফলো-আপ', hi: '$1 दिन में फ़ॉलो-अप है' },
  { en: /^(.+) asked you to come back on (.+)\. Book a time in the app\.$/, bn: '%1 আপনাকে #2 তারিখে আবার আসতে বলেছেন। অ্যাপে সময় বুক করুন।', hi: '%1 ने आपको #2 को फिर आने को कहा है। ऐप में समय बुक करें।' },
  { en: /^(.+): your follow-up is due on (.+)\. Please book a visit in MedPin or reply to this message\.$/, bn: '$1: আপনার ফলো-আপ #2 তারিখে। MedPin-এ ভিজিট বুক করুন বা এই মেসেজের উত্তর দিন।', hi: '$1: आपका फ़ॉलो-अप #2 को है। MedPin में विज़िट बुक करें या इस मैसेज का जवाब दें।' },

  // ── Medicines and daily log ──
  { en: /^Time for (\d+) medicines$/, bn: '$1টি ওষুধ খাওয়ার সময়', hi: '$1 दवाएं लेने का समय' },
  { en: /^Time for (.+)$/, bn: '$1 খাওয়ার সময়', hi: '$1 लेने का समय' },
  { en: /^Morning dose$/, bn: 'সকালের ডোজ', hi: 'सुबह की खुराक' },
  { en: /^Afternoon dose$/, bn: 'দুপুরের ডোজ', hi: 'दोपहर की खुराक' },
  { en: /^Night dose$/, bn: 'রাতের ডোজ', hi: 'रात की खुराक' },
  { en: /^before food$/i, bn: 'খাবারের আগে', hi: 'खाने से पहले' },
  { en: /^after food$/i, bn: 'খাবারের পরে', hi: 'खाने के बाद' },
  { en: /^with food$/i, bn: 'খাবারের সঙ্গে', hi: 'खाने के साथ' },
  { en: /^on an empty stomach$/i, bn: 'খালি পেটে', hi: 'खाली पेट' },
  { en: /^(.+) \/ (.+)$/, inner: [1, 2], bn: '@1 / @2', hi: '@1 / @2' },
  { en: /^(.+) has run out$/, bn: '$1 শেষ হয়ে গেছে', hi: '$1 ख़त्म हो गई' },
  { en: /^(.+) runs out in (\d+) days?$/, bn: '$1 আর $2 দিনে শেষ হবে', hi: '$1 $2 दिन में ख़त्म हो जाएगी' },
  { en: /^(\S+) left$/, bn: 'আর $1টি বাকি', hi: '$1 बची हैं' },
  { en: /^(.+)\. Reorder now so you don't miss doses\.$/, bn: '$1। ডোজ যাতে বাদ না পড়ে, এখনই আবার অর্ডার করুন।', hi: '$1। ख़ुराक न छूटे, इसलिए अभी फिर से ऑर्डर करें।' },
  { en: /^Log today's meals$/, bn: 'আজকের খাবারের লগ রাখুন', hi: 'आज के भोजन का लॉग रखें' },
  { en: /^A quick photo or a line is enough\. Your care team sees it\.$/, bn: 'একটা ছবি বা এক লাইন লিখলেই হবে। আপনার চিকিৎসক দল এটা দেখেন।', hi: 'एक फ़ोटो या एक लाइन काफ़ी है। आपकी देखभाल टीम इसे देखती है।' },
  { en: /^(.+) asked you to log your meals$/, bn: '%1 আপনাকে খাবারের লগ রাখতে বলেছেন', hi: '%1 ने आपसे अपने भोजन का लॉग रखने को कहा है' },
  { en: /^A quick photo or a line after each meal is enough\. They will review it\.$/, bn: 'প্রতিবার খাওয়ার পরে একটা ছবি বা এক লাইন লিখলেই হবে। ওঁরা দেখে নেবেন।', hi: 'हर बार खाने के बाद एक फ़ोटो या एक लाइन काफ़ी है। वे इसे देखेंगे।' },

  // ── Pharmacy orders ──
  { en: /^Pharmacy order from (.+)$/, bn: '&1 ফার্মেসি অর্ডার', hi: '%1 का फ़ार्मेसी ऑर्डर' },
  { en: /^The pharmacy confirmed your order$/, bn: 'ফার্মেসি আপনার অর্ডার নিশ্চিত করেছে', hi: 'फ़ार्मेसी ने आपका ऑर्डर पक्का किया' },
  { en: /^Your medicines are packed$/, bn: 'আপনার ওষুধ প্যাক হয়ে গেছে', hi: 'आपकी दवाएं पैक हो गईं' },
  { en: /^Your medicines are on the way$/, bn: 'আপনার ওষুধ পথে আছে', hi: 'आपकी दवाएं रास्ते में हैं' },
  { en: /^Your medicines are ready to pick up$/, bn: 'আপনার ওষুধ নেওয়ার জন্য তৈরি', hi: 'आपकी दवाएं लेने के लिए तैयार हैं' },
  { en: /^Your medicines were delivered$/, bn: 'আপনার ওষুধ পৌঁছে গেছে', hi: 'आपकी दवाएं पहुंच गईं' },
  { en: /^Order collected$/, bn: 'অর্ডার নেওয়া হয়েছে', hi: 'ऑर्डर ले लिया गया' },
  { en: /^Your order was cancelled$/, bn: 'আপনার অর্ডার বাতিল হয়েছে', hi: 'आपका ऑर्डर रद्द हो गया' },
  { en: /^Order (Placed|Confirmed|Packed|Out for delivery|Ready for pick-up|Delivered|Picked up|Cancelled)$/, bn: 'অর্ডার %1', hi: 'ऑर्डर %1' },

  // ── Alerts and chats ──
  { en: /^Emergency: (.+)$/, bn: 'জরুরি: $1', hi: 'आपात: $1' },
  { en: /^Urgent: (.+) needs help$/, bn: 'জরুরি: &1 সাহায্য দরকার', hi: 'ज़रूरी: %1 को मदद चाहिए' },
  { en: /^Urgent: (.+)$/, bn: 'জরুরি: $1', hi: 'ज़रूरी: $1' },
  { en: /^Watch: (.+)$/, bn: 'নজরে রাখুন: $1', hi: 'नज़र रखें: $1' },
  { en: /^Urgent message from (.+)$/, bn: '%1 জরুরি মেসেজ পাঠিয়েছেন', hi: '%1 ने ज़रूरी मैसेज भेजा' },
  { en: /^New message from (.+)$/, bn: '%1 নতুন মেসেজ পাঠিয়েছেন', hi: '%1 ने नया मैसेज भेजा' },
  { en: /^(.+) wants to talk to someone at the clinic$/, bn: '%1 ক্লিনিকের কারও সঙ্গে কথা বলতে চান', hi: '%1 क्लिनिक में किसी से बात करना चाहते हैं' },
  { en: /^MedPin AI is paused in this chat until you reply\.$/, bn: 'আপনি উত্তর না দেওয়া পর্যন্ত এই চ্যাটে MedPin AI বন্ধ থাকবে।', hi: 'आपके जवाब देने तक इस चैट में MedPin AI बंद रहेगा।' },
  { en: /^MedPin AI asked you to check a reply to (.+)$/, bn: 'MedPin AI ~1 দেওয়া একটি উত্তর দেখে নিতে বলেছে', hi: 'MedPin AI ने %1 को दिए एक जवाब को देखने के लिए कहा है' },
  { en: /^Tap to pay in the app, or open (.+)$/, bn: 'অ্যাপেই পেমেন্ট করতে ট্যাপ করুন, বা খুলুন $1', hi: 'ऐप में ही पेमेंट के लिए टैप करें, या खोलें $1' },
  { en: /^(.+) sent the (.+) report you asked for$/, bn: '%1 আপনার চাওয়া %2 রিপোর্ট পাঠিয়েছেন', hi: '%1 ने आपकी माँगी %2 रिपोर्ट भेजी' },
  { en: /^All of (.+)'s reports are in — book a report review$/, bn: '%1-এর সব রিপোর্ট এসে গেছে — রিপোর্ট দেখানোর ভিজিট বুক করুন', hi: '%1 की सभी रिपोर्ट आ गई हैं — रिपोर्ट दिखाने की विज़िट बुक करें' },
  { en: /^All reports in from (.+) — ready to review$/, bn: '%1-এর সব রিপোর্ট এসে গেছে — দেখার জন্য তৈরি', hi: '%1 की सभी रिपोर्ट आ गईं — देखने के लिए तैयार' },
  { en: /^(.+) has seen your test report$/, bn: '%1 আপনার টেস্ট রিপোর্ট দেখেছেন', hi: '%1 ने आपकी टेस्ट रिपोर्ट देख ली है' },
  { en: /^(.+) has seen your (.+) report$/, bn: '%1 আপনার %2 রিপোর্ট দেখেছেন', hi: '%1 ने आपकी %2 रिपोर्ट देख ली है' },
  { en: /^(\d+) patients are waiting for a reply$/, bn: '%1 জন রোগী উত্তরের অপেক্ষায়', hi: '%1 मरीज़ जवाब का इंतज़ार कर रहे हैं' },
  { en: /^(.+) is waiting for a reply$/, bn: '%1 উত্তরের অপেক্ষায়', hi: '%1 जवाब का इंतज़ार कर रहे हैं' },
  { en: /^Resolved by (.+)$/, bn: '%1 মিটিয়ে দিয়েছেন', hi: '%1 ने सुलझा दिया' },
  { en: /^(.+) hasn't seen an emergency for (.+) yet$/, bn: '%1 এখনও &2 জরুরি অবস্থা দেখেননি', hi: '%1 ने अभी तक %2 की आपात स्थिति नहीं देखी' },
  { en: /^Please let the doctor know\. ?(.*)$/, bn: 'ডাক্তারকে জানান। @1', hi: 'कृपया डॉक्टर को बताएं। @1' },
  { en: /^Home BP reading (\d+)\/(\d+) mmHg, above the alert limit\.$/, bn: 'বাড়িতে রক্তচাপ $1/$2 mmHg, সতর্কতার সীমার বেশি।', hi: 'घर पर बीपी $1/$2 mmHg, अलर्ट सीमा से ऊपर।' },
  { en: /^SpO₂ (\S+)%, below (\S+)%\.$/, bn: 'SpO₂ $1%, $2%-এর নিচে।', hi: 'SpO₂ $1%, $2% से कम।' },
  { en: /^Heart rate (\S+) bpm, outside (\S+)–(\S+)\.$/, bn: 'হৃদস্পন্দন $1 bpm, $2–$3-এর বাইরে।', hi: 'धड़कन $1 bpm, $2–$3 से बाहर।' },
  { en: /^Fasting sugar (\S+) mg\/dL\.$/, bn: 'খালি পেটে সুগার $1 mg/dL।', hi: 'खाली पेट शुगर $1 mg/dL।' },
  { en: /^Low blood sugar (\S+) mg\/dL\.$/, bn: 'রক্তে সুগার কম, $1 mg/dL।', hi: 'ब्लड शुगर कम, $1 mg/dL।' },
  { en: /^Very high blood sugar (\S+) mg\/dL \(fasting\)\.$/, bn: 'রক্তে সুগার খুব বেশি, $1 mg/dL (খালি পেটে)।', hi: 'ब्लड शुगर बहुत ज़्यादा, $1 mg/dL (खाली पेट)।' },
  { en: /^Very high blood sugar (\S+) mg\/dL \(post-meal\)\.$/, bn: 'রক্তে সুগার খুব বেশি, $1 mg/dL (খাওয়ার পরে)।', hi: 'ब्लड शुगर बहुत ज़्यादा, $1 mg/dL (खाने के बाद)।' },
  { en: /^Very high blood sugar (\S+) mg\/dL(?: \(random\))?\.$/, bn: 'রক্তে সুগার খুব বেশি, $1 mg/dL।', hi: 'ब्लड शुगर बहुत ज़्यादा, $1 mg/dL।' },
  { en: /^After-meal sugar (\S+) mg\/dL\.$/, bn: 'খাওয়ার পরে সুগার $1 mg/dL।', hi: 'खाने के बाद शुगर $1 mg/dL।' },
  { en: /^Random sugar (\S+) mg\/dL\.$/, bn: 'যেকোনো সময়ের সুগার $1 mg/dL।', hi: 'किसी भी समय की शुगर $1 mg/dL।' },
  { en: /^Critical result in (.+) \(shared by the patient\)$/, bn: '$1-এ গুরুতর ফল (রোগী শেয়ার করেছেন)', hi: '$1 में गंभीर नतीजा (मरीज़ ने शेयर किया)' },
  { en: /^Critical result in (.+)$/, bn: '$1-এ গুরুতর ফল', hi: '$1 में गंभीर नतीजा' },
  // "Priya Sharma: <an alert's detail>" (Resolved by …): only when the detail translates.
  { en: /^([^:]{1,80}): (.+)$/, inner: [2], bn: '$1: @2', hi: '$1: @2' },

  // ── Records, prescriptions, sharing ──
  { en: /^Your prescription is ready$/, bn: 'আপনার প্রেসক্রিপশন তৈরি', hi: 'आपका पर्चा तैयार है' },
  { en: /^(.+) shared a prescription$/, bn: '%1 একটি প্রেসক্রিপশন শেয়ার করেছেন', hi: '%1 ने एक पर्चा शेयर किया' },
  { en: /^(.+) shared a report$/, bn: '%1 একটি রিপোর্ট শেয়ার করেছেন', hi: '%1 ने एक रिपोर्ट शेयर की' },
  { en: /^(.+) shared (\d+) reports$/, bn: '%1 $2টি রিপোর্ট শেয়ার করেছেন', hi: '%1 ने $2 रिपोर्ट शेयर कीं' },
  { en: /^(.+) changed what you can see$/, bn: '%1 আপনি কী দেখতে পাবেন তা বদলেছেন', hi: '%1 ने बदला कि आप क्या देख सकते हैं' },
  { en: /^(.+) can now see your record$/, bn: '%1 এখন আপনার রেকর্ড দেখতে পারবে', hi: '%1 अब आपका रिकॉर्ड देख सकता है' },
  { en: /^You can change this any time in Profile\.$/, bn: 'প্রোফাইলে গিয়ে যেকোনো সময় এটা বদলাতে পারেন।', hi: 'इसे आप कभी भी प्रोफ़ाइल में बदल सकते हैं।' },

  // ── Doctor's daily summaries ──
  { en: /^Your day at (.+)$/, bn: 'আপনার আজকের দিন · %1', hi: 'आपका आज का दिन · %1' },
  { en: /^(\d+) seen$/, bn: '$1 জনকে দেখেছেন', hi: '$1 मरीज़ देखे' },
  { en: /^(\d+) missed$/, bn: '$1 জন আসেননি', hi: '$1 नहीं आए' },
  { en: /^(\d+) follow-ups? due in 3 days$/, bn: '3 দিনের মধ্যে $1টি ফলো-আপ', hi: '3 दिन में $1 फ़ॉलो-अप' },
  { en: /^(\d+) open alerts?$/, bn: '$1টি খোলা সতর্কতা', hi: '$1 खुले अलर्ट' },
  { en: /^(\d+) chats? waiting$/, bn: '$1টি চ্যাট অপেক্ষায়', hi: '$1 चैट इंतज़ार में' },
  { en: /^Your patients since yesterday$/, bn: 'গতকাল থেকে আপনার রোগীরা', hi: 'कल से आपके मरीज़' },
  {
    en: /^(\d+) reports? shared(?: \((\d+) out of range\))?$/,
    bn: (m) => `${m[1]}টি রিপোর্ট শেয়ার করেছেন${m[2] ? ` (${m[2]}টি সীমার বাইরে)` : ''}`,
    hi: (m) => `${m[1]} रिपोर्ट शेयर की गईं${m[2] ? ` (${m[2]} सीमा से बाहर)` : ''}`,
  },
  { en: /^(\d+) you asked for$/, bn: '$1টি আপনি চেয়েছিলেন', hi: '$1 आपने मांगी थीं' },
  { en: /^(\d+) patients? below 70% on medicines$/, bn: '$1 জন রোগী ওষুধ খাওয়ায় 70%-এর নিচে', hi: '$1 मरीज़ दवा लेने में 70% से नीचे' },
  { en: /^(\d+) patients? wrote, waiting for a reply$/, bn: '$1 জন রোগী লিখেছেন, উত্তরের অপেক্ষায়', hi: '$1 मरीज़ों ने लिखा, जवाब का इंतज़ार' },
  { en: /^(\d+) not logging meals$/, bn: '$1 জন খাবারের লগ রাখছেন না', hi: '$1 भोजन का लॉग नहीं रख रहे' },

  // ── Team, profile, support ──
  { en: /^Your access changed$/, bn: 'আপনার অ্যাক্সেস বদলেছে', hi: 'आपकी पहुँच बदली' },
  { en: /^Your access is back on$/, bn: 'আপনার অ্যাক্সেস আবার চালু', hi: 'आपकी पहुँच फिर चालू है' },
  { en: /^(.+): proof not accepted$/, bn: '$1: প্রমাণ গ্রহণ করা হয়নি', hi: '$1: प्रमाण स्वीकार नहीं हुआ' },
  { en: /^(.+) verified$/, bn: '$1 যাচাই হয়েছে', hi: '$1 सत्यापित हो गया' },
  { en: /^Your profile now shows the Verified badge\.$/, bn: 'আপনার প্রোফাইলে এখন "যাচাই করা" ব্যাজ দেখা যাচ্ছে।', hi: 'आपकी प्रोफ़ाइल पर अब "सत्यापित" बैज दिख रहा है।' },
  { en: /^Thank you\. Your other proofs are still in review\.$/, bn: 'ধন্যবাদ। আপনার বাকি প্রমাণগুলো এখনও যাচাই হচ্ছে।', hi: 'धन्यवाद। आपके बाकी प्रमाण अभी जांच में हैं।' },
  { en: /^Please upload a clearer copy$/, bn: 'আরও স্পষ্ট একটি কপি আপলোড করুন', hi: 'कृपया ज़्यादा साफ़ कॉपी अपलोड करें' },
  { en: /^We got your message$/, bn: 'আপনার মেসেজ পেয়েছি', hi: 'आपका मैसेज मिल गया' },
  { en: /^Our team will reply by email or phone\.$/, bn: 'আমাদের টিম ইমেল বা ফোনে উত্তর দেবে।', hi: 'हमारी टीम ईमेल या फ़ोन से जवाब देगी।' },
];

// A free capture stays inside one part of a " · " line ("Walk-in: Priya · token 4" is two
// parts, each translated) unless the template says `span: true`.
for (const t of TEMPLATES) {
  if (!t.span) t.en = new RegExp(t.en.source.replace(/\(\.\+(\??)\)/g, '([^·]+$1)'), t.en.flags);
}

/** One of the fixed words on its own (a role, "All locations", "clinic"…): a part of a " · " line. */
const wordAlone = (text, lang) => (Object.prototype.hasOwnProperty.call(WORDS[lang], text) ? WORDS[lang][text] : null);

function fill(t, m, lang, depth) {
  const out = t[lang];
  if (typeof out === 'function') return out(m);
  return out.replace(/([$%&~#@])(\d)/g, (_, mark, n) => {
    const v = m[Number(n)] ?? '';
    const word = WORDS[lang][v];
    switch (mark) {
      case '%': return word ?? v;
      case '&': return lang === 'bn' ? (BN_OF[v] ?? `${word ?? v}-এর`) : (word ?? v);
      case '~': return lang === 'bn' ? (BN_TO[v] ?? `${word ?? v}-কে`) : (word ?? v);
      case '#': return v.replace(DATE_WORD_RE, (w) => DATE_WORDS[lang][w] ?? w);
      case '@': return tr(v, lang, depth + 1);
      default: return v;
    }
  });
}

/** The first template matching the whole [text], filled in; null when none does. */
function byTemplate(text, lang, depth) {
  for (const t of TEMPLATES) {
    const m = text.match(t.en);
    if (!m) continue;
    if (t.inner && t.inner.some((n) => tr(m[n] ?? '', lang, depth + 1) === m[n])) continue;
    return fill(t, m, lang, depth);
  }
  return null;
}

function tr(text, lang, depth) {
  if (!text || depth > 4) return text;
  const whole = byTemplate(text, lang, depth) ?? wordAlone(text, lang);
  if (whole != null && whole !== text) return whole;
  if (text.includes(' · ')) {
    const parts = text.split(' · ');
    const out = parts.map((p) => byTemplate(p, lang, depth) ?? wordAlone(p, lang) ?? p);
    if (out.some((p, i) => p !== parts[i])) return out.join(' · ');
  }
  return text;
}

/** [text] (English) in [lang] ('en' | 'bn' | 'hi'); unknown text comes back unchanged. */
function translate(text, lang) {
  if (typeof text !== 'string' || !LANGS.includes(lang)) return text;
  return tr(text, lang, 0);
}

/** A notification's title and body in [lang]. */
const translateNotice = (n, lang) => ({ title: translate(n.title, lang), body: translate(n.body, lang) });

module.exports = { translate, translateNotice, TEMPLATES, LANGS };
