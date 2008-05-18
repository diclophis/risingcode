#!/usr/bin/ruby


def doccom (comment)
end

#TODO: email posting, comments, openid login with captcha first time test, loading image for gallery
#upcoming interface, iphone friendly, cronned main search for SF (front page), with expiry query interface
#me links

require 'gserver'
require 'uri'
require 'ftools'
require 'rubygems'
require 'RMagick'
include Magick
require 'time'
require 'timeout'
require 'open3'
require 'redcloth'
require 'digest/md5'
require 'daemons'
require 'benchmark'
require 'ruby2ruby'
require 'drb'
require 'uuidtools'
require 'right_aws'

#import into the system
require 'camping'
require 'camping/fastcgi'
require 'camping/session'
require 'acts_as_versioned'
require 'action_mailer'
require 'tmail'
require 'openid'
require 'openid/store/filesystem'
require 'openid/consumer'
require 'openid/extensions/sreg'


#import into this file
require '/var/www/risingcode.com/acts_as_taggable'
require '/var/www/risingcode.com/tag_list'
require '/var/www/risingcode.com/delicious'
require '/var/www/risingcode.com/upcoming'
require '/var/www/risingcode.com/email_server'
require '/var/www/risingcode.com/documentation_server'

Camping.goes :RisingCode

class RedCloth
  def self.highlight(content)
    now = Digest::MD5.hexdigest(content)
    input_buffer = "/tmp/#{now}.rb"
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
          cmd = "/var/www/risingcode.com/tohtml #{input_buffer} #{output_buffer}"
          wang = system(cmd)
          xml = File.open(output_buffer)
          doc = REXML::Document.new(xml)
          code_a = doc.root.elements["//body/p"].to_s.gsub("&#x20;", "&nbsp;").gsub("\n", "")
          cache_content = '<span class="snippet">' + code_a + '</span>'
          cache = File.new(cache_buffer, 'w')
          cache.write(cache_content)
          cache.close
          cache = nil
          Process.exit!(0)
        else
          i = 0
          until ready = IO.select([worker], nil, nil, 1) do
            Camping::Models::Base.logger.debug("waiting #{input_buffer}")
            break if (i+=1) > 10
          end
          Camping::Models::Base.logger.debug("gave up on #{input_buffer}")
          true
        end
      }
    end
    File.open(cache_buffer).readlines.join("").gsub("\n", "")
  end
  def textile_code(tag, atts, cite, content)
    begin
      Camping::Models::Base.logger.debug("parsing... #{content}")
      return @@documentation_server.source_for(content.strip.constantize)
    rescue Exception => problem
      Camping::Models::Base.logger.debug("#{problem}")
    end
  end
end

module SessionSupport
  def self.included(base)
    base.class_eval do
      def self.include_session_support
        true
      end
    end
  end
end

module RisingCode
  def service(*a)
    session = Camping::Models::Session.persist(@cookies)
    app = self.class.name.gsub(/^(\w+)::.+$/, '\1')
    @state = (session[app] ||= Camping::H[])
    hash_before = Marshal.dump(@state).hash
    s = super(*a)
    if @method == "get" and @input.length == 0 and not @env['REQUEST_URI'].include?("dashboard") and not @env['REQUEST_URI'].include?("dangotalk") then
      cache_directory = "/tmp/cache/risingcode.com/#{@env['REQUEST_URI']}"
      File.makedirs(cache_directory)
      cache_filename = "#{cache_directory}/index.html"
      cache_file = File.new(cache_filename, "w")
      #cache_file.write(s.body)
      cache_file.close
    end
    if session
      hash_after = Marshal.dump(@state).hash
      unless hash_before == hash_after
          session[app] = @state
          session.save
      end
    end
    return self
  end

  def log_user_out
    @state.user_id = nil
  end

  def user_logged_in
    @state.user_id != nil
  end

  def view_images
    @viewing_images = true
    yield
  end

  def other_layout
    @content_class = "other"
    @no_header = true
    @no_sidebar = true
    yield
  end

  def no_sidebar
    @no_sidebar
  end

  def no_header
    @no_header
  end

  def viewing_images
    @viewing_images
  end

  def administer (current_action = nil)
    if user_logged_in then 
      @administering = true
      @current_action = current_action
      other_layout {
        yield
      }
    else
      redirect(R(Controllers::Login, nil))
    end
  end

  def administering
    @administering
  end
end

