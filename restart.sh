#!/bin/sh

sudo killall -9 ruby
/etc/init.d/apache2 reload
mv /tmp/cache/risingcode.com /tmp/cache/risingcode.com.wtf.`date +'%N'`
ruby risingcode.rb documentation_server zap
ruby risingcode.rb documentation_server start
