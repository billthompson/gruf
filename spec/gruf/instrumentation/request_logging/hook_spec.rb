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
require 'spec_helper'

class FakeRequestLogFormatter; end
describe Gruf::Instrumentation::RequestLogging::Hook do
  let(:options) { { } }
  let(:service) { ThingService.new }
  let(:id) { rand(1..1000) }
  let(:request) { Rpc::GetThingRequest.new(id: id) }
  let(:response) { Rpc::GetThingResponse.new(id: id) }
  let(:execution_time) { rand(0.001..10.000).to_f }
  let(:call_signature) { :get_thing_without_intercept }
  let(:active_call) { Rpc::Test::Call.new }

  let(:hook) { described_class.new(service, request_logging: options) }
  let(:call) { hook.outer_around(call_signature, request, active_call) { true } }

  before do
    Gruf.configure do |c|
      c.instrumentation_options[:request_logging] = options
    end
  end

  describe '.call' do
    subject { call }

    context 'and the request was successful' do
      it 'should log the call properly as an INFO' do
        expect(Gruf.logger).to receive(:info).once
        subject
      end
    end

    context 'and the request was a failure' do
      let(:call) do
        hook.outer_around(call_signature, request, active_call) do |_cs, req, ac|
          service.fail!(req, ac, :not_found, :thing_not_found, 'thing not found')
        end
      end

      it 'should log the call properly as an ERROR' do
        expect(Gruf.logger).to receive(:error).once
        expect { subject }.to raise_error(GRPC::BadStatus) do |e|
          expect(e.details).to eq 'thing not found'
        end
      end
    end
  end

  describe '.sanitize' do
    let(:params) { { foo: 'bar', one: 'two', data: { hello: 'world', array: [] }, hello: { one: 'one', two: 'two' } } }
    subject { hook.send(:sanitize, params) }

    context 'vanilla' do
      it 'should return all params' do
        expect(subject).to eq params
      end
    end

    context 'with a blacklist' do
      let(:blacklist) { [:foo] }
      let(:options) { { blacklist: blacklist } }

      it 'should return all params that are not filtered by the blacklist' do
        expected = params.dup
        expected[:foo] = 'REDACTED'
        expect(subject).to eq expected
      end

      context 'with a custom redacted string' do
        let(:str) { 'goodbye' }
        let(:options) { { blacklist: blacklist, redacted_string: str } }

        it 'should return all params that are not filtered by the blacklist' do
          expected = params.dup
          expected[:foo] = str
          expect(subject).to eq expected
        end
      end

      context 'with nested blacklist' do
        let(:blacklist) { ['data.array', 'hello'] }
        let(:options) { { blacklist: blacklist } }

        it 'should support nested filtering' do
          expected = Marshal.load(Marshal.dump(params))
          expected[:data][:array] = 'REDACTED'
          expected[:hello].each do |key, _val|
            expected[:hello][key] = 'REDACTED'
          end
          expect(subject).to eq expected
        end
      end

      context 'when params is nil' do
        let(:params) { nil }
        it 'should return normally' do
          expect { subject }.to_not raise_error
        end
      end
    end
  end

  describe '.formatter' do
    subject { hook.send(:formatter) }

    context 'when the formatter is a symbol' do
      let(:options) { { formatter: :logstash } }

      context 'and exists' do
        it 'should return the formatter' do
          expect(subject).to be_a(Gruf::Instrumentation::RequestLogging::Formatters::Logstash)
        end
      end

      context 'and is invalid' do
        let(:options) { { formatter: :bar } }

        it 'should raise a NameError' do
          expect { subject }.to raise_error(NameError)
        end
      end
    end

    context 'when the formatter is a class' do
      let(:options) { { formatter: Gruf::Instrumentation::RequestLogging::Formatters::Logstash } }

      context 'and extends the base class' do
        it 'should return the formatter' do
          expect(subject).to be_a(Gruf::Instrumentation::RequestLogging::Formatters::Logstash)
        end
      end

      context 'and does not extend the base class' do
        let(:options) { { formatter: FakeRequestLogFormatter } }

        it 'should raise a InvalidFormatterError' do
          expect { subject }.to raise_error(Gruf::Instrumentation::RequestLogging::InvalidFormatterError)
        end
      end
    end

    context 'when the formatter is an instance' do
      let(:options) { { formatter: Gruf::Instrumentation::RequestLogging::Formatters::Logstash.new } }

      context 'and extends the base class' do
        it 'should return the formatter' do
          expect(subject).to be_a(Gruf::Instrumentation::RequestLogging::Formatters::Logstash)
        end
      end

      context 'and does not extend the base class' do
        let(:options) { { formatter: FakeRequestLogFormatter.new } }

        it 'should raise a InvalidFormatterError' do
          expect { subject }.to raise_error(Gruf::Instrumentation::RequestLogging::InvalidFormatterError)
        end
      end
    end
  end
end
