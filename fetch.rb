
require 'date'
require 'net/http'
require 'net/https'
require 'json'
require 'pp'


class Hash
    def - (h)
        self.merge(h) do |k, old, new|
            case old.class
                when Array then (new.class == Array) ? (old - new) : (old - [new])
                when Hash then (old - new)
                else (old == new) ? nil : old
            end
        end
    end
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

  class Fetch
    attr_reader :docker_registry, :docker_image, :docker_tag

    def initialize(args = {})
      @docker_registry = args[:docker_registry] || ENV['DOCKER_REGISTRY'] || "https://docker-dev.groupondev.com"
      @docker_image = args[:docker_image] || ENV['DOCKER_IMAGE'] || "ie/titan"

      check_args
      raise "No tags found" if tags.empty?
    end

    def view(tag = nil)
      @docker_tag = tag || tags.last
      manifest = get_manifest
      blobs = get_blobs(manifest)
      mash(manifest, blobs)
    end

    def diff
      # tags = get_most_recent_tags 
      pp "tags #{tags}"

      raise "only 1 tag for the image in the registry: #{tags.first}" if tags.size == 1
      @docker_tag = tags[1]

      # return get_most_recent_tags
      manifest = get_manifest
      blobs = get_blobs(manifest)
      # pp @blobs
      mashed = mash(manifest, blobs)
      pp mashed
      # pp mashed.keys
      pp "==================== "

      @docker_tag = tags[0]
      manifest = get_manifest
      blobs = get_blobs(manifest)
      mashed2 = mash(manifest, blobs)
      pp mashed2

      pp "==================== "

      # pp mashed2.keys
      pp mashed2 - mashed
    # rescue => e
    #   puts e
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

    def token
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

    def tags
      @tags ||= get_tags
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

    def mash(manifest, blobs)
      history = blobs["history"]
      layers = manifest["layers"]

      commands = history.map.with_index do |command, i|
        command["fake_id"] = i
        if command["empty_layer"]
          command["size"] = 0
          command["fake_id"] = i
        else
          layer = layers.shift
          command["size"] = layer["size"]
          command["fake_id"] = layer["digest"]
        end
        command["created_by"] = command["created_by"].sub("/bin/sh -c #(nop)", "").sub("/bin/sh -c", "RUN").strip
        command["prefix"] = (command["created_by"] || "").split(" ").first

        command
      end
    end

  end
end

# Spyglass::Fetch.new.diff
