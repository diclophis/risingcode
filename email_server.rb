#JonBardin

class EmailServer < GServer
  TRANS = {
    :_begin	=>      [:_begin,	:helo, :ehlo, :quit],
    :ehlo	=>        [:xforward,	:mail_from, :quit],
    :xforward	=>    [:mail_from, :quit],
    :helo	=>        [:mail_from, :quit],
    :mail_from	=>  [:rcpt_to, :quit ],
    :rcpt_to	=>    [:rcpt_to, :data, :quit ],
    :data	=>        [:_end],
    :quit	=>        [],
    :_end	=>        [:ehlo]
  }
	attr_accessor :socket, :pstate, :state, :line, :continue, :saybye, :body, :xf, :from, :to, :helo, :esmtp
	attr_accessor :host, :port, :body, :xf, :from, :to, :esmtp, :delivered

  def self.daemon (name, boot = "boot", port = 2525)
    Daemons.run_proc(name, {:dir_mode => :system}) do
      require boot
      email_server = self.new(port)
      Signal.trap(:KILL) do
        email_server.shutdown
        email_server.stop
        Camping::Models::Base.logger.debug("killing email_server")
      end
      Signal.trap(:INT) do
        email_server.shutdown
        email_server.stop
        Camping::Models::Base.logger.debug("interuptng email_server")
      end
      Signal.trap(:TERM) do
        email_server.shutdown
        email_server.stop
        Camping::Models::Base.logger.debug("terminating email_server")
      end
      Camping::Models::Base.logger.debug("starting email_server")
      email_server.start(1)
      email_server.join
    end
  end

	def process(socket)
		@socket = socket
		@pstate = :_begin
		@state = :_begin
		@esmtp = false
		@line = ''
		@continue = true
		@saybye = [ 221, "2.0.0 #{$apphost} #{$appname} Goodbye." ]
		@body = []
		@from = ''
		@to = []
		@xf = {}
		@helo = ''
		@host = "ASPMX.L.GOOGLE.COM"
		@port = 25 
		while(@continue)
			if(TRANS[@pstate].include? @state) then
				send(@state)
				@pstate = @state
			else
				error()
			end
			waitinput() if(@continue)
		end
		respond(*@saybye) if(@saybye.length > 0)
	end

	def respond(code, lines)
		c = code.to_s
		if(lines.respond_to? :to_ary) then
			l = lines.to_ary
		else
			l = [ lines.to_s ]
		end
		begin
			while(l.length > 1)
				p = c + '-' + l.shift
				@socket.print(p + "\r\n")
			end
			p = c + ' ' + l.shift
			@socket.print(p + "\r\n")
		rescue Exception => e
			@line = nil
			@continue = false
			@saybye = ''
		end
	end
	def error
		if(TRANS.has_key? @state) then
			respond(503, '5.5.1 Command out of sequence')
		else
			respond(502, '5.5.2 Command not recognized')	
		end
	end
	def waitinput
		while(true)
			begin
				@line = socket.gets
			rescue Exception => e
				@line = nil
				@continue = false
				@saybye = ''
			end
			if(@line.nil?) then
				return
			end
			@line.chomp!
			if(@line.length > 1024) then
				respond(501, '5.1.7 Line too long')
			else
				if(@state == :data) then
					if(@line == '.') then
						@state = :_end
						break
					end
					@line.gsub!(/^\.\./, '.')
					@body << @line
				else
					s = @line.sub(/ /, '_').downcase
					@state = TRANS.keys.find { |k| s =~ /^#{k.to_s}(\b|_)/ }
					@state = :nil if(@state.nil?)
					break
				end
			end
		end
	end
	def _begin()
		respond(220, "#{$apphost} ESMTP #{$appname} Hello !")
	end
	def helo
		@line.scan(/^helo +(.*)$/i) { |v| @helo = v }
		@esmtp = false
		respond(250, "#{$apphost}")
	end
	def ehlo
		@line.scan(/^ehlo +(.*)$/i) { |v| @helo = v }
		@esmtp = true
		respond(250, [ "#{$apphost}",
			       'PIPELINING',
			       'ENHANCEDSTATUSCODES',
			       '8BITMIME',
			       'XFORWARD NAME ADDR PROTO HELO' ])
	end
	def xforward
		@line.scan(/([A-Z]+)=(\S+)/i) { |k, v| @xf[k] = v }
		respond(250, [ '2.5.0 Ok XFORWARD' ])
	end
	def mail_from
    @from = @line.chomp.gsub("MAIL FROM:", "")
		respond(250, "2.1.0 Sender #{@from} OK")
	end
	def rcpt_to
    @to = @line.chomp
    respond(250, "2.1.5 Recipient #{@to} OK")
	end
	def data
		addr = @socket.peeraddr
		respond(354, 'End data with <CR><LF>.<CR><LF>')
		@body << "Received: from #{addr[2]}" + (addr[3].downcase != @helo ? " (HELO #{@helo})" : "") + " [#{addr[3]}]"
		@body << "\tby #{$apphost} (#{$appid}) with #{(@esmtp?'ESMTP':'SMTP')};"
		@body << "\t" + Time.now.rfc2822
  end
	def quit
		@continue = false
	end
	def _end
    begin
      if enqueue then
        respond(250, "Ok")
      else
        respond(554, "Transaction Failed")
      end
    rescue Exception => problem
      respond(554, "Transaction Failed")
      raise problem
    ensure
      @state = :ehlo
    end
	end

  def enqueue
    if true then
=begin
    if ((@from =~ /diclophis|jbardin/) != nil) then
      Camping::Models::Base.connection.verify!(60)
      #Camping::Models::Base.logger.debug(@body.join("\n"))
      m = TMail::Mail.parse(@body.join("\n"))
      image = nil
      text = nil
      if m.multipart? then
        m.parts.each do |mm|
          #Camping::Models::Base.logger.debug(mm.inspect)
          #Camping::Models::Base.logger.debug(mm.main_type)
          case mm.main_type
            when "image"
              image = RisingCode::Models::Image.new
              image.user_id = 1
              image.permalink = Time.now.to_i.to_s
              image.put(mm.body)
              image.save!
              Camping::Models::Base.logger.debug(image.inspect)
              #RisingCode::Models::Image.resize(mm.body, image.permalink)
            when "text"
              text = mm.body
            when "multipart"
          #Camping::Models::Base.logger.debug(mm.methods.inspect)
          #Camping::Models::Base.logger.debug(mm.body.inspect)
              text = mm.body
          end
        end
        if text then
          article = RisingCode::Models::Article.new
          article.autopop(1, m.subject) 
          #if image then
          #  article.excerpt = "!/images/public/#{image.thumb_permalink}!"
          #end
          if image then
            article.body = "!>/images/public/#{image.icon_permalink}!:/images/public/#{image.full_permalink}\n\n\n"
            article.body += text
          else
            article.body = text
          end
          article.save!
        end
      end
=end
      out_helo
      out_rcpt_to
      out_data
      return true
    else
      return false
    end
  end

	def out_helo
		begin
			smtp_connect
			l = smtp_gets
			if(l[0] / 100 != 2) then
				return [ l[0], l[1] ]
			end
			smtp_puts("ehlo #{$apphost}")
			l = smtp_gets
			if(l[0] / 100 != 2) then
				return [ l[0], l[1].to_a.join(', ') ]
			end
			if(@xf) then
				xf = l[1].find { |e| e =~ /^XFORWARD/i }
				if(xf) then
					xl = 'xforward'
					xf.split(/ /)[1..-1].each do |v|
						if(@xf[v]) then
							xl << " " + v + "=" + @xf[v]
						end
					end
					if(xl != 'xforward') then
						smtp_puts(xl)
						l = smtp_gets
						if(l[0] / 100 != 2) then
							return [ l[0], l[1].to_a.join(', ') ]
						end
					end
				end
			end
			smtp_puts("#{@from}")
			l = smtp_gets
			if(l[0] / 100 != 2) then
				return [ l[0], l[1].to_a.join(', ') ]
			end
		rescue Exception => e
      raise e
		end
	end

	def out_rcpt_to
    to = @to
		begin
			smtp_puts("#{to}")
			l = smtp_gets
			return [ l[0], l[1].to_a.join(', ') ]
		rescue Exception => e
			#return [ 451, "4.3.0 Queing error, #{e.to_s}" ]
      raise e
		end
	end

	def out_data
		begin
			smtp_puts("data")
			l = smtp_gets
			return [ l[0], l[1].to_a.join(', ') ] if(l[0] / 100 != 3)
			@body.each do |l|
				smtp_puts(l.gsub(/^\./, '..'))
			end
			smtp_puts('.')
			l = smtp_gets
		rescue Exception => e
			#return [ 451, "4.3.0 Queing error, #{e.to_s}" ]
      raise e
		end
		begin
			smtp_puts("quit")
			smtp_gets
		rescue Exception => e
      raise e
		end
		@sock.close
		return l
	end

  private

  def smtp_connect
		begin
			Timeout.timeout(10) do
				@sock = TCPSocket.new(@host, @port)
			end
    rescue Exception => e
      raise e
		end		
	end

	def smtp_gets
		c = 0
		t = []
		begin
			Timeout.timeout(60) do
				while(true)
					r = @sock.gets.chomp
					#puts "X<< " + r if($ldebug)
					if(r !~ /^(\d{3})([ -])(.*)$/) then
						raise SMTPFException, "unrecognized response (#{r})"
					else
						c = $1.to_i
						t.push($3)
						break unless($2 == '-')
					end
				end
			end
		rescue Exception => e
			raise e
		end		
		return [ c, (t.length == 1 ? t[0] : t) ]
	end
	def smtp_puts(r)
		begin
			Timeout.timeout(30) do
				#puts "X>> " + r if($ldebug)
				@sock.print(r + "\r\n")
			end
		rescue Exception => e
			raise e 
		end
	end

  def serve (io)
    begin
      process(io)
      #Camping::Models::Base.logger.debug("got message")
    rescue Exception => e
      Camping::Models::Base.logger.debug(e.message + "\n" + e.backtrace.join("\n"))
    end
  end
end

module ActionMailer
  
  module PartContainer

    # Add an inline attachment to a multipart message. 
    def inline_attachment(params, &block)
      params = { :content_type => params } if String === params
      params = { :disposition => "inline",
                 :transfer_encoding => "base64" }.merge(params)
      params[:headers] ||= {}
      params[:headers]['Content-ID'] = params[:cid]
      part(params, &block)
    end

  end

  class Part 

    def to_mail(defaults)
      part = TMail::Mail.new

      if @parts.empty?
        part.content_transfer_encoding = transfer_encoding || "quoted-printable"
        case (transfer_encoding || "").downcase
          when "base64" then
            part.body = TMail::Base64.folding_encode(body)
          when "quoted-printable"
            part.body = [Utils.normalize_new_lines(body)].pack("M*")
          else
            part.body = body
        end

        # Always set the content_type after setting the body and or parts

        # CHANGE: treat attachments and inline files the same
        if content_disposition == "attachment" || ((content_disposition == "inline") && filename)
            part.set_content_type(content_type || defaults.content_type, nil,
            squish("charset" => nil, "name" => filename))
        else
          part.set_content_type(content_type || defaults.content_type, nil,
            "charset" => (charset || defaults.charset))    
        end  
                     
        part.set_content_disposition(content_disposition, squish("filename" => filename))
        headers.each {|k,v| part[k] = v }
        # END CHANGE

      else
        if String === body
          part = TMail::Mail.new
          part.body = body
          part.set_content_type content_type, nil, { "charset" => charset }
          part.set_content_disposition "inline"
          m.parts << part
        end
          
        @parts.each do |p|
          prt = (TMail::Mail === p ? p : p.to_mail(defaults))
          part.parts << prt
        end
        
        part.set_content_type(content_type, nil, { "charset" => charset }) if content_type =~ /multipart/
      end
    
      part
    end
  end
end

module TMail

  class HeaderField   # redefine
  
      FNAME_TO_CLASS = {
        'date'                      => DateTimeHeader,
        'resent-date'               => DateTimeHeader,
        'to'                        => AddressHeader,
        'cc'                        => AddressHeader,
        'bcc'                       => AddressHeader,
        'from'                      => AddressHeader,
        'reply-to'                  => AddressHeader,
        'resent-to'                 => AddressHeader,
        'resent-cc'                 => AddressHeader,
        'resent-bcc'                => AddressHeader,
        'resent-from'               => AddressHeader,
        'resent-reply-to'           => AddressHeader,
        'sender'                    => SingleAddressHeader,
        'resent-sender'             => SingleAddressHeader,
        'return-path'               => ReturnPathHeader,
        'message-id'                => MessageIdHeader,
        'resent-message-id'         => MessageIdHeader,
        'in-reply-to'               => ReferencesHeader,
        'received'                  => ReceivedHeader,
        'references'                => ReferencesHeader,
        'keywords'                  => KeywordsHeader,
        'encrypted'                 => EncryptedHeader,
        'mime-version'              => MimeVersionHeader,
        'content-type'              => ContentTypeHeader,
        'content-transfer-encoding' => ContentTransferEncodingHeader,
        'content-disposition'       => ContentDispositionHeader,
       # 'content-id'                => MessageIdHeader,
        'subject'                   => UnstructuredHeader,
        'comments'                  => UnstructuredHeader,
        'content-description'       => UnstructuredHeader
      }
  
  end

end
