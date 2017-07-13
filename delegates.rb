##
# Based on Sample Ruby script from Cantelope 3.3
# This sets up Canadiana specific configuration
##
require 'cgi'
require 'zlib'

module Cantaloupe

##
  # Tells the server whether the given request is authorized. Will be called
  # upon all image requests to any endpoint.
  #
  # Implementations should assume that the underlying resource is available,
  # and not try to check for it.
  #
  # @param identifier [String] Image identifier
  # @param full_size [Hash<String,Integer>] Hash with `width` and `height`
  #                                         keys corresponding to the pixel
  #                                         dimensions of the source image.
  # @param operations [Array<Hash<String,Object>>] Array of operations in
  #                   order of execution. Only operations that are not no-ops
  #                   will be included. Every hash contains a `class` key
  #                   corresponding to the operation class name, which will be
  #                   one of the e.i.l.c.operation.Operation implementations.
  # @param resulting_size [Hash<String,Integer>] Hash with `width` and `height`
  #                       keys corresponding to the pixel dimensions of the
  #                       resulting image after all operations are applied.
  # @param output_format [Hash<String,String>] Hash with `media_type` and
  #                                            `extension` keys.
  # @param request_uri [String] Full request URI
  # @param request_headers [Hash<String,String>]
  # @param client_ip [String]
  # @param cookies [Hash<String,String>]
  # @return [Boolean,Hash<String,Object] To allow or deny the request, return
  #         true or false. To perform a redirect, return a hash with
  #         `location` and `status_code` keys. `location` must be a URL;
  #         `status_code` must be an integer from 300 to 399.
  #
  def self.authorized?(identifier, full_size, operations, resulting_size,
                       output_format, request_uri, request_headers, client_ip,
                       cookies)
    true
  end

  ##
  # Used to add additional keys to an information JSON response, including
  # `attribution`, `license`, `logo`, `service`, and other custom keys. See
  # the [Image API specification]
  # (http://iiif.io/api/image/2.1/#image-information).
  #
  # @param identifier [String] Image identifier
  # @return [Hash] Hash that will be merged into IIIF Image API 2.x
  #                information responses. Return an empty hash to add nothing.
  #
  def self.extra_iiif2_information_response_keys(identifier)
=begin
    Example:
    {
        'attribution' =>  'Copyright My Great Organization. All rights '\
                          'reserved.',
        'license' =>  'http://example.org/license.html',
        'logo' =>  'http://example.org/logo.png',
        'service' => {
            '@context' => 'http://iiif.io/api/annex/services/physdim/1/context.json',
            'profile' => 'http://iiif.io/api/annex/services/physdim',
            'physicalScale' => 0.0025,
            'physicalUnits' => 'in'
        }
    }
=end
    {}
  end


  module FilesystemResolver

    ##
    # @param identifier [String] Image identifier
    # @return [String,nil] Absolute pathname of the image corresponding to the
    #                      given identifier, or nil if not found.
    #
    def self.get_pathname(identifier)
      baserepo = '/repository/poolaip';
      repolist = Dir.entries(baserepo);
      aip, partpath = CGI::unescape(identifier).split('/', 2);
      depositor, objid = aip.split('.')
      aip_hash = Zlib::crc32(aip).to_s[-3..-1]
      aip_path = nil;
      repolist.each do |path|
        testpath = [baserepo, path, depositor, aip_hash, aip].join("/")
        if File.directory?(testpath)
          aip_path = testpath
          break
        end
      end
      return nil unless aip_path
      # Note: For anything beyond a test script, don't trust 'partpath' (check for ../)
      return [aip_path, partpath].join("/")
    end

  end

end

# Uncomment to test on the command line (`ruby delegates.rb`)
# puts Cantaloupe::FilesystemResolver::get_pathname('oocihm.lac_reel_h1015%2Fdata%2Fsip%2Fdata%2Ffiles%2F0004.jpg')
