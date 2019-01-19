
require 'date'
require 'httpclient'
require 'httplog'
require 'json'
require 'pp'

HttpLog.configure do |config|
  config.color = :red
  config.compact_log = true
end

module Spyglass

  class HttpError < StandardError
    attr_reader :code, :message

    def initialize(code, message)
      @code, @message = code, message
    end

    def to_s
      "HTTP request failed (NOK) => #{@code} #{@message}"
    end
  end

  class DockerClient
    attr_reader :docker_registry, :docker_image

    def initialize(args = {})
      @client = HTTPClient.new
      @docker_registry = args[:docker_registry] || ENV['DOCKER_REGISTRY']
      @docker_image = args[:docker_image] || ENV['DOCKER_IMAGE']
      @username = args[:username] || ENV['DOCKER_USERNAME'] 
      @password = args[:password] || ENV['DOCKER_PASSWORD'] 
      pp docker_image
      pp docker_registry

      check_args
    end

    def check_args
      raise "missing DOCKER_REGISTRY" if docker_registry.nil?
      # raise "missing docker_image" if docker_image.nil?
    end

    def https_get(url, headers = {})
      res = @client.get(url, {}, headers)

      raise HttpError.new(res.status, res.body) if res.status != 200

      JSON.parse(res.body)
    end

    def https_head(url, headers = {})
      res = @client.head(url, {}, headers)

      raise HttpError.new(res.status, res.body) if res.status != 200

      res.headers
    end

    def https_post(url, options, headers = {})
      res = @client.post(url, options, headers)

      raise HttpError.new(res.status, res.body) if res.status != 200

      JSON.parse(res.body)
    end

    def token
      if @token.nil?
        headers = {
          'Accept' => 'application/json',
        }
        if @username && @password
          @token ||= https_get("#{docker_registry}/v2/token", headers)["token"]
          "https://auth.docker.io/token?scope=repository:$image:pull&service=registry.docker.io"
          @token ||= https_post("#{docker_registry}/v2/users/login", {"username" => @username, "password" => @password}, headers)["token"]
        elsif @docker_registry == "https://registry-1.docker.io"
          @token ||= https_get("https://auth.docker.io/token?scope=repository:#{@docker_image}:pull&service=registry.docker.io", headers)["token"]
        else
          @token ||= https_get("#{docker_registry}/v2/token", headers)["token"]
        end
      end

      @token
    end

    def auth_header
      headers = {
        "Authorization" => "Bearer #{token}"
      }
      # if @username && @password
      #   headers = {
      #     "Authorization" => "JWT: #{token}"
      #   }
      # else
      #   headers = {
      #     "Authorization" => "Bearer: #{token}"
      #   }
      # end
    end

    def get_manifest(docker_tag)
      raise "Tag is nil" if docker_tag.nil?

      headers = auth_header.merge({
        "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
      })
      https_get("#{docker_registry}/v2/#{docker_image}/manifests/#{docker_tag}", headers)
    end

    def get_blobs(manifest)
      raise "only v2 images are supported" if manifest["schemaVersion"] != 2
      config_digest = manifest["config"]["digest"]
      # registry-1.docker.io will redirect to CDN location
      r = @client.get_content("#{docker_registry}/v2/#{docker_image}/blobs/#{config_digest}", {}, auth_header)
      JSON.parse(r)
    end

    def get_tags
      https_get("#{docker_registry}/v2/#{docker_image}/tags/list", auth_header)["tags"]
    end

    def get_tag_timestamp(tag)
      headers = auth_header.merge({
        "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
      })
      last_modified = https_head("#{docker_registry}/v2/#{docker_image}/manifests/#{tag}", headers)["Last-Modified"]
      DateTime.parse(last_modified)
    end
  end
end
