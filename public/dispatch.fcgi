#!/usr/bin/ruby

require ENV['COMP_ROOT'] + "/risingcode"

fast = Camping::FastCGI.new
fast.mount("/", RisingCode)
fast.start
