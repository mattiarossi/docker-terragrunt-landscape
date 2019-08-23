FROM golang:alpine
MAINTAINER MattiaRossi <mattia.rossi@gmail.comt>

ENV TERRAFORM_VERSION=0.11.14
ENV TERRAGRUNT_VERSION=0.18.8-cintra
ENV TERRAGRUNT_TFPATH=/bin/terraform
RUN apk add --update git bash openssh
ENV TF_DEV=true
ENV TF_RELEASE=true

WORKDIR $GOPATH/src/github.com/hashicorp/terraform
RUN git clone https://github.com/hashicorp/terraform.git ./ && \
    git checkout v${TERRAFORM_VERSION} && \
    /bin/bash scripts/build.sh


RUN curl -sL https://github.com/gruntwork-io/mattiarossi/terragrunt-binaries/releases/download/v$TERRAGRUNT_VERSION/terragrunt_linux_amd64 \
  -o /bin/terragrunt && chmod +x /bin/terragrunt


RUN apk add --no-cache \
        gmp-dev

# skip installing gem documentation
RUN mkdir -p /usr/local/etc \
    && { \
        echo 'install: --no-document'; \
        echo 'update: --no-document'; \
    } >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.6
ENV RUBY_VERSION 2.6.3
ENV RUBY_DOWNLOAD_SHA256 11a83f85c03d3f0fc9b8a9b6cad1b2674f26c5aaa43ba858d4b0fcc2b54171e1
# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
# readline-dev vs libedit-dev: https://bugs.ruby-lang.org/issues/11869 and https://github.com/docker-library/ruby/issues/75
RUN set -ex \
    \
    && apk add --no-cache --virtual .ruby-builddeps \
        autoconf \
        bison \
        bzip2 \
        bzip2-dev \
        ca-certificates \
        coreutils \
        dpkg-dev dpkg \
        gcc \
        gdbm-dev \
        glib-dev \
        libc-dev \
        libffi-dev \
        libxml2-dev \
        libxslt-dev \
        linux-headers \
        make \
        ncurses-dev \
        openssl \
        openssl-dev \
        procps \
        readline-dev \
        ruby \
        tar \
        xz \
        yaml-dev \
        zlib-dev \
    \
    && wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz" \
    && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum -c - \
    \
    && mkdir -p /usr/src/ruby \
    && tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1 \
    && rm ruby.tar.xz \
    \
    && cd /usr/src/ruby \
    \
# https://github.com/docker-library/ruby/issues/196
# https://bugs.ruby-lang.org/issues/14387#note-13 (patch source)
# https://bugs.ruby-lang.org/issues/14387#note-16 ("Therefore ncopa's patch looks good for me in general." -- only breaks glibc which doesn't matter here)
    && wget -O 'thread-stack-fix.patch' 'https://bugs.ruby-lang.org/attachments/download/7081/0001-thread_pthread.c-make-get_main_stack-portable-on-lin.patch' \
    && echo '3ab628a51d92fdf0d2b5835e93564857aea73e0c1de00313864a94a6255cb645 *thread-stack-fix.patch' | sha256sum -c - \
    && patch -p1 -i thread-stack-fix.patch \
    && rm thread-stack-fix.patch \
    \
# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
    && { \
        echo '#define ENABLE_PATH_CHECK 0'; \
        echo; \
        cat file.c; \
    } > file.c.new \
    && mv file.c.new file.c \
    \
    && autoconf \
    && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
# the configure script does not detect isnan/isinf as macros
    && export ac_cv_func_isnan=yes ac_cv_func_isinf=yes \
    && ./configure \
        --build="$gnuArch" \
        --disable-install-doc \
        --enable-shared \
    && make -j "$(nproc)" \
    && make install \
    \
    && runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && apk add --no-network --virtual .ruby-rundeps $runDeps \
        bzip2 \
        ca-certificates \
        libffi-dev \
        procps \
        yaml-dev \
        zlib-dev \
    && apk del --no-network .ruby-builddeps \
    && cd / \
    && rm -r /usr/src/ruby \
# rough smoke test
    && ruby --version && gem --version && bundle --version

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
# path recommendation: https://github.com/bundler/bundler/pull/6469#issuecomment-383235438
ENV PATH $GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
# (BUNDLE_PATH = GEM_HOME, no need to mkdir/chown both)
RUN gem install terraform_landscape

ENTRYPOINT ["/bin/terragrunt"]
