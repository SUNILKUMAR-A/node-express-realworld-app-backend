# ![Node/Express/Prisma Example App](project-logo.png)

[![Build Status](https://travis-ci.org/anishkny/node-express-realworld-example-app.svg?branch=master)](https://travis-ci.org/anishkny/node-express-realworld-example-app)

> ### Example Node (Express + Prisma) codebase containing real world examples (CRUD, auth, advanced patterns, etc) that adheres to the [RealWorld](https://github.com/gothinkster/realworld-example-apps) API spec.

<a href="https://thinkster.io/tutorials/node-json-api" target="_blank"><img width="454" src="https://raw.githubusercontent.com/gothinkster/realworld/master/media/learn-btn-hr.png" /></a>

## Getting Started

### Prerequisites

Run the following command to install dependencies:

```shell
npm install
```

### Environment variables

This project depends on some environment variables.
If you are running this project locally, create a `.env` file at the root for these variables.
Your host provider should included a feature to set them there directly to avoid exposing them.

Here are the required ones:

```
DATABASE_URL=
DIRECT_URL=
JWT_SECRET=
NODE_ENV=production
```

For PostgreSQL, set `DATABASE_URL` to the application connection string and `DIRECT_URL` to the direct connection string used by Prisma migrations. For the AWS RDS deployment in this assignment, both use the private RDS endpoint with `sslmode=require`. Locally, both can use the same connection string. Keep credentials in an ignored `.env` file for local development and AWS Secrets Manager in deployed environments; never commit credentials.

### Private RDS migrations

The production database is private and accepts connections only from the application Lambda and the one-shot migration runner security groups. The Terraform stack provisions a VPC-connected CodeBuild project, an encrypted private S3 artifact bucket, and VPC endpoints for S3, Secrets Manager, and CloudWatch Logs. This avoids a NAT gateway, but interface endpoints have hourly charges.

The migration runner temporarily uses the RDS-managed master credential to create or rotate a restricted `realworld_app` database role. It then runs `prisma migrate deploy` as that restricted role and stores the application credential JSON in the dedicated Secrets Manager secret. The Lambda role can read only the application secret; it cannot read the RDS master secret. Never print or commit either credential.

To prepare and invoke a migration after applying the Terraform stack:

```shell
npm ci
npx prisma generate
export MIGRATION_ARTIFACT_BUCKET="$(terraform -chdir=infra/main output -raw migration_artifact_bucket)"
./scripts/package-migration-artifact.sh
aws codebuild start-build \
  --project-name "$(terraform -chdir=infra/main output -raw migration_codebuild_project)"
```

Check the CodeBuild result and CloudWatch Logs before deploying an API release. The migration artifact contains installed Node dependencies and Prisma migrations; it is uploaded to a private, encrypted, versioned S3 bucket with a 30-day lifecycle.

On Linux, invoke the packaging helper with `bash` if its executable bit is not set:

```shell
bash ./scripts/package-migration-artifact.sh
```

### Generate your Prisma client

Run the following command to generate the Prisma Client which will include types based on your database schema:

```shell
npx prisma generate
```

### Apply any SQL migration script

Run the following command to create/update your database based on existing sql migration scripts:

```shell
npx prisma migrate deploy
```

### Run the project

Run the following command to run the project:

```shell
npx nx serve api
```

### Seed the database

The project includes a seed script to populate the database:

```shell
npx prisma db seed
```

## Deploy on a remote server

Run the following command to:
- install dependencies
- apply any new migration sql scripts
- run the server

```shell
npm ci && npx prisma migrate deploy && node dist/api/main.js
```
