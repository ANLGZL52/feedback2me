#!/usr/bin/env node
// ---------------------------------------------------------------------------
// error-watch — CANLI hata takibi (Cloud Functions).
//
// "Herhangi bir hata var mı, yok mu?" sorusuna SOMUT cevap verir: dağıtılmış
// Cloud Functions loglarını (firebase functions:log) çekip son zaman
// penceresindeki HATALARI/uyarıları tespit eder, kategorize eder ve raporlar.
// Önlem alabilmek için: çıkış kodu (hata varsa 1) + ops-status/error-watch.json.
//
// Kullanım:
//   node monitor/error-watch.mjs               # son 24 saat
//   ERROR_WATCH_HOURS=6 node monitor/error-watch.mjs
//   ERROR_WATCH_JSON=1 node monitor/error-watch.mjs   # sadece JSON çıktı
//
// NOT: firebase CLI + geçerli oturum gerekir (functions:log erişimi). Erişim
// yoksa "collector UNAVAILABLE" raporlar, çökme YAPMAZ. PII güvenli: yalnızca
// severity + eventType + errorCode + fonksiyon adı + sayım tutulur; ham
// receipt/token/uid gibi alanlar RAPORLANMAZ.
// ---------------------------------------------------------------------------
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');
const OUT_DIR = join(REPO, 'ops-status');
const OUT = join(OUT_DIR, 'error-watch.json');

const HOURS = Number(process.env.ERROR_WATCH_HOURS || 24);
const JSON_ONLY = process.env.ERROR_WATCH_JSON === '1';
const NOW = Date.now();
const WINDOW_MS = HOURS * 3600 * 1000;

// Bir log satırından HATA sınıfı çıkar (yoksa null = hata değil).
// severity harfleri: D=debug I=info W=warning E=error N=notice(audit).
function classify(sev, fn, msg) {
  // 1) Yapısal observability event'i (buildIapObsEvent / buildObsEvent JSON'u)
  if (msg.startsWith('{')) {
    let ev;
    try { ev = JSON.parse(msg); } catch { ev = null; }
    if (ev && typeof ev.eventType === 'string') {
      const et = ev.eventType;
      const rc = ev.resultClass;
      const code = ev.errorCode || null;
      // Kalıcı ret / hata / (config kaynaklı) geçici hata → izlenmeli.
      if (/\.error$/.test(et) || /\.rejected$/.test(et)) {
        return { kind: 'iap-reject', severity: 'ERROR', service: ev.service || fn, event: et, code };
      }
      if (/\.transient_failure$/.test(et) || rc === 'transient') {
        return { kind: 'iap-transient', severity: 'WARNING', service: ev.service || fn, event: et, code };
      }
      if (et.endsWith('.error') || rc === 'error') {
        return { kind: 'runtime-error', severity: 'ERROR', service: ev.service || fn, event: et, code };
      }
      return null; // başarı/started/replay vb. → hata değil
    }
  }
  // 2) Ham hata satırları (severity E veya bilinen hata kalıpları)
  if (sev === 'E') {
    // Firebase'in kendi logger içi hataları / gerçek runtime hataları
    const code = (msg.match(/\b(play_http_\d+|apple_status_\d+|[A-Z][A-Z0-9_]{3,})\b/) || [])[1] || null;
    return { kind: 'function-error', severity: 'ERROR', service: fn, event: 'log.error', code, sample: msg.slice(0, 120) };
  }
  if (sev === 'W' && /(unhandled|exception|timeout|crash|failed to|denied)/i.test(msg) && !msg.startsWith('{')) {
    return { kind: 'function-warning', severity: 'WARNING', service: fn, event: 'log.warning', code: null, sample: msg.slice(0, 120) };
  }
  return null;
}

function fetchLogs() {
  // firebase functions:log — dağıtılmış tüm fonksiyonların son logları.
  const out = execFileSync('firebase', ['functions:log'], {
    cwd: REPO, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'],
    shell: process.platform === 'win32',
  });
  return out.split(/\r?\n/);
}

function parseLine(line) {
  // "2026-08-24T09:00:00.000000Z W iapverify: {json...}" / "... E fn: Error: ..."
  const m = line.match(/^(\S+)\s+([DIWEN])\s+([A-Za-z0-9_-]+):\s?(.*)$/);
  if (!m) return null;
  const ts = Date.parse(m[1]);
  return { ts: Number.isNaN(ts) ? null : ts, sev: m[2], fn: m[3], msg: (m[4] || '').trim() };
}

