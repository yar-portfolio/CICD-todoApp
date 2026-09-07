pipeline {
    agent {
        label 'docker-aws-maven'
    }
    tools {
        maven "MAVEN3.9"
        jdk "JDK21"
    }


    environment {
    AWS_REGION = 'us-east-1'
    ECR_REGISTRY = '551647579168.dkr.ecr.us-east-1.amazonaws.com'
    ECR_REPOSITORY = 'todo-app'
    ECS_CLUSTER = 'newcluster'
    ECS_SERVICE = 'todo-ecs-service'
    ECS_TASK_FAMILY = 'todo-task'
    CONTAINER_NAME = 'todo'

    IMAGE_TAG = "${BUILD_NUMBER}"
    IMAGE_URI = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

    registryCredential = 'ecr:us-east-1:awscreds'
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

        stage('Build App Image') {
          steps {

            script {
                dockerImage = docker.build("${IMAGE_URI}", "./")
                }
          }

        }

        stage('Upload App Image') {
          steps{
            script {
              docker.withRegistry("https://${ECR_REGISTRY}", registryCredential ) {
                dockerImage.push()
              }
            }
          }
        }

         stage('Deploy to ECS') {
           steps {
             withAWS(credentials: 'awscreds', region: "${AWS_REGION}") {
               sh '''
                chmod +x scripts/deploy-ecs.sh
                ./scripts/deploy-ecs.sh
               '''
              }
            }
          }


  }
}
