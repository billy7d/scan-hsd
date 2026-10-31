/**
 * Kho ăn dặm — Google Apps Script Web App ghi/đọc sheet "TonKho".
 *
 * Cột được tìm theo TÊN TIÊU ĐỀ ở dòng 1, không theo vị trí: có thể chèn thêm cột tự nhập ở bất kỳ đâu,
 * kéo đổi thứ tự cột. Chỉ cần giữ nguyên 6 tiêu đề trong HEADERS (không đổi chữ, không xoá).
 *
 * Cài đặt (xem HUONG_DAN.md):
 *   1. Extensions > Apps Script, dán toàn bộ file này.
 *   2. Đổi API_KEY bên dưới thành một chuỗi bí mật của bạn (phải trùng apiKey trong lib/config.dart của app).
 *   3. Chạy hàm caiDat() một lần (cấp quyền khi được hỏi). Đã cài từ bản trước thì không cần chạy lại.
 *   4. Deploy > New deployment > Web app: Execute as Me, Who has access Anyone.
 *      Cập nhật bản đang chạy: Deploy > Manage deployments > Edit > Version: New version (giữ nguyên URL).
 */

const API_KEY = 'DOI_KEY_NAY';
const SHEET_NAME = 'TonKho';

const HEADERS = ['Mã vạch', 'Tên sản phẩm', 'Date (HSD)', 'Số lượng', 'Giá bán', 'ID'];
const FIELDS = ['BARCODE', 'NAME', 'HSD', 'QTY', 'PRICE', 'ID'];
const PROTECT_DESC = 'ID - khong sua tay';
const NEAR_EXPIRY_DAYS = 90;

// ---------------------------------------------------------------- HTTP

function doGet(e) {
  return handle_(function () {
    const p = (e && e.parameter) || {};
    checkKey_(p.key);
    switch (p.action) {
      case 'ping': return { ok: true };
      case 'lookup': return lookup_(String(p.barcode || ''));
      case 'snapshot': return withLock_(snapshot_);
      default: throw new Error('action không hợp lệ: ' + p.action);
    }
  });
}

function doPost(e) {
  return handle_(function () {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    checkKey_(body.key);
    const actions = {
      add: add_, adjust: adjust_, updateLot: updateLot_, deleteLot: deleteLot_, updateProduct: updateProduct_,
    };
    const fn = actions[body.action];
    if (!fn) throw new Error('action không hợp lệ: ' + body.action);
    return withLock_(function () { return fn(body); });
  });
}

function handle_(fn) {
  colsCache_ = null;
  let out;
  try {
    out = fn();
  } catch (err) {
    out = { ok: false, error: String(err && err.message ? err.message : err) };
  }
  return ContentService.createTextOutput(JSON.stringify(out))
    .setMimeType(ContentService.MimeType.JSON);
}

function checkKey_(key) {
  if (!key || key !== API_KEY) throw new Error('Sai key');
}

function withLock_(fn) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    damBaoId_(getSheet_());
    const result = fn();
    SpreadsheetApp.flush();
    return result;
  } finally {
    lock.releaseLock();
  }
}

// ---------------------------------------------------------------- Cột theo tiêu đề

let colsCache_ = null;

/**
 * Vị trí cột (bắt đầu từ 1) của 6 trường, đọc từ dòng tiêu đề: {BARCODE, NAME, HSD, QTY, PRICE, ID, max}.
 * `max` = cột xa nhất trong 6 cột, để chỉ đọc đến đó. Thiếu tiêu đề → báo lỗi, không đọc/ghi lệch.
 */
function cols_(sheet) {
  if (colsCache_) return colsCache_;
  const width = sheet.getLastColumn();
  const header = width > 0 ? sheet.getRange(1, 1, 1, width).getValues()[0].map(norm_) : [];
  const c = { max: 0 };
  const missing = [];
  HEADERS.forEach(function (h, i) {
    const at = header.indexOf(norm_(h));
    if (at < 0) { missing.push('"' + h + '"'); return; }
    c[FIELDS[i]] = at + 1;
    c.max = Math.max(c.max, at + 1);
  });
  if (missing.length) {
    throw new Error('Sheet ' + SHEET_NAME + ' thiếu cột ' + missing.join(', ') +
      ' ở dòng tiêu đề — đừng đổi tên hoặc xoá 6 cột gốc');
  }
  colsCache_ = c;
  return c;
}

