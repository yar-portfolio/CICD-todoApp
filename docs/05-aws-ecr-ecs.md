# AWS ECR and ECS

Terraform owns the AWS infrastructure, while Jenkins owns application delivery. Each successful Pipeline run publishes a new image to ECR, registers a new ECS task definition revision, and updates the running service.

## AWS services used

- **EC2:** runs Jenkins Controller, Jenkins Agent, Ansible Controller, and SonarQube.
- **ECR:** stores application Docker images.
- **ECS Fargate:** runs the application container.
- **Application Load Balancer:** exposes the application over HTTP.
- **IAM:** provides the ECS Task Execution Role and Jenkins deployment permissions.
- **CloudWatch Logs:** stores ECS container logs.
- **VPC and Security Groups:** control network access between project components.

## Deployment flow

1. Jenkins builds the Spring Boot JAR.
2. Jenkins builds a Docker image tagged with the Jenkins build number.
3. Jenkins authenticates to ECR using AWS CLI and temporary credentials provided by the Jenkins Agent IAM Role.
4. Jenkins pushes the image to the `todo-app` repository.
5. Jenkins dynamically replaces `IMAGE_URI_PLACEHOLDER` and `AWS_ACCOUNT_ID_PLACEHOLDER` in the ECS task definition template.
6. Jenkins registers a new `todo-task` task definition revision.
7. Jenkins updates `todo-ecs-service` to use the new revision.
8. Jenkins waits until the ECS service becomes stable.
9. The Application Load Balancer routes traffic to the healthy ECS task.

## Terraform-managed resources

Terraform creates:

- ECR repository `todo-app`;
- ECS cluster `newcluster`;
- ECS task definition family `todo-task`;
- ECS service `todo-ecs-service`;
- CloudWatch log group `/ecs/todo-task`;
- Application Load Balancer, target group, and HTTP listener;
- Security Group for the load balancer;
- Security Group for ECS tasks;
- IAM role `ecsTaskExecutionRole`.

Terraform also creates the four EC2 instances and their Security Groups. They are described in `docs/07-terraform-ansible.md`.

## ECR configuration

| Setting | Value |
|---|---|
| AWS region | `us-east-1` |
| Repository | `todo-app` |
| Registry | `<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com` |
| Image tag | Jenkins `BUILD_NUMBER` |

The ECR repository uses mutable tags. Image scanning on push is disabled in the current Terraform configuration.

`force_delete` is `false`, so Terraform cannot delete a non-empty repository during `terraform destroy`.

The ECR Registry URL is generated dynamically by Jenkins using aws sts get-caller-identity.

## ECS configuration

| Setting | Value |
|---|---|
| Cluster | `newcluster` |
| Service | `todo-ecs-service` |
| Task definition family | `todo-task` |
| Container name | `todo` |
| Container port | `8080` |
| Launch type | Fargate |
| CPU | `1024` |
| Memory | `3072` MiB |
| Desired task count | `1` |
| CloudWatch log group | `/ecs/todo-task` |

The ECS task uses `awsvpc` networking and receives a public IP in the current network design.

The ECS Security Group accepts port `8080` only from the Application Load Balancer Security Group.

### ECS networking and Availability Zones

The Application Load Balancer and ECS Service use the same subnet list:

`local.alb_subnet_ids`

Terraform selects two subnets from the default VPC.

Both `terraform/alb.tf` and `terraform/ecs.tf` reference this shared list.

This ensures that ECS tasks are scheduled only in subnets enabled for the Application Load Balancer.

The ALB target group uses HTTP port 8080 and performs health checks on `/`, accepting HTTP response codes 200-399.

## ECS task definition template

Jenkins uses:

```text
aws/task-definition-template.json
```

The template contains:

```text
IMAGE_URI_PLACEHOLDER
```

During deployment, `scripts/deploy-ecs.sh` replaces the placeholder and creates a temporary file:

