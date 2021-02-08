FROM registry.access.redhat.com/ubi7/ubi:latest

ENV SUMMARY="MongoDB NoSQL database server" \
    DESCRIPTION="MongoDB (from humongous) is a free and open-source \
                 cross-platform document-oriented database program. Classified as a NoSQL \
                 database program, MongoDB uses JSON-like documents with schemas. This \
                 container image contains programs to run mongod server."

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="MongoDB 3.6" \
      io.openshift.expose-services="27017:mongodb" \
      io.openshift.tags="database,mongodb,rh-mongodb36" \
      com.redhat.component="rh-mongodb36-container" \
      name="rhscl/mongodb-36-rhel7" \
      usage="docker run -d -e MONGODB_ADMIN_PASSWORD=my_pass rhscl/mongodb-36-rhel7" \
      version="1" \
      com.redhat.license_terms="https://www.redhat.com/en/about/red-hat-end-user-license-agreements#rhel" \
      maintainer="No One"
      
ADD centos7-scl.repo /etc/yum.repos.d/
ADD centos-gpg /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
RUN yum install -y yum-utils snappy-devel && \
    INSTALL_PKGS="bind-utils gettext iproute rsync tar hostname rh-mongodb36-mongodb rh-mongodb36 rh-mongodb36-mongo-tools rh-mongodb36-syspaths groff-base" && \
    yum install -y --setopt=tsflags=nodocs $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum -y clean all --enablerepo='*'

RUN usermod -aG root mongodb && \
    echo "mongodb ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    
RUN mkdir -p /var/lib/mongodb/data /var/log/mongod /secret && \
    touch /.dbshell && touch /.mongorc.js && \
    chown -R mongodb:root /var/lib/mongodb /var/lib/mongodb/data /var/log/mongod /secret /.mongorc.js /.dbshell && \
    chmod -R g=u,g+s /var/lib/mongodb /var/lib/mongodb/data /var/log/mongod /secret /.mongorc.js /.dbshell

ADD run_mongod.sh /usr/local/bin/run_mongod
RUN chmod +x /usr/local/bin/run_mongod

ENTRYPOINT run_mongod

USER mongodb


EXPOSE 27017