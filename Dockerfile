# this file is an edited version of https://github.com/kaij/cantaloupe/blob/docker-deploy/docker/Dockerfile

FROM openjdk:8u181-alpine

ENV VERSION 4.1.2

WORKDIR /tmp

RUN apk add --update curl openjpeg-tools ruby msttcorefonts-installer fontconfig \
  && update-ms-fonts \
  && fc-cache -f

# You need to download a local copy of the Java Advanced Imaging API 1.1.2_01
# http://www.oracle.com/technetwork/java/javasebusiness/downloads/java-archive-downloads-java-client-419417.html
COPY jai-1_1_2_01-lib-linux-i586.tar.gz /tmp
RUN tar -xvzpf jai-1_1_2_01-lib-linux-i586.tar.gz

ENV JAIHOME=/tmp/jai-1_1_2_01/lib \
  CLASSPATH=$JAIHOME/jai_core.jar:$JAIHOME/jai_codec.jar:$JAIHOME/mlibwrapper_jai.jar:$CLASSPATH \
  LD_LIBRARY_PATH=.:$JAIHOME:$CLASSPATH \
  GEM_HOME=/tmp/gems

RUN curl -OL "https://github.com/medusa-project/cantaloupe/releases/download/v$VERSION/Cantaloupe-$VERSION.zip" \
  && mkdir -p /usr/local/ \
  && cd /usr/local \
  && unzip /tmp/Cantaloupe-$VERSION.zip \
  && ln -s cantaloupe-$VERSION cantaloupe \
  && rm -rf /tmp/Cantaloupe-$VERSION \
  && rm /tmp/Cantaloupe-$VERSION.zip

RUN addgroup -S cantaloupe && adduser -S cantaloupe -G cantaloupe
COPY --chown=cantaloupe:cantaloupe cantaloupe.properties delegates.rb /etc/

RUN mkdir -p /var/log/cantaloupe \
  && mkdir -p /var/cache/cantaloupe \
  && chown -R cantaloupe:cantaloupe /var/log/cantaloupe \
  && chown -R cantaloupe:cantaloupe /var/cache/cantaloupe

USER cantaloupe

RUN gem install --no-document --install-dir /tmp/gems jwt json_pure

EXPOSE 8182

CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Dcom.sun.media.jai.disableMediaLib=true -Xmx16g -jar /usr/local/cantaloupe/cantaloupe-$VERSION.war"]

