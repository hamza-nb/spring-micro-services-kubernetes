# Multi-stage build for Spring Boot with Java 17
# Stage 1: Build the application
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
# Copy pom.xml and download dependencies (cached layer)
COPY pom.xml .
RUN mvn dependency:go-offline -B
# Copy source code and build
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2: Create the runtime image
FROM eclipse-temurin:17-jre
WORKDIR /app
# Create a non-root user
RUN groupadd -r spring && useradd -r -g spring spring
USER spring:spring
# Copy the jar from build stage
COPY --from=build /app/target/*.jar app.jar
# Expose port
EXPOSE 8761
# Set JVM options
ENV JAVA_OPTS="-Xmx512m -Xms256m"
# Run the application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]