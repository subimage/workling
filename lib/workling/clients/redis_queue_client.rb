require 'workling/clients/base'

# Workling client for REDIS, because Starling is a piece of garbage
# that falls over about once a month and eats up all my ram in the process.
module Workling
  module Clients
    class RedisQueueClient < Workling::Clients::Base
      attr_accessor :connection
      
      #  the client attempts to connect to queueserver using the configuration options found in 
      #      Workling.config. this can be configured in config/workling.yml. 
      #  the initialization code will raise an exception if redis cannot connect 
      def connect
        @server_url = Workling.config[:listens_on].split(':')
        self.connection = Redis.new(:host => @server_url[0], :port => @server_url[1])
        raise_unless_connected!
      end

      def reset; connect; end
      
      def close
        self.connection.quit
      end

      # implements the client job request and retrieval 
      def request(key, value)
        self.connection.lpush(key, Marshal.dump(value))
      end
      
      # Marshals data in case we're setting hashes and things
      def set(key, value)
        self.connection.set(key, Marshal.dump(value))
      end
      
      # Act like MemCached and "pop" items from the key when accessed
      def get(key)
        value = self.connection.get(key)
        self.connection.del(key)
        value.nil? ? nil : Marshal.load(value)
      end
      
      # We have to do some Redis magic to get it to act like MemCached.
      #
      # Workling likes to store sets AND strings at the same location,
      # so we need to be aware what we're pulling out & access it the right way.
      def retrieve(key)
        begin
          key_type = self.connection.type(key)
          if key_type == 'list'
            value = self.connection.rpop(key)
            return value.nil? ? nil : Marshal.load(value)
          else key_type == 'string'
            return get(key)
          end
        rescue RuntimeError => e
          # failed to enqueue, raise a workling error so that it propagates upwards
          raise Workling::WorklingError.new("#{e.class.to_s} - #{e.message}")        
        end
      end
            
      private
        # make sure we can actually connect to queueserver on the given port
        def raise_unless_connected!
          begin 
            self.connection.keys
          rescue Errno::ECONNREFUSED
            raise Workling::QueueserverNotFoundError.new
          end
        end

    end
  end
end