/** Chữ cái của cột (1 → A, 27 → AA) — dùng trong công thức tô màu. */
function colLetter_(n) {
  let s = '';
  for (; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s;
  return s;
}

// ---------------------------------------------------------------- Cài đặt

/** Chạy tay một lần: tạo sheet, tiêu đề, định dạng, tô màu, ID. Chạy lại không sao, không đụng tới cột tự thêm. */
function caiDat() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(SHEET_NAME);

  // Tiêu đề: sheet trống → ghi A→F; thiếu tiêu đề nào thì thêm vào cuối, giữ nguyên các cột đang có.
  const width = sheet.getLastColumn();
  const header = width > 0 ? sheet.getRange(1, 1, 1, width).getValues()[0].map(norm_) : [];
  let end = width;
  HEADERS.forEach(function (h) {
    if (header.indexOf(norm_(h)) >= 0) return;
    end++;
    if (end > sheet.getMaxColumns()) sheet.insertColumnAfter(sheet.getMaxColumns());
    sheet.getRange(1, end).setValue(h);
  });
  colsCache_ = null;
  const c = cols_(sheet);
  sheet.getRange(1, 1, 1, sheet.getLastColumn()).setFontWeight('bold');
  sheet.setFrozenRows(1);

  const rowsBelow = sheet.getMaxRows() - 1;
  const column = function (col, fromRow) { return sheet.getRange(fromRow, col, sheet.getMaxRows() - fromRow + 1, 1); };
  column(c.BARCODE, 1).setNumberFormat('@');
  column(c.HSD, 2).setNumberFormat('dd/MM/yyyy');
  column(c.QTY, 2).setNumberFormat('0');
  column(c.PRICE, 2).setNumberFormat('#,##0" ₫"');
  column(c.ID, 1).setNumberFormat('@');

  chuanHoaHsd_(sheet);
  damBaoId_(sheet);

  // Tô màu cả dòng: đỏ nhạt = đã hết hạn, vàng = còn ≤ 90 ngày. Quy tắc trên cả vùng nên dòng mới tự có màu.
  const range = sheet.getRange(2, 1, rowsBelow, sheet.getMaxColumns());
  const hsd = '$' + colLetter_(c.HSD) + '2';
  const rules = sheet.getConditionalFormatRules().filter(function (r) {
    return !r.getRanges().some(function (rg) { return rg.getRow() === 2 && rg.getColumn() === 1; });
  });
  rules.push(SpreadsheetApp.newConditionalFormatRule()
    .whenFormulaSatisfied('=AND(ISNUMBER(' + hsd + '),' + hsd + '<TODAY())')
    .setBackground('#F4C7C3').setRanges([range]).build());
  rules.push(SpreadsheetApp.newConditionalFormatRule()
    .whenFormulaSatisfied('=AND(ISNUMBER(' + hsd + '),' + hsd + '-TODAY()<=' + NEAR_EXPIRY_DAYS + ')')
    .setBackground('#FCE8B2').setRanges([range]).build());
  sheet.setConditionalFormatRules(rules);

  // Bảo vệ cột ID (chỉ cảnh báo).
  sheet.getProtections(SpreadsheetApp.ProtectionType.RANGE).forEach(function (p) {
    if (p.getDescription() === PROTECT_DESC) p.remove();
  });
  column(c.ID, 1).protect().setDescription(PROTECT_DESC).setWarningOnly(true);
  sheet.hideColumns(c.ID);
  sheet.setColumnWidth(c.NAME, 260);
}

/** Đổi ô HSD đang là chữ (nhập tay / dán từ Excel) thành ngày thật để tô màu được. */
function chuanHoaHsd_(sheet) {
  const n = sheet.getLastRow() - 1;
  if (n < 1) return;
  const range = sheet.getRange(2, cols_(sheet).HSD, n, 1);
  const values = range.getValues();
  let changed = false;
  for (let i = 0; i < n; i++) {
    const v = values[i][0];
    if (v === '' || v instanceof Date) continue;
    const iso = parseDate_(String(v));
    if (iso) { values[i][0] = isoToDate_(iso); changed = true; }
  }
  if (changed) range.setValues(values);
}

