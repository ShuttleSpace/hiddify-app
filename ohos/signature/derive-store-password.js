#!/usr/bin/env node
/**
 * 从已有的 material 目录派生 hvigor 的 storePassword 密文 hex。
 *
 * 与 generate-signing-material.js 的区别：
 *   - generate-signing-material.js  *生成* material 目录并输出密文
 *   - derive-store-password.js      复用 DevEco Studio 生成的 material 目录，
 *                                   只把明文口令加密成密文
 *
 * 原理（hvigor DecipherUtil）：
 *   rootKey = PBKDF2(Buffer.from(fd0^fd1^fd2^component).toString(), salt, 10000, 16, sha256)
 *   finalKey = AES-128-GCM-decrypt(rootKey, ceBlob)
 *   password = AES-128-GCM-decrypt(finalKey, passwordBlob)   // build-profile.json5 里的 hex
 *
 * 用法： node derive-store-password.js <material目录>
 *
 * 明文口令从环境变量 KEYSTORE_PASSWORD 读（不放在命令行参数里，
 * 避免出现在 ps 输出 / shell 历史中）。
 */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const COMPONENT = new Int8Array([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);

const materialDir = process.argv[2];
const plaintext = process.env.KEYSTORE_PASSWORD;

if (!materialDir || plaintext === undefined) {
  console.error('usage: KEYSTORE_PASSWORD=xxx node derive-store-password.js <materialDir>');
  process.exit(1);
}

function gcmEncrypt(key, buf) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ct = Buffer.concat([c.update(buf), c.final()]);
  const tag = c.getAuthTag();
  const len = Buffer.alloc(4);
  len.writeUInt32BE(iv.length + ct.length + 4, 0);
  return Buffer.concat([len, iv, ct, tag]);
}

function gcmDecrypt(key, blob) {
  const e = blob.readUInt32BE(0);
  const i = blob.length - 4 - e;
  const iv = blob.slice(4, 4 + i);
  const ct = blob.slice(4 + i, blob.length - 16);
  const tag = blob.slice(blob.length - 16);
  const d = crypto.createDecipheriv('aes-128-gcm', key, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(ct), d.final()]);
}

function xorBytes(a, b) {
  const r = new Int8Array(a.length);
  for (let i = 0; i < a.length; i++) r[i] = a[i] ^ b[i];
  return r;
}

// DevEco 的目录里每个子目录只有 1 个文件，文件名是随机的哈希，所以按内容读。
function readOne(dir) {
  const files = fs.readdirSync(dir, { withFileTypes: true }).filter((d) => d.isFile());
  if (files.length !== 1) {
    throw new Error(`expected exactly 1 file in ${dir}, got ${files.length}`);
  }
  return fs.readFileSync(path.join(dir, files[0].name));
}

const fdDir = path.join(materialDir, 'fd');
const fd = fs.readdirSync(fdDir).sort().map((n) => readOne(path.join(fdDir, n)));
if (fd.length !== 3) throw new Error(`expected 3 fd dirs, got ${fd.length}`);
const salt = readOne(path.join(materialDir, 'ac'));
const ceBlob = readOne(path.join(materialDir, 'ce'));

let acc = xorBytes(new Int8Array(fd[0]), new Int8Array(fd[1]));
acc = xorBytes(acc, new Int8Array(fd[2]));
acc = xorBytes(acc, COMPONENT);
const rootKey = crypto.pbkdf2Sync(Buffer.from(acc).toString(), salt, 10000, 16, 'sha256');
const finalKey = gcmDecrypt(rootKey, ceBlob);

const blob = gcmEncrypt(finalKey, Buffer.from(plaintext, 'utf-8'));

// 自校验：按 hvigor 的路径完整解密一遍
const back = gcmDecrypt(finalKey, blob).toString('utf-8');
if (back !== plaintext) {
  console.error('self-check failed');
  process.exit(1);
}

console.log(blob.toString('hex'));
