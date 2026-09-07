# Running the Application Locally

Running the application locally is the quickest way to verify a change before building a container or starting the Jenkins Pipeline.

## Prerequisites

Install the following tools:

- Java 21
- Maven 3.9 or newer
- Git

Docker is optional for this part. The application builds and runs directly with Java and Maven.

## Clone the repository

```bash
git clone https://github.com/yar-portfolio/CICD-todoApp.git
cd CICD-todoApp
```

## Verify Java and Maven

```bash
java -version
mvn -version
```

Java should report major version `21`, and Maven should report version `3.9.x` or newer.

## Local data directory

The application stores its SQLite database under `data/` in the repository root. The `data/.gitkeep` file preserves this directory in Git, so no additional setup is normally required after cloning.

If the directory is missing, create it before starting the application:

```bash
mkdir -p data
```

## Verify the project

Run the full Maven verification lifecycle:

```bash
mvn clean verify
```

This command clears previous build output, compiles the project, runs the configured tests, and completes Maven verification.

## Start with Maven

```bash
mvn spring-boot:run
```

Open the application at:

```text
http://localhost:8080
```

Press `Ctrl+C` in the terminal to stop it.

## Build and run the JAR

Create the application package:

```bash
mvn clean package
```

Maven writes the artifact to:

```text
target/todolist-app-1.0.0.jar
```

Run it directly with Java:

```bash
java -jar target/todolist-app-1.0.0.jar
```

The application is again available at `http://localhost:8080`.

## Quick verification

A local run is ready when:

- Java reports version 21;
- `mvn clean verify` finishes successfully;
- `mvn clean package` creates the expected JAR;
- the application responds on port `8080`.