function main() {
  let lines, collectorOk = true, collectorError = null;
  try { lines = fetchLogs(); }
  catch (e) { collectorOk = false; collectorError = (e.message || String(e)).slice(0, 160); lines = []; }

  const buckets = new Map(); // key -> {kind,severity,service,event,code,count,firstTs,lastTs,sample}
  let scanned = 0, inWindow = 0;
  for (const line of lines) {
    const p = parseLine(line);
    if (!p) continue;
    scanned++;
    if (p.ts != null && NOW - p.ts > WINDOW_MS) continue; // pencere dışı
    inWindow++;
    const c = classify(p.sev, p.fn, p.msg);
    if (!c) continue;
    const key = `${c.service}|${c.event}|${c.code || ''}`;
    const b = buckets.get(key) || { ...c, count: 0, firstTs: p.ts, lastTs: p.ts };
    b.count++;
    if (p.ts != null) { b.firstTs = Math.min(b.firstTs ?? p.ts, p.ts); b.lastTs = Math.max(b.lastTs ?? p.ts, p.ts); }
    if (c.sample && !b.sample) b.sample = c.sample;
    buckets.set(key, b);
  }

  const errors = [...buckets.values()].sort((a, b) => (b.severity === 'ERROR') - (a.severity === 'ERROR') || b.count - a.count);
  const errorCount = errors.filter(e => e.severity === 'ERROR').reduce((s, e) => s + e.count, 0);
  const warnCount = errors.filter(e => e.severity === 'WARNING').reduce((s, e) => s + e.count, 0);

  const status = !collectorOk ? 'UNAVAILABLE' : errorCount > 0 ? 'ERRORS' : warnCount > 0 ? 'WARNINGS' : 'HEALTHY';
  const report = {
    generatedAt: new Date(NOW).toISOString(),
    windowHours: HOURS,
    status,
    collector: { ok: collectorOk, error: collectorError, linesScanned: scanned, entriesInWindow: inWindow },
    counts: { errors: errorCount, warnings: warnCount, distinct: errors.length },
    items: errors.map(e => ({
      severity: e.severity, service: e.service, event: e.event, code: e.code || null,
      count: e.count, lastSeen: e.lastTs ? new Date(e.lastTs).toISOString() : null, sample: e.sample || null,
    })),
  };

  try { mkdirSync(OUT_DIR, { recursive: true }); writeFileSync(OUT, JSON.stringify(report, null, 2)); } catch { /* yoksay */ }

  if (JSON_ONLY) { console.log(JSON.stringify(report, null, 2)); }
  else { printHuman(report); }

  // Önlem için: hata varsa 1, uyarı varsa 0 (kırmızı değil), collector yoksa 2.
  process.exit(status === 'ERRORS' ? 1 : status === 'UNAVAILABLE' ? 2 : 0);
}

function printHuman(r) {
  const line = '─'.repeat(64);
  console.log(line);
  if (r.status === 'UNAVAILABLE') {
    console.log(`[error-watch] COLLECTOR ERİŞİLEMEDİ — ${r.collector.error}`);
    console.log('  (firebase CLI oturumu/erişimi gerekiyor: `firebase login`)');
    console.log(line);
    return;
  }
  const icon = r.status === 'HEALTHY' ? '✅' : r.status === 'WARNINGS' ? '⚠️ ' : '🔴';
  console.log(`[error-watch] ${icon} ${r.status}  · son ${r.windowHours} saat · ${r.collector.entriesInWindow} kayıt tarandı`);
  console.log(`  hatalar: ${r.counts.errors}  |  uyarılar: ${r.counts.warnings}  |  farklı: ${r.counts.distinct}`);
  if (r.items.length === 0) {
    console.log('  Bu pencerede hata/uyarı YOK.');
  } else {
    console.log('  ' + '-'.repeat(60));
    for (const it of r.items) {
      const sv = it.severity === 'ERROR' ? '🔴' : '⚠️ ';
      console.log(`  ${sv} ${it.service} · ${it.event}${it.code ? ' [' + it.code + ']' : ''} ×${it.count}  (son: ${it.lastSeen || '—'})`);
      if (it.sample) console.log(`       ↳ ${it.sample}`);
    }
  }
  console.log(`  durum dosyası: ops-status/error-watch.json`);
  console.log(line);
}

main();
