#!/usr/bin/ruby



require ENV['COMP_ROOT'] + "/risingcode"
require ENV['COMP_ROOT'] + "/boot"

require 'rubygems'
gem 'rack', '= 1.0.0'

Rack::Handler::FastCGI.run(Rack::Adapter::Camping.new(RisingCode))
#run RisingCode
#Rack::Adapter::Camping.new(RisingCode)