/** Điền ID cho dòng có dữ liệu mà chưa có ID; sinh lại ID bị trùng (dòng copy-paste). */
function damBaoId_(sheet) {
  const n = sheet.getLastRow() - 1;
  if (n < 1) return;
  const c = cols_(sheet);
  const data = sheet.getRange(2, 1, n, c.max).getValues();
  const seen = {};
  const ids = data.map(function (r) { return [String(r[c.ID - 1] || '').trim()]; });
  let changed = false;
  for (let i = 0; i < n; i++) {
    const hasData = String(data[i][c.BARCODE - 1]).trim() !== '' || String(data[i][c.NAME - 1]).trim() !== '';
    if (!hasData) continue;
    if (ids[i][0] === '' || seen[ids[i][0]]) {
      ids[i][0] = newId_(seen);
      changed = true;
    }
    seen[ids[i][0]] = true;
  }
  if (changed) sheet.getRange(2, c.ID, n, 1).setValues(ids);
}

function newId_(seen) {
  for (;;) {
    const id = Utilities.getUuid().replace(/-/g, '').slice(0, 8);
    if (!seen[id]) return id;
  }
}

// ---------------------------------------------------------------- Đọc

function getSheet_() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
  if (!sheet) throw new Error('Chưa có sheet ' + SHEET_NAME + ' — hãy chạy caiDat()');
  return sheet;
}

function readRows_() {
  const sheet = getSheet_();
  const c = cols_(sheet);
  const n = sheet.getLastRow() - 1;
  if (n < 1) return [];
  const values = sheet.getRange(2, 1, n, c.max).getValues();
  const tz = SpreadsheetApp.getActiveSpreadsheet().getSpreadsheetTimeZone();
  const rows = [];
  for (let i = 0; i < n; i++) {
    const v = values[i];
    const barcode = String(v[c.BARCODE - 1]).trim();
    const name = String(v[c.NAME - 1]).trim();
    if (!barcode && !name) continue;
    rows.push({
      r: i + 2,
      barcode: barcode,
      name: name,
      hsd: cellToIso_(v[c.HSD - 1], tz),
      qty: Number(v[c.QTY - 1]) || 0,
      price: Number(v[c.PRICE - 1]) || 0,
      id: String(v[c.ID - 1]).trim(),
    });
  }
  return rows;
}

function lotOf_(row) {
  return { id: row.id, hsd: row.hsd, qty: row.qty };
}

function byHsd_(a, b) {
  return (a.hsd || '9999').localeCompare(b.hsd || '9999');
}

/** Tên và giá của sản phẩm: lấy giá trị không rỗng đầu tiên. */
function productOf_(rows) {
  let name = '', price = 0;
  rows.forEach(function (r) {
    if (!name && r.name) name = r.name;
    if (!price && r.price) price = r.price;
  });
  return { barcode: rows[0].barcode, name: name, price: price };
}

function lookup_(barcode) {
  barcode = normBarcode_(barcode);
  if (!barcode) throw new Error('Thiếu mã vạch');
  const rows = readRows_().filter(function (r) { return normBarcode_(r.barcode) === barcode; });
  if (rows.length === 0) return { ok: true, found: false };
  return { ok: true, found: true, product: productOf_(rows), lots: rows.slice().sort(byHsd_).map(lotOf_) };
}

function snapshot_() {
  const rows = readRows_().map(function (r) { return [r.id, r.barcode, r.name, r.hsd, r.qty, r.price]; });
  return { ok: true, serverTime: new Date().toISOString(), rows: rows };
}

// ---------------------------------------------------------------- Ghi

/**
 * Ghi một sản phẩm với một hoặc nhiều date:
 *   {barcode?, name, price, lots: [{hsd, qty}], confirmMerge}
 * Date đã có → chưa xác nhận thì trả 'duplicate' cho date đó (không ghi), xác nhận thì cộng dồn.
 * Tên/giá khác bản đang lưu → cập nhật cho mọi date của sản phẩm (giá bán theo sản phẩm).
 */