module RisingCode::Models
  class CreateRisingCode < V 1 
    def self.up
      create_table :sessions, :force => true do |t|
        t.column :hashid,      :string,  :limit => 32
        t.column :created_at,  :datetime
        t.column :ivars,       :text
      end
      create_table :risingcode_articles, :force => true do |t|
        t.column :user_id,  :integer, :null => false
        t.column :title, :string, :limit => 255, :null => false
        t.column :permalink, :string, :limit => 255, :null => false
        t.column :excerpt, :string, :limit => 255
        t.column :body, :text
        t.column :created_at, :datetime, :null => false
        t.column :updated_at, :datetime, :null => false
        t.column :published_on, :datetime, :defaut => nil
      end
      Article.create_versioned_table
    end
    def self.down
      drop_table :articles
      Article.drop_versioned_table
    end
  end

  class AddTags < V 2
    def self.up
      create_table :risingcode_tags, :force => true do |t|
        t.column :name, :string
      end
      
      create_table :risingcode_taggings, :force => true do |t|
        t.column :tag_id, :integer
        t.column :taggable_id, :integer
        t.column :taggable_type, :string
        t.column :created_at, :datetime
      end
      
      add_index :risingcode_taggings, :tag_id
      add_index :risingcode_taggings, [:taggable_id, :taggable_type]
    end

    def self.down
      drop_table :taggings
      drop_table :tags
    end
  end

  class AddImages < V 3
    def self.up
      create_table :risingcode_images, :force => true do |t|
        t.column :user_id,  :integer, :null => false
        t.column :permalink, :string, :null => false
        t.column :created_at, :datetime, :null => false
      end
    end

    def self.down
      drop_table :risingcode_images
    end
  end

  class AddIncludeInHeaderFlagToTags < V 4
    def self.up
      add_column :risingcode_tags, :include_in_header, :boolean, :default => false
    end

    def self.down
      remove_column :risingcode_tags, :include_in_header
    end
  end

  class AddUsers < V 5
    def self.up
      create_table :risingcode_users, :force => true do |t|
        t.column :openid_url,  :text
        t.column :openid_attributes, :text, :null => false
        t.column :created_at, :datetime, :null => false
      end
    end

    def self.down
      drop_table :risingcode_users
    end
  end

  class AddDisplayIdentifierToUsers < V 6
    def self.up
      add_column :risingcode_users, :display_identifier, :text
    end

    def self.down
      remove_column :risingcode_users, :display_identifier
    end
  end

  class AddComments < V 7
    def self.up
      create_table :risingcode_comments, :force => true do |t|
        t.column :user_id,  :integer
        t.column :body, :text
        t.column :created_at, :datetime, :null => false
      end
    end

    def self.down
      drop_table :risingcode_comments
    end
  end

  class AddArticleIdToComments < V 8
    def self.up
      add_column :risingcode_comments, :article_id, :integer
    end

    def self.down
    end
  end

  class AddRootToUsers < V 9
    def self.up
      add_column :risingcode_users, :root, :boolean, :default => false
    end

    def self.down
    end
  end

  class AddMoreOpenIDToUsers < V 10
    def self.up
      add_column :risingcode_users, :openid_server, :text
      add_column :risingcode_users, :openid_delegate, :text
      add_column :risingcode_users, :openid2_provider, :text
      add_column :risingcode_users, :x_xrds_location, :text
    end

    def self.down
    end
  end


  class User < Base
    @@realm = nil
    serialize :openid_attributes

    def self.realm
      "http://" + @@realm
    end

    def self.realm=(realm)
      @@realm = realm
    end

    def self.get_authorized_action_url (openid_url, return_to_url, passthru = nil)
      @state_holder = Hash.new
      store = ::OpenID::Store::Filesystem.new("/tmp")
      openid_consumer = ::OpenID::Consumer.new(@state_holder, store)
      check_id_request = openid_consumer.begin(openid_url)
      openid_sreg = ::OpenID::SReg::Request.new(['nickname'])
      check_id_request.add_extension(openid_sreg)
      url = check_id_request.redirect_url(self.realm, self.realm + return_to_url)
      return [@state_holder, url]
    end

    def self.find_by_openid_url! (current_state, input, action_url) 
      this_url = self.realm + action_url
      store = ::OpenID::Store::Filesystem.new("/tmp")
      openid_consumer = ::OpenID::Consumer.new(current_state, store)
      openid_response = openid_consumer.complete(input, this_url)
      if openid_response.status == :success then
        display_identifier = openid_response.display_identifier
        identity_url = openid_response.identity_url
        openid_sreg = ::OpenID::SReg::Response.from_success_response(openid_response)
        user = User.find(:first, :conditions => ["openid_url = ?", identity_url])
        user ||= User.new
        user.root = User.find_by_root(true) == nil
        user.openid_url = identity_url
        user.display_identifier = display_identifier
        user.openid_attributes = openid_sreg
        user.save!
        return user
      else
        raise "Invalid login"
      end
    end

    def nickname
      unless openid_attributes["nickname"].nil?
        openid_attributes["nickname"]
      else
        openid_url
      end
    end
  end

  class Comment < Base
    belongs_to :user
    belongs_to :article
  end

  class Article < Base
    validates_presence_of :user_id
    validates_presence_of :title, :if => :title
    validates_uniqueness_of :title
    validates_uniqueness_of :permalink
    acts_as_versioned
    acts_as_taggable
    has_many :comments
    belongs_to :user

    def autopop(user_id, title = nil)
        Camping::Models::Base.logger.debug("AUTOPOP")
        Camping::Models::Base.logger.debug(self.inspect)
      self.user_id = user_id
      self.published_on = Time.now + 1.hour
      self.title = title 
      self.title ||= Time.now.to_f
      (1..100).each { |i|
        self.permalink = "/#{published_on.year}/#{published_on.month}/#{published_on.day}/#{i.ordinalize}"
        Camping::Models::Base.logger.debug(self.inspect)
        break if valid?
      }
    end
  end

  class Image < Base
    AWS_ID = '1SC4KXT7V1JYK1NDCDR2'
    SECRET_KEY = 'QEWX0W7qE/X+EUGWISTTtiEBs3FIi8oyBV+3Ie5k'
    @@s3 = ::RightAws::S3.new(AWS_ID, SECRET_KEY, {:multi_thread => true, :port => 80, :protocol => 'http'})
    @@s3interface = ::RightAws::S3Interface.new(AWS_ID, SECRET_KEY, {:multi_thread => true})
    @@bucket = @@s3.bucket('risingcode', true)
    validates_presence_of :user_id

    def put_key (x_key, blob)
      get_key(x_key).put(blob, 'public-read')
    end

    def get_key (x_key)
      RightAws::S3::Key.create(@@bucket, self.permalink + "_" + x_key.to_s)
    end

    def public_link(x_key = :main)
      get_key(x_key).public_link
    end

    def thumb_permalink
      public_link(:thumb)
    end

    def full_permalink
      public_link(:main)
    end
    
    def icon_permalink
      public_link(:icon)
    end

    def x_put (blob)
      self.permalink = UUID.random_create.to_s if self.permalink.blank?
      imgs = Magick::Image.from_blob(blob)
      first = imgs.first
      case first.get_exif_by_entry("Orientation") && first["EXIF:Orientation"]
        when "6"
          first.rotate!(90)
          first["EXIF:Orientation"] = "1"
        when "3"
          first.rotate!(180)
          first["EXIF:Orientation"] = "1"
        when "8"
          first.rotate!(270)
          first["EXIF:Orientation"] = "1"
      end
      sizes = {
        :main => {:cols => 640, :rows => 480},
        :thumb => {:cols => 400},
        :icon => {:cols => 128}
      }.each { |x_key, size|
        geometry = if size[:rows] then
          "#{size[:cols]}x#{size[:rows]}>"
        else
          "#{size[:cols]}x"
        end
        first.change_geometry(geometry) { |cols, rows, img|
          put_key(x_key, img.resize(cols, rows).to_blob)
        }
      }
    end
  end

  class HeatmapImage
    def self.create (name)
      Kernel.srand
      max_x = 640
      max_y = 480
      points = Array.new
      conf = {
        'dotimage' => '/var/www/risingcode.com/public/images/bolilla.png',
        'colorimage' => '/var/www/risingcode.com/public/images/colors.png',
        'opacity' => "0.50",
        'dotwidth' => 64
      }
      max_x = max_x
      max_y = max_y
      halfwidth = conf['dotwidth'] / 2
      intensity = (100 - (100 / 1).ceil)
      images = Magick::ImageList.new
      colored_images = Magick::ImageList.new
      dots = images.new_image((max_x + halfwidth), (max_y + halfwidth))
      dot = Magick::Image.read(conf['dotimage']).first.colorize(intensity, intensity, intensity, "white")
      color = Magick::Image.read(conf['colorimage']).first
      500.times {
        x = Kernel.rand(max_x)
        y = Kernel.rand(max_y)
        dots.composite!(dot, ((x)-halfwidth),  ((y)-halfwidth), Magick::MultiplyCompositeOp)
      }
      (ImageList.new << (ImageList.new << dots.negate << color).fx("v.p{0,u*v.h}")).fx("0.25", ChannelType::AlphaChannel).write(name)
      return name
    end
  end

  class Tagging < Base
    belongs_to :tag
    belongs_to :taggable, :polymorphic => true
    
    def after_destroy
      if Tag.destroy_unused and tag.taggings.count.zero?
        tag.destroy
      end
    end
  end

  class Tag < Base
    has_many :taggings
    validates_presence_of :name
    validates_uniqueness_of :name
    cattr_accessor :destroy_unused
    self.destroy_unused = false
    
    def self.find_or_create_with_like_by_name(name)
      find(:first, :conditions => ["name LIKE ?", name]) || create(:name => name)
    end
    
    def ==(object)
      super || (object.is_a?(Tag) && name == object.name)
    end
    
    def to_s
      name
    end
    
    def count
      read_attribute(:count).to_i
    end
  end
  class CacheObserver < ::Camping::Models::A::Observer
    observe Article, Comment, Image, Tag
    def after_save (record)
      Camping::Models::Base.logger.debug(record.inspect)
      if File.exists?("/tmp/cache/risingcode.com") then
        File.rename("/tmp/cache/risingcode.com", "/tmp/cache/risingcode.com.#{Time.now.to_i}")
      end
    end
  end
