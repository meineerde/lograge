# This class mocks the log subscriber class for Rails 2
# This provides just enough functionality for Lograge
# to work but is not intended to be useful to anyone
# else.
class ActiveSupport::LogSubscriber
  cattr_accessor :logger
end