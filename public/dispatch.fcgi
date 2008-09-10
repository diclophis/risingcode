#!/usr/bin/ruby

require ENV['COMP_ROOT'] + "/risingcode"
require ENV['COMP_ROOT'] + "/boot"

Rack::Handler::FastCGI.run(RisingCode)
#run RisingCode
#Rack::Adapter::Camping.new(RisingCode)
