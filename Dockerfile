FROM alpine:3.24

WORKDIR /tmp

# ---- Environment ----
ENV JAVA_HOME=/usr/lib/jvm/java-25-openjdk \
    GEM_HOME=/tmp/gems \
    PATH=/usr/local/bin:/root/.local/bin:$PATH

# ---- Base dependencies ----
RUN set -eux; \
    for i in 1 2 3 4 5; do \
        apk update \
        && apk add \
            openjdk25-jdk \
            wget \
            unzip \
            openjpeg-tools \
            python3 \
            ruby \
            redis \
            fontconfig \
            ttf-dejavu \
            ttf-liberation \
            sudo \
        && rm -rf /var/cache/apk/* \
        && break; \
        if [ "$i" = 5 ]; then exit 1; fi; \
        sleep 5; \
    done; \
    fc-cache -f

# ---- libjpeg-turbo (recommended for performance) ----
ENV TURBOVERSION=2.1.4

RUN set -eux; \
    for i in 1 2 3 4 5; do \
        apk update \
        && apk add --virtual build-deps \
            cmake g++ make nasm \
        && break; \
        if [ "$i" = 5 ]; then exit 1; fi; \
        sleep 5; \
    done; \
    for i in 1 2 3 4 5; do \
        wget -q -T 30 -O libjpeg-turbo-${TURBOVERSION}.tar.gz \
            https://downloads.sourceforge.net/project/libjpeg-turbo/${TURBOVERSION}/libjpeg-turbo-${TURBOVERSION}.tar.gz \
        && break; \
        rm -f libjpeg-turbo-${TURBOVERSION}.tar.gz; \
        if [ "$i" = 5 ]; then exit 1; fi; \
        sleep 5; \
    done \
 && tar -xpf libjpeg-turbo-${TURBOVERSION}.tar.gz \
 && cd libjpeg-turbo-${TURBOVERSION} \
 && cmake \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib \
        -DBUILD_SHARED_LIBS=True \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DWITH_JAVA=1 \
 && make \
 && make install \
 && apk del build-deps \
 && rm -rf /var/cache/apk/* \
 && rm -rf /tmp/libjpeg-turbo*

# ---- Cantaloupe 5.x ----
ENV VERSION=5.0.7

RUN set -eux; \
    for i in 1 2 3 4 5; do \
        wget -q -T 30 -O Cantaloupe-${VERSION}.zip \
            https://github.com/cantaloupe-project/cantaloupe/releases/download/v${VERSION}/Cantaloupe-${VERSION}.zip \
        && break; \
        rm -f Cantaloupe-${VERSION}.zip; \
        if [ "$i" = 5 ]; then exit 1; fi; \
        sleep 5; \
    done \
 && mkdir -p /usr/local \
 && unzip Cantaloupe-${VERSION}.zip -d /usr/local \
 && ln -s /usr/local/cantaloupe-${VERSION} /usr/local/cantaloupe \
 && rm Cantaloupe-${VERSION}.zip

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

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/populate-redis-from-couch /usr/local/bin/populate-redis-from-couch
COPY scripts/warm_manifest_info_cache.py /usr/local/bin/warm-manifest-info-cache

RUN chmod +x \
        /usr/local/bin/docker-entrypoint.sh \
        /usr/local/bin/populate-redis-from-couch \
        /usr/local/bin/warm-manifest-info-cache

# ---- Sudo permissions ----
RUN echo "cantaloupe ALL=(ALL) NOPASSWD: /usr/sbin/addgroup, /usr/sbin/adduser" \
    > /etc/sudoers.d/cantaloupe

USER cantaloupe

# ---- Ruby gems ----
RUN set -eux; \
    for i in 1 2 3 4 5; do \
        gem install --no-document --install-dir /tmp/gems \
            jwt \
            json_pure \
        && break; \
        if [ "$i" = 5 ]; then exit 1; fi; \
        sleep 5; \
    done

EXPOSE 8182

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["java", \
    "-Dcantaloupe.config=/etc/cantaloupe.properties", \
    "-Dcom.sun.media.jai.disableMediaLib=true", \
    "-cp", "/usr/local/cantaloupe/cantaloupe-5.0.7.jar", \
    "edu.illinois.library.cantaloupe.StandaloneEntry"]
