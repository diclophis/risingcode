FROM ubuntu:jammy-20221101

ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -yy git vim vim-runtime ruby ruby-bundler ruby-dev libsqlite3-dev libssl-dev build-essential --no-install-recommends

RUN useradd --create-home --uid 1000 application

COPY Gemfile /home/application/

USER application

RUN cd /home/application && bundle install --path=vendor/bundle

COPY [".", "/home/application"]

WORKDIR /home/application
USER application
CMD ["bundle", "exec", "ruby", "risingcode.rb"]
