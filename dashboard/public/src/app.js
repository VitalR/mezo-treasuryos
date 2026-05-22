const EXPLORER_TX = "https://explorer.test.mezo.org/tx/";
const EXPLORER_ADDRESS = "https://explorer.test.mezo.org/address/";

const app = document.querySelector("#app");

document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy]");
  if (!button) return;
  await navigator.clipboard?.writeText(button.dataset.copy).catch(() => {});
  button.dataset.copied = "true";
  button.textContent = "COPIED";
  setTimeout(() => {
    button.dataset.copied = "false";
    button.textContent = "COPY";
  }, 1100);
});

main().catch((error) => {
  app.innerHTML = `
    <section class="loading-panel error-panel">
      <p class="eyebrow">Dashboard data unavailable</p>
      <h1>Run <code>make dashboard-data</code></h1>
      <p>${escapeHtml(error.message)}</p>
    </section>
  `;
});

async function main() {
  const response = await fetch("/data/dashboard-data.json", { cache: "no-store" });
  if (!response.ok) throw new Error(`Missing /data/dashboard-data.json (${response.status})`);
  const data = await response.json();
  render(data);
}

function render(data) {
  const health = data.treasury.health;
  const composition = data.treasury.composition;
  const position = data.treasury.position;
  const buckets = data.treasury.btcReserveBuckets;
  const savings = findSleeve(data, "savings");
  const stableLp = findSleeve(data, "musdc|stable");
  const liveKeeper = data.keeper.live;
  const criticalKeeper = data.keeper.critical;
  const cfo = data.advisor.cfoPacket;

  app.innerHTML = `
    ${topStrip(data)}
    <section class="hero-grid">
      <article class="hero-panel">
        <div class="panel-head">
          <div>
            <p class="eyebrow">Treasury health</p>
            <h1>${statusPill(health.state)} ${escapeHtml(data.treasuryName)}</h1>
          </div>
          <span class="read-only">READ ONLY</span>
        </div>
        <div class="metric-grid hero-metrics">
          ${metric("Current CR", bps(health.currentCollateralRatioBps), "Measured against live position")}
          ${metric("Post-stress CR", bps(health.postStressCollateralRatioBps), `Minimum ${bps(health.minPostStressCollateralRatioBps)}`)}
          ${metric("Required buffer", musd(composition.liquidityBufferMUSD), "Operating liquidity floor")}
          ${metric("Idle MUSD", musd(composition.idleMUSD), `${musd(composition.deployableSurplusMUSD)} allocatable surplus`)}
        </div>
        <div class="threshold-row">
          <span>Target ${bps(health.targetCollateralRatioBps)}</span>
          <span>Warning ${bps(health.warningCollateralRatioBps)}</span>
          <span>Critical ${bps(health.criticalCollateralRatioBps)}</span>
          <span>Profile ${escapeHtml(data.treasury.profile.label)}</span>
        </div>
        <div class="flow-row" aria-label="Bank on Bitcoin treasury flow">
          <span>BTC collateral</span>
          <span>MUSD operating capital</span>
          <span>Policy-governed allocation</span>
          <span>Keeper defense</span>
          <span>AI-CFO reporting</span>
        </div>
      </article>
      <article class="action-panel">
        <p class="eyebrow">Operator recommendation</p>
        <h2>${escapeHtml(data.advisor.automationAction.action)}</h2>
        <p>${escapeHtml(data.advisor.automationAction.reason)}</p>
        <div class="divider"></div>
        <p class="eyebrow">AI-CFO recommendation</p>
        <p>${escapeHtml(data.advisor.memo)}</p>
      </article>
    </section>

    <section class="content-grid two-col">
      ${balanceSheet(position, composition, buckets, savings, stableLp)}
      ${controlsPanel(data)}
    </section>

    <section class="content-grid two-col">
      ${keeperPanel(liveKeeper, criticalKeeper)}
      ${advisorPanel(data)}
    </section>

    <section class="content-grid two-col">
      ${yieldPanel(data, savings, stableLp)}
      ${policyExplainerPanel(data)}
    </section>

    ${timelinePanel(data)}
    ${systemPanel(data)}
  `;
}

function topStrip(data) {
  return `
    <header class="top-strip">
      <div>
        <p class="eyebrow">Institutional client workspace</p>
        <strong>Treasury Command Center</strong>
        <small>Generated from live Mezo testnet state and TreasuryOS CLI snapshots</small>
      </div>
      ${stripItem("Network", `Mezo Testnet / ${data.network.chainId}`)}
      ${stripItem("RPC", `${data.network.provider} ${data.network.spectrumActive ? "(Spectrum)" : ""}`)}
      ${stripItem("Owner", data.owner.mode)}
      ${stripItem("Keeper", data.keeper.live.report.recommendation.type)}
      ${stripItem("Fees", data.feeStatus.label)}
    </header>
  `;
}

