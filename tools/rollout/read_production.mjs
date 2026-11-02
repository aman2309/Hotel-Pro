// Read-only production audit. Never deploys, imports, or writes application data.
// Tokens stay in memory. Private records are written only under .checkpoints.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const project = 'yankees-hotel-pro';
const root = path.resolve(import.meta.dirname, '../..');
const dir = path.join(root, '.checkpoints', `production-audit-${Date.now()}`);
if (fs.existsSync(path.join(dir, 'audit-summary.json'))) {
  console.error('Existing checkpoint preserved. Use a new dated output directory for a fresh audit.');
  process.exit(2);
}
fs.mkdirSync(dir, {recursive: true, mode: 0o700});
const save = (name, data) => fs.writeFileSync(path.join(dir, name), JSON.stringify(data, null, 2), {mode: 0o600});
const summary = {project, auditedAt: new Date().toISOString(), writes: false, checks: {}};
let token;
async function get(url) {
  const response = await fetch(url, {headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(30000)});
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}
async function paged(url, field) {
  let results = [], pageToken;
  do {
    const u = new URL(url);
    u.searchParams.set('pageSize', '100');
    if (pageToken) u.searchParams.set('pageToken', pageToken);
    const data = await get(u);
    results.push(...(data[field] ?? []));
    pageToken = data.nextPageToken;
  } while (pageToken);
  return results;
}
async function check(name, fn) {
  try { summary.checks[name] = await fn(); }
  catch (error) { summary.checks[name] = {verified: false, error: /^HTTP \d+$/.test(error.message) ? error.message : 'Access/network/authentication unavailable'}; }
  console.log(name, JSON.stringify(summary.checks[name]));
}
try {
  const auth = require('/opt/homebrew/Cellar/firebase-cli/15.30.1/libexec/lib/node_modules/firebase-tools/lib/auth.js');
  const account = auth.getProjectDefaultAccount(root);
  if (!account) throw new Error('No CLI account');
  const credentials = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/firebase']);
  token = credentials.access_token;
  if (!token) throw new Error('No access token');
} catch {
  summary.checks.authentication = {verified: false, error: 'CLI authentication unavailable; no production reads completed'};
  save('audit-summary.json', summary);
  console.log(JSON.stringify(summary));
  process.exit(2);
}
await check('rulesBackup', async () => {
  const releases = await paged(`https://firebaserules.googleapis.com/v1/projects/${project}/releases`, 'releases');
  save('releases.json', releases);
  const manifest = [];
  for (let i = 0; i < releases.length; i++) {
    const release = releases[i];
    const ruleset = await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
    save(`ruleset-${i}.json`, ruleset);
    const files = [];
    for (let j = 0; j < (ruleset.source?.files ?? []).length; j++) {
      const file = ruleset.source.files[j];
      const local = `release-${i}-source-${j}.rules`;
      fs.writeFileSync(path.join(dir, local), file.content, {mode: 0o600});
      files.push({originalName: file.name, local, sha256: crypto.createHash('sha256').update(file.content).digest('hex')});
    }
    const current = await get(`https://firebaserules.googleapis.com/v1/${release.name}`);
    if (current.rulesetName !== release.rulesetName) throw new Error('Release changed during backup; retry audit');
    manifest.push({release: release.name, ruleset: release.rulesetName, updateTime: release.updateTime, files});
  }
  save('rules-manifest.json', manifest);
  return {verified: true, releases: manifest};
});
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const value = (v) => v?.stringValue ?? v?.integerValue ?? v?.booleanValue ?? v?.timestampValue ?? null;
const field = (d, key) => value(d.fields?.[key]);
await check('ownerInventory', async () => {
  const businesses = await paged(`${base}/businesses`, 'documents');
  const users = await paged(`${base}/users`, 'documents');
  const phoneIndex = await paged(`${base}/phoneIndex`, 'documents');
  save('identity-inventory.json', {businesses, users, phoneIndex});
  return {verified: true, businessCount: businesses.length, userCount: users.length, phoneIndexCount: phoneIndex.length,
    owners: businesses.map(b => ({businessId: b.name.split('/').at(-1), ownerUid: field(b, 'ownerUid'), hotelName: field(b, 'hotelName'), linkedUsers: users.filter(u => field(u, 'businessId') === b.name.split('/').at(-1)).length, linkedPhones: phoneIndex.filter(p => field(p, 'businessId') === b.name.split('/').at(-1)).length}))};
});
save('audit-summary.json', summary);
console.log('Private audit saved; no production application writes performed.');
