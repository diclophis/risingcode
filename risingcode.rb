#!/usr/bin/ruby

require 'gserver'
require 'uri'
require 'rubygems'

require 'sqlite3'

require 'time'
require 'redcloth'
require 'digest/md5'
require 'ruby2ruby'
require 'drb'

require 'net/smtp'

require "active_record"

require "camping"
require 'camping/session'

#require 'openid'
#require 'openid/store/filesystem'
#require 'openid/consumer'
#require 'openid/extensions/sreg'

#import into this file
require '/home/application/acts_as_taggable'
require '/home/application/tag_list'
require '/home/application/documentation_server'
require '/home/application/slugalizer'
require '/home/application/lockfile'

Camping.goes :RisingCode

module RisingCode
  module Models
$ARV_EXTRAS = %{
  def self.V(n)
    @final = [n, @final.to_f].max
    m = (@migrations ||= [])
    Class.new(ActiveRecord::Migration[6.0]) do
      meta_def(:version) { n }
      meta_def(:inherited) { |k| m << k }
    end
  end

  def self.create_schema(opts = {})
    opts[:assume] ||= 0
    opts[:version] ||= @final
    if @migrations
      unless SchemaInfo.table_exists?
        ActiveRecord::Schema.define do
          create_table SchemaInfo.table_name do |t|
            t.column :version, :float
          end
        end
      end
      si = SchemaInfo.all.first || SchemaInfo.new(:version => opts[:assume])
      if si.version < opts[:version]
        @migrations.sort_by { |m| m.version }.each do |k|
          k.migrate(:up) if si.version < k.version and k.version <= opts[:version]
          k.migrate(:down) if si.version > k.version and k.version > opts[:version]
        end
        si.update(:version => opts[:version])
      end
    end
  end

}
    module_eval $ARV_EXTRAS
  end
end

module RisingCodeTags
  def hard_breaks; false; end
  def css(opts)
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
      problem.inspect
    end
  end
  def ruby(opts)
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "rb")
    rescue Exception => problem
      problem.inspect
    end
  end
  def rhtml(opts)
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "rhtml")
    rescue Exception => problem
      problem.inspect
    end
  end
  def javascript(opts)
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "js")
    rescue Exception => problem
      problem.inspect
    end
  end
  def cpp(opts)
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "cpp")
    rescue Exception => problem
      problem.inspect
    end
  end
  def objc(opts)
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "mm")
    rescue Exception => problem
      problem.inspect
    end
  end
  def java(opts)
    content = opts[:text]
    begin
      return DocumentationServer::SERVER.highlight(content, "java")
    rescue Exception => problem
      problem.inspect
    end
  end
end

class String
  def textilize
    wang = RedCloth.new(self, [:no_span_caps]).extend(::RisingCodeTags).to_html
    wang
  end
end

module RisingCode
  set :secret, "sql"
  include Camping::Session 

  def user_logged_in
    @state.authenticated == true
  end

  def log_user_out
    @state.authenticated = false
  end

  def view_images
    @viewing_images = true
    yield
  end
  def without_layout
    @no_layout = true
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
      self.permalink = SecureRandom.hex.to_s if self.permalink.blank?
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
    validates :name, :format => { :with => /\A[a-zA-Z0-9\-]+\z/, :message => "Only letters allowed" }
    cattr_accessor :destroy_unused
    self.destroy_unused = false
    def self.find_or_create_with_like_by_name(name)
      where("name LIKE ?", name).first || create(:name => name)
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
end

