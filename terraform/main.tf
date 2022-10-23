provider "aws" {
  region = var.region
}

resource "aws_iam_role" "lambda" {
  name = "lambdaRole"
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
  name = "LambdaPolicy"
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
  function_name = "notadrill"
  filename      = data.archive_file.lambda_payload.output_path
  role          = aws_iam_role.lambda.arn
  handler       = "notadrill.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = filebase64sha256("../lambda/notadrill.py")
  environment {
    variables = {
      bucket = aws_s3_bucket.notdrills.arn
    }
  }
}

resource "aws_s3_bucket" "notdrills" {
  bucket = "notdrills"
  acl = "public-read"
}

resource "aws_s3_bucket" "thisisnotadrill" {
  bucket = "thisisnotadrill"
  acl = "public-read"
}

resource "aws_apigatewayv2_api" "lambda-api" {
    name          = "v2-http-api"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda-stage" {
    api_id      = aws_apigatewayv2_api.lambda-api.id
    name        = "$default"
    auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda-integration" {
    api_id           = aws_apigatewayv2_api.lambda-api.id
    integration_type = "AWS_PROXY"

    integration_method   = "POST"
    integration_uri      = aws_lambda_function.notadrill.invoke_arn
    passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_apigatewayv2_route" "lambda-route" {
    api_id             = aws_apigatewayv2_api.lambda-api.id
    route_key          = "GET /{proxy+}"
    target             = "integrations/${aws_apigatewayv2_integration.lambda-integration.id}"
}



resource "aws_lambda_permission" "api-gw" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.notadrill.arn
    principal     = "apigateway.amazonaws.com"

    source_arn = "${aws_apigatewayv2_api.lambda-api.execution_arn}/*/*/*"
}
