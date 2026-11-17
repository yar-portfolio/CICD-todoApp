# Terraform and Ansible Infrastructure

This guide takes the environment from an empty AWS account configuration to a working CI/CD deployment. Terraform creates the resources, Ansible configures the EC2 hosts, and Jenkins builds and deploys the application.

## What Terraform creates

- Jenkins Controller EC2 instance;
- Jenkins Agent EC2 instance;
- Ansible Controller EC2 instance;
- SonarQube EC2 instance;
- Security Groups and ingress rules;
- ECR repository `todo-app`;
- ECS cluster `newcluster`;
- ECS task definition family `todo-task`;
- ECS service `todo-ecs-service`;
- Application Load Balancer, target group, and listener;
- ECS Task Execution IAM role;
- CloudWatch log group `/ecs/todo-task`.

## What Ansible configures

- Jenkins Controller with Java 21 and Jenkins;
- Jenkins Agent with Java 21, Maven 3.9.11, Docker, Git, and AWS CLI;
- SonarQube 10.7 as a systemd service.

## Deployment scope and trade-offs

The current setup uses:

- the default VPC;
- public subnets;
- public IPv4 addresses for EC2 instances;
- HTTP instead of HTTPS;
- an S3 remote backend for the main Terraform state, with a separate local state for bootstrap
- manually configured Jenkins credentials;
- SQLite inside the application container.

The environment uses a default VPC, public subnets, HTTP endpoints, and manually configured Jenkins integrations.

The main infrastructure state is stored in S3 with encryption and native state locking.

Bootstrap is managed separately and keeps its own local Terraform state.

## Where to run commands

| Location | Commands |
|---|---|
| Local computer | Bootstrap Terraform, main Terraform, scripts/setup-ansible.sh |
| Ansible Controller | Ansible commands launched automatically by the setup script |
| Jenkins web interface | Agent, tools, SonarQube, credentials, Slack and Pipeline jobs |

Do not run `terraform output` on the Ansible Controller.

## Prerequisites

Install on the local computer:

- Terraform 1.10 or newer;
- AWS CLI;
- Git;
- an SSH client;
- SSH Agent

Prepare AWS access:

1. Configure AWS CLI credentials for the target account.
2. Use the `us-east-1` region.
3. Create an EC2 key pair named `todo-app-key` or choose another name.
4. Save its private key locally as `~/.ssh/todo-app-key.pem`.
5. Protect the key with `chmod 600 ~/.ssh/todo-app-key.pem`.
6. Confirm that the region contains a default VPC with at least two default subnets.
7. Find the public IPv4 address of the local computer and write it as a `/32` CIDR.

The Terraform variable `key_name` must contain the EC2 key pair name, not the `.pem` filename.

If AWS already contains resources with the same names, Terraform cannot create duplicates. Remove resources that are no longer needed or import the existing resources into the current Terraform state. Import examples are available in `docs/06-troubleshooting.md`.


## 1. Bootstrap the infrastructure

Before provisioning the main infrastructure, initialize the bootstrap Terraform configuration.

From the repository root:

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan
terraform -chdir=bootstrap apply
```

Bootstrap creates:
- An S3 bucket for Terraform state.
- S3 bucket versioning and encryption.
- S3 public access restrictions.
- JenkinsInfraRole and its Instance Profile.
- IAM permissions for Jenkins and Terraform.

Retrieve the generated S3 bucket name:

```bash
terraform -chdir=bootstrap output -raw bucket_name
```

Open `terraform/backend.tf` and set the bucket value to the generated S3 bucket name.

The main Terraform backend uses:

- Key: `todoapp/terraform.tfstate`
- Region: `us-east-1`
- Encryption: enabled
- S3 state locking: enabled

Bootstrap keeps its own local Terraform state.
Back up this state securely and do not commit it to Git.

## 2. Create the main infrastructure

Run this section on the local computer.

Clone the repository if necessary:

```bash
git clone https://github.com/yar-portfolio/CICD-todoApp.git
cd CICD-todoApp
```

Open the Terraform directory and create the local variables file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region = "us-east-1"
key_name   = "todo-app-key"
admin_cidr = "YOUR_PUBLIC_IP/32"

jenkins_controller_instance_type = "t3.medium"
jenkins_agent_instance_type      = "t3.medium"
ansible_controller_instance_type = "t3.micro"
sonarqube_instance_type          = "t3.medium"

ecs_desired_count = 1
```