module RisingCode::Controllers
  class Index < R('/', '/(articles)', '/([a-zA-Z0-9 ]+)/(\d*)', '/(\d+)/(\d+)/(\d+)', '/(\w+)/(\w+)/(\w+)/([\w-]+)')
    def get(*args)
      @limit = 5
      @offset = 0
      @use_page_navigation = false
      @use_date_navigation = false
      @tags = Tag.all #(true)
      @active_tab = "risingcode"
      if args.empty? then
        @limit = 1
        @current_action = :index
        @permalink = "%"
        @now = Time.now
        @use_date_navigation = true
      elsif args.length == 1 then
        @articles = Article.order("published_on asc").all
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
      @articles = Article.where("permalink like ? and (date(published_on) <= ? or ?)", @permalink, @now, user_logged_in).order("published_on desc") if @articles.nil?
      #@old_ranger = Article.find(
      #  :first,
      #  :conditions => ["date(published_on) <= ? and id < ?", Time.now, @articles.last.id],
      #  :limit => @limit,
      #  :order => "published_on asc") if @articles.length > 0
      #@new_ranger = Article.find(
      #  :first,
      #  :conditions => ["date(published_on) <= ? and id > ?", Time.now, @articles.first.id],
      #  :limit => @limit,
      #  :order => "published_on desc") if @articles.length > 0
      #@single = @articles.length == 1
      render :index
    end
  end

  class Logout < R("/dashboard/logout")
    def get
      log_user_out
      redirect R(Index)
    end
  end

  class Contact < R("/contact")
    def get
      primes = []
      state = Numeric.new
      (2300..3500).each { |i|
         (2..(Math.sqrt(i).ceil)).each { |thing|
            state = 1
            if (i.divmod(thing)[1] == 0)
               state = 0
               break
            end
         }
         primes << i unless (state == 0)
      }
      random_primes = primes.sort_by { rand }
      @state.contact_me_token = SecureRandom.hex.to_s
      @state.authentication_token = "#{primes[0]}x#{primes[1]}"
      @large_factor = primes[0] * primes[1]
      render :contact
    end
    def post(*args)
      begin
        Lockfile.new('/home/application/db/lock') do
          sleep 5
          if @input.agree_to_tos.nil? and @input.i_am_not_a_robot == @state.contact_me_token and @input.authentication_token == @state.authentication_token then
            @state.contact_me_token = SecureRandom.hex.to_s
            Net::SMTP.start('localhost') do |smtp|
              smtp.sendmail("Subject: Contact Form Submission\n\n#{@input.inspect}", "www-data", "Jon Bardin <diclophis@gmail.com>")
            end
            other_layout {
              return render :thanks
            }
          else
            @state.contact_me_token = SecureRandom.hex.to_s
            return "<a href=\"#{R(Contact)}\">try again</a>"
          end
        end
      rescue => problem
        return "really, don't do that"
      end
    end
  end

  class About < R('/about')
    def get
      @title = "Jon Bardin lives in the Land of the Rising Code"

      @tags = Tag.where(:include_in_header => true)
      @active_tab = "about"
      render :about
    end
  end

  class Resume < R('/about/resume')
    def get
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "about"
      render :resume
    end
  end

  class Login < R("/dashboard/login(.*)")
    def get(*args)
      other_layout {
        render :login
      }
    end

    def post(*args)
      if @input.identity_url == "foobarbaz" then #TODO: !!! real security !!!
        @state.authenticated = true
        return redirect(R(Dashboard))
      else
        raise "wtf"
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

=begin
  class Images < R('/imagery')
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
  class BookmarksByTag < R('/bookmarks/tagged/([a-zA-Z0-9\-]+)', '/bookmarks/tagged/([a-zA-Z0-9\-]+)/([0-9]+)')
    def get (tag, page = nil)
      @tag = tag
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "bookmarks"
      raise "bookmarks model needs impl"
      @bookmarks = Delicious::Bookmarks.all(0, 99999)
      @bookmarks_for_tag = []
      @bookmarks.each { |date, bookmarks|
        bookmarks.each { |bookmark|
          @bookmarks_for_tag << bookmark if (bookmark["tag"].include?(tag) or bookmark["href"].include?(tag))
        }
      }
      @title = "Bookmarks tagged #{@tag}"
      @page = page
      if @page then
        @offset = 10 * @page.to_i
      else
        @offset = 0
      end
      render :bookmarks_by_tag
    end
  end
  class Bookmarks < R('/bookmarks', '/bookmarks/(\d+)/(\d+)/(\d+)')
    def get (*args)
      @tags = Tag.find_all_by_include_in_header(true)
      @active_tab = "bookmarks"
      return render :coming_soon
      raise "bookmarks model needs impl"
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
  class Highlight < R('/highlight/(\w+)\.(\w+)')
    def post(*args)
      @code = args.inspect + @input.inspect 
      unless @input.the_file.is_a?(String) then
        @code = DocumentationServer::SERVER.highlight(@input.the_file[:tempfile].read, args[1])
        #@code += @input.the_file[:tempfile].read
      end
      without_layout {
        render :highlight
      }
    end
  end
