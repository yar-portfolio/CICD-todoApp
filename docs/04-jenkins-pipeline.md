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
- **Docker Pipeline** — provides `docker.build` and `docker.withRegistry`.
- **Amazon ECR** — authenticates Docker with AWS ECR.
- **Pipeline: AWS Steps** — provides the `withAWS` Pipeline step.

Required dependency plugins are installed automatically by Jenkins.

The following plugins are not required by the current `Jenkinsfile`:

- Pipeline: GitHub Groovy Libraries;
- CloudBees Docker Build and Publish;
- Build Timestamp;
- Workspace Cleanup;
- Amazon Web Services SDK :: All as a separately selected plugin.

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

### AWS credentials

Create an **AWS Credentials** credential:

- **ID:** `awscreds`;
- **Access Key ID:** access key for the Jenkins IAM user;
- **Secret Access Key:** secret key for the Jenkins IAM user.

The ID must be exactly `awscreds` because `Jenkinsfile` uses it directly and through:

```groovy
registryCredential = 'ecr:us-east-1:awscreds'
```

The required IAM policy is documented in `docs/05-aws-ecr-ecs.md`.

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

The current `Jenkinsfile` does not contain a `triggers` block.

The Terraform Security Group allows access to Jenkins port `8080` only from the administrator CIDR and internal project Security Groups. GitHub cannot currently reach the Jenkins webhook endpoint.

Start the Pipeline manually with **Build Now**.

To enable builds on every push, add a Jenkins trigger and expose the webhook endpoint through an appropriately secured public route. Until then, **Build Now** is the intended entry point.

## Environment values

The `environment` block in `Jenkinsfile` uses:

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `ECR_REGISTRY` | `551647579168.dkr.ecr.us-east-1.amazonaws.com` |
| `ECR_REPOSITORY` | `todo-app` |
| `ECS_CLUSTER` | `newcluster` |
| `ECS_SERVICE` | `todo-ecs-service` |
| `ECS_TASK_FAMILY` | `todo-task` |
| `CONTAINER_NAME` | `todo` |

`IMAGE_TAG` uses the Jenkins build number. `IMAGE_URI` is built from the registry, repository, and build number.

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

### 8. Build App Image

Builds this Docker image:

```text
551647579168.dkr.ecr.us-east-1.amazonaws.com/todo-app:BUILD_NUMBER
```

### 9. Upload App Image

Uses the Amazon ECR plugin and the `awscreds` credential to authenticate and push the image.

### 10. Deploy to ECS

Runs `scripts/deploy-ecs.sh` inside `withAWS`.

The script:

1. replaces `IMAGE_URI_PLACEHOLDER` in `aws/task-definition-template.json`;
2. creates the temporary `task-definition.json` file;
3. registers a new `todo-task` revision;
4. updates `todo-ecs-service`;
5. waits until the ECS service becomes stable.

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
