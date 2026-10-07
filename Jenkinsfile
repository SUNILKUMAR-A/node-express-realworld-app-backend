pipeline {
  agent { label 'aws-builder' }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  parameters {
    string(name: 'DB_HOST', defaultValue: '', description: 'Private RDS endpoint from Terraform output')
    string(name: 'DB_PORT', defaultValue: '5432', description: 'RDS PostgreSQL port')
    string(name: 'DB_NAME', defaultValue: 'realworld', description: 'PostgreSQL database name')
    string(name: 'RDS_MASTER_SECRET_ARN', defaultValue: '', description: 'RDS-managed master secret ARN')
    string(name: 'APP_SECRET_ARN', defaultValue: '', description: 'Application database secret ARN')
    string(name: 'APP_PUBLIC_URL', defaultValue: '', description: 'Optional URL for the agent EC2, e.g. http://198.51.100.10')
  }

  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    FRONTEND_REPOSITORY = 'https://github.com/SUNILKUMAR-A/react-redux-realworld-app-frontent.git'
    FRONTEND_BRANCH = 'master'
    NPM_CONFIG_CACHE = '/home/ec2-user/.cache/jenkins/npm'
    APP_DB_USERNAME = 'realworld_app'
    DATABASE_URL = 'postgresql://localhost:5432/realworld?schema=public'
    DIRECT_URL = 'postgresql://localhost:5432/realworld?schema=public'
  }

  stages {
    stage('Checkout frontend') {
      steps {
        sh 'git clone --depth 1 --branch "$FRONTEND_BRANCH" "$FRONTEND_REPOSITORY" frontend'
      }
    }

    stage('Build, test, and scan') {
      steps {
        sh '''
          set -eu
          mkdir -p "$NPM_CONFIG_CACHE"
          npm ci --cache "$NPM_CONFIG_CACHE"
          npx prisma generate
          npx nx build api --configuration=production
          npx nx test api --runInBand
          npm audit --json > backend-npm-audit.json || true
          (
            cd frontend
            npm ci --legacy-peer-deps --cache "$NPM_CONFIG_CACHE"
            npm audit --json > ../frontend-npm-audit.json || true
            NODE_OPTIONS=--openssl-legacy-provider REACT_APP_API_ROOT=/api npm run build
          )
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: '*npm-audit.json', allowEmptyArchive: true
        }
      }
    }

    stage('Validate deployment configuration') {
      steps {
        sh '''
          set -eu
          test -n "$DB_HOST" || { echo "Build parameter DB_HOST is empty"; exit 1; }
          test -n "$DB_PORT" || { echo "Build parameter DB_PORT is empty"; exit 1; }
          test -n "$DB_NAME" || { echo "Build parameter DB_NAME is empty"; exit 1; }
          test -n "$RDS_MASTER_SECRET_ARN" || { echo "Build parameter RDS_MASTER_SECRET_ARN is empty"; exit 1; }
          test -n "$APP_SECRET_ARN" || { echo "Build parameter APP_SECRET_ARN is empty"; exit 1; }
          command -v node
          command -v npm
          command -v aws
          command -v nginx || true
          aws sts get-caller-identity
          python3 -c 'import os,socket; connection=socket.create_connection((os.environ["DB_HOST"], int(os.environ["DB_PORT"])), timeout=5); connection.close()'
          aws secretsmanager get-secret-value --secret-id "$RDS_MASTER_SECRET_ARN" --query SecretString --output text >/dev/null
          aws secretsmanager get-secret-value --secret-id "$APP_SECRET_ARN" --query SecretString --output text >/dev/null
          sudo -n true
        '''
      }
    }

    stage('Run database migrations') {
      steps {
        sh '''
          set -eu
          export APP_DB_USERNAME
          node scripts/provision-app-db-user.js
        '''
      }
    }

    stage('Prepare application release') {
      steps {
        sh '''
          set -eu
          RELEASE_ID="${GIT_COMMIT}-${BUILD_NUMBER}"
          RELEASE_DIR="/opt/realworld/releases/${RELEASE_ID}"
          FRONTEND_RELEASE_DIR="/opt/realworld/frontend-releases/${RELEASE_ID}"
          mkdir -p dist/api/src/prisma
          cp -a src/prisma/schema.prisma src/prisma/migrations dist/api/src/prisma/
          npm ci --omit=dev --cache "$NPM_CONFIG_CACHE" --prefix dist/api
          mkdir -p dist/api/node_modules/@prisma dist/api/node_modules/.prisma
          rm -rf dist/api/node_modules/@prisma/client dist/api/node_modules/.prisma/client
          cp -a node_modules/@prisma/client dist/api/node_modules/@prisma/
          cp -a node_modules/.prisma/client dist/api/node_modules/.prisma/
          sudo dnf install -y nginx
          sudo install -d -o ec2-user -g ec2-user /opt/realworld/releases
          sudo install -d -o ec2-user -g ec2-user "$RELEASE_DIR"
          cp -a dist/api/. "$RELEASE_DIR/"
          sudo chown -R ec2-user:ec2-user "$RELEASE_DIR"
          sudo install -d -o ec2-user -g ec2-user /opt/realworld/frontend-releases
          sudo install -d -o ec2-user -g ec2-user "$FRONTEND_RELEASE_DIR"
          cp -a frontend/build/. "$FRONTEND_RELEASE_DIR/"
          sudo chown -R ec2-user:ec2-user "$FRONTEND_RELEASE_DIR"
          sudo ln -sfn "$FRONTEND_RELEASE_DIR" /opt/realworld/frontend-current
          sudo ln -sfn "$RELEASE_DIR" /opt/realworld/current
          printf 'APP_SECRET_ARN=%s\\nAWS_REGION=%s\\nPORT=3000\\nNODE_ENV=production\\n' "$APP_SECRET_ARN" "$AWS_DEFAULT_REGION" |
            sudo tee /etc/realworld-api.env >/dev/null
          sudo chmod 600 /etc/realworld-api.env
          NODE_BIN="$(command -v node)"
          printf '[Unit]\\nDescription=RealWorld Express API\\nAfter=network-online.target\\nWants=network-online.target\\n\\n[Service]\\nType=simple\\nUser=ec2-user\\nGroup=ec2-user\\nWorkingDirectory=/opt/realworld/current\\nEnvironmentFile=/etc/realworld-api.env\\nExecStart=%s /opt/realworld/current/main.js\\nRestart=on-failure\\nRestartSec=5\\n\\n[Install]\\nWantedBy=multi-user.target\\n' "$NODE_BIN" |
            sudo tee /etc/systemd/system/realworld-api.service >/dev/null
          printf 'server {\\n  listen 80;\\n  server_name _;\\n  root /opt/realworld/frontend-current;\\n  index index.html;\\n  location /api/ {\\n    proxy_pass http://127.0.0.1:3000;\\n    proxy_http_version 1.1;\\n    proxy_set_header Host $host;\\n    proxy_set_header X-Real-IP $remote_addr;\\n    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\\n    proxy_set_header X-Forwarded-Proto $scheme;\\n  }\\n  location / {\\n    try_files $uri $uri/ /index.html;\\n  }\\n}\\n' |
            sudo tee /etc/nginx/conf.d/realworld.conf >/dev/null
          sudo nginx -t
          sudo systemctl daemon-reload
          sudo systemctl enable --now realworld-api
          sudo systemctl restart realworld-api
          sudo systemctl enable --now nginx
          sudo systemctl restart nginx
        '''
      }
    }

    stage('Smoke test') {
      steps {
        sh '''
          set -eu
          curl --fail --retry 12 --retry-delay 5 http://127.0.0.1/
          curl --fail --retry 12 --retry-delay 5 http://127.0.0.1/api/tags
          if [ -n "$APP_PUBLIC_URL" ]; then
            curl --fail --retry 6 --retry-delay 5 "$APP_PUBLIC_URL/"
            curl --fail --retry 6 --retry-delay 5 "$APP_PUBLIC_URL/api/tags"
            echo "Application URL: $APP_PUBLIC_URL"
          fi
        '''
      }
    }
  }

  post {
    always {
      deleteDir()
    }
  }
}