=end

  class RetrieveArticles < R("/dashboard/articles")
    def get
      administer { 
        @articles = Article.all
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

  class RetrieveTags < R("/dashboard/tags")
    def get
      administer { 
        @tags = Tag.all
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
          @article = Article.find(article_id)
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
          @article = Article.find(article_id)
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

=begin
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
=end
end

module RisingCode::Views
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
              #text {
                article.excerpt.textilize + article.body.textilize
              #}
              #text {
              #}
            elsif not @single and not article.excerpt.blank? then
              #text {
                article.excerpt.textilize
              #}
            else
              #text {
                article.body.textilize
              #}
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

  def thanks
    div {
      h1 {
        "Thanks!"
      }
      p {
        "I will try to get back to you as soon as possible..."
      }
      a(:href => R(Index)) {
        "return to index"
      }
    }
  end

  def contact
    form(:action => R(Contact), :method => :post) {
      ul {
        li {
          label {
            "Please State Your Name"
          }
          input(:id => "your_name", :name => "name", :type => "text", :disabled => :disabled) 
        }
        li {
          label {
            "And Your Business"
          }
          textarea(:id => "token", :class => @large_factor, :name => "business", :rows => 10, :cols => 10, :disabled => :disabled) {}
        }
        li {
          table {
            if rand > 0.5 then
              i_am_a_robot
              i_am_not_a_robot
            else
              i_am_not_a_robot
              i_am_a_robot
            end
          }
        }
        li {
          input(:id => "gotime", :class => @state.contact_me_token, :type => "submit", :value => "please wait...", :disabled => :disabled)
          span.wait! {
            "&nbsp;&nbsp;I am authenticating your session, please allow this script to finish before submitting"
          }
        }
      }
    }
    script(:src => "/javascripts/prototype.js", :type => "text/javascript") {
      "//foo"
    }
    script(:src => "/javascripts/filter.js", :type => "text/javascript") {
      "//foo"
    }
  end

  def i_am_a_robot
    tr {
      td.shrink {
        input(:id => "i_am_a_robot", :type => "checkbox", :name => "agree_to_tos", :disabled => :disabled)
      }
      td.puff {
        label(:for => "i_am_a_robot") {
          "You are a robot"
        }
      }
    }
  end

  def i_am_not_a_robot
    tr {
      td.human!(:class => "shrink") {
      }
      td.puff {
        label(:for => "i_am_not_a_robot") {
          "You are <em>not</em> a robot"
        }
      }
    }
  end

  def layout
    if @no_layout then
      self << yield
      return
    end

    html {
      head {
        meta("charset" => "utf-8")
        title {
          @title or "Land of the Rising Code"
        }
        link(:rel => "stylesheet", :type => "text/css", :href => "/stylesheets/vanilla.css")
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
                #@tags.each { |tag|
                #  li(:class => ((tag.name == @active_tab) ? "active" : "")) {
                #    h1 {
                #      a(:href => R(Index, tag.name, nil)) {
                #        text(tag.name.capitalize)
                #      }
                #    }
                #  }
                #}
              }
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
                      h1 {
                        a(:href => R(Dashboard), :class => ((@current_action == :dashboard) ? :current : nil)) {
                          "Dashboard"
                        }
                      }
                    }
                    li {
                      h1 {
                        a(:href => R(RetrieveArticles), :class => ((@current_action == :articles) ? :current : nil)) {
                          "Articles"
                        }
                      }
                    }
                    #li {
                    #  a(:href => R(RetrieveImages), :class => ((@current_action == :images) ? :current : nil)) {
                    #    h1 {
                    #      "Images"
                    #    }
                    #  }
                    #}
                    li {
                      h1 {
                        a(:href => R(RetrieveTags), :class => ((@current_action == :tags) ? :current : nil)) {
                          "Tags"
                        }
                      }
                    }
                    li {
                      h2 {
                        a(:href => R(CreateOrUpdateArticle, nil)) {
                          text("new article")
                        }
                      }
                    }
                    li {
                      h2 {
                        a(:href => R(CreateOrUpdateTag, nil)) {
                          text("new tag")
                        }
                      }
                    }
                    #li {
                    #  a(:href => R(CreateOrUpdateImage, nil)) {
                    #    h2 {
                    #      text("new image")
                    #    }
                    #  }
                    #}
                  }
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
      }
    }
  end

