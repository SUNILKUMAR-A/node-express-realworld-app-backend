data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "migration_artifacts" {
  bucket = "realworld-devops-artifacts-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.name}-migration-artifacts"
  }
}

resource "aws_s3_bucket_public_access_block" "migration_artifacts" {
  bucket                  = aws_s3_bucket.migration_artifacts.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "migration_artifacts" {
  bucket = aws_s3_bucket.migration_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "migration_artifacts" {
  bucket = aws_s3_bucket.migration_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "migration_artifacts" {
  bucket = aws_s3_bucket.migration_artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    filter {
      prefix = "migration/"
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_cloudwatch_log_group" "migration" {
  name              = "/aws/codebuild/${local.name}-migrations"
  retention_in_days = 7

  tags = {
    Name = "${local.name}-migration-logs"
  }
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "migration" {
  name               = "${local.name}-migration-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json

  tags = {
    Name = "${local.name}-migration-codebuild"
  }
}

data "aws_iam_policy_document" "migration_runtime" {
  statement {
    sid       = "ReadMigrationArtifact"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.migration_artifacts.arn}/migration/*"]
  }

  statement {
    sid       = "ReadMigrationArtifactBucket"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:GetBucketAcl"]
    resources = [aws_s3_bucket.migration_artifacts.arn]
  }

  statement {
    sid       = "ReadRdsMasterSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.app.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "WriteApplicationSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:PutSecretValue"]
    resources = [aws_secretsmanager_secret.app_credentials.arn]
  }

  statement {
    sid    = "WriteMigrationLogEvents"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.migration.arn}:*"]
  }

  statement {
    sid       = "CreateMigrationLogGroup"
    effect = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["${aws_cloudwatch_log_group.migration.arn}:*"]
  }

  statement {
    sid    = "ManageBuildNetworkInterfaces"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "migration_runtime" {
  name   = "${local.name}-migration-runtime"
  role   = aws_iam_role.migration.id
  policy = data.aws_iam_policy_document.migration_runtime.json
}

resource "aws_codebuild_project" "migration" {
  name         = "${local.name}-migrations"
  description  = "Run Prisma migrations against private RDS and provision the restricted application database user."
  service_role = aws_iam_role.migration.arn
  build_timeout = 30

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.migration_artifacts.bucket}/migration/migration-artifact.zip"
    buildspec = "buildspec-migrate.yml"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "RDS_MASTER_SECRET"
      value = aws_db_instance.app.master_user_secret[0].secret_arn
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "APP_SECRET_ARN"
      value = aws_secretsmanager_secret.app_credentials.arn
    }

    environment_variable {
      name  = "DB_HOST"
      value = aws_db_instance.app.address
    }

    environment_variable {
      name  = "DB_PORT"
      value = tostring(aws_db_instance.app.port)
    }

    environment_variable {
      name  = "DB_NAME"
      value = aws_db_instance.app.db_name
    }

    environment_variable {
      name  = "APP_DB_USERNAME"
      value = "realworld_app"
    }
  }

  vpc_config {
    vpc_id             = aws_vpc.app.id
    subnets            = [aws_subnet.database[0].id]
    security_group_ids = [aws_security_group.migrations.id]
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.migration.name
    }

    s3_logs {
      status = "DISABLED"
    }
  }

  depends_on = [
    aws_iam_role_policy.migration_runtime,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.secrets_manager,
    aws_vpc_endpoint.logs,
  ]

  tags = {
    Name = "${local.name}-migrations"
  }
}