Example:

```hcl
admin_cidr = "203.0.113.10/32"
```

Replace the example with the real public IP address of the local computer.

Initialize and validate Terraform:

```bash
terraform init
terraform fmt -check
terraform validate
```

Create and review the plan:

```bash
terraform plan -out=tfplan
```

Apply it:

```bash
terraform apply tfplan
```

Show the created addresses and resource values:

```bash
terraform output
```

The ECR repository is empty after the first `terraform apply`. The ECS task cannot start successfully until Jenkins builds and pushes the first application image. This is expected.

AWS resources can generate charges while they exist. Use the cleanup section at the end of this guide when the environment is no longer needed.


## 3. Configure EC2 instances using Ansible

The project includes an automated Ansible setup script located at:

`scripts/setup-ansible.sh`

Run this script from the local computer after the main Terraform infrastructure has been created.

Load the EC2 SSH private key into the local SSH agent:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/todo-app-key.pem
```

From the repository root, execute:

```bash
bash scripts/setup-ansible.sh
```

The script automatically:

1. Reads the EC2 IP addresses from Terraform outputs.
2. Generates a temporary Ansible inventory.
3. Connects to the Ansible Controller over SSH.
4. Waits for cloud-init to finish.
5. Clones or updates the GitHub repository.
6. Copies the generated inventory to the Ansible Controller.
7. Executes `ansible-inventory` and `ansible-playbook`.

Ansible configures:
- Jenkins Controller.
- Jenkins Agent.
- SonarQube server.

The SSH private key stays on the local computer. SSH Agent Forwarding is used for authentication.

No manual IP address replacement or repository cloning is required on the Ansible Controller.

Run the script again if the EC2 instances are recreated.

## 4. Finish the Jenkins and SonarQube setup

### 4.1 Open Jenkins

Run locally from `CICD-todoApp/terraform/`:

```bash
terraform output -raw jenkins_controller_url
```

Open the returned URL in a browser.

### 4.2 Read the initial Jenkins password

Run locally:

```bash
ssh -i ~/.ssh/todo-app-key.pem \
  ubuntu@$(terraform output -raw jenkins_controller_public_ip) \
  'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'
