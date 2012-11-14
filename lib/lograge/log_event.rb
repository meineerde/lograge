module Lograge
  class LogEvent < Hash
    def initialize(*args)
      super

      @payload = {}
      @duration = 0.0
    end

    attr_reader :payload
    attr_accessor :duration
  end
end