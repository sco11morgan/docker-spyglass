module Spyglass
  class Cache

    def self.redis
      Redis.current
    end

    def self.get(key, &block)
      if value = redis.get(key)
        value
      else
        if block_given?
          redis.set(key, yield(block))
        end
      end
    end  
  end
end