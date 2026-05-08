#!/bin/bash
# ──────────────────────────────────────────────
# jimmy-log-analyzer — AWS Deployment Script
# Run from: ClaudeCode/log-analyzer/
# ──────────────────────────────────────────────

BUCKET_NAME="jimmy-log-analyzer"
LAMBDA_NAME="jimmy-log-analyzer"
REGION="us-east-1"
ACCOUNT_ID="603509861186"
ROLE_NAME="jimmy-log-analyzer-role"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
API_NAME="jimmy-log-analyzer-api"

echo "=== Step 1: Create IAM Role for Lambda ==="
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }' \
  --region $REGION

# Attach basic Lambda execution
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

echo "Waiting 10s for IAM role to propagate..."
sleep 10

echo "=== Step 2: Package & Deploy Lambda ==="
zip -j lambda.zip lambda_function.py

aws lambda create-function \
  --function-name $LAMBDA_NAME \
  --runtime python3.12 \
  --role $ROLE_ARN \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda.zip \
  --timeout 30 \
  --region $REGION

echo "=== Step 3: Create API Gateway ==="
API_ID=$(aws apigateway create-rest-api \
  --name $API_NAME \
  --region $REGION \
  --query 'id' --output text)

echo "API ID: $API_ID"

# Get root resource
ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --region $REGION \
  --query 'items[0].id' --output text)

# Create /analyze resource
RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part analyze \
  --region $REGION \
  --query 'id' --output text)

# POST method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE \
  --region $REGION

# OPTIONS method for CORS
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method OPTIONS \
  --authorization-type NONE \
  --region $REGION

# Lambda integration for POST
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_NAME}"

aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
  --region $REGION

# Lambda integration for OPTIONS (same Lambda handles CORS)
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method OPTIONS \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
  --region $REGION

# Grant API Gateway permission to invoke Lambda
aws lambda add-permission \
  --function-name $LAMBDA_NAME \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/analyze" \
  --region $REGION

# Deploy API
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --region $REGION

API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod/analyze"
echo ""
echo "=== API Gateway URL ==="
echo "$API_URL"
echo ""
echo ">>> Paste this URL into index.html as API_ENDPOINT <<<"

echo "=== Step 4: Create S3 Bucket ==="
aws s3 mb s3://$BUCKET_NAME --region $REGION

aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"PublicRead\",
    \"Effect\": \"Allow\",
    \"Principal\": \"*\",
    \"Action\": \"s3:GetObject\",
    \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/*\"
  }]
}"

aws s3 website s3://$BUCKET_NAME \
  --index-document index.html

echo "=== Step 5: Upload Site ==="
aws s3 cp index.html s3://$BUCKET_NAME/index.html --content-type text/html

echo "=== Step 6: Invalidate CloudFront Cache ==="
CF_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?contains(Origins.Items[0].DomainName, '${BUCKET_NAME}')].Id | [0]" \
  --output text 2>/dev/null)

if [ -n "$CF_ID" ] && [ "$CF_ID" != "None" ]; then
  aws cloudfront create-invalidation --distribution-id "$CF_ID" --paths "/*" --output text > /dev/null
  echo "CloudFront invalidation started for $CF_ID"
else
  echo "(no CloudFront distribution found — skipping)"
fi

echo ""
echo "=== DONE ==="
echo "Site URL: http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"
echo "Remember to update API_ENDPOINT in index.html and re-upload if you haven't already."

# Cleanup
rm -f lambda.zip
