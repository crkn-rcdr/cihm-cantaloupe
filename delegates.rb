##
# Custom delegate for Canadiana's configuration of Cantaloupe
##

require 'cgi'
require 'jwt'
require 'json'
require 'zlib'
require 'net/http'

class CustomDelegate
  attr_accessor :context

  def check_couch(container_name)
    canvas_uri = URI([ENV["CANVAS_DB"], CGI.escape(@context["identifier"])].join("/"))
    response = Net::HTTP.get_response(canvas_uri)
    return nil unless response.is_a?(Net::HTTPSuccess)
    couch_res = JSON.parse(response.body)
    extension = couch_res.dig("master", "extension")  # Safely dig for 'extension'
    if extension
      return { 
        "filename" => "#{@context['identifier']}.#{extension}",
        "source" => ENV["S3SOURCE_ACCESSFILES_BUCKET_NAME"]
      }
    else # TODO: We need a script to clean up images so that they are all in access-files
      return { 
        "filename" => couch_res.dig("source", "path"), 
        "source" => ENV["S3SOURCE_BASICLOOKUPSTRATEGY_BUCKET_NAME"]
      }
    end
  end

  def canvas
    return @canvas if @canvas  
    container_name = ENV["S3SOURCE_ACCESSFILES_BUCKET_NAME"]
    @canvas = self.check_couch(container_name)
    # For new IIIF Presentation API Workflow:
    # If canvas is not found in legacy access database, attempt to 
    # retrieve it from Swift directly.
    # Python ended up running quicker and being cleaner than
    # network requests in ruby.
    unless @canvas
      filename = `python3 /etc/swift.py '#{container_name}' '#{@context["identifier"]}'`
      @canvas = { 
        "filename" => filename.chomp,
        "source" => container_name
      }
    end
    @canvas
  end

  def extractJwt
    query = CGI.parse(URI.parse(context["request_uri"]).query || '')
    # there's a bug in Cantaloupe 4 that doesn't generate the context["cookies"] hash in the way you'd expect; here's the fix
    cookies = context["cookies"]["Cookie"] || ""
    cookie_token = cookies.match(/auth_token=(.[^;$]*)/) { |kv| kv[1] }
    header_match = context["request_headers"]["Authorization"].match(/Bearer (.+)/) if context["request_headers"]["Authorization"]
    return (query["token"] ? query["token"][0] : nil) ||
      cookie_token ||
      (header_match ? header_match[1] : nil) ||
      nil
  end

  def validateJwt(token)
    jwtData = nil

    begin
      jwtData = JWT.decode(token, nil, false)[0]
    rescue JWT::DecodeError => e
      puts "JWT Decode error: #{e.message}"
      return nil
    end

    issuer = jwtData["iss"]
    unless (issuer)
      puts "JWT must indicate issuer in payload."
      return nil
    end

    if (issuer == "CAP")
      signingKey = ENV["CAP_JWT_SECRET"]
    elsif (/https:\/\/auth.*\.canadiana\.ca\//.match(issuer))
      signingKey = ENV["AUTH_JWT_SECRET"]
    end

    unless (signingKey)
      puts "JWT cannot be decoded with #{issuer}'s secret key."
      return nil
    end

    jwtData = nil
    begin
      jwtData = JWT.decode(token, signingKey, true, { :algorithm => 'HS256' })[0]
    rescue JWT::DecodeError => e
      puts "JWT Decode error: #{e.message}"
      return nil
    end

    return jwtData
  end

  def authorize(options = {})
    canvas = self.canvas
    if (canvas && !canvas["takedown"])
      return true
    else
      jwt = self.extractJwt

      unless (jwt)
        puts "Unauthorized: JWT could not be extracted from request."
        return false
      end
  
      jwtData = validateJwt(jwt)
      unless (jwtData)
        puts "Unauthorized: JWT could not be validated."
        return false
      end
  
      if (jwtData["derivativeFiles"])
        unless (context["identifier"].match jwtData["derivativeFiles"])
          puts "Unauthorized: Derivative image requested that was not allowed by the 'derivativeFiles' condition."
          return false
        end
      end
  
      return true
    end
  end

  def extra_iiif2_information_response_keys(options = {})
    {}
  end

  def source(options = {})
  end

  def azurestoragesource_blob_key(options = {})
  end

  def filesystemsource_pathname(options = {})
    repository_base = ENV["REPOSITORY_BASE"]
    repository_list = Dir.entries(repository_base).grep_v(/^\.*$/)
    canvas = self.canvas
    if canvas
      # TODO: Do we want to bother supporting ZFS filesystem any more?
      # access-files Swift container may have different images...
      # should we be looking at canvas["source"]["path"] ?
      pathname = canvas["master"]["path"]
    else
      pathname = context["identifier"]
    end
    aip, partpath = CGI::unescape(pathname).split('/', 2)
    depositor = aip.split('.')[0]
    aip_hash = Zlib::crc32(aip).to_s[-3..-1]
    aip_path = nil;
    repository_list.each do |path|
      testpath = [repository_base, path, depositor, aip_hash, aip].join("/")
      if File.directory?(testpath)
        aip_path = testpath
        break
      end
    end
    return nil unless aip_path
    # Note: For anything beyond a test script, don't trust 'partpath' (check for ../)
    return [aip_path, partpath].join("/")
  end

  def httpsource_resource_info(options = {})
  end

  def jdbcsource_database_identifier(options = {})
  end

  def jdbcsource_media_type(options = {})
  end

  def jdbcsource_lookup_sql(options = {})
  end

  def s3source_object_info(options = {})
    canvas = self.canvas
    rv = { 
      "bucket" => canvas["source"],
      "key" => canvas["filename"]
    }
    return rv
  end

  def overlay(options = {})
  end

  def redactions(options = {})
    []
  end
end

