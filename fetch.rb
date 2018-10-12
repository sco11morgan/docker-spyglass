
require 'date'
require 'net/http'
require 'net/https'
require 'json'
require 'pp'
require_relative 'cache'
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
      mashed = view(tag1)
      image1_size = mashed.inject(0) {|sum, command| command["size"] + sum }

      mashed2 = view(tag2)
      image2_size = mashed2.inject(0) {|sum, command| command["size"] + sum }

      diff = mashed2 - mashed
      # pp diff
      diff_size = diff.inject(0) {|sum, command| command["size"] + sum }

      result = {
        tag1: tag1,
        tag2: tag2,
        image1_size: image1_size,
        image2_size: image2_size,
        gain: image2_size - image1_size,
        diff_size: diff_size,
        percent_reuse: (100 - (diff_size.to_f / image2_size) * 100)
      }

      pp result
      result
    end

    def trend
      get_most_recent_tags(5).each_cons(2) do |tag1, tag2|
        score(tag1, tag2)
      end
      # tags.first(5).each_cons(2) do |tag1, tag2|
      #   score(tag1, tag2)
      # end
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

    def get_most_recent_tags(size = 3)
      tag_map = tags.map do |tag|
        timestamp = Cache.get("timestamp-#{tag}") do
          docker_client.get_tag_timestamp(tag)
        end

        [tag, timestamp]
      end.to_h

      tag_map.sort_by {|k,v| v}.reverse.map { |x| x.first }.take(size)
    end

  end
end
 # Spyglass::Fetch.new.score("2018.10.08-17.15.39-73b3b46", "2018.10.08-18.44.21-0dc52a4")
 # Spyglass::Fetch.new.score
 pp Spyglass::Fetch.new.tags
 pp Spyglass::Fetch.new.get_most_recent_tags
  Spyglass::Fetch.new.trend
   # Spyglass::Fetch.new.score("87d864ff718491bd67b65f3346d6007b-e02cc68", "2ded8dfe31f4307d65b9f6568cd405ec-e02cc68")

# Spyglass::Fetch.new.view("latest")
# pp Spyglass::Fetch.new.view("latest")
