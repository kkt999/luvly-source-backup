// Admin-only local endpoint rotation. Never prints credential material.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {validBackendOrigin} from './backend_origin.mjs';
const directory = dirname(fileURLToPath(import.meta.url));
const origin = process.argv[2];
if (!validBackendOrigin(origin)) {
  throw Error('Expected a temporary HTTPS tunnel origin');
}
const health = await fetch(`${origin}/health`, { redirect: 'error', signal: AbortSignal.timeout(15000) });
if (!health.ok || (await health.json()).environment !== 'sandbox') throw Error('Endpoint health check failed');
const envPath = resolve(directory, '.env');
let env = readFileSync(envPath, 'utf8');
for (const [key, suffix] of [['PAYMENT_RETURN_URL', 'return'], ['PAYMENT_CALLBACK_URL', 'callback']]) {
  const pattern = new RegExp(`^${key}=.*$`, 'm');
  if (!pattern.test(env)) throw Error('Missing callback configuration');
  env = env.replace(pattern, `${key}=${origin}/${suffix}`);
}
const calendarPath = resolve(directory, 'secrets/calendar-config.json');
const calendar = existsSync(calendarPath) ? JSON.parse(readFileSync(calendarPath, 'utf8')) : null;
writeFileSync(envPath, env);
if (calendar) {
  calendar.redirectUri = `${origin}/oauth/google/calendar/callback`;
  writeFileSync(calendarPath, JSON.stringify(calendar, null, 2) + '\n');
}
console.log('Local endpoint configured. Restart backend before publishing. Calendar OAuth redirect must also be registered in Google Cloud.');
