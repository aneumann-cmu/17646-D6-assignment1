#!/bin/bash

# SonarQube API URL and admin credentials
SONARQUBE_URL="http://localhost:9000"
SONARQUBE_ADMIN_USERNAME="admin"
SONARQUBE_ADMIN_PASSWORD="password"

# Jenkins credentials API URL
JENKINS_URL="http://localhost:8080"

# Jenkins API authentication (replace with your Jenkins credentials)
JENKINS_USERNAME="admin"
JENKINS_PASSWORD="password"

# SonarQube instance name
SONARQUBE_INSTANCE_NAME="sonarqube"

# Name of the Jenkins job and file to download
JOB_NAME="PetClinicBuild"

#Function to set admin password once Sonarqube is up
verify_sonarqube_status() {
  local sonarqube_status=""
  while [ "$sonarqube_status" != "UP" ]; do
    sonarqube_status=$(curl -f -s "$SONARQUBE_URL/api/system/status" | jq -r '.status')
    echo -n '.'
    sleep 10
  done
}

# Function to set Sonarqube admin password/remove forced authentication/set permission to anyone
create_sonarqube_password () {
  #Set Admin Password
  curl -s -vu $SONARQUBE_ADMIN_USERNAME:admin -o /dev/null -X POST "$SONARQUBE_URL/api/users/change_password?login=$SONARQUBE_ADMIN_USERNAME&previousPassword=admin&password=$SONARQUBE_ADMIN_PASSWORD"
}

# Function to create SonarQube user token
create_sonarqube_user_token() {
  SONARQUBE_TOKEN=$(curl -s -u "$SONARQUBE_ADMIN_USERNAME:$SONARQUBE_ADMIN_PASSWORD" -X POST "$SONARQUBE_URL/api/user_tokens/generate" \
    -d "name=JenkinsTokenForSonarQube" \
    -d "login=admin" \
    -d "type=GLOBAL_ANALYSIS_TOKEN")
  SONARQUBE_TOKEN=$(echo "$SONARQUBE_TOKEN" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
}

# Function to create Jenkins admin API token
create_jenkins_api_token () {
  response=$(curl -s -X POST -u "$JENKINS_USERNAME:$JENKINS_PASSWORD" \
    "$JENKINS_URL/user/$JENKINS_USERNAME/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken" \
    --data-urlencode "newTokenName=ScriptToken" \
    --data-urlencode "newTokenDescription=API Token for scripts" \
    --data-urlencode "newTokenTTL=365")
  API_TOKEN=$(echo "$response" | jq -r '.data.tokenValue')
}

# Function to create Jenkins secret text credential
create_jenkins_credential () {
  local credential_id="sonarqube-token"
  local credential_description="SonarQube User Token"

  curl -X POST -u "$JENKINS_USERNAME:$API_TOKEN" "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
  --data-urlencode "json={
    '': '0',
    'credentials': {
      'scope': 'GLOBAL',
      'id': '$credential_id',
      'secret': '$SONARQUBE_TOKEN',
      'description': '$credential_description',
      'stapler-class': 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl',
      '\$class': 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl'
    }
  }"
}

# Function to create Petclinic job in Jenkins
create_petclinic_project_jk() {
# Jenkins job configuration in XML format
JOB_CONFIG=$(cat << 'EOF'
<flow-definition plugin="workflow-job@2.40">
    <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.85">
        <script>
            <![CDATA[
                pipeline {
                    environment {
                        SONARQUBE_TOKEN = credentials('sonarqube-token')
                    }
                    agent any

                    tools {
                        // Install the Maven version configured as "M3" and add it to the path.
                        maven "M3"
                    }

                    stages {
                        stage('Checkout') {
                            steps {
                                // Checkout your source code from version control
                                git branch: 'main', url: 'https://github.com/spring-projects/spring-petclinic.git'
                            }
                        }
                        stage('Test') {
                            steps {
                                // Test code
                                withSonarQubeEnv('sonarqube') {
                                    sh "${tool 'M3'}/bin/mvn clean verify sonar:sonar -Dsonar.projectKey=petclinic -Dsonar.login=$SONARQUBE_TOKEN"
                                }
                            }
                        }
                        stage('Build') {
                            steps {
                                // Run Maven on a Unix agent.
                                sh './mvnw -Dmaven.test.failure.ignore=true clean package'
                            }
                            post {
                                // If Maven was able to run the tests, even if some of the test
                                // failed, record the test results and archive the jar file.
                                success {
                                    junit '**/target/surefire-reports/TEST-*.xml'
                                    archiveArtifacts 'target/*.jar'
                                }
                            }
                        }
                    }
                }
            ]]>
        </script>
        <sandbox>true</sandbox>
    </definition>
</flow-definition>
EOF
)

  # Submit the job configuration to Jenkins using curl
  curl -X POST -u "$JENKINS_USERNAME:$API_TOKEN" "$JENKINS_URL/createItem?name=$JOB_NAME" --data-binary "$JOB_CONFIG" -H "Content-Type:text/xml"
}

# Function to create Petclinic project in Sonarqube
create_petclinic_project_sq() {
  curl -s -u "$SONARQUBE_ADMIN_USERNAME:$SONARQUBE_ADMIN_PASSWORD" -o /dev/null -X POST "http://localhost:9000/api/projects/create" \
    -d "project"="petclinic" \
    -d "name"="petclinic" \
    -d "projectVisibility"="public"
}

# Function to trigger the Jenkins job
trigger_jenkins_job() {
  curl -o /dev/null -X POST -s -u "$JENKINS_USERNAME:$API_TOKEN" "$JENKINS_URL/job/$JOB_NAME/build"
}

# Function to check the build status
check_build_status() {
  local build_status=""
  while [ "$build_status" != "SUCCESS" ] && [ "$build_status" != "FAILURE" ]; do
    build_status=$(curl -s -u "$JENKINS_USERNAME:$API_TOKEN" "$JENKINS_URL/job/$JOB_NAME/lastBuild/api/json" | jq -r '.result')
    sleep 10
    echo -n '.'
  done

  if [ "$build_status" == "SUCCESS" ]; then
    echo "Build succeeded, downloading executables"
    sleep 10
    download_jar_file
    echo "Download successful, deploying PetClinic"
    deploy_petclinic_app
  else
    echo "Build failed!"
  fi
}

# Function to download .jar files from artifacts
download_jar_file() {
  curl "$JENKINS_URL/job/$JOB_NAME/lastSuccessfulBuild/artifact/target/spring-petclinic-3.1.0-SNAPSHOT.jar" -o "spring-petclinic-3.1.0-SNAPSHOT.jar"
}

deploy_petclinic_app () {
    java -jar spring-petclinic-3.1.0-SNAPSHOT.jar --server.port=8085
    echo "PetClinic Deployed, access at http://localhost:8085"
}

# Main script execution

# Setup Jenkins/SonarQube/PostGRE containers
echo "Setting up container environment"
docker-compose up -d
echo "Containers deployed, waiting for containers to be ready"
verify_sonarqube_status

echo "Containers online, setting up Sonarqube/Jenkins credentials"
create_sonarqube_password
create_sonarqube_user_token
create_jenkins_credential
create_jenkins_api_token
echo "Sonarqube/Jenkins credentials configured, creating Jenkins/Sonarqube Petclinic jobs"
create_petclinic_project_jk
create_petclinic_project_sq
echo "Petclinic project created, starting PetClinicBuild"
trigger_jenkins_job
echo "PetClinicBuild job running... waiting for job to finish"
check_build_status
