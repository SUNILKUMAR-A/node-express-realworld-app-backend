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

The RDS database is private and accepts connections only from application hosts allowed by its security group, reached over same-region VPC peering. The simplified branch deploys the API to the `aws-builder` host. VPC peering has no hourly connection charge; data transfer may be billed. The existing VPC includes a private Secrets Manager interface endpoint; the EC2 service uses its instance role to retrieve the app credential. The endpoint has an hourly charge and may not be covered by Free Tier.

Jenkins temporarily reads the RDS-managed master credential to create a restricted `realworld_app` database role. It runs `prisma migrate deploy` as that restricted role and stores the application credential JSON in the dedicated Secrets Manager secret. The EC2 instance role needs access to the RDS master secret for migrations and the app secret for runtime. Never print or commit either credential.

To run migrations from Jenkins on the application agent after VPC peering, its security-group access, and IAM permissions are applied, configure these non-secret values from Terraform outputs as pipeline parameters: `DB_HOST`, `DB_PORT`, `DB_NAME`, `RDS_MASTER_SECRET_ARN`, and `APP_SECRET_ARN`. The pipeline sets `APP_DB_USERNAME=realworld_app`. Then run:

```shell
npm ci
DATABASE_URL='postgresql://placeholder:placeholder@localhost:5432/realworld' \
DIRECT_URL='postgresql://placeholder:placeholder@localhost:5432/realworld' \
  npx prisma generate
node scripts/provision-app-db-user.js
```

The placeholder URLs are used only for Prisma client generation; migrations and database-user provisioning obtain their real credentials from Secrets Manager at runtime. Jenkins must run migrations before publishing a backend release. The private, encrypted, versioned S3 bucket is reserved for deployment artifacts and expires old migration artifacts after 30 days.

## Assignment deployment architecture

This simplified deployment runs the React static build and Express API on the dedicated `aws-builder` EC2 instance. Nginx serves the frontend on port 80 and reverse-proxies `/api` to the Node service on localhost port 3000. The Node service reads the restricted database credential from AWS Secrets Manager using the EC2 instance profile, then connects to the existing private, encrypted RDS PostgreSQL database. Jenkins runs the build, tests, migrations, and deployment on that same agent; no Lambda package, API Gateway, CloudFront, or public S3 hosting is required by this branch.

The RDS VPC remains private and is reached over the existing VPC peering connection. Allow PostgreSQL inbound on the RDS security group from the **agent's** security group, not the Jenkins controller group. The agent security group must allow HTTP port 80 from intended users; restrict SSH to the controller security group. Attach an EC2 instance profile that can read the application secret and read the RDS master secret plus update the application secret for the migration job. Because build, migration, and app runtime share this EC2 role, the running API host also has migration-level secret permissions; separate build/runtime roles and instances in production. Do not place database passwords in Jenkins parameters or files.

The existing Terraform stack still manages AWS networking and RDS, but this simple pipeline does not run Terraform or change those resources. Keep Terraform state and plan files out of Git. For production, separate build and runtime hosts, use HTTPS through a verified CloudFront distribution or load balancer, and manage the app host/security rules fully through Terraform.

## Jenkins CI/CD

Configure a Jenkins Pipeline job to use branch `simple-ec2-deployment` and load this repository's `Jenkinsfile`. The `aws-builder` agent must have Java 21, Node/npm, Git, AWS CLI, and passwordless sudo for the limited Nginx/systemd deployment commands. Its EC2 role supplies AWS authentication; do not store AWS access keys or database passwords in Jenkins.

Set the non-secret build parameters from Terraform outputs: `DB_HOST`, `DB_PORT`, `DB_NAME`, `RDS_MASTER_SECRET_ARN`, and `APP_SECRET_ARN`. Set `APP_PUBLIC_URL` to the agent's HTTP URL if you want an external smoke test. Before first build, configure the RDS and agent security-group rules and instance-profile permissions described above.

