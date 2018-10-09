
require 'date'
require 'net/http'
require 'net/https'
require 'json'
require 'pp'
require_relative 'docker_client'

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
    attr_reader :docker_client

    def initialize(args = {})
      @docker_client = DockerClient.new(args)

      raise "No tags found" if tags.empty?
    end

    def view(tag = nil)
      manifest = docker_client.get_manifest(tag || tags.last)
      blobs = docker_client.get_blobs(manifest)
      mash(manifest, blobs)
    end

    def diff
      # tags = get_most_recent_tags 
      pp "tags #{tags}"

      raise "only 1 tag for the image in the registry: #{tags.first}" if tags.size == 1

      # return get_most_recent_tags
      manifest = docker_client.get_manifest(tags[1])
      blobs = docker_client.get_blobs(manifest)
      # pp @blobs
      mashed = mash(manifest, blobs)
      pp mashed
      # pp mashed.keys
      pp "==================== "

      manifest = docker_client.get_manifest(tags[0])
      blobs = docker_client.get_blobs(manifest)
      mashed2 = mash(manifest, blobs)
      pp mashed2

      pp "==================== "

      # pp mashed2.keys
      pp mashed2 - mashed
    # rescue => e
    #   puts e
    end

    def tags
      @tags ||= docker_client.get_tags
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
# Spyglass::Fetch.new.view("latest")
pp Spyglass::Fetch.new.view("latest")
