FROM ruby:3.0.5-alpine3.15 AS builder
LABEL maintainer="Rapid7"

ARG BUNDLER_CONFIG_ARGS="set clean 'true' set no-cache 'true' set system 'true' set without 'development test coverage'"
ENV APP_HOME=/usr/src/metasploit-framework
ENV TOOLS_HOME=/usr/src/tools
ENV BUNDLE_IGNORE_MESSAGES="true"
WORKDIR $APP_HOME

COPY Gemfile* metasploit-framework.gemspec Rakefile $APP_HOME/
COPY lib/metasploit/framework/version.rb $APP_HOME/lib/metasploit/framework/version.rb
COPY lib/metasploit/framework/rails_version_constraint.rb $APP_HOME/lib/metasploit/framework/rails_version_constraint.rb
COPY lib/msf/util/helper.rb $APP_HOME/lib/msf/util/helper.rb

RUN apk add --no-cache \
      autoconf \
      bash \
      bison \
      build-base \
      curl \
      ruby-dev \
      openssl-dev \
      readline-dev \
      sqlite-dev \
      postgresql-dev \
      libpcap-dev \
      libxml2-dev \
      libxslt-dev \
      yaml-dev \
      zlib-dev \
      ncurses-dev \
      git \
      go \
    && echo "gem: --no-document" > /etc/gemrc \
    && gem update --system \
    && gem install debug \
    && bundle config $BUNDLER_ARGS \
    && bundle install --jobs=8 \
    # temp fix for https://github.com/bundler/bundler/issues/6680
    && rm -rf /usr/local/bundle/cache \
    # needed so non root users can read content of the bundle
    && chmod -R a+r /usr/local/bundle

ENV GO111MODULE=off
RUN mkdir -p $TOOLS_HOME/bin && \
    cd $TOOLS_HOME/bin && \
    curl -O https://dl.google.com/go/go1.11.2.src.tar.gz && \
    tar -zxf go1.11.2.src.tar.gz && \
    rm go1.11.2.src.tar.gz && \
    cd go/src && \
    ./make.bash

FROM ruby:3.0.5-alpine3.15
LABEL maintainer="Rapid7"

ENV APP_HOME=/usr/src/metasploit-framework
ENV TOOLS_HOME=/usr/src/tools
ENV NMAP_PRIVILEGED=""
ENV METASPLOIT_GROUP=metasploit

# used for the copy command
RUN addgroup -S $METASPLOIT_GROUP

RUN apk add --no-cache bash sqlite-libs nmap nmap-scripts nmap-nselibs \
    postgresql-libs python2 python3 py3-pip ncurses libcap su-exec alpine-sdk \
    python2-dev python3-dev openssl-dev nasm mingw-w64-gcc
RUN apk add --no-cache libxslt
RUN apk add --no-cache libxml2
RUN apk add --no-cache libxslt-dev
RUN apk add --no-cache bind-tools
RUN apk add --no-cache net-snmp-tools

RUN /usr/sbin/setcap cap_net_raw,cap_net_bind_service=+eip $(which ruby)
RUN /usr/sbin/setcap cap_net_raw,cap_net_bind_service=+eip $(which nmap)

COPY --from=builder /usr/local/bundle /usr/local/bundle
RUN chown -R root:metasploit /usr/local/bundle
COPY . $APP_HOME/
COPY --from=builder $TOOLS_HOME $TOOLS_HOME
RUN chown -R root:metasploit $APP_HOME/
RUN chmod 664 $APP_HOME/Gemfile.lock
RUN gem update --system
RUN cp -f $APP_HOME/docker/database.yml $APP_HOME/config/database.yml
RUN curl -L -O https://github.com/pypa/get-pip/raw/3843bff3a0a61da5b63ea0b7d34794c5c51a2f11/get-pip.py && python get-pip.py && rm get-pip.py
RUN pip install wheel
RUN pip install impacket
RUN pip install requests
RUN pip install pymongo
RUN pip3 install python-nmap
RUN pip3 install pycryptodomex
RUN pip3 install pymongo
RUN pip3 install beautifulsoup4
RUN pip3 install lxml
RUN pip3 install tftpy

ENV GOPATH=$TOOLS_HOME/go
ENV GOROOT=$TOOLS_HOME/bin/go
ENV PATH=${PATH}:${GOPATH}/bin:${GOROOT}/bin

WORKDIR $APP_HOME

# we need this entrypoint to dynamically create a user
# matching the hosts UID and GID so we can mount something
# from the users home directory. If the IDs don't match
# it results in access denied errors.
ENTRYPOINT ["docker/entrypoint.sh"]

CMD ["./msfconsole", "-r", "docker/msfconsole.rc", "-y", "$APP_HOME/config/database.yml"]
