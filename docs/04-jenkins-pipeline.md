# Jenkins Pipeline

The CI/CD workflow is defined in `Jenkinsfile`. It builds and analyzes the application, publishes a Docker image to AWS ECR, registers a new ECS task definition revision, and rolls the ECS service forward to that revision.

## Pipeline overview

```text
Verify Agent → Fetch Code → Maven Verify → Checkstyle → SonarQube → Quality Gate → Package → Docker Build → ECR Push → ECS Deployment
```

## Execution model

The Pipeline runs on a dedicated Jenkins Agent with this label:

```text
docker-aws-maven
```

The Jenkins Controller coordinates the job. The Jenkins Agent performs:

- Maven builds and tests;
- Checkstyle and SonarQube analysis;
- Docker image build and push;
- AWS CLI commands and ECS deployment.

The Jenkins node label must exactly match the label in `Jenkinsfile`.

## Required Jenkins plugins

Install these plugins on the Jenkins Controller:

- **Pipeline** — runs the declarative `Jenkinsfile`.
- **Git** — checks out the repository.
- **SSH Build Agents** — connects the Jenkins Controller to the Agent through SSH.
- **SonarQube Scanner for Jenkins** — configures the scanner and Quality Gate integration.
- **Credentials Binding** — exposes credentials securely to Pipeline steps.
- **Slack Notification** — sends infrastructure check notifications to Slack.

Required dependency plugins are installed automatically by Jenkins.

## Jenkins tools

Open **Manage Jenkins → Tools** and configure these exact names:

| Tool | Jenkins name | Agent installation |
|---|---|---|
| JDK | `JDK21` | `/usr/lib/jvm/java-21-openjdk-amd64` |
| Maven | `MAVEN3.9` | `/opt/apache-maven-3.9.11` |
| SonarQube Scanner | `sonar8.0` | Configure automatic installation in Jenkins |

The JDK and Maven paths are created on the Jenkins Agent by Ansible.

If Jenkins is configured to install a tool automatically, the tool name must still match the value used in `Jenkinsfile`.

## Jenkins Agent configuration

Create a permanent Jenkins node with:

- **Node name:** `jenkins-agent`;
- **Remote root directory:** `/home/jenkins/agent`;
- **Labels:** `docker-aws-maven`;
- **Usage:** use this node as much as possible;
- **Launch method:** `Launch agents via SSH`;
- **Host:** Jenkins Agent private IP;
- **Credentials:** SSH username `jenkins` with the EC2 private key;
- **Host Key Verification Strategy:** `Manually trusted key Verification Strategy`.

The Jenkins Controller must contain the Agent host key in:

```text
/var/lib/jenkins/.ssh/known_hosts
```

The complete node and `known_hosts` setup is documented in `docs/07-terraform-ansible.md`.

## Required credentials

### Jenkins Agent SSH key

Create an **SSH Username with private key** credential:

- **Username:** `jenkins`;
- **Private key:** the private key of the EC2 key pair used by Terraform;
- **Suggested ID:** `jenkins-agent-ssh`.

### SonarQube token

Create a **Secret text** credential:

- **Secret:** token generated in SonarQube;
- **ID:** `sonar-token`.

### AWS authentication

The Jenkins Agent EC2 instance uses the `JenkinsInfraRole` IAM Role created by bootstrap.

AWS CLI automatically obtains temporary credentials through the EC2 Instance Metadata Service.

No permanent AWS access keys are required in Jenkins Credentials.

Verify the IAM identity on the Jenkins Agent:

```bash
aws sts get-caller-identity
```

The returned ARN should reference `assumed-role/JenkinsInfraRole`.

### Terraform admin CIDR

Create a Jenkins `Secret text` credential:

- ID: `terraform-admin-cidr`
- Secret: the administrator's IPv4 CIDR, matching the value used during Terraform infrastructure provisioning.

`Jenkinsfile.drift` binds this credential to `TF_VAR_admin_cidr`, allowing Terraform to use the same configuration as the initial deployment.

## SonarQube integration

Open **Manage Jenkins → System → SonarQube servers** and configure:

- **Name:** `sonarserver`;
- **Server URL:** `http://SONARQUBE_PRIVATE_IP:9000`;
- **Server authentication token:** `sonar-token`.

The server name must exactly match:

```groovy
withSonarQubeEnv('sonarserver')
```

In SonarQube, create this webhook:

```text
http://JENKINS_CONTROLLER_PRIVATE_IP:8080/sonarqube-webhook/
```

SonarQube sends the Quality Gate result to the Jenkins Controller. The Jenkins Agent starts the analysis, but it does not receive the webhook.

## Pipeline job

Create a Jenkins **Pipeline** job and select **Pipeline script from SCM**.

Use:

- **SCM:** Git;
- **Repository URL:** `https://github.com/yar-portfolio/CICD-todoApp.git`;
- **Branch Specifier:** `*/main`;
- **Script Path:** `Jenkinsfile`.

The repository is public, so Git credentials are not required for checkout.


## Pipeline trigger

The main Jenkins Pipeline uses SCM polling:

```groovy
triggers {
    pollSCM('H/3 * * * *')
}
```

Jenkins checks the GitHub main branch approximately every three minutes and starts a new build when repository changes are detected.

A public GitHub webhook is not required.

After creating the Pipeline job, run it manually once to initialize the job and register its trigger.

## Environment values

The `environment` block in `Jenkinsfile` uses:

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `todo-app` |
| `ECS_CLUSTER` | `newcluster` |
| `ECS_SERVICE` | `todo-ecs-service` |
| `ECS_TASK_FAMILY` | `todo-task` |
| `CONTAINER_NAME` | `todo` |

AWS_REGION, ECR_REPOSITORY, ECS_CLUSTER, ECS_SERVICE, ECS_TASK_FAMILY, and CONTAINER_NAME are defined in the Jenkinsfile environment block.

ECR_REGISTRY is generated dynamically using the AWS Account ID returned by AWS STS.

IMAGE_URI is generated from the registry, repository name, and Jenkins BUILD_NUMBER.

If Terraform is deployed in another AWS account, update `ECR_REGISTRY` in `Jenkinsfile` and `executionRoleArn` in `aws/task-definition-template.json`.

## Pipeline stages

### 1. VERIFY AGENT

Checks that Java, Maven, Git, Docker, and AWS CLI are available on the Jenkins Agent.

### 2. Fetch code

Clones the `main` branch from:

```text
https://github.com/yar-portfolio/CICD-todoApp.git
```

### 3. UNIT TEST

Runs:

```bash
mvn clean verify
```

This compiles the project, runs tests, and performs Maven verification.

### 4. Checkstyle Analysis

Runs:

```bash
mvn checkstyle:checkstyle
```

The generated report is later passed to SonarQube.

### 5. Sonar Code Analysis

Uses the Jenkins tool `sonar8.0` and the SonarQube server `sonarserver`.

The project key is:

```text
todo-sonar
```

### 6. Quality Gate

Waits up to one hour for the SonarQube webhook result.

The Pipeline stops when the Quality Gate fails.

### 7. Build

Runs:

```bash
mvn package -DskipTests
```

The generated artifact is:

```text
target/todolist-app-1.0.0.jar
```

Jenkins archives the JAR after a successful build.


### 8. Build and Push to ECR

Jenkins retrieves the AWS Account ID and constructs the ECR Registry URL dynamically.

It authenticates using AWS CLI and the Jenkins Agent IAM Role, builds the Docker image, and pushes it with the Jenkins BUILD_NUMBER tag.

### 9. Deploy to ECS

Jenkins executes `scripts/deploy-ecs.sh`.


The deployment script automatically retrieves the
AWS Account ID using AWS STS.

It replaces `IMAGE_URI_PLACEHOLDER` and `AWS_ACCOUNT_ID_PLACEHOLDER` in the task definition template, registers a new ECS task definition revision, updates the ECS service, and waits until the deployment becomes stable.

## Expected outcome

After a successful run:

- the Jenkins Agent is connected and has the required tools;
- Maven verification and Checkstyle complete successfully;
- SonarQube returns an accepted Quality Gate result;
- the application JAR and Docker image are created;
- the image is pushed to ECR;
- a new task definition revision is registered;
- the ECS service is updated and becomes stable;
- the application can be opened through the Application Load Balancer URL.


## Infrastructure Drift Monitoring

The repository includes a separate Pipeline defined in `Jenkinsfile.drift`.

The Pipeline runs every three minutes using:

```groovy
triggers {
    cron('H/3 * * * *')
}
```

It initializes Terraform and executes:

```bash
terraform plan -detailed-exitcode \
  -input=false -no-color
```

Terraform plan exit codes:

- 0 — no changes proposed.
- 1 — Terraform execution failed.
- 2 — Terraform proposes infrastructure changes.

The Pipeline archives the complete output as `terraform/drift-report.txt`.

The Jenkins `terraform-admin-cidr` credential provides the value of `TF_VAR_admin_cidr`.

Build results:
- SUCCESS — no changes proposed.
- UNSTABLE — changes proposed.
- FAILURE — Terraform execution error.

The Slack Notification plugin sends messages to `#infra-alerts` when the Jenkins build status changes.

The Pipeline does not run terraform apply.

Note: This check detects differences between Terraform configuration, state, and current AWS resources. It is not a complete audit of every manual change made in the AWS account.

