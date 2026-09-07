# Troubleshooting

This guide covers the most common problems that may appear during the build and deployment process.

When a Jenkins Pipeline fails, start by opening the failed stage and reading the last lines of its log. They usually show which component needs to be checked.

## Maven build fails

Check the Java version:

```bash
java -version
```

The project requires Java 21.

Check Maven:

```bash
mvn -version
```

The project uses Maven 3.9 or newer.

Run the build manually from the project root:

```bash
mvn clean verify
```

If this command also fails, the problem is related to the application build rather than Jenkins.

## JAR file is missing

The Dockerfile expects this file:

```text
target/todolist-app-1.0.0.jar
```

Create it from the project root:

```bash
mvn clean package
```

Then check that the file exists:

```bash
ls -l target/todolist-app-1.0.0.jar
```

## Docker image build fails

Check that Docker is running:

```bash
docker version
```

Check that the JAR file exists:

```bash
ls -l target/todolist-app-1.0.0.jar
```

Try to build the image manually:

```bash
docker build -t todo-app:v1.0 .
```

If Jenkins reports a Docker permission error, make sure the `jenkins` user belongs to the `docker` group. Restart the Jenkins Agent after changing the group membership.

## Container starts but the application is unavailable

Check whether the container is running:

```bash
docker ps
```

Read its logs:

```bash
docker logs CONTAINER_ID
```

The application listens on port `8080`. Run it locally with:

```bash
docker run --rm -p 8080:8080 todo-app:v1.0
```

Then open:

```text
http://localhost:8080
```

## Local run fails because the data directory is missing

The application expects a `data/` directory in the project root.

Create it if it is missing:

```bash
mkdir -p data
```

## Terraform reports that a resource already exists

This usually means that a resource with the same name is already present in AWS.

Open the AWS Console and find the resource named in the Terraform error. If it belongs to an older deployment and is no longer needed, delete it and run Terraform again:

```bash
cd terraform
terraform apply
```

Do not delete a resource if it contains important data or is used by another project. In that case, it should be imported into Terraform state instead.

Remember that `terraform destroy` removes only the resources tracked in the current Terraform state. Resources created manually are not removed automatically.

## Terraform cannot delete the ECR repository

Terraform cannot delete the `todo-app` repository while it contains Docker images.

Delete the images through the AWS Console:

1. Open **Amazon ECR**.
2. Open **Private repositories**.
3. Select `todo-app`.
4. Select all images and choose **Delete**.
5. Run `terraform destroy` again.

## Ansible cannot connect to a server

Run Ansible from the Ansible Controller:

```bash
cd ~/CICD-todoApp/ansible
ansible all -m ping
```

If a server is unreachable, check that:

- the EC2 instance is running;
- `inventory/hosts.ini` contains the correct private IP addresses;
- `~/.ssh/todo-app-key.pem` exists on the Ansible Controller;
- the SSH key has permission `600`;
- the remote user is `ubuntu`;
- the Security Group allows SSH from the Ansible Controller.

Set the correct key permission with:

```bash
chmod 600 ~/.ssh/todo-app-key.pem
```

## Ansible variable is undefined

Run Ansible commands from the repository `ansible/` directory:

```bash
cd ~/CICD-todoApp/ansible
ansible-playbook playbooks/site.yml
```

This allows Ansible to load `ansible.cfg` and the files inside `group_vars/`.

If the error remains, check the variable name for spelling mistakes and make sure the required file exists in `group_vars/`.

## Jenkins cannot find Java or Maven

Open **Manage Jenkins → Tools** and check these names:

- JDK: `JDK21`;
- Maven: `MAVEN3.9`.

The names must exactly match the values used in `Jenkinsfile`.

You can also check the tools directly on the Jenkins Agent:

```bash
java -version
mvn -version
```

## Jenkins cannot connect to the SSH Agent

Open the Jenkins node configuration:

1. Go to **Manage Jenkins → Nodes**.
2. Open the Jenkins Agent node.
3. Select **Configure**.
4. Make sure **Launch method** is set to `Launch agents via SSH`.
5. Under **Host Key Verification Strategy**, select `Manually trusted key Verification Strategy`.
6. Save the configuration.
7. Open the node again and select **Relaunch agent**.
8. Confirm the Agent host key when Jenkins asks whether it should be trusted.