function balanceSheet(position, composition, buckets, savings, stableLp) {
  return `
    <article class="panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">Balance sheet</p>
          <h2>BTC and MUSD buckets</h2>
        </div>
      </div>
      <div class="bucket-grid">
        <div class="bucket">
          <h3>BTC treasury</h3>
          ${kv("Collateral", btc(buckets.collateralBTC ?? position.collateralBTC))}
          ${kv("Idle reserve", btc(buckets.idleBTCReserve ?? composition.idleBTC))}
          ${kv("Emergency reserve", btc(buckets.emergencyBTCReserve))}
          ${kv("Yield-active BTC", btc(buckets.yieldActiveBTC))}
          ${kv("BTC sleeve", "Blocked / planning", "warn")}
        </div>
        <div class="bucket">
          <h3>MUSD operating capital</h3>
          ${kv("Total debt", musd(position.totalDebtMUSD))}
          ${kv("Close debt", musd(position.closeDebtMUSD))}
          ${kv("Idle MUSD", musd(composition.idleMUSD))}
          ${kv("MUSD Savings", musd(savings?.allocatedMUSD))}
          ${kv("MUSD/mUSDC", musd(stableLp?.allocatedMUSD))}
        </div>
      </div>
    </article>
  `;
}

function controlsPanel(data) {
  const d = data.deployment;
  return `
    <article class="panel">
      <p class="eyebrow">Policy and controls</p>
      <h2>Execution boundaries</h2>
      <div class="address-list">
        ${addressRow("TreasuryAccount", d.treasuryAccount)}
        ${addressRow("TreasuryMultisig owner", d.treasuryMultisig)}
        ${addressRow("PolicyEngine", d.treasuryPolicyEngine)}
        ${addressRow("AutomationExecutor", d.automationExecutor)}
        ${addressRow("AllocationRouter", d.allocationRouter)}
        ${addressRow("MUSD Savings handler", d.musdSavingsHandler)}
      </div>
      <div class="control-badges">
        ${badge("Client-isolated account", "neutral")}
        ${badge("Multisig controls sensitive actions", "ok")}
        ${badge("Policy enforced", "ok")}
        ${badge("Keeper allowlisted and capped", "ok")}
        ${badge("Explorer verified", "neutral")}
        ${badge("Fees disabled", "neutral")}
        ${badge("BTC sleeve validation pending", "warn")}
      </div>
    </article>
  `;
}

function keeperPanel(liveKeeper, criticalKeeper) {
  const live = liveKeeper.report;
  const critical = criticalKeeper.actionPlan;
  return `
    <article class="panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">Risk keeper</p>
          <h2>${escapeHtml(live.health.state)} / ${escapeHtml(live.recommendation.type)}</h2>
        </div>
        ${badge("Gas-only EOA", "ok")}
      </div>
      <p>${escapeHtml(live.recommendation.memo)}</p>
      <div class="metric-grid">
        ${metric("Current CR", bps(live.health.currentCollateralRatioBps), "Live")}
        ${metric("Post-stress CR", bps(live.health.postStressCollateralRatioBps), "Stress model")}
        ${metric("Defense capacity", musd(live.defenseCapacity.totalMUSD), "Effective")}
        ${metric("Required repay", musd(live.requiredDefense.repayNeededToTargetMUSD), "To target")}
      </div>
      <details>
        <summary>Critical proposal calldata</summary>
        <div class="code-block">
          <div>Target: ${addressLink(critical.target, "not available")}</div>
          <div>Signature: ${escapeHtml(critical.signature ?? "not available")}</div>
          <div>Args: ${escapeHtml((critical.args ?? []).join(", "))}</div>
          <div>${escapeHtml(critical.castCalldataCommand ?? critical.reason ?? "No calldata")}</div>
        </div>
      </details>
      <p class="boundary">Keeper pays gas only; it never custodies BTC, MUSD, or receipt tokens.</p>
    </article>
  `;
}

