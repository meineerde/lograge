require 'lograge/version'
require 'lograge/log_subscriber'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/string/inflections'
require 'active_support/ordered_options'

module Lograge
  mattr_accessor :logger

  # Custom options that will be appended to log line
  #
  # Currently supported formats are:
  #  - Hash
  #  - Any object that responds to call and returns a hash
  #
  mattr_writer :custom_options
  self.custom_options = nil

  def self.custom_options(event)
    if @@custom_options.respond_to?(:call)
      @@custom_options.call(event)
    else
      @@custom_options
    end
  end

  # The emitted log format
  #
  # Currently supported formats are>
  #  - :lograge - The custom tense lograge format
  #  - :logstash - JSON formatted as a Logstash Event.
  mattr_accessor :log_format
  self.log_format = :lograge

  def self.remove_existing_log_subscriptions
    ActiveSupport::LogSubscriber.log_subscribers.each do |subscriber|
      case subscriber
      when ActionView::LogSubscriber
        unsubscribe(:action_view, subscriber)
      when ActionController::LogSubscriber
        unsubscribe(:action_controller, subscriber)
      end
    end
  end

  def self.unsubscribe(component, subscriber)
    events = subscriber.public_methods(false).reject{ |method| method.to_s == 'call' }
    events.each do |event|
      ActiveSupport::Notifications.notifier.listeners_for("#{event}.#{component}").each do |listener|
        if listener.instance_variable_get('@delegate') == subscriber
          ActiveSupport::Notifications.unsubscribe listener
        end
      end
    end
  end

  def self.setup(app)
    if ::ActionPack::VERSION::MAJOR >= 3
      app.config.action_dispatch.rack_cache[:verbose] = false if app.config.action_dispatch.rack_cache
      require 'lograge/rails_ext/rack/logger'
      Lograge.remove_existing_log_subscriptions
      Lograge::RequestLogSubscriber.attach_to :action_controller
      Lograge.custom_options = app.config.lograge.custom_options
      Lograge.log_format = app.config.lograge.log_format || :lograge
    else
      require 'lograge/rails_ext/action_controller/lograge'
      require 'action_controller/base'
      ActionController::Base.class_eval do
        include ActionController::Lograge
      end

      Lograge.custom_options = Rails.configuration.lograge.custom_options
      Lograge.log_format = Rails.configuration.lograge.log_format || :lograge

      # force the logger to be only set on the mocked LogSubscriber
      ActiveSupport::LogSubscriber.logger = ActionController::Base.logger

      # Nobody else should spew their logs
      Object.send(:remove_const, :RAILS_DEFAULT_LOGGER) if Object.const_defined?(:RAILS_DEFAULT_LOGGER)
      Object.const_set(:RAILS_DEFAULT_LOGGER, nil)

      ActionController::Base.logger = nil
      ActiveSupport::Cache::Store.logger = nil
      # ActiveRecord::Base.logger = nil if defined?(ActiveRecord)
      ActiveResource::Base.logger = nil if defined?(ActiveResource)

      if ActiveSupport::LogSubscriber.logger && ActiveSupport::LogSubscriber.logger.respond_to?(:flush)
        ActionController::Dispatcher.after_dispatch do
          ActiveSupport::LogSubscriber.logger.flush
        end
      end
    end

    case Lograge.log_format.to_s
    when "logstash"
      begin
        # MRI 1.8 doesn't set the RUBY_ENGINE constant required by logstash
        Object.const_set(:RUBY_ENGINE, "ruby") unless Object.const_defined?(:RUBY_ENGINE)
        require "logstash-event"
      rescue LoadError
        puts "You need to install the logstash-event gem to use the logstash output."
        raise
      end
    end
  end
end

if defined?(Rails)
  if Rails::VERSION::MAJOR >= 3
    require 'lograge/railtie'
  else
    # In Rails 2.x, Lograge must be setup by hand in an initializer
    # Thus can be done similar to:
    #
    #  require 'lograge'
    #  Rails.configuration.lograge.log_format = :logstash
    #  Lograge.setup(nil)

    Rails::Configuration.class_eval do
      def lograge
        @lograge ||= Rails::OrderedOptions.new
      end
    end
  end
end
