# coding: utf-8
# Copyright (c) 2017-present, BigCommerce Pty. Ltd. All rights reserved
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
# Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
require 'socket'
require_relative 'formatters/base'
require_relative 'formatters/logstash'
require_relative 'formatters/plain'

module Gruf
  module Instrumentation
    module RequestLogging
      ##
      # Represents an error if the formatter does not extend the base formatter
      #
      class InvalidFormatterError < StandardError; end

      ##
      # Handles Rails-style request logging for gruf services.
      #
      # This is added by default to gruf servers; if you have `Gruf.use_default_hooks = false`, you can add it back
      # manually by doing:
      #
      #   Gruf::Instrumentation::Registry.add(:request_logging, Gruf::Instrumentation::RequestLogging::Hook)
      #
      class Hook < ::Gruf::Instrumentation::Base

        ###
        # Log the request, sending it to the appropriate formatter
        #
        # @param [Gruf::Instrumentation::RequestContext] rc The current request context for the call
        # @return [String]
        #
        def call(rc)
          if rc.success?
            type = :info
            status_name = 'GRPC::Ok'
          else
            type = :error
            status_name = rc.response_class_name
          end

          payload = {}
          payload[:params] = sanitize(rc.request.to_h) if options.fetch(:log_parameters, false)
          payload[:message] = message(rc)
          payload[:service] = service_key
          payload[:method] = rc.call_signature
          payload[:action] = rc.call_signature
          payload[:grpc_status] = status_name
          payload[:duration] = rc.execution_time_rounded
          payload[:status] = status(rc.response, rc.success?)
          payload[:thread_id] = Thread.current.object_id
          payload[:time] = Time.now.to_s
          payload[:host] = Socket.gethostname

          ::Gruf.logger.send(type, formatter.format(payload))
        end

        private

        ##
        # Return an appropriate log message dependent on the status
        #
        # @param [RequestContext] rc The current request context
        # @return [String] The appropriate message body
        #
        def message(rc)
          if rc.success?
            "[GRPC::Ok] (#{service_key}.#{rc.call_signature})"
          else
            "[#{rc.response_class_name}] (#{service_key}.#{rc.call_signature}) #{rc.response.message}"
          end
        end

        ##
        # Return the proper status code for the response
        #
        # @param [Object] response The response object
        # @param [Boolean] successful If the response was successful
        # @return [Boolean] The proper status code
        #
        def status(response, successful)
          successful ? GRPC::Core::StatusCodes::OK : response.code
        end

        ##
        # Determine the appropriate formatter for the request logging
        #
        # @return [Gruf::Instrumentation::RequestLogging::Formatters::Base]
        #
        def formatter
          unless @formatter
            fmt = options.fetch(:formatter, :plain)
            @formatter = case fmt
              when Symbol
                klass = "Gruf::Instrumentation::RequestLogging::Formatters::#{fmt.to_s.capitalize}"
                fmt = klass.constantize.new
              when Class
                fmt = fmt.new
              else
                fmt
            end
            raise Gruf::Instrumentation::RequestLogging::InvalidFormatterError unless fmt.is_a?(Gruf::Instrumentation::RequestLogging::Formatters::Base)
          end
          @formatter
        end

        ##
        # Redact any blacklisted params and return an updated hash
        #
        # @param [Hash] params The hash of parameters to sanitize
        # @return [Hash] The sanitized params in hash form
        #
        def sanitize(params = {})
          blacklists = options.fetch(:blacklist, []).map(&:to_s)
          redacted_string = options.fetch(:redacted_string, 'REDACTED')
          blacklists.each do |blacklist|
            parts = blacklist.split('.').map(&:to_sym)
            redact!(parts, 0, params, redacted_string)
          end
          params
        end

        ##
        # Fetch the options for this hook
        #
        # @return [Hash] Return a hash of options for this hook
        #
        def options
          super().fetch(:request_logging, {})
        end

        ##
        # Helper method to recursively redact based on the black list
        #
        # @param [Array] parts The blacklist. ex. 'data.schema' -> [:data, :schema]
        # @param [Integer] idx The current index of the blacklist
        # @param [Hash] params The hash of parameters to sanitize
        # @param [String] redacted_string The custom redact string
        #
        def redact!(parts = [], idx = 0, params = {}, redacted_string = 'REDACTED')
          return unless parts.is_a?(Array) && params.is_a?(Hash)
          return if idx >= parts.size || !params.key?(parts[idx])
          if idx == parts.size - 1
            if params[parts[idx]].is_a? Hash
              hash_deep_redact!(params[parts[idx]], redacted_string)
            else
              params[parts[idx]] = redacted_string
            end
            return
          end
          redact!(parts, idx + 1, params[parts[idx]], redacted_string)
        end

        ##
        # Helper method to recursively redact the value of all hash keys
        #
        # @param [Hash] hash Part of the hash of parameters to sanitize
        # @param [String] redacted_string The custom redact string
        #
        def hash_deep_redact!(hash, redacted_string)
          hash.keys.each do |key|
            if hash[key].is_a? Hash
              hash_deep_redact!(hash[key], redacted_string)
            else
              hash[key] = redacted_string
            end
          end
        end
      end
    end
  end
end