function advisorPanel(data) {
  const cfo = data.advisor.cfoPacket;
  return `
    <article class="panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">AI-CFO Agent</p>
          <h2>Recommendation packet ${escapeHtml(cfo.recommendationId)}</h2>
          <p class="panel-subtitle">Treasury advisor memo generated from deterministic policy data.</p>
        </div>
        ${badge("Advisory only", "neutral")}
      </div>
      <div class="memo-grid">
        <div>
          <h3>Deterministic result</h3>
          <p>${escapeHtml(data.advisor.memo)}</p>
          <p>${escapeHtml(data.advisor.btcMemo)}</p>
        </div>
        <div>
          <h3>Prepared proposal</h3>
          ${proposalList(cfo.preparedActions)}
        </div>
      </div>
      <div class="blocked-list">
        <h3>Blocked / watch-only opportunities</h3>
        ${data.advisor.opportunityReview.map((item) => `
          <div class="opportunity ${item.decision.includes("BLOCK") ? "blocked" : ""}">
            <strong>${escapeHtml(item.label)}</strong>
            <span>${escapeHtml(item.decision)}</span>
            <p>${escapeHtml(item.reason)}</p>
          </div>
        `).join("")}
      </div>
      <div class="control-badges">
        ${badge("No signing", "neutral")}
        ${badge("No custody", "neutral")}
        ${badge("No execution", "neutral")}
        ${badge("Policy is source of truth", "ok")}
      </div>
    </article>
  `;
}

function yieldPanel(data, savings, stableLp) {
  return `
    <article class="panel">
      <p class="eyebrow">Yield console</p>
      <h2>Surplus allocation, not APY chasing</h2>
      <div class="metric-grid">
        ${metric("Required buffer", musd(data.treasury.composition.liquidityBufferMUSD), "Preserved first")}
        ${metric("Allocatable surplus", musd(data.treasury.composition.deployableSurplusMUSD), "Policy-scoped")}
        ${metric("Savings exposure", musd(savings?.allocatedMUSD), `${musd(savings?.remainingCapacityMUSD)} remaining`)}
        ${metric("Stable LP exposure", musd(stableLp?.allocatedMUSD), "Optional")}
      </div>
      <div class="sleeve-table">
        ${(data.treasury.sleeves ?? []).map((sleeve) => `
          <div>
            <strong>${escapeHtml(sleeve.label)}</strong>
            <span>${escapeHtml(statusForSleeve(sleeve))}</span>
            <span>${musd(sleeve.allocatedMUSD)} / ${musd(sleeve.capMUSD)}</span>
          </div>
        `).join("")}
        <div>
          <strong>Tigris mcbBTC/BTC</strong>
          <span>BLOCKED / ADVANCED</span>
          <span>Planning only until validation passes</span>
        </div>
      </div>
    </article>
  `;
}

function policyExplainerPanel(data) {
  return `
    <article class="panel">
      <p class="eyebrow">Policy decision trace</p>
      <h2>Why actions are allowed or blocked</h2>
      <div class="explainer-stack">
        ${data.policyExplainers.map((item) => `
          <section class="explainer ${item.tone}">
            <div class="explainer-head">
              <strong>${escapeHtml(item.title)}</strong>
              <span>${escapeHtml(item.result)}</span>
            </div>
            ${item.checks.map((check) => `
              <div class="check-row ${check.pass ? "pass" : "fail"}">
                <span>${check.pass ? "OK" : "NO"}</span>
                <p>${escapeHtml(check.label)}</p>
              </div>
            `).join("")}
          </section>
        `).join("")}
      </div>
    </article>
  `;
}

function timelinePanel(data) {
  return `
    <section class="panel full-width">
      <p class="eyebrow">Scenario proof</p>
      <h2>Activity timeline</h2>
      <div class="timeline">
      ${data.timeline.map((item) => `
          <article class="timeline-item">
            <span class="timeline-status ${item.status.toLowerCase()}">${escapeHtml(item.status)}</span>
            <div>
              <strong>${escapeHtml(item.title)}</strong>
              <p>Actor: ${escapeHtml(item.actor)}</p>
              ${item.tx ? txLink(item.tx) : ""}
              ${item.address ? addressLink(item.address) : ""}
            </div>
          </article>
        `).join("")}
      </div>
    </section>
  `;
}

function systemPanel(data) {
  return `
    <section class="panel full-width">
      <p class="eyebrow">Data and infrastructure</p>
      <h2>Tenant data snapshot</h2>
      <div class="system-grid">
        ${metric("Active RPC", data.network.provider, data.network.providerEnv)}
        ${metric("Spectrum", data.network.spectrumActive ? "active" : "fallback", "Preferred RPC path")}
        ${metric("Snapshot block", data.network.snapshotBlock ?? "n/a", "Generated data")}
        ${metric("Goldsky", data.infrastructure.goldsky.status, "Indexer scaffold")}
        ${metric("Fee status", data.feeStatus.label, "Future monetization only")}
        ${metric("Generated", new Date(data.generatedAt).toLocaleString(), "Local dashboard data")}
        ${metric("Tenant", "Demo institutional client", "One TreasuryOS workspace")}
        ${metric("Data source", "Live contracts + CLI snapshots", "Public testnet state")}
      </div>
      <p class="boundary">This dashboard shows one institutional TreasuryOS tenant on Mezo testnet. The client treasury holds BTC collateral, manages borrowed MUSD operating capital, preserves a required liquidity buffer, allocates approved surplus into MUSD Savings, and exposes policy-capped keeper defense plus AI-CFO reporting.</p>
      <p class="boundary">Execution is intentionally separated: client owner/multisig controls sensitive actions; bounded keeper actions are policy-capped; the dashboard is an operator and reviewer console.</p>
    </section>
  `;
}

