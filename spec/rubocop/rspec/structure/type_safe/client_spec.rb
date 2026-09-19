# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::Client do
  subject(:client) { described_class.new(api_key: "dummy", model: "jev-latest", timeout: 5) }

  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
  end

  context "when the response is successful" do
    it "returns the probability" do
      response = instance_double(Net::HTTPSuccess, body: '{"nouls":{"result":{"noul":0.73}}}')
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http).to receive(:request).and_return(response)

      probability = client.noul(state: "when the user is an admin", instructions: "does this describe a condition?")

      expect(probability).to eq(0.73)
    end
  end

  context "when the request times out" do
    it "raises TimeoutError" do
      allow(http).to receive(:request).and_raise(Net::OpenTimeout)

      expect { client.noul(state: "x", instructions: "y") }
        .to raise_error(described_class::TimeoutError)
    end
  end

  context "when the HTTP response is not a success" do
    it "raises RequestError" do
      response = instance_double(Net::HTTPServerError, code: "500", body: "boom")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(http).to receive(:request).and_return(response)

      expect { client.noul(state: "x", instructions: "y") }
        .to raise_error(described_class::RequestError, /500/)
    end
  end

  context "when the JSON body is malformed" do
    it "raises RequestError" do
      response = instance_double(Net::HTTPSuccess, body: "not json")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http).to receive(:request).and_return(response)

      expect { client.noul(state: "x", instructions: "y") }
        .to raise_error(described_class::RequestError)
    end
  end

  context "when the response is missing the expected field" do
    it "raises RequestError" do
      response = instance_double(Net::HTTPSuccess, body: "{}")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http).to receive(:request).and_return(response)

      expect { client.noul(state: "x", instructions: "y") }
        .to raise_error(described_class::RequestError, /missing/)
    end
  end
end