function add_(b) {
  const barcode = String(b.barcode || '').trim();
  const name = String(b.name || '').trim();
  const price = toPrice_(b.price);
  if (!name) throw new Error('Thiếu tên sản phẩm');
  const lots = (b.lots || []).map(function (l) {
    const hsd = parseDate_(String(l.hsd || ''));
    if (!hsd) throw new Error('Date không hợp lệ: ' + l.hsd);
    return { hsd: hsd, qty: toQty_(l.qty, false) };
  });
  if (lots.length === 0) throw new Error('Chưa có date nào');

  const sheet = getSheet_();
  const c = cols_(sheet);
  const rows = readRows_();
  const key = productKey_(barcode, name);
  const same = rows.filter(function (r) { return productKey_(r.barcode, r.name) === key; });

  // Tên / giá theo sản phẩm: cập nhật mọi dòng cũ nếu khác.
  same.forEach(function (r) {
    if (r.name !== name || r.price !== price) {
      sheet.getRange(r.r, c.NAME).setValue(name);
      sheet.getRange(r.r, c.PRICE).setValue(price);
    }
  });

  const seen = {};
  rows.forEach(function (r) { seen[r.id] = true; });
  const results = [];
  let next = sheet.getLastRow() + 1;
  lots.forEach(function (l) {
    const dup = same.filter(function (r) { return r.hsd === l.hsd; })[0];
    if (dup) {
      if (!b.confirmMerge) {
        results.push({ hsd: l.hsd, status: 'duplicate', currentQty: dup.qty, id: dup.id });
        return;
      }
      dup.qty += l.qty;
      sheet.getRange(dup.r, c.QTY).setValue(dup.qty);
      results.push({ hsd: l.hsd, status: 'merged', newQty: dup.qty, id: dup.id });
      return;
    }
    const id = newId_(seen);
    seen[id] = true;
    // Ghi từng ô vào đúng cột của nó — không đụng tới cột tự thêm (kể cả cột có công thức).
    sheet.getRange(next, c.BARCODE).setNumberFormat('@').setValue(barcode);
    sheet.getRange(next, c.NAME).setValue(name);
    sheet.getRange(next, c.HSD).setValue(isoToDate_(l.hsd));
    sheet.getRange(next, c.QTY).setValue(l.qty);
    sheet.getRange(next, c.PRICE).setValue(price);
    sheet.getRange(next, c.ID).setNumberFormat('@').setValue(id);
    same.push({ r: next, barcode: barcode, name: name, hsd: l.hsd, qty: l.qty, price: price, id: id });
    next++;
    results.push({ hsd: l.hsd, status: 'created', id: id, newQty: l.qty });
  });
  return { ok: true, results: results };
}

/** Tìm dòng theo ID và kiểm tra giá trị app đã thấy. Trả {row, rows} hoặc {response} (conflict/notFound). */
function findChecked_(b) {
  const id = String(b.id || '').trim();
  if (!id) throw new Error('Thiếu id');
  if (!b.expect) throw new Error('Thiếu expect');
  const rows = readRows_();
  const row = rows.filter(function (r) { return r.id === id; })[0];
  if (!row) return { response: { ok: true, status: 'notFound' } };
  const e = b.expect;
  const same = String(e.barcode || '').trim() === row.barcode && String(e.hsd || '') === row.hsd && Number(e.qty) === row.qty;
  if (!same) return { response: { ok: true, status: 'conflict', current: { id: row.id, hsd: row.hsd, qty: row.qty } } };
  return { row: row, rows: rows };
}

function adjust_(b) {
  const f = findChecked_(b);
  if (f.response) return f.response;
  const delta = Number(b.delta);
  if (!isFinite(delta) || Math.floor(delta) !== delta) throw new Error('delta không hợp lệ');
  const newQty = f.row.qty + delta;
  if (newQty < 0) throw new Error('Số lượng không được âm');
  const sheet = getSheet_();
  sheet.getRange(f.row.r, cols_(sheet).QTY).setValue(newQty);
  return { ok: true, status: 'updated', newQty: newQty };
}

function updateLot_(b) {
  const f = findChecked_(b);
  if (f.response) return f.response;
  const row = f.row;
  const sheet = getSheet_();
  const c = cols_(sheet);
  const hsd = b.hsd != null && b.hsd !== '' ? parseDate_(String(b.hsd)) : row.hsd;
  if (!hsd) throw new Error('Date không hợp lệ');
  const qty = b.qty != null && b.qty !== '' ? toQty_(b.qty, true) : row.qty;

  if (hsd !== row.hsd) {
    const key = productKey_(row.barcode, row.name);
    const other = f.rows.filter(function (r) {
      return r.id !== row.id && r.hsd === hsd && productKey_(r.barcode, r.name) === key;
    })[0];
    if (other) {
      if (!b.confirmMerge) return { ok: true, status: 'duplicate', currentQty: other.qty, id: other.id, hsd: other.hsd };
      const newQty = other.qty + qty;
      sheet.getRange(other.r, c.QTY).setValue(newQty);
      sheet.deleteRow(row.r);
      return { ok: true, status: 'merged', newQty: newQty, id: other.id };
    }
  }
  sheet.getRange(row.r, c.HSD).setValue(isoToDate_(hsd));
  sheet.getRange(row.r, c.QTY).setValue(qty);
  return { ok: true, status: 'updated', newQty: qty };
}

