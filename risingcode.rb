#!/usr/bin/ruby

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
require 'ruby2ruby'
require 'drb'
require 'uuidtools'
require 'right_aws'
require 'linguistics'
require 'hpricot'
require 'plist'
Linguistics::use( :en )

#import into the system
require 'rack'
require 'camping'
require 'camping/session'
require 'openid'
require 'openid/store/filesystem'
require 'openid/consumer'
require 'openid/extensions/sreg'

#import into this file
require '/var/www/risingcode/acts_as_taggable'
require '/var/www/risingcode/tag_list'
require '/var/www/risingcode/delicious'
require '/var/www/risingcode/email_server'
require '/var/www/risingcode/documentation_server'
require '/var/www/risingcode/twitter'
require '/var/www/risingcode/referrer'
require '/var/www/risingcode/fast'
require '/root/ruby-oembed/lib/oembed'

Camping.goes :RisingCode

module RisingCodeTags
  def hard_breaks; false; end
  def css(opts)
#Camping::Models::Base.logger.debug("css. opts = #{opts.inspect}")
    content = opts[:text]
    begin
      h = DocumentationServer::SERVER.highlight(content, "css")
      j = content.split("\n").length
      return ::Markaby::Builder.new.table {
        tr {
          td.lines {
            j.times { |i|
              text("#{i}\n")
              br
            }
          }
          td {
            text(h)
          }
        }
      }
    rescue Exception => problem
#Camping::Models::Base.logger.debug("css. problem #{problem}")
      problem.inspect
    end
  end
  def ruby(opts)
#Camping::Models::Base.logger.debug("ruby. opts = #{opts.inspect}")
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "rb")
    rescue Exception => problem
#Camping::Models::Base.logger.debug("ruby problem #{problem}")
      problem.inspect
    end
  end
  def oembed(opts)
#Camping::Models::Base.logger.debug("oembed. opts = #{opts.inspect}")
    content = opts[:text]
    begin
      Timeout::timeout(3) do
        res = OEmbed::Providers::OohEmbed.get(content)
        case res
          when OEmbed::Response::Photo
            ::Markaby::Builder.new.div(:class => "oembed centered") {
              div.oembeded {
                a(:href => content) {
                  img(:src => res.field(:url))
                }
                text(res.field(:html))
              }
            }
          when OEmbed::Response::Video, OEmbed::Response::Rich
            ::Markaby::Builder.new.div(:class => "oembed centered") {
              div.oembeded {
                text(res.field(:html))
              }
            }
          when OEmbed::Response::Link
            ::Markaby::Builder.new.div(:class => "oembed") {
              div.oembeded {
                a(:href => content) {
                  h4 {
                    text(res.field(:title))
                  }
                }
                text(res.field(:html))
              }
            }
        else
          content
        end
      end
    rescue Exception => problem
#      Camping::Models::Base.logger.debug("wang chung")
#      Camping::Models::Base.logger.debug("#{problem.inspect}")
#      Camping::Models::Base.logger.debug(problem.backtrace.join("\n"))
      content
    end
  end
end

class String
  def textilize
#Camping::Models::Base.logger.debug("AAA")
    wang = RedCloth.new(self, [:no_span_caps]).extend(::RisingCodeTags).to_html(:ruby)
#Camping::Models::Base.logger.debug("BBB")
    wang
  end
end

module RisingCode
  include Camping::Session 
  def user_logged_in
    @state.authenticated == true
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
  def display_identifier
    @@display_identifier
  end
  def service(*a)
    searched = Referrer.parse(@env["HTTP_REFERER"])
    if searched then
      #status = "#{searched[0]} found '#{searched[1]}' at http://risingcode.com" + @env["PATH_INFO"]
      #Twitter.update(status)
    end
    return super(*a)
  end
end

