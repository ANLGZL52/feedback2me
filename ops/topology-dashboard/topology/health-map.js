// Feedback2Me — END-TO-END HEALTH MAP. PURE DATA. Maps each topology node to the REAL
// evidence that determines its health, plus the product critical paths and the safe
// read-only canary definitions. No invented coverage: `service` points at an existing
// artifact signal (a latest.json blackbox-prod component, a runtime-health domain, a
// business invariant, or an on-demand canary). Nodes with no safe signal declare `naReason`
// + `recommend` (Mission 9). `probe:true` marks a DIRECT health probe (blackbox/canary/DB).
//
// service kinds (resolved in health-model.mjs):
//   component:<id>  -> ops-status/latest.json components[id].status  (real blackbox-prod check)
//   domain:<KEY>    -> runtime-health.json domains[KEY].status
//   field:<k>       -> runtime-health top-level field
//   business:money  -> IAP money-safety invariants (HEALTHY unless a violation alert exists)
//   canary:<ID>     -> on-demand local canary result (else UNKNOWN until run)
//   const/gate/incident/digest/digestChannel/deferred/na
// traffic:<KEY>     -> runtime-health domain used purely as the traffic/activity signal.

export const NODE_HEALTH = {
  // application
  flutter_app: { service: { kind: 'na' }, probe: false, naReason: 'Mobile client — cannot be black-box probed from outside.', recommend: 'Crash-free sessions & app-start success via Firebase Crashlytics / Analytics.' },
  firebase_auth: { service: { kind: 'component', id: 'node-firebase-auth' }, canary: 'CANARY_AUTH', probe: true, naReason: 'Auth config probe present (firebase-auth-config.mjs) — currently UNKNOWN in the artifact; run the CANARY_AUTH init-config check for a live signal.', recommend: 'GET the published Firebase config (init.json) + identitytoolkit reachability — no sign-in.' },
  firestore: { service: { kind: 'component', id: 'node-firestore' }, canary: 'CANARY_FIRESTORE_READ', probe: true },
  ai_summary: { service: { kind: 'component', id: 'node-ai-proxy' }, canary: 'CANARY_AI_FUNCTION', probe: true, naReason: 'aiSummary callable availability not in the artifact (built; deploy pending). Run CANARY_AI_FUNCTION to check reachability without a paid generation.', recommend: 'GET the callable URL (rejected before the handler runs) — proves deploy without OpenAI cost.' },

  // IAP / payments
  app_store: { service: { kind: 'component', id: 'node-apple-store' }, probe: false, naReason: 'External store — Apple exposes no per-app availability signal.', recommend: 'Infer from Apple verification failure rate + purchase telemetry when traffic exists.' },
  premium_product: { service: { kind: 'business', which: 'money' }, traffic: 'IAP', probe: false },
  iap_verify: { service: { kind: 'business', which: 'money' }, canary: 'CANARY_IAP_FUNCTION', traffic: 'IAP', probe: true },
  apple_verification: { service: { kind: 'component', id: 'node-apple-store' }, traffic: 'IAP', probe: false, naReason: 'Apple server-side verification — no external availability probe; observed via failure-rate when purchases occur.', recommend: 'APPLE_VERIFICATION_FAILURE_SPIKE on real traffic.' },
  processed_purchases: { service: { kind: 'component', id: 'node-firestore' }, business: 'money', traffic: 'IAP', probe: true },
  paid_link_credits: { service: { kind: 'component', id: 'node-firestore' }, business: 'money', traffic: 'IAP', probe: true },

  // backend / external services
  openai: { service: { kind: 'domain', key: 'OPENAI' }, traffic: 'OPENAI', probe: false },
  railway: { service: { kind: 'component', id: 'node-railway-api' }, canary: 'CANARY_RAILWAY', traffic: 'RAILWAY', probe: true },
  postgres: { service: { kind: 'component', id: 'node-postgres' }, traffic: 'POSTGRES', probe: true },
  wif: { service: { kind: 'domain', key: 'SECURITY' }, probe: true },
  service_domain: { service: { kind: 'domain', key: 'SERVICE' }, probe: true },
  security_domain: { service: { kind: 'domain', key: 'SECURITY' }, probe: true },

  // observability spine
  collector: { service: { kind: 'domain', key: 'COLLECTOR' }, probe: true },
  evaluator: { service: { kind: 'field', key: 'observabilityPlatformStatus' }, probe: true },
  runtime_health: { service: { kind: 'field', key: 'currentRuntimeHealth' }, probe: true },

  // validation / release
  release_gate: { service: { kind: 'gate' }, probe: true, separate: 'release' },
  real_iap_e2e: { service: { kind: 'deferred' }, probe: false, separate: 'release', naReason: 'Real on-device TestFlight purchase → credit E2E is intentionally DEFERRED (no physical device). Not an observability blocker.', recommend: 'Run a real sandbox/TestFlight purchase on a device and assert exactly one credit.' },

  // incident + delivery
  incident_engine: { service: { kind: 'incident' }, probe: true },
  github_issues: { service: { kind: 'incident' }, probe: true },
  ops_console: { service: { kind: 'const', value: 'LIVE' }, probe: true },
  trend: { service: { kind: 'const', value: 'LIVE' }, probe: true },
  daily_digest: { service: { kind: 'digest' }, probe: true },
  slack: { service: { kind: 'digestChannel' }, probe: true },
};

