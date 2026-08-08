const { Client } = require("pg");

const host = process.env.DATABASE_HOST;
const database = process.env.DATABASE_NAME || "vexar_fleet";
const admin = process.env.DATABASE_ADMIN;
const adminPassword = process.env.DATABASE_ADMIN_PASSWORD;
const appPassword = process.env.DATABASE_APP_PASSWORD;

if (!host || !admin || !adminPassword || !appPassword) {
  throw new Error("Database migration environment is incomplete");
}

const ssl = { rejectUnauthorized: true };

async function main() {
  const client = new Client({
    host,
    port: 5432,
    user: admin,
    password: adminPassword,
    database,
    ssl,
  });

  await client.connect();

  try {
    await client.query(`
      CREATE ROLE appuser LOGIN PASSWORD '${appPassword.replaceAll("'", "''")}'
    `).catch(async (err) => {
      if (err.code !== "42710") throw err;
      await client.query(
        `ALTER ROLE appuser PASSWORD '${appPassword.replaceAll("'", "''")}';`
      );
    });

    await client.query(`GRANT CONNECT ON DATABASE "${database}" TO appuser`);

    await client.query(`
      CREATE TABLE IF NOT EXISTS drivers (
        id BIGSERIAL PRIMARY KEY,
        phone VARCHAR(15) UNIQUE NOT NULL,
        name VARCHAR(100),
        otp_hash TEXT NOT NULL,
        role VARCHAR(20) NOT NULL DEFAULT 'driver',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS fleet_pings (
        id BIGSERIAL PRIMARY KEY,
        vehicle_id VARCHAR(50) NOT NULL,
        lat DECIMAL(9,6) NOT NULL CHECK (lat BETWEEN -90 AND 90),
        lng DECIMAL(9,6) NOT NULL CHECK (lng BETWEEN -180 AND 180),
        speed DECIMAL(5,2) NOT NULL CHECK (speed BETWEEN 0 AND 500),
        ts TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_fleet_pings_vehicle_ts
      ON fleet_pings (vehicle_id, ts DESC)
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_fleet_pings_ts
      ON fleet_pings (ts DESC)
    `);

    await client.query(`GRANT USAGE ON SCHEMA public TO appuser`);
    await client.query(`GRANT SELECT, INSERT, UPDATE, DELETE ON drivers, fleet_pings TO appuser`);
    await client.query(`GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser`);
    await client.query(`
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser
    `);
    await client.query(`
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT USAGE, SELECT ON SEQUENCES TO appuser
    `);

    console.log(JSON.stringify({ level: "info", event: "migration_complete" }));
  } finally {
    await client.end();
  }
}

main().catch(err => {
  console.error(JSON.stringify({ level: "error", event: "migration_failed", message: err.message }));
  process.exit(1);
});
