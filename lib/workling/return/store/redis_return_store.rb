require 'workling/return/store/base'
require 'workling/clients/redis_queue_client'

#
#  Recommended Return Store if you are using the Redis Runner. This
#  Simply sets and gets values against queues. 'key' is the name of the respective Queue. 
#
module Workling
  module Return
    module Store
      class RedisReturnStore < Base
        cattr_accessor :client
        
        def initialize
          self.client = Workling::Clients::RedisQueueClient.new
          self.client.connect
        end
        
        # set a value in the queue 'key'. 
        def set(key, value)
          self.class.client.set(key, value)
        end
        
        # get a value from starling queue 'key'.
        def get(key)
          self.class.client.get(key)
        end
      end
    end
  end
end