// Bank details for payouts: IFSC → bank and branch, UPI ID → app and bank.
//
// IFSC codes are looked up in Razorpay's public IFSC directory
// (https://ifsc.razorpay.com, free, no key; data from RBI). Results are
// cached for a week. If the directory can't be reached, the bank is still
// named from the code's first four letters (the RBI bank code), marked
// unverified.
const CACHE_MS = 7 * 24 * 3600e3;
const cache = new Map(); // IFSC → { at, info }

const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;

// RBI bank codes (first 4 letters of the IFSC) of the banks most used in India.
const BANK_CODES = {
  SBIN: 'State Bank of India', HDFC: 'HDFC Bank', ICIC: 'ICICI Bank', UTIB: 'Axis Bank', KKBK: 'Kotak Mahindra Bank',
  PUNB: 'Punjab National Bank', BARB: 'Bank of Baroda', CNRB: 'Canara Bank', UBIN: 'Union Bank of India', BKID: 'Bank of India',
  IDIB: 'Indian Bank', IOBA: 'Indian Overseas Bank', CBIN: 'Central Bank of India', UCBA: 'UCO Bank', MAHB: 'Bank of Maharashtra',
  PSIB: 'Punjab & Sind Bank', YESB: 'Yes Bank', INDB: 'IndusInd Bank', FDRL: 'Federal Bank', IDFB: 'IDFC FIRST Bank',
  AUBL: 'AU Small Finance Bank', RATN: 'RBL Bank', KARB: 'Karnataka Bank', KVBL: 'Karur Vysya Bank', SIBL: 'South Indian Bank',
  CIUB: 'City Union Bank', DLXB: 'Dhanlaxmi Bank', TMBL: 'Tamilnad Mercantile Bank', JAKA: 'Jammu & Kashmir Bank',
  BDBL: 'Bandhan Bank', ESFB: 'Equitas Small Finance Bank', UJVN: 'Ujjivan Small Finance Bank', AIRP: 'Airtel Payments Bank',
  IPOS: 'India Post Payments Bank', PYTM: 'Paytm Payments Bank', FINO: 'Fino Payments Bank', DBSS: 'DBS Bank India',
  HSBC: 'HSBC', SCBL: 'Standard Chartered Bank', CITI: 'Citibank', DCBL: 'DCB Bank', CSBK: 'CSB Bank', NKGS: 'NKGSB Co-op Bank',
  SVCB: 'SVC Co-operative Bank', COSB: 'Cosmos Co-operative Bank', SRCB: 'Saraswat Co-operative Bank', WBSC: 'West Bengal State Co-operative Bank',
};

// UPI handles (the part after @): the app that issues them and the bank behind it.
const UPI_HANDLES = {
  okhdfcbank: ['Google Pay', 'HDFC Bank'], oksbi: ['Google Pay', 'State Bank of India'], okicici: ['Google Pay', 'ICICI Bank'],
  okaxis: ['Google Pay', 'Axis Bank'], ybl: ['PhonePe', 'Yes Bank'], ibl: ['PhonePe', 'ICICI Bank'], axl: ['PhonePe', 'Axis Bank'],
  paytm: ['Paytm', 'Paytm Payments Bank'], ptyes: ['Paytm', 'Yes Bank'], ptaxis: ['Paytm', 'Axis Bank'], pthdfc: ['Paytm', 'HDFC Bank'],
  ptsbi: ['Paytm', 'State Bank of India'], upi: ['BHIM', 'NPCI'], apl: ['Amazon Pay', 'Axis Bank'], yapl: ['Amazon Pay', 'Yes Bank'],
  rapl: ['Amazon Pay', 'RBL Bank'], waicici: ['WhatsApp Pay', 'ICICI Bank'], wahdfcbank: ['WhatsApp Pay', 'HDFC Bank'],
  waaxis: ['WhatsApp Pay', 'Axis Bank'], wasbi: ['WhatsApp Pay', 'State Bank of India'], jupiteraxis: ['Jupiter', 'Axis Bank'],
  fam: ['FamPay', 'IDFC FIRST Bank'], slc: ['slice', 'slice small finance bank'], naviaxis: ['Navi', 'Axis Bank'], freecharge: ['Freecharge', 'Axis Bank'],
  sbi: ['SBI YONO', 'State Bank of India'], hdfcbank: ['HDFC Bank', 'HDFC Bank'], icici: ['iMobile', 'ICICI Bank'], axisbank: ['Axis Bank', 'Axis Bank'],
  kotak: ['Kotak', 'Kotak Mahindra Bank'], kmbl: ['Kotak', 'Kotak Mahindra Bank'], barodampay: ['bob World', 'Bank of Baroda'],
  pnb: ['PNB ONE', 'Punjab National Bank'], cnrb: ['Canara ai1', 'Canara Bank'], unionbank: ['Vyom', 'Union Bank of India'],
  boi: ['BOI Mobile', 'Bank of India'], indianbank: ['IndOASIS', 'Indian Bank'], iob: ['IOB Mobile', 'Indian Overseas Bank'],
  yesbank: ['Yes Bank', 'Yes Bank'], idfcbank: ['IDFC FIRST', 'IDFC FIRST Bank'], indus: ['IndusInd', 'IndusInd Bank'],
  federal: ['FedMobile', 'Federal Bank'], aubank: ['AU 0101', 'AU Small Finance Bank'], rbl: ['RBL MoBank', 'RBL Bank'],
  airtel: ['Airtel Thanks', 'Airtel Payments Bank'], postbank: ['IPPB', 'India Post Payments Bank'], dbs: ['digibank', 'DBS Bank India'],
  citi: ['Citi', 'Citibank'], hsbc: ['HSBC', 'HSBC'], sc: ['SC Mobile', 'Standard Chartered Bank'], equitas: ['Equitas', 'Equitas Small Finance Bank'],
  ujjivan: ['Ujjivan', 'Ujjivan Small Finance Bank'], bandhan: ['Bandhan', 'Bandhan Bank'], kvb: ['KVB', 'Karur Vysya Bank'],
  cub: ['CUB', 'City Union Bank'], dlb: ['Dhanlaxmi', 'Dhanlaxmi Bank'], jkb: ['J&K Bank', 'Jammu & Kashmir Bank'],
};

