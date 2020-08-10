##
# Custom delegate for Canadiana's configuration of Cantaloupe
##

require 'cgi'
require 'uri'
require 'jwt'
require 'json'

class CustomDelegate
  attr_accessor :context

  def extractJwt
    cookieval = nil
    query = CGI.parse(URI.parse(context["request_uri"]).query || '')
    # there's a bug in Cantaloupe 4 that doesn't generate the context["cookies"] hash in the way you'd expect; here's the fix
    if (context["cookies"]["Cookie"].respond_to?(:match))
      cookieval = context["cookies"]["Cookie"].match (/auth_token=(.[^;$]*)/) { |kv| kv[1] }
    end
    header_match = context["request_headers"]["Authorization"].match(/Bearer (.+)/) if context["request_headers"]["Authorization"]

    return (query["token"] ? query["token"][0] : nil) ||
      cookieval ||
      (header_match ? header_match[0] : nil) ||
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
  end

  def overlay(options = {})
  end

  def redactions(options = {})
    []
  end
end

