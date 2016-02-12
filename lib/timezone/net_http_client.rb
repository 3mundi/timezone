require 'uri'
require 'net/http'

module Timezone
  # @!visibility private
  # A basic HTTP Client that handles requests to Geonames and Google.
  #
  # You can create your own version of this class if you want to use
  # a proxy or a different http library such as faraday.
  #
  # @example
  #     Timezone::Lookup.config(:google) do |c|
  #       c.api_key = 'foo'
  #       c.http_client = Timezone::NetHTTPClient
  #     end
  #
  class NetHTTPClient
    def initialize(protocol, host)
      uri = URI.parse("#{protocol}://#{host}")
      @http = Net::HTTP.new(uri.host, uri.port)
      @http.use_ssl = (protocol == 'https'.freeze)
    end

    def get(url)
      @http.request(Net::HTTP::Get.new(url))
    end
  end
end
