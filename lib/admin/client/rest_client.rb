require 'json'

module AdminUI
  class RestClient
    def initialize(config, logger)
      @config = config
      @logger = logger
    end

    def delete_cc(path)
      cf_request('DELETE', get_cc_url(path), nil, nil)
    end

    def get_cc(path)
      uri = "#{ @config.cloud_controller_uri }/#{ path }"

      resources = []
      loop do
        json = cf_request('GET', uri, nil, nil)
        resources.concat(json['resources'])
        next_url = json['next_url']
        return resources if next_url.nil?
        uri = "#{ @config.cloud_controller_uri }#{ next_url }"
      end
      resources
    end

    def get_uaa(path)
      info

      uri = "#{ @token_endpoint }/#{ path }"

      resources = []
      loop do
        json = cf_request('GET', uri, nil, nil)
        resources.concat(json['resources'])
        total_results = json['totalResults']
        start_index = resources.length + 1
        return resources unless total_results > start_index
        uri = "#{ @token_endpoint }/#{ path }?startIndex=#{ start_index }"
      end

      resources
    end

    def put_cc(path, body)
      cf_request('PUT', get_cc_url(path), nil, body)
    end

    private

    def cf_request(method, url, basic_auth, body)
      recent_login = false
      if @token.nil?
        login
        recent_login = true
      end

      loop do
        response = Utils.http_request(@config, url, method, basic_auth, body, @token)

        if method == 'GET' && response.is_a?(Net::HTTPOK)
          return JSON.parse(response.body)
        elsif method == 'PUT' && (response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPCreated))
          return JSON.parse(response.body)
        elsif method == 'DELETE' && (response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPNoContent))
          return
        end

        if recent_login && response.is_a?(Net::HTTPUnauthorized)
          login
          recent_login = true
        else
          fail "Unexected response code from #{ method } is #{ response.code }, message #{ response.message }"
        end
      end
    end

    def get_cc_url(path)
      if path && path[0] == '/'
        return "#{ @config.cloud_controller_uri }#{ path }"
      else
        return "#{ @config.cloud_controller_uri }/#{ path }"
      end
    end

    def login
      info

      @token = nil

      response = Utils.http_request(
          @config,
          "#{ @authorization_endpoint }/oauth/token",
          'POST',
          nil,
          "grant_type=password&username=#{ @config.uaa_admin_credentials_username }&password=#{ @config.uaa_admin_credentials_password }",
          'Basic Y2Y6')

      if response.is_a?(Net::HTTPOK)
        body_json = JSON.parse(response.body)
        @token = "#{ body_json['token_type'] } #{ body_json['access_token'] }"
      else
        fail "Unexpected response code from login is #{ response.code }, message #{ response.message }"
      end
    end

    def info
      return unless @token_endpoint.nil?

      response = Utils.http_request(@config, "#{ @config.cloud_controller_uri }/info", 'GET')

      if response.is_a?(Net::HTTPOK)
        body_json = JSON.parse(response.body)

        @authorization_endpoint = body_json['authorization_endpoint']
        if @authorization_endpoint.nil?
          fail "Information retrieved from #{ url } does not include authorization_endpoint"
        end

        @token_endpoint = body_json['token_endpoint']
        if @token_endpoint.nil?
          fail "Information retrieved from #{ url } does not include token_endpoint"
        end
      else
        fail "Unable to fetch info from #{ url }"
      end
    end
  end
end