/** Replaced in tests so they never call the internet. */
let fetchImpl = (url, opts) => fetch(url, opts);

const title = (s) => String(s || '').toLowerCase().replace(/\b([a-z])/g, (m) => m.toUpperCase()).replace(/\bOf\b/g, 'of').replace(/\bAnd\b/g, 'and');

/**
 * { valid, found, verified, ifsc, bank, branch, city, state, address }.
 * valid: the format is right; found: the code exists (null when the
 * directory couldn't be reached); verified: from the directory.
 */
async function ifscInfo(raw) {
  const ifsc = String(raw || '').trim().toUpperCase();
  if (!IFSC_RE.test(ifsc)) return { valid: false, found: false, verified: false, ifsc };
  const hit = cache.get(ifsc);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.info;
  const guess = BANK_CODES[ifsc.slice(0, 4)];
  try {
    const res = await fetchImpl(`https://ifsc.razorpay.com/${ifsc}`, { signal: AbortSignal.timeout(5000) });
    if (res.status === 404) {
      const info = { valid: true, found: false, verified: true, ifsc };
      cache.set(ifsc, { at: Date.now(), info });
      return info;
    }
    if (!res.ok) throw new Error(`IFSC directory ${res.status}`);
    const d = await res.json();
    const info = {
      valid: true, found: true, verified: true, ifsc,
      bank: d.BANK || guess || null,
      branch: d.BRANCH ? title(d.BRANCH) : null,
      city: d.CITY ? title(d.CITY) : (d.DISTRICT ? title(d.DISTRICT) : null),
      state: d.STATE ? title(d.STATE) : null,
      address: d.ADDRESS || null,
    };
    cache.set(ifsc, { at: Date.now(), info });
    return info;
  } catch (err) {
    console.warn('[ifsc]', err.message);
    // Offline: name the bank from its code, but don't claim the branch exists.
    return { valid: true, found: null, verified: false, ifsc, bank: guess || null };
  }
}

/** { valid, handle, app, bank, known } for a UPI ID such as name@oksbi. */
function upiInfo(raw) {
  const vpa = String(raw || '').trim().toLowerCase();
  const m = /^([a-z0-9._-]{2,256})@([a-z][a-z0-9]{1,63})$/.exec(vpa);
  if (!m) return { valid: false, vpa };
  const known = UPI_HANDLES[m[2]];
  return { valid: true, vpa, handle: m[2], app: known?.[0] || null, bank: known?.[1] || null, known: Boolean(known) };
}

module.exports = {
  ifscInfo, upiInfo, IFSC_RE, BANK_CODES, UPI_HANDLES,
  set fetchImpl(f) { fetchImpl = f; cache.clear(); },
  get fetchImpl() { return fetchImpl; },
};
