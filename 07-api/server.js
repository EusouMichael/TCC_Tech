const express = require("express");
const helmet = require("helmet");
const { Pool, Client } = require("pg");
const { Signer } = require("@aws-sdk/rds-signer");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");

const PORT = Number(process.env.PORT || 3000);
const app = express();
const RDS_CA = fs.readFileSync("/etc/pki/rds/global-bundle.pem", "utf8");

app.disable("x-powered-by");
app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: "32kb" }));

function loadDatabaseSecret() {
  const arn = process.env.DB_SECRET_ARN;
  if (!arn) throw new Error("DB_SECRET_ARN nao configurado");

  const raw = execFileSync(
    "aws",
    ["secretsmanager", "get-secret-value", "--secret-id", arn, "--region", process.env.AWS_REGION, "--query", "SecretString", "--output", "text"],
    { encoding: "utf8", timeout: 10000 }
  ).trim();

  return JSON.parse(raw);
}

function createAdminClient(secret) {
  return new Client({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME,
    user: secret.username,
    password: secret.password,
    ssl: { rejectUnauthorized: true, ca: RDS_CA },
    connectionTimeoutMillis: 10000
  });
}

function createAppPool() {
  const signer = new Signer({
    region: process.env.AWS_REGION,
    hostname: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    username: process.env.DB_APP_USERNAME
  });

  return new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME,
    user: process.env.DB_APP_USERNAME,
    password: () => signer.getAuthToken(),
    ssl: { rejectUnauthorized: true, ca: RDS_CA },
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
    maxLifetimeSeconds: 600
  });
}

let pool;

async function initializeDatabase() {
  const adminSecret = loadDatabaseSecret();
  const admin = createAdminClient(adminSecret);

  for (let attempt = 1; attempt <= 30; attempt++) {
    try {
      await admin.connect();

      await admin.query(`CREATE ROLE "${process.env.DB_APP_USERNAME}" LOGIN;`);
      console.log("Application database role created");
    } catch (error) {
      if (error.code !== "42710") {
        console.error(`Database role/bootstrap attempt ${attempt}/30 failed:`, error.message);
        if (attempt === 30) throw error;
        await new Promise((resolve) => setTimeout(resolve, 5000));
        continue;
      }
    }

    try {
      await admin.query(`GRANT rds_iam TO "${process.env.DB_APP_USERNAME}";`);
      await admin.query(`GRANT CONNECT ON DATABASE "${process.env.DB_NAME}" TO "${process.env.DB_APP_USERNAME}";`);
      await admin.query(`
        CREATE TABLE IF NOT EXISTS enrollments (
          id BIGSERIAL PRIMARY KEY,
          first_name VARCHAR(100) NOT NULL,
          email VARCHAR(255) NOT NULL,
          phone VARCHAR(30),
          course VARCHAR(100) NOT NULL,
          experience VARCHAR(30),
          message TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      `);
      await admin.query('GRANT USAGE ON SCHEMA public TO "' + process.env.DB_APP_USERNAME + '";');
      await admin.query('GRANT SELECT, INSERT ON enrollments TO "' + process.env.DB_APP_USERNAME + '";');
      await admin.query('GRANT USAGE, SELECT ON SEQUENCE enrollments_id_seq TO "' + process.env.DB_APP_USERNAME + '";');
      await admin.query("CREATE INDEX IF NOT EXISTS idx_enrollments_email ON enrollments(email);");
      await admin.query("CREATE INDEX IF NOT EXISTS idx_enrollments_created_at ON enrollments(created_at);");
      await admin.end();
      pool = createAppPool();
      await pool.query("SELECT 1");
      console.log("Database initialized; application uses IAM authentication");
      return;
    } catch (error) {
      console.error(`Database initialization attempt ${attempt}/30 failed:`, error.message);
      try { await admin.end(); } catch {}
      if (attempt === 30) throw error;
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
  }
}

app.get("/api/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.status(200).json({ status: "ok", database: "ok" });
  } catch {
    res.status(503).json({ status: "degraded", database: "unavailable" });
  }
});

app.post("/api/enrollments", async (req, res) => {
  const { firstName, email, phone, course, experience, message } = req.body || {};

  if (!firstName || !email || !course) {
    return res.status(400).json({ error: "firstName, email e course sao obrigatorios" });
  }

  if (String(firstName).length > 100 || String(email).length > 255 || String(message || "").length > 2000) {
    return res.status(400).json({ error: "Dados acima do limite permitido" });
  }

  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email));
  if (!emailOk) return res.status(400).json({ error: "E-mail invalido" });

  try {
    const result = await pool.query(
      `INSERT INTO enrollments (first_name, email, phone, course, experience, message)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, first_name, email, course, created_at`,
      [
        String(firstName).trim(),
        String(email).trim().toLowerCase(),
        phone ? String(phone).trim() : null,
        String(course).trim(),
        experience ? String(experience).trim() : null,
        message ? String(message).trim() : null
      ]
    );

    return res.status(201).json({ enrollment: result.rows[0] });
  } catch (error) {
    console.error("Enrollment error:", error.message);
    return res.status(500).json({ error: "Nao foi possivel concluir o cadastro" });
  }
});

initializeDatabase()
  .then(() => app.listen(PORT, "127.0.0.1", () => console.log(`API listening on 127.0.0.1:${PORT}`)))
  .catch((error) => {
    console.error("Fatal startup error:", error);
    process.exit(1);
  });
