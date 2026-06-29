#!/usr/bin/env node
// backfill-healthkit.js — one-time script to upload CSV rows to /api/healthkit
// Usage: INGEST_KEY=<your-key> node backfill-healthkit.js [csv-file] [base-url]
//
// Defaults:
//   csv-file  = healthkit-data.csv
//   base-url  = https://hrt.cruznetllc.com

const fs       = require('fs');
const path     = require('path');
const https    = require('https');
const http     = require('http');

const csvFile  = process.argv[2] || path.join(__dirname, 'healthkit-data.csv');
const baseUrl  = (process.argv[3] || 'https://hrt.cruznetllc.com').replace(/\/$/, '');
const ingestKey = process.env.INGEST_KEY;

if (!ingestKey) {
  console.error('Error: INGEST_KEY environment variable is required');
  console.error('Usage: INGEST_KEY=<your-key> node backfill-healthkit.js [csv-file] [base-url]');
  process.exit(1);
}

const csvText = fs.readFileSync(csvFile, 'utf8');
const url     = `${baseUrl}/api/healthkit`;

console.log(`Uploading ${csvFile} → ${url}`);

const body    = Buffer.from(csvText, 'utf8');
const parsed  = new URL(url);
const lib     = parsed.protocol === 'https:' ? https : http;

const req = lib.request({
  hostname: parsed.hostname,
  port:     parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
  path:     parsed.pathname,
  method:   'POST',
  headers: {
    'Content-Type':   'text/csv',
    'Content-Length': body.length,
    'X-Ingest-Key':   ingestKey,
  },
}, res => {
  let data = '';
  res.on('data', c => data += c);
  res.on('end', () => {
    console.log(`Status: ${res.statusCode}`);
    try { console.log(JSON.parse(data)); } catch { console.log(data); }
    process.exit(res.statusCode === 200 ? 0 : 1);
  });
});

req.on('error', e => { console.error('Request error:', e.message); process.exit(1); });
req.write(body);
req.end();
