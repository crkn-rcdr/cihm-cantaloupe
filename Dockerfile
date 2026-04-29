FROM alpine:3.19

WORKDIR /tmp

# ---- Environment ----
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk \
    GEM_HOME=/tmp/gems \
    PATH=/usr/local/bin:/root/.local/bin:$PATH
ENV SQLITE_JDBC_VERSION=3.45.3.0

# ---- Base dependencies ----
RUN apk --no-cache add \
    openjdk17-jdk \
    wget \
    unzip \
    openjpeg-tools \
    ruby \
    fontconfig \
    ttf-dejavu \
    ttf-liberation \
    sudo \
 && fc-cache -f

# ---- libjpeg-turbo (recommended for performance) ----
ENV TURBOVERSION=2.1.4

RUN apk add --no-cache --virtual build-deps \
        cmake g++ make nasm \
 && wget -q https://downloads.sourceforge.net/project/libjpeg-turbo/${TURBOVERSION}/libjpeg-turbo-${TURBOVERSION}.tar.gz \
 && tar -xpf libjpeg-turbo-${TURBOVERSION}.tar.gz \
 && cd libjpeg-turbo-${TURBOVERSION} \
 && cmake \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib \
        -DBUILD_SHARED_LIBS=True \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_JAVA=1 \
 && make \
 && make install \
 && apk del build-deps \
 && rm -rf /tmp/libjpeg-turbo*

# ---- Cantaloupe 5.x ----
ENV VERSION=5.0.7

RUN wget -q https://github.com/cantaloupe-project/cantaloupe/releases/download/v${VERSION}/Cantaloupe-${VERSION}.zip \
 && mkdir -p /usr/local \
 && unzip Cantaloupe-${VERSION}.zip -d /usr/local \
 && ln -s /usr/local/cantaloupe-${VERSION} /usr/local/cantaloupe \
 && rm Cantaloupe-${VERSION}.zip

# ---- SQLite extension index support ----
RUN wget -q -O /usr/local/lib/sqlite-jdbc.jar \
    https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/${SQLITE_JDBC_VERSION}/sqlite-jdbc-${SQLITE_JDBC_VERSION}.jar

# ---- User setup ----
RUN addgroup -S cantaloupe --gid 8182 \
 && adduser -S cantaloupe --uid 8182 -G cantaloupe \
 && mkdir -p /var/log/cantaloupe /var/cache/cantaloupe \
 && chown -R cantaloupe:cantaloupe \
        /var/log/cantaloupe \
        /var/cache/cantaloupe

# ---- Configuration ----
COPY --chown=cantaloupe:cantaloupe \
    cantaloupe.properties \
    delegates.rb \
    test.rb \
    /etc/

# ---- Sudo permissions ----
RUN echo "cantaloupe ALL=(ALL) NOPASSWD: /usr/sbin/addgroup, /usr/sbin/adduser" \
    > /etc/sudoers.d/cantaloupe

USER cantaloupe

# ---- Ruby gems ----
RUN gem install --no-document --install-dir /tmp/gems \
    jwt \
    json_pure

EXPOSE 8182

CMD ["java", \
    "-Dcantaloupe.config=/etc/cantaloupe.properties", \
    "-Dcom.sun.media.jai.disableMediaLib=true", \
    "-cp", "/usr/local/lib/sqlite-jdbc.jar:/usr/local/cantaloupe/cantaloupe-5.0.7.jar", \
    "edu.illinois.library.cantaloupe.StandaloneEntry"]
