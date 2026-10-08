const express = require("express");
const helmet = require("helmet");
const { Pool } = require("pg");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");

const PORT = Number(process.env.PORT || 3000);
const app = express();

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

  const secret = JSON.parse(raw);
  return {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME,
    user: secret.username,
    password: secret.password,
    ssl: {
      rejectUnauthorized: true,
      ca: fs.readFileSync("/etc/pki/rds/global-bundle.pem", "utf8")
    },
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000
  };
}

let pool;

function getPool() {
  if (!pool) pool = new Pool(loadDatabaseSecret());
  return pool;
}

async function initializeDatabase() {
  const p = getPool();
  for (let attempt = 1; attempt <= 30; attempt++) {
    try {
      await p.query(`
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

        CREATE INDEX IF NOT EXISTS idx_enrollments_email ON enrollments(email);
        CREATE INDEX IF NOT EXISTS idx_enrollments_created_at ON enrollments(created_at);
      `);
      console.log("Database initialized");
      return;
    } catch (error) {
      console.error(`Database attempt ${attempt}/30 failed:`, error.message);
      if (attempt === 30) throw error;
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
  }
}

app.get("/api/health", async (_req, res) => {
  try {
    await getPool().query("SELECT 1");
    res.status(200).json({ status: "ok", database: "ok" });
  } catch {
    res.status(503).json({ status: "degraded", database: "unavailable" });
  }
});

app.post("/api/enrollments", async (req, res) => {
  const { firstName, email, phone, course, experience, message } = req.body || {};

  if (!firstName || !email || !course) {
    return res.status(400).json({
      error: "firstName, email e course sao obrigatorios"
    });
  }

  if (String(firstName).length > 100 || String(email).length > 255 || String(message || "").length > 2000) {
    return res.status(400).json({ error: "Dados acima do limite permitido" });
  }

  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email));
  if (!emailOk) return res.status(400).json({ error: "E-mail invalido" });

  try {
    const result = await getPool().query(
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
    console.error("Enrollment error:", error);
    return res.status(500).json({ error: "Nao foi possivel concluir o cadastro" });
  }
});

initializeDatabase()
  .then(() => app.listen(PORT, "127.0.0.1", () => console.log(`API listening on 127.0.0.1:${PORT}`)))
  .catch((error) => {
    console.error("Fatal startup error:", error);
    process.exit(1);
  });
