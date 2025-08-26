#!/bin/bash

# Script to install Velero v1.16.2 for performance testing
# Supports multiple cloud providers and local storage options

set -e

VELERO_VERSION="v1.16.2"
NAMESPACE="velero"

echo "🚀 Installing Velero $VELERO_VERSION for performance testing"
echo "============================================="
echo ""

# Check if velero CLI is installed
if ! command -v velero &> /dev/null; then
    echo "❌ Velero CLI not found. Please install it first:"
    echo ""
    echo "# macOS"
    echo "brew install velero"
    echo ""
    echo "# Linux"
    echo "wget https://github.com/vmware-tanzu/velero/releases/download/$VELERO_VERSION/velero-$VELERO_VERSION-linux-amd64.tar.gz"
    echo "tar -xvf velero-$VELERO_VERSION-linux-amd64.tar.gz"
    echo "sudo mv velero-$VELERO_VERSION-linux-amd64/velero /usr/local/bin/"
    echo ""
    exit 1
fi

echo "✅ Velero CLI found: $(velero version --client-only)"
echo ""

# Provider selection
echo "📋 Select your storage provider:"
echo "1) AWS S3"
echo "2) Google Cloud Storage"
echo "3) Azure Blob Storage"
echo "4) MinIO (local testing)"
echo "5) Skip installation (configure manually)"
echo ""
read -p "Enter choice (1-5): " -n 1 -r PROVIDER_CHOICE
echo ""

case $PROVIDER_CHOICE in
    1)
        echo "🔧 AWS S3 Configuration"
        echo "Please ensure you have:"
        echo "- AWS credentials configured (aws configure or IAM roles)"
        echo "- S3 bucket created"
        echo "- Proper IAM permissions"
        echo ""
        read -p "AWS S3 bucket name: " S3_BUCKET
        read -p "AWS region: " AWS_REGION
        
        # Create credentials file if not exists
        if [ ! -f "aws-credentials" ]; then
            echo "Creating aws-credentials file..."
            cat > aws-credentials << EOF
[default]
aws_access_key_id=$(aws configure get aws_access_key_id)
aws_secret_access_key=$(aws configure get aws_secret_access_key)
EOF
        fi
        
        echo "Installing Velero with AWS provider..."
        velero install \
            --provider aws \
            --plugins velero/velero-plugin-for-aws:$VELERO_VERSION \
            --bucket $S3_BUCKET \
            --secret-file ./aws-credentials \
            --backup-location-config region=$AWS_REGION \
            --snapshot-location-config region=$AWS_REGION \
            --namespace $NAMESPACE
        ;;
    2)
        echo "🔧 Google Cloud Storage Configuration"
        echo "Please ensure you have:"
        echo "- GCP service account key file"
        echo "- GCS bucket created"
        echo "- Proper IAM permissions"
        echo ""
        read -p "GCS bucket name: " GCS_BUCKET
        read -p "Path to service account key file: " GCP_KEY_FILE
        
        echo "Installing Velero with GCP provider..."
        velero install \
            --provider gcp \
            --plugins velero/velero-plugin-for-gcp:$VELERO_VERSION \
            --bucket $GCS_BUCKET \
            --secret-file $GCP_KEY_FILE \
            --namespace $NAMESPACE
        ;;
    3)
        echo "🔧 Azure Blob Storage Configuration"
        echo "Please ensure you have:"
        echo "- Azure storage account and container"
        echo "- Azure credentials configured"
        echo ""
        read -p "Azure storage account: " AZURE_ACCOUNT
        read -p "Azure container name: " AZURE_CONTAINER
        read -p "Azure resource group: " AZURE_RG
        
        # Create credentials file
        echo "Creating Azure credentials file..."
        cat > azure-credentials << EOF
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
AZURE_CLIENT_ID=<your-client-id>
AZURE_CLIENT_SECRET=<your-client-secret>
AZURE_RESOURCE_GROUP=$AZURE_RG
AZURE_CLOUD_NAME=AzurePublicCloud
EOF
        
        echo "⚠️  Please edit azure-credentials file with your client ID and secret"
        echo "Installing Velero with Azure provider..."
        velero install \
            --provider azure \
            --plugins velero/velero-plugin-for-microsoft-azure:$VELERO_VERSION \
            --bucket $AZURE_CONTAINER \
            --secret-file ./azure-credentials \
            --backup-location-config resourceGroup=$AZURE_RG,storageAccount=$AZURE_ACCOUNT \
            --namespace $NAMESPACE
        ;;
    4)
        echo "🔧 MinIO Configuration (Local Testing)"
        echo "This will install MinIO in your cluster for local testing"
        echo ""
        
        # Install MinIO
        kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          value: "admin"
        - name: MINIO_ROOT_PASSWORD
          value: "password123"
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
  type: ClusterIP
EOF
        
        echo "✅ MinIO installed. Setting up Velero..."
        
        # Create credentials for MinIO
        cat > minio-credentials << EOF
[default]
aws_access_key_id = admin
aws_secret_access_key = password123
EOF
        
        echo "Installing Velero with MinIO provider..."
        velero install \
            --provider aws \
            --plugins velero/velero-plugin-for-aws:$VELERO_VERSION \
            --bucket velero-backups \
            --secret-file ./minio-credentials \
            --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.minio.svc.cluster.local:9000 \
            --namespace $NAMESPACE
        ;;
    5)
        echo "⏭️  Skipping automatic installation"
        echo "Please install Velero manually and ensure it's configured properly"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "⏳ Waiting for Velero to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/velero -n $NAMESPACE

echo ""
echo "✅ Velero installation completed!"
echo ""
echo "🔍 Verification:"
velero version
echo ""
echo "📊 Check status:"
echo "kubectl get pods -n $NAMESPACE"
echo "velero backup-location get"
echo ""
echo "🎯 Ready for performance testing!"
echo "Next steps:"
echo "1. Create test resources: ./scripts/run-simple-test.sh"
echo "2. Run backup: ./velero/backup-performance-test.sh"
echo "3. Monitor performance: ./velero/monitor-backup.sh"