module RisingCode::Models
  class Base
    def Base.table_name_prefix
    end
  end
  class CreateRisingCode < V 1 
    def self.up
      create_table :sessions, :force => true do |t|
        t.column :hashid,      :string,  :limit => 32
        t.column :created_at,  :datetime
        t.column :ivars,       :text
      end
      create_table :articles, :force => true do |t|
        t.column :title, :string, :limit => 255, :null => false
        t.column :permalink, :string, :limit => 255, :null => false
        t.column :excerpt, :string, :limit => 255
        t.column :body, :text
        t.column :created_at, :datetime, :null => false
        t.column :updated_at, :datetime, :null => false
        t.column :published_on, :datetime, :defaut => nil
      end
      create_table :tags, :force => true do |t|
        t.column :name, :string
      end
      create_table :taggings, :force => true do |t|
        t.column :tag_id, :integer
        t.column :taggable_id, :integer
        t.column :taggable_type, :string
        t.column :created_at, :datetime
      end
      create_table :images, :force => true do |t|
        t.column :permalink, :string, :null => false
        t.column :created_at, :datetime, :null => false
      end
      add_column :tags, :include_in_header, :boolean, :default => false
      add_index :taggings, :tag_id
      add_index :taggings, [:taggable_id, :taggable_type]
    end
    def self.down
      drop_table :articles
      drop_table :taggings
      drop_table :tags
      drop_table :images
    end
  end
  class Article < Base
    validates_presence_of :title, :if => :title
    validates_uniqueness_of :title
    validates_uniqueness_of :permalink
    acts_as_taggable
    has_many :comments
    belongs_to :user

    def autopop(title = nil)
      self.title = title 
      self.published_on = Time.now 
      (1..100).each { |i|
        self.permalink = "/#{published_on.year}/#{published_on.month}/#{published_on.day}/#{i.ordinalize}"
        break if valid?
      }
    end
  end
  class Image < Base
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
  class Tagging < Base
    belongs_to :tag
    belongs_to :taggable, :polymorphic => true
    def after_destroy
      if Tag.destroy_unused and tag.taggings.count.zero? then
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
#  class CacheObserver < ::Camping::Models::A::Observer
#    observe Article, Comment, Image, Tag
#    def after_save (record)
#      Camping::Models::Base.logger.debug(record.inspect)
#      if File.exists?("/tmp/cache/risingcode.com") then
#        File.rename("/tmp/cache/risingcode.com", "/tmp/cache/risingcode.com.#{Time.now.to_i}")
#      end
#    end
#  end
end

module RisingCode::Controllers
  class States < R('/states')
    def get
      states = [
        "alabama",
        "alaska",
        "arizona",
        "arkansas",
        "california",
        "colorado",
        "connecticut",
        "washington dc",
        "delaware",
        "florida",
        "georgia",
        "hawaii",
        "idaho",
        "illinois",
        "indiana",
        "iowa",
        "kansas",
        "kentucky",
        "louisiana",
        "maine",
        "maryland",
        "massachusetts",
        "michigan",
        "minnesota",
        "mississippi",
        "missouri",
        "montana",
        "nebraska",
        "nevada",
        "new hampshire",
        "new jersey",
        "new york",
        "north carolina",
        "north dakota",
        "ohio",
        "oklahoma",
        "oregon",
        "pennsylvania",
        "rhode island",
        "south carolina",
        "south dakota",
        "states",
        "tennessee",
        "texas",
        "utah",
        "vermont",
        "virginia",
        "washington",
        "west virginia",
        "wisconsin",
        "wyoming"
      ]

      data = {}
      states.each { |state|
        begin
          Timeout::timeout(3) do
#Camping::Models::Base.logger.debug("111")
            fetched = Fast.fetch("http://en.wikipedia.org/wiki/Special:Search/#{URI.encode(state)}")
            fetched = nil if fetched.blank?
            if fetched then
#Camping::Models::Base.logger.debug(fetched.slice(0, 100))
              doc = Hpricot(fetched)
              (doc / "li#ca-nstab-main").each { |el|
#Camping::Models::Base.logger.debug("222")
                data[state] = "oembed. http://en.wikipedia.org#{el.children[0].attributes['href']}".textilize
#Camping::Models::Base.logger.debug("333")
                break
              }
              (doc / "ul.mw-search-results li").each { |el|
#Camping::Models::Base.logger.debug("444")
                data[state] = "oembed. http://en.wikipedia.org#{el.children[0].attributes['href']}".textilize
#Camping::Models::Base.logger.debug("555")
                break
              }
            end
          end
        rescue Exception => problem
#Camping::Models::Base.logger.debug("wikipedia timedout")
#Camping::Models::Base.logger.debug("#{problem.inspect}")
#Camping::Models::Base.logger.debug(problem.backtrace.join("\n"))
        end
      }
