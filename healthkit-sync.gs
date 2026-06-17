// ── Health Auto Export → Google Sheets Sync ──────────────────────────────
// Paste this entire file into Google Apps Script: script.google.com
// Open a new project, replace the default code, and save.
//
// First-time setup:
//   1. Click Run → setupTrigger() to authorize and schedule daily sync
//   2. Approve permissions (Drive + Sheets access required)
//   3. Optionally run syncHealthKit() manually to populate data immediately

const HK_FOLDER_ID = '1jFc2yMCsqOoZ8GboS37O2oXht-Cqu6AN';
const HK_SHEET_ID  = '1-1zGJo-1SudZ37LZKzqgs-7pCcvLU2haSNjOYUuF19Q';
const HK_TAB_NAME  = 'HealthKit';

// ── Main sync function ────────────────────────────────────────────────────
function syncHealthKit() {
  const folder = DriveApp.getFolderById(HK_FOLDER_ID);
  const files = folder.getFilesByType(MimeType.CSV);

  let headers = null;
  const rowsByDate = {};

  while (files.hasNext()) {
    const file = files.next();
    let csv;
    try {
      csv = Utilities.parseCsv(file.getBlob().getDataAsString('UTF-8'));
    } catch (e) {
      Logger.log('Skipping (parse error): ' + file.getName() + ' — ' + e.message);
      continue;
    }
    if (!csv || csv.length < 2) continue;

    // First valid file determines the column order
    if (!headers) {
      headers = csv[0].map(h => (h || '').trim());
      Logger.log('Headers from: ' + file.getName() + ' (' + headers.length + ' cols)');
    }

    // Collect rows keyed by date; prefer rows with more filled cells
    for (let i = 1; i < csv.length; i++) {
      const row = csv[i];
      const dateKey = (row[0] || '').trim();
      if (!dateKey) continue;
      const existing = rowsByDate[dateKey];
      if (!existing || _filledCount(row) > _filledCount(existing)) {
        rowsByDate[dateKey] = row;
      }
    }
  }

  if (!headers) {
    Logger.log('No CSV files found in Drive folder: ' + HK_FOLDER_ID);
    return;
  }

  // Sort rows chronologically
  const dates = Object.keys(rowsByDate).sort();
  const output = [headers];
  dates.forEach(d => {
    const row = rowsByDate[d].slice(); // copy
    // Pad or trim to header length
    while (row.length < headers.length) row.push('');
    output.push(row.slice(0, headers.length));
  });

  // Write to HealthKit sheet tab (clear + rewrite)
  const ss = SpreadsheetApp.openById(HK_SHEET_ID);
  let sheet = ss.getSheetByName(HK_TAB_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(HK_TAB_NAME);
    Logger.log('Created new tab: ' + HK_TAB_NAME);
  } else {
    sheet.clearContents();
  }
  sheet.getRange(1, 1, output.length, headers.length).setValues(output);

  Logger.log('✓ syncHealthKit complete — ' + dates.length + ' days written to "' + HK_TAB_NAME + '" tab');
}

function _filledCount(row) {
  return row.filter(v => v !== null && v !== undefined && v.toString().trim() !== '').length;
}

// ── One-time trigger setup ────────────────────────────────────────────────
// Run this once from the Apps Script editor to schedule daily sync at 3 AM
function setupTrigger() {
  // Remove any existing triggers for syncHealthKit
  ScriptApp.getProjectTriggers().forEach(function(t) {
    if (t.getHandlerFunction() === 'syncHealthKit') {
      ScriptApp.deleteTrigger(t);
      Logger.log('Removed old trigger');
    }
  });

  // Create new daily trigger at 3:00 AM
  ScriptApp.newTrigger('syncHealthKit')
    .timeBased()
    .everyDays(1)
    .atHour(3)
    .create();

  Logger.log('✓ Daily trigger set: syncHealthKit runs at 3 AM every day');
  Logger.log('Running initial sync now...');
  syncHealthKit();
}
