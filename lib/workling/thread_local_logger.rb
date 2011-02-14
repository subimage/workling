require 'thread'
require 'stringio'
require 'logger'

module Workling
  # This logger buffers all data that is written to it into memory. Buffers are
  # seperated based on the thread that called the logger in order to avoid
  # messages from different threads interleaving each other. Messages are only
  # flushed when #flush is called or when autoflushing is enabled (the default).
  # This logger also makes it possible to peek into a thread's current buffer
  # using the #peek method; useful for debugging.
  class ThreadLocalLogger
    def initialize(underlying_logger)
      @mutex = Mutex.new
      @underlying_logger = underlying_logger
      @local_state = {}
      @level = Logger::DEBUG
      @formatter = nil
      @progname = nil
      @datetime_format = nil
    end
  
    [:<<, :add, :close, :debug, :error, :fatal, :format_message, :format_severity,
     :info, :log, :unknown, :warn].each do |method_name|
      line = __LINE__
      eval(%Q{
        def #{method_name}(*args, &block)
          @mutex.synchronize do
            state = local_state
            state.logger.send(:#{method_name}, *args, &block)
            state.flush(@underlying_logger) if state.autoflush
          end
        end
      }, binding, __FILE__, line + 1)
    end
    
    [:level, :formatter, :progname, :datetime_format].each do |attribute|
      line = __LINE__
      eval(%Q{
        def #{attribute}
          @#{attribute}
        end
        
        def #{attribute}=(value)
          @mutex.synchronize do
            @#{attribute} = value
            @local_state.each_value do |state|
              state.logger.#{attribute} = value
            end
          end
        end
      }, binding, __FILE__, line + 1)
    end
    
    def debug?
      @level <= Logger::DEBUG
    end
    
    def info?
      @level <= Logger::INFO
    end
    
    def warn?
      @level <= Logger::WARN
    end
    
    def error?
      @level <= Logger::ERROR
    end
    
    def fatal?
      @level <= Logger::FATAL
    end
    
    def unknown?
      @level <= Logger::UNKNOWN
    end
    
    def autoflush!(enabled = true)
      state = nil
      old_value = nil
      @mutex.synchronize do
        state = local_state
        old_value = state.autoflush
        state.autoflush = enabled
      end
      begin
        yield
      ensure
        @mutex.synchronize do
          state.autoflush = old_value
          state.flush(@underlying_logger) if old_value
        end
      end
    end
    
    def autoflush=(value)
      @mutex.synchronize do
        state = local_state
        state.autoflush = value
        state.flush(@underlying_logger) if value
      end
    end
  
    def autoflush?
      @mutex.synchronize do
        local_state.autoflush
      end
    end
  
    def peek(thread = Thread.current)
      @mutex.synchronize do
        local_state(thread).buffer.string.dup
      end
    end
  
    def flush
      @mutex.synchronize do
        local_state.flush(@underlying_logger)
      end
    end
  
    private
      class LocalState
        attr_reader :logger, :buffer
        attr_accessor :autoflush
      
        def initialize(level, formatter, progname, datetime_format)
          @buffer = StringIO.new
          @logger = Logger.new(@buffer)
          @logger.level = level
          @logger.formatter = formatter
          @logger.progname = progname
          @logger.datetime_format = datetime_format
          @autoflush = true
        end
      
        def clear
          data = @buffer.string.dup
          @buffer.seek(0)
          @buffer.truncate(0)
          data
        end
        
        def flush(underlying_logger)
          if underlying_logger.is_a?(ActiveSupport::BufferedLogger)
            underlying_logger.send(:buffer) << clear
            underlying_logger.flush
          else
            underlying_logger << clear
          end
        end
      end
    
      def local_state(thread = Thread.current)
        @local_state[thread] ||= LocalState.new(@level, @formatter, @progname, @datetime_format)
      end
  end
end