#Camping::Models::Base.logger.debug("666")

      return data.to_plist
    end
  end
  class Button < R('/button/(.*)')
    def get (id)
      if id.nil? or id.length == 0 or id.length > 30 then
        id = "                    "
      end
      label = Draw.new
      label.fill = "black" 
      label.stroke = 'none'
      label.font = "Vera"
      label.text_antialias(true)
      label.font_style=Magick::NormalStyle
      label.font_weight=Magick::BoldWeight
      label.gravity=Magick::CenterGravity
      label.text(0,0,id)
      metrics = label.get_type_metrics(id)
      width = metrics.width
      height = metrics.height
      width += 16
      height += 12
      radius = 8
      top_grad = GradientFill.new(0, 0, width, 0, "#ffffff", "#cccccc")
      image_layer_one = Magick::Image.new(width, height, top_grad)
      gc = Draw.new
      gc.roundrectangle(0,0,image_layer_one.columns-1, image_layer_one.rows-1, radius, radius)
      gc.composite(0,0,0,0,image_layer_one,InCompositeOp)
      new_layer_one = Magick::Image.new(width, height) { self.background_color = "none" }
      gc.draw(new_layer_one)
      inner_glow_mask = Magick::Image.new(width, height) { self.background_color = "none" }
      gc = Draw.new
      gc.stroke("black")
      gc.stroke_width(1)
      gc.fill("white")
      gc.roundrectangle(1,1,inner_glow_mask.columns - 2, inner_glow_mask.rows - 2, radius, radius)
      gc.draw(inner_glow_mask)
      inner_glow_mask = inner_glow_mask.blur_image(0, 1)
      highlight_gradient = GradientFill.new(0,0,80, 0, "#ffffff", "#e4e4e4")
      highlight_layer = Magick::Image.new((width - 14).to_i, (height * 0.5).to_i, highlight_gradient)
      gc = Draw.new
      gc.roundrectangle(0, 0, highlight_layer.columns - 1, highlight_layer.rows - 1, radius, radius)
      gc.composite(0,0,0,0,highlight_layer,InCompositeOp)
      new_highlight_layer = Magick::Image.new(highlight_layer.columns, highlight_layer.rows) { self.background_color = "none" }
      gc.draw(new_highlight_layer)
      new_layer_one.composite!(inner_glow_mask, CenterGravity, MultiplyCompositeOp)
      new_layer_one.composite!(new_highlight_layer, NorthGravity, 4, 3, OverCompositeOp)
      label.draw(new_layer_one)
      final_image = new_layer_one
      blob = final_image.to_blob {
        self.format = 'GIF'
        self.quality = 100
      }
      @headers["Content-Type"] = "image/gif"
      @headers["Content-Disposition"] = "inline"
      return blob
    end
  end
  class Contact < R("/contact")
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      render :contact
    end
    def post
      
    end
  end
  class Login < R("/dashboard/login(.*)")
    def get(*args)
      if (@input.has_key?("openid.mode")) then
        this_url = @@realm + R(Login, nil)
        store = ::OpenID::Store::Filesystem.new("/tmp")
        openid_consumer = ::OpenID::Consumer.new(@state, store)
        openid_response = openid_consumer.complete(@input, this_url)
        if openid_response.status == :success and openid_response.identity_url == "http://diclophis.pip.verisignlabs.com/" then
          @state.authenticated = true
          return redirect(R(Dashboard))
        end
      end
      other_layout {
        render :login
      }
    end
    def post(*args)
      if @input.identity_url == @@identity_url then
        store = ::OpenID::Store::Filesystem.new("/tmp")
        openid_consumer = ::OpenID::Consumer.new(@state, store)
        check_id_request = openid_consumer.begin(@input.identity_url)
        openid_sreg = ::OpenID::SReg::Request.new(['nickname'])
        check_id_request.add_extension(openid_sreg)
        url = check_id_request.redirect_url(@@realm, @@realm + R(Login, nil))
        redirect(url)
      end
    end
  end
  class Dashboard < R("/dashboard")
    def get
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
      @title = "Jon Bardin lives in the Land of the Rising Code"
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "about"
      @bookmarks = Delicious::Bookmarks.all(0, 99999)
      @found = []
      @words = {}
      @bookmarks.each { |date, bookmarks|
        bookmarks.each { |bookmark|
          new_words = bookmark["excerpt"].split(/([^a-zA-Z0-9])/)
          new_words.each { |word|
            word.gsub!(/([a-zA-Z0-9])\..*/, '\1')
            word.gsub!(/([^a-zA-Z0-9])/, '')
            word.downcase!
            @words[word] = 0 if @words[word].nil?
            @words[word] += 1
          }
        }
      }
      @words.each { |word, count|
        next if word.length < 6
        case count
          when 1..10
            next
          when 10..20
          when 30..60
            next
        end
          
        #next if count < 20
        #next if count > 40
        @found << word
      }
      #@top = @found.collect { |word| word.en.present_participle }
      #@generalization = @found.en.conjunction(:generalize => true)
      render :about
    end
  end
  class Resume < R('/about/resume')
    def get
      #other_layout {
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "about"
      render :resume
      #}
    end
  end
  class Images < R('/images/', '/images/public/([a-zA-Z0-9\-]+).png', '/images/([a-zA-Z0-9\-]+)/(\d*)')
    def get (*args)
      if args.length == 0 then
        view_images {
          @tags = Tag.find_all_by_include_in_header(true)
          @active_tab = "risingcode"
          @images = Image.find(:all, :order => "created_at desc")
          render :images
        }
      else
        args.inspect
      end
    end
  end
  class Learn < R('/learn/about/(.*)')
    def get (tag)
      @tag = tag
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "bookmarks"
      render :message
    end
  end
  class BookmarksByTag < R('/bookmarks/tagged/(.*)')
    def get (tag)
      @tag = tag
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "bookmarks"
      @bookmarks = Delicious::Bookmarks.all(0, 99999)
      @bookmarks_for_tag = []
      @bookmarks.each { |date, bookmarks|
        bookmarks.each { |bookmark|
          @bookmarks_for_tag << bookmark if (bookmark["tag"].include?(tag) or bookmark["href"].include?(tag))
        }
      }
      render :bookmarks_by_tag
    end
  end
  class Bookmarks < R('/bookmarks', '/bookmarks/(\d+)/(\d+)/(\d+)')
    def get (*args)
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "bookmarks"
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
          return redirect(R(Bookmarks, @today.year, @today.month, @today.day))

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
        @s = ""
        @s += (Date::DAYNAMES[@today.wday])
        words = {}
        word = nil
        @bookmarks.each { |date, bookmarks|
          bookmarks.each { |bookmark|
            words_ = bookmark["excerpt"].split(/([^a-zA-Z0-9])/)
            words_.each { |word|
              word.gsub!(/([a-zA-Z0-9])\..*/, '\1')
              word.gsub!(/([^a-zA-Z0-9])/, '')
              word.downcase!
              words[word] = 0 if words[word].nil?
              words[word] += 1
            }
          }
        }
        flex = 0
        @found = []
        until (@found.length == 1) do
          @bookmarks_for_today.each { |bookmark|
            bookmark["excerpt"].split(/([^a-zA-Z0-9])/).sort_by { |word| word.length }.each { |word|
              word.gsub!(/([a-zA-Z0-9])\..*/, '\1')
              word.gsub!(/([^a-zA-Z0-9])/, '')
              word.downcase!
              next if word.length < 6
              next if words[word] > 13
              next if @found.include?(word)
              @found << word
              break
            }
          } 
          break if ((flex += 1) > 4)
        end
        @title = @found.slice(0, 4).collect { |word| word.en.present_participle }.join(", ")
        render :bookmarks
      else
        redirect(R(Bookmarks))
      end
    end
  end
  class Comments < R('/comment/(\d+)(.*)')
