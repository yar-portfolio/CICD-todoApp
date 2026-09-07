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
- a local Terraform state;
- manually configured Jenkins credentials;
- SQLite inside the application container.

The deployment remains intentionally compact: it does not add a custom VPC, private subnets, an S3 backend, RDS, HTTPS, Route 53, or Auto Scaling. These services can be introduced independently as the environment is hardened or scaled.

## Where to run commands

| Location | Commands |
|---|---|
| Local computer, inside `CICD-todoApp/terraform/` | `terraform init`, `plan`, `apply`, `output`, `destroy`, and SSH/SCP commands |
| Ansible Controller, inside `~/CICD-todoApp/ansible/` | `ansible`, `ansible-playbook`, and inventory editing |
| Jenkins web interface | Credentials, Agent node, tools, SonarQube, and Pipeline settings |

Do not run `terraform output` on the Ansible Controller. The Terraform state remains on the local computer.

## Prerequisites

Install on the local computer:

- Terraform 1.7 or newer;
- AWS CLI;
- Git;
- an SSH client.

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

## 1. Create the infrastructure

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

## 2. Prepare the Ansible Controller

Run the first commands in this section on the local computer from `CICD-todoApp/terraform/`.

Wait for cloud-init on the Ansible Controller:

```bash
ssh -i ~/.ssh/todo-app-key.pem \
  ubuntu@$(terraform output -raw ansible_controller_public_ip) \
  'cloud-init status --wait'
```

Copy the EC2 private key to the Ansible Controller:

```bash
scp -i ~/.ssh/todo-app-key.pem \
  ~/.ssh/todo-app-key.pem \
  ubuntu@$(terraform output -raw ansible_controller_public_ip):/home/ubuntu/.ssh/todo-app-key.pem
```

Connect to the Ansible Controller:

```bash
ssh -i ~/.ssh/todo-app-key.pem \
  ubuntu@$(terraform output -raw ansible_controller_public_ip)
```

Run the following commands on the Ansible Controller:

```bash
chmod 600 ~/.ssh/todo-app-key.pem

git clone https://github.com/yar-portfolio/CICD-todoApp.git
cd CICD-todoApp/ansible

cp inventory/hosts.ini.example inventory/hosts.ini
```

Do not commit the private key or the real inventory. The repository ignores `.pem` files and `inventory/hosts.ini`.

## 3. Fill the Ansible inventory

Open a local terminal and run these commands inside `CICD-todoApp/terraform/`:

```bash
terraform output -raw jenkins_controller_private_ip
terraform output -raw jenkins_agent_private_ip
terraform output -raw sonarqube_private_ip
```

Copy the three returned private IP addresses.

Return to the Ansible Controller and open the inventory:

```bash
cd ~/CICD-todoApp/ansible
nano inventory/hosts.ini
```

Replace the example addresses:

```ini
[jenkins_controller]
jenkins-controller ansible_host=JENKINS_CONTROLLER_PRIVATE_IP

[jenkins_agents]
jenkins-agent ansible_host=JENKINS_AGENT_PRIVATE_IP

[sonarqube]
sonarqube-server ansible_host=SONARQUBE_PRIVATE_IP

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/todo-app-key.pem
ansible_python_interpreter=/usr/bin/python3
```

Use private IP addresses because the managed EC2 instances accept SSH from the Ansible Controller Security Group inside the VPC.

Check connectivity:

```bash
cd ~/CICD-todoApp/ansible
ansible all -m ping
```

Run all playbooks:

```bash
ansible-playbook playbooks/site.yml
```

Run individual playbooks only when necessary:

```bash
ansible-playbook playbooks/setup-jenkins-controller.yml
ansible-playbook playbooks/setup-jenkins-agent.yml
ansible-playbook playbooks/setup-sonarqube.yml
```

Always run these commands from `~/CICD-todoApp/ansible/`. This ensures that Ansible loads `ansible.cfg`, the inventory, and `group_vars`.

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

- Pipeline;
- Git;
- SSH Build Agents;
- SonarQube Scanner for Jenkins;
- Docker Pipeline;
- Amazon ECR;
- Pipeline: AWS Steps.

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

### 4.9 Add AWS credentials to Jenkins

Create a dedicated IAM user such as `jenkins-cicd` and attach the policy documented in `docs/05-aws-ecr-ecs.md`.

Create an access key for that IAM user.

In Jenkins, open **Manage Jenkins → Credentials → System → Global credentials** and create:

- **Kind:** `AWS Credentials`;
- **ID:** `awscreds`;
- **Access Key ID:** the IAM access key;
- **Secret Access Key:** the IAM secret key.

The ID must be exactly `awscreds` because it is referenced by `Jenkinsfile`.

Do not add AWS access keys to Git, Terraform variables, Ansible variables, shell scripts, or screenshots.

## 5. Check account-specific Pipeline values

Run this section locally from `CICD-todoApp/terraform/`:

```bash
terraform output -raw aws_account_id
terraform output -raw ecr_repository_url
terraform output -raw ecs_cluster_name
terraform output -raw ecs_service_name
terraform output -raw ecs_task_execution_role_arn
```

The current repository contains AWS account ID `551647579168` in:

- `ECR_REGISTRY` inside `Jenkinsfile`;
- `executionRoleArn` inside `aws/task-definition-template.json`.

If Terraform is deployed in another AWS account, update both files before running the Pipeline.

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

The current `Jenkinsfile` does not contain a `triggers` block. The Terraform Security Group also does not allow GitHub to reach Jenkins port `8080`.

Start the Pipeline manually with **Build Now**.

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
