// Explicit user-authorized admin operation. Dry run by default; no secrets logged.
import { loadEnvFile } from 'node:process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { variantId } from './rental_service.mjs';
import { withDemoMeasurements } from './demo_measurements.mjs';
const directory = dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory, '.env'));
const credential = JSON.parse(readFileSync(resolve(directory, process.env.GOOGLE_APPLICATION_CREDENTIALS), 'utf8'));
if (credential.project_id !== 'luvly-44c77') throw Error('Wrong project');
const app = initializeApp({ credential: cert(credential), projectId: credential.project_id });
const db = getFirestore(app);
const apply = process.argv.includes('--apply');
try {
  const dresses = await db.collection('dresses').get();
  let count = 0;
  for (const d of dresses.docs) {
    for (const size of (d.data().sizes ?? '').split(', ')) {
      const id = variantId(d.id, size), ref = db.doc(`rentalVariants/${id}`);
      const changed = await db.runTransaction(async tx => {
        const latestDress = await tx.get(d.ref);
        const existing = await tx.get(ref);
        if (!(latestDress.data()?.sizes ?? '').split(', ').includes(size)) return false;
        const next = withDemoMeasurements(existing.data(), size);
        if (!next) return false;
        if (apply) tx.set(ref, { ...next, id, dressId: d.id, size });
        return true;
      });
      if (changed) { count++; console.log(`${apply ? 'Filled' : 'Would fill'} ${d.id} / ${size}`); }
    }
  }
  console.log(`${apply ? 'Applied' : 'Dry run'}: ${count} missing size records. Existing measurements, quantities, allocations and dress prices preserved.`);
} finally { await db.terminate(); }
