##
# Custom delegate for Canadiana's configuration of Cantaloupe
##

require 'cgi'
require 'jwt'
require 'json'
require 'net/http'

class CustomDelegate
  attr_accessor :context

  def canvas
    unless @canvas
      if context["identifier"].start_with?("69429")
        canvas_uri = URI([ENV["CANVAS_DB"], CGI.escape(context["identifier"])].join("/"))
        response = Net::HTTP.get_response(canvas_uri)
        @canvas = response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
      else
        @canvas = nil
      end
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
    return "FilesystemSource"
  end

  def azurestoragesource_blob_key(options = {})
  end

  def filesystemsource_pathname(options = {})
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
    rv = { "bucket" => ENV["S3SOURCE_BASICLOOKUPSTRATEGY_BUCKET_NAME"] }
    canvas = self.canvas
    if canvas
      rv["key"] = canvas["master"]["path"]
    else
      rv["key"] = context["identifier"]
    end
    return rv
  end

  def overlay(options = {})
  end

  def redactions(options = {})
    []
  end
end

