
require 'date'
require 'net/http'
require 'net/https'
require 'json'
require 'pp'

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
      @docker_registry = args[:docker_registry] || ENV['DOCKER_REGISTRY'] || "https://docker-dev.groupondev.com"
      @docker_image = args[:docker_image] || ENV['DOCKER_IMAGE'] || "ie/titan"
      @username = args[:username] || ENV['DOCKER_USERNAME'] 
      @password = args[:password] || ENV['DOCKER_PASSWORD'] 
      pp docker_image
      pp docker_registry

      check_args
    end

    def check_args
      raise "missing DOCKER_REGISTRY" if docker_registry.nil?
      raise "missing docker_image" if docker_image.nil?
    end

    def https_get(url, headers = {})
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      headers.each do |k,v|
        req[k] = v
      end

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        http.request(req)
      end

      raise HttpError.new(res.code, res.message) if res.code != "200"

      JSON.parse(res.body)
    end

    def https_head(url, headers = {})
      uri = URI(url)
      req = Net::HTTP::Head.new(uri)
      headers.each do |k,v|
        req[k] = v
      end

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        http.request(req)
      end

      raise HttpError.new(res.code, res.message) if res.code != "200"

      res.each_header.to_h
    end

    def https_post(url, headers = {})
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      headers.each do |k,v|
        req[k] = v
      end

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        http.request(req)
      end

      raise HttpError.new(res.code, res.message) if res.code != "200"

      JSON.parse(res.body)
    end

    def token
      if @token.nil?
        # headers = {}
        # headers.merge!({"username" => @username, "password" => @password}) if @username && @password
        # @token = https_get("#{docker_registry}/v2/token", headers)["token"]
        @token ||= https_get("#{docker_registry}/v2/token")["token"]
      end

      @token
    end

    def get_manifest(docker_tag)
      pp docker_tag
      raise "Tag is nil" if docker_tag.nil?


      uri = URI("#{docker_registry}/v2/#{docker_image}/manifests/#{docker_tag}")

      headers = {
        "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
        "Authorization" => "Bearer: #{token}"
      }
      https_get("#{docker_registry}/v2/#{docker_image}/manifests/#{docker_tag}", headers)
    end

    def get_blobs(manifest)
      config_digest = manifest["config"]["digest"]
      headers = {
        "Authorization" => "Bearer: #{token}"
      }
      https_get("#{docker_registry}/v2/#{docker_image}/blobs/#{config_digest}", headers)
    end

    def get_tags
      headers = {
        "Authorization" => "Bearer: #{token}"
      }
      https_get("#{docker_registry}/v2/#{docker_image}/tags/list", headers)["tags"]
    end

    def get_most_recent_tags(size = 3)
      tags = get_tags

      headers = {
        "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
        "Authorization" => "Bearer: #{token}"
      }

      tag_map = tags.map do |tag|
        last_modified = https_head("#{docker_registry}/v2/#{docker_image}/manifests/#{tag}", headers)["last-modified"]
        [tag, DateTime.parse(last_modified)]
      end.to_h

      tag_map.sort_by {|k,v| v}.reverse.map { |x| x.first }.take(size)
    end
  end
end

# Spyglass::Fetch.new.diff
# Spyglass::Fetch.new.view("latest")
# Spyglass::Fetch.new.view("2.5")
