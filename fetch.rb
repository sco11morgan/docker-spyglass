
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
      pp "==================== fetching tag: #{tag}"
      manifest = docker_client.get_manifest(tag || tags.last)
      blobs = docker_client.get_blobs(manifest)
      mash(manifest, blobs)
    end

    def diff
      # tags = get_most_recent_tags 
      pp "tags #{tags}"

      raise "only 1 tag for the image in the registry: #{tags.first}" if tags.size == 1

      mashed = view(tags[1])
      # pp mashed
      # pp mashed.keys

      mashed2 = view(tags[0])
      # pp mashed2
      # pp mashed2.keys
      pp "==================== comparing #{tags[1]} to #{tags[0]}"
      raise "same image" if mashed2.last["created"] ==  mashed.last["created"]
      pp mashed2 - mashed
    # rescue => e
    #   puts e
    end

    def score(tag1 = tags[1], tag2 = tags[0])
      pp tags
      mashed = view(tag1)
      image1_size = mashed.inject(0) {|sum, command| command["size"] + sum }
      # pp mashed
      # pp mashed.keys

      mashed2 = view(tag2)
      image2_size = mashed2.inject(0) {|sum, command| command["size"] + sum }

      diff = mashed2 - mashed
      diff_size = diff.inject(0) {|sum, command| command["size"] + sum }

      result = {
        image1_size: image1_size,
        image2_size: image2_size,
        gain: image2_size - image1_size,
        diff_size: diff_size,
        percent_reuse: (100 - (diff_size.to_f / image2_size) * 100)
      }

      pp result
      result
    end

    def tags
      @tags ||= docker_client.get_tags.reverse
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
 # Spyglass::Fetch.new.score("2018.10.08-17.15.39-73b3b46", "2018.10.08-18.44.21-0dc52a4")
 Spyglass::Fetch.new.score
# Spyglass::Fetch.new.view("latest")
# pp Spyglass::Fetch.new.view("latest")
