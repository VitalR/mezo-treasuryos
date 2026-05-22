#!/usr/bin/env node

import { cpSync, existsSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const dashboardRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = resolve(dashboardRoot, "public");
const output = resolve(dashboardRoot, "dist");

if (!existsSync(source)) {
  throw new Error("Missing dashboard/public. Run from the repository root.");
}

rmSync(output, { force: true, recursive: true });
cpSync(source, output, { recursive: true });

console.log("Built dashboard/dist");