This strategy allows Jenkins to save the Agent host key during the first successful connection. It is also useful after the Agent EC2 instance is recreated and receives a new host key.

If the connection still fails, check that:

- the host is the Jenkins Agent private IP;
- the SSH username is `jenkins`;
- the correct SSH private key is selected in **Credentials**;
- the remote root directory is `/home/jenkins/agent`;
- port `22` is allowed from the Jenkins Controller Security Group.

## Jenkins cannot clone the repository

The Pipeline uses:

```text
https://github.com/yar-portfolio/CICD-todoApp.git
```

Check that:

- the repository address is correct;
- the selected branch is `main`;
- Git is installed on the Jenkins Agent;
- the Jenkins Agent has internet access.

## SonarQube analysis fails

Open **Manage Jenkins → System → SonarQube servers** and check:

- server name: `sonarserver`;
- server URL uses the SonarQube private IP and port `9000`;
- the selected SonarQube token is valid.

Then open **Manage Jenkins → Tools** and check that the SonarQube Scanner name is `sonar8.0`.

If SonarQube itself is unavailable, connect to its EC2 instance and check the service:

```bash
sudo systemctl status sonarqube
```

## Jenkins Agent cannot reach SonarQube

The SonarQube Security Group must allow TCP port `9000` from the Jenkins Agent Security Group.

Check the connection from the Jenkins Agent:

```bash
curl http://SONARQUBE_PRIVATE_IP:9000/api/system/status
```

If the command cannot connect, check the SonarQube private IP, the EC2 instance state, and the Security Group rule.

## Quality Gate stage is stuck

SonarQube must send the analysis result back to the Jenkins Controller.

Open **SonarQube → Administration → Configuration → Webhooks** and check this address:

```text
http://JENKINS_CONTROLLER_PRIVATE_IP:8080/sonarqube-webhook/
```

Make sure that:

- the address ends with `/`;
- the Jenkins Controller private IP is correct;
- the Jenkins Security Group allows port `8080` from the SonarQube Security Group;
- the latest webhook delivery in SonarQube was successful.

## ECR push fails

Start with the failed Jenkins stage and read its log. Then check the following settings.

### 1. Check Jenkins credentials

Open **Manage Jenkins → Credentials**. The AWS credential must have:

- type: `AWS Credentials`;
- ID: `awscreds`;
- a valid Access Key ID and Secret Access Key.

### 2. Check the ECR repository

Open **AWS Console → Amazon ECR → Private repositories** and make sure the `todo-app` repository exists in `us-east-1`.

### 3. Check IAM permissions

Open the IAM user used by Jenkins and check that it has permission to log in to ECR and push images.

After correcting the setting, run the Jenkins Pipeline again.

## ECS deployment fails

Open **AWS Console → Amazon ECS → Clusters → newcluster → Services → todo-ecs-service**.

The **Events** tab usually explains why the deployment failed. Check the newest message first.

Also check that:

- the `todo-app` image exists in ECR;
- a new revision appears under **Task definitions → todo-task**;
- Jenkins has permission to register a task definition and update the ECS service;
- Jenkins can pass the `ecsTaskExecutionRole` to ECS;
- the region is `us-east-1`.

If no new task definition revision appears, the problem happened before ECS updated the service. Check the `Deploy to ECS` stage in Jenkins.

## ECS task starts and then stops

Open the ECS service and select the **Tasks** tab. Change the filter to **Stopped** and open the latest task.

Check:

- **Stopped reason**;
- the container exit code;
- the message under the container details.

Then open **CloudWatch → Log groups → `/ecs/todo-task`** and read the newest log stream.

Common causes include:

- the application failed to start;
- the Docker image or tag does not exist in ECR;
- ECS cannot pull the image;
- the container does not listen on port `8080`;
- the load balancer health check fails.

## Application works but Todo data disappears

SQLite data is stored inside the container at:

```text
/app/data/TodoList.db
```

The current ECS configuration does not use persistent storage for this directory. When ECS replaces the task, the new container starts with an empty database.

Keep `ecs_desired_count = 1`. If several tasks run at the same time, each task has its own separate database.

## Screenshot safety check

Before committing screenshots, make sure they do not show:

- AWS access keys or secret keys;
- SonarQube or Jenkins tokens;
- passwords;
- private SSH keys;
- session cookies;
- personal information.
