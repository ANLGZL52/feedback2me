// Feedback2Me — system topology NODES (single source of truth; imported by both the
// read-only server and the browser). PURE DATA — no imports, no secrets. Every node is
// grounded in the real repository; do not invent components.
//
// statusSource tells the model how to derive the live status from ops-status artifacts:
//   { kind:'domain', key:'POSTGRES' }   -> runtime-health.json domains[key].status
//   { kind:'field', key:'currentRuntimeHealth' } -> top-level health field
//   { kind:'const', value:'LIVE' }      -> fixed (structural fact)
//   { kind:'gate' }                     -> productReleaseGate.status
//   { kind:'incident' }                 -> incident delivery mode/health
//   { kind:'digest' }                   -> digest delivery health/channel
//   { kind:'deferred' }                 -> DEFERRED (validationEvidence.realIapE2E)
//   { kind:'na' }                       -> N/A (client-side / not directly observed)
// metric (optional) tells the model which single key metric to surface.

export const CATEGORIES = [
  'APPLICATION', 'DATA', 'EXTERNAL_PROVIDER', 'BACKEND',
  'OBSERVABILITY', 'SECURITY', 'INCIDENT', 'DELIVERY', 'VALIDATION',
];

export const NODES = [
  // ---- application + product data ----
  { id: 'flutter_app', label: 'Flutter App', category: 'APPLICATION', role: 'Mobile client',
    description: 'The Feedback2Me Flutter application. Authenticates users, reads/writes content & feedback in Firestore, and initiates in-app purchases via StoreKit.',
    x: 600, y: 40, statusSource: { kind: 'na' },
    sources: ['lib/'], alertCodes: [], runbook: [] },

  { id: 'firebase_auth', label: 'Firebase Auth', category: 'SECURITY', role: 'Identity provider',
    description: 'Firebase Authentication (Email / Google / Apple). Establishes the signed-in user identity used by Firestore rules and callable functions.',
    x: 360, y: 150, statusSource: { kind: 'na' },
    sources: ['lib/', 'functions/src/index.ts'], alertCodes: [], runbook: [] },

  { id: 'firestore', label: 'Firestore', category: 'DATA', role: 'App database',
    description: 'Cloud Firestore holds users, contents, feedbacks, reactions, ratings, notifications, and the IAP ledger collections (processedPurchases, paidLinkCredits).',
    x: 840, y: 150, statusSource: { kind: 'na' },
    sources: ['firestore.rules', 'functions/src/iap-core.ts'], alertCodes: [], runbook: [] },

  // ---- IAP money path (left column) ----
  { id: 'app_store', label: 'App Store / StoreKit', category: 'EXTERNAL_PROVIDER', role: 'Store transaction',
    description: 'Apple StoreKit / App Store. Processes the purchase and returns a signed store transaction for the consumable link product.',
    x: 300, y: 250, statusSource: { kind: 'na' },
    sources: ['lib/'], alertCodes: [], runbook: [] },

  { id: 'premium_product', label: 'premium_link_single_v2', category: 'DATA', role: 'IAP product id',
    description: 'The allow-listed consumable product id (with legacy premium_link_single). Any other product id crediting is a money-safety violation.',
    x: 300, y: 350, statusSource: { kind: 'domain', key: 'IAP' },
    sources: ['functions/src/iap-core.ts'], alertCodes: ['IAP_CREDIT_UNKNOWN_PRODUCT', 'IAP_INVALID_PRODUCT_CREDITED'], runbook: ['IAP_CREDIT_INVARIANT_BREACH'] },

  { id: 'iap_verify', label: 'iapVerify', category: 'BACKEND', role: 'Purchase verifier (callable)',
    description: 'Firebase callable that verifies a store transaction with Apple, deduplicates it, and grants exactly one credit. Fails CLOSED — no verification, no credit. Emits PII-safe iap.* observability events.',
    x: 300, y: 460, statusSource: { kind: 'domain', key: 'IAP' },
    metric: { kind: 'domainLatencyP95', key: 'IAP', label: 'verify p95', unit: 'ms' },
    sources: ['functions/src/iap-core.ts', 'functions/src/index.ts'],
    alertCodes: ['IAP_VERIFY_DOWN', 'IAP_LATENCY_DEGRADED', 'IAP_SUCCESS_WITHOUT_CREDIT', 'IAP_CREDIT_AFTER_FAILURE'],
    runbook: ['IAP_VERIFY_DOWN', 'IAP_CREDIT_INVARIANT_BREACH'] },

  { id: 'apple_verification', label: 'Apple Verification', category: 'EXTERNAL_PROVIDER', role: 'Server-side receipt check',
    description: 'Apple\'s server-to-server transaction/receipt verification. A spike of verification failures raises APPLE_VERIFICATION_FAILURE_SPIKE.',
    x: 90, y: 460, statusSource: { kind: 'domain', key: 'IAP' },
    sources: ['functions/src/iap-core.ts'],
    alertCodes: ['APPLE_VERIFICATION_FAILURE_SPIKE', 'IAP_VERIFY_FAILURE_ELEVATED'], runbook: ['APPLE_VERIFICATION_FAILURE_SPIKE'] },

  { id: 'processed_purchases', label: 'processedPurchases', category: 'DATA', role: 'Dedup ledger',
    description: 'Firestore collection recording each processed store transaction id — the replay/duplicate guard. A second grant for the same transaction is a money-safety violation.',
    x: 120, y: 590, statusSource: { kind: 'domain', key: 'IAP' },
    sources: ['functions/src/iap-core.ts'],
    alertCodes: ['IAP_DUPLICATE_GRANT', 'IAP_REPLAY_DELTA_NOT_ZERO'], runbook: ['IAP_CREDIT_INVARIANT_BREACH'] },

  { id: 'paid_link_credits', label: 'paidLinkCredits', category: 'DATA', role: 'Entitlement ledger',
    description: 'Firestore collection holding the user\'s granted link credits. Each verified purchase grants exactly one (delta must equal 1).',
    x: 320, y: 590, statusSource: { kind: 'domain', key: 'IAP' },
    sources: ['functions/src/iap-core.ts'],
    alertCodes: ['IAP_GRANT_DELTA_NOT_ONE', 'IAP_SUCCESS_WITHOUT_CREDIT'], runbook: ['IAP_CREDIT_INVARIANT_BREACH'] },

  { id: 'ai_summary', label: 'aiSummary', category: 'BACKEND', role: 'Server-side OpenAI proxy',
    description: 'Firebase callable that summarizes real community feedback server-side (keeps the OpenAI key off the client). Built; deploy pending. Its runtime telemetry appears under the OpenAI domain.',
    x: 520, y: 560, statusSource: { kind: 'na' },
    sources: ['functions/src/ai-core.ts', 'functions/src/index.ts'], alertCodes: [], runbook: [] },

  // ---- runtime sources (middle band) ----
  { id: 'openai', label: 'OpenAI', category: 'EXTERNAL_PROVIDER', role: 'LLM provider',
    description: 'OpenAI (gpt-4o-mini) used for community-feedback summaries. Observed for failure rate, latency, and token spikes via Functions logs.',
    x: 540, y: 690, statusSource: { kind: 'domain', key: 'OPENAI' },
    metric: { kind: 'domainField', key: 'OPENAI', field: 'p95', label: 'p95', unit: 'ms' },
    sources: ['ops/monitor/evaluate-runtime.mjs', 'ops/monitor/checks/gcp-functions-logs.mjs'],
    alertCodes: ['OPENAI_DEGRADED', 'OPENAI_LATENCY_DEGRADED', 'OPENAI_TOKEN_SPIKE'], runbook: ['OPENAI_PROVIDER_FAILURE'] },

  { id: 'railway', label: 'Railway', category: 'EXTERNAL_PROVIDER', role: 'Backend host',
    description: 'Railway hosts the link backend. Observed read-only for HTTP 5xx and reachability via the Railway API (OPS_RAILWAY_TOKEN).',
    x: 720, y: 690, statusSource: { kind: 'domain', key: 'RAILWAY' },
    metric: { kind: 'domainField', key: 'RAILWAY', field: '5xx', label: '5xx', unit: '' },
    sources: ['ops/monitor/checks/railway-http-logs.mjs', 'ops/monitor/checks/railway-runtime-logs.mjs'],
    alertCodes: ['RAILWAY_5XX_ELEVATED', 'RAILWAY_UNREACHABLE'], runbook: ['RAILWAY_UNAVAILABLE'] },

  { id: 'postgres', label: 'Postgres', category: 'BACKEND', role: 'Operational DB',
    description: 'Operational Postgres, probed read-only via a dedicated ops credential (OPS_POSTGRES_DATABASE_URL). Consecutive failures escalate to CRITICAL and block release.',
    x: 900, y: 690, statusSource: { kind: 'domain', key: 'POSTGRES' },
    metric: { kind: 'domainField', key: 'POSTGRES', field: 'latencyMs', label: 'Latency', unit: 'ms' },
    sources: ['ops/monitor/checks/postgres-direct.mjs'],
    alertCodes: ['POSTGRES_CRITICAL', 'POSTGRES_WARNING'], runbook: ['POSTGRES_UNAVAILABLE'] },

  { id: 'wif', label: 'GCP WIF', category: 'SECURITY', role: 'Keyless auth',
    description: 'Workload Identity Federation: short-lived OIDC access token (logging.read, 300s) that lets the collector read Cloud Logging. No static service-account key.',
    x: 1080, y: 690, statusSource: { kind: 'domain', key: 'SECURITY' },
    sources: ['.github/workflows/ops-health.yml'],
    alertCodes: ['COLLECTOR_RUN_FAILED'], runbook: ['GCP_WIF_AUTH_FAILED'] },

  // ---- observability pipeline (center) ----
  { id: 'collector', label: 'Collector', category: 'OBSERVABILITY', role: 'Read-only telemetry collector',
    description: 'Collects runtime logs from Railway + GCP Cloud Logging (read-only). Missing creds → NOT_CONFIGURED (never an outage). Staleness beyond the SLO window is itself a CRITICAL incident.',
    x: 600, y: 830, statusSource: { kind: 'domain', key: 'COLLECTOR' },
    metric: { kind: 'collectorFreshness', label: 'Freshness', unit: 'min' },
    sources: ['ops/monitor/collect-runtime.mjs'],
    alertCodes: ['COLLECTOR_STALE', 'COLLECTOR_RUN_FAILED'], runbook: ['COLLECTOR_STALE', 'GCP_WIF_AUTH_FAILED'] },

  { id: 'evaluator', label: 'Evaluator', category: 'OBSERVABILITY', role: 'Metrics → SLO → alerts → gate',
    description: 'Pure evaluator: turns collected metrics into per-domain health, SLO verdicts, CRITICAL/WARNING alerts, trends, and the release gate. Distinguishes NO_TRAFFIC (IDLE) from NO_OBSERVABILITY (UNKNOWN).',
    x: 600, y: 950, statusSource: { kind: 'field', key: 'observabilityPlatformStatus' },
    sources: ['ops/monitor/evaluate-runtime.mjs', 'ops/monitor/iap-invariants.mjs'],
    alertCodes: [], runbook: [] },

  { id: 'service_domain', label: 'Service (components)', category: 'BACKEND', role: 'Live component health',
    description: 'Composite live-component health (from latest.json). A component reporting DOWN raises SERVICE_COMPONENT_DOWN (release-blocking) via the incident pipeline.',
    x: 320, y: 950, statusSource: { kind: 'domain', key: 'SERVICE' },
    sources: ['ops/monitor/evaluate-runtime.mjs', 'ops/monitor/run.mjs'],
    alertCodes: ['SERVICE_COMPONENT_DOWN'], runbook: ['SERVICE_COMPONENT_DOWN'] },

  { id: 'security_domain', label: 'Security (payload safety)', category: 'SECURITY', role: 'Secret/PII guard',
    description: 'Payload validator that blocks any secret/PII (email, JWT, bearer, private key, webhook) before an Issue or a Slack digest is sent, and the secret/PII leak detector.',
    x: 900, y: 950, statusSource: { kind: 'domain', key: 'SECURITY' },
    sources: ['ops/monitor/incident-actions.mjs'],
    alertCodes: ['SECRET_OR_PII_LEAK', 'INCIDENT_DELIVERY_PAYLOAD_REJECTED', 'SLACK_DIGEST_PAYLOAD_REJECTED'],
    runbook: ['SECRET_OR_PII_LEAK_DETECTED'] },

  { id: 'runtime_health', label: 'Runtime Health / SLO', category: 'OBSERVABILITY', role: 'Health snapshot',
    description: 'The evaluated runtime-health snapshot: per-domain status, SLO verdicts, and the inputs to the release gate.',
    x: 600, y: 1070, statusSource: { kind: 'field', key: 'currentRuntimeHealth' },
    sources: ['ops/monitor/evaluate-runtime.mjs'], alertCodes: [], runbook: [] },

  // ---- release chain ----
  { id: 'release_gate', label: 'Product Release Gate', category: 'VALIDATION', role: 'Release readiness',
    description: 'Derives PASS / WARN / BLOCK from runtime health, money-safety, and deferred validations. Observability health ≠ product release readiness.',
    x: 600, y: 1190, statusSource: { kind: 'gate' },
    sources: ['ops/monitor/evaluate-runtime.mjs', 'ops/monitor/preflight.mjs'], alertCodes: [], runbook: [] },

  { id: 'real_iap_e2e', label: 'Real IAP TestFlight E2E', category: 'VALIDATION', role: 'Deferred product validation',
    description: 'A real on-device TestFlight purchase → credit end-to-end proof. DEFERRED until a physical device is available; keeps Runtime Validation PARTIAL and the gate at WARN. Not an observability blocker.',
    x: 880, y: 1190, statusSource: { kind: 'deferred' },
    sources: ['ops/RUNBOOK.md'], alertCodes: [], runbook: ['IAP_E2E_VALIDATION_DEFERRED'] },

  // ---- incident chain ----
  { id: 'incident_engine', label: 'Incident Engine', category: 'INCIDENT', role: 'Incident decision engine',
    description: 'Pure decision engine: NEW/UPDATE/RESOLVE/REOPEN with dedup, cooldown, renotify, flapping, material-change, and schema-versioned state trust. Transport-agnostic.',
    x: 420, y: 1310, statusSource: { kind: 'incident' },
    metric: { kind: 'activeIncidents', label: 'Active', unit: '' },
    sources: ['ops/monitor/incident-actions.mjs'],
    alertCodes: ['INCIDENT_STATE_LOST'], runbook: ['INCIDENT_STATE_LOST'] },

  { id: 'github_issues', label: 'GitHub Issue Delivery', category: 'DELIVERY', role: 'Canonical incident channel',
    description: 'The ONE canonical operational Issue writer. Delivers CRITICAL incidents as GitHub Issues with dedup (local state + open-issue title lookup). Legacy alert writer is OFF.',
    x: 420, y: 1430, statusSource: { kind: 'incident' },
    sources: ['ops/monitor/incident-delivery.mjs'],
    alertCodes: ['INCIDENT_DELIVERY_UNAVAILABLE', 'GITHUB_ISSUE_LOOKUP_FAILED'],
    runbook: ['INCIDENT_DELIVERY_UNAVAILABLE', 'GITHUB_ISSUE_LOOKUP_FAILED'] },

  // ---- digest chain ----
  { id: 'ops_console', label: 'Ops Console', category: 'OBSERVABILITY', role: 'Private console + run summary',
    description: 'Renders the private ops console and the GitHub Actions step summary (metadata only, no PII).',
    x: 820, y: 1310, statusSource: { kind: 'const', value: 'LIVE' },
    sources: ['ops/monitor/ops-console.mjs'], alertCodes: [], runbook: [] },

  { id: 'trend', label: 'Trend', category: 'OBSERVABILITY', role: '24h trend engine',
    description: 'Computes IMPROVING / STABLE / DEGRADING / INSUFFICIENT_DATA trends over the rolling window.',
    x: 1040, y: 1310, statusSource: { kind: 'const', value: 'LIVE' },
    sources: ['ops/monitor/evaluate-runtime.mjs'], alertCodes: [], runbook: [] },

  { id: 'daily_digest', label: 'Daily Digest', category: 'DELIVERY', role: 'Once/UTC-day summary',
    description: 'Builds the rolling-24h operational digest and delivers it to Slack at most once per UTC day (deterministic eligibility + artifact-restored dedup). Payload validated before send.',
    x: 820, y: 1430, statusSource: { kind: 'digest' },
    sources: ['ops/monitor/digest.mjs'],
    alertCodes: ['DIGEST_GENERATION_FAILED', 'SLACK_DIGEST_DELIVERY_FAILED', 'SLACK_DIGEST_NOT_CONFIGURED'],
    runbook: ['DIGEST_GENERATION_FAILED', 'SLACK_DIGEST_DELIVERY_FAILED'] },

  { id: 'slack', label: 'Slack', category: 'DELIVERY', role: 'Daily digest transport',
    description: 'Slack Incoming Webhook — the DAILY DIGEST channel only. CRITICAL incidents never cross to Slack. Bounded timeout, ≤1 retry, never logs the webhook.',
    x: 820, y: 1550, statusSource: { kind: 'digestChannel' },
    sources: ['ops/monitor/slack-digest-adapter.mjs'],
    alertCodes: ['SLACK_DIGEST_DELIVERY_FAILED', 'SLACK_DIGEST_RATE_LIMITED', 'SLACK_DIGEST_NOT_CONFIGURED', 'SLACK_DIGEST_PAYLOAD_REJECTED'],
    runbook: ['SLACK_DIGEST_DELIVERY_FAILED', 'SLACK_DIGEST_RATE_LIMITED', 'SLACK_DIGEST_NOT_CONFIGURED', 'SLACK_DIGEST_PAYLOAD_REJECTED'] },
];
