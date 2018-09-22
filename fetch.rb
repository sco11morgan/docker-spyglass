
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

  class Fetch
    attr_reader :docker_registry, :docker_image, :docker_tag, :token

    def initialize(args = {})
      @docker_registry = ENV['DOCKER_REGISTRY'] || "https://docker.groupondev.com"
      @docker_image = ENV['DOCKER_IMAGE'] || "rapt/deploy_kubernetes"
      @docker_tag = ENV['DOCKER_TAG'] || "v0.1"

      check_args

      @token = args[:token ] || get_token

      @token ||= get_token
      puts @token
      manifest = get_manifest
      pp "==================== "
      # pp @manifest
      pp "==================== "
      blobs = get_blobs(manifest)
      # pp @blobs
      pp "==================== "

      pp mash(manifest, blobs)
    rescue => e 
      puts e
    end

    def check_args
      raise "missing DOCKER_REGISTRY" if docker_registry.nil?
      raise "missing DOCKER_IMAGE" if docker_image.nil?
      raise "missing DOCKER_TAG" if docker_tag.nil?
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

    def get_token
      @token ||= https_get("#{docker_registry}/v2/token")["token"]
    end

    def get_manifest
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

    def mash(manifest, blobs)
      history = blobs["history"]
      layers = manifest["layers"]

      commands = history.map do |command|
        if command["empty_layer"]
          command["size"] = 0
        else
          command["size"] = layers.shift["size"]
        end
        command["created_by"] = command["created_by"].sub("/bin/sh -c #(nop) ", "")

        command
      end
    end

  end
end

Spyglass::Fetch.new.get_token
