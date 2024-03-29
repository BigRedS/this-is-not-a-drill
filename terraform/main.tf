provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project = "this-is-not-a-drill"
      repo    = "https://github.com/BigRedS/this-is-not-a-drill"
    }
  }
}

terraform {
  cloud {
    organization = "bigreds"
    workspaces {
      name = "this-is-not-a-drill"
    }
  }
}

data "terraform_remote_state" "aws_tf_common" {
  backend = "remote"
  config = {
    organization = "bigreds"
    workspaces = {
      name = "aws-tf-common"
    }
  }
}

# Lambda
resource "aws_iam_role" "lambda" {
  name = "thisisnotadrill-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "thisisnotadrill-lambda"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:List*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      }
    ]
  })
}

provider "archive" {}
data "archive_file" "lambda_payload" {
  type        = "zip"
  source_file = "../lambda/notadrill.py"
  output_path = "../lambda/notadrill.zip"
}

resource "aws_lambda_function" "notadrill" {
  function_name    = "notadrill"
  filename         = data.archive_file.lambda_payload.output_path
  role             = aws_iam_role.lambda.arn
  handler          = "notadrill.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("../lambda/notadrill.py")
  environment {
    variables = {
      bucket = aws_s3_bucket.notdrills.arn
    }
  }
}


resource "aws_apigatewayv2_api" "lambda" {
  name          = "thisisnotadrill"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_api_mapping" "lambda" {
  api_id      = aws_apigatewayv2_api.lambda.id
  domain_name = aws_apigatewayv2_domain_name.lambda.id
  stage       = aws_apigatewayv2_stage.lambda.id
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id      = aws_apigatewayv2_api.lambda.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.lambda.id
  integration_type = "AWS_PROXY"

  integration_method   = "POST"
  integration_uri      = aws_lambda_function.notadrill.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_apigatewayv2_route" "lambda" {
  api_id    = aws_apigatewayv2_api.lambda.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_domain_name" "lambda" {
  domain_name = "notadrill-api.avi.pm"
  domain_name_configuration {
    certificate_arn = data.terraform_remote_state.aws_tf_common.outputs.avipm_cert_id
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_route53_record" "lambda" {
  name    = aws_apigatewayv2_domain_name.lambda.domain_name
  type    = "A"
  zone_id = data.terraform_remote_state.aws_tf_common.outputs.avipm_zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.lambda.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.lambda.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }

}

resource "aws_lambda_permission" "lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notadrill.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*/*"
}

# Buckets
resource "aws_s3_bucket" "notdrills" {
  bucket = "notdrills"
  acl    = "public-read"
}

resource "aws_s3_bucket" "website" {
  bucket = var.website-dns-name
  acl    = "public-read"
}
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_policy" "website_access" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "PublicReadGetObject",
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.website.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.website.id}"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "notdrills_access" {
  bucket = aws_s3_bucket.notdrills.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "PublicReadGetObject",
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.notdrills.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.notdrills.id}"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_cors_configuration" "notdrills" {
  bucket = aws_s3_bucket.notdrills.id

  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = [var.website-dns-name]
  }
}

resource "aws_route53_record" "website" {
  zone_id = data.terraform_remote_state.aws_tf_common.outputs.avipm_zone_id
  name    = "thisisnotadrill.avi.pm"
  type    = "A"
  alias {
    name                   = aws_s3_bucket_website_configuration.website.website_domain
    zone_id                = aws_s3_bucket.website.hosted_zone_id
    evaluate_target_health = true
  }
}
