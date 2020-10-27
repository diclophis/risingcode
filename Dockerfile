FROM ubuntu:bionic-20180526

ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -yy libwxsqlite3-3.0-dev ruby2.5 ruby-bundler ruby-dev build-essential

RUN useradd --create-home --uid 1001 application

COPY Gemfile /home/application/

USER application

RUN cd /home/application && bundle install --path=vendor/bundle

#RUN cd /home/application && (grep -rl "ActiveRecord::Migration" vendor/bundle | xargs -I{} sed -i "" "s/ActiveRecord::Migration/ActiveRecord::Migration[6.0]/g" {})

COPY [".", "/home/application"]

#COPY lib /home/application/lib/
#COPY public /home/application/public/
#COPY mime.yaml config.ru tngd.rb application.rb /home/application/

ENV SERVER_PORT 3000
WORKDIR /home/application
USER application
CMD ["bundle", "exec", "ruby", "risingcode.rb"]
