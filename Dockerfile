# this file is an edited version of https://github.com/kaij/cantaloupe/blob/docker-deploy/docker/Dockerfile

FROM openjdk:8-jdk-alpine

ENV VERSION 3.3.2
EXPOSE 8182

WORKDIR /tmp

# Temporary build of fixed openjpeg-tools
RUN  apk add --update git libpng-dev tiff-dev lcms-dev doxygen cmake make g++ \
  && git clone https://github.com/uclouvain/openjpeg.git \
  && mkdir /tmp/openjpeg/build \
  && cd /tmp/openjpeg/build \
  && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  && make install

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

USER cantaloupe

ENV GEM_HOME /usr/lib/ruby/gems/2.4.0

CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Xmx2g -jar /usr/local/cantaloupe/Cantaloupe-$VERSION.war"]
