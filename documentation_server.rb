#JonBardin

class DocumentationServer
  URI = "druby://:2527"
  SERVER = DRbObject.new(nil, URI)
  def self.daemon (argv)
    #Daemons.run_proc("documentation_server", {:ontop => true, :dir_mode => :system, :ARGV => argv}) do
    Daemons.run_proc("documentation_server", {:ontop => true, :dir_mode => :script, :ARGV => argv}) do
      require "/home/ubuntu/risingcode/risingcode"
      require "/home/ubuntu/risingcode/boot"
      #Camping::Models::Base.logger.debug("starting server")
      DRb.start_service(URI, self.new)
#      Signal.trap(:KILL) do
#        #Camping::Models::Base.logger.debug("killing server")
#      end
#      Signal.trap(:INT) do
#        #Camping::Models::Base.logger.debug("interuptng server")
#      end
#      Signal.trap(:TERM) do
#        #Camping::Models::Base.logger.debug("terminating server")
#      end
      DRb.thread.join
    end
  end
  def initialize
  end
  def controllers
    RisingCode::X.r
  end
  def models
    models = Array.new
    ObjectSpace.each_object { |object|
      if object.is_a? Class then
        if object.superclass == ActiveRecord::Base then
          models << object
        end
      end
    }
    return models.sort {|a,b| b.to_s <=> a.to_s}
  end
  def source_for (class_name)
    if class_name.respond_to? :urls then
      url_string = "< R(" + class_name.urls.collect{|url| "'" + url + "'"}.join(",") + ")"
    else
      url_string = ""
    end
    puts class_name
    if class_name == RisingCode::Models::SchemaInfo or class_name == RisingCode::Controllers::I or class_name == Camping::Models::SchemaInfo then
        puts "Wtf"
        return "unknown"
    else
      return highlight(RubyToRuby.translate(class_name).gsub("< nil", url_string), "rb")
    end
  end
  def highlight(content, extension)
    now = Digest::MD5.hexdigest(content)
    input_buffer = "/tmp/#{now}.#{extension}"
    output_buffer = "/tmp/#{now}.html"
    cache_buffer = "/tmp/#{now}.cache"
    unless File.exists?(cache_buffer) 
      input = File.new(input_buffer, "w")
      input.write(content)
      input.close
      input = nil
      worker = nil
      IO.popen("-") { |worker|
        if worker == nil
          ready = nil
          cmd = "/home/ubuntu/risingcode/tohtml #{input_buffer} #{output_buffer}"

cache_content = cmd
cache = File.new(cache_buffer, 'w')
cache.write(cache_content)
cache.close
cache = nil

          if system(cmd) then
            begin
              xml = File.open(output_buffer)
              doc = REXML::Document.new(xml)
              code_a = ""
              doc.root.elements["//body"].each { |element| 
                code_a += element.to_s.gsub("&#x20;", "&nbsp;").gsub("\n", "")
              }
              cache_content = '<span class="snippet">' + code_a + '</span>'
              cache = File.new(cache_buffer, 'w')
              cache.write(cache_content)
              cache.close
              cache = nil
             rescue => problem
              cache_content = problem.inspect
              cache = File.new(cache_buffer, 'w')
              cache.write(cache_content)
              cache.close
              cache = nil
             end
          end
          Process.exit!(0)
        else
          i = 0
          until ready = IO.select([worker], nil, nil, 1) do
            break if (i+=1) > 10
          end
          true
        end
      }
    end
    File.open(cache_buffer).readlines.join("").gsub("\n", "")
  end
end
