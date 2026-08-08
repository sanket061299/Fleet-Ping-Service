const express = require("express");
const { Pool } = require("pg");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");

const PORT = Number(process.env.PORT || 3000);
const NODE_ENV = process.env.NODE_ENV || "development";
const JWT_SECRET = process.env.JWT_SECRET;

if (NODE_ENV === "production" && !JWT_SECRET) {
  throw new Error("JWT_SECRET must be configured in production");
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.DB_POOL_MAX || 20),
  idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS || 30000),
  connectionTimeoutMillis: Number(process.env.DB_CONNECTION_TIMEOUT_MS || 5000),
  ssl: process.env.DB_SSL === "true" ? { rejectUnauthorized: true } : false,
});

pool.on("error", (err) => {
  console.error(JSON.stringify({
    level: "error",
    event: "db_pool_error",
    message: err.message,
  }));
});

function log(level, event, fields = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    event,
    service: "fleet-ping-service",
    ...fields,
  }));
}

function validatePing(body) {
  const { vehicleId, lat, lng, speed, timestamp } = body;
  if (!vehicleId || typeof vehicleId !== "string" || vehicleId.length > 50) {
    return "vehicleId is required and must be <= 50 characters";
  }
  if (!Number.isFinite(Number(lat)) || Number(lat) < -90 || Number(lat) > 90) {
    return "lat must be between -90 and 90";
  }
  if (!Number.isFinite(Number(lng)) || Number(lng) < -180 || Number(lng) > 180) {
    return "lng must be between -180 and 180";
  }
  if (!Number.isFinite(Number(speed)) || Number(speed) < 0 || Number(speed) > 500) {
    return "speed must be between 0 and 500";
  }
  if (!timestamp || Number.isNaN(Date.parse(timestamp))) {
    return "timestamp must be a valid ISO-8601 timestamp";
  }
  return null;
}

function verifyOtp(otp, otpHash) {
  if (!otp || !otpHash || !otpHash.startsWith("scrypt$")) return false;
  const [, saltHex, hashHex] = otpHash.split("$");
  try {
    const derived = crypto.scryptSync(String(otp), Buffer.from(saltHex, "hex"), 32);
    return crypto.timingSafeEqual(derived, Buffer.from(hashHex, "hex"));
  } catch {
    return false;
  }
}

function createApp(db = pool) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "64kb" }));

  app.use((req, res, next) => {
    const started = process.hrtime.bigint();
    res.on("finish", () => {
      const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
      log("info", "http_request", {
        method: req.method,
        path: req.path,
        status: res.statusCode,
        duration_ms: Math.round(durationMs * 100) / 100,
      });
    });
    next();
  });

  app.get("/", (_req, res) => {
    res.json({ service: "fleet-ping-service", status: "running" });
  });

  app.get("/healthz", (_req, res) => {
    res.status(200).json({ status: "healthy" });
  });

  app.get("/readyz", async (_req, res) => {
    try {
      await db.query("SELECT 1");
      res.status(200).json({ status: "ready" });
    } catch (err) {
      log("error", "readiness_check_failed", { message: err.message });
      res.status(503).json({ status: "not_ready" });
    }
  });

  app.post("/api/fleet/ping", async (req, res) => {
    const validationError = validatePing(req.body);
    if (validationError) return res.status(400).json({ error: validationError });

    const { vehicleId, lat, lng, speed, timestamp } = req.body;
    try {
      await db.query(
        `INSERT INTO fleet_pings (vehicle_id, lat, lng, speed, ts)
         VALUES ($1, $2, $3, $4, $5)`,
        [vehicleId, Number(lat), Number(lng), Number(speed), new Date(timestamp)]
      );
      return res.status(201).json({ status: "ok" });
    } catch (err) {
      log("error", "ping_insert_failed", { message: err.message });
      return res.status(500).json({ error: "insert failed" });
    }
  });

  app.post("/api/auth/login", async (req, res) => {
    const { phone, otp } = req.body;
    if (!phone || !otp) return res.status(400).json({ error: "phone and otp are required" });

    try {
      const result = await db.query(
        "SELECT id, otp_hash, role FROM drivers WHERE phone = $1",
        [phone]
      );
      if (result.rows.length === 0 || !verifyOtp(otp, result.rows[0].otp_hash)) {
        return res.status(401).json({ error: "invalid credentials" });
      }

      const secret = JWT_SECRET || "development-only-secret";
      const token = jwt.sign(
        { driverId: result.rows[0].id, role: result.rows[0].role },
        secret,
        { expiresIn: "15m", issuer: "vexardrive", audience: "fleet-api" }
      );
      return res.json({ token });
    } catch (err) {
      log("error", "login_failed", { message: err.message });
      return res.status(500).json({ error: "authentication failed" });
    }
  });

  app.get("/api/admin/drivers", async (req, res) => {
    const auth = req.headers.authorization || "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
    if (!token) return res.status(401).json({ error: "authentication required" });

    try {
      const secret = JWT_SECRET || "development-only-secret";
      const claims = jwt.verify(token, secret, {
        issuer: "vexardrive",
        audience: "fleet-api",
      });
      if (claims.role !== "admin") {
        return res.status(403).json({ error: "admin role required" });
      }

      const result = await db.query(
        "SELECT id, phone, name, created_at FROM drivers ORDER BY id"
      );
      return res.json(result.rows);
    } catch {
      return res.status(401).json({ error: "invalid token" });
    }
  });

  return app;
}

if (require.main === module) {
  const server = createApp().listen(PORT, () => {
    log("info", "server_started", { port: PORT, node_env: NODE_ENV });
  });

  const shutdown = async (signal) => {
    log("info", "shutdown_started", { signal });
    server.close(async () => {
      await pool.end();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

module.exports = { createApp, pool };
