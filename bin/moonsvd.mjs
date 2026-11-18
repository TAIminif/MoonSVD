#!/usr/bin/env node
import { closeSync, fstatSync, openSync, readSync } from 'node:fs';

const usage = [
  'MoonSVD commands',
  '  inspect <file.svd>',
  '  check <file.svd>',
  '  lookup <file.svd> <Peripheral.Register>',
  '  diff <before.svd> <after.svd>',
].join('\n');

const byteLimit = 16 * 1024 * 1024;

function readSvd(path) {
  const file = openSync(path, 'r');
  try {
    const stat = fstatSync(file);
    if (!stat.isFile() || stat.size > byteLimit) {
      throw new Error('SVD input must be a regular file of at most 16 MiB');
    }
    const bytes = Buffer.alloc(stat.size + 1);
    let count = 0;
    while (count < bytes.length) {
      const read = readSync(file, bytes, count, bytes.length - count, null);
      if (!read) break;
      count += read;
    }
    if (count !== stat.size) throw new Error('SVD input size changed while reading');
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, count));
  } finally {
    closeSync(file);
  }
}

async function main(args) {
  if (args.length === 0 || (args.length === 1 && ['--help', '-h'].includes(args[0]))) {
    console.log(usage);
    return 0;
  }
  const [command, path, extra] = args;
  const counts = new Map([['inspect', 2], ['check', 2], ['lookup', 3], ['diff', 3]]);
  if (counts.get(command) !== args.length) {
    console.error(usage);
    return 2;
  }
  let bridge;
  try {
    bridge = await import('../_build/js/release/build/bridge/bridge.js');
  } catch (error) {
    if (error.code === 'ERR_MODULE_NOT_FOUND') {
      throw new Error('Build the CLI first with moon build --target js --release', { cause: error });
    }
    throw error;
  }
  const text = readSvd(path);
  const other = command === 'diff' ? readSvd(extra) : (extra ?? '');
  const { code, report } = JSON.parse(bridge.execute(command, text, other));
  if (report.error) console.error(report.error);
  else console.log(JSON.stringify(report, null, 2));
  return code;
}

main(process.argv.slice(2)).then(code => {
  process.exitCode = code;
}).catch(error => {
  console.error(error.message);
  process.exitCode = 2;
});