function deleteLot_(b) {
  const f = findChecked_(b);
  if (f.response) return f.response;
  getSheet_().deleteRow(f.row.r);
  return { ok: true, status: 'deleted' };
}

/** Sửa tên / giá cho mọi date của sản phẩm (có mã vạch: theo mã; không có: theo tên cũ). */
function updateProduct_(b) {
  const barcode = normBarcode_(b.barcode);
  const name = String(b.name || '').trim();
  if (!name) throw new Error('Thiếu tên sản phẩm');
  const price = toPrice_(b.price);
  const match = barcode
    ? function (r) { return normBarcode_(r.barcode) === barcode; }
    : function (r) { return !r.barcode && norm_(r.name) === norm_(b.oldName); };
  const rows = readRows_().filter(match);
  if (rows.length === 0) return { ok: true, status: 'notFound' };
  const sheet = getSheet_();
  const c = cols_(sheet);
  rows.forEach(function (r) {
    sheet.getRange(r.r, c.NAME).setValue(name);
    sheet.getRange(r.r, c.PRICE).setValue(price);
  });
  return { ok: true, status: 'updated', rowsChanged: rows.length };
}

// ---------------------------------------------------------------- Tiện ích

/** So sánh không phân biệt hoa thường, bỏ khoảng trắng thừa. */
function norm_(s) {
  return String(s == null ? '' : s).trim().replace(/\s+/g, ' ').toLowerCase();
}

/** Mã vạch: bỏ khoảng trắng; UPC-A 12 số = EAN-13 có số 0 đầu. */
function normBarcode_(s) {
  const b = String(s == null ? '' : s).replace(/\s+/g, '');
  return /^\d{12}$/.test(b) ? '0' + b : b;
}

/** Khoá sản phẩm: mã vạch nếu có, không thì tên. */
function productKey_(barcode, name) {
  const b = normBarcode_(barcode);
  return b ? 'b:' + b : 'n:' + norm_(name);
}

function toQty_(v, allowZero) {
  const n = Number(v);
  if (!isFinite(n) || Math.floor(n) !== n || n < 0 || (n === 0 && !allowZero)) throw new Error('Số lượng không hợp lệ');
  return n;
}

function toPrice_(v) {
  if (v == null || v === '') return 0;
  const n = Number(String(v).replace(/[^\d]/g, ''));
  if (!isFinite(n) || n < 0) throw new Error('Giá bán không hợp lệ');
  return n;
}

function pad2_(n) { return (n < 10 ? '0' : '') + n; }

function lastDay_(y, m) { return new Date(y, m, 0).getDate(); }

/** 'yyyy-MM-dd' | 'dd/MM/yyyy' | 'dd.MM.yyyy' | 'dd-MM-yyyy' | 'MM/yyyy' (→ ngày cuối tháng) → 'yyyy-MM-dd' hoặc null. */
function parseDate_(s) {
  s = String(s || '').trim();
  let m, y, mo, d;
  if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/))) {
    y = +m[1]; mo = +m[2]; d = +m[3];
  } else if ((m = s.match(/^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2}|\d{4})$/))) {
    d = +m[1]; mo = +m[2]; y = +m[3]; if (y < 100) y += 2000;
  } else if ((m = s.match(/^(\d{1,2})[\/.\-](\d{4})$/))) {
    mo = +m[1]; y = +m[2]; d = lastDay_(y, mo);
  } else {
    return null;
  }
  if (mo < 1 || mo > 12 || d < 1 || d > lastDay_(y, mo)) return null;
  return y + '-' + pad2_(mo) + '-' + pad2_(d);
}

/** Ngày lúc 12:00 trưa để không bị lệch ngày dù múi giờ script và sheet khác nhau. */
function isoToDate_(iso) {
  const p = iso.split('-');
  return new Date(+p[0], +p[1] - 1, +p[2], 12, 0, 0);
}

function cellToIso_(v, tz) {
  if (v instanceof Date) return Utilities.formatDate(v, tz, 'yyyy-MM-dd');
  return parseDate_(String(v)) || '';
}
