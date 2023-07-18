pipelineJob('PetClinicBuild') {
    definition {
        cps {
            script('''
                        pipeline {
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
                                            sh "${tool 'M3'}/bin/mvn clean verify sonar:sonar -Dsonar.projectKey=petclinic"
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
                                            sh 'cp target/*.jar $HOME/devops'
                                        }
                                    }
                                }
                                stage('Deploy') {
                                    steps {
                                        sh 'docker run -d -p 8084:8084 \
                                        -v /var/run/docker.sock:/var/run/docker.sock \
                                        -v ./devops:/$HOME/devops
                                        --privileged \
                                        --network devnet \
                                        openjdk:21-ea-17-slim-buster'
                                        sh 'java -jar $HOME/devops/*.jar --server.port=8084'
                                    }
                                }
                            }
                        }
                    '''.stripIndent())
            sandbox()
        }
    }
}

