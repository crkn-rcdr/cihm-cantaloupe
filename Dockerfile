# this file is an edited version of https://github.com/kaij/cantaloupe/blob/docker-deploy/docker/Dockerfile

FROM alpine:3.16.3

WORKDIR /tmp

ENV JAIHOME=/tmp/jai-1_1_2_01/lib \
  CLASSPATH=$JAIHOME/jai_core.jar:$JAIHOME/jai_codec.jar:$JAIHOME/mlibwrapper_jai.jar:$CLASSPATH \
  LD_LIBRARY_PATH=.:$JAIHOME:$CLASSPATH \
  GEM_HOME=/tmp/gems \
  JAVA_HOME=/usr/lib/jvm/java-11-openjdk

RUN apk --no-cache add openjdk11 wget openjpeg-tools ruby msttcorefonts-installer fontconfig sudo \
  python3 py3-pip gcc musl-dev libffi-dev python3-dev linux-headers \
  && update-ms-fonts \
  && fc-cache -f \
  # See https://github.com/exo-docker/exo/blob/master/Dockerfile#L99
  && wget -nv -q --no-cookies --no-check-certificate \
  --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
  -O "/tmp/jai.tar.gz" "http://download.oracle.com/otn-pub/java/jai/1.1.2_01-fcs/jai-1_1_2_01-lib-linux-i586.tar.gz" \
  && tar -xzpf jai.tar.gz

# Verify Python and pip installation
RUN python3 --version \
&& pip3 --version \
&& which python3 \
&& which pip3 \
&& ls -l /usr/bin/python3 \
&& ls -l /usr/bin/pip3 \
&& echo $PATH

# https://github.com/crkn-rcdr/cihm-cantaloupe/issues/15
ENV TURBOVERSION=2.1.4
RUN cd /tmp && apk add --virtual build-dependencies cmake g++ make nasm \
  && wget "https://downloads.sourceforge.net/project/libjpeg-turbo/${TURBOVERSION}/libjpeg-turbo-${TURBOVERSION}.tar.gz" \
  && tar -xpf libjpeg-turbo-${TURBOVERSION}.tar.gz \
  && cd libjpeg-turbo-${TURBOVERSION} \
  && cmake \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=/usr/lib \
  -DBUILD_SHARED_LIBS=True \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$CFLAGS" \
  -DWITH_JPEG8=1 \
  -DWITH_JAVA=1 \
  && make && make install \
  && apk del build-dependencies

ENV VERSION=4.1.11

RUN wget -nv "https://github.com/medusa-project/cantaloupe/releases/download/v$VERSION/Cantaloupe-$VERSION.zip" \
  && mkdir -p /usr/local/ \
  && cd /usr/local \
  && unzip /tmp/Cantaloupe-$VERSION.zip \
  && ln -s cantaloupe-$VERSION cantaloupe \
  && rm -rf /tmp/Cantaloupe-$VERSION \
  && rm /tmp/Cantaloupe-$VERSION.zip 

# Add the cantaloupe user and group with sudo privileges
RUN addgroup -S cantaloupe --gid 8182 && adduser -S cantaloupe --uid 8182 -G cantaloupe \
    && mkdir -p /var/log/cantaloupe /var/cache/cantaloupe \
    && chown -R cantaloupe:cantaloupe /var/log/cantaloupe /var/cache/cantaloupe

# Copy necessary config files
COPY --chown=cantaloupe:cantaloupe cantaloupe.properties delegates.rb test.rb swift.py /etc/

# Install Python dependencies including Swift CLI
RUN pip3 install --no-cache-dir python-swiftclient python-keystoneclient

# Install wheel for building the required packages
RUN pip3 install wheel

# Install other Python dependencies that need compilation
RUN pip3 install --no-cache-dir psutil

# Give 'cantaloupe' user permission to use 'sudo' for specific commands
RUN echo "cantaloupe ALL=(ALL) NOPASSWD: /usr/sbin/addgroup, /usr/sbin/adduser" > /etc/sudoers.d/cantaloupe

# Set environment variables to include directories for Python and Swift CLI
ENV PATH=/usr/local/bin:$PATH \
    PATH=/root/.local/bin:$PATH 

USER cantaloupe

RUN gem install --no-document --install-dir /tmp/gems jwt json_pure

EXPOSE 8182

CMD ["sh", "-c", "java -Dcantaloupe.config=/etc/cantaloupe.properties -Dcom.sun.media.jai.disableMediaLib=true -jar /usr/local/cantaloupe/cantaloupe-$VERSION.war"]
