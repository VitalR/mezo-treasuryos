#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";

import { buildTreasuryAdvisorReport, formatAdvisorReport, formatCfoPacket } from "./advisor.mjs";
import { buildLiveMezoOpportunities } from "./live-opportunities.mjs";

loadDotEnv();

const args = parseArgs(process.argv.slice(2));

if (!args.snapshotPath) {
  console.error(
    "Usage: node services/treasury-advisor/run.mjs <snapshot.json> [--profile balanced] [--opportunities path|--live-opportunities] [--ai] [--cfo] [--json]",
  );
  process.exit(1);
}

const snapshot = JSON.parse(readFileSync(args.snapshotPath, "utf8"));
const opportunities = args.liveOpportunities
  ? await buildLiveMezoOpportunities()
  : args.opportunitiesPath
    ? JSON.parse(readFileSync(args.opportunitiesPath, "utf8"))
    : undefined;
const report = buildTreasuryAdvisorReport(snapshot, {
  profileName: args.profileName,
  opportunities,
});

if (args.json) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

console.log(formatAdvisorReport(report));

if (args.cfo) {
  console.log("");
  console.log(formatCfoPacket(report.cfoPacket));
}

if (args.ai) {
  const aiMemo = await buildAIMemo(report).catch((error) => `AI memo unavailable: ${error.message}`);
  console.log("");
  console.log("AI-written advisor memo:");
  console.log(aiMemo);
}

function parseArgs(argv) {
  const parsed = {
    snapshotPath: null,
    profileName: process.env.TREASURY_PROFILE ?? process.env.DEMO_TREASURY_PROFILE ?? "balanced",
    opportunitiesPath: null,
    liveOpportunities: false,
    ai: false,
    cfo: false,
    json: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--profile") {
      parsed.profileName = argv[index + 1] ?? parsed.profileName;
      index += 1;
    } else if (arg === "--opportunities") {
      parsed.opportunitiesPath = argv[index + 1] ?? null;
      index += 1;
    } else if (arg === "--live-opportunities") {
      parsed.liveOpportunities = true;
    } else if (arg === "--ai") {
      parsed.ai = true;
    } else if (arg === "--cfo") {
      parsed.cfo = true;
    } else if (arg === "--json") {
      parsed.json = true;
    } else if (!arg.startsWith("--") && !parsed.snapshotPath) {
      parsed.snapshotPath = arg;
    }
  }

  return parsed;
}

async function buildAIMemo(report) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");

  const model = process.env.TREASURY_ADVISOR_OPENAI_MODEL ?? "gpt-4.1-mini";
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "system",
          content:
            "You write concise institutional BTC treasury memos from supplied JSON only. Do not invent dates, APRs, balances, or transaction authority. Preserve all numbers exactly. Use six short bullets or fewer and complete the memo. You are advisory only. Do not imply that AI signs, controls funds, bypasses policy, or executes transactions.",
        },
        {
          role: "user",
          content: JSON.stringify({
            treasuryName: report.treasuryName,
            profile: report.profile,
            summary: report.summary,
            sleeves: report.sleeves,
            btc: report.btc,
            allocationPlan: report.allocationPlan,
            automationAction: report.automationAction,
            opportunityReview: report.opportunityReview,
            cfoPacket: report.cfoPacket,
            btcMemo: report.btcMemo,
            guardrails: report.guardrails,
            memoRules: [
              "Do not include a date.",
              "Say current MUSD Savings allocation is 900 MUSD if that is present in sleeves.",
              "Say recommended new allocation is 25 MUSD if that is present in allocationPlan.",
              "Do not claim positive yield when annualYieldBps is 0.",
              "Do not say 'no yield reduction' or imply yield improvement when projected yield is 0.",
              "If discussing yield, say projected 30d yield is 0 MUSD when that is present in allocationPlan.",
              "Explain mcbBTC/BTC using the supplied opportunityReview reason; do not use stale quote-impact values.",
              "In the Opportunity Review section, preserve each supplied opportunityReview decision and reason exactly.",
              "Do not say a BTC handler is missing or undeveloped unless the supplied reason says that.",
              "If cfoPacket.preparedActions is non-empty, mention that the action is prepared_not_executed and must be approved/executed through the stated approval path.",
            ],
          }),
        },
      ],
      max_output_tokens: 750,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI API returned ${response.status}`);
  }

  const data = await response.json();
  return extractResponseText(data);
}

function extractResponseText(data) {
  if (typeof data.output_text === "string" && data.output_text.trim()) return data.output_text.trim();
  const parts = [];
  for (const item of data.output ?? []) {
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && content.text) parts.push(content.text);
      if (content.type === "text" && content.text) parts.push(content.text);
    }
  }
  return parts.join("\n").trim() || "AI memo response did not include text.";
}

function loadDotEnv(path = ".env") {
  if (!existsSync(path)) return;

  const content = readFileSync(path, "utf8");
  for (const line of content.split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separator = trimmed.indexOf("=");
    if (separator === -1) continue;

    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if (!key || process.env[key] != null) continue;

    if (
      (value.startsWith("'") && value.endsWith("'"))
      || (value.startsWith('"') && value.endsWith('"'))
    ) {
      value = value.slice(1, -1);
    }

    process.env[key] = value;
  }
}