function proposalList(actions) {
  if (!actions?.length) return "<p>No proposal prepared.</p>";
  return actions.map((action) => `
    <div class="proposal">
      <strong>${escapeHtml(action.type)}</strong>
      <span>${escapeHtml(action.status)}</span>
      ${kvHtml("Target", addressLink(action.target))}
      ${kv("Signature", action.signature)}
      ${kv("Amount", action.humanAmount)}
      <details>
        <summary>Calldata helper</summary>
        <code>${escapeHtml(action.castCalldataCommand)}</code>
      </details>
    </div>
  `).join("");
}

function statusForSleeve(sleeve) {
  if (/savings/i.test(sleeve.label)) return "LIVE / READY";
  if (/musdc|stable/i.test(sleeve.label)) return "OPTIONAL / ROUTE-HEALTH";
  return sleeve.approved ? "APPROVED" : "WATCH";
}

function findSleeve(data, pattern) {
  const regex = new RegExp(pattern, "i");
  return (data.treasury.sleeves ?? []).find((sleeve) => regex.test(sleeve.label ?? ""));
}

function stripItem(label, value) {
  return `<div class="strip-item"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value ?? "n/a")}</strong></div>`;
}

function metric(label, value, detail) {
  return `<div class="metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong><small>${escapeHtml(detail ?? "")}</small></div>`;
}

function kv(label, value, tone = "") {
  return `<div class="kv ${tone}"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value ?? "n/a")}</strong></div>`;
}

function kvHtml(label, html, tone = "") {
  return `<div class="kv ${tone}"><span>${escapeHtml(label)}</span><strong>${html ?? "n/a"}</strong></div>`;
}

function addressRow(label, address) {
  return `<div class="address-row"><span>${escapeHtml(label)}</span>${addressLink(address)}</div>`;
}

function badge(label, tone = "neutral") {
  return `<span class="badge ${tone}">${escapeHtml(label)}</span>`;
}

function statusPill(state) {
  const normalized = String(state ?? "UNKNOWN").toLowerCase();
  return `<span class="status-pill ${normalized}">${escapeHtml(state ?? "UNKNOWN")}</span>`;
}

function musd(value) {
  return `${num(value).toLocaleString("en-US", { maximumFractionDigits: 2 })} MUSD`;
}

function btc(value) {
  return `${num(value).toLocaleString("en-US", { maximumFractionDigits: 8 })} BTC`;
}

function bps(value) {
  return `${(num(value) / 100).toFixed(2)}%`;
}

function num(value) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function shortHash(value) {
  if (!value) return "not set";
  const text = String(value);
  if (text.length <= 18) return text;
  return `${text.slice(0, 8)}...${text.slice(-6)}`;
}

function addressLink(address, fallback = "not set") {
  if (!isAddress(address)) return `<code>${escapeHtml(fallback)}</code>`;
  return proofLink({
    href: `${EXPLORER_ADDRESS}${address}`,
    value: address,
    label: shortHash(address),
    kind: "address",
  });
}

function txLink(tx) {
  if (!isTx(tx)) return "";
  return proofLink({
    href: `${EXPLORER_TX}${tx}`,
    value: tx,
    label: shortHash(tx),
    kind: "tx",
  });
}

function proofLink({ href, value, label, kind }) {
  return `
    <span class="proof-link-wrap">
      <a class="proof-link ${kind}" href="${escapeHtml(href)}" target="_blank" rel="noreferrer" title="${escapeHtml(value)}">
        <code>${escapeHtml(label)}</code><span aria-hidden="true">OPEN</span>
      </a>
      <button class="copy-button" type="button" data-copy="${escapeHtml(value)}" title="Copy ${escapeHtml(kind)}">COPY</button>
    </span>
  `;
}

function isAddress(value) {
  return /^0x[a-fA-F0-9]{40}$/.test(String(value ?? ""));
}

function isTx(value) {
  return /^0x[a-fA-F0-9]{64}$/.test(String(value ?? ""));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
