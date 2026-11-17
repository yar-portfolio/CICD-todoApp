# CI/CD Todo App

This repository contains a Java Spring Boot Todo application and the automation required to provision, configure, build, test, and deploy it on AWS.

Terraform manages the infrastructure, Ansible configures the EC2 hosts, and Jenkins carries the application from source code to a running ECS Fargate service. Docker, SonarQube, AWS ECR, an Application Load Balancer, and CloudWatch complete the delivery path.

## Architecture

The project has three automation layers:

1. **Terraform** creates the AWS infrastructure.
2. **Ansible** configures Jenkins Controller, Jenkins Agent, and SonarQube.
3. **Jenkins** builds, checks, packages, and deploys the application.

Application delivery flow:

```text
GitHub → Jenkins Controller → Jenkins Agent → Maven → Checkstyle → SonarQube → Docker → AWS ECR → AWS ECS Fargate → Application Load Balancer
```

The Jenkins pipeline performs these steps:

1. Verifies the required tools on the Jenkins Agent.
2. Fetches the source code from GitHub.
3. Runs Maven verification.
4. Runs Checkstyle analysis.
5. Sends code analysis to SonarQube.
6. Waits for the SonarQube Quality Gate.
7. Packages the Spring Boot application.
8. Builds a Docker image.
9. Pushes the image to AWS ECR.
10. Registers a new ECS task definition revision.
11. Updates the ECS service and waits until it becomes stable.

## Tech stack

- **Application:** Java 21, Spring Boot
- **Build:** Maven 3.9
- **CI/CD:** Jenkins Pipeline
- **Code quality:** Checkstyle, SonarQube Quality Gate
- **Containerization:** Docker
- **Cloud registry:** AWS ECR
- **Cloud runtime:** AWS ECS Fargate
- **Load balancing:** AWS Application Load Balancer
- **Infrastructure as Code:** Terraform
- **Server configuration:** Ansible
- **Logging:** AWS CloudWatch Logs
- **Version control:** Git, GitHub

## Jenkins agent-based execution

The pipeline runs on a dedicated Jenkins Agent with the label `docker-aws-maven`.

The Jenkins Controller manages jobs and coordinates the pipeline. The Jenkins Agent performs the actual CI/CD work:

- Maven build and tests;
- Checkstyle and SonarQube analysis;
- Docker image build and push to ECR;
- ECS task definition registration and service deployment.

This keeps build tools and Docker operations away from the Jenkins Controller.

## Repository structure

- `src/` — Spring Boot application source code and tests.
- `data/` — keeps the local application data directory in Git through `.gitkeep`.
- `Dockerfile` — Docker image definition.
- `.dockerignore` — limits the Docker build context to the Dockerfile and application JAR.
- `Jenkinsfile` — Jenkins CI/CD pipeline.
- `Jenkinsfile.drift` — scheduled Terraform configuration checks and Slack notifications.
- `bootstrap/` — provisions the Terraform S3 state bucket and Jenkins Agent IAM Role.
- `scripts/setup-ansible.sh` — generates Ansible inventory from Terraform outputs and automates the configuration of EC2 hosts.
- `pom.xml` — Maven project configuration.
- `aws/` — AWS deployment templates.
- `aws/task-definition-template.json` — ECS task definition template used by Jenkins.
- `scripts/deploy-ecs.sh` — registers a new task definition revision and updates the ECS service.
- `terraform/` — Terraform configuration for the AWS infrastructure.
- `ansible/` — Ansible inventory, variables, and playbooks for EC2 configuration.
- `docs/` — project documentation.
- `docs/screenshots/` — screenshots from documented releases and successful deployments.

## Run locally

Prerequisites:

- Java 21;
- Maven 3.9 or newer;
- Git.

Clone the repository:

```bash
git clone https://github.com/yar-portfolio/CICD-todoApp.git
cd CICD-todoApp
```

Run Maven verification:

```bash
mvn clean verify
```

Start the application:

```bash
mvn spring-boot:run
```

Open:

```text
http://localhost:8080
```

The application expects the `data/` directory in the project root. The repository keeps this directory through `data/.gitkeep`.

More details are available in `docs/02-local-run.md`.

## Run with Docker

Build the application artifact:

```bash
mvn clean package -DskipTests
```

Build the Docker image:

```bash
docker build -t todo-app:local .
```

Run the container:

```bash
docker run --rm -p 8080:8080 todo-app:v1.0
```

More details are available in `docs/03-docker.md`.

## Deploy the complete environment

The complete deployment sequence is documented in `docs/07-terraform-ansible.md`.

In short:

1. Run Terraform in `bootstrap/` to create the S3 state bucket and Jenkins Agent IAM Role.
2. Configure `terraform/backend.tf` with the S3 bucket name created by bootstrap.
3. Run Terraform in `terraform/` to provision the AWS infrastructure.
4. Load the EC2 SSH private key into the local SSH agent.
5. Run `bash scripts/setup-ansible.sh` to configure Jenkins Controller, Jenkins Agent, and SonarQube.
6. Complete the manual Jenkins, SonarQube, and Slack integration settings.
7. Create and run the main Jenkins Pipeline.
8. Configure the separate Terraform drift-check job.

The main Jenkins Pipeline uses SCM polling to check the GitHub `main` branch approximately every three minutes. No inbound GitHub webhook is required.

The drift-check Pipeline runs Terraform plan every three minutes and sends Slack notifications when its build status changes.

The current version does not configure an automatic GitHub webhook trigger.

## Project screenshots

Screenshots are grouped by project version inside `docs/screenshots/`.

The repository currently includes screenshots for:

- `v1.0-devops-foundation`;
- `v1.1-ecs-task-revision-deployment`;
- `v1.3-terraform-ansible-integration`.

## Documentation

- `docs/01-project-overview.md` — project purpose, architecture, and workflow.
- `docs/02-local-run.md` — local build and run instructions.
- `docs/03-docker.md` — Docker image build and container run instructions.
- `docs/04-jenkins-pipeline.md` — Jenkins tools, plugins, integrations, credentials, and pipeline stages.
- `docs/05-aws-ecr-ecs.md` — AWS architecture, IAM permissions, ECR, ECS, and ALB deployment details.
- `docs/06-troubleshooting.md` — common Terraform, Ansible, Jenkins, SonarQube, Docker, ECR, and ECS issues.
- `docs/07-terraform-ansible.md` — complete infrastructure and configuration instructions.

## Data persistence

The application stores SQLite data inside the container at `/app/data/TodoList.db`. The current ECS task definition does not attach persistent storage, so replacing a task also replaces its database.

Keep `ecs_desired_count = 1` with this design. Running multiple tasks would create a separate SQLite database for each task.

## Security

The Jenkins Agent uses an EC2 IAM Role to obtain temporary AWS credentials. Permanent AWS access keys are not required by the Jenkins Pipeline.

SSH private keys, SonarQube tokens, Slack tokens, and Jenkins credentials must be managed outside Git.

The main Terraform state is stored in an encrypted S3 backend with state locking. Bootstrap maintains its own separate local Terraform state.

Before committing screenshots, make sure that they do not expose access keys, tokens, passwords, private keys, or other sensitive information.
