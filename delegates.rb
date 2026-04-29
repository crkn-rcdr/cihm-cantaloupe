##
# Custom delegate for Canadiana's configuration of Cantaloupe (5.x compatible)
##

require 'cgi'
require 'jwt'
require 'json'
require 'zlib'
require 'uri'

begin
  require 'java'
  java_import 'java.sql.DriverManager'
  java.lang.Class.forName('org.sqlite.JDBC')
rescue StandardError => e
  puts "SQLite JDBC unavailable: #{e.message}"
end

class CustomDelegate
  attr_accessor :context

  IMAGE_EXTENSIONS_DB = ENV["IMAGE_EXTENSIONS_DB"]
  DEFAULT_EXTENSION = "jpg"
  @@extension_db_connection = nil
  @@extension_db_mutex = Mutex.new

  #
  # Canvas lookup (unchanged logic, safer handling)
  #
  def canvas
    return @canvas if @canvas

    container_name = ENV["S3SOURCE_ACCESSFILES_BUCKET_NAME"]
    identifier = context["identifier"]

    return nil unless container_name && identifier

    filename = swift_filename(container_name, identifier)

    @canvas = {
      "filename" => filename,
      "source"   => container_name
    }
  end

  def swift_filename(container_name, identifier)
    "#{identifier}.#{extension_for(identifier)}"
  end

  def extension_for(identifier)
    extension_from_db(identifier) || DEFAULT_EXTENSION
  end

  def extension_from_db(identifier)
    return nil unless defined?(DriverManager) && File.readable?(IMAGE_EXTENSIONS_DB)

    @@extension_db_mutex.synchronize do
      connection = extension_db_connection
      statement = connection.prepareStatement(
        "SELECT extension FROM image_extensions WHERE identifier = ?"
      )
      begin
        statement.setString(1, identifier)
        result = statement.executeQuery
        begin
          return normalize_extension(result.getString(1)) if result.next
        ensure
          result.close
        end
      ensure
        statement.close
      end
    end
  rescue StandardError => e
    puts "SQLite extension lookup failed for #{identifier}: #{e.message}"
    nil
  end

  def extension_db_connection
    @@extension_db_connection ||= DriverManager.getConnection(
      "jdbc:sqlite:file:#{IMAGE_EXTENSIONS_DB}?mode=ro&immutable=1"
    )
  end

  def normalize_extension(extension)
    extension.to_s.sub(/\A\./, "").downcase
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
    nil
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
