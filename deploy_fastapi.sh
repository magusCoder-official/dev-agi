#!/bin/bash

# Define the project directory
PROJECT_DIR="fastapi_app"

# Create the project directory
mkdir -p $PROJECT_DIR

# Navigate to the project directory
cd $PROJECT_DIR

# Create a virtual environment
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate

# Create requirements.txt
cat <<EOL > requirements.txt
fastapi
uvicorn
boto3
cryptography
pydantic
EOL

# Install dependencies
pip install -r requirements.txt

# Create main.py
cat <<EOL > main.py
from fastapi import FastAPI, HTTPException
from models import AWSCredentials, ECSClusterModel, VPCModel, LambdaModel, S3UploadModel, S3BucketModel, CognitoGroupModel
from cryptography.fernet import Fernet
import boto3
import json

app = FastAPI()

# Encryption key for credentials
key = Fernet.generate_key()
cipher_suite = Fernet(key)

# Endpoint to store AWS credentials securely
@app.post("/store_credentials")
def store_credentials(credentials: AWSCredentials):
    encrypted_access_key = cipher_suite.encrypt(credentials.AWS_ACCESS_KEY.encode())
    encrypted_secret_key = cipher_suite.encrypt(credentials.AWS_SECRET_KEY.encode())
    with open('aws_credentials.json', 'w') as f:
        json.dump({
            'AWS_ACCESS_KEY': encrypted_access_key.decode(),
            'AWS_SECRET_KEY': encrypted_secret_key.decode()
        }, f)
    return {"message": "Credentials stored securely"}

# Function to load and decrypt AWS credentials
def load_credentials():
    with open('aws_credentials.json', 'r') as f:
        data = json.load(f)
    encrypted_access_key = data['AWS_ACCESS_KEY']
    encrypted_secret_key = data['AWS_SECRET_KEY']
    aws_access_key = cipher_suite.decrypt(encrypted_access_key.encode()).decode()
    aws_secret_key = cipher_suite.decrypt(encrypted_secret_key.encode()).decode()
    return aws_access_key, aws_secret_key

# Initialize boto3 clients
def initialize_clients():
    aws_access_key, aws_secret_key = load_credentials()
    ecs_client = boto3.client('ecs', aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    ec2_client = boto3.client('ec2', aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    lambda_client = boto3.client('lambda', aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    s3_client = boto3.client('s3', aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    cognito_client = boto3.client('cognito-idp', aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    return ecs_client, ec2_client, lambda_client, s3_client, cognito_client

# Endpoint to create ECS cluster
@app.post("/create_ecs_cluster")
def create_ecs_cluster(cluster: ECSClusterModel):
    ecs_client, _, _, _, _ = initialize_clients()
    response = ecs_client.create_cluster(clusterName=cluster.cluster_name)
    return response

# Endpoint to create VPC
@app.post("/create_vpc")
def create_vpc(vpc: VPCModel):
    _, ec2_client, _, _, _ = initialize_clients()
    response = ec2_client.create_vpc(CidrBlock=vpc.cidr_block)
    return response

# Endpoint to create Lambda function from Dockerized container
@app.post("/create_lambda_function")
def create_lambda_function(lambda_function: LambdaModel):
    _, _, lambda_client, _, _ = initialize_clients()
    response = lambda_client.create_function(
        FunctionName=lambda_function.function_name,
        Code={'ImageUri': lambda_function.image_uri},
        Role=lambda_function.role_arn,
        PackageType='Image'
    )
    return response

# Endpoint to upload file to S3
@app.post("/upload_file_to_s3")
def upload_file_to_s3(upload: S3UploadModel):
    _, _, _, s3_client, _ = initialize_clients()
    response = s3_client.upload_file(upload.file_name, upload.bucket_name, upload.object_name or upload.file_name)
    return {"message": "File uploaded successfully"}

# Endpoint to create S3 bucket
@app.post("/create_s3_bucket")
def create_s3_bucket(bucket: S3BucketModel):
    _, _, _, s3_client, _ = initialize_clients()
    response = s3_client.create_bucket(Bucket=bucket.bucket_name)
    return response

# Endpoint to create Cognito group
@app.post("/create_cognito_group")
def create_cognito_group(group: CognitoGroupModel):
    _, _, _, _, cognito_client = initialize_clients()
    response = cognito_client.create_group(
        UserPoolId=group.user_pool_id,
        GroupName=group.group_name
    )
    return response
EOL

# Create models.py
cat <<EOL > models.py
from pydantic import BaseModel, Field
from typing import Optional

class AWSCredentials(BaseModel):
    AWS_ACCESS_KEY: str = Field(..., min_length=16, max_length=128)
    AWS_SECRET_KEY: str = Field(..., min_length=16, max_length=128)

class ECSClusterModel(BaseModel):
    cluster_name: str = Field(..., min_length=1, max_length=255)

class VPCModel(BaseModel):
    cidr_block: str = Field(..., regex=r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$')

class LambdaModel(BaseModel):
    function_name: str = Field(..., min_length=1, max_length=255)
    image_uri: str = Field(..., min_length=1, max_length=255)
    role_arn: str = Field(..., min_length=20, max_length=2048)

class S3UploadModel(BaseModel):
    bucket_name: str = Field(..., min_length=3, max_length=63)
    file_name: str = Field(..., min_length=1, max_length=1024)
    object_name: Optional[str] = None

class S3BucketModel(BaseModel):
    bucket_name: str = Field(..., min_length=3, max_length=63)

class CognitoGroupModel(BaseModel):
    user_pool_id: str = Field(..., min_length=1, max_length=55)
    group_name: str = Field(..., min_length=1, max_length=128)
EOL

# Deactivate the virtual environment
deactivate

echo "FastAPI application setup complete."