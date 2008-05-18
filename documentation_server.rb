#JonBardin

class DocumentationServer
  def self.daemon (name, boot = "boot", drb = nil)
    Daemons.run_proc(name, {:dir_mode => :system}) do
      require boot
      server = self.new
      DRb.start_service(drb, server)
      Signal.trap(:KILL) do
        Camping::Models::Base.logger.debug("killing server")
      end
      Signal.trap(:INT) do
        Camping::Models::Base.logger.debug("interuptng server")
      end
      Signal.trap(:TERM) do
        Camping::Models::Base.logger.debug("terminating server")
      end
      Camping::Models::Base.logger.debug("starting server")
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
    return RedCloth.highlight(RubyToRuby.translate(class_name).gsub("doccom", "#").gsub("< nil", url_string))
  end
end
