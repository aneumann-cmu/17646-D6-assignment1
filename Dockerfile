# Use latest Jenkins LTS Image
FROM jenkins/jenkins:lts
LABEL Name=aneumann_assignment1 Version=0.0.1

#Set Jenkins Installation Options
ENV JAVA_OPTS -Djenkins.install.runSetupWizard=false
ENV CASC_JENKINS_CONFIG /var/jenkins_home/casc.yaml

#Install Plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

#Set Jenkins Environment Variables
COPY casc.yaml /var/jenkins_home/casc.yaml