end

module RisingCode::Controllers
  class Contact < R("/contact")
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      render :contact
    end
  end

  class Login < R("/dashboard/login(.*)")
    include Camping::Session
    def get(*args)
      begin
        if (@input.has_key?("openid.mode")) then
          user = User.find_by_openid_url!(@state, @input, R(Login, nil))
          @state.user_id = user.id
          return redirect(R(Dashboard))
        else
          raise "Login Required"
        end
      rescue Exception => e
        @login_exception = e
        other_layout {
          render :login 
        }
      end
    end
    def post(*args)
      begin
        new_state, authorized_action_url = User.get_authorized_action_url(@input.openid_url, R(Login, nil))
        @state = new_state
        redirect(authorized_action_url)
      rescue Exception => e
        @login_exception = e
        other_layout {
          render :login
        }
      end
    end
  end

  class Dashboard < R("/dashboard")
    include SessionSupport
    def get
        Camping::Models::Base.logger.debug("wang5")
    raise "wtf"
      administer { 
        render :dashboard 
      }
    end
  end

  class Logout < R("/dashboard/logout")
    def get
      log_user_out
      redirect R(Index)
    end
  end

  class About < R('/about')
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      render :about
    end
  end

  class OpenID < R('/about/openid')
    def get
      other_layout {
        render :openid
      }
    end
  end

  class Resume < R('/about/resume')
    def get
      other_layout {
        render :resume
      }
    end
  end

  class Images < R('/images/', '/images/public/([a-zA-Z0-9\-]+).png', '/images/([a-zA-Z0-9\-]+)/(\d*)')
    def get (*args)
      if args.length == 0 then
        view_images {
          @tags = Tag.find_all_by_include_in_header(true)
          @images = Image.find(:all, :order => "created_at desc")
          render :images
        }
      else
        args.inspect
      end
    end
  end

  class Events < R('/events', '/event/(\w+)/(.*)')
    def get (event_id = nil, event_name = nil)
      @tags = Tag.find_all_by_include_in_header(true)
      unless event_id.nil?
        @event = Upcoming::Event.get_info(event_id)
        unless @event.nil?
          @map_url = "http://maps.google.com/maps?q=" + C.escape("#{@event.venue_address}, #{@event.venue_city}, #{@event.venue_state_name}")
          @venue_url = @event.venue_url.length > 0 ? @event.venue_url : "http://upcoming.yahoo.com/event/#{@event.id}"
          render :event
        else
          @status = 404
          "event not found"
        end
      else
        render :events
      end
    end
  end

  class Bookmarks < R('/bookmarks', '/bookmarks/(\d+)/(\d+)/(\d+)')
    def get (*args)
      @tags = Tag.find_all_by_include_in_header(true)
      @bookmarks = Delicious::Bookmarks.all(0, 99999)
      @bookmarks_for_today = nil
      @bookmarks_for_tomorrow = nil
      @bookmarks_for_yesterday = nil
      @days = @bookmarks.keys.sort
      @index = nil
      case args.length
        when 0
          @today = Time.now
          until @index = @days.index(@today.strftime("%Y-%m-%d")) do
            @today = @today - 24.hours 
          end

        when 3
          @today = Date.parse(args.join("/")) 
          @index = @days.index(@today.strftime("%Y-%m-%d"))
      end
      if @index then
        @bookmarks_for_today = @bookmarks[@today.strftime("%Y-%m-%d")]
        if @days[@index+1] then
          @tomorrow = Date.parse(@days[@index+1]) 
          @bookmarks_for_tomorrow = @bookmarks[@tomorrow.strftime("%Y-%m-%d")] 
        end

        if @days[@index-1] then
          @yesterday = Date.parse(@days[@index-1]) 
          @bookmarks_for_yesterday = @bookmarks[@yesterday.strftime("%Y-%m-%d")] 
        end
        render :bookmarks
      else
        redirect(R(Bookmarks))
      end
    end
  end

  class Comments < R('/comment/(\d+)(.*)')
    def get (article_id, junk = nil)
      article = Article.find(article_id)
      unless article.nil?
        if (@input.has_key?("openid.mode")) then
          this_url = User.realm + R(Comments, article_id, nil)
          store = ::OpenID::Store::Filesystem.new("/tmp")
          openid_consumer = ::OpenID::Consumer.new(@state, store)
          openid_response = openid_consumer.complete(@input, this_url)
          if openid_response.status == :success then
            display_identifier = openid_response.display_identifier
            identity_url = openid_response.identity_url
            openid_sreg = ::OpenID::SReg::Response.from_success_response(openid_response)
            user = User.find(:first, :conditions => ["openid_url = ?", identity_url])
            user ||= User.new
            user.openid_url = identity_url
            user.display_identifier = display_identifier
            user.openid_attributes = openid_sreg
            user.save!
            comment = Comment.new
            comment.user_id = user.id
            comment.article_id = article.id
            comment.body = @state.comment_body
            comment.save!
            return redirect(article.permalink) 
          end
        end
      end
      raise "fail"
    end
    def post (article_id, junk = nil)
      article = Article.find(article_id)
      unless article.nil?
        @state.openid_url = @input.openid_url
        @state.comment_body = @input.body
        store = ::OpenID::Store::Filesystem.new("/tmp")
        openid_consumer = ::OpenID::Consumer.new(@state, store)
        check_id_request = openid_consumer.begin(@input.openid_url)
        openid_sreg = ::OpenID::SReg::Request.new(['nickname'])
        check_id_request.add_extension(openid_sreg)
        return_to_url = User.realm + R(Comments, article_id, nil)
        redirect_url = check_id_request.redirect_url(User.realm, return_to_url)
        return redirect(redirect_url)
      end
      raise "fail"
    end
  end


  class Sources < R('/sources')
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      @controllers = Hash.new
      @models = Hash.new
      @@documentation_server.controllers.each { |controller|
        @controllers[controller] = @@documentation_server.source_for(controller)
      }
      @@documentation_server.models.each { |model|
        @models[model] = model
      }
      render :sources
    end
  end

  class DangoTalkReadme < R('/dangotalk/readme')
    include SessionSupport
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      @state[:read_readme] = true
      render(:dangotalk_readme)
    end
  end

  class DangoTalkSource < R('/dangotalk/source')
    include SessionSupport
    def get
      source = "/root/dangotalk-march.tar.gz"
      if @state[:read_readme] then
        @headers['Content-Type'] = "application/gzip"
        @headers['Content-Disposition'] = "attachment; filename=dangotalk.tar.gz"
        @headers['Content-Length'] = File.size(source)
        File.read(source)
      else
        redirect(R(DangoTalkReadme))
      end
    end
  end

  class Index < R('/', '/(articles)', '/([a-zA-Z0-9 ]+)/(\d*)', '/(\d+)/(\d+)/(\d+)', '/(\w+)/(\w+)/(\w+)/([\w-]+)')
    def get(*args)
      @limit = 5
      @offset = 0
      @use_page_navigation = false
      @use_date_navigation = false
      @include_openid_delegation = false
      @tags = Tag.find_all_by_include_in_header(true)
      if args.empty? then
        @limit = 1
        @current_action = :index
        @permalink = "%"
        @now = Time.now
        @use_date_navigation = true
        @include_openid_delegation = true
      elsif args.length == 1 then
        @articles = Article.find(
          :all,
          :order => "published_on asc")
        @use_date_navigation = true
        return render(:articles)
      elsif args.length == 2 then
        @permalink = "%"
        @now = Time.now
        @tag = args[0]
        @page = args[1].to_i
        @offset = (@page - 1) * @limit if @page > 0
        @articles = Article.find_tagged_with(
          @tag,
          :limit => @limit, 
          :offset => @offset,
          :conditions => ["permalink like ? and date(published_on) <= ?", @permalink, @now], 
          :order => "published_on desc")
        @current_action = @tag.to_s.intern
        @use_page_navigation = true
      elsif args.length == 3 then
        @permalink = "%"
        @now = Date.parse(args.join("/")) 
        @limit = 99;
        @use_date_navigation = true
      else
        @permalink = "/" + args.join("/")
        @now = Time.now
        @limit = 1
        @use_date_navigation = true
      end
      @articles = Article.find(
        :all, 
        :limit => @limit, 
        :offset => @offset,
        :conditions => ["permalink like ? and date(published_on) <= ?", @permalink, @now], 
        :order => "published_on desc") if @articles.nil?
      @old_ranger = Article.find(
        :first,
        :conditions => ["date(published_on) <= ? and id < ?", Time.now, @articles.last.id],
        :limit => @limit,
        :order => "published_on asc") if @articles.length > 0
      @new_ranger = Article.find(
        :first,
        :conditions => ["date(published_on) <= ? and id > ?", Time.now, @articles.first.id],
        :limit => @limit,
        :order => "published_on desc") if @articles.length > 0
      @single = @articles.length == 1
      doccom %{wang chung what the fuck}
      render :index
    end
  end

  class Heatmap < R("/heatmap(.*)")
    def get (junk)
      created_image_file = false
      heatmap_id = Time.now.to_i
      dir = "/tmp/cache/risingcode.com/heatmaps/#{heatmap_id}"
      File.makedirs(dir)
      name = "png:#{dir}/index.png"
      IO.popen("-") { |worker|
        unless worker
          created_image_file = HeatmapImage.create(name)
        else
          created_image_file = true
        end
      }
      if created_image_file then
        "<html><body style=\"background:url(/images/stripe.gif)\"><img src=\"/heatmaps/#{heatmap_id}\"/></body></html>"
      end
    end
  end

  class RetrieveArticles < R("/dashboard/articles")
    def get
      administer { 
        @articles = Article.find(:all)
        render :list_articles
      }
    end
    def post
      @input.article_ids.each { |article_id|
        article = Article.find(article_id)
        article.destroy
      }
      redirect(R(RetrieveArticles))
    end
  end

  class RetrieveImages < R("/dashboard/images")
    def get
      administer { 
        @images = Image.find(:all)
        render :list_images
      }
    end
    def post
      @input.image_ids.each { |image_id|
        image = Image.find(image_id)
        image.destroy
      }
      redirect(R(RetrieveImages))
    end
  end

  class RetrieveTags < R("/dashboard/tags")
    def get
      administer { 
        @tags = Tag.find(:all)
        render :list_tags
      }
    end
    def post
      @input.tag_ids.each { |tag_id|
        tag = Tag.find(tag_id)
        tag.destroy
      }
      redirect(R(RetrieveTags))
    end
  end

  class CreateOrUpdateTag < R('/dashboard/tag/(\d*)')
    def get (tag_id)
      administer {
        unless tag_id.blank?
          @tag = Tag.find_by_id(tag_id)
        else
          @tag = Tag.new
        end

        render :create_or_update_tag
      }
    end
    def post (tag_id)
      administer {
        unless tag_id.blank?
          @tag = Tag.find_by_id(tag_id)
        else
          @tag = Tag.new
        end
        @tag.name = @input.name
        @tag.include_in_header = (@input.include_in_header.nil? ? false : true)
        if @tag.save! then
          redirect(R(CreateOrUpdateTag, @tag.id))
        else
          render :create_or_update_tag
        end
      }
    end
  end

  class CreateOrUpdateArticle < R('/dashboard/article/(\d*)')
    def get (article_id)
      administer {
        unless article_id.blank?
          @article = Article.find_by_id(article_id)
        else
          @article = Article.new
          @article.autopop(@state.user_id)
        end

        render :create_or_update_article
      }
    end
    def post (article_id)
      administer {
        unless article_id.blank?
          @article = Article.find_by_id(article_id)
        else
          @article = Article.new
        end
        @article.user_id = @state.user_id
        @article.title = @input.title
        @article.permalink = @input.permalink
        @article.excerpt = @input.excerpt
        @article.body = @input.body
        @article.published_on = @input.published_on
        @article.tag_list = @input.tag_list
        redirect(CreateOrUpdateArticle, @article.id) if @article.save!
      }
    end
  end
  class CreateOrUpdateImage < R('/dashboard/image/(\d*)')
    def get (image_id)
      administer {
        unless image_id.blank?
          @image = Image.find_by_id(image_id)
        else
          @image = Image.new
        end
        render :create_or_update_image
      }
    end
    def post (image_id)
      administer {
        unless image_id.blank?
          @image = Image.find_by_id(image_id)
        else
          @image = Image.new
        end
        @image.user_id = @state.user_id
        unless @input.the_file.is_a?(String) then
          @image.x_put(@input.the_file.tempfile.read)
        end
        @image.save!
        redirect(R(CreateOrUpdateImage, @image.id))
      }
    end
  end