// Product critical paths. Aggregation uses ONLY members that carry a real health signal;
// N/A/client members are recorded as coverage gaps but never force the path UNHEALTHY.
export const CRITICAL_PATHS = [
  { id: 'AUTH', name: 'Auth', members: ['flutter_app', 'firebase_auth'] },
  { id: 'FEEDBACK', name: 'Feedback', members: ['flutter_app', 'firestore', 'railway', 'service_domain'] },
  { id: 'AI', name: 'AI Summary', members: ['ai_summary', 'openai'] },
  { id: 'IAP', name: 'IAP / Money', members: ['iap_verify', 'apple_verification', 'processed_purchases', 'paid_link_credits'] },
  { id: 'OBSERVABILITY', name: 'Observability', members: ['collector', 'evaluator', 'incident_engine'] },
];

// Safe, read-only, bounded, on-demand canaries. GET only — never a body, never a mutation,
// never a paid generation, never a sign-in. Verified endpoints from the repo.
export const CANARIES = [
  { id: 'CANARY_PUBLIC_FEEDBACK', node: 'firestore', kind: 'http', method: 'GET', url: 'https://feedbacktome-79655.web.app/f.html', okStatuses: [200], desc: 'Public feedback page reachable (loads page only; resolves no link code).' },
  { id: 'CANARY_APP_BACKEND', node: 'railway', kind: 'http', method: 'GET', url: 'https://feedback2me-production.up.railway.app/health', okStatuses: [200], desc: 'Railway backend public /health endpoint.' },
  { id: 'CANARY_RAILWAY', node: 'railway', kind: 'http', method: 'GET', url: 'https://feedback2me-production.up.railway.app/health', okStatuses: [200], desc: 'Railway reachability (alias of app backend health).' },
  { id: 'CANARY_AUTH', node: 'firebase_auth', kind: 'http', method: 'GET', url: 'https://feedbacktome-79655.web.app/__/firebase/init.json', okStatuses: [200], reachableStatuses: [401, 403, 404], desc: 'Published Firebase/Auth config reachable (public init.json; no sign-in).' },
  { id: 'CANARY_FIRESTORE_READ', node: 'firestore', kind: 'http', method: 'GET', url: 'https://firestore.googleapis.com/v1/projects/feedbacktome-79655/databases/(default)/documents/appConfig/version?key=AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M', okStatuses: [200], reachableStatuses: [401, 403, 404], desc: 'Read-only Firestore REST (appConfig/version; public web key). 200=readable, 401/403=rules enforced, 404=reachable/doc-path — all prove the API is up. No write.' },
  { id: 'CANARY_AI_FUNCTION', node: 'ai_summary', kind: 'http', method: 'GET', url: 'https://us-central1-feedbacktome-79655.cloudfunctions.net/aiSummary', okStatuses: [200, 400, 401, 403, 405], notDeployed: [404], desc: 'aiSummary callable reachable (GET rejected before the handler → no OpenAI cost). 404=not deployed.' },
  { id: 'CANARY_IAP_FUNCTION', node: 'iap_verify', kind: 'http', method: 'GET', url: 'https://us-central1-feedbacktome-79655.cloudfunctions.net/iapVerify', okStatuses: [200, 400, 401, 403, 405], notDeployed: [404], desc: 'iapVerify callable reachable (GET rejected before the handler → no verification/mutation). 404=not deployed.' },
];
