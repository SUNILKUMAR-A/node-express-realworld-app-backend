const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { PrismaClient } = require('@prisma/client');

const masterSecret = JSON.parse(process.env.RDS_MASTER_SECRET);
const databaseName = process.env.DB_NAME;
const username = process.env.APP_DB_USERNAME;
const password = crypto.randomBytes(32).toString('base64url');

const connectionUrl = (user, secretPassword) => {
  const url = new URL(
    `postgresql://${encodeURIComponent(user)}:${encodeURIComponent(secretPassword)}@${process.env.DB_HOST}:${process.env.DB_PORT}/${databaseName}`,
  );
  url.searchParams.set('sslmode', 'require');
  return url.toString();
};

const run = async () => {
  const admin = new PrismaClient({
    datasources: {
      db: {
        url: connectionUrl(masterSecret.username, masterSecret.password),
      },
    },
  });

  try {
    await admin.$connect();
    const [{ statement: roleStatement }] = await admin.$queryRaw`
      SELECT format(
        '%s ROLE %I LOGIN PASSWORD %L',
        CASE
          WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ${username})
          THEN 'ALTER'
          ELSE 'CREATE'
        END,
        ${username},
        ${password}
      ) AS statement
    `;
    await admin.$executeRawUnsafe(roleStatement);

    const [{ statement: connectStatement }] = await admin.$queryRaw`
      SELECT format('GRANT CONNECT ON DATABASE %I TO %I', ${databaseName}, ${username}) AS statement
    `;
    await admin.$executeRawUnsafe(connectStatement);

    const [{ statement: schemaStatement }] = await admin.$queryRaw`
      SELECT format('GRANT USAGE, CREATE ON SCHEMA public TO %I', ${username}) AS statement
    `;
    await admin.$executeRawUnsafe(schemaStatement);
  } finally {
    await admin.$disconnect();
  }

  const appUrl = connectionUrl(username, password);
  const migration = spawnSync(
    path.resolve('node_modules/.bin/prisma'),
    ['migrate', 'deploy'],
    {
      env: {
        ...Object.fromEntries(
          Object.entries(process.env).filter(([key]) => key !== 'RDS_MASTER_SECRET'),
        ),
        DATABASE_URL: appUrl,
        DIRECT_URL: appUrl,
      },
      stdio: 'inherit',
      shell: process.platform === 'win32',
    },
  );

  if (migration.error) {
    throw migration.error;
  }
  if (migration.status !== 0) {
    throw new Error(`Prisma migrate deploy exited with status ${migration.status}`);
  }

  const secretFile = path.join(os.tmpdir(), `realworld-app-secret-${process.pid}.json`);
  const secretValue = JSON.stringify({
    username,
    password,
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    dbname: databaseName,
  });

  try {
    fs.writeFileSync(secretFile, secretValue, { mode: 0o600, flag: 'wx' });
    const result = spawnSync(
      'aws',
      [
        'secretsmanager',
        'put-secret-value',
        '--secret-id',
        process.env.APP_SECRET_ARN,
        '--secret-string',
        `file://${secretFile}`,
      ],
      { stdio: 'inherit' },
    );
    if (result.error) {
      throw result.error;
    }
    if (result.status !== 0) {
      throw new Error(`Writing application credentials failed with status ${result.status}`);
    }
  } finally {
    fs.rmSync(secretFile, { force: true });
  }
};

run().catch((error) => {
  const details =
    error instanceof Error ? error.message : String(error);
  const sanitized = details
    .split(masterSecret.password)
    .join('[REDACTED]')
    .split(password)
    .join('[REDACTED]');
  console.error(`Database migration or application-user provisioning failed: ${sanitized}`);
  process.exitCode = 1;
});
