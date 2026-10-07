import { GetSecretValueCommand, SecretsManagerClient } from '@aws-sdk/client-secrets-manager';

const secretsManager = new SecretsManagerClient({});

const configureDatabase = async () => {
  const secretArn = process.env.APP_SECRET_ARN;
  if (!secretArn) {
    if (!process.env.DATABASE_URL || !process.env.DIRECT_URL) {
      throw new Error('Configure APP_SECRET_ARN or both DATABASE_URL and DIRECT_URL.');
    }
    return;
  }

  const secretResult = await secretsManager.send(
    new GetSecretValueCommand({ SecretId: secretArn }),
  );
  if (!secretResult.SecretString) {
    throw new Error('The application database secret has no SecretString value.');
  }

  const credentials = JSON.parse(secretResult.SecretString);
  if (
    !credentials.username ||
    !credentials.password ||
    !credentials.host ||
    !credentials.port ||
    !credentials.dbname
  ) {
    throw new Error('The application database secret is missing required connection fields.');
  }

  const databaseUrl = new URL(
    `postgresql://${encodeURIComponent(credentials.username)}:${encodeURIComponent(credentials.password)}@${credentials.host}:${credentials.port}/${credentials.dbname}`,
  );
  databaseUrl.searchParams.set('sslmode', 'require');
  process.env.DATABASE_URL = databaseUrl.toString();
  process.env.DIRECT_URL = databaseUrl.toString();
};

const start = async () => {
  await configureDatabase();
  const { default: app } = await import('./app');
  const PORT = Number(process.env.PORT || 3000);
  app.listen(PORT, '127.0.0.1', () => {
    console.info(`RealWorld API listening on port ${PORT}`);
  });
};

start().catch((error: unknown) => {
  console.error('Unable to start the RealWorld API:', error);
  process.exitCode = 1;
});
