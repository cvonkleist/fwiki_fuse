require 'fusefs'
require 'net/http'
require 'nokogiri'
require 'cgi'

class String
  def path_to_title
    sub(%r(^/), '')
  end
end

class FwikiFuse
  def initialize(host, port, username, password)
    @host, @port, @username, @password = host, port, username, password
    @http = Net::HTTP.new(@host, @port)
    @http.set_debug_output STDERR
  end

  def markdown(page)
    response = get(page, 'raw' => 'fishsticks')
    puts response.inspect
    raise Errno::ENOENT unless response.code == '200'
    response.read_body
  end

  ## fuse methods

  def contents(path)
    all_titles
  end

  def file?(path)
    all_titles.include?(path.path_to_title)
  end

  def size(path)
    sizes[path.path_to_title]
  end

  def read_file(path)
    markdown(path)
  end

  def write_to(path, contents)
    response = put(path, contents)
    raise Errno::EAGAIN unless response.code == '200'
  end

  def can_write?(path)
    # prevent vim temp files
    path[-1,1] == '~' ? false : true
  end

  def can_delete?(path)
    true
  end
  private

  # when opening a file, applications like vim will do many checks of the
  # file's contents, size, etc., which leads to tons of http requests. the
  # problem can be avoided by caching data for a safe amount of time, like 1
  # second.
  def cache(key)
    @cache ||= {}
    timestamp, data = @cache[key]
    if timestamp && data && Time.now - timestamp < 1
      puts 'CACHE HIT'
      data
    else
      data = yield
      @cache[key] = [Time.now, data]
      data
    end
  end

  def all_titles
    sizes.keys
  end

  def sizes
    cache(:sizes) do
      response = get('/', :long => 'wangs')
      raise Errno::ENOENT unless response.code == '200'
      doc = Nokogiri::XML(response.read_body)
      doc.search('//ul[@id = "pages"]/li').inject({}) do |sum, li|
        sum.merge CGI.unescapeHTML(li.at('a').inner_html) => li.inner_html[%r((\d+) bytes), 1].to_i
      end
    end
  end

  def get(path, params = {})
    cache([:get, path, params]) do
      request = Net::HTTP::Get.new(escape(path))
      request.form_data = params
      request.basic_auth @username, @password
      @http.request(request)
    end
  end

  def head(path, params = {})
    cache([:head, path, params]) do
      request = Net::HTTP::Head.new(escape(path))
      request.form_data = params
      request.basic_auth @username, @password
      @http.request(request)
    end
  end

  def put(path, contents)
    cache([:put, path, contents]) do
      request = Net::HTTP::Put.new(escape(path))
      request.set_form_data(:contents => contents)
      request.basic_auth @username, @password
      @http.request(request)
    end
  end

  def escape(path)
    CGI.escape(path).gsub('%2F', '/')
  end
end

if $0 == __FILE__
  host, port, username, password, mount_dir = ARGV
  raise "usage: #{$0} host port username password mount_dir" unless host && port && username && password && mount_dir
  fwiki_fuse = FwikiFuse.new(host, port, username, password)
  FuseFS.set_root fwiki_fuse
  FuseFS.mount_under mount_dir
  FuseFS.run
end
