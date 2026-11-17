# Running the Application with Docker

The repository packages the Spring Boot application into the same container format that Jenkins publishes to AWS ECR and deploys through ECS Fargate.

## How the image is built

The `Dockerfile` uses Java 21 and copies the packaged application from `target/`. It also creates `/app/data`, where the application stores its SQLite database inside the container.

The root `.dockerignore` keeps the build context small and prevents local infrastructure files, SSH keys, Git metadata, and other unrelated files from being sent to the Docker daemon.

## Build the application

Create the JAR from the repository root:

```bash
mvn clean package -DskipTests
```

The Docker build expects this exact file:

```text
target/todolist-app-1.0.0.jar
```

## Build the image

```bash
docker build -t todo-app:v1.0 .
```

Confirm that the image exists:

```bash
docker images todo-app
```

## Run the container

```bash
docker run --rm -p 8080:8080 todo-app:v1.0
```

Open:

```text
http://localhost:8080
```

Because the command uses `--rm` and does not mount a volume, the container's SQLite data is removed when the container stops.

## Run in the background

```bash
docker run -d --name todo-app -p 8080:8080 todo-app:v1.0
```

Inspect the running container and its logs:

```bash
docker ps
docker logs -f todo-app
```

Stop and remove it when finished:

```bash
docker stop todo-app
docker rm todo-app
```

## Jenkins image flow


## Jenkins image flow

The Jenkins Pipeline uses the `Build and Push to ECR` stage to build and publish the application image.

The stage performs the following operations:

1. Retrieves the AWS Account ID using AWS STS.
2. Generates the ECR Registry URL dynamically.
3. Authenticates to ECR using AWS CLI and the Jenkins Agent IAM Role.
4. Builds the Docker image from the repository Dockerfile.
5. Pushes the image to ECR using the Jenkins BUILD_NUMBER as the image tag.

The image tag identifies the build associated with each ECS task definition revision.

## Expected result

The Docker workflow is working when:

- the JAR is packaged into the image;
- the container starts and exposes port `8080`;
- the application responds through the mapped local port;
- Jenkins can use the same image structure for ECR and ECS.