```text
task-definition.json
```

The generated file is ignored by Git.

The template uses this execution role:

```text
arn:aws:iam::AWS_ACCOUNT_ID_PLACEHOLDER:role/ecsTaskExecutionRole
```
The ECS task definition template uses two placeholders:

- `IMAGE_URI_PLACEHOLDER` — the Docker image URI.
- `AWS_ACCOUNT_ID_PLACEHOLDER` — the AWS Account ID.

During deployment, `scripts/deploy-ecs.sh` retrieves the AWS Account ID automatically using:

```bash
aws sts get-caller-identity --query Account --output text
```

The script replaces both placeholders and generates `task-definition.json` before registering a new ECS task definition revision.

The execution role ARN is generated dynamically:

`arn:aws:iam::<AWS_ACCOUNT_ID>:role/ecsTaskExecutionRole`

No manual AWS Account ID replacement is required.

The `ecsTaskExecutionRole` must exist in the target AWS account.

## Terraform and Jenkins task definition revisions

Terraform creates the initial task definition and ECS service.

After each successful build, Jenkins creates a newer task definition revision. The Terraform ECS service resource contains:

```hcl
lifecycle {
  ignore_changes = [task_definition]
}
```

This prevents a later `terraform apply` from moving the ECS service back to the original Terraform-created revision.

### Initial ECS deployment

The initial Terraform task definition references the image tag `bootstrap`.

This image is not automatically created in ECR.

Because the ECS service starts with `ecs_desired_count = 1`, the first task may fail until Jenkins publishes the first application image.

Jenkins then registers a new task definition revision using its versioned image and updates the ECS service.


## Jenkins Agent IAM Role

Bootstrap creates an IAM Role named `JenkinsInfraRole` and attaches it to the Jenkins Agent EC2 through an Instance Profile.

The current role includes:

- PowerUserAccess for AWS resource operations.
- IAMReadOnlyAccess for inspecting IAM resources.
- TerraformStateAccess for the remote S3 state and lock file.
- A restricted iam:PassRole permission for
  ecsTaskExecutionRole.

The Jenkins Agent automatically receives temporary AWS credentials from the EC2 metadata service.

No IAM User access keys are required.

PowerUserAccess is intentionally broad for this learning project. A production environment should use more restrictive permissions.

## ECS Task Execution Role

Terraform creates `ecsTaskExecutionRole` and attaches the AWS-managed policy:

```text
service-role/AmazonECSTaskExecutionRolePolicy
```

ECS uses this role to pull the image from ECR and send container logs to CloudWatch.

Jenkins uses its EC2 IAM Role to register task definitions and receives permission to pass ecsTaskExecutionRole through iam:PassRole.

## Deployment verification

After a successful Jenkins run, verify:

1. ECR contains a new image tagged with the Jenkins build number.
2. ECS contains a new `todo-task` revision.
3. `todo-ecs-service` uses the new revision.
4. The ECS task is running and healthy.
5. CloudWatch contains a log stream under `/ecs/todo-task`.
6. The application opens through:

```bash
terraform output -raw application_url
```

## Data persistence

The application stores SQLite data at:

```text
/app/data/TodoList.db
```

The current ECS task definition does not mount persistent storage. Todo records are lost when the task is replaced or recreated.

Keep:

```hcl
ecs_desired_count = 1
```

With multiple ECS tasks, each task would have its own independent SQLite database and users could receive different data depending on which task handles the request.

## Security notes

- Jenkins uses temporary AWS credentials through the Jenkins Agent EC2 IAM Role.
- The EC2 private key must not be committed to Git.
- The ALB currently uses HTTP on port `80`; HTTPS is not configured.
- ECS tasks receive public IPs in the current network design, while inbound application traffic remains restricted to the ALB Security Group.
- A hardened deployment can extend this design with private subnets, HTTPS, stronger IAM separation, persistent storage.