=begin
  def images
    div {
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
  def coming_soon
    h3 { "Coming Soon" }
  end
  def bookmarks_by_tag
    div {
      ul.bookmarks {
        @bookmarks_for_tag.slice(@offset, 10).each { |bookmark|
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
                h4 {
                  a(:href => bookmark["href"]) {
                    bookmark["excerpt"]
                  }
                }
              end
            else
              text(oembed)
            end
            p {
              text(bookmark["extended"])
            } unless bookmark["extended"].blank?
            h5.taglabel {
              text("tags")
            }
            div.tagdisplay {
              ul.tags {
                bookmark["tag"].split(" ").each { |tag|
                  r = nil
                  begin
                    r = R(BookmarksByTag, Slugalizer.slugalize(tag))
                  rescue
                  end
                  unless r.blank?
                    li {
                      a(:href => r) {
                        span {
                          text("&nbsp;" + tag)
                        }
                      }
                    }
                  end
                }
              }
            }
            div.clr {}
          }
        }
        if @offset > 0 then
          a(:href => R(Learn, @tag)) {
            text("Learn more about #{@tag}")
          }
        else
          a(:href => R(BookmarksByTag, Slugalizer.slugalize(@tag), 1)) {
            text("More tagged #{@tag} >>")
          }
        end

      }
    }
  end
  def bookmarks
    div {
      h2 {
        if @found.at_center > 1 then
          text(@s + " started with #{@found.first}, featured a #{@found.center} flavoured lunch, ended in a #{@found.last} afternoon")
        elsif @found.at_center == 1 then
          text(@s + " was a half #{@found.first} and half #{@found.last} kinda day")
        else
          text(@s + " was a whole lotta #{@found.first || :nothing}")
        end
      }
      ul.bookmarks {
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
                h3 {
                  a(:href => bookmark["href"]) {
                    text(bookmark["excerpt"])
                  }
                }
              end
            else
              text(oembed)
            end
            p {
              text(bookmark["extended"])
            } unless bookmark["extended"].blank?
            h5.taglabel {
              text("tags")
            }
            div.tagdisplay {
              ul.tags {
                bookmark["tag"].split(" ").each { |tag|
                  li {
                    a(:href => R(BookmarksByTag, Slugalizer.slugalize(tag))) {
                      span {
                        text("&nbsp;" + tag)
                      }
                    }
                  }
                }
              }
            }
            div.clr {}
          }
        }
      }
      bookmarks_nav
    }
  end
  def bookmarks_nav
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
  end
