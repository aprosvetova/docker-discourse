FROM ruby:2.6.5

ARG DISCOURSE_VERSION

ENV RAILS_ENV=production \
    DEBIAN_VERSION=buster \
    DISCOURSE_DB_HOST=postgres \
    DISCOURSE_REDIS_HOST=redis \
    DISCOURSE_SERVE_STATIC_ASSETS=true \
    DISCOURSE_VERSION=${DISCOURSE_VERSION} \
    GIFSICLE_VERSION=1.92 \
    PNGQUANT_VERSION=2.12.5 \
    PNGCRUSH_VERSION=1.8.13 \
    JEMALLOC_NEW=3.6.0 \
    JEMALLOC_STABLE=5.2.0 \
    PG_MAJOR=10 \
    NODE_MAJOR=10 \
    RUBY_GLOBAL_METHOD_CACHE_SIZE=131072 \
    RUBY_GC_HEAP_GROWTH_MAX_SLOTS=40000 \
    RUBY_GC_HEAP_INIT_SLOTS=400000 \
    RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR=1.5 \
    RUBY_GC_MALLOC_LIMIT=90000000 \
    BUILD_DEPS="\
      autoconf \
      advancecomp \
      libbz2-dev \
      libfreetype6-dev \
      libjpeg-dev \
      libjpeg-turbo-progs \
      libtiff-dev \
      pkg-config"

COPY install /tmp/install

RUN ls /tmp/ && ls /tmp/install

RUN curl http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | apt-key add - \
 && echo "deb http://apt.postgresql.org/pub/repos/apt/ ${DEBIAN_VERSION}-pgdg main" | \
        tee /etc/apt/sources.list.d/postgres.list \
 && curl --silent --location https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get update && apt-get install -y --no-install-recommends \
      ${BUILD_DEPS} \
      brotli \
      ghostscript \
      gsfonts \
      jpegoptim \
      libxml2 \
      nodejs \
      optipng \
      jhead \
      postgresql-client-${PG_MAJOR} \
      postgresql-contrib-${PG_MAJOR} libpq-dev libreadline-dev \
 && npm install svgo uglify-js -g \
 && mkdir /jemalloc-stable && cd /jemalloc-stable &&\
      wget https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_STABLE}/jemalloc-${JEMALLOC_STABLE}.tar.bz2 &&\
      tar -xjf jemalloc-${JEMALLOC_STABLE}.tar.bz2 && cd jemalloc-${JEMALLOC_STABLE} && ./configure --prefix=/usr && make && make install &&\
      cd / && rm -rf /jemalloc-stable \
 && mkdir /jemalloc-new && cd /jemalloc-new &&\
      wget https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_NEW}/jemalloc-${JEMALLOC_NEW}.tar.bz2 &&\
      tar -xjf jemalloc-${JEMALLOC_NEW}.tar.bz2 && cd jemalloc-${JEMALLOC_NEW} && ./configure --prefix=/usr --with-install-suffix=${JEMALLOC_NEW} && make build_lib && make install_lib &&\
      cd / && rm -rf /jemalloc-new \
 && gem update --system \
 && gem install bundler --force \
 && rm -rf /usr/local/share/ri/${RUBY_VERSION}/system \
 && /tmp/install/imagemagick \
 # Validate install
 && ruby -Eutf-8 -e "v = \`convert -version\`; %w{png tiff jpeg freetype}.each { |f| unless v.include?(f); STDERR.puts('no ' + f +  ' support in imagemagick'); exit(-1); end }" \
 && /tmp/install/pngcrush \
 && /tmp/install/gifsicle \
 && /tmp/install/pngquant \
 && addgroup --gid 1000 discourse \
 && adduser --system --uid 1000 --ingroup discourse --shell /bin/bash discourse \
 && cd /home/discourse \
 && mkdir -p tmp/pids \
 && mkdir -p ./tmp/sockets \
 && git clone --branch ${DISCOURSE_VERSION} https://github.com/discourse/discourse.git \
 && chown -R discourse:discourse . \
 && cd /home/discourse/discourse \
 && git remote set-branches --add origin tests-passed \
 && sed -i 's/daemonize true/daemonize false/g' ./config/puma.rb \
 && bundle config build.nokogiri --use-system-libraries \
 && bundle install --deployment --verbose --without test --without development --retry 3 --jobs 4 \
 && find /home/discourse/discourse/vendor/bundle -name tmp -type d -exec rm -rf {} + \
 && apt-get remove -y --purge ${BUILD_DEPS} \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

RUN cd /home/discourse/discourse/plugins \
 && for plugin in $(cat /tmp/install/plugin-list); do \
      git clone $plugin; \
    done \
 && chown -R discourse:discourse .

WORKDIR /home/discourse/discourse

USER discourse

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
