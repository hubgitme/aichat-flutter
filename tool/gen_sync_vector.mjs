// تولید بردارِ تستِ رمزنگاریِ سینک از روی پیاده‌سازیِ واقعیِ JS.
// استفاده:
//   node tool/gen_sync_vector.mjs <مسیر sync-crypto.js نسخهٔ وب>
// خروجی: test/sync_vector.json (تستِ sync_crypto_test.dart آن را می‌خواند).
// بررسی می‌کند: PBKDF2 (با node crypto)، AES-256-GCM و gzip — برای بلاب‌های
// kind=1، kind=2 و بلابی که خودِ JS ساخته است.

import crypto from 'node:crypto';
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const src = process.argv[2];
if (!src) {
  console.error('usage: node tool/gen_sync_vector.mjs <path-to-sync-crypto.js>');
  process.exit(1);
}
const tmp = path.join(process.env.TMPDIR || '/tmp', 'sync-crypto-vector.mjs');
fs.copyFileSync(src, tmp);
const { deriveKeys, encryptJson, isValidCode } = await import(
  pathToFileURL(tmp).href
);

const code = 'ABCD-EFGH-JKLM-NPQR-STUV';
if (!isValidCode(code)) throw new Error('bad code');
const { aesKey, syncId } = await deriveKeys(code);

// KDF مستقل با node crypto (کلید WebCrypto قابل export نیست)
const bits = crypto.pbkdf2Sync(code.replace(/-/g, ''), 'aichat-sync-v1', 100000, 64, 'sha256');
const keyHex = bits.subarray(0, 32).toString('hex');
if (bits.subarray(32).toString('hex') !== syncId) {
  throw new Error('syncId mismatch vs node pbkdf2');
}

const sample = { id: 'c1', title: 'تست', created_at: 1700000000000, updated_at: 1700000001000,
  messages: [{ role: 'user', content: 'سلام' }, { role: 'assistant', content: 'سلام! چطوری؟' }] };
const jsBlob = await encryptJson(aesKey, sample);

const raw = Buffer.from(JSON.stringify(sample), 'utf8');
function encBlob(kind, payload) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', Buffer.from(keyHex, 'hex'), iv);
  const ct = Buffer.concat([c.update(payload), c.final(), c.getAuthTag()]);
  return Buffer.concat([Buffer.from([kind]), iv, ct]).toString('base64');
}
const kind1Blob = encBlob(1, raw);
const kind2Blob = encBlob(2, zlib.gzipSync(raw));

function dec(b64) {
  const b = Buffer.from(b64, 'base64');
  const kind = b[0], iv = b.subarray(1, 13), data = b.subarray(13);
  const d = crypto.createDecipheriv('aes-256-gcm', Buffer.from(keyHex, 'hex'), iv);
  d.setAuthTag(data.subarray(data.length - 16));
  const plain = Buffer.concat([d.update(data.subarray(0, data.length - 16)), d.final()]);
  return kind === 2 ? zlib.gunzipSync(plain).toString('utf8') : plain.toString('utf8');
}
const plain = JSON.stringify(sample);
for (const [name, blob] of [['js', jsBlob], ['kind1', kind1Blob], ['kind2', kind2Blob]]) {
  if (dec(blob) !== plain) throw new Error('decrypt mismatch: ' + name);
}
console.log('ALL CRYPTO CHECKS PASSED');
console.log('syncId:', syncId);
const outDir = path.dirname(fileURLToPath(import.meta.url));
fs.writeFileSync(path.join(outDir, '..', 'test', 'sync_vector.json'), JSON.stringify({
  code, syncId, aesKeyHex: keyHex, plaintext: sample,
  jsBlob, kind1Blob, kind2Blob,
}, null, 2));
console.log('vector written to test/sync_vector.json');