end

module RisingCode::Views
  def contact
    form(:action => R(Contact), :method => :post) {
      label {
        "Name"
      }
      input(:type => "text") 
      input(:type => "submit", :value => "go")
    }
  end

  def layout
    xhtml_transitional {
      head {
        title {
          "Land of the Rising Code"
        }
        link(:rel => "stylesheet", :type => "text/css", :href => "/stylesheets/main.css")
        meta(:name => "viewport", :content => "width=850")
      }
      body {
        div.wrap!(:class => @content_class) {
          div.header! {
            div.logo!{
              ul {
                li {
                  h1 {
                    a(:href => R(Index)) {
                      "RisingCode"
                    }
                  }
                }
                @tags.each { |tag|
                  li {
                    h1 {
                      a(:href => R(Index, tag.name, nil)) {
                        text(tag.name.capitalize)
                      }
                    }
                  }
                }
              }
              br
            }
          } unless no_header
          if administering then
            div.wrap!(:class => @content_class) {
              div.header! {
                div.logo!{
                  ul {
                    li {
                      h1 {
                        a(:href => R(Index)) {
                          "RisingCode"
                        }
                      }
                    }
                    li {
                      a(:href => R(Dashboard), :class => ((@current_action == :dashboard) ? :current : nil)) {
                        h1 {
                          "Dashboard"
                        }
                      }
                    }
                    li {
                      a(:href => R(RetrieveArticles), :class => ((@current_action == :articles) ? :current : nil)) {
                        h1 {
                          "Articles"
                        }
                      }
                    }
                    li {
                      a(:href => R(RetrieveImages), :class => ((@current_action == :images) ? :current : nil)) {
                        h1 {
                          "Images"
                        }
                      }
                    }
                    li {
                      a(:href => R(RetrieveTags), :class => ((@current_action == :tags) ? :current : nil)) {
                        h1 {
                          "Tags"
                        }
                      }
                    }
                  }
                  br
                }
              }
            }
          end
          div.content! {
            self << yield
          }
          div.sidebar! {
          } unless (administering or viewing_images or no_sidebar) 
        }
        unless (administering)
          script(:type => "text/javascript") {"
            var gaJsHost = ((\"https:\" == document.location.protocol) ? \"https://ssl.\" : \"http://www.\");
            document.write(unescape(\"%3Cscript src='\" + gaJsHost + \"google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E\"));
          "}
          script(:type => "text/javascript") {"
            var pageTracker = _gat._getTracker(\"UA-104916-1\");
            pageTracker._initData();
            pageTracker._trackPageview();
          "}
        end
      }
    }
  end

  def events
    div {
      ads
      Upcoming::Events.all.each { |date, events|
        ul {
          li {
            h2 {
              date
            }
          }
          events.each { |event|
            li {
              a(:href => R(Events, event.id, event.excerpt)) { 
                event.excerpt
              }
            }
          }
        }
      }
    }
  end

  def images
    div {
      ads
      ul {
        @images.each { |image|
          li {
            h2 {
              image.created_at.strftime("%B %d %Y")
            }
            a(:href => image.full_permalink) {
              img(:src => image.thumb_permalink)
            }
          }
        }
      }
    }
  end

  def bookmarks
    div {
      ads
      ul {
        li {
          h2 {
            text("Bookmarks for ")
            a(:href => R(Bookmarks, @today.year, @today.month, @today.day)) {
              @today.strftime("%Y-%m-%d")
            }
          }
        }
        @bookmarks_for_today.each { |bookmark|
          li {
            if (
              bookmark["href"].downcase.include?(".png") or
              bookmark["href"].downcase.include?(".jpg") or
              bookmark["href"].downcase.include?(".jpeg") or
              bookmark["href"].downcase.include?(".jpeg") or
              bookmark["href"].downcase.include?(".gif")
            ) then
              img(:src => bookmark["href"])
            else
              a(:href => bookmark["href"]) {
                bookmark["excerpt"]
              }
            end
            p {
              ["tag", "extended"].each { |key|
                text(bookmark[key] + " ")
              }
            }
          }
        }
        li {
          h2 {
            text("Bookmarks for ")
            a(:href => R(Bookmarks, @yesterday.year, @yesterday.month, @yesterday.day)) {
              @yesterday.strftime("%Y-%m-%d")
            }
            text(" ...")
          }
        } if @bookmarks_for_yesterday
        li {
          h2 {
            text("Bookmarks for ")
            a(:href => R(Bookmarks, @tomorrow.year, @tomorrow.month, @tomorrow.day)) {
              @tomorrow.strftime("%Y-%m-%d")
            }
            text(" ...")
          }
        } if @bookmarks_for_tomorrow
      }
    }
  end
  
  def ads
    p.ads! {
      text('
      <script type="text/javascript"><!--
      google_ad_client = "pub-1383228323607572";
      /* 728x15, created 3/7/08 */
      google_ad_slot = "4271053867";
      google_ad_width = 728;
      google_ad_height = 15;
      //-->
      </script>
      <script type="text/javascript"
      src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
      </script>
      ')
    }
  end

  def event
    div {
      ads
      a(:href => "http://upcoming.yahoo.com/event/#{@event.id}", :target => :_blank) {
        h2 {
          @event.name
        }
      }
      p {
        @event.description
      }
      ul {
        li {
          @event.start_date
        }
        li {
          @event.start_time
        } if (@event.start_time.length > 0)
        li {
          a(:href => @venue_url, :target => :_blank) {
            @event.venue_name
          }
        } if (@event.venue_name.length > 0)
        li {
          a(:href => @map_url, :target => :_blank) {
            "map"
          }
          text("...")
        } if @map_url
        li {
          a(:href => @event.url) {
            "more details"
          }
          text("...")
        } if (@event.url.length > 0)
      }
    }
  end

  def about
    div {
      ads
      h2 {
        "About RisingCode.com"
      }
      p {
        text("This is ")
        a(:href => R(Resume)) {
          "Jon Bardin"
        }
        text("'s ")
        a(:href => R(Sources)) {
          "source code"
        }
        text(", a.k.a. The Land of the Rising Code.")
      }
      ul.profiles! {
        li {
          a(:href => "http://del.icio.us/diclophis", :rel => :me) {
            img(:src => "/images/del.gif")
          }
        }
        li {
          a(:href => "http://github.com/diclophis", :rel => :me) {
            img(:src => "/images/github.png")
          }
        }
        li {
          a(:href => "http://www.engadget.com/profile/68892/", :rel => :me) {
            img(:src => "/images/engadget.gif")
          }
        }
        li {
          a(:href => "http://ruby.meetup.com/6/members/4890/", :rel => :me) {
            img(:src => "/images/meetup.gif")
          }
        }
        li {
          a(:href => "https://rubyforge.org/users/diclophis/", :rel => :me) {
            img(:src => "/images/rubyforge_logo.png")
          }
        }
        li {
          a(:href => "http://sourceforge.net/users/diclophis/", :rel => :me) {
            img(:src => "http://sourceforge.net/sflogo.php?group_id=13609&type=2")
          }
        }
        li {
          a(:href => "http://freshmeat.net/~jbardin/", :rel => :me) {
            img(:src => "http://images.freshmeat.net/img/logo.gif")
          }
        }
        li {
          a(:href => "http://iphonebookmarklets.com/", :rel => :me) {
            img(:src => "http://iphonebookmarklets.com/logo.png")
          }
        }
        li {
          a(:href => "http://upcoming.yahoo.com/user/70266/", :rel => :me) {
            img(:src => "http://upcoming.org/images/logo/logo_large_orange.png")
          }
        }
        li {
          a(:href => "http://slashdot.org/~diclophis", :rel => :me) {
            img(:src => "/images/slashdotlg.gif")
          }
        }
      }
    }
  end

  def openid
    div {
      h1 {
        "What is OpenID?"
      }
      p {
        "OpenID eliminates the need for multiple usernames across different websites, simplifying your online experience."
      }
      p {
        "You get to choose the OpenID Provider that best meets your needs and most importantly that you trust. At the same time, your OpenID can stay with you, no matter which Provider you move to. And best of all, the OpenID technology is not proprietary and is completely free."
      }
      p {
        "For businesses, this means a lower cost of password and account management, while drawing new web traffic. OpenID lowers user frustration by letting users have control of their login."
      }
      p {
        "For geeks, OpenID is an open, decentralized, free framework for user-centric digital identity. OpenID takes advantage of already existing internet technology (URI, HTTP, SSL, Diffie-Hellman) and realizes that people are already creating identities for themselves whether it be at their blog, photostream, profile page, etc. With OpenID you can easily transform one of these existing URIs into an account which can be used at sites which support OpenID logins."
      }
      p {
        "OpenID is still in the adoption phase and is becoming more and more popular, as large organizations like AOL, Microsoft, Sun, Novell, etc. begin to accept and provide OpenIDs. Today it is estimated that there are over 160-million OpenID enabled URIs with nearly ten-thousand sites supporting OpenID logins."
      }
      p {
        "Please follow the links below for more information:"
      }
      a(:href => "http://openid.net") {
        h2 {
          "OpenID.net"
        }
      }
      a(:href => "https://pip.verisignlabs.com/") {
        h2 {
          "Verisign Labs Personal Identity Provider"
        }
      }
    }
  end

  def resume
    div {
      h1 {
        "Jon Bardin"
      }
      p {
        "Contact Me"
      }
    }
    div {
        h2 {
          "Background"
        }
        p {"
         Developed middleware for legacy and future system interoperation, through the use
         of standardized data transfer and storage techniques.
        "}
    }
    div {
      h2 {
        "Experience"
      }
      p {
      }
      p {
        h3 {
          em {
            "Software Engineer - CIS Data Systems"
          }
        }
        h4 {
          "September 2005 - Current, Oakland, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Click-to-Talk System"
            }
            p {
            }
          }
          li {
            h5 {
              "Toll-Free Hotline System"
            }
          }
        }
      }
      p {
        h3 {
          "Software Engineer - USF College of Medicine"
        }
        h4 {
          "June 2001 - May 2005, Tampa, FL"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Online Election System for Year I Student Government."
            }
            p {"
              Developed in C, deployed using CGI on a SunOS based platform.
              Data storage layer is implemented with a MySQL database.
              A system used by medical students to execute student government posistions.
            "}
          }
          li {
            h5 {
              "Online Course Registration System for Year III Electives."
            }
            p {"
              Developed in C, deployed using CGI on a SunOS based platform. Data storage layer
              is implemented with a MySQL database. This system was used by students,
              advisors, course directors, and the registrar to determine a eligibility for electives.
            "}
          }
          li {
            h5 {
              "Virtual lab software for clinical competency exams."
            }
            p {"
              Developed in VB, deployed on multiple remote testing workstations running windows
              98. Information is stored in an embedded Sqlite database.
            "}
          }
          li {
            h5 {
              "Exam grading software, for Year I &amp; II curriculum."
            }
            p {"
              Developed in C#, deployed on a single machine running windows 98. Data persistence is
              achieved using serialized objects, communicated through a relational bridge.
            "}
          }
        }
      }
      p {
        h3 {
          "Software Engineer - ImageLinks"
        }
        h4 {
          "Dec 1999 - August 2000, Melbourne, FL"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Online timecard submission/auditing system."
            }
            p {"
              Developed in PHP, deployed on a Linux based web-server.
              Data storage layer is implemented with a MySQL database.
            "}
          }
          li {
            h5 {
              "Online geographically indexed GIS-Imagery database."
            }
            p {"
              Developed in PHP, deployed on a Linux based web-server.
              Data storage layer is implemented with a MySQL database.
            "}
          }
          li {
            h5 {
              "Maintenance of a Linux-based computing cluster."
            }
            p {"
              Used to decrease computation time of GIS-Imagery. Implementation of several
              system administration tools, used to maintain the integrity of the cluster.
            "}
          }
        }
      }
      p {
        h3 {
          "Software Engineer - XL Vision"
        }
        h4 {
          "April 2000 - August 2000, Vero, FL"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Online intranet contact Database"
            }
            p {"
              A searchable phonebook, developed in PHP.
              Data storage layer is implemented with a MSSQL database.
            "}
          }
          li {
            h5 {
              "Online List-Serve interface"
            }
            p {"
              An ASP interface for a list-serve.
              Used to facilitate intra-office communication.
            "}
          }
          li {
            h5 {
              "Linux Server administration"
            }
            p {"
              Configuration of Apache, PHP, MySQL to meet the needs of several intranet applications.
            "}
          }
        }
      }
      p {
        h3 {
          "Architectural Intern - The Kendust Group"
        }
        h4 {
          "May 1998 - May 1999, Suntree, FL"
        }
        ul {
          li {
            h5 {
              "Commercial/Residential AutoCAD Drafting"
            }
            p {"
              I have drafted complete blueprints ranging from simple remodeling projects, to 5000 sq. ft. homes, to Steel Shell buildings.
              In addition I have drawn mechanical, electrical, and plumbing plans.
            "}
          }
          li {
            h5 {
              "Developed several tools to aid the drafting process."
            }
            p {"
              Developed in AutoLISP, for AutoCAD.
              These tools were designed to streamline several common tasks, such as mirroring a floorplan.
            "}
          }
          li {
            h5 {
              "Deployed a small LAN."
            }
            p {"
              3 computers, in 2 separate rooms, SMB based file sharing.
            "}
          }
        }
      }
    }
  end

  def sources
    ul {
      li {
        h2 {
          "Controllers"
        }
        ul {
          @controllers.each { |controller, source|
            li {
              h3 {
                controller
              }
              text(source)
            }
          }
        }
      }
      li {
        h2 {
          "Models"
        }
        ul {
          @models.each { |model, source|
            li {
              h3 {
                model
              }
              text(source)
            }
          }
        }
      }
    }
  end

  def timecard
    div {
      table {
        tr {
        }
        tr {
        }
        tr.header {
        }
        7.times { |i|
        tr.day {
        }
        }
        tr {
        }
        7.times { |i|
        tr.day {
        }
        }
      }
    }
  end

  def dangotalk_readme
    div {
      ads
      h2 {
        "DangoTalk"
      }
      p {"
This is my ghetto ass attempt to get VOIP working on the iphone using the official SDK.
Right now it will connect a call, but no audio is transfered (yet).
What is left to do? Where do we go from here?
Well the first step is getting the audio connection to work, I have started to engineer a driver for pjmedia from null_sound.c, but I havnt had much success (yet)!
You can download the _entire_ source from the link provided below...
      "}
      p {
        "read the README first!"
      }
      br
      a(:href => R(DangoTalkSource)) {
        "dangotalk.tar.gz"
      }
    }
  end

  def index
    div {
      @articles.each_with_index { |article, i|
        h2 {
          a(:href => article.permalink) {
            text(article.title)
          }
        }
        ul {
          li {
            h3 {
              a(:href => article.user.openid_url) {
                text(article.user.nickname)
              }
              text(" at ")
              text(article.published_on.strftime("%B %d %Y"))
            }
          }
          li {
            h3 {
              text("tagged: ")
              article.tags.reverse.each_with_index { |tag, i|
                text(",") if i > 0
                a(:href => R(Index, tag.name, nil)) {
                  text(tag.name)
                }
              }
            }
          } if article.tags.length > 0
          li {
            if @single and not article.excerpt.blank? then
              RedCloth.new(article.excerpt).to_html + RedCloth.new(article.body).to_html
            elsif not @single and not article.excerpt.blank? then
              RedCloth.new(article.excerpt).to_html
            else
              RedCloth.new(article.body).to_html
            end
          }
          li {
            h3{ 
              a(:href => article.permalink) {
                text("#{article.comments_count} comments")
              }
            }
          } unless @single
        }
        if @single
          h2 {
            "Comments"
          } if article.comments.length > 0
          ul {
            article.comments.each { |comment|
              li {
                h3 {
                  a(:href => comment.user.openid_url) {
                    text(comment.user.nickname)
                  }
                  text(" at ")
                  text(comment.created_at.strftime("%B %d %Y"))
                }
                p {
                  text(comment.body)
                }
              }
            }
          }
          h2 {
            "Post a comment"
          }
          ul {
            li {
              form.comment(:action => R(Comments, article.id, nil), :method => :post) {
                ul {
                  li {
                    label {
                      a(:href => R(OpenID), :target => :_blank) {
                        text("OpenID URL")
                      }
                    }
                    input.openid_url!(:type => :text, :name => :openid_url)
                  }
                  li {
                    textarea(:name => :body, :rows => 10, :cols => 10)
                  }
                  li {
                    input(:type => :submit, :value => "go")
                  }
                }
              }
            }
          }
        end
      }
=begin
      if @use_page_navigation and (@old_ranger or @new_ranger) then
        h2 {
          "More articles numbered"
        }
        ul.rangers_list {
          li {
            a(:href => R(Index, @older_articles)) {
              @older_articles
            }
          } if @old_ranger
          li {
            a(:href => R(Index, @newer_articles)) {
              @newer_articles
            }
          } if @new_ranger
        }
      end
=end
      if @use_date_navigation and (@old_ranger or @new_ranger) then
        h2 {
          "More articles dated"
        }
        ul.rangers_list {
          li {
            a(:href => R(Index, @old_ranger.published_on.year, @old_ranger.published_on.month, @old_ranger.published_on.day)) {
              @old_ranger.published_on.strftime("%B %d %Y")
            }
          } if @old_ranger
          li {
            a(:href => R(Index, @new_ranger.published_on.year, @new_ranger.published_on.month, @new_ranger.published_on.day)) {
              @new_ranger.published_on.strftime("%B %d %Y")
            }
          } if @new_ranger
        }
      end
    }
  end

  def login
    form(:method => :post) {
      h1("login")
      h2 {
        @login_exception
      } if @login_exception
      ul {
        li {
          a(:href => R(OpenID), :target => :_blank) {
            "OpenID URL"
          }
        }
        li {
          input.openid_url!(:type => :text, :name => :openid_url)
        }
        li {
          input(:type => "submit", :value => "go")
        }
      }
    }
  end

  def dashboard
    div {
              ul {
                li {
                  a(:href => R(CreateOrUpdateArticle, nil)) {
                    text("new article")
                  }
                }
                li {
                  a(:href => R(CreateOrUpdateTag, nil)) {
                    text("new tag")
                  }
                }
                li {
                  a(:href => R(CreateOrUpdateImage, nil)) {
                    text("new image")
                  }
                }
              }
      ul {
        li {
          "new things that have happend"
        }
      }
    }
  end

  def list_tags
    div {
      form(:method => :post, :enctype => "multipart/form-data") {
        ul {
          @tags.each { |tag|
            li {
              input(:type => :checkbox, :name => "tag_ids[]", :value => tag.id)
              a(:href => R(CreateOrUpdateTag, tag.id)) {
                tag.name
              }
            }
          }
          li {
            input(:type => :submit, :value => "go")
          } if @tags.length > 0
        }
      }
    }
  end

  def list_articles
    div {
      form(:method => :post, :enctype => "multipart/form-data") {
        ul {
          @articles.each { |article|
            li {
              input(:type => :checkbox, :name => "article_ids[]", :value => article.id)
              a(:href => R(CreateOrUpdateArticle, article.id)) {
                article.title
              }
            }
          }
          li {
            input(:type => :submit, :value => "go")
          } if @articles.length > 0
        }
      }
    }
  end

  def articles
    div {
      ul {
        @articles.each { |article|
          li {
            h2 {
              article.title
            }
          }
        }
      }
    }
  end

  def list_images
    div {
      form(:method => :post, :enctype => "multipart/form-data") {
        ul {
          @images.each { |image|
            li {
              input(:type => :checkbox, :name => "image_ids[]", :value => image.id)
              a(:href => R(CreateOrUpdateImage, image.id)) {
                h2 {
                  image.permalink
                }
                img(:src => image.icon_permalink)
              }
            }
          }
          li {
            input(:type => :submit, :value => "go")
          } if @images.length > 0
        }
      }
    }
  end

  def create_or_update_article
    div {
      form(:method => :post) {
        ul {
          li {
            label(:for => :title) {
              text("title")
            }
            input(:type => :text, :name => :title, :value => @article.title)
          }
          li {
            label(:for => :permalink) {
              text("permalink")
            }
            input(:type => :text, :name => :permalink, :value => @article.permalink)
          }
          li {
            label(:for => :published_on) {
              text("published on")
            }
            input(:type => :text, :name => :published_on, :value => (@article.published_on or Time.now))
          }
          li {
            label(:for => :excerpt) {
              text("excerpt")
            }
            textarea(:name => :excerpt) {
              @article.excerpt
            }
          }
          li {
            label(:for => :body) {
              text("body")
            }
            textarea(:name => :body) {
              @article.body
            }
          }
          li {
            label(:for => :tag_list) {
              text("tag_list")
            }
            input(:type => :text, :name => :tag_list, :value => @article.tag_list)
          }
          li {
            input(:type => :submit, :value => "go")
          }
        }
      }
    }
  end

  def create_or_update_tag
    div {
      form(:method => :post, :enctype => "multipart/form-data") {
        ul {
          li {
            label(:for => :name) {
              text("name")
            }
            input(:type => :text, :name => :name, :value => @tag.name)
          }
          li {
            label(:for => :include_in_header) {
              text("include_in_header")
            }
            checked = @tag.include_in_header ? {:checked => :checked} : {}
            input({:type => :checkbox, :name => :include_in_header}.merge(checked))
          }
          li {
            input(:type => :submit, :value => "go")
          }
        }
      }
    }
  end

  def create_or_update_image
    div {
      form(:method => :post, :enctype => "multipart/form-data") {
        ul {
          li {
            label(:for => :permalink) {
              text("permalink")
            }
          }
          li {
            label(:for => :file) {
              text("file")
            }
            input(:type => :file, :name => :the_file)
          }
          li {
            input(:type => :submit, :value => "go")
          }
        }
      }
    }
  end
end

if __FILE__ == $0 then
  daemon = ARGV.shift.intern if ARGV.length > 0
  drb = "druby://:2527"
  case daemon
    when :documentation_client
      DRb.start_service
      documentation_server = DRbObject.new(nil, drb)
      documentation_server.controllers.each { |controller|
        puts documentation_server.source_for(controller)
      }

    when :documentation_server
      DocumentationServer.daemon("risingcode_documentation_server", '/var/www/risingcode.com/boot', drb)


    when :email_server
      EmailServer.daemon("risingcode_email_server", '/var/www/risingcode.com/boot', 2525)

    when :runner
      require "boot"
      wang = RedCloth.highlight("puts :wang if :chung")
      Camping::Models::Base.logger.debug(wang)
      drb = "druby://:2527"
      DRb.start_service
      @@documentation_server = DRbObject.new(nil, drb)
      wang = @@documentation_server.source_for(RisingCode::Controllers::Login)
      Camping::Models::Base.logger.debug(wang)
  else
    puts "wtf"
  end

else
  drb = "druby://:2527"
  DRb.start_service
  @@documentation_server = DRbObject.new(nil, drb)
  require ENV['COMP_ROOT'] + "/boot"
end

=begin
[]   range specificication (e.g., [a-z] means a letter in the range a to z)
\w  letter or digit; same as [0-9A-Za-z]
\W  neither letter or digit
\s  space character; same as [ \t\n\r\f]
\S  non-space character
\d  digit character; same as [0-9]
\D  non-digit character
\b  backspace (0x08) (only if in a range specification)
\b  word boundary (if not in a range specification)
\B  non-word boundary
*   zero or more repetitions of the preceding
+   one or more repetitions of the preceding
{m,n}   at least m and at most n repetitions of the preceding
?   at most one repetition of the preceding; same as {0,1}
|   either preceding or next expression may match
()  grouping
=end
#JonBardin


