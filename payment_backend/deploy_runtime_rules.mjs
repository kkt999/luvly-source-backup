// Narrow administrative migration. Abort if local and deployed rules differ.
import { loadEnvFile } from 'node:process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getSecurityRules } from 'firebase-admin/security-rules';
const directory = dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory, '.env'));
try {
  const credential = JSON.parse(readFileSync(resolve(directory, process.env.GOOGLE_APPLICATION_CREDENTIALS), 'utf8'));
  if (credential.project_id !== 'luvly-44c77') throw Error('WRONG_PROJECT');
  const app = initializeApp({ credential: cert(credential), projectId: 'luvly-44c77' });
  const rules = getSecurityRules(app);
  const before = await rules.getFirestoreRuleset();
  const normalize = s => s.replace(/\r\n/g, '\n').trim();
  const local = normalize(readFileSync(resolve(directory, '../firestore.rules'), 'utf8'));
  const block = "    // Endpoint discovery is admin-managed; no app account can redirect tokens.\n    match /runtimeConfig/backend {\n      allow get: if request.auth != null;\n      allow list, create, update, delete: if false;\n    }\n";
  const remote = normalize(before.source[0].content);
  if (remote === local) { console.log('Runtime rules already deployed:', before.name); }
  else {
    if (!local.includes(block) || local.replace(block, '') !== remote) throw Error('UNRELATED_RULE_DIFFERENCE');
    console.log('Verified only change is runtimeConfig/backend get permission. Previous ruleset:', before.name);
    if (process.argv.includes('--publish')) {
      const current = await rules.getFirestoreRuleset();
      if (current.name !== before.name) throw Error('RULES_CHANGED');
      await rules.releaseFirestoreRulesetFromSource(local);
      const after = await rules.getFirestoreRuleset();
      if (normalize(after.source[0].content) !== local) throw Error('VERIFY_FAILED');
      console.log('Published and verified:', after.name);
    }
  }
} catch (e) {
  console.error('Rules migration stopped:', /^[A-Z_]+$/.test(e.message) ? e.message : 'ADMIN_RULES_ACCESS_FAILED');
  process.exitCode = 1;
}
