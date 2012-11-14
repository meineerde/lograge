require 'lograge/log_event'

# THIS IS FOR RAILS 2.x COMPATIBILITY ONLY
#
# This module, when included into ActionController::Base
# makes sure that no superfluous log entries are generated during request
# handling. Instead, only the configured Lograge output is generated

module ActionController::Lograge
  def self.included(base)
    base.extend(ClassMethods)

    base.class_eval do
      alias_method_chain :perform_action, :lograge
      alias_method_chain :render_without_benchmark, :lograge
      alias_method_chain :render, :lograge
    end
  end

  module ClassMethods
    def lograge_subscriber
      @@lograge_subscriber ||= ::Lograge::RequestLogSubscriber.new
    end
  end

  # This makes sure that ActionController::Benchmarking#render_with_benchmark
  # collects the metrics, even if no actual logger is configured (which it is
  # not). The method will not actually use the logger, it just checks if it is
  # there.
  # In the end, it calls render_without_benchmark
  protected
  def render_with_lograge(options = nil, extra_options = {}, &block)
    # Pretend there is a logger present.
    self.logger = true
    render_without_lograge(options, extra_options, &block)
  end


  # This methods removes the "mocked" logger set by render_with_lograge
  # and then finally calls the actual render_without_benchmark method
  # created by alias_method_chain in ActionController::Benchmarking
  protected
  def render_without_benchmark_with_lograge(options = nil, extra_options = {}, &block)
    self.logger = nil
    render_without_benchmark_without_lograge(options, extra_options, &block)
  end

  private
  def perform_action_with_lograge
    ms = [Benchmark.ms { perform_action_without_benchmark }, 0.01].max
    logging_view          = defined?(@view_runtime)
    logging_active_record = Object.const_defined?("ActiveRecord") && ActiveRecord::Base.connected?

    event = Lograge::LogEvent.new
    event.duration = ms
    event.payload[:view_runtime] = @view_runtime if logging_view    
    event.payload[:db_runtime] = active_record_runtime_for_lograge if logging_active_record

    parameters = respond_to?(:filter_parameters) ? filter_parameters(params) : params.dup
    event.payload[:format] = parameters["format"]
    event.payload[:params] = parameters.except(:controller, :action, :format, :_method)
    event.payload[:method] = request.method.to_s.upcase
    event.payload[:path] = (request.fullpath rescue "unknown")

    event.payload[:status] = response.status

    if false
      # TODO: Handle exceptions
      event.payload[:exception] = ""
      event.payload[:message] = ""
    end
    self.class.lograge_subscriber.process_action(event)
  end

  # Basically the same as ActionController::Benchmarking#active_record_runtime
  # but we return a float instead of a pre-formatted string.
  private
  def active_record_runtime_for_lograge
    db_runtime = ActiveRecord::Base.connection.reset_runtime
    db_runtime += @db_rt_before_render if @db_rt_before_render
    db_runtime += @db_rt_after_render if @db_rt_after_render
    db_runtime
  end
end