=begin
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
=end
    def post (article_id, junk = nil)
      return @input.inspect
=begin
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
=end
    end
  end
  class Sources < R('/sources')
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "about"
      @controllers = Hash.new
      @models = Hash.new
      DocumentationServer::SERVER.controllers.each { |controller|
        @controllers[controller] = DocumentationServer::SERVER.source_for(controller)
      }
      DocumentationServer::SERVER.models.each { |model|
        @models[model] = DocumentationServer::SERVER.source_for(model)
      }
      render :sources
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
      @active_tab = "risingcode"
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
          :conditions => ["permalink like ? and (date(published_on) <= ?)", @permalink, @now], 
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
        :conditions => ["permalink like ? and (date(published_on) <= ? or ?)", @permalink, @now, user_logged_in], 
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
      render :index
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
          @article.autopop
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
        unless @input.the_file.is_a?(String) then
          @image.x_put(@input.the_file[:tempfile].read)
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
          @title or "Land of the Rising Code"
        }
        link(:rel => "stylesheet", :type => "text/css", :href => "/stylesheets/main.css")
        #script(:src => "/javascripts/prototype-1.6.0.2.js")
        #script(:src => "/javascripts/scriptaculous.js")
        #script(:src => "/javascripts/bubble.js")
        meta(:name => "viewport", :content => "width=850")
      }
      body {
        div.wrap!(:class => @content_class) {
          div.header! {
            div.logo!{
              ul {
                li(:class => (("risingcode" == @active_tab) ? "active" : "")) {
                  h1 {
                    a(:href => R(Index)) {
                      "RisingCode"
                    }
                  }
                }
                @tags.each { |tag|
                  li(:class => ((tag.name == @active_tab) ? "active" : "")) {
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
  def bookmarks_by_tag
    div {
      ads
      ul {
        @bookmarks_for_tag.each { |bookmark|
          li {
            if ((oembed = "oembed. #{bookmark["href"]}".textilize) == bookmark["href"]) then
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
            else
              text(oembed)
            end
            p.tagged {
              bookmark["tag"].split(" ").each { |tag|
                a(:href => R(BookmarksByTag, tag)) {
                  text("&nbsp;" + tag)
                }
              }
            }
            p {
              text(bookmark["extended"])
            } unless bookmark["extended"].blank?
          }
        }
        li {
          a(:href => R(Learn, @tag)) {
            text("Learn about #{@tag}")
          }
        }
      }
    }
  end
  def bookmarks
    div {
      ads
      ul {
        bookmarks_nav
        li {
          h2 {
            if @found.at_center > 1 then
              text(@s + " started with #{@found.first}, featured a #{@found.center} flavoured lunch, ended in a #{@found.last} afternoon")
            elsif @found.at_center == 1 then
              text(@s + " was a half #{@found.first} and half #{@found.last} kinda day")
            else
              text(@s + " was a whole lotta #{@found.first || :nothing}")
            end
          }
        }
        @bookmarks_for_today.each { |bookmark|
          li {
            if ((oembed = "oembed. #{bookmark["href"]}".textilize) == bookmark["href"]) then
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
                  text(bookmark["excerpt"])
                }
              end
            else
              text(oembed)
            end
            p.tagged {
              bookmark["tag"].split(" ").each { |tag|
                a(:href => R(BookmarksByTag, tag)) {
                  text("&nbsp;" + tag)
                }
              }
            }
            p {
              text(bookmark["extended"])
            } unless bookmark["extended"].blank?
          }
        }
      }
    }
  end
  def bookmarks_nav
    li {
      a(:href => R(Bookmarks, @yesterday.year, @yesterday.month, @yesterday.day)) {
        text("&laquo;&nbsp;")
        text(@yesterday.strftime("%Y-%m-%d"))
        text("&nbsp;|&nbsp;")
      } if @bookmarks_for_yesterday
      text("&nbsp;")
      text(@today.strftime("%Y-%m-%d"))
      text("&nbsp;")
      a(:href => R(Bookmarks, @tomorrow.year, @tomorrow.month, @tomorrow.day)) {
        text("&nbsp;|&nbsp;")
        text(@tomorrow.strftime("%Y-%m-%d"))
        text("&nbsp;&raquo;")
      } if @bookmarks_for_tomorrow
    }
  end
  def ads
    p.ads! {
      text('
      <script type="text/javascript"><!--
      google_ad_client = "pub-1383228323607572";
      /* 728x15, created 3/7/08 */
      google_ad_slot = "4271053867";
      google_ad_width = 700;
      google_ad_height = 15;
      //-->
      </script>
      <script type="text/javascript"
      src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
      </script>
      ')
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
        a(:href => R(Index)) {
          "blog"
        }
        text(", ")
        a(:href => R(Sources)) {
          "source code"
        }
        text(" and ")
        a(:href => R(Resume)) {
          "resume"
        }
        text(", a.k.a. The Land of the Rising Code.")
      }
      h3 {
        "I can also be found at..."
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
            img(:src => "/images/freshmeat.gif")
          }
        }
        #li {
        #  a(:href => "http://iphonebookmarklets.com/", :rel => :me) {
        #    img(:src => "http://iphonebookmarklets.com/logo.png")
        #  }
        #}
        li {
          a(:href => "http://upcoming.yahoo.com/user/70266/", :rel => :me) {
            img(:src => "/images/logo/logo_large_orange.png")
          }
        }
        li {
          a(:href => "http://slashdot.org/~diclophis", :rel => :me) {
            img(:src => "/images/slashdotlg.gif")
          }
        }
        li {
          a(:href => "http://www.vimeo.com/user1005919", :rel => :me) {
            img(:src => "/images/vimeo_logo.png", :width => 100)
          }
        }
        li {
          a(:href => "http://www.linkedin.com/pub/10/44/a08", :rel => :me) {
            img(:src => "/images/linkedin.gif")
          }
        }
        li {
          a(:href => "http://www.facebook.com/people/Jon-Bardin/5005911", :rel => :me) {
            img(:src => "/images/facebook_logo.gif")
          }
        }
      }
      h3 {
        "You can ask me anything about..."
      }
      p {
        @found.each { |word|
          a(:href => R(BookmarksByTag, word)) {
            text(" " + word)
          }
        }
      }
      h3 {
        "If I were a cloud of words..."
      }
      img(:src => "/images/wordcloud.png", :width => 699)
    }
  end
  def resume
    div {
      h1 {
        "Jon Bardin"
      }
    }
    div {
      p {"
       I am a bleeding edge technology evangelist.
       I spend my time dabbling in protoypes, widgets, gizmos and automatons.
      "}
    }
    div.experience {
      p {
        h3 {
          em {
            "Software Engineer - Timebridge"
          }
        }
        h4 {
          "July 2008 - October 2008, San Francisco, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Mobile Application Interface"
            }
            p {"
              Lead the development of a mobile interface to the primary web application.
              With this new feature, people are now able to view and interact with the system in a simplified and fast way.
            "}
          }
          li {
            h5 {
              "Daily Email Notification System"
            }
            p {"
              Designed to enhance the user experience by providing a summary of the users meetings for the given day.
              In conjunction to the meeting time and location data, the attendees were linked to a profiling application allowing for research of the person before the meeting.
            "}
          }
          li {
            h5 {
              "Rails Application Maintenance"
            }
            p {"
              Throughout my employment I was tasked with fixing many existing bugs within the web application.
            "}
          }
        }
      }
      p {
        h3 {
          em {
            "Software Engineer - CIS Data Systems"
          }
        }
        h4 {
          "September 2005 - July 2008, Oakland, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              "MVC Application Framework (Gears)"
            }
            p {
              "
                Used for several products, patterned after several key Rails concepts.
                Models are implemented through the PDO.
                Views are rendered through Smarty, with a Tag and Other Helpers library.
                Controllers follow the ActionController pattern.
              "
            }
          }
          li {
            h5 {
              "Toll-Free Listing Information System (ConnecTel)"
            }
            p {
              "
                Built with Gears, Apache, Asterisk and Ruby, this system provides telephony services to real-estate agents.
                They can manage their listings and settings through the phone or over the web.
              "
            }
          }
          li {
            h5 {
              "Web/Telephony Communication System (Click-to-Talk)"
            }
            p {
              "
                Extending the framework used for the ConnecTel product, this product allows people to connect in an unique way.
                A home-buyer is prompted through a online form for their phone number,  upon submission both parties are dialed simultaneously.
                Upon answering the calls are then connected through this system.
                During the call, the agent may then send urls to the home-buyer, which are automatically loaded in their web-browser.
              "
            }
          }
          li {
            h5 {
              "Automated Listing Information Hotline (ListingLine)"
            }
            p {
              "
                This product is a lightweight version of the ConnecTel product.
                It is integrated into an existing website hosting application, allowing agents to automatically make listing data available over the phone.
                Voice recordings are generated using text-to-speech technology, through templates defined in a domain specific language.
              "
            }
          }
          li {
            h5 {
              "MLS Aggregation System (IDXPro)"
            }
            p {
              "
                Built with Gears, this product aggregates over 300 MLS data feeds into a unified search / management interface.
                Once an agent is authorized for access to a particular MLS, this product allows them to provide a listing search interface to their customers.
                There is also a very advanced mapping search interface that allows for a unique home searching experience.
              "
            }
          }
        }
      }
      p {
        h3 {
          "Junior Software Engineer - USF College of Medicine"
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
              A system used by medical students to execute student government positions.
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
          "Junior Software Engineer - ImageLinks"
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
          "Junior Software Engineer - XL Vision"
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
        hr
        ul.projects {
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
      p {
        h3 {
          em {
            "Open Source Software Engineer"
          }
        }
        h4 {
          "December 2000 - Present, San Francisco, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              a(:href => "http://veejay.tv") {
                "VeeJay.tv"
              }
            }
            p {"
              Online music sharing / social messaging system
            "}
          }
          li {
            h5 {
              a(:href => "http://centerology.com") {
                "Centerology.com"
              }
            }
            p {"
              Social Image Bookmarking System
            "}
          }
          li {
            h5 {
              a(:href => "http://risingcode.com") {
                "RisingCode.com"
              }
            }
            p {"
               Personal blog built using ruby+camping 
            "}
          }
          li {
            h5 {
              "ProjectWiki"
            }
            p {"
               A server-side savable TiddlyWiki
            "}
          }
          li {
            h5 {
              "MyRingr"
            }
            p {"
               A web/telephony integration framework
            "}
          }
          li {
            h5 {
              "Mandelbrot Set Generator"
            }
            p {"
               C++ Generator + OpenLayers Web Interface
            "}
          }
          li {
            h5 {
              "Heatmap Image Generator"
            }
            p {"
              Generates heatmaps based on input data, used to overlay the original source
            "}
          }
          li {
            h5 {
              "Word Search Puzzle generator"
            }
            p {"
            "}
          }
          li {
            h5 {
              "SiG Reloaded"
            }
            p {"
              PHP5 Web Application Framework
            "}
          }
          li {
            h5 {
              "SiG Information Generator"
            }
            p {"
              PHP4 Web Application Framework
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
  def message
    flickr = nil
    wikipedia = nil
    youtube = nil
    div {
      fetched = Fast.fetch("http://api.flickr.com/services/feeds/photos_public.gne?tags=#{URI.encode(@tag)}&lang=en-us&format=rss_200")
      fetched = nil if fetched.blank?
      if fetched then
        doc = ::REXML::Document.new(fetched)
        event = nil
        doc.elements.each('/rss/channel/item') { |el|
          el.elements.each('link') { |li|
            flickr = "oembed. #{li.text}"
            text(flickr.textilize)
          }
          break
        }
      end
      fetched = Fast.fetch("http://en.wikipedia.org/wiki/Special:Search/#{@tag}")
      fetched = nil if fetched.blank?
      if fetched then
#Camping::Models::Base.logger.debug(fetched.slice(0, 100))
        doc = Hpricot(fetched)
        (doc / "li#ca-nstab-main").each { |el|
          text("oembed. http://en.wikipedia.org#{el.children[0].attributes['href']}".textilize)
          break
        }
        (doc / "ul.mw-search-results li").each { |el|
          text("oembed. http://en.wikipedia.org#{el.children[0].attributes['href']}".textilize)
          break
        }
      end
=begin
      fetched = Fast.fetch("http://www.vimeo.com/tag:#{@tag}/rss")
      fetched = nil if fetched.blank?
      Camping::Models::Base.logger.debug("#{fetched.length} wang chung")
      Camping::Models::Base.logger.debug("#{fetched.readlines.join} wang chung")
      if fetched and fetched.length > 2 then
        doc = ::REXML::Document.new(fetched)
        event = nil
        doc.elements.each('/rss/channel/item') { |el|
          el.elements.each('link') { |li|
            wikipedia = "oembed. #{li.text}"
            text(wikipedia.textilize)
          }
          break
        }
      end
      fetched = Fast.fetch("http://www.youtube.com/rss/tag/#{@tag}.rss")
      fetched = nil if fetched.blank?
      if fetched then
        doc = ::REXML::Document.new(fetched)
        event = nil
        doc.elements.each('/rss/channel/item') { |el|
          el.elements.each('link') { |li|
            text(("oembed. #{li.text.gsub("?v", "watch?v")}").textilize)
          }
          break
        }
      end
      fetched = Fast.fetch("http://www.slideshare.net/rss/tag/#{@tag}")
      fetched = nil if fetched.blank?
      if fetched then
        doc = ::REXML::Document.new(fetched)
        event = nil
        doc.elements.each('/rss/channel/item') { |el|
          el.elements.each('link') { |li|
            text(("oembed. #{li.text}").textilize)
          }
          break
        }
      end
=end
      p {
        a(:href => "http://delicious.com/tag/#{@tag}") {
          text("more about #{@tag}")
        }
      }
    }
  end
  def index
    div {
      @articles.each_with_index { |article, i|
        ul {
          li {
            h2 {
              a(:href => article.permalink) {
                text(article.title)
              }
            }
          }
          li {
            h3 {
              text(" on ")
              text(article.published_on.strftime("%B %d %Y"))
              text(" I wondered... ")
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
              text(article.excerpt.textilize)
              text(article.body.textilize)
            elsif not @single and not article.excerpt.blank? then
              text(article.excerpt.textilize)
            else
              text(article.body.textilize)
            end
          }
        }
      }
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
      ul {
        li {
          input(:type => :text, :name => :identity_url)
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
            input(:type => :submit, :value => "delete selected articles")
          } unless @articles.empty?
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
            img(:src => @image.icon_permalink)
          } unless @image.new_record?
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
