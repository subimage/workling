# -*- coding: utf-8 -*-
require 'stringio'
require 'thread'
require 'workling/remote/invokers/base'

#
#  A threaded polling Invoker. 
# 
#  TODO: refactor this to make use of the base class. 
# 
module Workling
  module Remote
    module Invokers
      class ThreadedPoller < Workling::Remote::Invokers::Base
        
        cattr_accessor :verify_database_connection, :sleep_time, :reset_time
        
        class DummyMutex
          def synchronize
            yield
          end
        end
        
        class WorkerStatus
          attr_reader :thread
          attr_reader :clazz
          
          def initialize(thread, clazz)
            @mutex = Mutex.new
            @thread = thread
            @clazz = clazz
          end
          
          def log_string
            Workling::Base.logger.peek(@thread)
          end
          
          def worker_name
            "#{@clazz.name} #{@thread.object_id.to_s(16)}"
          end
        end
      
        def initialize(routing, client_class)
          super
          
          ThreadedPoller.verify_database_connection =
            fetch_bool_config(Workling.config, :verify_database_connection, true)
          ThreadedPoller.sleep_time = Workling.config[:sleep_time] || 2
          ThreadedPoller.reset_time = Workling.config[:reset_time] || 30
          
          @workers = ThreadGroup.new
          if active_record_is_thread_safe?
            @mutex = DummyMutex.new
          else
            @mutex = Mutex.new
          end
        end      
          
        def listen                
          # Allow concurrency for our tasks
          if !active_record_is_thread_safe?
            ActiveRecord::Base.allow_concurrency = true
          end

          # Create threads for each worker.
          total_threads = 0
          Workling::Discovery.discovered.each do |clazz|
            nthreads = 1
            if Workling.config[:listeners] && (config = Workling.config[:listeners][clazz.to_s])
              config = config.symbolize_keys
              nthreads = config[:threads] if config.has_key?(:threads)
            end
            
            logger.debug("Discovered listener #{clazz}; spawning #{nthreads} thread(s)")
            total_threads += nthreads
            nthreads.times do
              thread = Thread.new(clazz) do |c|
                Thread.current[:status] = WorkerStatus.new(Thread.current, clazz)
                clazz_listen(c)
              end
              @workers.add(thread)
            end
          end
          
          @total_threads = total_threads
          
          # Wait for all workers to complete
          @workers.list.each do |t|
            begin
              t.join
            rescue
              # Ignore exceptions, the thread already logs them.
            end
          end

          logger.debug("Reaped listener threads. ")
        
        ensure
          # Clean up all the connections.
          @total_threads = nil
          ActiveRecord::Base.verify_active_connections!
          logger.debug("Cleaned up connection: out!")
        end
      
        # Check if all Worker threads have been started. 
        def started?
          logger.debug("checking if started... list size is #{ worker_threads }")
          @total_threads == worker_threads && @workers.list.all? { |w| w[:status] }
        end
        
        # number of worker threads running
        def worker_threads
          @workers.list.size
        end
      
        # Gracefully stop processing
        def stop
          logger.info("stopping threaded poller...")
          sleep 1 until started? # give it a chance to start up before shutting down. 
          logger.info("Giving Listener Threads a chance to shut down. This may take a while... ")
          @workers.list.each { |w| w[:shutdown] = true }
          logger.info("Listener threads were shut down.  ")
        end
        
        def status
          workers = @workers.list
          backtraces = gather_thread_backtraces(workers)
          
          result = "[#{Time.now}] Status report for Workling process #{Process.pid}\n"
          result << "#{workers.size} workers (there are supposed to be #{@total_threads.inspect})\n"
          workers.each_with_index do |thread, i|
            status = thread[:status]
            result << "\n"
            if status
              result << "### #{i + 1}. Worker thread #{status.worker_name}\n"
              
              result << "   Active log:\n"
              log_string = status.log_string.strip
              if log_string.empty?
                result << "      (empty; thread seems to be idle)\n"
              else
                result << indent(log_string, 6) << "\n"
              end
              
              result << "   Backtrace:\n"
              if (backtrace = backtraces[status.thread])
                str = indent(backtrace, 6)
                result << str
                result << "\n" if !str.end_with?("\n")
              else
                result << "      (not available; requires Ruby Enterprise Edition or Ruby >= 1.9.2)\n"
              end
            else
              result << "### #{i + 1}. Worker thread #{thread}\n"
            end
          end
          
          result << "\nEnd of status.\n"
          result
        end

        # Listen for one worker class
        def clazz_listen(clazz)
          status = Thread.current[:status]
          logger.debug("Listener thread #{status.worker_name} started")
          
          thread_verify_database_connection = self.class.verify_database_connection
          thread_sleep_time = self.class.sleep_time
          thread_reset_time = self.class.reset_time
           
          # Read thread configuration if available
          if Workling.config.has_key?(:listeners)
            if Workling.config[:listeners].has_key?(clazz.to_s)
              config = Workling.config[:listeners][clazz.to_s].symbolize_keys
              thread_verify_database_connection = config[:verify_database_connection] if config.has_key?(:verify_database_connection)
              thread_sleep_time = config[:sleep_time] if config.has_key?(:sleep_time)
              thread_reset_time = config[:reset_time] if config.has_key?(:reset_time)
            end
          end
                
          # Setup connection to client (one per thread)
          connection = @client_class.new
          connection.connect
          logger.info("** Starting client #{ connection.class } for #{clazz.name} queue")
     
          # Start dispatching those messages
          while (!Thread.current[:shutdown]) do
            begin
            
              if thread_verify_database_connection
                # Thanks for this Brent! 
                #
                #     ...Just a heads up, due to how rails’ MySQL adapter handles this  
                #     call ‘ActiveRecord::Base.connection.active?’, you’ll need 
                #     to wrap the code that checks for a connection in in a mutex.
                #
                #     ....I noticed this while working with a multi-core machine that 
                #     was spawning multiple workling threads. Some of my workling 
                #     threads would hit serious issues at this block of code without 
                #     the mutex.            
                #
                @mutex.synchronize do 
                  ActiveRecord::Base.connection.verify!  # Keep MySQL connection alive
                  unless ActiveRecord::Base.connection.active?
                    logger.fatal("Failed - Database not available!")
                  end
                end
              end

              # Dispatch and process the messages
              logger.autoflush!(false) do
                done = false
                while !done
                  n = dispatch!(connection, clazz, true)
                  done = n == 0 || Thread.current[:shutdown]
                  if n > 0
                    logger.debug("Listener thread #{clazz.name} processed #{n.to_s} queue items")
                    logger.flush
                  end
                end
              end

              sleep(thread_sleep_time)
            
              # If there is a memcache error, hang for a bit to give it a chance to fire up again
              # and reset the connection.
              rescue Workling::WorklingConnectionError
                logger.warn("Listener thread #{clazz.name} failed to connect. Resetting connection.")
                sleep(thread_reset_time)
                connection.reset
            end
          end
        
          logger.debug("Listener thread #{clazz.name} ended")
        rescue Exception => e
          STDERR.puts("*** Error in client thread #{clazz.name} " +
            "#{Thread.current.object_id.to_s(16)}: " +
            "#{e}\n" +
            e.backtrace.join("\n"))
          raise e
        ensure
          release_active_record_connection
        end
      
        # Dispatcher for one worker class. Will throw MemCacheError if unable to connect.
        # Returns the number of worker methods called
        def dispatch!(connection, clazz, print_newline = false)
          status = Thread.current[:status]
          if status
            worker_name = status.worker_name
          else
            worker_name = "?"
          end
          
          n = 0
          for queue in @routing.queue_names_routing_class(clazz)
            begin
              result = connection.retrieve(queue)
              if result
                n += 1
                handler = @routing[queue]
                method_name = @routing.method_name(queue)
                logger.debug("\n") if print_newline
                logger.debug("### Calling #{handler.class.to_s}\##{method_name}(#{result.inspect}) | " +
                  "pid=#{Process.pid} thread=#{worker_name}")
                t1 = Time.now
                handler.dispatch_to_worker_method(method_name, result)
                t2 = Time.now
                logger.debug(sprintf("Finished in %.1f msec", (t2 - t1) * 1000))
              end
            rescue MemCache::MemCacheError => e
              logger.error("FAILED to connect with queue #{ queue }: #{ e } }")
              raise e
            end
          end
        
          return n
        ensure
          release_active_record_connection
        end
        
        private
          def fetch_bool_config(hash, key, default = true)
            if hash.has_key?(key)
              hash[key]
            else
              default
            end
          end
          
          def gather_thread_backtraces(threads)
            if Kernel.respond_to?(:caller_for_all_threads)
              temp = caller_for_all_threads
              result = {}
              threads.each do |thread|
                result[thread] = temp[thread]
              end
            elsif Thread.current.respond_to?(:backtrace)
              result = {}
              threads.each do |thread|
                result[thread] = thread.backtrace
              end
            end
            result
          end
          
          def indent(string_or_array, level)
            indentation = " " * level
            if string_or_array.is_a?(String)
              lines = string_or_array.split("\n")
            else
              lines = string_or_array.dup
            end
            lines.map! do |line|
              indentation + line
            end
            lines.join("\n")
          end
          
          if ActiveRecord::VERSION::STRING >= '2.3.0'
            def active_record_is_thread_safe?
              true
            end
          else
            def active_record_is_thread_safe?
              false
            end
          end
          
          if ActiveRecord::Base.respond_to?(:clear_active_connections!)
            def release_active_record_connection
              ActiveRecord::Base.clear_active_connections!
            end
          else
            def release_active_record_connection
            end
          end
      end
    end
  end
end