The pipeline clones the frontend, installs dependencies, builds/tests the API, records npm audit reports, builds the React app to use same-origin `/api`, and runs Prisma migrations through VPC peering. It installs production dependencies for the API, deploys versioned backend/frontend releases under `/opt/realworld`, configures a systemd Node service and Nginx reverse proxy, and smoke-tests frontend/API locally (and externally when `APP_PUBLIC_URL` is set). The build commit and Jenkins build number identify each release. Use Git SemVer tags for release labels; review audit reports and document findings rather than claiming an unreviewed scan is clean.

The pipeline stores npm's download cache in `/home/ec2-user/.cache/jenkins/npm` on the `aws-builder` agent, outside the Jenkins workspace. It survives `deleteDir()` between builds and is reused by backend and frontend installs. `npm ci` still performs a clean install from each lockfile; only package downloads are cached. Monitor agent disk usage and periodically run `sudo -u ec2-user npm cache clean --force` if the cache grows too large.

## Monitoring and security

The Node service writes startup and application logs to stdout/stderr, which systemd records in the journal (`journalctl -u realworld-api`). Nginx access/error logs are in `/var/log/nginx`. Check service health with `systemctl status realworld-api nginx` and the API endpoint `/api/tags`. RDS CPU/connections remain available in CloudWatch. Grafana can visualize CloudWatch metrics if needed; Prometheus scraping is not configured in this simplified branch.

RDS is encrypted, private, single-AZ for the demo, and should only accept PostgreSQL from the app agent security group. The shared EC2 instance role reads the RDS-managed master secret for migrations and the restricted app secret for runtime. The Node service listens on localhost and Nginx exposes only HTTP port 80. Dependency audit results are archived by Jenkins. Never commit `.env`, AWS credentials, generated secret values, Terraform state, or plan files.

## Cost and limitations

The API/frontend now share the existing agent EC2, avoiding a Lambda package and CloudFront account-verification blocker. EC2/EBS, RDS, Secrets Manager, VPC interface endpoints, CloudWatch, and data transfer can incur charges; Free Tier eligibility varies by account, region, current terms, and usage. This simple single-instance deployment has no HTTPS, auto-scaling, or high availability. Use AWS Billing/Cost Explorer and a budget alert; stop or remove disposable resources after capturing evidence.

This is a single-region development demonstration: RDS is single-AZ with short backup/log retention, Jenkins is a single EC2 host, and no production high availability or load testing is claimed. A production version should add a reviewed multi-AZ database/backup strategy, approval gates, secret rotation, stronger frontend/API CORS restrictions, separate environments, and tested recovery procedures.

## Challenges encountered

- The starter frontend referenced a stylesheet URL that returned 404. Bootstrap is now installed locally and included in the frontend build; the original external theme is no longer required for the app to render.
- PostgreSQL on Amazon Linux initially used `ident` for local TCP authentication. The local development setup was corrected with a database-specific SCRAM rule; the deployed RDS database uses private security-group access and Secrets Manager credentials instead.
- Auth service tests initially reached a real EC2 database because the Prisma mock loaded after the service. Import order was fixed, and the test suite passed (26 tests passed, one existing test remains marked todo).
- The AWS account allowed zero CodeBuild builds. CodeBuild was removed from the design; Jenkins runs the CI/CD pipeline on the dedicated EC2 agent and reaches private RDS over VPC peering.
- AWS required account verification before creating CloudFront and enforced account-level S3 Block Public Access, preventing public S3 hosting. This simplified branch avoids both by serving the React app from Nginx on the app EC2.
- The initial Lambda ZIP exceeded AWS's 250 MiB uncompressed limit. This branch avoids Lambda packaging entirely and deploys the Node service directly to EC2.
- Terraform bootstrap and application state are kept separate in S3, with versioning and native S3 lock files. The application plan was reviewed before applying the VPC, RDS, endpoints, and Jenkins connectivity.

Screenshots, scan reports, and build logs should be captured from actual successful runs and attached to the submission. Do not represent a planned or unexecuted pipeline as a successful deployment.

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
