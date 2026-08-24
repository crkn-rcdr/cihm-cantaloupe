##
# Custom delegate for Canadiana's configuration of Cantaloupe (5.x compatible)
##

require 'cgi'
require 'jwt'
require 'json'
require 'socket'
require 'thread'
require 'zlib'
require 'uri'

class RedisHashClient
  def initialize(url, timeout)
    uri = URI.parse(url)
    @host = uri.host || "127.0.0.1"
    @port = uri.port || 6379
    @timeout = timeout.to_f
    @socket = TCPSocket.new(@host, @port)
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

    authenticate(uri)
    select_database(uri)
  end

  def hget(hash_name, field)
    call("HGET", hash_name, field)
  end

  def close
    @socket&.close
  end

  private

  def authenticate(uri)
    return unless uri.password || (uri.user && !uri.user.empty?)

    if uri.password
      username = CGI.unescape(uri.user.to_s)
      password = CGI.unescape(uri.password)
      username.empty? ? call("AUTH", password) : call("AUTH", username, password)
    else
      call("AUTH", CGI.unescape(uri.user))
    end
  end

  def select_database(uri)
    database = uri.path.to_s.sub(%r{\A/}, "")
    call("SELECT", database) unless database.empty? || database == "0"
  end

  def call(*parts)
    write_command(parts)
    read_response
  end

  def write_command(parts)
    payload = +"*#{parts.length}\r\n"
    parts.each do |part|
      value = part.to_s
      payload << "$#{value.bytesize}\r\n#{value}\r\n"
    end

    wait_writable
    @socket.write(payload)
  end

  def read_response
    line = read_line
    type = line[0, 1]
    body = line[1, line.length]

    case type
    when "+"
      body
    when "-"
      raise body
    when ":"
      body.to_i
    when "$"
      read_bulk_string(body.to_i)
    else
      raise "Unexpected Redis response: #{line.inspect}"
    end
  end

  def read_bulk_string(length)
    return nil if length == -1

    data = read_exact(length)
    read_exact(2)
    data
  end

  def read_line
    wait_readable
    line = @socket.gets("\r\n")
    raise "Redis closed the connection" unless line

    line.chomp
  end

  def read_exact(length)
    buffer = +""
    while buffer.bytesize < length
      wait_readable
      buffer << @socket.readpartial(length - buffer.bytesize)
    end
    buffer
  end

  def wait_readable
    return unless @timeout.positive?
    return if IO.select([@socket], nil, nil, @timeout)

    raise "Redis read timed out after #{@timeout}s"
  end

  def wait_writable
    return unless @timeout.positive?
    return if IO.select(nil, [@socket], nil, @timeout)

    raise "Redis write timed out after #{@timeout}s"
  end
end

