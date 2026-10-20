#!/usr/bin/env node
/**
 * 生成 hvigor 签名密码的加密材料（复刻 DevEco Studio 的方案）。
 *
 * hvigor 的 DecipherUtil 要求：
 *   <keystore所在目录>/material/
 *     fd/  下恰好 3 个目录，每个目录恰好 1 个 16 字节文件（异或分量）
 *     ac/  下恰好 1 个目录，其中 1 个文件（PBKDF2 salt）
 *     ce/  下恰好 1 个目录，其中 1 个文件（AES-128-GCM 加密的最终密钥）
 *   build-profile.json5 中的 storePassword/keyPassword 为密文 hex：
 *     rootKey = PBKDF2(Buffer.from(fd0^fd1^fd2^component).toString(), salt, 10000, 16, sha256)
 *     finalKey = AES-128-GCM-decrypt(rootKey, ceBlob)
 *     password = AES-128-GCM-decrypt(finalKey, passwordBlob).toString('utf-8')
 *
 * 用法： node generate-signing-material.js <明文密码> <material目录>
 */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const plaintext = process.argv[2];
const materialDir = process.argv[3];

if (!plaintext || !materialDir) {
  console.error('usage: node generate-signing-material.js <password> <materialDir>');
  process.exit(1);
}

const COMPONENT = new Int8Array([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);

function gcmEncrypt(key, plaintextBuf) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(plaintextBuf), cipher.final()]);
  const tag = cipher.getAuthTag();
  // hvigor 的 blob 格式：[BE32(ivLen + ctLen + 4)][iv][ct][tag]
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(iv.length + ct.length + 4, 0);
  return Buffer.concat([lenBuf, iv, ct, tag]);
}

function gcmDecrypt(key, blob) {
  // 与 hvigor DecipherUtil.decrypt 完全一致的解析逻辑
  const e = blob.readUInt32BE(0);            // = ivLen + ctLen + 4
  const i = blob.length - 4 - e;             // = ivLen
  const iv = blob.slice(4, 4 + i);
  const ct = blob.slice(4 + i, blob.length - 16);
  const tag = blob.slice(blob.length - 16);
  const decipher = crypto.createDecipheriv('aes-128-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]);
}

function writeSingleFileDir(dir, buf) {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'data.bin'), buf);
}

// 注意 hvigor 的目录约定：
//   material/fd/<子目录>/<文件>   —— fd 下 3 个子目录，各含 1 个 16 字节文件
//   material/ac/<文件>            —— ac 下直接 1 个文件（salt）
//   material/ce/<文件>            —— ce 下直接 1 个文件（work material）

// 1. fd: 3 个 16 字节随机分量
const fd = [crypto.randomBytes(16), crypto.randomBytes(16), crypto.randomBytes(16)];
fd.forEach((b, i) => writeSingleFileDir(path.join(materialDir, 'fd', `fd${i + 1}`), b));

// 2. ac: salt（直接放在 ac/ 下的文件）
const salt = crypto.randomBytes(16);
fs.mkdirSync(path.join(materialDir, 'ac'), { recursive: true });
fs.writeFileSync(path.join(materialDir, 'ac', 'salt.bin'), salt);

// 3. rootKey = PBKDF2(Buffer.from(fd0^fd1^fd2^component).toString(), salt, 10000, 16, sha256)
function xorBytes(a, b) {
  const r = new Int8Array(a.length);
  for (let i = 0; i < a.length; i++) r[i] = a[i] ^ b[i];
  return r;
}
let acc = xorBytes(new Int8Array(fd[0]), new Int8Array(fd[1]));
for (let i = 2; i < fd.length; i++) acc = xorBytes(acc, new Int8Array(fd[i]));
acc = xorBytes(acc, COMPONENT);
const rootKey = crypto.pbkdf2Sync(Buffer.from(acc).toString(), salt, 10000, 16, 'sha256');

// 4. finalKey（16 字节随机）经 rootKey 加密后写入 ce/（直接文件）
const finalKey = crypto.randomBytes(16);
const ceBlob = gcmEncrypt(rootKey, finalKey);
fs.mkdirSync(path.join(materialDir, 'ce'), { recursive: true });
fs.writeFileSync(path.join(materialDir, 'ce', 'work.bin'), ceBlob);

// 5. 用 finalKey 加密明文密码，输出 hex
const pwdBlob = gcmEncrypt(finalKey, Buffer.from(plaintext, 'utf-8'));

// 自校验：按 hvigor 的路径完整解密一遍
const decryptedFinalKey = gcmDecrypt(rootKey, ceBlob);
const decryptedPwd = gcmDecrypt(decryptedFinalKey, pwdBlob).toString('utf-8');
if (decryptedPwd !== plaintext) {
  console.error('self-check failed: decrypted password mismatch');
  process.exit(1);
}

console.log(pwdBlob.toString('hex'));
