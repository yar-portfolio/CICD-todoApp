# Project Overview

This repository brings infrastructure provisioning, server configuration, continuous delivery, code analysis, containerization, and AWS deployment into one workflow for a Java Spring Boot Todo application.

## How the system is organized

The automation is split into three clear layers.

### Infrastructure provisioning

```text
Terraform → AWS EC2, Security Groups, ECR, ECS Fargate, ALB, IAM, and CloudWatch Logs
```

Terraform creates and tracks the AWS resources used by the application and the CI/CD platform.

### Server configuration

```text
Ansible Controller → Jenkins Controller, Jenkins Agent, and SonarQube
```

Ansible installs the required packages and configures each EC2 instance for its role.

### Application delivery

```text
GitHub → Jenkins Controller → Jenkins Agent → Maven → Checkstyle → SonarQube → Docker → AWS ECR → AWS ECS Fargate → ALB
```

Jenkins coordinates the build and deployment process. Resource-intensive work runs on a dedicated Agent, while the Controller remains focused on orchestration.

## End-to-end workflow

1. Bootstrap Terraform provisions the S3 remote state bucket and Jenkins Agent IAM Role.
2. Main Terraform provisions the AWS infrastructure.
3. The local setup-ansible.sh script reads Terraform outputs, generates inventory, and launches Ansible on the Ansible Controller.
4. Ansible configures Jenkins Controller, Jenkins Agent, and SonarQube.
5. The Jenkins Pipeline job loads the repository `Jenkinsfile`.
6. The Controller assigns the build to the Jenkins Agent.
7. The Agent verifies its tools and checks out the source code.
8. Maven compiles and tests the application.
9. Checkstyle produces the Java style report.
10. SonarQube analyzes the code and returns the Quality Gate result.
11. Maven packages `target/todolist-app-1.0.0.jar`.
12. Docker builds the application image.
13. Jenkins pushes the image to the `todo-app` ECR repository.
14. Jenkins registers a new revision of the `todo-task` task definition.
15. Jenkins updates `todo-ecs-service` and waits for the service to stabilize.
16. The Application Load Balancer routes HTTP traffic to the healthy ECS task.

## Main components

- **Spring Boot application:** provides the Todo web interface and API behavior.
- **Maven:** compiles, tests, verifies, and packages the application.
- **Checkstyle:** checks Java source formatting and style rules.
- **SonarQube:** analyzes code quality and evaluates the Quality Gate.
- **Docker:** packages the application as a portable container image.
- **Terraform:** creates and manages the AWS infrastructure.
- **Ansible:** configures the EC2 instances and installed services.
- **Jenkins Controller:** stores job configuration and coordinates Pipeline execution.
- **Jenkins Agent:** performs Maven, SonarQube, Docker, and AWS CLI operations.
- **AWS ECR:** stores versioned Docker images.
- **AWS ECS Fargate:** runs the application container.
- **Application Load Balancer:** exposes the application over HTTP.
- **IAM:** provides the ECS execution role and Jenkins deployment permissions.
- **CloudWatch Logs:** collects logs from the ECS container.
- **VPC and Security Groups:** control access between project components.

## AWS infrastructure

Terraform creates:

- a Jenkins Controller EC2 instance;
- a Jenkins Agent EC2 instance;
- an Ansible Controller EC2 instance;
- a SonarQube EC2 instance;
- Security Groups and their ingress rules;
- the `todo-app` ECR repository;
- the `newcluster` ECS cluster;
- the `todo-task` task definition family;
- the `todo-ecs-service` ECS service;
- an Application Load Balancer, target group, and listener;
- the ECS Task Execution IAM role;
- the `/ecs/todo-task` CloudWatch log group.

The current network design uses the default VPC, public subnets, and public IPv4 addresses for the EC2 instances. The main Terraform configuration stores its state in an S3 remote backend with encryption and native S3 state locking. The bootstrap configuration maintains a separate local state.

## Jenkins execution model

The Pipeline targets the `docker-aws-maven` label and runs on the dedicated Jenkins Agent.

The Jenkins Controller handles orchestration. Maven builds, Docker operations, SonarQube scans, and AWS deployment commands run on the Agent.

The main Jenkins Pipeline uses SCM polling to detect changes in the GitHub main branch.

A separate Terraform drift-check Pipeline runs every three minutes and reports its status to Slack.

## DevOps-related repository files

- `Jenkinsfile` — defines the CI/CD pipeline.
- `Dockerfile` — defines the application container image.
- `.dockerignore` — keeps unrelated and sensitive local files out of the Docker build context.
- `pom.xml` — defines Maven dependencies and plugins.
- `terraform/` — contains the Terraform AWS configuration.
- `ansible/` — contains Ansible configuration, inventory, variables, and playbooks.
- `aws/task-definition-template.json` — provides the ECS task definition template used during deployment.
- `scripts/deploy-ecs.sh` — registers a new task revision, updates the ECS service, and waits for stability.
- `scripts/setup-ansible.sh` — creates ansible inventory and configures Jenkins controller, agent and Sonarqube server.
- `data/.gitkeep` — preserves the local data directory in Git.
- `docs/` — contains setup, architecture, and troubleshooting documentation.
- `docs/screenshots/` — contains screenshots from documented releases and deployments.
- `bootstrap/` — contains the Terraform S3 and IAM Role configuration.
- `Jenkinsfile.drift` — defines the infrastructure drift checking pipeline and Slack notification.

## Design choices and trade-offs

- Jenkins, SonarQube, and the application currently use HTTP rather than HTTPS.
- Jenkins credentials and SonarQube integration are configured after provisioning.
- The environment uses the default VPC and public subnets.
- SQLite runs inside the application container without persistent ECS storage.
- Replacing the ECS task also replaces the Todo database.
- The ECS service runs one task because each additional task would have an independent SQLite database.
- The main Terraform state is stored in S3 with encryption and state locking.
- Bootstrap uses a separate local Terraform state.
- Jenkins uses SCM polling rather than public GitHub webhooks.
- Jenkins Agent authenticates to AWS using its EC2 IAM Role.
- Terraform uses the same two selected default VPC subnets for ALB and ECS tasks.
- Jenkins and SonarQube integrations still require manual configuration after Ansible provisioning.

## Technical coverage

The repository covers:

- Linux and EC2 administration;
- Git-based delivery workflows;
- Terraform Infrastructure as Code;
- Ansible configuration management;
- Jenkins controller-agent architecture;
- Maven build automation;
- Docker image lifecycle management;
- SonarQube Quality Gate integration;
- AWS ECR and ECS Fargate deployment;
- load balancing and centralized container logs;
- operational documentation and troubleshooting.
