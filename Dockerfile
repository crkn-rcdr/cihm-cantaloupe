FROM openjdk:8-jdk-alpine

EXPOSE 8182

RUN apk add --update curl

RUN adduser -S cantaloupe

WORKDIR /tmp
RUN  curl -OL "https://github.com/medusa-project/cantaloupe/releases/download/v3.3/Cantaloupe-3.3.zip" \
  && mkdir -p /usr/local/ \
  && cd /usr/local \
  && unzip /tmp/Cantaloupe-3.3.zip \
  && ln -s Cantaloupe-3.3 cantaloupe \
  && rm -rf /tmp/Cantaloupe-3.3 \
  && rm /tmp/Cantaloupe-3.3.zip

COPY cantaloupe.properties delegates.rb /etc/
RUN  mkdir -p /var/log/cantaloupe \
  && mkdir -p /var/cache/cantaloupe \
  && chown -R cantaloupe /var/log/cantaloupe \
  && chown -R cantaloupe /var/cache/cantaloupe \
  && chown cantaloupe /etc/cantaloupe.properties \
  && chown cantaloupe /etc/delegates.rb

USER cantaloupe
CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Xmx2g -jar /usr/local/cantaloupe/Cantaloupe-3.3.war"]
