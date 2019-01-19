
require 'date'
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

      begin
        @docker_client.token
      rescue => e
        pp "Error authenticating with Docker Registry: #{docker_client.docker_registry}"
        # pp e
        raise e
      end

      @docker_client

      raise "No tags found" if tags.empty?
    end

    def view(tag = nil)
      tag = tag || get_most_recent_tags(1).last
      pp "==================== fetching tag: #{tag}"
      manifest = docker_client.get_manifest(tag)
      blobs = docker_client.get_blobs(manifest)
      layers = mash(manifest, blobs)
      image_size = layers.inject(0) {|sum, command| command["size"] + sum }

      max = layers.max_by { |layer| layer["size"] }["size"]

      {
        tag: tag,
        created: layers.last["created"],
        layers: layers,
        max: max,
        image_size: image_size,
        image_human_size: number_to_human_size(image_size)
      }
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

    def compare(tag1 = tags[1], tag2 = tags[0], include_details = false)
      pp "==================== compare"
      mashed1 = view(tag1)
      image1_size = mashed1[:image_size]

      mashed2 = view(tag2)
      image2_size = mashed2[:image_size]

      layers1 = mashed1[:layers]
      layers2 = mashed2[:layers]

      diff = layers2.dup - layers1.dup
      diff_size = diff.inject(0) {|sum, command| command["size"] + sum }

      result = {
        tag1: tag1,
        tag2: tag2,
        tag1_created: mashed1[:created],
        tag2_created: mashed2[:created],
        image1_human_size: mashed1[:image_human_size],
        image1_size: mashed1[:image_size],
        image2_size: mashed2[:image_size],
        gain: mashed2[:image_size] - mashed1[:image_size],
        diff_size: diff_size,
        percent_reuse: (100 - (diff_size.to_f / image2_size) * 100).round(1)
      }
      if include_details
        shared = layers1 - diff
        result.merge!(
          image1: layers1,
          image2: layers2,
          diff1: layers1 - layers2,
          diff2: layers2 - layers1,
          shared: layers1 - (layers1 - layers2),
          max: [mashed1[:max], mashed2[:max]].max
        )
      end

      pp result
      result
    end

    def score(tag1, tag2)
      score = Cache.get("score-#{docker_client.docker_image}-#{tag1}-#{tag2}") do
        compare = compare(tag1, tag2)
        compare
      end
    end

    def trend
      get_most_recent_tags(5).each_cons(2).map do |e|
        tag1, tag2 = e[0], e[1]
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
        command["human_size"] = number_to_human_size(command["size"])
        command["created_by"] = command["created_by"].sub("/bin/sh -c #(nop)", "").sub("/bin/sh -c", "RUN").strip
        command["prefix"] = (command["created_by"] || "").split(" ").first.upcase

        command
      end

      commands
    end

    def number_to_human_size(size)
      if size < 1024
        "#{size}B"
      elsif size < 1024.0 * 1024.0
        "%.01fKB" % (size / 1024.0)
      elsif size < 1024.0 * 1024.0 * 1024.0
        "%.01fMB" % (size / 1024.0 / 1024.0)
      else
        "%.01fGB" % (size / 1024.0 / 1024.0 / 1024.0)
      end
    end

    def get_most_recent_tags(size = 3)
      tag_map = tags.map do |tag|
        timestamp = Cache.get("timestamp-#{docker_client.docker_image}-#{tag}") do
          docker_client.get_tag_timestamp(tag)
        end

        [tag, timestamp]
      end.to_h

      tag_map.sort_by {|k,v| v}.reverse.map { |x| x.first }.take(size)
    end

  end
end

# pp Spyglass::Fetch.new.tags
# pp Spyglass::Fetch.new.get_most_recent_tags
# # Spyglass::Fetch.new.trend
# # Spyglass::Fetch.new.score("2018.10.05-21.18.04-e02cc68", "2ded8dfe31f4307d65b9f6568cd405ec-e02cc68")
# Spyglass::Fetch.new.compare("d480128", "bffc975", true)

