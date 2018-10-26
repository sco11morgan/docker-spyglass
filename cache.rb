module Spyglass
  class Cache

    def self.redis
      @@redis ||= {}
    end

    def self.get(key, &block)
      if redis.key?(key)
        redis[key]
      else
        if block_given?
          redis[key] = yield(block)
        end
      end
    end  
  end
end