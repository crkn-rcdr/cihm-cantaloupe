# this file is an edited version of https://github.com/kaij/cantaloupe/blob/docker-deploy/docker/Dockerfile

FROM alpine:3.10

WORKDIR /tmp

ENV VERSION=4.1.3 \
  JAIHOME=/tmp/jai-1_1_2_01/lib \
  CLASSPATH=$JAIHOME/jai_core.jar:$JAIHOME/jai_codec.jar:$JAIHOME/mlibwrapper_jai.jar:$CLASSPATH \
  LD_LIBRARY_PATH=.:$JAIHOME:$CLASSPATH \
  GEM_HOME=/tmp/gems

RUN apk --no-cache add openjdk11-jre wget openjpeg-tools ruby msttcorefonts-installer fontconfig \
  && update-ms-fonts \
  && fc-cache -f \
  # See https://github.com/exo-docker/exo/blob/master/Dockerfile#L99
  && wget -nv -q --no-cookies --no-check-certificate \
  --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
  -O "/tmp/jai.tar.gz" "http://download.oracle.com/otn-pub/java/jai/1.1.2_01-fcs/jai-1_1_2_01-lib-linux-i586.tar.gz" \
  && tar -xzpf jai.tar.gz \
  && wget -nv "https://github.com/medusa-project/cantaloupe/releases/download/v$VERSION/Cantaloupe-$VERSION.zip" \
  && mkdir -p /usr/local/ \
  && cd /usr/local \
  && unzip /tmp/Cantaloupe-$VERSION.zip \
  && ln -s cantaloupe-$VERSION cantaloupe \
  && rm -rf /tmp/Cantaloupe-$VERSION \
  && rm /tmp/Cantaloupe-$VERSION.zip \
  && addgroup -S cantaloupe --gid 8182 && adduser -S cantaloupe --uid 8182 -G cantaloupe \
  && mkdir -p /var/log/cantaloupe \
  && mkdir -p /var/cache/cantaloupe \
  && chown -R cantaloupe:cantaloupe /var/log/cantaloupe \
  && chown -R cantaloupe:cantaloupe /var/cache/cantaloupe

COPY --chown=cantaloupe:cantaloupe cantaloupe.properties delegates.rb /etc/

USER cantaloupe

RUN gem install --no-document --install-dir /tmp/gems jwt json_pure

EXPOSE 8182

CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Dcom.sun.media.jai.disableMediaLib=true -jar /usr/local/cantaloupe/cantaloupe-$VERSION.war"]

