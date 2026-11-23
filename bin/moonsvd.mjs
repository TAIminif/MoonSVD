#!/usr/bin/env node
import { closeSync, constants, fstatSync, openSync, readSync, statSync } from 'node:fs';

const usage = [
  'MoonSVD commands',
  '  inspect <file.svd>',
  '  check <file.svd>',
  '  lookup <file.svd> <Peripheral.Register>',
  '  at <file.svd> <address>',
  '  diff <before.svd> <after.svd>',
].join('\n');

const byteLimit = 16 * 1024 * 1024;

function checkInputFile(stat) {
  if (!stat.isFile() || stat.size > byteLimit) {
    throw new Error('SVD input must be a regular file of at most 16 MiB');
  }
}

function readSvd(path) {
  checkInputFile(statSync(path));
  // Nonblocking open also covers a POSIX file replaced by a pipe after stat.
  const file = openSync(path, constants.O_RDONLY | (constants.O_NONBLOCK ?? 0));
  try {
    const stat = fstatSync(file);
    checkInputFile(stat);
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

function printError(message) {
  const printable = message.replace(/[\u0000-\u001f\u007f-\u009f]/g, character =>
    '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0')
  );
  console.error(printable);
}

async function main(args) {
  if (args.length === 0 || (args.length === 1 && ['--help', '-h'].includes(args[0]))) {
    console.log(usage);
    return 0;
  }
  const [command, path, extra] = args;
  const counts = new Map([
    ['inspect', 2], ['check', 2], ['lookup', 3], ['at', 3], ['diff', 3],
  ]);
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
  if (report.error) printError(report.error);
  else console.log(JSON.stringify(report, null, 2));
  return code;
}

main(process.argv.slice(2)).then(code => {
  process.exitCode = code;
}).catch(error => {
  printError(error.message);
  process.exitCode = 2;
});
