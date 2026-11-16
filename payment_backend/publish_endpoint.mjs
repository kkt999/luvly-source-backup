// Explicit administrator command. Never called by the public HTTP service.
import { loadEnvFile } from 'node:process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import {validBackendOrigin} from './backend_origin.mjs';

const directory = dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory, '.env'));
try {
  const origin = new URL(process.argv[2]);
  if (!validBackendOrigin(process.argv[2])) throw Error();
  if (process.env.PAYMENT_RETURN_URL !== `${origin.origin}/return` ||
      process.env.PAYMENT_CALLBACK_URL !== `${origin.origin}/callback`) throw Error();
  const health = await fetch(`${origin.origin}/health`, { redirect: 'error', signal: AbortSignal.timeout(15000) });
  if (!health.ok || (await health.json()).environment !== 'sandbox') throw Error();
  const credential = JSON.parse(readFileSync(resolve(directory, process.env.GOOGLE_APPLICATION_CREDENTIALS), 'utf8'));
  if (credential.project_id !== 'luvly-44c77') throw Error();
  const app = initializeApp({ credential: cert(credential), projectId: 'luvly-44c77' });
  const db = getFirestore(app);
  await db.doc('runtimeConfig/backend').set({
    schemaVersion: 1, environment: 'sandbox', enabled: true,
    baseUrl: origin.origin, updatedAt: FieldValue.serverTimestamp(),
  });
  const current = (await db.doc('runtimeConfig/backend').get()).data();
  if (current.baseUrl !== origin.origin) throw Error();
  console.log('Verified Firebase runtimeConfig/backend:', current.baseUrl);
  await db.terminate();
} catch {
  console.error('Endpoint not published. Check URL, health and local administrator configuration; no secrets logged.');
  process.exitCode = 1;
}
