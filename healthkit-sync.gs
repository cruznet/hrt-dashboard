// ── Health Auto Export → Google Sheets Sync ──────────────────────────────
// Health Auto Export is saving Google Sheets files to Drive.
// This script reads all of them, deduplicates by date, and writes the
// combined data to a "HealthKit" tab in your HRT Google Sheet.
//
// Setup:
//   1. Paste into Apps Script (script.google.com), save
//   2. Run inspectFolder() to confirm it sees the files
//   3. Run syncHealthKit() to do the first sync
//   4. Run setupTrigger() to schedule daily auto-sync at 3 AM

const HK_FOLDER_ID = '1jFc2yMCsqOoZ8GboS37O2oXht-Cqu6AN';
const HK_SHEET_ID  = '1-1zGJo-1SudZ37LZKzqgs-7pCcvLU2haSNjOYUuF19Q';
const HK_TAB_NAME  = 'HealthKit';

// ── Debug: confirms what files are in the folder ──────────────────────────
function inspectFolder() {
  const folder = DriveApp.getFolderById(HK_FOLDER_ID);
  Logger.log('Folder: ' + folder.getName());

  let count = 0;
  const files = folder.getFilesByType(MimeType.GOOGLE_SHEETS);
  while (files.hasNext()) {
    const f = files.next();
    Logger.log('SHEET: ' + f.getName() + ' | modified: ' + f.getLastUpdated());
    count++;
  }

  // Also check subfolders
  const subs = folder.getFolders();
  while (subs.hasNext()) {
    const sub = subs.next();
    Logger.log('SUBFOLDER: ' + sub.getName());
    const subFiles = sub.getFilesByType(MimeType.GOOGLE_SHEETS);
    while (subFiles.hasNext()) {
      const f = subFiles.next();
      Logger.log('  SHEET: ' + f.getName() + ' | modified: ' + f.getLastUpdated());
      count++;
    }
  }

  Logger.log('Total Sheets files found: ' + count);
}

// ── Main sync ─────────────────────────────────────────────────────────────
function syncHealthKit() {
  const folder = DriveApp.getFolderById(HK_FOLDER_ID);

  let headers = null;
  const rowsByDate = {};
  let filesProcessed = 0;

  // Process all Google Sheets files in the folder (and subfolders)
  _eachSheetFile(folder, function(file) {
    Logger.log('Reading: ' + file.getName());
    let ss;
    try {
      ss = SpreadsheetApp.openById(file.getId());
    } catch (e) {
      Logger.log('  Cannot open: ' + e.message);
      return;
    }

    const sheet = ss.getSheets()[0];
    const data = sheet.getDataRange().getValues();
    if (!data || data.length < 2) {
      Logger.log('  Empty or header-only, skipping');
      return;
    }

    // Normalize headers from the first valid file
    const fileHeaders = data[0].map(function(h) { return String(h || '').trim(); });
    if (!headers) {
      headers = fileHeaders;
      Logger.log('  Headers (' + headers.length + ' cols): ' + headers.slice(0, 5).join(', ') + '...');
    }

    // Collect rows keyed by the first column (date)
    for (var i = 1; i < data.length; i++) {
      var row = data[i].map(function(v) { return v === null || v === undefined ? '' : String(v); });
      var dateKey = row[0].trim();
      if (!dateKey) continue;

      // Keep the row with the most filled cells (more complete data wins)
      var existing = rowsByDate[dateKey];
      if (!existing || _filledCount(row) > _filledCount(existing)) {
        rowsByDate[dateKey] = row;
      }
    }
    filesProcessed++;
    Logger.log('  Done. Unique dates so far: ' + Object.keys(rowsByDate).length);
  });

  if (!headers || filesProcessed === 0) {
    Logger.log('❌ No Google Sheets files found in folder. Run inspectFolder() to diagnose.');
    return;
  }

  // Sort chronologically and build the output array
  const dates = Object.keys(rowsByDate).sort();
  const output = [headers];
  dates.forEach(function(d) {
    var row = rowsByDate[d].slice();
    while (row.length < headers.length) row.push('');
    output.push(row.slice(0, headers.length));
  });

  // Write to HealthKit tab in the HRT Google Sheet
  const targetSS = SpreadsheetApp.openById(HK_SHEET_ID);
  var targetSheet = targetSS.getSheetByName(HK_TAB_NAME);
  if (!targetSheet) {
    targetSheet = targetSS.insertSheet(HK_TAB_NAME);
    Logger.log('Created tab: ' + HK_TAB_NAME);
  } else {
    targetSheet.clearContents();
  }
  targetSheet.getRange(1, 1, output.length, headers.length).setValues(output);

  Logger.log('✓ Done — ' + dates.length + ' days from ' + filesProcessed + ' files written to "' + HK_TAB_NAME + '" tab');
}

// ── Helpers ───────────────────────────────────────────────────────────────

function _eachSheetFile(folder, callback) {
  var files = folder.getFilesByType(MimeType.GOOGLE_SHEETS);
  while (files.hasNext()) callback(files.next());

  var subs = folder.getFolders();
  while (subs.hasNext()) _eachSheetFile(subs.next(), callback);
}

function _filledCount(row) {
  return row.filter(function(v) { return v !== null && v !== undefined && String(v).trim() !== ''; }).length;
}

// ── Schedule daily trigger ────────────────────────────────────────────────
function setupTrigger() {
  // Remove old triggers
  ScriptApp.getProjectTriggers().forEach(function(t) {
    if (t.getHandlerFunction() === 'syncHealthKit') {
      ScriptApp.deleteTrigger(t);
      Logger.log('Removed old trigger');
    }
  });

  // Daily at 3 AM
  ScriptApp.newTrigger('syncHealthKit')
    .timeBased()
    .everyDays(1)
    .atHour(3)
    .create();

  Logger.log('✓ Trigger set: syncHealthKit at 3 AM daily');
  Logger.log('Running initial sync...');
  syncHealthKit();
}
