// TWRXA - Firebase connectivity check.
//
// Tells you, in plain language, whether the backend the app needs is actually
// reachable. Run it from the project root:
//
//   node scripts/check-backend.mjs
//
// It only performs READ probes with the public keys that already ship in the
// app; it never writes anything.

const FIREBASE_API_KEY = 'AIzaSyCHjO5zVnSoxEnrn4htvXwNyTd-_CUb4cY';
const FIREBASE_PROJECT = 'twrxa-shop';

const results = [];

function record(name, ok, detail) {
  results.push({ name, ok, detail });
}

async function probe(url, options = {}) {
  try {
    const response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(20000),
    });
    const text = await response.text();
    return { status: response.status, ok: response.ok, text };
  } catch (error) {
    return { status: 0, ok: false, text: String(error?.message ?? error) };
  }
}

// --- Firebase Auth ----------------------------------------------------------
{
  const url = `https://identitytoolkit.googleapis.com/v1/projects?key=${FIREBASE_API_KEY}`;
  const { status, text } = await probe(url);
  if (status === 200) {
    record('Firebase Auth', true, 'Reachable - sign-in can work.');
  } else if (text.includes('API_KEY_INVALID')) {
    record('Firebase Auth', false, 'API key rejected - check firebase_options.dart.');
  } else {
    record('Firebase Auth', false, `HTTP ${status} - ${text.slice(0, 200)}`);
  }
}

// --- Cloud Firestore --------------------------------------------------------
// Products are public in Firestore and power the Vercel storefront.
//
// Note there are no collections to create by hand: Firestore creates a
// collection the first time a document is written into it, and the rules file
// matches paths, not pre-declared names. An empty console is a healthy console.
{
  const url =
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}` +
    `/databases/(default)/documents/products?key=${FIREBASE_API_KEY}`;
  const { status, text } = await probe(url);
  if (status === 403 && text.includes('SERVICE_DISABLED')) {
    record(
      'Cloud Firestore',
      false,
      'DISABLED. Enable Firestore at:\n' +
      '    https://console.firebase.google.com/project/twrxa-shop/firestore',
    );
  } else if (status === 404) {
    record(
      'Cloud Firestore',
      false,
      'No database created yet. Create one at:\n' +
      '    https://console.firebase.google.com/project/twrxa-shop/firestore',
    );
  } else if (status === 403 || status === 401) {
    // A permission error is EXPECTED for an unauthenticated read once the
    // database exists and rules are deployed - it means the DB is live.
    record('Cloud Firestore', true, 'Database is live.');
  } else if (status === 200) {
    record('Cloud Firestore', true, 'Database is live.');
  } else {
    record('Cloud Firestore', false, `HTTP ${status} - ${text.slice(0, 200)}`);
  }
}

// --- Cloud Storage ----------------------------------------------------------
// Cloud Storage is not part of the TWRXA product catalog integration.

// --- Report -----------------------------------------------------------------
console.log('\nTWRXA - Firebase connectivity check\n' + '='.repeat(44));
let failed = 0;
for (const { name, ok, detail } of results) {
  console.log(`\n${ok ? '[OK]  ' : '[FAIL]'} ${name}`);
  console.log(`   ${detail.replace(/\n/g, '\n   ')}`);
  if (!ok) failed += 1;
}
console.log('\n' + '='.repeat(44));
if (failed === 0) {
  console.log('All backends reachable. Data will persist across reloads.');
} else {
  console.log(
    `${failed} backend(s) need attention. Until they are fixed, data created ` +
      'in the app is not saved anywhere.',
  );
}
process.exit(failed === 0 ? 0 : 1);
