require 'rubygems'
require 'rake'

require './risingcode.rb'
require './boot'
 
desc "Default Task"
task :default => [ :schema ]

desc "Migrate Schema"
task :schema do
  puts "migrating schema..."
  RisingCode::Models.create_schema
end

#desc "documentation server"
#task :document do
#  #DocumentationServer.daemon(["stop", "-t"])
#  #DocumentationServer.daemon(["zap", "-t"])
#  #DocumentationServer.daemon(["start", "-f"])
#end
