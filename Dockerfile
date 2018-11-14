# this file is an edited version of https://github.com/kaij/cantaloupe/blob/docker-deploy/docker/Dockerfile

FROM openjdk:8u181-alpine

ENV VERSION 4.0.2
EXPOSE 8182

WORKDIR /tmp

RUN  apk add --update curl openjpeg-tools ruby msttcorefonts-installer fontconfig \
  && update-ms-fonts \
  && fc-cache -f

# Needed to make local copy from http://www.oracle.com/technetwork/java/javasebusiness/downloads/java-archive-downloads-java-client-419417.html
RUN curl -OL "http://feta.tor.c7a.ca/deploy/jai-1_1_2_01-lib-linux-i586.tar.gz" \
  && tar -xvzpf jai-1_1_2_01-lib-linux-i586.tar.gz

ENV JAIHOME /tmp/jai-1_1_2_01/lib
ENV CLASSPATH $JAIHOME/jai_core.jar:$JAIHOME/jai_codec.jar:$JAIHOME/mlibwrapper_jai.jar:$CLASSPATH
ENV LD_LIBRARY_PATH .:$JAIHOME:$CLASSPATH

RUN  curl -OL "https://github.com/medusa-project/cantaloupe/releases/download/v$VERSION/Cantaloupe-$VERSION.zip" \
  && mkdir -p /usr/local/ \
  && cd /usr/local \
  && unzip /tmp/Cantaloupe-$VERSION.zip \
  && ln -s cantaloupe-$VERSION cantaloupe \
  && rm -rf /tmp/Cantaloupe-$VERSION \
  && rm /tmp/Cantaloupe-$VERSION.zip

RUN adduser -S cantaloupe

COPY cantaloupe.properties delegates.rb config.json /etc/
RUN  mkdir -p /var/log/cantaloupe \
  && mkdir -p /var/cache/cantaloupe \
  && chown -R cantaloupe /var/log/cantaloupe \
  && chown -R cantaloupe /var/cache/cantaloupe \
  && chown cantaloupe /etc/cantaloupe.properties \
  && chown cantaloupe /etc/delegates.rb \
  && chown cantaloupe /etc/config.json

USER cantaloupe

RUN  gem install --no-document --install-dir /tmp/gems jwt json_pure

ENV GEM_HOME /tmp/gems

CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Dcom.sun.media.jai.disableMediaLib=true -Xmx4g -jar /usr/local/cantaloupe/cantaloupe-$VERSION.war"]

