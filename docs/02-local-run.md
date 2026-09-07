# Local Run Guide

## Prerequisites

- Java 21
- Maven 3.9 or newer
- Git

Docker is only needed for container testing. Terraform and AWS access are not required to run the application locally.

## Clone the repository

```bash
git clone https://github.com/yar-portfolio/CICD-todoApp.git
cd CICD-todoApp
git checkout github-actions
```

## Verify the tools

```bash
java -version
mvn -version
```

The Java output should show major version `21`.

## Build and test

Run the same basic Maven verification used by the workflow:

```bash
mvn clean verify
```

This removes the previous build output, compiles the application, runs the configured tests, and creates the JAR in `target/`.

Expected artifact:

```text
target/todolist-app-1.0.0.jar
```

## Run with Maven

```bash
mvn spring-boot:run
```

Open `http://localhost:8080`.

Stop the application with `Ctrl+C`.

## Run the packaged JAR

```bash
mvn clean package
java -jar target/todolist-app-1.0.0.jar
```

Open `http://localhost:8080` and stop the application with `Ctrl+C`.

## Local database

The application uses SQLite and expects the `data/` directory in the repository root. The directory is retained in Git through:

```text
data/.gitkeep
```

The local database file is created in this directory and is excluded from Git.

## Optional Checkstyle report

The workflow creates a Checkstyle report before the SonarQube Cloud analysis. To reproduce that step locally, run:

```bash
mvn checkstyle:checkstyle
```

The report is generated under `target/`.

## Quick verification

A successful local check confirms that:

- Java 21 and Maven are available;
- `mvn clean verify` finishes successfully;
- `target/todolist-app-1.0.0.jar` is created;
- the application opens on port `8080`.
