pipeline {

    agent {
        label 'docker-aws-maven'
    }

    triggers {
      pollSCM('H/3 * * * *')
    }

    tools {
        maven "MAVEN3.9"
        jdk "JDK21"
    }


    environment {
    AWS_REGION = 'us-east-1'
    ECR_REPOSITORY = 'todo-app'
    ECS_CLUSTER = 'newcluster'
    ECS_SERVICE = 'todo-ecs-service'
    ECS_TASK_FAMILY = 'todo-task'
    CONTAINER_NAME = 'todo'
}
  stages {

        stage('VERIFY AGENT') {
         steps {
         sh '''
            echo "Running on: $(hostname)"
            whoami
            java -version
            mvn -version
            git --version
            docker --version
            aws --version
            '''
          }
        }

        stage('Fetch code') {
            steps {
               git branch: 'main', url: 'https://github.com/yar-portfolio/CICD-todoApp.git'
            }

        }

        stage('UNIT TEST') {
            steps{
                sh 'mvn clean verify'
            }
        }

        stage('Checkstyle Analysis') {
            steps{
                sh 'mvn checkstyle:checkstyle'
            }
        }

        stage("Sonar Code Analysis") {
            environment {
                scannerHome = tool 'sonar8.0'
            }
            steps {
              withSonarQubeEnv('sonarserver') {
                sh """${scannerHome}/bin/sonar-scanner -Dsonar.projectKey=todo-sonar \
                   -Dsonar.projectName=todo-sonar \
                   -Dsonar.projectVersion=1.0 \
                   -Dsonar.sources=src/ \
                   -Dsonar.java.binaries=target/classes/ \
                   -Dsonar.junit.reportPath=target/surefire-reports/ \
                   -Dsonar.java.checkstyle.reportPaths=target/checkstyle-result.xml"""
              }
            }
        }

        stage("Quality Gate") {
            steps {
              timeout(time: 1, unit: 'HOURS') {
                waitForQualityGate abortPipeline: true
              }
            }
          }

        stage('Build'){
            steps{
               sh 'mvn package -DskipTests'
            }

            post {
               success {
                  echo 'Now Archiving it...'
                  archiveArtifacts artifacts: '**/target/todolist-app-1.0.0.jar'
               }
            }
        }

         stage('Build and Push to ECR') {
	   steps {
	     script {
	       def accountId = sh(
	         script: 'aws sts get-caller-identity --query Account --output text',
		 returnStdout: true
		 ).trim()

		 env.ECR_REGISTRY = "${accountId}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

		 env.IMAGE_URI = "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.BUILD_NUMBER}"
		 }

	     sh '''
                set -eu

                # Login to Amazon ECR
                aws ecr get-login-password \
                    --region "$AWS_REGION" |
                docker login \
                    --username AWS \
                    --password-stdin "$ECR_REGISTRY"

                # Build Docker image
                docker build -t "$IMAGE_URI" .

                # Push image to ECR
                docker push "$IMAGE_URI"
            '''
	   }
	 }

	 stage('Deploy to ECS') {
           steps {
               sh '''
                chmod +x scripts/deploy-ecs.sh
                ./scripts/deploy-ecs.sh
               '''
            }
          }


  }
}
