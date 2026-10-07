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

The RDS database is private and accepts connections only from the application Lambda and the Jenkins host security group over same-region VPC peering. Jenkins runs on the existing EC2 host, avoiding a second always-on build instance. VPC peering has no hourly connection charge; data transfer may be billed. The VPC has a private Secrets Manager interface endpoint for Lambda. Jenkins uses its EC2 instance role to call Secrets Manager through its existing outbound connectivity. The Secrets Manager interface endpoint has an hourly charge and is not covered by the typical RDS free-tier allowance.

Jenkins temporarily reads the RDS-managed master credential to create a restricted `realworld_app` database role. It runs `prisma migrate deploy` as that restricted role and stores the application credential JSON in the dedicated Secrets Manager secret. Terraform grants the configured Jenkins EC2 role access only to the RDS master secret and this application secret. The Lambda role can read only the application secret; it cannot read the RDS master secret. Never print or commit either credential.

To run migrations from Jenkins after VPC peering and its IAM policy are applied, configure these non-secret values from Terraform outputs as pipeline environment variables: `DB_HOST`, `DB_PORT`, `DB_NAME`, `RDS_MASTER_SECRET_ARN`, `APP_SECRET_ARN`, and `APP_DB_USERNAME=realworld_app`. Jenkins must check out the backend repository and use the repository's Node/npm toolchain. Then run:

```shell
npm ci
DATABASE_URL='postgresql://placeholder:placeholder@localhost:5432/realworld' \
DIRECT_URL='postgresql://placeholder:placeholder@localhost:5432/realworld' \
  npx prisma generate
node scripts/provision-app-db-user.js
```

The placeholder URLs are used only for Prisma client generation; migrations and database-user provisioning obtain their real credentials from Secrets Manager at runtime. Jenkins must run migrations before publishing a backend release. The private, encrypted, versioned S3 bucket is reserved for deployment artifacts and expires old migration artifacts after 30 days.

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