=end

  def about
    div {
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
        #text(", ")
        #a(:href => R(Sources)) {
        #  "source code"
        #}
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
          a(:href => "http://github.com/diclophis", :rel => :me) {
            img(:src => "/images/github.png")
          }
        }
        li {
          a(:href => "http://stackoverflow.com/users/32678?sort=recent", :rel => :me) {
            img(:src => "/images/stackoverflow.png")
          }
        }
        #li {
        #  a(:href => "http://www.engadget.com/profile/68892/", :rel => :me) {
        #    img(:src => "/images/engadget.gif")
        #  }
        #}
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
        li {
          a(:href => "https://web.archive.org/web/20130423144543/http://upcoming.yahoo.com/user/70266/", :rel => :me) {
            img(:src => "/images/upcoming.png")
          }
        }
        li {
          a(:href => "https://web.archive.org/web/20090824114341/http://freshmeat.net/users/jbardin/", :rel => :me) {
            img(:src => "/images/freshmeat.gif")
          }
        }
        li {
          a(:href => "http://code.google.com/u/102182916232982105135/", :rel => :me) {
            img(:src => "/images/google_code.png")
          }
        }
        li {
          a(:href => "http://del.icio.us/diclophis", :rel => :me) {
            img(:src => "/images/del.gif")
          }
        }
      }
      h3 {
        "You can ask me anything about..."
      }
      img(:src => "/images/wordcloud.png", :width => 699, :usemap => "#wordcloud_map")
    }
  end
  def resume
    div {
      h1 {
        text("Jon Bardin")
        a(:href => R(Contact), :class => :unprintable) {
          text("&nbsp;contact me if you are not a robot")
        }
      }
    }
    div {
      p {"
       I am a bleeding edge technology evangelist.
       I spend my time dabbling in prototypes, widgets, gizmos and automatons.
      "}
    }
    div.experience {
      div {
        h3 {
          em {
            "Senior Software Engineer - Mavenlink Inc."
          }
        }
        h4 {
          "June April - Preset, San Francisco, CA"
        }
      }
      div {
        h3 {
          em {
            "Senior Software Engineer - GREE Intl."
          }
        }
        h4 {
          "June 2011 - February 2013, San Francisco, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Systems Administration / DevOps on OpenFeint Platform"
            }
            p {"
              After GREE's acquisition of OpenFeint, my duties shifted from application development to Server Ops of the OpenFeint platform.
              I was the release manager for all QA and Production deploys of the OpenFeint platform.
              I also performed routine performance monitoring and uptime reporting of the system, and reported any errors/events back to the engineering team.
              During this time we scaled up the throughput of the platform from 50k requests-per-minute to 120k requests-per-minute using a variety of optimizations and infrastructure upgrades.
            "}
          }
          li {
            h5 {
              "HTML5 Game Engine"
            }
            p {"
              After we finished stabilizing the OpenFeint platform, I transitioned my role into a game developer using HTML5 technologies.
              I help develop and architect the foundation of 2 published game titles. (" +
              a(:href => "https://itunes.apple.com/us/app/nfl-shuffle/id572960605?mt=8") { "NFL Shuffle" } +
              " / " +
              a(:href => "https://itunes.apple.com/ca/app/book-ashes-age-dragons/id571986621?mt=8") { "Book of Ashes: The Age of Dragons" } +
              ") This foundation included a PHP Application Framework, PHPUnit unit-test suite, Selenium/Rspec acceptance-test suite and a native Android/iOS 'shell' application.
              I was responsible for several core web-based systems such as performance/error monitoring, as well as building an automated deployment system using Jenkins.
              Additionally I developed several of the native iOS bridging components used for asset delivery to mobile clients.
            "}
          }
          li {
            h5 {
              "Sports Themed HTML5 Card Game (NFL Shuffle)"
            }
            p {"
              I developed (using our in house html5-core technology) several core gameplay features.
              My primary responsibility was developing an animation system used during the main 'card-combat' scenes in the game.
              This was accomplished using CSS3 keyframe animations and Javascript.
            "}
            a.unprintable(:href => "https://itunes.apple.com/us/app/nfl-shuffle/id572960605?mt=8") {
              "NFL Shuffle on iTunes"
            }
          }
        }
      }
      div {
        h3 {
          em {
            "Senior Software Engineer - OpenFeint"
          }
        }
        h4 {
          "October 2009 - June 2011, Burlingame, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              "Virtual Economy Platform (OFX)"
            }
            p {"
              By provided a REST based API to store resources we enable social game developers to quickly integrate virtual economy functionality into their titles.
              The service is centered around items that can be purchased in game via real-money micro-payments or in game virtual currency.
              My main responsibility was implementing the server-side functionality of the platform.
              Building on top of an existing Rails project infrastructure our team added several new features including a Scribe based event logger, an asynchronous offline package generation process,
              a virtual store and user inventory management interface.
            "}
          }
          li {
            h5 {
              "Instant Messaging And Presence Platform (OFSocket)"
            }
            p {"
              Evented message based server infrastructure.
              Built using Ruby EventMachine and RabbitMQ.
              Implemented client side networking with asynchrounous tcp socket programming techniques.
              Custom streaming-text based wire protocol.
              Used for IM functionality and Forum Topic pubsub style notifications.
              Services >70k simultaneous client connections.
            "}
          }
          li {
            h5 {
              "Cross Platform Social Gaming Platform (XP)"
            }
            p {"
              Responsible for minor operations duties, such as deploys, hot-fixes, and basic server monitoring.
              Implemented / Enhanced several features like Forums and Moderation and Abuse Flagging.
              Maintained multi-host QA infrastructure.
              Also part of the team implementing a new architecture for the core service to provide enhanced cross-platform support, namely Android clients.
              Tons of bug-fixing and refactoring. 
            "}
          }
        }
      }
      div {
        h3 {
          em {
            "Senior Software Engineer - Funji"
          }
        }
        h4 {
          "January 2009 - October 2009, San Francisco, CA"
        }
        hr
        ul.projects {
          li {
            h5 {
              "iPhone Social Network Application (Funji Home)"
            }
            p {"
             Architected and implemented both the iPhone frontend and Linux/Rails backend system.
             Features include real time group chat / instant messaging, sprite based room decoration, community forum, message wall, point system, virtual goods store.
             The client/server protocol is Thrift, the database is MySQL, and the server is a multi-threaded ruby application.
            "}
          }
          li {
            h5 {
              "Side Scrolling iPhone Game (Funji Float)"
            }
            p {"
              Lead the engineering on a basic side-scrolling sprite based game engine.
              The graphics engine was built on top of CoreAnimation, the sound system was built on top of AVFoundation.
              Gameplay is based around the idea that you are a character from Funji Home, floating around and collecting fruit for points.
            "}
          }
          li {
            h5 {
              "Finger Maze iPhone Game (Funji Flush)"
            }
            p {"
              Building on top of the game engine I developed for Funji Float, we built a second game with simple maze dynamics.
              This games primary purpose was to serve as a marketing platform for the Funji Home application.
            "}
          }
          li {
            h5 {
              "Frogger Clone iPhone Game (Funji Bunny)"
            }
            p {"
              Again using the game engine from Funji Float we built an homage to frogger.
            "}
          }
          li {
            h5 {
              "Marketing Website (funji.me)"
            }
            p {"
              Built with Rails, it features a basic authentication mechanism allowing users to participate in the Funji Home community without an iPhone.
            "}
          }
        }
      }
      h4.only_print {
        "... continued at http://risingcode.com/about/resume"
      }
      div.unprintable {
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
      div.unprintable {
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
      div.unprintable {
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
      div.unprintable {
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
          li.unprintable {
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
      div.unprintable {
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
          li.unprintable {
            h5 {
              "Online List-Serve interface"
            }
            p {"
              An ASP interface for a list-serve.
              Used to facilitate intra-office communication.
            "}
          }
          li.unprintable {
            h5 {
              "Linux Server administration"
            }
            p {"
              Configuration of Apache, PHP, MySQL to meet the needs of several intranet applications.
            "}
          }
        }
      }
      div.unprintable {
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
      div.unprintable {
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
              a(:href => "http://web.archive.org/web/20090311001445/http://veejay.tv/") {
                "VeeJay.tv"
              }
            }
            p {"
              Online music sharing / social messaging system
            "}
          }
          li {
            h5 {
              a(:href => "http://web.archive.org/web/20090416041116/http://centerology.com/?") {
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
              a(:href => "https://web.archive.org/web/20190609132324/http://www.kivaiphoneapp.com/contributors.php") {
                "Kiva iPhone App"
              }
            }
            p {"
              iPhone Kiva Application
            "}
          }
          li {
            h5 {
              a(:href => "https://github.com/diclophis/projectwiki") {
                "ProjectWiki"
              }
            }
            p {"
               A server-side savable TiddlyWiki
            "}
          }
          li {
            h5 {
              a(:href => "https://github.com/diclophis/myringr") {
                "MyRingr"
              }
            }
            p {"
               A Ruby web/telephony integration framework for Asterisk
            "}
          }
          li {
            h5 {
              a(:href => "https://github.com/diclophis/mandelbrot") {
                "Mandelbrot Set Generator"
              }
            }
            p {"
               C++ Generator + OpenLayers Web Interface
            "}
          }
          li {
            h5 {
              a(:href => "https://github.com/diclophis/heatmap") {
                "Heatmap Image Generator"
              }
            }
            p {"
              Generates heatmaps based on input data, used to overlay the original source
            "}
          }
          li {
            h5 {
              a(:href => "https://github.com/diclophis/wordsearch") {
                "Word Search Puzzle generator"
              }
            }
            p {"
              PHP5 Library for generating word search puzzles.
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

=begin
  def highlight
    @code
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
=end

  def login
    form(:method => :post) {
      ul {
        li {
          input(:type => :text, :name => :identity_url)
        }
        li {
          input(:type => "submit")
        }
      }
    }
  end
  def dashboard
    div {
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
            input(:type => :submit, :value => "delete selected tags")
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
=begin
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
            input(:type => :submit, :value => "delete selected images")
          } if @images.length > 0
        }
      }
    }
  end
=end
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
            input(:type => :submit)
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
            input(:type => :submit)
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
            input(:type => :submit)
          }
        }
      }
    }
  end
end
