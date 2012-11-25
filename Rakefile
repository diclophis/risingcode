require 'rubygems'
require 'rake'
require './risingcode.rb'
require './boot'
 
desc "Default Task"
task :default => [ :migrate ]

desc "Migrate"
task :migrate do
  puts "migrating..."
  RisingCode::Models.create_schema
end

desc "documentation server"
task :document do
  #DocumentationServer.daemon(["stop", "-t"])
  #DocumentationServer.daemon(["zap", "-t"])
  DocumentationServer.daemon(["start", "-f"])
end