```

Use the password to complete the Jenkins setup wizard and create the administrator account.

Install the plugins listed in `docs/04-jenkins-pipeline.md`:

- Pipeline
- Git
- SSH Build Agents
- SonarQube Scanner for Jenkins
- Credentials Binding
- Slack Notification

### 4.3 Prepare SSH access to the Jenkins Agent

The Ansible playbook creates the `jenkins` user on the Agent and adds the EC2 public key to:

```text
/home/jenkins/.ssh/authorized_keys
```

This allows the Jenkins Controller to connect to the Agent as the `jenkins` user. No additional SSH configuration is required on the Jenkins Controller.

The public key stays on the Jenkins Agent. The matching private key is added to Jenkins Credentials in the next step.

### 4.4 Add the Jenkins Agent SSH credential

Open **Manage Jenkins → Credentials → System → Global credentials**.

Create a credential:

- **Kind:** `SSH Username with private key`;
- **ID:** `jenkins-agent-ssh`;
- **Username:** `jenkins`;
- **Private Key:** choose `Enter directly` and paste the content of `~/.ssh/todo-app-key.pem` from the local computer.

Ansible copies the EC2 authorized public key from the Ubuntu account to the Jenkins Agent account, so the corresponding EC2 private key can authenticate as `jenkins`.

### 4.5 Create the Jenkins Agent node

Open **Manage Jenkins → Nodes → New Node**.

Create a permanent agent with:

- **Node name:** `jenkins-agent`;
- **Remote root directory:** `/home/jenkins/agent`;
- **Labels:** `docker-aws-maven`;
- **Usage:** `Use this node as much as possible`;
- **Launch method:** `Launch agents via SSH`;
- **Host:** Jenkins Agent private IP;
- **Credentials:** `jenkins-agent-ssh`;
- **Host Key Verification Strategy:** `Manually trusted key Verification Strategy`.

Save the node and click **Relaunch agent** if it does not connect automatically. If Jenkins asks whether the Agent should be trusted during the first connection, confirm it from the node page.

The node must show as online before running the Pipeline.

### 4.6 Configure Jenkins tools

Open **Manage Jenkins → Tools**.

Configure JDK:

- **Name:** `JDK21`;
- disable automatic installation;
- **JAVA_HOME:** `/usr/lib/jvm/java-21-openjdk-amd64`.

Configure Maven:

- **Name:** `MAVEN3.9`;
- disable automatic installation;
- **MAVEN_HOME:** `/opt/apache-maven-3.9.11`.

Configure SonarQube Scanner:

- **Name:** `sonar8.0`;
- enable automatic installation and select the available SonarScanner CLI version.

The names must exactly match `Jenkinsfile`.

### 4.7 Configure SonarQube

Get the public SonarQube URL locally:

```bash
terraform output -raw sonarqube_url
```

Open the URL in a browser. On a new installation, sign in with the default `admin` user and change the default password when prompted.

Create a token in SonarQube:

1. Open **My Account → Security**.
2. Enter a token name such as `jenkins`.
3. Generate the token.
4. Copy it immediately.

Create the token credential in Jenkins:

1. Open **Manage Jenkins → Credentials → System → Global credentials**.
2. Select **Add Credentials**.
3. Choose **Secret text**.
4. Paste the SonarQube token into **Secret**.
5. Set **ID** to `sonar-token`.

Get the SonarQube private IP locally:

```bash
terraform output -raw sonarqube_private_ip
```

Open **Manage Jenkins → System → SonarQube servers** and configure:

- enable **Environment variables**;
- **Name:** `sonarserver`;
- **Server URL:** `http://SONARQUBE_PRIVATE_IP:9000`;
- **Server authentication token:** `sonar-token`.

The Jenkins Agent connects to SonarQube over HTTP port `9000`. HTTPS is not configured in this project.

### 4.8 Add the SonarQube webhook

Get the Jenkins Controller private IP locally:

```bash
terraform output -raw jenkins_controller_private_ip
```

In SonarQube, open **Administration → Configuration → Webhooks** and create:

- **Name:** `jenkins`;
- **URL:** `http://JENKINS_CONTROLLER_PRIVATE_IP:8080/sonarqube-webhook/`.

The trailing `/` is required.

SonarQube sends the Quality Gate result to the Jenkins Controller because the Controller manages the Pipeline. The Agent only runs the scanner.


### 4.9 Verify Jenkins IAM Role

The Jenkins Agent receives AWS permissions from the JenkinsInfraRole IAM Role created by bootstrap.

Permanent AWS credentials are not required in Jenkins.

Verify authentication on the Jenkins Agent:

```bash
aws sts get-caller-identity
```

The identity should reference the JenkinsInfraRole assumed role.

## 5. Check account-specific Pipeline values

Run this section locally from `CICD-todoApp/terraform/`:

```bash
terraform output -raw aws_account_id
terraform output -raw ecr_repository_url
terraform output -raw ecs_cluster_name
terraform output -raw ecs_service_name
terraform output -raw ecs_task_execution_role_arn
```
The Jenkins Pipeline automatically retrieves the AWS Account ID using AWS STS.

The ECR Registry URL is generated dynamically.

During ECS deployment, `scripts/deploy-ecs.sh` also retrieves the AWS Account ID and inserts it into the ECS task definition execution role ARN.

No manual AWS Account ID configuration is required in the Jenkinsfile or ECS task definition template.

The `ecsTaskExecutionRole` must exist in the target AWS account, and JenkinsInfraRole must have permission to pass it using `iam:PassRole`.

The current resource names must remain:

