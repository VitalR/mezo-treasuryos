#!/usr/bin/env node

import { createReadStream, existsSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const dashboardRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = resolve(dashboardRoot, process.env.DASHBOARD_ROOT ?? "public");
const port = Number(process.env.DASHBOARD_PORT ?? process.env.PORT ?? 5173);

const types = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

createServer((request, response) => {
  const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
  const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
  const filePath = resolve(join(root, normalize(pathname)));

  if (!filePath.startsWith(root) || !existsSync(filePath)) {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("Not found");
    return;
  }

  response.writeHead(200, { "content-type": types[extname(filePath)] ?? "application/octet-stream" });
  createReadStream(filePath).pipe(response);
}).listen(port, () => {
  console.log(`TreasuryOS dashboard: http://127.0.0.1:${port}`);
  console.log(`Serving: ${root}`);
});
