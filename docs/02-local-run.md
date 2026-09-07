# Local Run

## Requirements

- Java 21
- Maven 3.9+
- Git

## Build and verify

```bash
git clone https://github.com/yar-portfolio/CICD-todoApp.git
cd CICD-todoApp
git checkout gitlab-ci

java -version
mvn -version
mvn clean verify
mvn clean package
```

Build output:

```text
target/todolist-app-1.0.0.jar
```

## Run

With Maven:

```bash
mvn spring-boot:run
```

With the JAR:

```bash
java -jar target/todolist-app-1.0.0.jar
```

Open `http://localhost:8080`. Stop the application with `Ctrl+C`.

The `data/` directory must exist in the project root. It is included through `data/.gitkeep`.