```text
ECR repository: todo-app
ECS cluster: newcluster
ECS service: todo-ecs-service
Task family: todo-task
Container: todo
```

## 6. Create and run the Jenkins Pipeline

In Jenkins, select **New Item → Pipeline**.

Configure:

- **Definition:** `Pipeline script from SCM`;
- **SCM:** `Git`;
- **Repository URL:** `https://github.com/yar-portfolio/CICD-todoApp.git`;
- **Branch Specifier:** `*/main`;
- **Script Path:** `Jenkinsfile`.

Save the job.

The Jenkinsfile uses SCM polling to check the GitHub main branch approximately every three minutes.

After creating the Pipeline job, run it manually once to initialize the job and register the trigger.

Jenkins can then automatically detect new commits without requiring a public GitHub webhook.

Jenkins will:

1. run the build on the Jenkins Agent;
2. verify and package the application;
3. analyze the code in SonarQube;
4. wait for the Quality Gate webhook;
5. build and push the Docker image to ECR;
6. register a new `todo-task` revision;
7. update `todo-ecs-service`;
8. wait until the ECS service becomes stable.

Terraform ignores later changes to the ECS service task definition revision. A future `terraform apply` therefore does not roll the service back to the original revision.


## Configure Terraform drift monitoring

Create a second Jenkins Pipeline job:

- Job name: `terraform-drift-check`
- Definition: Pipeline script from SCM
- SCM: Git
- Repository: the same GitHub repository
- Branch: `*/main`
- Script Path: `Jenkinsfile.drift`

The job checks Terraform configuration every three minutes.

### Terraform admin CIDR credential

Open Jenkins Credentials and create a new Secret text credential:

- ID: `terraform-admin-cidr`
- Secret: the same IPv4 CIDR used during the initial Terraform deployment.

The Pipeline maps this credential to TF_VAR_admin_cidr.

### Slack configuration

Create or select the Slack channel:

`#infra-alerts`

Configure the Slack Notification plugin using a Slack App bot token stored in Jenkins Credentials.

Configure the Slack workspace, credentials, default channel, and bot-user settings.

Test the connection before running the Pipeline.

The drift-check Pipeline:

- Runs terraform plan.
- Stores the report as drift-report.txt.
- Marks proposed changes as UNSTABLE.
- Marks Terraform execution errors as FAILURE.
- Sends Slack notifications when build status changes.
- Does not automatically run terraform apply.

## 7. Open the application

After a successful Pipeline, run locally from `CICD-todoApp/terraform/`:

```bash
terraform output -raw application_url
```

Open the returned Application Load Balancer URL in a browser.

If the application is unavailable, check the ECS service events, stopped task reason, target group health, and CloudWatch log group `/ecs/todo-task`.

## Data persistence

The application stores SQLite data inside the container at:

```text
/app/data/TodoList.db
```

The current ECS task definition does not mount persistent storage. Todo records are lost when the task is replaced or recreated.

Keep:

```hcl
ecs_desired_count = 1
```

With multiple tasks, each task would have a separate SQLite database.

## Cleanup

Run cleanup commands locally from `CICD-todoApp/terraform/`.

The ECR repository uses `force_delete = false`. Delete all images from `todo-app` through the AWS Console before destroying the infrastructure.

Review the resources Terraform manages:

```bash
terraform state list
```

Destroy them:

```bash
terraform destroy
```

Confirm the destruction only after reviewing the plan.

After `terraform destroy`, check the AWS Console for manually created resources or resources from a different Terraform state. They are not removed by the current state and may continue to generate charges.

### Bootstrap cleanup

The main Terraform configuration does not manage the bootstrap S3 bucket or JenkinsInfraRole.

Bootstrap resources are managed by a separate Terraform state.

Do not remove the S3 backend while the main infrastructure still depends on it.

Before cleaning up bootstrap:
- Destroy the main infrastructure.
- Back up the S3 Terraform state.
- Check that no Terraform runner still needs access to the bucket.
- Review the bootstrap destroy plan carefully.

The S3 bucket may need its objects and versions removed before it can be deleted.
