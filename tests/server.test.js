const test = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../server");
const http = require("node:http");

function request(app, method, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      const data = body ? JSON.stringify(body) : "";
      const req = http.request({
        hostname: "127.0.0.1",
        port,
        path,
        method,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(data),
          ...headers,
        },
      }, (res) => {
        let raw = "";
        res.on("data", chunk => raw += chunk);
        res.on("end", () => {
          server.close();
          resolve({ status: res.statusCode, body: raw ? JSON.parse(raw) : null });
        });
      });
      req.on("error", reject);
      if (data) req.write(data);
      req.end();
    });
  });
}

test("health endpoint returns healthy", async () => {
  const app = createApp({ query: async () => ({ rows: [{ "?column?": 1 }] }) });
  const result = await request(app, "GET", "/healthz");
  assert.equal(result.status, 200);
  assert.equal(result.body.status, "healthy");
});

test("readiness endpoint verifies database connectivity", async () => {
  const app = createApp({ query: async () => ({ rows: [{ "?column?": 1 }] }) });
  const result = await request(app, "GET", "/readyz");
  assert.equal(result.status, 200);
  assert.equal(result.body.status, "ready");
});

test("ping validation rejects invalid coordinates", async () => {
  const app = createApp({ query: async () => ({ rows: [] }) });
  const result = await request(app, "POST", "/api/fleet/ping", {
    vehicleId: "VH-001", lat: 100, lng: 10, speed: 50, timestamp: new Date().toISOString()
  });
  assert.equal(result.status, 400);
});

test("admin endpoint requires authentication", async () => {
  const app = createApp({ query: async () => ({ rows: [] }) });
  const result = await request(app, "GET", "/api/admin/drivers");
  assert.equal(result.status, 401);
});
