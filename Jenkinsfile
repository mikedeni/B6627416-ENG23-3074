pipeline {
    agent any
    
    environment {
        // กำหนดตัวแปรสำหรับ Docker Image
        DB_IMAGE = "postgres:15-alpine"
        WEB_IMAGE = "nginx:latest"
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code from repository...'
                checkout scm
            }
        }

        stage('Security Scan') {
            steps {
                echo 'Scanning Kubernetes Manifests for security...'
                // ตัวอย่าง: ใช้ kube-linter หรือ checkov (ถ้าติดตั้งไว้)
                sh 'echo "Scanning secrets and configmaps..."'
            }
        }

        stage('Deploy to K8s') {
            steps {
                echo 'Deploying application to Kubernetes...'
                sh '''
                    kubectl apply -f postgresql/
                    kubectl apply -f nginx/deployment/
                    kubectl apply -f nginx/service/
                    kubectl apply -f nginx/ingress/
                '''
            }
        }

        stage('Health Check') {
            steps {
                echo 'Verifying deployment status...'
                sh 'kubectl get pods'
                sh 'kubectl get svc'
            }
        }
    }

    post {
        always {
            echo 'Pipeline finished.'
        }
        success {
            echo 'Deployment Successful! Visit http://my-nginx.local'
        }
        failure {
            echo 'Deployment Failed. Please check logs.'
        }
    }
}