class CustomDelegate
  attr_accessor :context

  DEFAULT_EXTENSION = "jpg"
  MISSING_EXTENSIONS = ["", "none", "null", "nil"].freeze
  EXTENSION_CACHE_MAX_ENTRIES = ENV.fetch("IMAGE_EXTENSIONS_CACHE_SIZE", "50000").to_i
  SOURCE_PATH_CACHE_MAX_ENTRIES = ENV.fetch("IMAGE_SOURCE_PATHS_CACHE_SIZE", EXTENSION_CACHE_MAX_ENTRIES.to_s).to_i
  IMAGE_EXTENSIONS_REDIS_URL = ENV["IMAGE_EXTENSIONS_REDIS_URL"].to_s
  IMAGE_EXTENSIONS_REDIS_HASH = ENV.fetch("IMAGE_EXTENSIONS_REDIS_HASH", "image_extensions")
  IMAGE_SOURCE_PATHS_REDIS_HASH = ENV.fetch("IMAGE_SOURCE_PATHS_REDIS_HASH", "image_source_paths")
  EXTENSION_REDIS_POOL_SIZE = ENV.fetch("IMAGE_EXTENSIONS_REDIS_POOL_SIZE", "64").to_i
  EXTENSION_REDIS_TIMEOUT_SECONDS = ENV.fetch("IMAGE_EXTENSIONS_REDIS_TIMEOUT_SECONDS", "0.5").to_f
  EXTENSION_REDIS_BACKOFF_SECONDS = ENV.fetch("IMAGE_EXTENSIONS_REDIS_BACKOFF_SECONDS", "10").to_f
  PRESERVATION_BUCKET_ENV_NAMES = [
    "S3SOURCE_PRESERVATION_BUCKET_NAME",
    "S3SOURCE_BASICLOOKUPSTRATEGY_BUCKET_NAME"
  ].freeze
  CACHE_MISS = Object.new.freeze
  REDIS_UNAVAILABLE = Object.new.freeze
  @@extension_cache = {}
  @@extension_cache_fingerprint = nil
  @@extension_cache_mutex = Mutex.new
  @@source_path_cache = {}
  @@source_path_cache_fingerprint = nil
  @@source_path_cache_mutex = Mutex.new
  @@extension_redis_pool = []
  @@extension_redis_pool_open_count = 0
  @@extension_redis_pool_mutex = Mutex.new
  @@extension_redis_pool_condition = ConditionVariable.new
  @@extension_redis_disabled_until = 0.0
  @@extension_redis_last_error_logged_at = 0.0

  #
  # Canvas lookup (unchanged logic, safer handling)
  #
  def canvas
    return @canvas if @canvas

    access_container_name = ENV["S3SOURCE_ACCESSFILES_BUCKET_NAME"].to_s
    identifier = context["identifier"].to_s

    return nil if identifier.empty?

    extension = extension_from_index(identifier)
    if extension && !access_container_name.empty?
      @canvas = access_canvas(access_container_name, identifier, extension)
      return @canvas
    end

    source_path = source_path_from_index(identifier)
    preservation_container = preservation_container_name
    if source_path && !preservation_container.empty?
      @canvas = {
        "filename" => source_path,
        "source"   => preservation_container
      }
      return @canvas
    end

    return nil if access_container_name.empty?

    @canvas = access_canvas(access_container_name, identifier, DEFAULT_EXTENSION)
  end

  def access_canvas(container_name, identifier, extension)
    {
      "filename" => "#{identifier}.#{extension}",
      "source"   => container_name
    }
  end

  def swift_filename(container_name, identifier)
    "#{identifier}.#{extension_for(identifier)}"
  end

  def extension_for(identifier)
    extension_from_index(identifier) || DEFAULT_EXTENSION
  end

  def preservation_container_name
    PRESERVATION_BUCKET_ENV_NAMES.each do |env_name|
      container_name = ENV[env_name].to_s.strip
      return container_name unless container_name.empty?
    end

    ""
  end

  def extension_from_index(identifier)
    return nil unless redis_enabled?

    fingerprint = extension_index_fingerprint
    cached = extension_cache_get(identifier, fingerprint)
    return nil if cached.equal?(CACHE_MISS)
    return cached if cached

    extension = extension_from_redis(identifier)
    return nil if extension.equal?(REDIS_UNAVAILABLE)

    extension_cache_put(identifier, extension || CACHE_MISS, fingerprint)
    extension
  end

  def source_path_from_index(identifier)
    return nil unless redis_enabled?

    fingerprint = source_path_index_fingerprint
    cached = source_path_cache_get(identifier, fingerprint)
    return nil if cached.equal?(CACHE_MISS)
    return cached if cached

    source_path = source_path_from_redis(identifier)
    return nil if source_path.equal?(REDIS_UNAVAILABLE)

    source_path_cache_put(identifier, source_path || CACHE_MISS, fingerprint)
    source_path
  end

  def extension_index_fingerprint
    ["redis", IMAGE_EXTENSIONS_REDIS_URL, IMAGE_EXTENSIONS_REDIS_HASH]
  end

  def source_path_index_fingerprint
    ["redis", IMAGE_EXTENSIONS_REDIS_URL, IMAGE_SOURCE_PATHS_REDIS_HASH]
  end

  def extension_from_redis(identifier)
    return REDIS_UNAVAILABLE unless redis_enabled?

    client = nil
    begin
      client = checkout_extension_redis_client
      normalize_extension(client.hget(IMAGE_EXTENSIONS_REDIS_HASH, identifier))
    rescue StandardError => e
      discard_extension_redis_client(client)
      client = nil
      disable_extension_redis(e)
      REDIS_UNAVAILABLE
    ensure
      checkin_extension_redis_client(client) if client
    end
  end

  def source_path_from_redis(identifier)
    return REDIS_UNAVAILABLE unless redis_enabled?

    client = nil
    begin
      client = checkout_extension_redis_client
      normalize_source_path(client.hget(IMAGE_SOURCE_PATHS_REDIS_HASH, identifier))
    rescue StandardError => e
      discard_extension_redis_client(client)
      client = nil
      disable_extension_redis(e)
      REDIS_UNAVAILABLE
    ensure
      checkin_extension_redis_client(client) if client
    end
  end

  def redis_enabled?
    !IMAGE_EXTENSIONS_REDIS_URL.empty? &&
      Time.now.to_f >= @@extension_redis_disabled_until
  end

  def checkout_extension_redis_client
    client = nil
    create_client = false

    @@extension_redis_pool_mutex.synchronize do
      loop do
        client = @@extension_redis_pool.pop
        break if client

        if @@extension_redis_pool_open_count < extension_redis_pool_size
          @@extension_redis_pool_open_count += 1
          create_client = true
          break
        end

        @@extension_redis_pool_condition.wait(@@extension_redis_pool_mutex)
      end
    end

    begin
      create_client ? open_extension_redis_client : client
    rescue StandardError
      release_extension_redis_client_slot
      raise
    end
  end

  def checkin_extension_redis_client(client)
    @@extension_redis_pool_mutex.synchronize do
      @@extension_redis_pool << client
      @@extension_redis_pool_condition.signal
    end
  end

  def discard_extension_redis_client(client)
    return unless client

    close_extension_redis_client(client)
    release_extension_redis_client_slot
  end

  def release_extension_redis_client_slot
    @@extension_redis_pool_mutex.synchronize do
      @@extension_redis_pool_open_count -= 1 if @@extension_redis_pool_open_count.positive?
      @@extension_redis_pool_condition.signal
    end
  end

  def extension_redis_pool_size
    [EXTENSION_REDIS_POOL_SIZE, 1].max
  end

  def open_extension_redis_client
    RedisHashClient.new(IMAGE_EXTENSIONS_REDIS_URL, EXTENSION_REDIS_TIMEOUT_SECONDS)
  end

  def close_extension_redis_client(client)
    client.close if client.respond_to?(:close)
  rescue StandardError => e
    puts "Redis extension client close failed: #{e.message}"
  end

  def disable_extension_redis(error)
    now = Time.now.to_f
    @@extension_redis_disabled_until = now + EXTENSION_REDIS_BACKOFF_SECONDS
    return if now - @@extension_redis_last_error_logged_at < EXTENSION_REDIS_BACKOFF_SECONDS

    @@extension_redis_last_error_logged_at = now
    puts "Redis extension lookup disabled temporarily: #{error.message}"
  end

  def extension_cache_get(identifier, fingerprint)
    return nil unless extension_cache_enabled?

    @@extension_cache_mutex.synchronize do
      reset_extension_cache_if_needed(fingerprint)
      value = @@extension_cache.delete(identifier)
      @@extension_cache[identifier] = value if value
      value
    end
  end

  def extension_cache_put(identifier, value, fingerprint)
    return unless extension_cache_enabled?

    @@extension_cache_mutex.synchronize do
      reset_extension_cache_if_needed(fingerprint)
      @@extension_cache.delete(identifier)
      @@extension_cache[identifier] = value
      @@extension_cache.shift while @@extension_cache.size > EXTENSION_CACHE_MAX_ENTRIES
    end
  end

  def extension_cache_enabled?
    EXTENSION_CACHE_MAX_ENTRIES.positive?
  end

  def reset_extension_cache_if_needed(fingerprint)
    return if @@extension_cache_fingerprint == fingerprint

    @@extension_cache.clear
    @@extension_cache_fingerprint = fingerprint
  end

  def source_path_cache_get(identifier, fingerprint)
    return nil unless source_path_cache_enabled?

    @@source_path_cache_mutex.synchronize do
      reset_source_path_cache_if_needed(fingerprint)
      value = @@source_path_cache.delete(identifier)
      @@source_path_cache[identifier] = value if value
      value
    end
  end

  def source_path_cache_put(identifier, value, fingerprint)
    return unless source_path_cache_enabled?

    @@source_path_cache_mutex.synchronize do
      reset_source_path_cache_if_needed(fingerprint)
      @@source_path_cache.delete(identifier)
      @@source_path_cache[identifier] = value
      @@source_path_cache.shift while @@source_path_cache.size > SOURCE_PATH_CACHE_MAX_ENTRIES
    end
  end

  def source_path_cache_enabled?
    SOURCE_PATH_CACHE_MAX_ENTRIES.positive?
  end

  def reset_source_path_cache_if_needed(fingerprint)
    return if @@source_path_cache_fingerprint == fingerprint

    @@source_path_cache.clear
    @@source_path_cache_fingerprint = fingerprint
  end

  def normalize_extension(extension)
    normalized = extension.to_s.strip.sub(/\A\./, "").downcase
    return nil if MISSING_EXTENSIONS.include?(normalized)

    normalized
  end

  def normalize_source_path(source_path)
    normalized = source_path.to_s.strip
    return nil if MISSING_EXTENSIONS.include?(normalized.downcase)

    normalized
  end

  #
  # Extract JWT from query param, cookie, or Authorization header
  # Cantaloupe 5 FIX: remove old cookie workaround
  #
  def extractJwt
    uri = URI.parse(context["request_uri"]) rescue nil
    query = uri ? CGI.parse(uri.query.to_s) : {}

    # Query parameter token
    return query["token"].first if query["token"]&.any?

    # Cookie parsing (5.x provides normalized cookies)
    cookies = context["cookies"] || {}
    return cookies["auth_token"] if cookies["auth_token"]

    # Authorization header (Bearer token)
    headers = context["request_headers"] || {}
    auth = headers["Authorization"] || headers["authorization"]

    if auth && auth =~ /^Bearer\s+(.+)$/
      return Regexp.last_match(1)
    end

    nil
  end

  #
  # Validate JWT
  #
  def validateJwt(token)
    payload = JWT.decode(token, nil, false)[0] rescue nil
    return nil unless payload

    issuer = payload["iss"]
    return nil unless issuer

    signing_key =
      if issuer == "CAP"
        ENV["CAP_JWT_SECRET"]
      elsif issuer.match(%r{https://auth.*\.canadiana\.ca/})
        ENV["AUTH_JWT_SECRET"]
      end

    return nil unless signing_key

    JWT.decode(token, signing_key, true, algorithm: "HS256")[0]
  rescue JWT::DecodeError => e
    puts "JWT decode error: #{e.message}"
    nil
  end

  #
  # Authorization hook
  #
  def pre_authorize(options = {})
    authorize(options)
  end

  def authorize(options = {})
    canvas = self.canvas

    # Public access if no takedown
    return true if canvas && !canvas["takedown"]

    token = extractJwt
    unless token
      puts "Unauthorized: No JWT provided"
      return false
    end

    jwt_data = validateJwt(token)
    unless jwt_data
      puts "Unauthorized: Invalid JWT"
      return false
    end

    if jwt_data["derivativeFiles"]
      unless context["identifier"]&.match(jwt_data["derivativeFiles"])
        puts "Unauthorized: derivativeFiles restriction failed"
        return false
      end
    end

    true
  end

  #
  # IIIF 2 extension hook (kept for backward compatibility)
  #
  def extra_iiif2_information_response_keys(options = {})
    {}
  end

  def extra_iiif3_information_response_keys(options = {})
    {}
  end

  def deserialize_meta_identifier(identifier = nil)
    nil
  end

  def serialize_meta_identifier(identifier = nil)
    nil
  end

  def source(options = {})
    nil
  end

  def azurestoragesource_blob_key(options = {})
    nil
  end

  #
  # Filesystem source resolution (unchanged logic, safer)
  #
  def filesystemsource_pathname(options = {})
    repository_base = ENV["REPOSITORY_BASE"]
    return nil unless repository_base

    canvas = self.canvas
    pathname = canvas ? canvas.dig("master", "path") : context["identifier"]
    return nil unless pathname

    aip, partpath = CGI.unescape(pathname).split("/", 2)
    depositor = aip.split(".").first
    aip_hash = Zlib.crc32(aip).to_s[-3..]

    Dir.entries(repository_base).grep_v(/^\./).each do |path|
      testpath = File.join(repository_base, path, depositor, aip_hash, aip)
      return File.join(testpath, partpath) if File.directory?(testpath)
    end

    nil
  end

  def httpsource_resource_info(options = {})
    canvas = self.canvas
    return nil unless canvas

    base_url = swift_preauth_base_url
    return nil if base_url.empty?

    {
      "uri" => swift_http_url(base_url, canvas["source"], canvas["filename"])
    }
  end

  def swift_preauth_base_url
    explicit_url = ENV["IIIF_SWIFT_PREAUTH_URL"].to_s
    return explicit_url unless explicit_url.empty?

    legacy_url = ENV["SWIFT_PREAUTH_URL"].to_s
    return legacy_url unless legacy_url.empty?

    swift_endpoint = ENV["S3SOURCE_ENDPOINT"].to_s
    return "" if swift_endpoint.empty?

    tenant = ENV["SWIFT_TENANT"].to_s
    tenant = ENV["SWIFT_TENNANT"].to_s if tenant.empty?
    tenant = ENV["S3SOURCE_ACCESS_KEY_ID"].to_s.split(":", 2)[1].to_s if tenant.empty?
    return "" if tenant.empty?

    "#{swift_endpoint.chomp("/")}/v1/#{escape_path_segment(tenant)}"
  end

  def swift_http_url(base_url, container_name, filename)
    [
      base_url.chomp("/"),
      escape_path_segment(container_name),
      filename.to_s.split("/").map { |part| escape_path_segment(part) }.join("/")
    ].join("/")
  end

  def escape_path_segment(segment)
    CGI.escape(segment.to_s).gsub("+", "%20")
  end

  def jdbcsource_database_identifier(options = {})
    nil
  end

  def jdbcsource_last_modified(options = {})
    nil
  end

  def jdbcsource_media_type(options = {})
    nil
  end

  def jdbcsource_lookup_sql(options = {})
    nil
  end

  #
  # S3 source mapping
  #
  def s3source_object_info(options = {})
    canvas = self.canvas
    return nil unless canvas

    {
      "bucket" => canvas["source"],
      "key"    => canvas["filename"]
    }
  end

  def metadata(options = {})
    nil
  end

  def overlay(options = {})
    {}
  end

  #
  # No overlays / redactions by default
  #
  def redactions(options = {})
    []
  end
end
