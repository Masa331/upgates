# frozen_string_literal: true

class Upgates
  class UnknownError < StandardError; end
  class TooManyRequests < StandardError; end
  class TooManyRedirects < StandardError; end

  class ApiEnumerator < SimpleDelegator
    def initialize(base_url, data_key, params, api)
      @base_url = base_url
      @params = params
      @data_key = data_key
      @api = api

      @enum = Enumerator.new do |y|
        first_page.fetch(@data_key,  []).each { y.yield(_1) }

        if total_pages > 1
          (2..(total_pages - 1)).each do |page|
            @api.get(base_url, params.merge(page: page))
              .fetch(@data_key, [])
              .each { y.yield(_1) }
          end

          last_page.fetch(@data_key,  []).each { y.yield(_1) }
        end
      end

      super(@enum)
    end

    def first_page
      @first_page ||= @api.get(@base_url, @params)
    end

    def last_page
      return first_page if total_pages < 2

      @last_page ||= @api.get(@base_url, @params.merge(page: total_pages))
    end

    def total_pages
      first_page.dig('number_of_pages') || 0
    end

    def size
      first_page.dig('number_of_items')
    end
  end

  def initialize(base_url, client_id, client_secret)
    @base_url = base_url
    @client_id = client_id
    @client_secret = client_secret
  end

  def valid_credentials?
    get['code'] == '404'
  end

  def products(params = {})
    enumerize('/products', 'products', params)
  end

  def categories(params = {})
    enumerize('/categories', 'categories', params)
  end

  def enumerize(base_url, data_key, params = {})
    ApiEnumerator.new(base_url, data_key, params, self)
  end

  def get(path = '', params = {})
    parsed = URI(@base_url + path)
    parsed.query = URI.encode_www_form(params) if params.any?

    internal_get(parsed)
  end

  private

  def internal_get(parsed, redirects = 0)
    http = Net::HTTP.new(parsed.host, parsed.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(parsed)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Basic #{encoded_authorization}"

    response = http.request(request)

    if response.code == '200'
      JSON.parse(response.body).merge('code' => response.code)
    elsif response.code == '301'
      if redirects < 4
        internal_get(URI(response['Location']), redirects + 1)
      else
        raise Upgates::TooManyRedirects.new
      end
    elsif response.code == '429'
      raise Upgates::TooManyRequests.new
    else
      raise Upgates::UnknownError.new("#{response.code}: #{response.body}: #{response.each.map { |k, v| [k, v] }}")
    end
  end

  def encoded_authorization
    @authorization ||= Base64.urlsafe_encode64("#{@client_id}:#{@client_secret}")
  end
end
