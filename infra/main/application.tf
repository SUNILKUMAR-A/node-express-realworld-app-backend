locals {
  lambda_zip_path = abspath("${path.module}/${var.lambda_package_path}")
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.name}-api"
  description      = "RealWorld Express API"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs22.x"
  handler          = "main.handler"
  s3_bucket        = aws_s3_bucket.migration_artifacts.bucket
  s3_key           = var.lambda_package_key
  source_code_hash = filebase64sha256(local.lambda_zip_path)
  timeout          = 30
  memory_size      = 512

  vpc_config {
    subnet_ids         = aws_subnet.database[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      APP_SECRET_ARN = aws_secretsmanager_secret.app_credentials.arn
      NODE_ENV       = "production"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_runtime,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = {
    Name = "${local.name}-api"
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["authorization", "content-type"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = {
    Name = "${local.name}-api"
  }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
    })
  }

  tags = {
    Name = "${local.name}-api"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name}-api"
  retention_in_days = 7

  tags = {
    Name = "${local.name}-api-gateway-logs"
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_s3_bucket" "frontend" {
  bucket = "realworld-frontend-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.name}-frontend"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend"
  description                       = "CloudFront access to the private frontend bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "frontend-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name}-frontend"
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_cloudfront.json
}

data "aws_iam_policy_document" "frontend_cloudfront" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name}-api-lambda-errors"
  alarm_description   = "Lambda API errors exceed the development threshold."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }
}

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${local.name}-application"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Lambda requests and errors"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.api.function_name, { stat = "Sum" }],
            [".", "Errors", ".", ".", { stat = "Sum" }],
            [".", "Throttles", ".", ".", { stat = "Sum" }],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Lambda duration"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "Average" }],
            [".", "Duration", ".", ".", { stat = "p95" }],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU and connections"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.app.identifier, { stat = "Average" }],
            [".", "DatabaseConnections", ".", ".", { stat = "Average", yAxis = "right" }],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway requests and latency"
          region = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.api.id, "Stage", "$default", { stat = "Sum" }],
            [".", "Latency", ".", ".", ".", ".", { stat = "Average", yAxis = "right" }],
            [".", "5xx", ".", ".", ".", ".", { stat = "Sum", yAxis = "left" }],
          ]
          period = 300
        }
      },
    ]
  })
}
