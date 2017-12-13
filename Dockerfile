# this file is an edited version of https://github.com/kaij/cantaloupe/blob/docker-deploy/docker/Dockerfile

FROM openjdk:8u131-jdk-alpine

ENV VERSION 3.3.5
EXPOSE 8182

WORKDIR /tmp

# Temporary build of fixed openjpeg-tools
RUN  apk add --update git libpng-dev tiff-dev lcms-dev doxygen cmake make g++ \
  && git clone --branch v2.3.0 --single-branch --depth 1 https://github.com/uclouvain/openjpeg.git \
  && mkdir /tmp/openjpeg/build \
  && cd /tmp/openjpeg/build \
  && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  && make install && rm -rf /tmp/openjpeg

RUN  apk add --update curl ruby msttcorefonts-installer fontconfig \
  && update-ms-fonts \
  && fc-cache -f \
  && echo 'gem: --no-document' >> /etc/gemrc \
  && gem install jwt json_pure

RUN  curl -OL "https://github.com/medusa-project/cantaloupe/releases/download/v$VERSION/Cantaloupe-$VERSION.zip" \
  && mkdir -p /usr/local/ \
  && cd /usr/local \
  && unzip /tmp/Cantaloupe-$VERSION.zip \
  && ln -s Cantaloupe-$VERSION cantaloupe \
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

# Needed to make local copy from http://www.oracle.com/technetwork/java/javasebusiness/downloads/java-archive-downloads-java-client-419417.html
RUN curl -OL "http://feta.office.c7a.ca/deploy/jai-1_1_2_01-lib-linux-i586.tar.gz" \
  && tar -xvzpf jai-1_1_2_01-lib-linux-i586.tar.gz

ENV JAIHOME /tmp/jai-1_1_2_01/lib
ENV CLASSPATH $JAIHOME/jai_core.jar:$JAIHOME/jai_codec.jar:$JAIHOME/mlibwrapper_jai.jar:$CLASSPATH
ENV LD_LIBRARY_PATH .:$JAIHOME:$CLASSPATH

USER cantaloupe

ENV GEM_HOME /usr/lib/ruby/gems/2.4.0

CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Xmx2g -jar /usr/local/cantaloupe/Cantaloupe-$VERSION.war"]
